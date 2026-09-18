# Agenda -- cria a tabela. Rode uma vez: bend setup.bend
import Base
import ./lib/db.bend as Db
import ./lib/raw.bend as Raw

def sql() -> String:
  "create table if not exists tarefa (id serial primary key, "
    ++ "titulo text not null, feito boolean not null default false)"

def mostra(res: Result<&1, &1, Db.Err(), Db.Table()>) -> String:
  match res:
    case Fail{(code, m)}:
      "falhou: " ++ m
    case Done{t}:
      "tabela tarefa pronta"

def done(r: Db.Fetch()) -> IO(Unit):
  match r:
    case Tuple{conn, res}:
      IO.bind(Unit, Unit, Db.close(conn), u => IO.print(mostra(res)))

def aberto(r: Result<&1, &1, Db.Err(), Db.Conn>) -> IO(Unit):
  match r:
    case Fail{(code, m)}:
      IO.die(Unit, 1, "banco fora: " ++ m)
    case Done{conn}:
      IO.bind(Db.Fetch(), Unit, Db.query(conn, Raw.utf8(sql())), done)

def main() -> IO(Unit):
  IO.bind(Result<&1, &1, Db.Err(), Db.Conn>, Unit,
    Db.connect("127.0.0.1", 55432, "bend", "senha", "bend"), aberto)
