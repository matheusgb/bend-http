// Raw
// ===

// Latin-1 na rede: cada byte vira um char de 0 a 255, sem decodificar UTF-8.
// Recebe zero byte quando o outro lado fecha. O loop estacionou a leitura ate
// o socket ter dado; se ainda nao tem, estaciona de novo.
function recv(socket, max, k) {
  const sys = io_sys();
  const fd = socket;
  const b = new Uint8Array(Math.max(Number(max), 1));
  const again = sys.mac ? 35 : 11;
  const go = () => {
    const n = Number(sys.recv(fd, sys.ptr(b), Number(max), 0));
    if (n < 0) {
      const code = sys.errno();
      if (code === again) {
        io_park_on(fd, false, k, go);
        return undefined;
      }
      return io_tup(socket, io_fail(code));
    }
    let s = "";
    for (let i = 0; i < n; i++) {
      s += String.fromCharCode(b[i]);
    }
    return io_tup(socket, io_done(s));
  };
  return go();
}

function recv_need() {
  return { read: true };
}
