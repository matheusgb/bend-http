# bend-http -- cliente Postgres, protocolo v3.
#
# A String aqui e sequencia de byte, um char por byte, do jeito que raw.bend
# poe no fio. Toda mensagem do protocolo tem tag de 1 byte, tamanho de 4 bytes
# big endian (contando os proprios 4) e corpo. A mensagem de startup e a unica
# sem tag.
import Base

type Msg is Data:
  Msg{tag: Char, body: String}

type Taken is Data:
  Taken{msg: Msg, rest: String}

# Bytes e inteiros
# ----------------

def byte_at(x: U32, sh: Nat) -> Char:
  Chr{U32.and(U32.shrn(x, sh), 255)}

def u32be(+x: U32) -> String:
  SCon{byte_at(x, 24n),
    SCon{byte_at(x, 16n), SCon{byte_at(x, 8n), SCon{byte_at(x, 0n), SNil{}}}}}

def be32.go(s: String, acc: U32) -> U32:
  match s:
    case SNil{}:
      acc
    case SCon{c, t}:
      be32.go(t, U32.or(U32.shln(acc, 8n), Char.to_u32(c)))

def be32(s: String) -> U32:
  be32.go(String.take(s, 4n), 0)

# Texto terminado em zero, como o protocolo pede.
def cstr(s: String) -> String:
  s ++ SCon{Chr{0}, SNil{}}

# Monta mensagem
# --------------

# O tamanho conta os 4 bytes do proprio tamanho, e nao conta a tag.
def frame(tag: Char, +body: String) -> String:
  SCon{tag, u32be(U32.add(U32.from_nat(String.length(body)), 4))}
    ++ body

def startup.pack(+body: String) -> String:
  u32be(U32.add(U32.from_nat(String.length(body)), 4)) ++ body


# Startup nao tem tag: tamanho, versao 3.0 e os pares chave/valor.
def startup(user: String, db: String) -> String:
  startup.pack(u32be(196608) ++ cstr("user") ++ cstr(user)
    ++ cstr("database") ++ cstr(db) ++ SCon{Chr{0}, SNil{}})

def query(sql: String) -> String:
  frame('Q', cstr(sql))

# Le mensagem
# -----------

# Uma mensagem inteira, se ela couber no que ja chegou. Devolve tambem o que
# sobrou, porque uma leitura traz varias mensagens.
def take.cut(+want: Nat, +buf: String, tag: Char) -> Maybe<&2, Taken>:
  Some{Taken{Msg{tag, String.take(String.drop(buf, 5n), Nat.sub(want, 5n))},
    String.drop(buf, want)}}

def take.at(fits: Bool, want: Nat, buf: String, tag: Char) ->
  Maybe<&2, Taken>:
  match fits:
    case True{}:
      take.cut(want, buf, tag)
    case False{}:
      None{}

# Tamanho declarado menor que 4 e mensagem quebrada, nao mensagem curta: os 4
# bytes do proprio tamanho ja nao caberiam. Nesse caso nao existe mensagem.
def take.ok(sane: Bool, +want: Nat, +buf: String, tag: Char) ->
  Maybe<&2, Taken>:
  match sane:
    case True{}:
      take.at(Nat.is_ge(String.length(buf), want), want, buf, tag)
    case False{}:
      None{}

def take.len(+buf: String, tag: Char) -> Maybe<&2, Taken>:
  take.ok(Nat.is_ge(Nat.add(U32.to_nat(be32(String.drop(buf, 1n))), 1n), 5n),
    Nat.add(U32.to_nat(be32(String.drop(buf, 1n))), 1n), buf, tag)

def take(buf: String) -> Maybe<&2, Taken>:
  match buf:
    case SNil{}:
      None{}
    case SCon{+tag, t}:
      take.len(SCon{tag, t}, tag)

# Base64
# ------
#
# O SCRAM carrega salt e prova em base64, entao a conversao precisa existir
# nos dois backends. Em Bend ela e pura e testavel; em efeito nativo, ela seria
# escrita duas vezes.

def b64.alpha() -> String:
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

def b64.at(m: Maybe<&2, Char>) -> Char:
  match m:
    case None{}:
      '='
    case Some{c}:
      c

def b64.chr(i: U32) -> Char:
  b64.at(String.get(b64.alpha(), U32.to_nat(i)))

def b64.six(+x: U32, sh: Nat) -> Char:
  b64.chr(U32.and(U32.shrn(x, sh), 63))

