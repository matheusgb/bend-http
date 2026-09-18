# bend-http -- request e response HTTP/1.1.
#
# O parser anda a String uma vez por corte. String em Bend e lista ligada, logo
# nao existe indice O(1): todo corte custa o tamanho do prefixo. Para cabecalho
# de request normal isso e barato.
import Base

type Req is Data:
  Req{method: String, path: String, query: String,
    headers: Map<&2, String>, body: String}

type Head is Data:
  Head{name: String, value: String}

type Res is Data:
  Res{status: U32, headers: List<&2, Head>, body: String}

# Corta no primeiro sep. Devolve o antes e o depois, sem o sep. Sem sep na
# string, o depois vem vazio.
def cut.push(h: Char, r: String & String) -> String & String:
  match r:
    case Tuple{a, b}:
      (SCon{h, a}, b)

def cut.at(hit: Bool, h: Char, t: String, rest: String & String) ->
  String & String:
  match hit:
    case True{}:
      (SNil{}, t)
    case False{}:
      cut.push(h, rest)

def cut(s: String, +sep: Char) -> String & String:
  match s:
    case SNil{}:
      (SNil{}, SNil{})
    case SCon{+h, +t}:
      cut.at(Char.is_eq(h, sep), h, t, cut(t, sep))

# Tira o \r que sobra no fim da linha, porque String.lines corta so no \n.
def uncr.at(hit: Bool, +s: String) -> String:
  match hit:
    case True{}:
      String.take(s, Nat.sub(String.length(s), 1n))
    case False{}:
      s

def uncr(+s: String) -> String:
  uncr.at(String.ends_with(s, "\r"), s)

# Uma linha de cabecalho vira par nome minusculo e valor sem espaco.
def head.pair(p: String & String) -> String & String:
  match p:
    case Tuple{name, value}:
      (String.to_lower(String.trim(name)), String.trim(value))

def head.put(m: Map<&2, String>, p: String & String) -> Map<&2, String>:
  match p:
    case Tuple{name, value}:
      Map.set(&2, String, m, name, value)

# Corta no primeiro \r\n\r\n: cabecalho antes, corpo depois, byte a byte.
def cut2.at(hit: Bool, h: Char, t: String, rest: String & String) ->
  String & String:
  match hit:
    case True{}:
      (SNil{}, String.drop(t, 3n))
    case False{}:
      cut.push(h, rest)

def cut2(s: String) -> String & String:
  match s:
    case SNil{}:
      (SNil{}, SNil{})
    case SCon{+h, +t}:
      cut2.at(String.starts_with(SCon{h, t}, "\r\n\r\n"), h, t,
        cut2(t))

# Le as linhas ate a linha vazia. O corpo nao passa por aqui.
def heads(ls: List<&2, String>, m: Map<&2, String>) -> Map<&2, String>:
  match ls:
    case Nil{}:
      m
    case Con{l, t}:
      heads(t, head.put(m, head.pair(cut(uncr(l),
        ':'))))

# O alvo da request: caminho antes do ?, query depois.
def target(method: String, p: String & String, m: Map<&2, String>,
  body: String) -> Maybe<&2, Req>:
  match p:
    case Tuple{path, query}:
      Some{Req{method, path, query, m, body}}

def line.target(method: String, rest: List<&2, String>,
  m: Map<&2, String>, body: String) -> Maybe<&2, Req>:
  match rest:
    case Nil{}:
      None{}
    case Con{tgt, _}:
      target(method, cut(tgt, '?'), m, body)


# A primeira linha: metodo, alvo e versao.
def line(parts: List<&2, String>, m: Map<&2, String>, body: String) ->
  Maybe<&2, Req>:
  match parts:
    case Nil{}:
      None{}
    case Con{method, rest}:
      line.target(method, rest, m, body)

# Cabecalho e corpo, separados pela linha vazia.
def parse.head(ls: List<&2, String>, body: String) -> Maybe<&2, Req>:
  match ls:
    case Nil{}:
      None{}
    case Con{first, rest}:
      line(String.split(uncr(first), ' '),
        heads(rest, Map.new(&2, String)), body)

def parse.split(p: String & String) -> Maybe<&2, Req>:
  match p:
    case Tuple{head, body}:
      parse.head(String.lines(head), body)

# A request inteira, do primeiro byte ao fim do corpo.
def parse(raw: String) -> Maybe<&2, Req>:
  parse.split(cut2(raw))

# Render
# ------

def pick(c: Bool, a: String, b: String) -> String:
  match c:
    case True{}:
      a
    case False{}:
      b

# So os codigos que esta biblioteca emite. Um codigo fora da lista sai como
# "Status", que e valido: o cliente le o numero, nao o texto.
def reason(+code: U32) -> String:
  pick(U32.is_eq(code, 200), "OK",
    pick(U32.is_eq(code, 201), "Created",
      pick(U32.is_eq(code, 204), "No Content",
        pick(U32.is_eq(code, 400), "Bad Request",
          pick(U32.is_eq(code, 404), "Not Found",
            pick(U32.is_eq(code, 405), "Method Not Allowed",
              pick(U32.is_eq(code, 500), "Internal Server Error",
                "Status")))))))

def head.line(h: Head) -> String:
  match h:
    case Head{name, value}:
      name ++ ": " ++ value ++ "\r\n"

def heads.render(hs: List<&2, Head>, acc: String) -> String:
  match hs:
    case Nil{}:
      acc
    case Con{h, t}:
      heads.render(t, acc ++ head.line(h))

# content-length sai sempre, calculado do corpo: e o que a v1 exige do cliente
# e o que ela promete de volta.
def render(res: Res) -> String:
  Res{+status, headers, +body} = res
  "HTTP/1.1 " ++ U32.show(status) ++ " " ++ reason(status) ++ "\r\n"
    ++ "content-length: " ++ Nat.show(String.length(body)) ++ "\r\n"
    ++ heads.render(headers, SNil{}) ++ "\r\n" ++ body

# Atalhos de resposta.
def text(code: U32, body: String) -> Res:
  Res{code, [Head{"content-type", "text/plain; charset=utf-8"}], body}

def json(code: U32, body: String) -> Res:
  Res{code, [Head{"content-type", "application/json"}], body}
