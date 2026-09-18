# bend-http -- tenta um login e diz o que aconteceu, para scram_test.py julgar.
# Alvo por PGHOST e PGPORT.
import Base
import ./db.bend as Db

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

def said(r: Result<&1, &1, Db.Err(), Db.Conn>) -> IO(Unit):
  match r:
    case Fail{(code, m)}:
      IO.print("recusado: " ++ m)
    case Done{conn}:
      IO.bind(Unit, Unit, Db.close(conn), u => IO.print("aceitou"))

def main() -> IO(Unit):
  do IO<Unit>:
    +host : String <- env("PGHOST", "127.0.0.1")
    +raw_port : String <- env("PGPORT", "55432")
    +user : String <- env("PGUSER", "bend")
    +pass : String <- env("PGPASSWORD", "senha")
    +db : String <- env("PGDATABASE", "bend")
    IO.bind(Result<&1, &1, Db.Err(), Db.Conn>, Unit,
      Db.connect(host, port.at(U32.read(raw_port)), user, pass, db), said)
