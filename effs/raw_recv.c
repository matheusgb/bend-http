// Raw
// ===

// Latin-1 na rede: cada byte vira um char de 0 a 255. Espelha tcp_recv.c; so a
// conversao muda, porque io_str decodifica UTF-8 e troca byte invalido por
// U+FFFD.
static Term raw_str(Env e, const char* p, u64 n) {
  Term s    = term_pak(CID_SNIL, 0);
  Loc  hole = 0;
  for (u64 i = 0; i < n; i += 1) {
    Loc  l = heap_alloc(e, 1);
    Term t = term_ctr(CID_SCON, l);
    e.mem[l] = (u64)(uint8_t)p[i];
    if (hole == 0) {
      s = t;
    } else {
      e.mem[hole] = io_seal(e, t, IO_HOTS & 1);
    }
    hole = l + 1;
  }
  if (hole != 0) {
    e.mem[hole] = io_seal(e, term_pak(CID_SNIL, 0), IO_HOTS & 1);
  }
  return s;
}

static Term raw_recv_pack(Env e, IoWork* w) {
  Term r = w->code ? io_fail(e, w->code, NULL)
    : io_done(e, raw_str(e, w->data, w->size));
  free(w->data);
  return io_tup(e, io_hand(w->hand), r);
}

// O loop estacionou a leitura ate o socket ter dado; se ainda nao tem, ele
// estaciona de novo.
static Term raw_recv_more(Env e, IoWork* w) {
  int fd  = (int)w->hand;
  w->size = io_sys_end(w, recv(fd, w->data, (size_t)w->made, 0));
  return w->code == EAGAIN ? io_wait_on(w, fd, POLLIN, raw_recv_more)
    : raw_recv_pack(e, w);
}

Term recv_run(Env e, Term* f, IoWork* w) {
  w->hand = (intptr_t)io_hand_v(f[0]);
  w->made = f[1] < INT32_MAX ? (intptr_t)f[1] : INT32_MAX;
  w->data = io_mem(malloc((size_t)w->made + 1));
  return raw_recv_more(e, w);
}

static void __attribute__((constructor)) recv_use(void) {
  io_eff(CID_RECV, recv_run, IO_READ);
}
