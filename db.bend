# bend-http -- conexao com o Postgres: login SCRAM-SHA-256 e query simples.
#
# O protocolo puro (enquadramento, base64, linha) esta em pg.bend. Aqui fica o
# que fala com o socket. Sem TLS: rode o Postgres na rede interna, ou ponha um
# proxy TLS na frente.
import Base
import ./raw.bend as Raw
import ./crypto.bend as Crypto
import ./pg.bend as Pg

type Conn is Type:
  Conn{sock: Socket, buf: String}

def Err() -> Type:
  U32 & String

def Table() -> Type:
  List<&2, List<&2, String>>

def Got() -> Type:
  Conn & Maybe<&2, Pg.Msg>

def Login() -> Type:
  Result<&1, &1, Err(), Conn>

def Fetch() -> Type:
  Conn & Result<&1, &1, Err(), Table()>

# Mandar e receber
# ----------------

def push.done(-A: Type, sent: Socket & Result<&1, &1, Err(), Unit>,
  rest: Socket -> IO(A)) -> IO(A):
  match sent:
    case Tuple{sock, res}:
      rest(sock)

def push(-A: Type, sock: Socket, data: String, rest: Socket -> IO(A)) -> IO(A):
  IO.bind(Socket & Result<&1, &1, Err(), Unit>, A, Raw.send(sock, data),
    s => push.done(A, s, rest))

def next.got(t: Pg.Taken, sock: Socket) -> IO(Got()):
  match t:
    case Pg.Taken{msg, rest}:
      IO.pure(Got(), (Conn{sock, rest}, Some{msg}))

# Parte vazia quer dizer que o Postgres fechou.
def next.eof(eof: Bool, +buf: String, +part: String, sock: Socket,
  rest: Socket -> String -> IO(Got())) -> IO(Got()):
  match eof:
    case True{}:
      IO.pure(Got(), (Conn{sock, buf}, None{}))
    case False{}:
      rest(sock)(buf ++ part)

def next.part(buf: String, sock: Socket, res: Result<&1, &1, Err(), String>,
  rest: Socket -> String -> IO(Got())) -> IO(Got()):
  match res:
    case Fail{(code, m)}:
      IO.pure(Got(), (Conn{sock, buf}, None{}))
    case Done{+part}:
      next.eof(String.is_empty(part), buf, part, sock, rest)

def next.more(buf: String, got: Socket & Result<&1, &1, Err(), String>,
  rest: Socket -> String -> IO(Got())) -> IO(Got()):
  match got:
    case Tuple{sock, res}:
      next.part(buf, sock, res, rest)

def next.have(m: Maybe<&2, Pg.Taken>, sock: Socket, buf: String,
  rest: Socket -> String -> IO(Got())) -> IO(Got()):
  match m:
    case Some{t}:
      next.got(t, sock)
    case None{}:
      IO.bind(Socket & Result<&1, &1, Err(), String>, Got(),
        Raw.recv(sock, 65536), g => next.more(buf, g, rest))

# Uma mensagem inteira, lendo do socket o quanto precisar.
def next(fuel: Nat, sock: Socket, +buf: String) -> IO(Got()):
  match fuel:
    case 0n:
      IO.pure(Got(), (Conn{sock, buf}, None{}))
    case 1n++f:
      next.have(Pg.take(buf), sock, buf, s => b => next(f, s, b))

# Login
# -----

def fail.shut(-A: Type, code: U32, msg: String, conn: Conn) ->
  IO(Result<&1, &1, Err(), A>):
  match conn:
    case Conn{sock, buf}:
      IO.bind(Unit, Result<&1, &1, Err(), A>, Socket.close(sock),
        u => IO.pure(Result<&1, &1, Err(), A>, Fail{(code, msg)}))

def conn.go(conn: Conn, cfirst: String,
  rest: Socket -> String -> String -> IO(Login())) -> IO(Login()):
  match conn:
    case Conn{sock, buf}:
      rest(sock)(buf)(cfirst)

