# bend-http -- exemplo. Rode: bend example.bend
# Depois: curl localhost:8080/ e curl -d oi localhost:8080/echo
import Base
import ./http.bend as Http
import ./server.bend as Server

def hello(+r: Http.Req) -> IO(Http.Res):
  IO.pure(Http.Res, Http.text(200, "oi, bend-http"))

def user(+r: Http.Req) -> IO(Http.Res):
  IO.pure(Http.Res,
    Http.json(200, "{\"id\":\"" ++ Http.param(r, "id") ++ "\"}"))

def echo(+r: Http.Req) -> IO(Http.Res):
  IO.pure(Http.Res, Http.text(201, "recebi: " ++ Http.body(r)))

def routes() -> List<&1, Http.Route>:
  [Http.get("/", hello),
    Http.get("/users/:id", user),
    Http.post("/echo", echo)]

def main() -> IO(Unit):
  Server.listen(~routes(), 8080)
