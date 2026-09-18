# bend-http -- as provas das leis de LAWS.bend. Rode: bend PROOF.bend
import Base
import ./http.bend as Http
import ./LAWS.bend as Laws

# segs abre os dois lados de uma vez; o par (Con, Nil) tem caso proprio, e ele
# devolve None sem olhar mais nada.
def Laws.no_match_when_path_ends(p, pt, ps):
  {==}

def Laws.no_match_when_pattern_ends(s, st, ps):
  {==}

# Lista de rota vazia cai no primeiro caso de route.pick.
def Laws.empty_router_is_404(method, ss, req):
  {==}