# SCRAM, primeiro passo: n,, mais o nonce do cliente.
def sasl.first(conn: Conn, +bare: String,
  rest: Socket -> String -> String -> IO(Login())) -> IO(Login()):
  match conn:
    case Conn{sock, buf}:
      push(Login(), sock,
        Pg.frame('p', Pg.cstr("SCRAM-SHA-256")
          ++ Pg.u32be(U32.add(U32.from_nat(String.length(bare)), 3))
          ++ "n,," ++ bare),
        s => rest(s)(buf)(bare))

def sasl.start(conn: Conn, raw: String,
  rest: Socket -> String -> String -> IO(Login())) -> IO(Login()):
  sasl.first(conn, "n=,r=" ++ Pg.b64.enc(raw), rest)

# SCRAM, segundo passo: a prova, que e ClientKey xor HMAC(StoredKey, mensagem).
def sasl.send(conn: Conn, final: String,
  rest: Socket -> String -> String -> IO(Login())) -> IO(Login()):
  match conn:
    case Conn{sock, buf}:
      push(Login(), sock, Pg.frame('p', final), s => rest(s)(buf)(""))

def sasl.proof(conn: Conn, +cfinal: String, ckey: String, csig: String,
  rest: Socket -> String -> String -> IO(Login())) -> IO(Login()):
  sasl.send(conn, cfinal ++ ",p=" ++ Pg.b64.enc(Pg.xor(ckey, csig)), rest)

def sasl.keys(conn: Conn, +cfirst: String, +sfirst: String, +pass: String,
  rest: Socket -> String -> String -> IO(Login())) -> IO(Login()):
  do IO<Login()>:
    salted : String <- Crypto.pbkdf2(pass,
      Pg.b64.dec(Pg.field(String.split(sfirst, ','), "s=")),
      Pg.iters.at(U32.read(Pg.field(String.split(sfirst, ','), "i="))))
    +ckey : String <- Crypto.hmac256(salted, "Client Key")
    skey : String <- Crypto.sha256(ckey)
    csig : String <- Crypto.hmac256(skey,
      cfirst ++ "," ++ sfirst ++ ",c=biws,r="
        ++ Pg.field(String.split(sfirst, ','), "r="))
    sasl.proof(conn,
      "c=biws,r=" ++ Pg.field(String.split(sfirst, ','), "r="), ckey, csig,
      rest)

# Qual autenticacao o Postgres pediu.
def auth.pick(ok: Bool, sasl: Bool, cont: Bool, conn: Conn, body: String,
  +pass: String, +cfirst: String,
  rest: Socket -> String -> String -> IO(Login())) -> IO(Login()):
  match ok sasl cont:
    case True{} _ _:
      conn.go(conn, cfirst, rest)
    case False{} True{} _:
      IO.bind(String, Login(), Crypto.nonce(18),
        raw => sasl.start(conn, raw, rest))
    case False{} False{} True{}:
      sasl.keys(conn, cfirst, String.drop(body, 4n), pass, rest)
    case False{} False{} False{}:
      conn.go(conn, cfirst, rest)

def auth.at(+code: U32, conn: Conn, +body: String, +pass: String,
  +cfirst: String, rest: Socket -> String -> String -> IO(Login())) ->
  IO(Login()):
  auth.pick(U32.is_eq(code, 0), U32.is_eq(code, 10), U32.is_eq(code, 11),
    conn, body, pass, cfirst, rest)

def auth.no(supported: Bool, +code: U32, conn: Conn, body: String,
  +pass: String, +cfirst: String,
  rest: Socket -> String -> String -> IO(Login())) -> IO(Login()):
  match supported:
    case True{}:
      auth.at(code, conn, body, pass, cfirst, rest)
    case False{}:
      fail.shut(Conn, 1,
        "o Postgres pediu autenticacao que a v1 nao faz, codigo "
          ++ U32.show(code), conn)

