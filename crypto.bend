# bend-http -- os primitivos de cripto que o SCRAM pede.
#
# A conta sai da plataforma, nao do Bend: cripto escrita a mao erra calado.
# Entra e sai byte em latin1, um char por byte, igual ao raw.bend.
import Base

def sha256(data: String) -> IO(String):
  import "./effs/crypto.c"
  import "./effs/crypto.js"

def hmac256(key: String, data: String) -> IO(String):
  import "./effs/crypto.c"
  import "./effs/crypto.js"

def pbkdf2(pass: String, salt: String, iters: U32) -> IO(String):
  import "./effs/crypto.c"
  import "./effs/crypto.js"

def nonce(n: U32) -> IO(String):
  import "./effs/crypto.c"
  import "./effs/crypto.js"
