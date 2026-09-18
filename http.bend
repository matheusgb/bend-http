# bend-http -- request e response HTTP/1.1.
#
# O parser anda a String uma vez por corte. String em Bend e lista ligada, logo
# nao existe indice O(1): todo corte custa o tamanho do prefixo. Para cabecalho
# de request normal isso e barato.
import Base

type Req is Data:
  Req{method: String, path: String, query: String,
    headers: Map<&2, String>, body: String, params: Map<&2, String>}

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
# Acumulador de novo, e pelo mesmo motivo do brk: montar o prefixo na volta
# empilha um quadro por byte do corpo.
def cut2.step(hit: Bool, h: Char, t: String, +acc: String,
  rest: String -> String & String) -> String & String:
  match hit:
    case True{}:
      (String.reverse(acc), String.drop(t, 3n))
    case False{}:
      rest(SCon{h, acc})

def cut2.go(s: String, +acc: String) -> String & String:
  match s:
    case SNil{}:
      (String.reverse(acc), SNil{})
    case SCon{+h, +t}:
      cut2.step(String.starts_with(SCon{h, t}, "\r\n\r\n"), h, t, acc,
        a => cut2.go(t, a))

def cut2(s: String) -> String & String:
  cut2.go(s, SNil{})

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
      Some{Req{method, path, query, m, body, Map.new(&2, String)}}

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

# Contagem de cabecalho pelo nome, para recusar o que vem repetido.
def name.of(l: String) -> String:
  String.to_lower(String.trim(Pair.fst(String, String, cut(uncr(l), ':'))))

def count.at(hit: Bool, rest: Nat) -> Nat:
  match hit:
    case True{}:
      1n+rest
    case False{}:
      rest

def count(ls: List<&2, String>, +key: String) -> Nat:
  match ls:
    case Nil{}:
      0n
    case Con{l, t}:
      count.at(String.eq(name.of(l), key), count(t, key))

# Dois content-length com valores diferentes sao a porta de entrada do request
# smuggling: o proxy da frente acredita em um, e o servidor de tras no outro.
# transfer-encoding a v1 nao faz, e fingir que fez seria o mesmo buraco.
def suspect(+ls: List<&2, String>) -> Bool:
  Bool.or(Nat.is_gt(count(ls, "content-length"), 1n),
    Nat.is_gt(count(ls, "transfer-encoding"), 0n))

def parse.ok(bad: Bool, first: String, rest: List<&2, String>,
  body: String) -> Maybe<&2, Req>:
  match bad:
    case True{}:
      None{}
    case False{}:
      line(String.split(uncr(first), ' '), heads(rest, Map.new(&2, String)),
        body)

# Cabecalho e corpo, separados pela linha vazia.
def parse.head(ls: List<&2, String>, body: String) -> Maybe<&2, Req>:
  match ls:
    case Nil{}:
      None{}
    case Con{first, +rest}:
      parse.ok(suspect(rest), first, rest, body)

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

# Router
# ------

type Route is Type:
  Route{method: String, pattern: String, run: @+r: Req -> IO(Res)}

# Map.get devolve o mapa junto com o valor; aqui so o valor interessa.
def val(p: Map<&2, String> & String) -> String:
  match p:
    case Tuple{m, v}:
      v

def param(r: Req, name: String) -> String:
  match r:
    case Req{method, path, query, hs, body, params}:
      val(Map.get(String, "", params, name))

# Leitores, para o handler nao precisar abrir o Req na mao.
def body(r: Req) -> String:
  match r:
    case Req{method, path, query, hs, b, params}:
      b

def query(r: Req) -> String:
  match r:
    case Req{method, path, q, hs, b, params}:
      q

def header(r: Req, name: String) -> String:
  match r:
    case Req{method, path, query, hs, b, params}:
      val(Map.get(String, "", hs, name))

def with_params(r: Req, ps: Map<&2, String>) -> Req:
  match r:
    case Req{method, path, query, hs, b, old}:
      Req{method, path, query, hs, b, ps}

# Um segmento de padrao que comeca com : casa com qualquer coisa e guarda o
# valor. Qualquer outro segmento precisa ser igual.
def segs.keep(ok: Bool, r: Maybe<&2, Map<&2, String>>) ->
  Maybe<&2, Map<&2, String>>:
  match ok:
    case True{}:
      r
    case False{}:
      None{}

def segs.one(is_param: Bool, +p: String, s: String, ps: Map<&2, String>) ->
  Maybe<&2, Map<&2, String>>:
  match is_param:
    case True{}:
      Some{Map.set(&2, String, ps, String.drop(p, 1n), s)}
    case False{}:
      segs.keep(String.eq(p, s), Some{ps})