# 0 e ok, 10 abre o SCRAM, 11 continua, 12 fecha. Md5 e senha em texto ficam
# de fora de proposito: quem usa esta biblioteca usa SCRAM.
def auth.body(conn: Conn, +body: String, +pass: String, +cfirst: String,
  rest: Socket -> String -> String -> IO(Login())) -> IO(Login()):
  auth.no(Bool.or(Bool.or(U32.is_eq(Pg.be32(body), 0),
    U32.is_eq(Pg.be32(body), 10)),
    Bool.or(U32.is_eq(Pg.be32(body), 11), U32.is_eq(Pg.be32(body), 12))),
    Pg.be32(body), conn, body, pass, cfirst, rest)

def login.pick(ready: Bool, err: Bool, auth: Bool, conn: Conn, +body: String,
  +pass: String, +cfirst: String,
  rest: Socket -> String -> String -> IO(Login())) -> IO(Login()):
  match ready err auth:
    case True{} _ _:
      IO.pure(Login(), Done{conn})
    case False{} True{} _:
      fail.shut(Conn, 1, Pg.errtext(body), conn)
    case False{} False{} True{}:
      auth.body(conn, body, pass, cfirst, rest)
    case False{} False{} False{}:
      conn.go(conn, cfirst, rest)

def login.tag(conn: Conn, msg: Pg.Msg, +pass: String, +cfirst: String,
  rest: Socket -> String -> String -> IO(Login())) -> IO(Login()):
  match msg:
    case Pg.Msg{+tag, body}:
      login.pick(Char.is_eq(tag, 'Z'), Char.is_eq(tag, 'E'),
        Char.is_eq(tag, 'R'), conn, body, pass, cfirst, rest)

def login.on(conn: Conn, m: Maybe<&2, Pg.Msg>, +pass: String, +cfirst: String,
  rest: Socket -> String -> String -> IO(Login())) -> IO(Login()):
  match m:
    case None{}:
      fail.shut(Conn, 1, "o Postgres fechou a conexao durante o login", conn)
    case Some{msg}:
      login.tag(conn, msg, pass, cfirst, rest)

def login.msg(r: Got(), +pass: String, +cfirst: String,
  rest: Socket -> String -> String -> IO(Login())) -> IO(Login()):
  match r:
    case Tuple{conn, m}:
      login.on(conn, m, pass, cfirst, rest)

# Cada volta le uma mensagem do servidor ate chegar o ReadyForQuery.
def login(fuel: Nat, sock: Socket, buf: String, +pass: String,
  +cfirst: String) -> IO(Login()):
  match fuel:
    case 0n:
      fail.shut(Conn, 1, "o Postgres nao terminou o login", Conn{sock, buf})
    case 1n++f:
      IO.bind(Got(), Login(), next(4096n, sock, buf),
        r => login.msg(r, pass, cfirst,
          s => b => cf => login(f, s, b, pass, cf)))

def connect.go(sock: Socket, +user: String, +pass: String, +db: String) ->
  IO(Login()):
  push(Login(), sock, Pg.startup(user, db), s => login(64n, s, "", pass, ""))

def connect.at(r: Result<&1, &1, Err(), Socket>, +user: String, +pass: String,
  +db: String) -> IO(Login()):
  match r:
    case Fail{(code, m)}:
      IO.pure(Login(), Fail{(code, m)})
    case Done{sock}:
      connect.go(sock, user, pass, db)

def connect(host: String, port: U32, +user: String, +pass: String,
  +db: String) -> IO(Login()):
  IO.bind(Result<&1, &1, Err(), Socket>, Login(), TCP.connect(host, port),
    r => connect.at(r, user, pass, db))

# Query
# -----

