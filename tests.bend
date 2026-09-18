# bend-http -- testes puros. Um caso que falha encerra com codigo diferente de
# zero. O teste de fio, que precisa de peer externo, fica em wire_test.py.
# Rode: bend tests.bend
import Base
import ./http.bend as Http

def check(name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("ok    " ++ name)
    case False{}:
      IO.die(Unit, 1, "FALHOU " ++ name)

# Leitores de campo, para o teste falar de um campo por vez.
def val(p: Map<&2, String> & String) -> String:
  match p:
    case Tuple{m, v}:
      v

def field.at(which: Nat, method: String, path: String, query: String,
  heads: Map<&2, String>, body: String, name: String) -> String:
  match which:
    case 0n:
      method
    case 1n:
      path
    case 2n:
      query
    case 3n:
      body
    case _:
      val(Map.get(String, "<sem cabecalho>", heads, name))


def field(r: Http.Req, which: Nat, name: String) -> String:
  match r:
    case Http.Req{method, path, query, heads, body, params}:
      field.at(which, method, path, query, heads, body, name)

def got(m: Maybe<&2, Http.Req>, which: Nat, name: String) -> String:
  match m:
    case None{}:
      "<nao parseou>"
    case Some{r}:
      field(r, which, name)

def get_raw() -> String:
  "GET /users/7?x=1 HTTP/1.1\r\nHost: localhost:8080\r\nAccept: */*\r\n\r\n"

# O corpo guarda \r\n no meio: quem cortar o corpo por linha perde isso.
def post_raw() -> String:
  "POST /users HTTP/1.1\r\nContent-Type: text/plain\r\n\r\nlinha1\r\nlinha2"

def test_parse() -> IO(Unit):
  do IO<Unit>:
    check("parse: metodo", String.eq(got(Http.parse(get_raw()), 0n, ""), "GET"))
    check("parse: caminho sem a query",
      String.eq(got(Http.parse(get_raw()), 1n, ""), "/users/7"))
    check("parse: query depois do ?",
      String.eq(got(Http.parse(get_raw()), 2n, ""), "x=1"))
    check("parse: cabecalho em minusculo, valor com : dentro",
      String.eq(got(Http.parse(get_raw()), 4n, "host"), "localhost:8080"))
    check("parse: cabecalho ausente cai no default",
      String.eq(got(Http.parse(get_raw()), 4n, "authorization"),
        "<sem cabecalho>"))
    check("parse: corpo vazio no GET",
      String.eq(got(Http.parse(get_raw()), 3n, ""), ""))
    check("parse: metodo do POST",
      String.eq(got(Http.parse(post_raw()), 0n, ""), "POST"))
    check("parse: corpo do POST preserva o \\r\\n de dentro",
      String.eq(got(Http.parse(post_raw()), 3n, ""), "linha1\r\nlinha2"))
    check("parse: lixo nao vira request",
      String.eq(got(Http.parse(""), 0n, ""), "<nao parseou>"))

def test_render() -> IO(Unit):
  do IO<Unit>:
    check("render: linha de status, content-length e corpo",
      String.eq(Http.render(Http.text(404, "nao achei")),
        "HTTP/1.1 404 Not Found\r\ncontent-length: 9\r\n"
        ++ "content-type: text/plain; charset=utf-8\r\n\r\nnao achei"))
    check("render: codigo fora da lista ainda sai valido",
      String.eq(Http.render(Http.Res{799, [], ""}),
        "HTTP/1.1 799 Status\r\ncontent-length: 0\r\n\r\n"))


# Router
# ------

def h_user(+r: Http.Req) -> IO(Http.Res):
  IO.pure(Http.Res, Http.text(200, "user " ++ Http.param(r, "id")))

def h_post(+r: Http.Req) -> IO(Http.Res):
  IO.pure(Http.Res, Http.text(201, "criou"))

def h_par(+r: Http.Req) -> IO(Http.Res):
  IO.pure(Http.Res, Http.text(200,
    Http.param(r, "a") ++ "/" ++ Http.param(r, "b")))

def routes() -> List<&1, Http.Route>:
  [Http.get("/users/:id", h_user), Http.post("/users", h_post),
    Http.get("/p/:a/:b", h_par)]

def body_of(res: Http.Res) -> String:
  match res:
    case Http.Res{+status, heads, body}:
      U32.show(status) ++ " " ++ body

def hit(m: Maybe<&2, Http.Req>) -> IO(Http.Res):
  match m:
    case None{}:
      IO.pure(Http.Res, Http.text(400, "request invalida"))
    case Some{r}:
      Http.route(routes(), r)

def check_route(name: String, raw: String, want: String) -> IO(Unit):
  do IO<Unit>:
    res : Http.Res <- hit(Http.parse(raw))
    check(name, String.eq(body_of(res), want))

def req_of(method: String, path: String) -> String:
  method ++ " " ++ path ++ " HTTP/1.1\r\nHost: x\r\n\r\n"

def test_router() -> IO(Unit):
  do IO<Unit>:
    check_route("router: parametro de rota chega no handler",
      req_of("GET", "/users/7"), "200 user 7")
    check_route("router: dois parametros na ordem certa",
      req_of("GET", "/p/um/dois"), "200 um/dois")
    check_route("router: POST nao cai na rota GET do mesmo caminho",
      req_of("POST", "/users/7"), "404 nao encontrado")
    check_route("router: POST casa a rota POST",
      req_of("POST", "/users"), "201 criou")
    check_route("router: caminho mais curto nao casa padrao mais longo",
      req_of("GET", "/users"), "404 nao encontrado")
    check_route("router: caminho mais longo nao casa padrao mais curto",
      req_of("GET", "/users/7/x"), "404 nao encontrado")
    check_route("router: query nao entra no casamento de rota",
      req_of("GET", "/users/7?a=1"), "200 user 7")
    check_route("router: rota inexistente sai 404",
      req_of("GET", "/nada"), "404 nao encontrado")

def main() -> IO(Unit):
  do IO<Unit>:
    test_parse()
    test_render()
    test_router()
