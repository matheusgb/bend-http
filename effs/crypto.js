// Crypto
// ======
//
// Os quatro primitivos que o SCRAM pede. A plataforma faz a conta; aqui so
// entra e sai byte em latin1, um char por byte, do jeito que raw.bend usa.

function cry_buf(text) {
  const b = new Uint8Array(text.length);
  for (let i = 0; i < text.length; i++) {
    b[i] = text.charCodeAt(i) & 255;
  }
  return b;
}

function cry_text(b) {
  let s = "";
  for (let i = 0; i < b.length; i++) {
    s += String.fromCharCode(b[i]);
  }
  return s;
}

function sha256(data) {
  const c = require("node:crypto");
  return cry_text(c.createHash("sha256").update(cry_buf(data)).digest());
}

function hmac256(key, data) {
  const c = require("node:crypto");
  return cry_text(c.createHmac("sha256", cry_buf(key)).update(cry_buf(data))
    .digest());
}

function pbkdf2(pass, salt, iters) {
  const c = require("node:crypto");
  return cry_text(c.pbkdf2Sync(cry_buf(pass), cry_buf(salt), Number(iters), 32,
    "sha256"));
}

// Sem aleatorio do sistema, volta vazio: quem chama compara o tamanho antes
// de usar, e byte zero nao passa por nonce.
function nonce(n) {
  try {
    const c = require("node:crypto");
    return cry_text(c.randomBytes(Number(n)));
  } catch (err) {
    return "";
  }
}
