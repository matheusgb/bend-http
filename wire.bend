# bend-http -- eco de bytes para o teste de fio (wire_test.py).
#
# Conecta, le 256 bytes e devolve os mesmos 256 bytes. Quem checa e o peer em
# Python, que nao fala Bend: ele compara o byte que saiu com o byte que voltou.
# Este arquivo existe porque um teste Bend contra Bend nao prova nada aqui: a
# ida e volta por UTF-8 tambem e reversivel entre dois Bend.
import Base
import ./raw.bend as Raw

# ponytail: uma leitura so. 256 bytes em loopback chegam juntos. O acumulador
# de leitura parcial nasce no parser HTTP, que precisa dele de verdade.
def echo.sent(sent: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match sent:
    case Tuple{sock, res}:
      do IO<Unit>:
        Unit <- IO.pass(Unit, res)
        Socket.close(sock)

def echo.res(sock: Socket, res: Result<&1, &1, U32 & String, String>) ->
  IO(Unit):
  match res:
    case Fail{(code, msg)}:
      IO.die(Unit, code, msg)
    case Done{data}:
      do IO<Unit>:
        sent : Socket & Result<&1, &1, U32 & String, Unit> <-
          Raw.send(sock, data)
        echo.sent(sent)

def echo.got(got: Socket & Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match got:
    case Tuple{sock, res}:
      echo.res(sock, res)

def main() -> IO(Unit):
  do IO<Unit>:
    sock : Socket <- IO.try(Socket, TCP.connect("127.0.0.1", 18080))
    got : Socket & Result<&1, &1, U32 & String, String> <- Raw.recv(sock, 4096)
    echo.got(got)
