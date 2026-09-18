#!/usr/bin/env python3
"""Testa a demo de ponta a ponta: cria a tabela, sobe o servidor, POST e GET.

Precisa de um Postgres. Com o docker do README:
  python3 demo_test.py
"""
import json
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request

PORT = 8090
BASE = "http://127.0.0.1:%d" % PORT


def post(titulo):
    dados = urllib.parse.urlencode({"titulo": titulo}).encode()
    with urllib.request.urlopen(BASE + "/tarefas", dados, timeout=20) as r:
        return json.loads(r.read())


def get(caminho):
    with urllib.request.urlopen(BASE + caminho, timeout=20) as r:
        return json.loads(r.read())


falhou = []


def check(nome, ok, visto=None):
    if ok:
        print("ok    demo: " + nome)
    else:
        falhou.append((nome, visto))


setup = subprocess.run(["bend", "setup.bend"], capture_output=True, text=True)
if "pronta" not in setup.stdout:
    print("FALHOU demo: setup nao criou a tabela", file=sys.stderr)
    print(setup.stdout + setup.stderr, file=sys.stderr)
    sys.exit(1)
print("ok    demo: setup criou a tabela")

servidor = subprocess.Popen(["bend", "agenda.bend"],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
try:
    for _ in range(100):
        try:
            get("/tarefas")
            break
        except Exception:
            time.sleep(0.3)
    else:
        print("FALHOU demo: o servidor nao subiu", file=sys.stderr)
        print(servidor.stderr.read().decode(), file=sys.stderr)
        sys.exit(1)

    marca = "tarefa %d" % time.time()
    criado = post(marca)
    check("POST devolve a linha criada",
          len(criado) == 1 and criado[0]["titulo"] == marca, criado)

    ident = criado[0]["id"]
    um = get("/tarefas/" + ident)
    check("GET por id devolve a mesma linha",
          len(um) == 1 and um[0]["titulo"] == marca, um)

    lista = get("/tarefas")
    check("GET na lista traz o que o POST gravou",
          any(t["titulo"] == marca for t in lista), len(lista))

    acento = post("revisão de código")
    check("acento sobrevive ao caminho inteiro",
          acento[0]["titulo"] == "revisão de código", acento)

    aspas = post('ler "o cortiço"')
    check("aspa no valor nao quebra o JSON",
          aspas[0]["titulo"] == 'ler "o cortiço"', aspas)

    # Se o Pg.lit falhasse, o drop rodaria e o proximo GET quebraria.
    ataque = "x'); drop table tarefa; --"
    inj = post(ataque)
    check("injecao de SQL entra como dado", inj[0]["titulo"] == ataque, inj)
    check("a tabela continua de pe depois da tentativa",
          any(t["titulo"] == ataque for t in get("/tarefas")))
finally:
    servidor.kill()

for nome, visto in falhou:
    print("FALHOU demo: " + nome, file=sys.stderr)
    print("  recebido: %r" % (visto,), file=sys.stderr)

sys.exit(1 if falhou else 0)