def segs.add(+p: String, s: String, r: Maybe<&2, Map<&2, String>>) ->
  Maybe<&2, Map<&2, String>>:
  match r:
    case None{}:
      None{}
    case Some{ps}:
      segs.one(String.starts_with(p, ":"), p, s, ps)

# Padrao e caminho casam segmento a segmento, e o numero de segmentos precisa
# bater: /users nao casa /users/7.
def segs(pats: List<&2, String>, ss: List<&2, String>, ps: Map<&2, String>) ->
  Maybe<&2, Map<&2, String>>:
  match pats ss:
    case Nil{} Nil{}:
      Some{ps}
    case Nil{} Con{s, st}:
      None{}
    case Con{p, pt} Nil{}:
      None{}
    case Con{p, pt} Con{s, st}:
      segs.add(p, s, segs(pt, st, ps))

def route.go(ps: Maybe<&2, Map<&2, String>>, run: @+r: Req -> IO(Res),
  req: Req,
  rest: IO(Res)) -> IO(Res):
  match ps:
    case None{}:
      rest
    case Some{p}:
      run(with_params(req, p))

def route.when(hit: Bool, ps: Maybe<&2, Map<&2, String>>,
  run: @+r: Req -> IO(Res), req: Req, rest: IO(Res)) -> IO(Res):
  match hit:
    case True{}:
      route.go(ps, run, req, rest)
    case False{}:
      rest

def route.try(r: Route, method: String, ss: List<&2, String>, req: Req,
  rest: IO(Res)) -> IO(Res):
  match r:
    case Route{m, pattern, run}:
      route.when(String.eq(m, method),
        segs(String.split(pattern, '/'), ss, Map.new(&2, String)), run, req,
        rest)

# A primeira rota que casa responde. Nenhuma casa, sai 404.
def route.pick(rs: List<&1, Route>, +method: String, +ss: List<&2, String>,
  +req: Req) -> IO(Res):
  match rs:
    case Nil{}:
      IO.pure(Res, text(404, "nao encontrado"))
    case Con{r, rt}:
      route.try(r, method, ss, req, route.pick(rt, method, ss, req))

def route(rs: List<&1, Route>, req: Req) -> IO(Res):
  match req:
    case Req{+method, +path, query, hs, b, params}:
      route.pick(rs, method, String.split(path, '/'),
        Req{method, path, query, hs, b, params})

def get(pattern: String, run: @+r: Req -> IO(Res)) -> Route:
  Route{"GET", pattern, run}

def post(pattern: String, run: @+r: Req -> IO(Res)) -> Route:
  Route{"POST", pattern, run}

# A request esta inteira?
# -----------------------

# Quem le do socket precisa saber quando parar. A regra da v1: separador de
# cabecalho presente e corpo com pelo menos content-length bytes.
def want_len.at(m: Maybe<&2, U32>) -> Nat:
  match m:
    case None{}:
      0n
    case Some{n}:
      U32.to_nat(n)


def want_len(h: Map<&2, String>) -> Nat:
  want_len.at(U32.read(val(Map.get(String, "0", h, "content-length"))))

def complete.len(r: Req) -> Bool:
  match r:
    case Req{method, path, query, hs, b, params}:
      Nat.is_ge(String.length(b), want_len(hs))

