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
python3 wire_test.py                               # teste de fio
bend example.bend                                  # sobe o exemplo na 8080
bend example.bend -o out/app                       # binario nativo, precisa de clang
```

## Rigor

- `LAWS.bend` guarda as provas, e o checker recusa lei que não fecha. Ele ainda
  não existe: prova em Bend paga sobre estrutura recursiva (`Nat`, `List`,
  `String`), e trava sobre comparação de `U32` ou literal de texto, que não
  reduzem com valor simbólico. Ele nasce no router, onde a indução é natural.
- `tests.bend` sai com código diferente de zero quando um caso falha.
- `wire_test.py` checa o byte no fio contra um peer que não fala Bend. Teste de
  Bend contra Bend não serve aqui: ida e volta por UTF-8 também é reversível
  entre dois Bend, então ele passaria com o TCP errado.
- O Bend não tem ferramenta de cobertura. O CI checa que todo `def` público
  aparece em `tests.bend`. Isso é cobertura de nome, não de caminho: garante que
  nenhuma função pública ficou sem teste, não que todo ramo foi exercitado.

## Licença

MIT.
