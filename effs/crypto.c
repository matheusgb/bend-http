// Crypto
// ======
//
// Os quatro primitivos que o SCRAM pede, no backend nativo. O clang aqui nao
// linka OpenSSL, entao o SHA-256 vem embutido, direto do FIPS 180-4. Os
// vetores do NIST e da RFC estao em tests.bend, e rodam nos dois backends.

static const u32 CRY_K[64] = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};

#define CRY_ROR(x, n) (((x) >> (n)) | ((x) << (32 - (n))))

typedef struct {
  u32     hs[8];
  u64     len;
  uint8_t buf[64];
  u64     n;
} CrySha;

static void cry_block(CrySha* s, const uint8_t* p) {
  u32 w[64];
  for (int i = 0; i < 16; i += 1) {
    w[i] = ((u32)p[i * 4] << 24) | ((u32)p[i * 4 + 1] << 16)
      | ((u32)p[i * 4 + 2] << 8) | (u32)p[i * 4 + 3];
  }
  for (int i = 16; i < 64; i += 1) {
    u32 s0 = CRY_ROR(w[i - 15], 7) ^ CRY_ROR(w[i - 15], 18) ^ (w[i - 15] >> 3);
    u32 s1 = CRY_ROR(w[i - 2], 17) ^ CRY_ROR(w[i - 2], 19) ^ (w[i - 2] >> 10);
    w[i] = w[i - 16] + s0 + w[i - 7] + s1;
  }
  u32 a = s->hs[0], b = s->hs[1], c = s->hs[2], d = s->hs[3];
  u32 v = s->hs[4], f = s->hs[5], g = s->hs[6], h = s->hs[7];
  for (int i = 0; i < 64; i += 1) {
    u32 x1 = CRY_ROR(v, 6) ^ CRY_ROR(v, 11) ^ CRY_ROR(v, 25);
    u32 ch = (v & f) ^ (~v & g);
    u32 t1 = h + x1 + ch + CRY_K[i] + w[i];
    u32 x0 = CRY_ROR(a, 2) ^ CRY_ROR(a, 13) ^ CRY_ROR(a, 22);
    u32 mj = (a & b) ^ (a & c) ^ (b & c);
    u32 t2 = x0 + mj;
    h = g; g = f; f = v; v = d + t1; d = c; c = b; b = a; a = t1 + t2;
  }
  s->hs[0] += a; s->hs[1] += b; s->hs[2] += c; s->hs[3] += d;
  s->hs[4] += v; s->hs[5] += f; s->hs[6] += g; s->hs[7] += h;
}

