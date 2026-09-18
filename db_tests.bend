# bend-http -- testes contra um Postgres de verdade. Rode:
#   docker run -d -e POSTGRES_PASSWORD=senha -e POSTGRES_USER=bend \
#     -e POSTGRES_DB=bend -p 55432:5432 postgres:16
#   bend db_tests.bend
#
# Configuravel por PGHOST, PGPORT, PGUSER, PGPASSWORD e PGDATABASE.
import Base
import ./raw.bend as Raw
import ./db.bend as Db

def check(name: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("ok    " ++ name)
    case False{}:
      IO.die(Unit, 1, "FALHOU " ++ name)

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

# Uma tabela vira texto, para o teste comparar uma string so.
def show.row(cs: List<&2, String>) -> String:
  String.join(cs, "|")

def show(t: List<&2, List<&2, String>>) -> String:
  match t:
    case Nil{}:
      ""
    case Con{r, rest}:
      show.row(r) ++ ";" ++ show(rest)

def erro(res: Result<&1, &1, Db.Err(), Db.Table()>) -> String:
  match res:
    case Fail{(code, m)}:
      m
    case Done{t}:
      "<sem erro>"

def table(res: Result<&1, &1, Db.Err(), Db.Table()>) -> String:
  match res:
    case Fail{(code, m)}:
      "<erro: " ++ m ++ ">"
    case Done{t}:
      show(t)

# Roda uma query e compara o texto do resultado.
def ask.done(name: String, want: String, r: Db.Fetch(),
  rest: Db.Conn -> IO(Unit)) -> IO(Unit):
  match r:
    case Tuple{conn, res}:
      IO.bind(Unit, Unit, check(name, String.eq(table(res), want)),
        u => rest(conn))

def ask(name: String, conn: Db.Conn, sql: String, want: String,
  rest: Db.Conn -> IO(Unit)) -> IO(Unit):
  IO.bind(Db.Fetch(), Unit, Db.query(conn, Raw.utf8(sql)),
    r => ask.done(name, want, r, rest))

def ask.err.done(name: String, want: String, r: Db.Fetch(),
  rest: Db.Conn -> IO(Unit)) -> IO(Unit):
  match r:
    case Tuple{conn, res}:
      IO.bind(Unit, Unit, check(name, String.contains(erro(res), want)),
        u => rest(conn))

def ask.err(name: String, conn: Db.Conn, sql: String, want: String,
  rest: Db.Conn -> IO(Unit)) -> IO(Unit):
  IO.bind(Db.Fetch(), Unit, Db.query(conn, Raw.utf8(sql)),
    r => ask.err.done(name, want, r, rest))

def suite(conn: Db.Conn) -> IO(Unit):
  ask("db: escalar", conn, "select 42", "42;", c1 =>
    ask("db: duas colunas e um texto", c1, "select 1, 'oi'", "1|oi;", c2 =>
      ask("db: varias linhas", c2,
        "select n from generate_series(1, 3) as n", "1;2;3;", c3 =>
        ask("db: null vira texto vazio", c3, "select null, 'x'", "|x;", c4 =>
          ask("db: acento volta em utf8", c4, "select 'ação'",
            Raw.utf8("ação") ++ ";", c5 =>
            ask("db: query sem linha nenhuma", c5,
              "select 1 where false", "", c6 =>
              ask.err("db: sql quebrado vira erro, nao linha", c6,
                "select nao_existe", "nao_existe", c7 =>
                ask("db: a conexao continua boa depois do erro", c7,
                  "select 7", "7;", c8 => Db.close(c8)))))))))

def logged(r: Result<&1, &1, Db.Err(), Db.Conn>) -> IO(Unit):
  match r:
    case Fail{(code, m)}:
      IO.die(Unit, 1, "FALHOU db: login nao passou: " ++ m)
    case Done{conn}:
      suite(conn)

def wrong(r: Result<&1, &1, Db.Err(), Db.Conn>) -> IO(Unit):
  match r:
    case Fail{(code, m)}:
      check("db: senha errada nao entra", True{})
    case Done{conn}:
      IO.bind(Unit, Unit, Db.close(conn),
        u => check("db: senha errada nao entra", False{}))

def main() -> IO(Unit):
  do IO<Unit>:
    +host : String <- env("PGHOST", "127.0.0.1")
    +raw_port : String <- env("PGPORT", "55432")
    +user : String <- env("PGUSER", "bend")
    +pass : String <- env("PGPASSWORD", "senha")
    +db : String <- env("PGDATABASE", "bend")
    IO.bind(Result<&1, &1, Db.Err(), Db.Conn>, Unit,
      Db.connect(host, port.at(U32.read(raw_port)), user, pass, db), logged)
    IO.bind(Result<&1, &1, Db.Err(), Db.Conn>, Unit,
      Db.connect(host, port.at(U32.read(raw_port)), user, pass ++ "x", db),
      wrong)
