# bend-http

Biblioteca de backend web em [Bend](https://bend-lang.com): servidor HTTP/1.1,
router e cliente Postgres. Tudo em Bend, sem dependência externa.

Estado: em construção. Nada aqui é estável ainda.

## O que a v1 entrega

- Parser de request HTTP/1.1 e render de response.
- Router com método, caminho, parâmetro de rota e query string.
- Middleware como função pura.
- `PG.connect` e `PG.query`, protocolo v3 simples, auth SCRAM-SHA-256.

## O que a v1 não entrega

| Fora | Motivo |
| --- | --- |
| TLS | Rode atrás de Caddy ou nginx. |
| Chunked encoding | A v1 exige `Content-Length`. |
| Upload binário | `String` do Bend é lista de char. Corpo binário sai caro. |
| Pool de conexão | Uma conexão por processo. Pool quando alguém medir a falta. |
| Prepared statement | O protocolo simples já cobre `SELECT` e `INSERT`. |

## Rodar

```bash
curl -fsSL https://bend-lang.com/install.sh | sh   # instala o Bend
bend tests.bend                                    # testes puros
bend PROOF.bend                                    # provas
python3 wire_test.py                               # teste de fio
python3 http_test.py                               # teste de ponta a ponta
bend example.bend                                  # sobe o exemplo na 8080
bend example.bend -o out/app                       # binario nativo, precisa de clang
```

## Rigor

- `LAWS.bend` declara o que a biblioteca promete, `PROOF.bend` prova, e
  `bend PROOF.bend` falha enquanto uma lei estiver aberta ou falsa. Hoje estão
  provadas três: padrão mais longo que o caminho nunca casa, caminho mais longo
  que o padrão nunca casa, e router sem rota responde 404.
- Prova em Bend paga sobre estrutura recursiva (`List`, `Nat`, `String`). Ela
  trava sobre comparação de `U32` e literal de texto, que não reduzem com valor
  simbólico. O que não cabe em lei fica em teste, e o README diz qual é qual.
- `tests.bend` sai com código diferente de zero quando um caso falha.
- `wire_test.py` checa o byte no fio contra um peer que não fala Bend. Teste de
  Bend contra Bend não serve aqui: ida e volta por UTF-8 também é reversível
  entre dois Bend, então ele passaria com o TCP errado.
- O Bend não tem ferramenta de cobertura. O CI checa que todo `def` público
  aparece em `tests.bend`. Isso é cobertura de nome, não de caminho: garante que
  nenhuma função pública ficou sem teste, não que todo ramo foi exercitado.

## Escrever um handler

```python
import Base
import ./http.bend as Http
import ./server.bend as Server

def hello(+r: Http.Req) -> IO(Http.Res):
  IO.pure(Http.Res, Http.text(200, "oi, " ++ Http.param(r, "nome")))

def routes() -> List<&1, Http.Route>:
  [Http.get("/oi/:nome", hello)]

def main() -> IO(Unit):
  Server.listen(~routes(), 8080)
```

O `+` em `+r` marca a request como reusável: sem ele, o handler só pode tocar
nela uma vez. O `~` em `~routes()` passa a lista de rotas como argumento de
tempo de compilação, que é o que permite reusar as rotas a cada conexão.

## Licença

MIT.
