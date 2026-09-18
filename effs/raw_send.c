// Raw
// ===

// Latin-1 na rede: um char, um byte. Espelha tcp_send.c; so a conversao de
// String para bytes muda, porque io_cstr escreve UTF-8.
static char* raw_cstr(Env e, Term s, u64* len) {
  u64   cap = 64;
  u64   n   = 0;
  char* buf = io_mem(malloc(cap));
  while (term_aux(s) == CID_SCON) {
    Term fb[2];
    spare_free(e, cls_fit(2), ctr_take(e, s, 2, fb));
    if (n + 2 > cap) {
      cap *= 2;
      buf = io_mem(realloc(buf, cap));
    }
    buf[n] = (char)(fb[0] & 255);
    n += 1;
    s = fb[1];
  }
  buf[n] = 0;
  *len = n;
  return buf;
}

// Manda o que falta; socket cheio (nao bloqueante, logo EAGAIN) estaciona a
// computacao ate ele aceitar escrita, e o loop volta aqui.
static Term raw_send_more(Env e, IoWork* w) {
  int fd = (int)w->hand;
  while (w->code == 0 && (u64)w->made < w->size) {
    ssize_t n = send(fd, w->data + w->made, w->size - (u64)w->made, 0);
    if (n < 0 && errno == EAGAIN) {
      return io_wait_on(w, fd, POLLOUT, raw_send_more);
    }
    w->made += io_sys_end(w, n);
  }
  Term r = w->code != 0 ? io_fail(e, w->code, NULL)
    : io_done(e, term_pak(CID_UNIT, 0));
  free(w->data);
  return io_tup(e, io_hand(w->hand), r);
}

Term send_run(Env e, Term* f, IoWork* w) {
  w->hand = (intptr_t)io_hand_v(f[0]);
  w->data = raw_cstr(e, f[1], &w->size);
  w->made = 0;
  w->code = 0;
  return raw_send_more(e, w);
}

static void __attribute__((constructor)) send_use(void) {
  io_eff(CID_SEND, send_run, 0);
}
