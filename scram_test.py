#!/usr/bin/env python3
"""Servidor Postgres falso: ele fecha o SCRAM sem saber a senha.

Um cliente correto recusa os dois casos:
  - assinatura do servidor errada no SASLFinal;
  - nonce do servidor que nao continua o nonce do cliente.

Sem essas duas checagens, quem estiver no meio do caminho entra como se fosse
o banco. Rode: python3 scram_test.py
"""
import base64
import hashlib
import hmac
import os
import socket
import subprocess
import sys

PORT = 55433
SALT = b"saltsalt"
ITERS = 4096


def recv_exact(conn, n):
    out = b""
    while len(out) < n:
        part = conn.recv(n - len(out))
        if not part:
            raise EOFError("o cliente fechou")
        out += part
    return out


def read_startup(conn):
    size = int.from_bytes(recv_exact(conn, 4), "big")
    recv_exact(conn, size - 4)


def read_tagged(conn):
    tag = recv_exact(conn, 1)
    size = int.from_bytes(recv_exact(conn, 4), "big")
    return tag, recv_exact(conn, size - 4)


def send(conn, tag, body):
    conn.sendall(tag + (len(body) + 4).to_bytes(4, "big") + body)


def auth(code, extra=b""):
    return code.to_bytes(4, "big") + extra


def serve(quebra):
    """Fala SCRAM ate o fim, quebrando o passo pedido."""
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", PORT))
    srv.listen(1)
    srv.settimeout(30)
    peer = subprocess.Popen(["bend", "scram_try.bend"],
                            env={**os.environ, "PGPORT": str(PORT)},
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        conn, _ = srv.accept()
        conn.settimeout(30)
        read_startup(conn)
        send(conn, b"R", auth(10, b"SCRAM-SHA-256\x00\x00"))

        _, body = read_tagged(conn)
        first = body.split(b"\x00", 1)[1][4:].decode("latin1")
        cnonce = first.split("r=", 1)[1]
        snonce = "xyz123" if quebra == "nonce" else cnonce + "servidor"
        sfirst = "r=%s,s=%s,i=%d" % (
            snonce, base64.b64encode(SALT).decode(), ITERS)
        send(conn, b"R", auth(11, sfirst.encode()))

        _, final = read_tagged(conn)
        bare = first[first.index("n="):]
        cfinal = final.split(b"\x00", 1)[0].decode("latin1") \
            if False else final.decode("latin1")
        auth_msg = "%s,%s,%s" % (bare, sfirst, cfinal.split(",p=")[0])
        salted = hashlib.pbkdf2_hmac("sha256", b"senha", SALT, ITERS, 32)
        skey = hmac.new(salted, b"Server Key", hashlib.sha256).digest()
        sig = hmac.new(skey, auth_msg.encode(), hashlib.sha256).digest()
        if quebra == "assinatura":
            sig = bytes(b ^ 1 for b in sig)
        send(conn, b"R",
             auth(12, b"v=" + base64.b64encode(sig)))
        send(conn, b"R", auth(0))
        send(conn, b"Z", b"I")
        conn.close()
    except (EOFError, socket.timeout, OSError):
        pass
    finally:
        srv.close()
    out = peer.communicate(timeout=30)[0].decode()
    return out.strip()


falhou = []
CASOS = [
    ("assinatura", "assinatura do servidor errada", "recusado:"),
    ("nonce", "nonce do servidor trocado", "recusado:"),
    # O controle: sem quebra nenhuma o login passa. Sem este caso, os dois de
    # cima passariam ate se o cliente recusasse tudo por outro motivo.
    ("nada", "handshake correto", "aceitou"),
]
for quebra, nome, esperado in CASOS:
    disse = serve(quebra)
    if disse.startswith(esperado):
        print("ok    scram: %s" % nome)
    else:
        falhou.append((nome, esperado, disse))

for nome, esperado, disse in falhou:
    print("FALHOU scram: %s" % nome, file=sys.stderr)
    print("  esperava comecar com %r, o cliente disse %r"
          % (esperado, disse), file=sys.stderr)

sys.exit(1 if falhou else 0)