def b64.pack3(+x: U32) -> String:
  SCon{b64.six(x, 18n), SCon{b64.six(x, 12n),
    SCon{b64.six(x, 6n), SCon{b64.six(x, 0n), SNil{}}}}}

def b64.pack2(+x: U32) -> String:
  SCon{b64.six(x, 18n), SCon{b64.six(x, 12n),
    SCon{b64.six(x, 6n), SCon{'=', SNil{}}}}}

def b64.pack1(+x: U32) -> String:
  SCon{b64.six(x, 18n), SCon{b64.six(x, 12n), SCon{'=', SCon{'=', SNil{}}}}}

# Tres bytes viram quatro chars. Sobrando um ou dois bytes, o resto vira '='.
def b64.one(a: Char, b: Char, t2: String, rest: String -> String) -> String:
  match t2:
    case SNil{}:
      b64.pack2(U32.or(U32.shln(Char.to_u32(a), 16n),
        U32.shln(Char.to_u32(b), 8n)))
    case SCon{+c, t3}:
      b64.pack3(U32.or(U32.or(U32.shln(Char.to_u32(a), 16n),
        U32.shln(Char.to_u32(b), 8n)), Char.to_u32(c))) ++ rest(t3)

def b64.two(a: Char, t: String, rest: String -> String) -> String:
  match t:
    case SNil{}:
      b64.pack1(U32.shln(Char.to_u32(a), 16n))
    case SCon{+b, t2}:
      b64.one(a, b, t2, rest)

def b64.three(s: String, rest: String -> String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+a, t}:
      b64.two(a, t, rest)

# O fuel conta grupos de tres bytes. Ele so existe porque a recursao anda tres
# passos de uma vez, e o checador de terminacao exige um argumento que encolhe.
def b64.enc.go(fuel: Nat, s: String) -> String:
  match fuel:
    case 0n:
      SNil{}
    case 1n++f:
      b64.three(s, r => b64.enc.go(f, r))

def b64.enc(+s: String) -> String:
  b64.enc.go(Nat.add(String.length(s), 1n), s)

def b64.idx.at(hit: Bool, i: U32, rest: U32) -> U32:
  match hit:
    case True{}:
      i
    case False{}:
      rest


# Decodificacao: o indice do char no alfabeto, ou 0 para '=' e lixo.
def b64.idx.go(al: String, +c: Char, +i: U32) -> U32:
  match al:
    case SNil{}:
      0
    case SCon{+h, t}:
      b64.idx.at(Char.is_eq(h, c), i, b64.idx.go(t, c, U32.add(i, 1)))

def b64.idx(c: Char) -> U32:
  b64.idx.go(b64.alpha(), c, 0)

def b64.out(+x: U32, keep: Nat) -> String:
  match keep:
    case 0n:
      SNil{}
    case 1n:
      SCon{byte_at(x, 16n), SNil{}}
    case 2n:
      SCon{byte_at(x, 16n), SCon{byte_at(x, 8n), SNil{}}}
    case _:
      SCon{byte_at(x, 16n),
        SCon{byte_at(x, 8n), SCon{byte_at(x, 0n), SNil{}}}}

def b64.keep.at(c_pad: Bool, d_pad: Bool) -> Nat:
  match c_pad d_pad:
    case True{} _:
      1n
    case False{} True{}:
      2n
    case False{} False{}:
      3n


# Quantos bytes o grupo carrega: '=' no fim tira um byte cada.
def b64.keep(c: Char, d: Char) -> Nat:
  b64.keep.at(Char.is_eq(c, '='), Char.is_eq(d, '='))

def b64.quad(a: Char, b: Char, +c: Char, +d: Char, t: String,
  rest: String -> String) -> String:
  b64.out(U32.or(U32.or(U32.shln(b64.idx(a), 18n),
    U32.shln(b64.idx(b), 12n)),
    U32.or(U32.shln(b64.idx(c), 6n), b64.idx(d))),
    b64.keep(c, d)) ++ rest(t)

def b64.dec.4(a: Char, b: Char, +c: Char, s: String, rest: String -> String) ->
  String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+d, t}:
      b64.quad(a, b, c, d, t, rest)

def b64.dec.3(a: Char, b: Char, s: String, rest: String -> String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+c, t}:
      b64.dec.4(a, b, c, t, rest)

def b64.dec.2(a: Char, s: String, rest: String -> String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+b, t}:
      b64.dec.3(a, b, t, rest)

def b64.dec.1(s: String, rest: String -> String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+a, t}:
      b64.dec.2(a, t, rest)

