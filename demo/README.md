# Agenda

Demo de [bend-http](https://github.com/matheusgb/bend-http): uma lista de
tarefas com `GET` e `POST` em cima do Postgres. É o caminho que um projeto
novo em Bend percorre para usar a biblioteca.

Esta pasta vive dentro do repositório da biblioteca, e aqui `lib` é um link
para a raiz dele, para o CI rodar a demo. Num projeto seu, `lib` é um clone,
como o passo 2 abaixo mostra.

## Do zero

```bash
# 1. Bend
curl -fsSL https://bend-lang.com/install.sh | sh

# 2. A biblioteca, ao lado do seu código
mkdir agenda && cd agenda
git clone https://github.com/matheusgb/bend-http lib

# 3. Um Postgres para conversar
docker run -d -e POSTGRES_PASSWORD=senha -e POSTGRES_USER=bend \
  -e POSTGRES_DB=bend -p 55432:5432 postgres:16

# 4. A tabela, e o servidor
bend setup.bend
bend agenda.bend
```

`PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD` e `PGDATABASE` mudam o alvo. Sem
eles, a demo fala com o docker acima.

## Usar

```bash
curl -X POST -d 'titulo=comprar+pao' localhost:8090/tarefas
curl localhost:8090/tarefas
curl localhost:8090/tarefas/1
```

```json
[{"id":"1","titulo":"comprar pao","feito":"f"}]
```

## Testar

```bash
python3 demo_test.py
```

Ele cria a tabela, sobe o servidor e checa o caminho inteiro, incluindo acento,
aspa dentro do JSON e uma tentativa de injeção de SQL que precisa entrar como
dado.

## Binário nativo

```bash
mkdir -p out && bend agenda.bend -o out/agenda && ./out/agenda
```

## O que a demo mostra da biblioteca

| Peça | Onde |
| --- | --- |
| Rota com método e parâmetro | `routes()` em `agenda.bend` |
| Ler campo do corpo do POST | `Http.form(Http.body(r), "titulo")` |
| Escapar valor para o SQL | `Pg.lit(...)` |
| Escapar texto para o JSON | `Http.jstr(...)` |
| Conexão por request | `run` em `agenda.bend` |

A biblioteca não tem pool de conexão: `run` abre, pergunta e fecha. Para carga
de verdade, é o primeiro lugar a mexer.

## Três armadilhas que esta demo já pagou

1. **Não passe `Raw.utf8` em texto que veio do fio.** O corpo da request já
   chega em byte UTF-8. Encodar de novo transforma `ção` em `Ã§Ã£o`. `Raw.utf8`
   é para literal escrito no seu código.
2. **Use `Http.jstr` em todo valor que entra no JSON.** Um título com aspas
   quebra a resposta inteira, e o título vem de fora.
3. **Use `Pg.lit` em todo valor que entra na query.** A v1 não tem prepared
   statement, então o escape é seu.
