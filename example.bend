# bend-http -- exemplo. Rode: bend example.bend
# Depois: curl localhost:8080/ e curl -d oi localhost:8080/echo
import Base
import ./http.bend as Http
import ./server.bend as Server
import ./raw.bend as Raw
import ./db.bend as Db

def hello(+r: Http.Req) -> IO(Http.Res):
  IO.pure(Http.Res, Http.text(200, "oi, bend-http"))

def user(+r: Http.Req) -> IO(Http.Res):
  IO.pure(Http.Res,
    Http.json(200, "{\"id\":\"" ++ Http.param(r, "id") ++ "\"}"))

def echo(+r: Http.Req) -> IO(Http.Res):
  IO.pure(Http.Res, Http.text(201, "recebi: " ++ Http.body(r)))

# Uma conexao por request: a v1 nao tem pool. Para carga de verdade, isso e o
# primeiro lugar a mexer.
def db.first(t: List<&2, List<&2, String>>) -> String:
  match t:
    case Nil{}:
      ""
    case Con{r, rest}:
      String.join(r, "|")

def db.res(res: Result<&1, &1, Db.Err(), Db.Table()>) -> Http.Res:
  match res:
    case Fail{(code, m)}:
      Http.text(500, "postgres: " ++ m)
    case Done{t}:
      Http.text(200, db.first(t))

def db.done(r: Db.Fetch()) -> IO(Http.Res):
  match r:
    case Tuple{conn, res}:
      IO.bind(Unit, Http.Res, Db.close(conn),
        u => IO.pure(Http.Res, db.res(res)))

def db.open(r: Result<&1, &1, Db.Err(), Db.Conn>) -> IO(Http.Res):
  match r:
    case Fail{(code, m)}:
      IO.pure(Http.Res, Http.text(500, "postgres nao conectou: " ++ m))
    case Done{conn}:
      IO.bind(Db.Fetch(), Http.Res,
        Db.query(conn, Raw.utf8("select now(), version()")), db.done)

def agora(+r: Http.Req) -> IO(Http.Res):
  IO.bind(Result<&1, &1, Db.Err(), Db.Conn>, Http.Res,
    Db.connect("127.0.0.1", 55432, "bend", "senha", "bend"), db.open)

def routes() -> List<&1, Http.Route>:
  [Http.get("/", hello),
    Http.get("/users/:id", user),
    Http.post("/echo", echo),
    Http.get("/agora", agora)]

def main() -> IO(Unit):
  Server.listen(~routes(), 8080)