static void cry_init(CrySha* s) {
  static const u32 iv[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
  for (int i = 0; i < 8; i += 1) {
    s->hs[i] = iv[i];
  }
  s->len = 0;
  s->n   = 0;
}

static void cry_push(CrySha* s, const uint8_t* p, u64 n) {
  s->len += n;
  for (u64 i = 0; i < n; i += 1) {
    s->buf[s->n] = p[i];
    s->n += 1;
    if (s->n == 64) {
      cry_block(s, s->buf);
      s->n = 0;
    }
  }
}

static void cry_done(CrySha* s, uint8_t out[32]) {
  u64 bits = s->len * 8;
  uint8_t pad = 0x80;
  cry_push(s, &pad, 1);
  uint8_t zero = 0;
  while (s->n != 56) {
    cry_push(s, &zero, 1);
  }
  for (int i = 7; i >= 0; i -= 1) {
    uint8_t b = (uint8_t)(bits >> (i * 8));
    cry_push(s, &b, 1);
  }
  for (int i = 0; i < 8; i += 1) {
    out[i * 4]     = (uint8_t)(s->hs[i] >> 24);
    out[i * 4 + 1] = (uint8_t)(s->hs[i] >> 16);
    out[i * 4 + 2] = (uint8_t)(s->hs[i] >> 8);
    out[i * 4 + 3] = (uint8_t)(s->hs[i]);
  }
}

static void cry_sha(const uint8_t* p, u64 n, uint8_t out[32]) {
  CrySha s;
  cry_init(&s);
  cry_push(&s, p, n);
  cry_done(&s, out);
}

// HMAC-SHA-256, RFC 2104. Chave maior que o bloco vira o proprio hash dela.
static void cry_hmac(const uint8_t* key, u64 kn, const uint8_t* msg, u64 mn,
  uint8_t out[32]) {
  uint8_t k[64];
  uint8_t pad[64];
  uint8_t in[32];
  CrySha  s;
  for (int i = 0; i < 64; i += 1) {
    k[i] = 0;
  }
  if (kn > 64) {
    cry_sha(key, kn, k);
  } else {
    for (u64 i = 0; i < kn; i += 1) {
      k[i] = key[i];
    }
  }
  for (int i = 0; i < 64; i += 1) {
    pad[i] = k[i] ^ 0x36;
  }
  cry_init(&s);
  cry_push(&s, pad, 64);
  cry_push(&s, msg, mn);
  cry_done(&s, in);
  for (int i = 0; i < 64; i += 1) {
    pad[i] = k[i] ^ 0x5c;
  }
  cry_init(&s);
  cry_push(&s, pad, 64);
  cry_push(&s, in, 32);
  cry_done(&s, out);
}

// PBKDF2-HMAC-SHA-256 com saida de 32 bytes, ou seja, um bloco so.
static void cry_pbkdf2(const uint8_t* pw, u64 pn, const uint8_t* salt, u64 sn,
  u32 iters, uint8_t out[32]) {
  uint8_t* first = (uint8_t*)io_mem(malloc(sn + 4));
  uint8_t  u[32];
  for (u64 i = 0; i < sn; i += 1) {
    first[i] = salt[i];
  }
  first[sn] = 0; first[sn + 1] = 0; first[sn + 2] = 0; first[sn + 3] = 1;
  cry_hmac(pw, pn, first, sn + 4, u);
  free(first);
  for (int i = 0; i < 32; i += 1) {
    out[i] = u[i];
  }
  for (u32 r = 1; r < iters; r += 1) {
    cry_hmac(pw, pn, u, 32, u);
    for (int i = 0; i < 32; i += 1) {
      out[i] ^= u[i];
    }
  }
}

// Ponte com o Bend: byte cru vira String de um char por byte, e volta.
static uint8_t* cry_cstr(Env en, Term s, u64* len) {
  u64      cap = 64;
  u64      n   = 0;
  uint8_t* buf = io_mem(malloc(cap));
  while (term_aux(s) == CID_SCON) {
    Term fb[2];
    spare_free(en, cls_fit(2), ctr_take(en, s, 2, fb));
    if (n + 2 > cap) {
      cap *= 2;
      buf = io_mem(realloc(buf, cap));
    }
    buf[n] = (uint8_t)(fb[0] & 255);
    n += 1;
    s = fb[1];
  }
  buf[n] = 0;
  *len = n;
  return buf;
}

static Term cry_str(Env en, const uint8_t* p, u64 n) {
  Term s    = term_pak(CID_SNIL, 0);
  Loc  hole = 0;
  for (u64 i = 0; i < n; i += 1) {
    Loc  l = heap_alloc(en, 1);
    Term t = term_ctr(CID_SCON, l);
    en.mem[l] = (u64)p[i];
    if (hole == 0) {
      s = t;
    } else {
      en.mem[hole] = io_seal(en, t, IO_HOTS & 1);
    }
    hole = l + 1;
  }
  if (hole != 0) {
    en.mem[hole] = io_seal(en, term_pak(CID_SNIL, 0), IO_HOTS & 1);
  }
  return s;
}

Term sha256_run(Env en, Term* f, IoWork* w) {
  u64      n    = 0;
  uint8_t* data = cry_cstr(en, f[0], &n);
  uint8_t  out[32];
  cry_sha(data, n, out);
  free(data);
  return cry_str(en, out, 32);
}

Term hmac256_run(Env en, Term* f, IoWork* w) {
  u64      kn  = 0;
  u64      mn  = 0;
  uint8_t* key = cry_cstr(en, f[0], &kn);
  uint8_t* msg = cry_cstr(en, f[1], &mn);
  uint8_t  out[32];
  cry_hmac(key, kn, msg, mn, out);
  free(key);
  free(msg);
  return cry_str(en, out, 32);
}

Term pbkdf2_run(Env en, Term* f, IoWork* w) {
  u64      pn   = 0;
  u64      sn   = 0;
  uint8_t* pw   = cry_cstr(en, f[0], &pn);
  uint8_t* salt = cry_cstr(en, f[1], &sn);
  uint8_t  out[32];
  cry_pbkdf2(pw, pn, salt, sn, (u32)f[2], out);
  free(pw);
  free(salt);
  return cry_str(en, out, 32);
}

// O nonce do SCRAM precisa ser imprevisivel, entao ele vem do sistema. Sem
// /dev/urandom, ele volta vazio: byte zero passaria calado por aleatorio, e
// quem chama compara o tamanho antes de usar.
Term nonce_run(Env en, Term* f, IoWork* w) {
  u64      n   = (u64)f[0];
  uint8_t* buf = io_mem(malloc(n + 1));
  FILE*    src = fopen("/dev/urandom", "rb");
  u64      got = src == NULL ? 0 : (u64)fread(buf, 1, (size_t)n, src);
  if (src != NULL) {
    fclose(src);
  }
  Term r = cry_str(en, buf, got < n ? 0 : n);
  free(buf);
  return r;
}

static void __attribute__((constructor)) cry_use(void) {
  io_eff(CID_SHA256, sha256_run, 0);
  io_eff(CID_HMAC256, hmac256_run, 0);
  io_eff(CID_PBKDF2, pbkdf2_run, 0);
  io_eff(CID_NONCE, nonce_run, 0);
}
