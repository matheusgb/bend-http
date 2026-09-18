# bend-http -- as leis. Aqui fica o que a biblioteca promete; a prova fica em
# PROOF.bend. `bend PROOF.bend` e o portao: ele falha enquanto uma lei estiver
# aberta ou falsa.
#
# O que da para provar barato aqui e o que anda sobre estrutura recursiva:
# lista de segmento, Nat, String. Comparacao de U32 e literal de texto nao
# reduzem com valor simbolico, entao aquilo fica por teste.
import Base
import ./http.bend as Http

# LEI: padrao com mais segmentos que o caminho nunca casa. /users/:id nao
# responde /users.
law no_match_when_path_ends:
  for p: String
  for pt: List<&2, String>
  for ps: Map<&2, String>
  {Http.segs(Con{p, pt}, Nil{}, ps) == None{} : Maybe<&2, Map<&2, String>>}

# LEI: caminho com mais segmentos que o padrao nunca casa. /users nao responde
# /users/7.
law no_match_when_pattern_ends:
  for s: String
  for st: List<&2, String>
  for ps: Map<&2, String>
  {Http.segs(Nil{}, Con{s, st}, ps) == None{} : Maybe<&2, Map<&2, String>>}

# LEI: router sem rota responde 404, seja qual for a request.
law empty_router_is_404:
  for method: String
  for ss: List<&2, String>
  for req: Http.Req
  {Http.route.pick(Nil{}, method, ss, req) ==
    IO.pure(Http.Res, Http.text(404, "nao encontrado")) : IO(Http.Res)}
