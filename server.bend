# bend-http -- o loop do servidor.
#
# Uma conexao por processo leve (IO.spawn). Cada uma le ate a request estar
# inteira, roteia, responde e fecha. Sem keep-alive na v1.
import Base
import ./raw.bend as Raw
import ./http.bend as Http

def Err() -> Type:
  U32 & String

# Leitura
# -------
#
# Os pedacos entram numa lista, e a String so e montada no fim: concatenar a
# cada pacote custaria o buffer inteiro por pacote, e um cliente que manda a
# request byte a byte viraria trabalho ao quadrado.

# Teto de cabecalho e de request inteira. Acima disso nao e request: e cliente
# enchendo a memoria do servidor. A resposta vira 400.
#
# ponytail: 8 KB de cabecalho porque String.lines da Base estoura a pilha da
# maquina perto de 50 KB, e 8 KB e o mesmo teto que nginx usa. Subir isso pede
# um String.lines com acumulador, nao um numero maior aqui.
def max.head() -> Nat:
  8192n

def max.total() -> Nat:
  1048576n

def joined(cs: List<&2, String>) -> String:
  String.concat(List.reverse(&2, String, cs))

def read.want(m: Maybe<&2, Nat>) -> Nat:
  match m:
    case None{}:
      0n
    case Some{n}:
      n

def read.known.at(hit: Bool, want: Nat, raw: String) -> Nat:
  match hit:
    case True{}:
      want
    case False{}:
      read.want(Http.need(raw))

# O tamanho total so e calculado uma vez: depois que o cabecalho fechou, cada
# pacote novo so soma no contador.
def read.known(+want: Nat, raw: String) -> Nat:
  read.known.at(Nat.is_gt(want, 0n), want, raw)

def read.stop(+want: Nat, +seen: Nat) -> Bool:
  Bool.or(Bool.and(Nat.is_gt(want, 0n), Nat.is_ge(seen, want)),
    Bool.or(Nat.is_gt(want, max.total()),
      Bool.or(Bool.and(Nat.is_eq(want, 0n), Nat.is_gt(seen, max.head())),
        Nat.is_gt(seen, max.total()))))

def read.done(stop: Bool, sock: Socket, cs: List<&2, String>, seen: Nat,
  want: Nat,
  rest: Socket -> List<&2, String> -> Nat -> Nat -> IO(Socket & String)) ->
  IO(Socket & String):
  match stop:
    case True{}:
      IO.pure(Socket & String, (sock, joined(cs)))
    case False{}:
      rest(sock)(cs)(seen)(want)

def read.grew(sock: Socket, +cs: List<&2, String>, +seen: Nat, +want: Nat,
  rest: Socket -> List<&2, String> -> Nat -> Nat -> IO(Socket & String)) ->
  IO(Socket & String):
  read.done(read.stop(want, seen), sock, cs, seen, want, rest)

# Pedaco vazio quer dizer que o outro lado fechou: para com o que tem.
def read.step(eof: Bool, +cs: List<&2, String>, +part: String, +seen: Nat,
  +want: Nat, sock: Socket,
  rest: Socket -> List<&2, String> -> Nat -> Nat -> IO(Socket & String)) ->
  IO(Socket & String):
  match eof:
    case True{}:
      IO.pure(Socket & String, (sock, joined(cs)))
    case False{}:
      read.grew(sock, part <> cs, Nat.add(seen, String.length(part)),
        read.known(want, joined(part <> cs)), rest)

# Erro de leitura nao derruba o servidor: responde com o que ja chegou.
def read.res(cs: List<&2, String>, seen: Nat, want: Nat, sock: Socket,
  res: Result<&1, &1, Err(), String>,
  rest: Socket -> List<&2, String> -> Nat -> Nat -> IO(Socket & String)) ->
  IO(Socket & String):
  match res:
    case Fail{(code, m)}:
      IO.pure(Socket & String, (sock, joined(cs)))
    case Done{+part}:
      read.step(String.is_empty(part), cs, part, seen, want, sock, rest)

