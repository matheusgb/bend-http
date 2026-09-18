# bend-http -- testes puros. Um caso que falha encerra com codigo diferente de
# zero. O teste de fio, que precisa de peer externo, fica em wire_test.py.
# Rode: bend tests.bend
import Base
import ./http.bend as Http
import ./pg.bend as Pg
import ./crypto.bend as Crypto

def check(name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("ok    " ++ name)
    case False{}:
      IO.die(Unit, 1, "FALHOU " ++ name)

# Os bytes 0, 1, ... n-1, nessa ordem.
def bytes(n: Nat, acc: String) -> String:
  match n:
    case 0n:
      acc
    case 1n++p:
      bytes(p, SCon{Chr{U32.from_nat(p)}, acc})

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

# Postgres: enquadramento e base64
# --------------------------------

def took.msg(m: Pg.Msg, want_tag: Char, want_body: String) -> Bool:
  match m:
    case Pg.Msg{tag, body}:
      Bool.and(Char.is_eq(tag, want_tag), String.eq(body, want_body))

def took.at(t: Pg.Taken, want_tag: Char, want_body: String,
  want_rest: String) -> Bool:
  match t:
    case Pg.Taken{msg, rest}:
      Bool.and(took.msg(msg, want_tag, want_body), String.eq(rest, want_rest))

def took(m: Maybe<&2, Pg.Taken>, want_tag: Char, want_body: String,
  want_rest: String) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{t}:
      took.at(t, want_tag, want_body, want_rest)

def nada(m: Maybe<&2, Pg.Taken>) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{t}:
      False{}

def test_pg_frame() -> IO(Unit):
  do IO<Unit>:
    check("pg: be32 desfaz u32be",
      U32.is_eq(Pg.be32(Pg.u32be(196608)), 196608))
    check("pg: be32 desfaz u32be no maximo",
      U32.is_eq(Pg.be32(Pg.u32be(4294967295)), 4294967295))
    check("pg: o tamanho da mensagem conta os 4 bytes dele mesmo",
      U32.is_eq(Pg.be32(String.drop(Pg.query("oi"), 1n)), 7))
    check("pg: take devolve a mensagem e o que sobrou",
      took(Pg.take(Pg.frame('R', "ab") ++ "sobra"), 'R', "ab", "sobra"))
    check("pg: take nao inventa mensagem cortada pela metade",
      nada(Pg.take(String.take(Pg.frame('R', "abcdef"), 5n))))
    check("pg: take de buffer vazio nao inventa mensagem",
      nada(Pg.take("")))

# Vetores da RFC 4648.
def test_b64() -> IO(Unit):
  do IO<Unit>:
    check("b64: vazio", String.eq(Pg.b64.enc(""), ""))
    check("b64: f", String.eq(Pg.b64.enc("f"), "Zg=="))
    check("b64: fo", String.eq(Pg.b64.enc("fo"), "Zm8="))
    check("b64: foo", String.eq(Pg.b64.enc("foo"), "Zm9v"))
    check("b64: foob", String.eq(Pg.b64.enc("foob"), "Zm9vYg=="))
    check("b64: fooba", String.eq(Pg.b64.enc("fooba"), "Zm9vYmE="))
    check("b64: foobar", String.eq(Pg.b64.enc("foobar"), "Zm9vYmFy"))
    check("b64: decodifica de volta, com padding de um",
      String.eq(Pg.b64.dec("Zm9vYmE="), "fooba"))
    check("b64: decodifica de volta, com padding de dois",
      String.eq(Pg.b64.dec("Zg=="), "f"))
    check("b64: decodifica de volta, sem padding",
      String.eq(Pg.b64.dec("Zm9vYmFy"), "foobar"))
    check("b64: byte alto sobrevive a ida e volta",
      String.eq(Pg.b64.dec(Pg.b64.enc(bytes(256n, SNil{}))),
        bytes(256n, SNil{})))

# Cripto: vetores do NIST e das RFC 4231 e 7914
# --------------------------------------------

def hex.at(m: Maybe<&2, Char>) -> Char:
  match m:
    case None{}:
      '?'
    case Some{c}:
      c

def hex.chr(i: U32) -> Char:
  hex.at(String.get("0123456789abcdef", U32.to_nat(i)))

def hex(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+c, t}:
      SCon{hex.chr(U32.shrn(Char.to_u32(c), 4n)),
        SCon{hex.chr(U32.and(Char.to_u32(c), 15)), hex(t)}}

# O byte 0x0b repetido, que e a chave do primeiro caso da RFC 4231.
def rep(n: Nat, +c: Char, acc: String) -> String:
  match n:
    case 0n:
      acc
    case 1n++p:
      rep(p, c, SCon{c, acc})

def test_crypto() -> IO(Unit):
  do IO<Unit>:
    a : String <- Crypto.sha256("abc")
    check("sha256: vetor abc do NIST", String.eq(hex(a),
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))
    b : String <- Crypto.sha256("")
    check("sha256: vetor vazio do NIST", String.eq(hex(b),
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"))
    c : String <- Crypto.sha256(rep(1000n, 'a', SNil{}))
    check("sha256: mil bytes, mais de um bloco", String.eq(hex(c),
      "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3"))
    d : String <- Crypto.hmac256(rep(20n, Chr{11}, SNil{}), "Hi There")
    check("hmac256: caso 1 da RFC 4231", String.eq(hex(d),
      "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"))
    e : String <- Crypto.hmac256("Jefe", "what do ya want for nothing?")
    check("hmac256: caso 2 da RFC 4231", String.eq(hex(e),
      "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"))
    f : String <- Crypto.hmac256(rep(131n, Chr{170}, SNil{}),
      "Test Using Larger Than Block-Size Key - Hash Key First")
    check("hmac256: caso 6 da RFC 4231, chave maior que o bloco",
      String.eq(hex(f),
        "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"))
    g : String <- Crypto.pbkdf2("password", "salt", 1)
    check("pbkdf2: uma volta", String.eq(hex(g),
      "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b"))
    h : String <- Crypto.pbkdf2("password", "salt", 4096)
    check("pbkdf2: 4096 voltas, que e o padrao do Postgres",
      String.eq(hex(h),
        "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a"))
    i : String <- Crypto.nonce(18)
    check("nonce: devolve o tamanho pedido",
      Nat.is_eq(String.length(i), 18n))

def main() -> IO(Unit):
  do IO<Unit>:
    test_parse()
    test_render()
    test_router()
    test_pg_frame()
    test_b64()
    test_crypto()