def complete.body(m: Maybe<&2, Req>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{r}:
      complete.len(r)

def complete.at(has_break: Bool, raw: String) -> Bool:
  match has_break:
    case False{}:
      False{}
    case True{}:
      complete.body(parse(raw))

def complete(+raw: String) -> Bool:
  complete.at(String.contains(raw, "\r\n\r\n"), raw)

# Onde termina o cabecalho, se ele ja chegou inteiro.
# Com acumulador, de proposito: a versao que soma na volta empilha um quadro
# por byte, e um cabecalho de 50 KB derruba o runtime.
def brk.step(hit: Bool, i: Nat, rest: Nat -> Maybe<&2, Nat>) ->
  Maybe<&2, Nat>:
  match hit:
    case True{}:
      Some{i}
    case False{}:
      rest(1n+i)

def brk.go(s: String, i: Nat) -> Maybe<&2, Nat>:
  match s:
    case SNil{}:
      None{}
    case SCon{+h, +t}:
      brk.step(String.starts_with(SCon{h, t}, "\r\n\r\n"), i,
        k => brk.go(t, k))

def brk(s: String) -> Maybe<&2, Nat>:
  brk.go(s, 0n)

# Cabecalho suspeito nao ganha corpo: quem le para no fim do cabecalho, e o
# parse recusa depois. Sem isso, dois content-length deixariam o servidor
# esperando para sempre o corpo que o outro valor prometeu.
def need.sane(bad: Bool, +i: Nat, ls: List<&2, String>) -> Maybe<&2, Nat>:
  match bad:
    case True{}:
      Some{Nat.add(i, 4n)}
    case False{}:
      Some{Nat.add(Nat.add(i, 4n),
        want_len(heads(ls, Map.new(&2, String))))}

def need.len(+i: Nat, +raw: String) -> Maybe<&2, Nat>:
  need.sane(suspect(String.lines(String.take(raw, i))), i,
    String.lines(String.take(raw, i)))

def need.at(m: Maybe<&2, Nat>, raw: String) -> Maybe<&2, Nat>:
  match m:
    case None{}:
      None{}
    case Some{i}:
      need.len(i, raw)

# Quantos bytes a request inteira tem. Enquanto o cabecalho nao fechou, nao da
# para saber, e quem le precisa dessa resposta para nao ficar relendo o buffer
# inteiro a cada pacote que chega.
def need(+raw: String) -> Maybe<&2, Nat>:
  need.at(brk(raw), raw)

# Campo de formulario e de query string
# -------------------------------------
#
# Os dois usam o mesmo formato: chave=valor separado por &, com espaco virando
# + e byte fora do ASCII virando %XX. form le um campo, no corpo ou na query.

def hex.val.at(digito: Bool, minus: Bool, maius: Bool, +c: U32) -> U32:
  match digito minus maius:
    case True{} _ _:
      U32.sub(c, 48)
    case False{} True{} _:
      U32.sub(c, 87)
    case False{} False{} True{}:
      U32.sub(c, 55)
    case False{} False{} False{}:
      0

def hex.val.go(+c: U32) -> U32:
  hex.val.at(Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57)),
    Bool.and(U32.is_ge(c, 97), U32.is_le(c, 102)),
    Bool.and(U32.is_ge(c, 65), U32.is_le(c, 70)), c)

def hex.val(c: Char) -> U32:
  hex.val.go(Char.to_u32(c))

def pct.byte(h1: Char, h2: Char) -> Char:
  Chr{U32.add(U32.mul(hex.val(h1), 16), hex.val(h2))}

# %XX sem os dois digitos e lixo: o que sobrou fica de fora.
def unpct.two(h1: Char, t1: String, acc: String,
  rest: String -> String -> String) -> String:
  match t1:
    case SNil{}:
      String.reverse(acc)
    case SCon{h2, t2}:
      rest(t2)(SCon{pct.byte(h1, h2), acc})

def unpct.one(t: String, acc: String, rest: String -> String -> String) ->
  String:
  match t:
    case SNil{}:
      String.reverse(acc)
    case SCon{h1, t1}:
      unpct.two(h1, t1, acc, rest)

def unpct.at(pct: Bool, plus: Bool, c: Char, t: String, acc: String,
  rest: String -> String -> String) -> String:
  match pct plus:
    case True{} _:
      unpct.one(t, acc, rest)
    case False{} True{}:
      rest(t)(SCon{' ', acc})
    case False{} False{}:
      rest(t)(SCon{c, acc})

def unpct.start(s: String, acc: String, rest: String -> String -> String) ->
  String:
  match s:
    case SNil{}:
      String.reverse(acc)
    case SCon{+c, +t}:
      unpct.at(Char.is_eq(c, '%'), Char.is_eq(c, '+'), c, t, acc, rest)

# O fuel existe porque %XX anda tres passos de uma vez, e o checador de
# terminacao pede um argumento que encolhe sozinho.
def unpct.go(fuel: Nat, s: String, acc: String) -> String:
  match fuel:
    case 0n:
      String.reverse(acc)
    case 1n++f:
      unpct.start(s, acc, u => a => unpct.go(f, u, a))

def unpct(+s: String) -> String:
  unpct.go(Nat.add(String.length(s), 1n), s, SNil{})

def form.at(hit: Bool, +item: String, +name: String, rest: String) -> String:
  match hit:
    case True{}:
      unpct(String.drop(item, Nat.add(String.length(name), 1n)))
    case False{}:
      rest

def form.one(ls: List<&2, String>, +name: String) -> String:
  match ls:
    case Nil{}:
      ""
    case Con{+item, t}:
      form.at(String.starts_with(item, name ++ "="), item, name,
        form.one(t, name))

# Campo ausente vira texto vazio: a v1 nao separa ausente de vazio.
def form(s: String, +name: String) -> String:
  form.one(String.split(s, '&'), name)
