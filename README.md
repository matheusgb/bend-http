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
| Prepared statement | O protocolo simples já cobre `SELECT` e `INSERT`. Use `Pg.lit` para escapar valor de texto. |
| Keep-alive | Uma request por conexão. |

## Rodar

```bash
curl -fsSL https://bend-lang.com/install.sh | sh   # instala o Bend
bend tests.bend                                    # testes puros
bend PROOF.bend                                    # provas
python3 wire_test.py                               # teste de fio
python3 http_test.py                               # teste de ponta a ponta
bend db_tests.bend                                 # testes contra o Postgres
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

## Consultar o Postgres

`Db.connect` faz login SCRAM-SHA-256. `Db.query` usa o protocolo simples e
devolve `List<&2, List<&2, String>>`: linha por linha, coluna por coluna, tudo
em texto. `NULL` volta como texto vazio, e a v1 não separa os dois. Erro do
servidor vira `Fail` com a mensagem dele, e a conexão continua utilizável.

Veja a rota `/agora` em `example.bend`. Para rodar os testes do banco:

```bash
docker run -d -e POSTGRES_PASSWORD=senha -e POSTGRES_USER=bend \
  -e POSTGRES_DB=bend -p 55432:5432 postgres:16
bend db_tests.bend
```

`PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD` e `PGDATABASE` mudam o alvo.

## Injeção de SQL

A v1 monta query em texto, sem bind de parâmetro. O risco de injeção é seu.
`Pg.lit` cobre o caso comum, que é valor de texto dentro da query:

```python
Db.query(conn, "select * from conta where dono = " ++ Pg.lit(nome))
```

`lit` põe o texto entre aspas simples, dobra a aspa de dentro e descarta o
byte zero, que cortaria a query no meio. A regra vale com
`standard_conforming_strings` ligado, que é o padrão do Postgres desde a 9.1.

`lit` não serve para nome de tabela, nome de coluna nem pedaço de comando.
Para isso, não monte SQL com dado de fora.

## Limites do servidor

| Limite | Valor | Por quê |
| --- | --- | --- |
| Cabeçalho | 8 KB | `String.lines` da Base estoura a pilha perto de 50 KB. 8 KB é o mesmo teto do nginx. |
| Request inteira | 1 MB | Acima disso é cliente enchendo memória, não request. |
| Leituras por conexão | 1024 | Cliente que abre e não termina a request não prende o processo. |

Passar de qualquer um deles devolve 400. Dois `content-length` ou
`transfer-encoding` também devolvem 400: divergência entre o proxy da frente e
este parser é a porta do request smuggling.

## O que o SCRAM verifica

`Db.connect` recusa o servidor que:

- devolve assinatura errada no `SASLFinal`, ou seja, não prova que conhece a
  senha;
- devolve um nonce que não começa com o nonce do cliente.

`scram_test.py` sobe um Postgres falso que tenta os dois, e um terceiro caso
que joga limpo, para o teste não passar por acidente.

## Byte, não caractere

`String` nesta biblioteca é sequência de byte, um char por byte. O `String` do
Bend é sequência de codepoint. Para ASCII os dois coincidem; para o resto, não.

Passe todo texto com acento por `Raw.utf8` antes de mandar:

```python
Db.query(conn, Raw.utf8("select 'ação'"))
Http.text(200, Raw.utf8("não achei"))
```

Sem isso, o `ç` sai como um byte só, e o Postgres recusa a query. O caminho de
volta, byte UTF-8 para codepoint, ainda não existe: ele nasce quando alguma
rota precisar olhar caractere de um corpo acentuado.

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
