# bend-http -- testes puros. Um caso que falha encerra com codigo diferente de
# zero. O teste de fio, que precisa de peer externo, fica em wire_test.py.
# Rode: bend tests.bend
import Base
import ./http.bend as Http
import ./pg.bend as Pg
import ./crypto.bend as Crypto
import ./raw.bend as Raw

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

def need.or(m: Maybe<&2, Nat>, d: Nat) -> Nat:
  match m:
    case None{}:
      d
    case Some{n}:
      n

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
    check("parse: dois content-length viram request invalida",
      String.eq(got(Http.parse("GET / HTTP/1.1\r\ncontent-length: 1\r\n"
        ++ "Content-Length: 9\r\n\r\nx"), 0n, ""), "<nao parseou>"))
    check("parse: transfer-encoding vira request invalida, porque a v1 nao faz",
      String.eq(got(Http.parse("GET / HTTP/1.1\r\ntransfer-encoding: chunked"
        ++ "\r\n\r\n"), 0n, ""), "<nao parseou>"))
    check("parse: um content-length so continua valido",
      String.eq(got(Http.parse("POST / HTTP/1.1\r\ncontent-length: 1\r\n"
        ++ "\r\nx"), 3n, ""), "x"))
    check("need: sem o fim do cabecalho, nao da para saber o tamanho",
      Nat.is_eq(need.or(Http.need("GET / HTT"), 0n), 0n))
    check("need: com o cabecalho fechado, o tamanho e cabecalho mais corpo",
      Nat.is_eq(need.or(Http.need("GET / HTTP/1.1\r\ncontent-length: 3"
        ++ "\r\n\r\nabc"), 0n), 40n))

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

# Literal de SQL
# --------------

def test_lit() -> IO(Unit):
  do IO<Unit>:
    check("lit: texto simples vira texto entre aspas",
      String.eq(Pg.lit("oi"), "'oi'"))
    check("lit: aspa dentro do texto dobra",
      String.eq(Pg.lit("o'brien"), "'o''brien'"))
    check("lit: tentativa de fechar a string e virar comando nao escapa",
      String.eq(Pg.lit("x'; drop table alvo; --"),
        "'x''; drop table alvo; --'"))
    check("lit: barra invertida fica como esta, que e a regra do Postgres",
      String.eq(Pg.lit("c:\\tmp"), "'c:\\tmp'"))
    check("lit: byte zero sai fora, senao ele cortaria a query no meio",
      String.eq(Pg.lit(SCon{'a', SCon{Chr{0}, SCon{'b', SNil{}}}}), "'ab'"))

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
    # As bordas do bloco de 64 bytes, que e onde implementacao de SHA erra.
    b55 : String <- Crypto.sha256(rep(55n, 'a', SNil{}))
    check("sha256: 55 bytes, o ultimo que cabe com o padding", String.eq(hex(b55),
      "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318"))
    b56 : String <- Crypto.sha256(rep(56n, 'a', SNil{}))
    check("sha256: 56 bytes, o primeiro que pede bloco extra",
      String.eq(hex(b56),
        "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a"))
    b64 : String <- Crypto.sha256(rep(64n, 'a', SNil{}))
    check("sha256: 64 bytes, o bloco exato", String.eq(hex(b64),
      "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb"))
    b65 : String <- Crypto.sha256(rep(65n, 'a', SNil{}))
    check("sha256: 65 bytes, um a mais que o bloco", String.eq(hex(b65),
      "635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0"))
    k64 : String <- Crypto.hmac256(rep(64n, 'k', SNil{}), "msg")
    check("hmac256: chave do tamanho exato do bloco", String.eq(hex(k64),
      "d62ad25bb128e96ab6ef43464aaf2bb91b5b85f013381e9ba6be747e8d0911b2"))
    k65 : String <- Crypto.hmac256(rep(65n, 'k', SNil{}), "msg")
    check("hmac256: chave de um byte acima do bloco", String.eq(hex(k65),
      "c65585780e821bd312cfaa440c33cb28d6af6b323d4977ae83934834ce589e38"))
    p0 : String <- Crypto.pbkdf2("pw", "", 1)
    check("pbkdf2: salt vazio", String.eq(hex(p0),
      "6a65192736d636be9f08743ea5a9e37cf93c2701cc689aac593a23a0a9df5677"))
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

# UTF-8: codepoint vira byte
# --------------------------

def test_utf8() -> IO(Unit):
  do IO<Unit>:
    check("utf8: ASCII nao muda", String.eq(Raw.utf8("abc"), "abc"))
    check("utf8: cedilha vira dois bytes",
      String.eq(Raw.utf8(SCon{Chr{231}, SNil{}}),
        SCon{Chr{195}, SCon{Chr{167}, SNil{}}}))
    check("utf8: o til do a vira dois bytes",
      String.eq(Raw.utf8(SCon{Chr{227}, SNil{}}),
        SCon{Chr{195}, SCon{Chr{163}, SNil{}}}))
    check("utf8: o euro vira tres bytes",
      String.eq(Raw.utf8(SCon{Chr{8364}, SNil{}}),
        SCon{Chr{226}, SCon{Chr{130}, SCon{Chr{172}, SNil{}}}}))
    check("utf8: emoji vira quatro bytes",
      String.eq(Raw.utf8(SCon{Chr{128512}, SNil{}}),
        SCon{Chr{240}, SCon{Chr{159}, SCon{Chr{152}, SCon{Chr{128},
          SNil{}}}}}))
    check("utf8: o tamanho em byte e maior que o tamanho em char",
      Nat.is_eq(String.length(Raw.utf8(SCon{Chr{231}, "ao"})), 4n))

def main() -> IO(Unit):
  do IO<Unit>:
    test_parse()
    test_render()
    test_router()
    test_pg_frame()
    test_b64()
    test_lit()
    test_crypto()
    test_utf8()