def read.got(cs: List<&2, String>, seen: Nat, want: Nat,
  got: Socket & Result<&1, &1, Err(), String>,
  rest: Socket -> List<&2, String> -> Nat -> Nat -> IO(Socket & String)) ->
  IO(Socket & String):
  match got:
    case Tuple{sock, res}:
      read.res(cs, seen, want, sock, res, rest)

# O fuel limita quantas leituras uma conexao pode pedir: cliente que abre e
# nao termina a request nao prende o processo para sempre.
def read(fuel: Nat, sock: Socket, cs: List<&2, String>, seen: Nat,
  want: Nat) -> IO(Socket & String):
  match fuel:
    case 0n:
      IO.pure(Socket & String, (sock, joined(cs)))
    case 1n++f:
      IO.bind(Socket & Result<&1, &1, Err(), String>, Socket & String,
        Raw.recv(sock, 65536),
        got => read.got(cs, seen, want, got,
          s => c => sn => w => read(f, s, c, sn, w)))

# Conexao
# -------

# A resposta pode falhar (cliente sumiu); o socket fecha do mesmo jeito.
def conn.close(sent: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match sent:
    case Tuple{sock, res}:
      Socket.close(sock)

def conn.write(sock: Socket, out: String) -> IO(Unit):
  do IO<Unit>:
    sent : Socket & Result<&1, &1, U32 & String, Unit> <- Raw.send(sock, out)
    conn.close(sent)

def conn.parse(rs: List<&1, Http.Route>, sock: Socket,
  m: Maybe<&2, Http.Req>) -> IO(Unit):
  match m:
    case None{}:
      conn.write(sock, Http.render(Http.text(400, "request invalida")))
    case Some{req}:
      do IO<Unit>:
        res : Http.Res <- Http.route(rs, req)
        conn.write(sock, Http.render(res))

# A leitura para por teto, por fim de fuel ou porque o cliente sumiu. Nenhum
# desses casos e request: so o que chegou inteiro vale.
def conn.check(ok: Bool, rs: List<&1, Http.Route>, sock: Socket,
  raw: String) -> IO(Unit):
  match ok:
    case True{}:
      conn.parse(rs, sock, Http.parse(raw))
    case False{}:
      conn.write(sock, Http.render(Http.text(400, "request invalida")))

def conn.req(rs: List<&1, Http.Route>, got: Socket & String) -> IO(Unit):
  match got:
    case Tuple{sock, +raw}:
      conn.check(Http.complete(raw), rs, sock, raw)

def conn(rs: List<&1, Http.Route>, sock: Socket) -> IO(Unit):
  do IO<Unit>:
    got : Socket & String <- read(1024n, sock, Nil{}, 0n, 0n)
    conn.req(rs, got)

# Accept
# ------

def serve.spawn(~rs: List<&1, Http.Route>, lis: Listener,
  res: Result<&1, &1, U32 & String, Socket>, rest: Listener -> IO(Unit)) ->
  IO(Unit):
  match res:
    case Fail{(code, msg)}:
      rest(lis)
    case Done{sock}:
      do IO<Unit>:
        IO.spawn(Unit, conn(rs, sock))
        rest(lis)

def serve.accepted(~rs: List<&1, Http.Route>,
  seen: Listener & Result<&1, &1, U32 & String, Socket>,
  rest: Listener -> IO(Unit)) -> IO(Unit):
  match seen:
    case Tuple{lis, res}:
      serve.spawn(~rs, lis, res, rest)

# O fuel conta conexoes atendidas. 4294967295 e o teto de um U32: na pratica o
# servidor so para quando o processo para.
def serve.loop(~rs: List<&1, Http.Route>, fuel: Nat, lis: Listener) ->
  IO(Unit):
  match fuel:
    case 0n:
      Listener.close(lis)
    case 1n++f:
      IO.bind(Listener & Result<&1, &1, U32 & String, Socket>, Unit,
        TCP.accept(lis),
        seen => serve.accepted(~rs, seen, l => serve.loop(~rs, f, l)))

def listen(~rs: List<&1, Http.Route>, +port: U32) -> IO(Unit):
  do IO<Unit>:
    lis : Listener <- IO.try(Listener, TCP.listen(port))
    IO.print("bend-http ouvindo em http://127.0.0.1:" ++ U32.show(port))
    serve.loop(~rs, U32.to_nat(4294967295), lis)