def b64.dec.go(fuel: Nat, s: String) -> String:
  match fuel:
    case 0n:
      SNil{}
    case 1n++f:
      b64.dec.1(s, r => b64.dec.go(f, r))

# Grupo incompleto no fim vira nada: base64 quebrado nao vira byte inventado.
def b64.dec(+s: String) -> String:
  b64.dec.go(Nat.add(String.length(s), 1n), s)

# SCRAM e linhas de resultado
# ---------------------------

def be16(s: String) -> U32:
  be32.go(String.take(s, 2n), 0)

# XOR byte a byte, que e como o SCRAM fecha a prova do cliente.
def xor(a: String, b: String) -> String:
  match a b:
    case SNil{} _:
      SNil{}
    case SCon{x, xt} SNil{}:
      SNil{}
    case SCon{x, xt} SCon{y, yt}:
      SCon{Chr{U32.xor(Char.to_u32(x), Char.to_u32(y))}, xor(xt, yt)}

# O valor do campo que comeca com a chave, dentro de "r=...,s=...,i=...".
def field.at(hit: Bool, +item: String, +key: String, rest: String) -> String:
  match hit:
    case True{}:
      String.drop(item, String.length(key))
    case False{}:
      rest

def field(ls: List<&2, String>, +key: String) -> String:
  match ls:
    case Nil{}:
      ""
    case Con{+item, t}:
      field.at(String.starts_with(item, key), item, key, field(t, key))

def iters.at(m: Maybe<&2, U32>) -> U32:
  match m:
    case None{}:
      4096
    case Some{n}:
      n

# Uma coluna: 4 bytes de tamanho e o valor. Tamanho 0xFFFFFFFF e NULL, que a
# v1 entrega como texto vazio.
def col.cut(+want: Nat, +s: String,
  rest: String -> List<&2, String>) -> List<&2, String>:
  String.take(String.drop(s, 4n), want)
    <> rest(String.drop(s, Nat.add(4n, want)))

def col.at(is_null: Bool, +s: String,
  rest: String -> List<&2, String>) -> List<&2, String>:
  match is_null:
    case True{}:
      "" <> rest(String.drop(s, 4n))
    case False{}:
      col.cut(U32.to_nat(be32(s)), s, rest)

def cols.go(n: Nat, +s: String) -> List<&2, String>:
  match n:
    case 0n:
      Nil{}
    case 1n++p:
      col.at(U32.is_eq(be32(s), 4294967295), s, r => cols.go(p, r))

# Uma linha de resultado: 2 bytes com o numero de colunas, depois as colunas.
def row(+body: String) -> List<&2, String>:
  cols.go(U32.to_nat(be16(body)), String.drop(body, 2n))

# O texto do erro que o Postgres manda: campos com tag de 1 byte, terminados
# em zero. O campo M e a mensagem legivel.
def errtext.at(hit: Bool, +item: String, rest: String) -> String:
  match hit:
    case True{}:
      String.drop(item, 1n)
    case False{}:
      rest

def errtext.go(ls: List<&2, String>) -> String:
  match ls:
    case Nil{}:
      "erro do Postgres sem texto"
    case Con{+item, t}:
      errtext.at(String.starts_with(item, "M"), item, errtext.go(t))

def errtext(body: String) -> String:
  errtext.go(String.split(body, Chr{0}))

# Literal de SQL
# --------------
#
# A v1 nao tem prepared statement, entao a query vai montada em texto. Isso
# joga o risco de injecao para quem usa a biblioteca. lit fecha esse buraco
# para o caso comum: valor de texto dentro da query.
#
# A regra e a do Postgres com standard_conforming_strings ligado, que e o
# padrao desde a versao 9.1: dentro de aspas simples, a unica coisa que escapa
# e a propria aspa, dobrada. O byte zero sai fora, porque ele terminaria a
# query no meio: o protocolo manda o texto terminado em zero.

def lit.push(quote: Bool, +c: Char, acc: String) -> String:
  match quote:
    case True{}:
      SCon{c, SCon{c, acc}}
    case False{}:
      SCon{c, acc}

def lit.keep(nul: Bool, +c: Char, acc: String) -> String:
  match nul:
    case True{}:
      acc
    case False{}:
      lit.push(Char.is_eq(c, '\''), c, acc)

def lit.go(s: String, acc: String) -> String:
  match s:
    case SNil{}:
      String.reverse(acc)
    case SCon{+c, t}:
      lit.go(t, lit.keep(U32.is_eq(Char.to_u32(c), 0), c, acc))

def lit(s: String) -> String:
  "'" ++ lit.go(s, SNil{}) ++ "'"