def rows.go(conn: Conn, acc: List<&2, List<&2, String>>,
  rest: Socket -> String -> List<&2, List<&2, String>> -> IO(Fetch())) ->
  IO(Fetch()):
  match conn:
    case Conn{sock, buf}:
      rest(sock)(buf)(acc)

def rows.kept(r: Fetch(), msg: String) -> IO(Fetch()):
  match r:
    case Tuple{conn, old}:
      IO.pure(Fetch(), (conn, Fail{(1, msg)}))

# Erro no meio do resultado: le ate o ReadyForQuery, senao a proxima query le
# a sobra desta.
def rows.err(conn: Conn, msg: String, acc: List<&2, List<&2, String>>,
  rest: Socket -> String -> List<&2, List<&2, String>> -> IO(Fetch())) ->
  IO(Fetch()):
  match conn:
    case Conn{sock, buf}:
      IO.bind(Fetch(), Fetch(), rest(sock)(buf)(acc),
        r => rows.kept(r, msg))

def rows.pick(ready: Bool, err: Bool, data: Bool, conn: Conn, +body: String,
  acc: List<&2, List<&2, String>>,
  rest: Socket -> String -> List<&2, List<&2, String>> -> IO(Fetch())) ->
  IO(Fetch()):
  match ready err data:
    case True{} _ _:
      IO.pure(Fetch(), (conn, Done{List.reverse(&2, List<&2, String>, acc)}))
    case False{} True{} _:
      rows.err(conn, Pg.errtext(body), acc,
        rest)
    case False{} False{} True{}:
      rows.go(conn, Pg.row(body) <> acc, rest)
    case False{} False{} False{}:
      rows.go(conn, acc, rest)

def rows.tag(conn: Conn, msg: Pg.Msg, acc: List<&2, List<&2, String>>,
  rest: Socket -> String -> List<&2, List<&2, String>> -> IO(Fetch())) ->
  IO(Fetch()):
  match msg:
    case Pg.Msg{+tag, body}:
      rows.pick(Char.is_eq(tag, 'Z'), Char.is_eq(tag, 'E'),
        Char.is_eq(tag, 'D'), conn, body, acc, rest)

def rows.on(conn: Conn, m: Maybe<&2, Pg.Msg>, acc: List<&2, List<&2, String>>,
  rest: Socket -> String -> List<&2, List<&2, String>> -> IO(Fetch())) ->
  IO(Fetch()):
  match m:
    case None{}:
      IO.pure(Fetch(), (conn, Fail{(1, "o Postgres fechou no meio da query")}))
    case Some{msg}:
      rows.tag(conn, msg, acc, rest)

def rows.msg(r: Got(), acc: List<&2, List<&2, String>>,
  rest: Socket -> String -> List<&2, List<&2, String>> -> IO(Fetch())) ->
  IO(Fetch()):
  match r:
    case Tuple{conn, m}:
      rows.on(conn, m, acc, rest)

def rows(fuel: Nat, sock: Socket, buf: String,
  acc: List<&2, List<&2, String>>) -> IO(Fetch()):
  match fuel:
    case 0n:
      IO.pure(Fetch(),
        (Conn{sock, buf}, Fail{(1, "resultado sem fim: fuel acabou")}))
    case 1n++f:
      IO.bind(Got(), Fetch(), next(4096n, sock, buf),
        r => rows.msg(r, acc, s => b => a => rows(f, s, b, a)))

def query.go(sock: Socket, buf: String, sql: String) -> IO(Fetch()):
  push(Fetch(), sock, Pg.query(sql), s => rows(65536n, s, buf, Nil{}))

# Protocolo simples: uma query por vez, resultado em texto.
def query(conn: Conn, sql: String) -> IO(Fetch()):
  match conn:
    case Conn{sock, buf}:
      query.go(sock, buf, sql)

def close(conn: Conn) -> IO(Unit):
  match conn:
    case Conn{sock, buf}:
      Socket.close(sock)
