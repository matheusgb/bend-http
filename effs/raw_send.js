// Raw
// ===

// Latin-1 na rede: um char, um byte. O TCP.send da Base recodifica em UTF-8,
// o que estraga todo byte acima de 0x7F. Protocolo binario precisa deste.
// Um socket cheio (nao bloqueante, logo EAGAIN) estaciona a computacao ate
// o socket aceitar escrita, e o loop volta aqui.
function send(socket, data, k) {
  const sys = io_sys();
  const fd = socket;
  const b = new Uint8Array(data.length);
  for (let i = 0; i < data.length; i++) {
    b[i] = data.charCodeAt(i) & 255;
  }
  const again = sys.mac ? 35 : 11;
  const go = (at) => {
    while (at < b.length) {
      const part = b.subarray(at);
      const n = Number(sys.send(fd, sys.ptr(part), part.length, 0));
      if (n < 0) {
        const code = sys.errno();
        if (code === again) {
          io_park_on(fd, true, k, () => go(at));
          return undefined;
        }
        return io_tup(socket, io_fail(code));
      }
      at += n;
    }
    return io_tup(socket, io_done({ $: "Unit" }));
  };
  return go(0);
}
