# bend-http -- TCP byte a byte.
#
# O TCP da Base transporta texto: ele recodifica em UTF-8 na saida e decodifica
# na entrada, entao todo byte acima de 0x7F volta trocado por U+FFFD. Protocolo
# binario, como o do Postgres, morre assim. Aqui cada char de 0 a 255 e um byte,
# e a ida e volta preserva o byte.
import Base

def send(sock: Socket, data: String) ->
  IO(Socket & Result<&1, &1, U32 & String, Unit>):
  import "./effs/raw_send.c"
  import "./effs/raw_send.js"

def recv(sock: Socket, max: U32) ->
  IO(Socket & Result<&1, &1, U32 & String, String>):
  import "./effs/raw_recv.c"
  import "./effs/raw_recv.js"

# Texto para byte
# ---------------
#
# String em Bend e lista de codepoint, e no fio trafega byte. Para ASCII os
# dois coincidem, e para o resto nao: "cao" com til vira um codepoint 0xE3 que
# precisa sair como dois bytes. utf8 faz essa conversao. Toda String que sai
# desta biblioteca e byte; texto com acento passa por aqui antes.

def utf8.one(+c: U32) -> String:
  SCon{Chr{c}, SNil{}}

def utf8.two(+c: U32) -> String:
  SCon{Chr{U32.or(192, U32.shrn(c, 6n))},
    SCon{Chr{U32.or(128, U32.and(c, 63))}, SNil{}}}

def utf8.three(+c: U32) -> String:
  SCon{Chr{U32.or(224, U32.shrn(c, 12n))},
    SCon{Chr{U32.or(128, U32.and(U32.shrn(c, 6n), 63))},
      SCon{Chr{U32.or(128, U32.and(c, 63))}, SNil{}}}}

def utf8.four(+c: U32) -> String:
  SCon{Chr{U32.or(240, U32.shrn(c, 18n))},
    SCon{Chr{U32.or(128, U32.and(U32.shrn(c, 12n), 63))},
      SCon{Chr{U32.or(128, U32.and(U32.shrn(c, 6n), 63))},
        SCon{Chr{U32.or(128, U32.and(c, 63))}, SNil{}}}}}

def utf8.pick(one: Bool, two: Bool, three: Bool, +c: U32) -> String:
  match one two three:
    case True{} _ _:
      utf8.one(c)
    case False{} True{} _:
      utf8.two(c)
    case False{} False{} True{}:
      utf8.three(c)
    case False{} False{} False{}:
      utf8.four(c)

def utf8.chr(+c: U32) -> String:
  utf8.pick(U32.is_lt(c, 128), U32.is_lt(c, 2048), U32.is_lt(c, 65536), c)

def utf8(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{c, t}:
      utf8.chr(Char.to_u32(c)) ++ utf8(t)
