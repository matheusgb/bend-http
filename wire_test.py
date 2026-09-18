#!/usr/bin/env python3
"""Teste de fio: o byte que sai tem que ser o byte que volta.

O peer aqui nao fala Bend. Ele manda os 256 bytes crus, le a resposta e
compara. O TCP da Base falha este teste: ele recodifica a saida em UTF-8 e
troca byte invalido por U+FFFD na entrada.

Rode: python3 wire_test.py            # pelo bend, backend JS
      python3 wire_test.py ./out     # por um binario nativo ja compilado
"""
import socket
import subprocess
import sys

PORT = 18080
PAYLOAD = bytes(range(256))

srv = socket.socket()
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", PORT))
srv.listen(1)
srv.settimeout(30)

cmd = sys.argv[1:] or ["bend", "wire.bend"]
peer = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
back = b""
try:
    conn, _ = srv.accept()
    conn.settimeout(30)
    conn.sendall(PAYLOAD)
    back = b""
    while len(back) < len(PAYLOAD):
        part = conn.recv(4096)
        if not part:
            break
        back += part
    conn.close()
except socket.timeout:
    peer.kill()
    print("FALHOU wire: o peer %s nao conectou" % cmd, file=sys.stderr)
    print(peer.stderr.read().decode(), file=sys.stderr)
    sys.exit(1)
finally:
    srv.close()

peer.wait(timeout=30)

if back != PAYLOAD:
    print("FALHOU wire: o byte voltou diferente", file=sys.stderr)
    print("  esperado %d bytes: %s" % (len(PAYLOAD), PAYLOAD[:16].hex()),
          file=sys.stderr)
    print("  recebido %d bytes: %s" % (len(back), back[:16].hex()),
          file=sys.stderr)
    print(peer.stderr.read().decode(), file=sys.stderr)
    sys.exit(1)

print("ok    wire: os 256 bytes atravessam o fio sem mudar (%s)" % cmd[0])
