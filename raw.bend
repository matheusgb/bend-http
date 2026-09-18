# bend-http -- TCP byte a byte.
#
# O TCP da Base transporta texto: ele recodifica em UTF-8 na saida e decodifica
# na entrada, entao todo byte acima de 0x7F volta trocado por U+FFFD. Protocolo
# binario, como o do Postgres, morre assim. Aqui cada char de 0 a 255 e um byte,
# e a ida e volta preserva o byte.
import Base

def send(sock: Socket, data: String) ->
  IO(Socket & Result<&1, &1, U32 & String, Unit>):
  import "./effs/raw_send.js"

def recv(sock: Socket, max: U32) ->
  IO(Socket & Result<&1, &1, U32 & String, String>):
  import "./effs/raw_recv.js"
