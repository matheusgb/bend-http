# bend-http -- o loop do servidor.
#
# Uma conexao por processo leve (IO.spawn). Cada uma le ate a request estar
# inteira, roteia, responde e fecha. Sem keep-alive na v1.
import Base
import ./raw.bend as Raw
import ./http.bend as Http

# Leitura
# -------

def read.done(ok: Bool, sock: Socket, all: String,
  rest: Socket -> String -> IO(Socket & String)) -> IO(Socket & String):
  match ok:
    case True{}:
      IO.pure(Socket & String, (sock, all))
    case False{}:
      rest(sock)(all)

# Parte vazia quer dizer que o outro lado fechou: para com o que tem.
def read.step(eof: Bool, +acc: String, +part: String, sock: Socket,
  rest: Socket -> String -> IO(Socket & String)) -> IO(Socket & String):
  match eof:
    case True{}:
      IO.pure(Socket & String, (sock, acc))
    case False{}:
      read.done(Http.complete(acc ++ part), sock, acc ++ part, rest)

# Erro de leitura nao derruba o servidor: responde com o que ja chegou.
def read.res(acc: String, sock: Socket,
  res: Result<&1, &1, U32 & String, String>,
  rest: Socket -> String -> IO(Socket & String)) -> IO(Socket & String):
  match res:
    case Fail{(code, msg)}:
      IO.pure(Socket & String, (sock, acc))
    case Done{+part}:
      read.step(String.is_empty(part), acc, part, sock, rest)

def read.got(acc: String, got: Socket & Result<&1, &1, U32 & String, String>,
  rest: Socket -> String -> IO(Socket & String)) -> IO(Socket & String):
  match got:
    case Tuple{sock, res}:
      read.res(acc, sock, res, rest)

# O fuel limita quantas leituras uma conexao pode pedir: cliente que abre e
# nao termina a request nao prende o processo para sempre.
def read(fuel: Nat, sock: Socket, acc: String) -> IO(Socket & String):
  match fuel:
    case 0n:
      IO.pure(Socket & String, (sock, acc))
    case 1n++f:
      IO.bind(Socket & Result<&1, &1, U32 & String, String>, Socket & String,
        Raw.recv(sock, 65536),
        got => read.got(acc, got, s => a => read(f, s, a)))

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

def conn.req(rs: List<&1, Http.Route>, got: Socket & String) -> IO(Unit):
  match got:
    case Tuple{sock, raw}:
      conn.parse(rs, sock, Http.parse(raw))

def conn(rs: List<&1, Http.Route>, sock: Socket) -> IO(Unit):
  do IO<Unit>:
    got : Socket & String <- read(1024n, sock, "")
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
