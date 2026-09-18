#!/usr/bin/env python3
"""Teste de ponta a ponta: sobe o exemplo e fala HTTP de verdade com ele.

Rode: python3 http_test.py            # pelo bend, backend JS
      python3 http_test.py ./out/app  # por um binario nativo ja compilado
"""
import socket
import subprocess
import sys
import time

PORT = 8080
CASES = [
    ("GET /", [b"GET / HTTP/1.1\r\nHost: x\r\n\r\n"],
     b"HTTP/1.1 200 OK", b"oi, bend-http"),
    ("parametro de rota", [b"GET /users/42 HTTP/1.1\r\nHost: x\r\n\r\n"],
     b"HTTP/1.1 200 OK", b'{"id":"42"}'),
    ("POST com corpo",
     [b"POST /echo HTTP/1.1\r\nHost: x\r\ncontent-length: 8\r\n\r\noi mundo"],
     b"HTTP/1.1 201 Created", b"recebi: oi mundo"),
    ("rota que nao existe", [b"GET /nada HTTP/1.1\r\nHost: x\r\n\r\n"],
     b"HTTP/1.1 404 Not Found", b"nao encontrado"),
    ("request em dois pedacos",
     [b"POST /echo HTTP/1.1\r\nHost: x\r\ncontent-length: 5\r\n\r\nab",
      b"cde"],
     b"HTTP/1.1 201 Created", b"recebi: abcde"),
]


def ask(parts):
    """Manda a request em pedacos e le tudo que voltar."""
    s = socket.create_connection(("127.0.0.1", PORT), timeout=10)
    for part in parts:
        s.sendall(part)
        if len(parts) > 1:
            time.sleep(0.2)
    out = b""
    while True:
        got = s.recv(4096)
        if not got:
            break
        out += got
    s.close()
    return out


cmd = sys.argv[1:] or ["bend", "example.bend"]
server = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
falhou = []
try:
    for _ in range(100):
        try:
            socket.create_connection(("127.0.0.1", PORT), timeout=1).close()
            break
        except OSError:
            time.sleep(0.3)
    else:
        print("FALHOU http: o servidor nao subiu", file=sys.stderr)
        print(server.stderr.read().decode(), file=sys.stderr)
        sys.exit(1)

    for nome, req, status, corpo in CASES:
        got = ask(req)
        if not got.startswith(status) or not got.endswith(corpo):
            falhou.append((nome, status, corpo, got))
        else:
            print("ok    http: " + nome)
finally:
    server.kill()

for nome, status, corpo, got in falhou:
    print("FALHOU http: " + nome, file=sys.stderr)
    print("  esperado comecar com %r e terminar em %r" % (status, corpo),
          file=sys.stderr)
    print("  recebido %r" % got[:200], file=sys.stderr)

sys.exit(1 if falhou else 0)
