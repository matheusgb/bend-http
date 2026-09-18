# Agenda -- demo de bend-http: GET e POST em cima do Postgres.
#
# Rode:
#   bend setup.bend     # cria a tabela
#   bend agenda.bend    # sobe o servidor na 8090
import Base
import ./lib/http.bend as Http
import ./lib/server.bend as Server
import ./lib/db.bend as Db
import ./lib/pg.bend as Pg

# Config por ambiente, com o mesmo padrao do docker do README.
def env.or(d: String, r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Fail{(code, m)}:
      d
    case Done{v}:
      v

def env(name: String, d: String) -> IO(String):
  IO.bind(Result<&1, &1, U32 & String, String>, String, IO.get_env(name),
    r => IO.pure(String, env.or(d, r)))

def port.at(m: Maybe<&2, U32>) -> U32:
  match m:
    case None{}:
      55432
    case Some{n}:
      n

type Cfg is Data:
  Cfg{host: String, port: U32, user: String, senha: String, base: String}

# Uma query por request: abre, pergunta, fecha.
def run.done(r: Db.Fetch(),
  k: Result<&1, &1, Db.Err(), Db.Table()> -> Http.Res) -> IO(Http.Res):
  match r:
    case Tuple{conn, res}:
      IO.bind(Unit, Http.Res, Db.close(conn),
        u => IO.pure(Http.Res, k(res)))

def run.open(sql: String,
  k: Result<&1, &1, Db.Err(), Db.Table()> -> Http.Res,
  r: Result<&1, &1, Db.Err(), Db.Conn>) -> IO(Http.Res):
  match r:
    case Fail{(code, m)}:
      IO.pure(Http.Res, Http.text(500, "banco fora: " ++ m))
    case Done{conn}:
      IO.bind(Db.Fetch(), Http.Res, Db.query(conn, sql),
        r2 => run.done(r2, k))

def run.cfg(c: Cfg, sql: String,
  k: Result<&1, &1, Db.Err(), Db.Table()> -> Http.Res) -> IO(Http.Res):
  match c:
    case Cfg{host, port, user, senha, base}:
      IO.bind(Result<&1, &1, Db.Err(), Db.Conn>, Http.Res,
        Db.connect(host, port, user, senha, base), r => run.open(sql, k, r))

def cfg() -> IO(Cfg):
  do IO<Cfg>:
    host : String <- env("PGHOST", "127.0.0.1")
    raw_port : String <- env("PGPORT", "55432")
    user : String <- env("PGUSER", "bend")
    senha : String <- env("PGPASSWORD", "senha")
    base : String <- env("PGDATABASE", "bend")
    return Cfg{host, port.at(U32.read(raw_port)), user, senha, base}

def run(sql: String,
  k: Result<&1, &1, Db.Err(), Db.Table()> -> Http.Res) -> IO(Http.Res):
  IO.bind(Cfg, Http.Res, cfg(), c => run.cfg(c, sql, k))

# Tabela do Postgres vira JSON. Http.jstr cuida das aspas do valor.

def json.cols.at(fim: Bool, um: String, resto: String) -> String:
  match fim:
    case True{}:
      um
    case False{}:
      um ++ "," ++ resto

def json.cols.sep(um: String, +resto: String) -> String:
  json.cols.at(String.is_empty(resto), um, resto)

def json.cols(cs: List<&2, String>, nomes: List<&2, String>) -> String:
  match cs nomes:
    case Nil{} _:
      ""
    case Con{c, ct} Nil{}:
      ""
    case Con{c, ct} Con{n, nt}:
      json.cols.sep(Http.jstr(n) ++ ":" ++ Http.jstr(c),
        json.cols(ct, nt))

def json.rows(t: List<&2, List<&2, String>>, +nomes: List<&2, String>) ->
  String:
  match t:
    case Nil{}:
      ""
    case Con{r, rt}:
      json.cols.sep("{" ++ json.cols(r, nomes) ++ "}", json.rows(rt, nomes))

def json.res(res: Result<&1, &1, Db.Err(), Db.Table()>) -> Http.Res:
  match res:
    case Fail{(code, m)}:
      Http.json(500, "{\"erro\":" ++ Http.jstr(m) ++ "}")
    case Done{t}:
      Http.json(200, "[" ++ json.rows(t, ["id", "titulo", "feito"]) ++ "]")

# Rotas
# -----

def listar(+r: Http.Req) -> IO(Http.Res):
  run("select id, titulo, feito from tarefa order by id", json.res)

def ver(+r: Http.Req) -> IO(Http.Res):
  run("select id, titulo, feito from tarefa where id = "
    ++ Pg.lit(Http.param(r, "id")) ++ "::int", json.res)

def criar(+r: Http.Req) -> IO(Http.Res):
  run("insert into tarefa (titulo) values ("
    ++ Pg.lit(Http.form(Http.body(r), "titulo"))
    ++ ") returning id, titulo, feito", json.res)

def routes() -> List<&1, Http.Route>:
  [Http.get("/tarefas", listar),
    Http.get("/tarefas/:id", ver),
    Http.post("/tarefas", criar)]

def main() -> IO(Unit):
  Server.listen(~routes(), 8090)
