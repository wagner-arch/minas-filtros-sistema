/* ==========================================================================
   ERP Minas Filtros — adapter Supabase
   Imita a superfície do banco do artifact (claude.use("db")) sobre a tabela
   única public.docs(colecao, id, loja, data jsonb, criado_em, atualizado_em).
   O HTML continua chamando col("clientes").limit(500).get(), grava(), etc.

   BIBLIOTECA (verificada em 09/09/2026: HTTP 200, 218 KB, define "var supabase")
   cdnjs NÃO publica o supabase-js — use o jsDelivr abaixo, com a versão fixa:

   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.116.0/dist/umd/supabase.js"></script>
   <script src="supabase/adapter.js"></script>

   COMO USAR (3 linhas — nesta ordem, as duas tags acima ANTES do <script> do sistema):
   1) var db = window.criarDbSupabase("https://SEUPROJETO.supabase.co", "SUA_CHAVE_ANON_PUBLICA");
   2) await db.auth.entrar(email, senha);  var p = await db.perfil();  // p.nome, p.funcao, p.loja
   3) db.lojaPadrao = p.loja;  await carregar();  render();  ouvirPedidos();

   SEGREDO: só a chave "anon public" entra aqui (ela é pública por natureza e vem
   protegida pela RLS). A service_role NUNCA — o adapter recusa e lança erro.

   O QUE ESTE ARQUIVO ENTREGA
   - db.collection(n).limit(N).get()   -> {docs:[{id,exists,data()}], size, empty, forEach, total}
   - db.collection(n).doc(id).set/get/delete
   - db.collection(n).onSnapshot(cb)   -> Realtime; devolve unsubscribe (com reconexão)
   - db.doc("config/empresa").get()    -> {exists:<booleano>, data():<obj|undefined>}
   - db.doc("config/empresa").set(obj)
   - db.auth.entrar/sair/sessao/aoMudar/redefinirSenha
   - db.perfil()                        -> linha de public.perfis do usuário logado
     (traz jornada, ultimo_acesso e consentiu_facial_em — o cartão de ponto precisa)
   - db.perfis(somenteAtivos)           -> a equipe inteira, com jornada
   - db.perfilGravar(linha)             -> upsert em public.perfis (só Administrador passa na RLS)
   - db.registrarAcesso()               -> RPC registrar_acesso (carimba ultimo_acesso)
   - db.registrarConsentimentoFacial()  -> RPC do aceite LGPD (art. 11)
   - db.proximoNumero(loja, tipo)       -> RPC atômica proximo_numero (fim das colisões)
   - EXTENSÕES: get({loja, de, ate}), contar(), exportar() — o HTML antigo ignora.

   DIFERENÇAS PROPOSITAIS EM RELAÇÃO AO BANCO ANTIGO (leia antes de integrar)
   a) TODA falha REJEITA a promise (rede, RLS, sessão expirada). O HTML de hoje
      engole o erro em grava()/apaga(); a correção fica no INTEGRACAO.md.
      O erro traz .ehRLS / .ehSessao / .ehRede e mensagem pronta para o toast.
      DOIS estados alimentam o banner, e eles são diferentes:
        db.online         -> rede/sessão. Volta sozinho quando o servidor responde.
        db.falhaPendente  -> a ÚLTIMA GRAVAÇÃO PERDIDA (inclusive erro de permissão).
                             NÃO some por causa de uma leitura que deu certo: só sai
                             quando a mesma gravação der certo ou o usuário chamar
                             db.reconhecerFalha(). É o banner persistente do item 4.
      db.aoEstado(ok, erro) é chamado nas viradas de (online && !falhaPendente).
   b) Toda leitura de coleção sai PAGINADA (o PostgREST corta em 1000 linhas por
      resposta): limit(2000) de pontos/movest chega inteiro em vez de cortado em 1000.
      ATENÇÃO — limite NÃO é o mesmo que "cabe tudo": quando a coleção tem mais
      documentos que o limite pedido, o adapter traz os MAIS NOVOS (ordena por id
      decrescente, que no id do sistema é ordem de criação) e devolve o array já
      em ordem crescente. O registro de hoje NUNCA fica de fora — quem fica é o
      mais antigo. E o corte é anunciado: snap.truncado + db.aoTruncar(colecao,
      total, trazidos). Sem limite, a leitura sai crescente e completa.
   c) get() devolve também q.total (total real no banco) para a tela poder dizer
      "mostrando 500 de 3.212".
   ========================================================================== */

(function () {
  "use strict";

  var VERSAO_ADAPTER = "1.0.0";
  var TABELA = "docs";
  var PAGINA = 1000; /* teto padrão de linhas por resposta do PostgREST */

  /* ------------------------------------------------------------------------
     MAPAS DO INVENTÁRIO
     campo do documento que vira a coluna docs.loja. null = coleção global
     (catálogo/cadastro compartilhado pelas 3 lojas) — grava loja NULL.
     ---------------------------------------------------------------------- */
  var CAMPO_LOJA = {
    clientes: "loja",
    produtos: null,
    pedidos: "loja",
    orcamentos: "loja",
    atendimentos: "loja",
    fechamentos: "loja",
    ajustes: "loja",
    pontos: "loja",
    caixas: "loja",
    centros: null,
    fornecedores: null,
    titulos: "loja",
    movs: "loja",
    movest: "loja",
    requisicoes: "loja",
    equipamentos: "loja",
    ordens: "loja",
    notas: "loja",
    config: null,
    rh: null,
    facial: null,
    ponto_fotos: "loja"
  };

  /* AS 18 COLEÇÕES DE DADOS DO DIA A DIA — é esta lista (branca, explícita) que
     o backup exporta. "config", "rh", "facial" e "ponto_fotos" ficam FORA de
     propósito: config/usuarios guarda CPF, salário, CTPS/PIS, filhos e a foto
     facial dos 7 colaboradores enquanto o documento antigo não for apagado. */
  var COLECOES_DADOS = [
    "clientes", "produtos", "pedidos", "orcamentos", "atendimentos",
    "fechamentos", "ajustes", "pontos", "caixas", "centros",
    "fornecedores", "titulos", "movs", "movest", "requisicoes",
    "equipamentos", "ordens", "notas"
  ];

  /* documentos de config que o backup NUNCA leva (dado pessoal):
     usuarios   = cadastro antigo com hash de senha, CPF, salário e facial;
     celebracoes = aniversário/data de nascimento de todo mundo. */
  var CONFIG_NAO_EXPORTA = ["usuarios", "celebracoes"];

  /* nomes que alguém pode digitar por engano — o adapter recusa em vez de
     gravar num "primo" da coleção certa (o schema aceita os dois nomes nas
     policies só por segurança; aqui escolhemos UM, no singular). */
  var APELIDOS_PROIBIDOS = { pontos_fotos: "ponto_fotos" };

  /* coleções append-only: gravar é INSERT puro, nunca upsert. "ponto_fotos" é
     assim porque a RLS deixa o colaborador INSERIR a foto da própria batida e
     NÃO deixa atualizar (schema.sql, 8.3) — um upsert em id repetido cairia no
     ON CONFLICT DO UPDATE e levaria 42501, travando a marcação para sempre. */
  var COLECOES_SO_INSERIR = ["ponto_fotos"];

  /* coleções cujo "campo de data" é COMPETÊNCIA 'yyyy-mm' (e não 'yyyy-mm-dd').
     Comparar "2025-03" >= "2025-03-09" dá FALSO e some com o mês inteiro, então
     o filtro de período é truncado para 7 caracteres nessas coleções. */
  var COLECOES_COMPETENCIA = ["fechamentos", "ajustes"];

  /* campo de data usado nos filtros de período (extensão get({de,ate})).
     Compare sempre no MESMO formato do campo: 'yyyy-mm-dd', ou 'yyyy-mm'
     em fechamentos/ajustes (competência — ver COLECOES_COMPETENCIA). */
  var CAMPO_DATA = {
    clientes: "criadoEm",
    produtos: null,
    pedidos: "data",
    orcamentos: "data",
    atendimentos: "data",
    fechamentos: "comp",
    ajustes: "comp",
    pontos: "data",
    caixas: "dataSaldo",
    centros: null,
    fornecedores: "criadoEm",
    titulos: "vencimento",
    movs: "data",
    movest: "data",
    requisicoes: "data",
    equipamentos: "criadoEm",
    ordens: "abertura",
    notas: "emissao",
    config: null,
    ponto_fotos: "data"
  };

  /* coleções com dado pessoal sensível — a RLS já barra, isto é só sinalização
     para quem for ler este arquivo, para o aviso no console e para o backup. */
  var COLECOES_RESTRITAS = ["rh", "facial", "ponto_fotos"];

  /* ------------------------------------------------------------------------
     UTILITÁRIOS
     ---------------------------------------------------------------------- */

  /* id novo quando o chamador não informa (set sem id / doc() sem argumento).
     Mesmo espírito do uid() do HTML: nunca colide na prática. */
  function novoId() {
    try {
      if (typeof crypto !== "undefined" && crypto && typeof crypto.randomUUID === "function") {
        return crypto.randomUUID();
      }
      if (typeof crypto !== "undefined" && crypto && typeof crypto.getRandomValues === "function") {
        var a = new Uint8Array(9), s = "", i;
        crypto.getRandomValues(a);
        for (i = 0; i < a.length; i++) s += a[i].toString(36);
        return Date.now().toString(36) + "-" + s.slice(0, 12);
      }
    } catch (e) { /* segue para o plano B */ }
    return Date.now().toString(36) + Math.random().toString(36).slice(2, 9);
  }

  function ehTexto(v) { return typeof v === "string" && v !== ""; }

  /* loja e nomes de campo/coleção entram em filtros montados à mão (.or, canal do
     Realtime, coluna data->>campo). Valide antes de concatenar. */
  function lojaSegura(v) {
    return ehTexto(v) && /^[A-Za-z0-9_-]{1,40}$/.test(v);
  }
  function nomeSeguro(v) {
    return ehTexto(v) && /^[A-Za-z0-9_]{1,60}$/.test(v);
  }

  /* Erro único do adapter: mensagem em português para a tela + tudo do original
     preservado em .codigo/.original para o console. NUNCA é engolido. */
  function ErroBanco(mensagem, contexto, original) {
    var e = new Error(mensagem);
    e.name = "ErroBanco";
    e.contexto = contexto || "";
    e.original = original || null;
    e.codigo = (original && (original.code || original.status)) || "";
    e.ehRLS = false;
    e.ehSessao = false;
    e.ehRede = false;
    return e;
  }

  /* traduz o erro do PostgREST/GoTrue/fetch para algo que o usuário entenda */
  function traduzir(erro, contexto) {
    var cod = String((erro && (erro.code || erro.status)) || "");
    var msg = String((erro && erro.message) || erro || "");
    var baixa = msg.toLowerCase();
    var e;

    if (cod === "42501" || baixa.indexOf("row-level security") >= 0 || baixa.indexOf("permission denied") >= 0) {
      e = ErroBanco("Sem permissão para " + (contexto || "esta operação") + ".", contexto, erro);
      e.ehRLS = true;
      return e;
    }
    if (cod === "PGRST301" || cod === "401" || baixa.indexOf("jwt") >= 0 || baixa.indexOf("not authenticated") >= 0) {
      e = ErroBanco("Sessão expirada — entre no sistema novamente.", contexto, erro);
      e.ehSessao = true;
      return e;
    }
    if (cod === "23505") {
      return ErroBanco("Registro duplicado em " + (contexto || "docs") + ".", contexto, erro);
    }
    if (baixa.indexOf("failed to fetch") >= 0 || baixa.indexOf("networkerror") >= 0 ||
        baixa.indexOf("load failed") >= 0 || baixa.indexOf("timeout") >= 0) {
      e = ErroBanco("Sem conexão com o servidor — o registro NÃO foi salvo.", contexto, erro);
      e.ehRede = true;
      return e;
    }
    return ErroBanco("Falha no banco (" + (contexto || "docs") + "): " + msg, contexto, erro);
  }

  /* impede que alguém cole a service_role no HTML (ela ignora a RLS) */
  function conferirChave(chave) {
    if (!ehTexto(chave)) throw new Error("criarDbSupabase: informe a chave anon public do projeto.");
    try {
      var partes = chave.split(".");
      if (partes.length === 3) {
        var corpo = JSON.parse(atob(partes[1].replace(/-/g, "+").replace(/_/g, "/")));
        if (corpo && corpo.role === "service_role") {
          throw new Error(
            "criarDbSupabase: essa é a chave SERVICE_ROLE. Ela ignora a RLS e não pode " +
            "ficar num arquivo que o navegador baixa. Use a chave anon public."
          );
        }
      }
    } catch (e) {
      if (e && /SERVICE_ROLE/.test(e.message || "")) throw e; /* só o nosso erro sobe */
    }
    return chave;
  }

  function campoLojaDe(colecao) {
    return Object.prototype.hasOwnProperty.call(CAMPO_LOJA, colecao) ? CAMPO_LOJA[colecao] : "loja";
  }
  function campoDataDe(colecao) {
    return Object.prototype.hasOwnProperty.call(CAMPO_DATA, colecao) ? CAMPO_DATA[colecao] : null;
  }
  function ehCompetencia(colecao) { return COLECOES_COMPETENCIA.indexOf(colecao) >= 0; }
  function soInserir(colecao) { return COLECOES_SO_INSERIR.indexOf(colecao) >= 0; }

  /* recusa o apelido errado (pontos_fotos) antes que ele vire uma segunda
     coleção com metade das fotos e nenhum filtro de data. */
  function conferirNomeColecao(colecao) {
    if (Object.prototype.hasOwnProperty.call(APELIDOS_PROIBIDOS, colecao)) {
      throw ErroBanco(
        "Coleção \"" + colecao + "\" não existe neste sistema — use \"" +
        APELIDOS_PROIBIDOS[colecao] + "\".", colecao, null
      );
    }
    return colecao;
  }

  /* 'yyyy-mm-dd' -> 'yyyy-mm' nas coleções de competência (fechamentos/ajustes) */
  function ajustarLimiteData(colecao, valor) {
    if (!ehTexto(valor)) return valor;
    return ehCompetencia(colecao) ? valor.slice(0, 7) : valor;
  }

  /* ------------------------------------------------------------------------
     FORMATOS DE RETORNO (idênticos aos que o HTML já consome)
     ---------------------------------------------------------------------- */

  /* DocumentSnapshot: exists é PROPRIEDADE booleana (o HTML faz fp.exists&&...),
     data() devolve SEMPRE o mesmo objeto (é chamado 3x na mesma expressão) e
     undefined quando o documento não existe. */
  function fazerDocSnap(id, valor, existe) {
    var conteudo = existe ? (valor && typeof valor === "object" ? valor : {}) : undefined;
    return {
      id: id,
      exists: !!existe,
      data: function () { return conteudo; }
    };
  }

  /* QuerySnapshot: o HTML usa só .docs, mas devolvemos size/empty/forEach por
     compatibilidade, e .total (contagem real no banco) como extensão. */
  function fazerQuerySnap(linhas, total) {
    var docs = linhas.map(function (l) { return fazerDocSnap(l.id, l.data, true); });
    return {
      docs: docs,
      size: docs.length,
      empty: docs.length === 0,
      total: (typeof total === "number" ? total : docs.length),
      truncado: (typeof total === "number" && total > docs.length),
      forEach: function (fn, escopo) { docs.forEach(fn, escopo); }
    };
  }

  /* ------------------------------------------------------------------------
     FÁBRICA
     ---------------------------------------------------------------------- */

  var CACHE_CLIENTES = {}; /* evita 2 clientes GoTrue sobre o mesmo storage */

  function criarDbSupabase(url, chaveAnon, opcoes) {
    if (!window.supabase || typeof window.supabase.createClient !== "function") {
      throw new Error(
        "supabase-js não foi carregado. Ponha a tag <script src=\"https://cdn.jsdelivr.net/npm/" +
        "@supabase/supabase-js@2.116.0/dist/umd/supabase.js\"></script> ANTES de adapter.js."
      );
    }
    if (!ehTexto(url)) throw new Error("criarDbSupabase: informe a URL do projeto (https://xxxx.supabase.co).");
    conferirChave(chaveAnon);
    opcoes = opcoes || {};

    var chaveCache = url + "|" + chaveAnon;
    var sb = CACHE_CLIENTES[chaveCache];
    if (!sb) {
      sb = window.supabase.createClient(url, chaveAnon, {
        auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
        realtime: { params: { eventsPerSecond: 5 } }
      });
      CACHE_CLIENTES[chaveCache] = sb;
    }

    /* db.lojaPadrao é preenchido depois do login (perfil.loja). Serve de rede de
       segurança: documento de coleção com loja que chega sem o campo preenchido
       ainda vai para a loja certa. O gatilho no Postgres faz o mesmo no servidor. */
    var adapter = {
      versao: VERSAO_ADAPTER,
      sb: sb,
      lojaPadrao: opcoes.lojaPadrao || null,
      /* ---- estado, para o banner de falha (INTEGRACAO.md, item 4) --------
         online        = rede/sessão/permissão do servidor. Volta a true sozinho
                         assim que qualquer chamada é respondida.
         falhaPendente = a última GRAVAÇÃO que não entrou (rede, sessão, RLS).
                         NÃO é apagada por uma leitura que deu certo — senão o
                         banner sumiria em segundos por causa do Realtime e o
                         usuário acharia que o pedido foi salvo. Sai quando a
                         MESMA gravação der certo ou em db.reconhecerFalha().
         aoEstado(ok, erro) dispara nas viradas de (online && !falhaPendente). */
      online: true,
      ultimoErro: null,
      falhaPendente: null,
      aoEstado: typeof opcoes.aoEstado === "function" ? opcoes.aoEstado : null,
      /* chamado quando uma leitura com limite deixou documentos para trás:
         aoTruncar(colecao, total, trazidos) — a tela mostra "500 de 3.212". */
      aoTruncar: typeof opcoes.aoTruncar === "function" ? opcoes.aoTruncar : null,
      colecoes: Object.keys(CAMPO_LOJA),
      colecoesDados: COLECOES_DADOS.slice(),
      restritas: COLECOES_RESTRITAS.slice()
    };

    /* "tudo certo" = servidor respondendo E nenhuma gravação perdida em aberto */
    adapter.tudoOk = function () { return !!adapter.online && !adapter.falhaPendente; };

    var okAnterior = true;
    function avaliarEstado(e) {
      var ok = adapter.tudoOk();
      if (ok === okAnterior) return;
      okAnterior = ok;
      if (typeof adapter.aoEstado !== "function") return;
      var motivo = ok ? null : (e ||
        (adapter.falhaPendente && adapter.falhaPendente.erro) ||
        (adapter.ultimoErro && adapter.ultimoErro.erro) || null);
      try { adapter.aoEstado(ok, motivo); } catch (x) { console.warn("aoEstado", x); }
    }

    function definirOnline(ok, e) {
      adapter.online = !!ok;
      avaliarEstado(e);
    }
    /* registra o erro e devolve ele mesmo, para usar como `throw anotar(e)` */
    function anotar(e) {
      adapter.ultimoErro = { quando: new Date().toISOString(), contexto: e.contexto || "", mensagem: e.message, erro: e };
      /* rede e sessão derrubam o estado do servidor. RLS não é queda de servidor,
         mas também não pode passar calado: vira falha pendente (banner aceso). */
      if (e.ehRede || e.ehSessao) definirOnline(false, e);
      else if (e.ehRLS) marcarFalha(e);
      return e;
    }
    /* gravação que não entrou: fica pendurada até dar certo ou ser reconhecida */
    function marcarFalha(e) {
      adapter.falhaPendente = {
        quando: new Date().toISOString(),
        contexto: e.contexto || "",
        mensagem: e.message,
        erro: e
      };
      avaliarEstado(e);
      return e;
    }
    /* a MESMA gravação deu certo (mesmo contexto: "gravar pedidos/abc") */
    function limparFalha(contexto) {
      adapter.ultimoErro = null;
      if (adapter.falhaPendente && adapter.falhaPendente.contexto === contexto) {
        adapter.falhaPendente = null;
      }
      avaliarEstado(null);
    }
    /* o usuário clicou em "entendi" no banner (ou refez o trabalho na mão) */
    adapter.reconhecerFalha = function () {
      adapter.falhaPendente = null;
      avaliarEstado(null);
      return true;
    };
    function estourar(e) { throw anotar(e); }

    /* toda resposta do supabase-js volta como {data,error}: aqui o error vira throw.
       NADA é engolido — é o contrário do grava()/apaga() de hoje.
       ehEscrita=true nas operações que MUDAM o banco: só elas acendem e apagam
       o banner persistente. Leitura que deu certo devolve o "online", nunca
       apaga uma gravação perdida. */
    function conferir(resp, contexto, ehEscrita) {
      if (resp && resp.error) {
        var e = anotar(traduzir(resp.error, contexto));
        if (ehEscrita) marcarFalha(e);
        throw e;
      }
      definirOnline(true, null);
      if (ehEscrita) limparFalha(contexto);
      return resp;
    }

    /* -------------------- monta o SELECT de uma coleção --------------------
       crescente=false traz os documentos MAIS NOVOS primeiro (usado quando há
       limite, para o corte deixar de fora o antigo e não o de hoje). */
    function montarConsulta(colecao, filtros, contar, crescente) {
      var q = sb.from(TABELA).select("id,data", contar ? { count: "exact" } : undefined).eq("colecao", colecao);
      filtros = filtros || {};

      if (ehTexto(filtros.loja)) {
        if (!lojaSegura(filtros.loja)) estourar(ErroBanco("Loja inválida no filtro: " + filtros.loja, colecao, null));
        if (filtros.lojaEstrita) {
          q = q.eq("loja", filtros.loja);
        } else {
          /* espelha o daLoja() do HTML: a loja atual MAIS os documentos globais */
          q = q.or("loja.eq." + filtros.loja + ",loja.is.null");
        }
      }

      var pediuPeriodo = ehTexto(filtros.de) || ehTexto(filtros.ate);
      var campoData = ehTexto(filtros.campoData) ? filtros.campoData : campoDataDe(colecao);
      /* o nome do campo entra na URL como coluna (data->>x): só letras e números */
      if (campoData && !nomeSeguro(campoData)) {
        estourar(ErroBanco("Campo de data inválido: " + campoData, colecao, null));
      }
      /* pedir período numa coleção sem campo de data mapeado NÃO pode devolver a
         coleção inteira em silêncio (era assim que um get({de:hoje,ate:hoje}) em
         ponto_fotos trazia todas as fotos JPEG já batidas). Estoura. */
      if (pediuPeriodo && !campoData) {
        estourar(ErroBanco(
          "A coleção \"" + colecao + "\" não tem campo de data mapeado: o filtro de " +
          "período seria ignorado. Informe {campoData:\"...\"} ou tire de/ate.", colecao, null
        ));
      }
      if (campoData && pediuPeriodo) {
        /* comparação de TEXTO em ISO. Os dois lados precisam estar no MESMO
           formato: 'yyyy-mm-dd' na maioria e 'yyyy-mm' na competência de
           fechamentos/ajustes ("2025-03" >= "2025-03-09" é FALSO e apagaria o
           mês inteiro). ajustarLimiteData() trunca quando é competência.
           Documento SEM o campo fica de fora do período — de propósito. */
        var de = ajustarLimiteData(colecao, filtros.de);
        var ate = ajustarLimiteData(colecao, filtros.ate);
        if (ehTexto(de)) q = q.gte("data->>" + campoData, de);
        if (ehTexto(ate)) q = q.lte("data->>" + campoData, ate);
      }

      /* ordem fixa: sem ela o .range() da paginação pode repetir/pular linhas.
         (id é a 2ª coluna da chave primária, então sai do índice, de graça.)
         O id do sistema começa com Date.now().toString(36), então ordem de id é
         ordem de criação: decrescente = mais novos primeiro. */
      return q.order("id", { ascending: crescente !== false });
    }

    /* -------------------- lê a coleção inteira, paginando ------------------
       O PostgREST devolve no máximo ~1000 linhas por resposta; limit(2000) de
       pontos/movest e limit(1000) de titulos/movs vinham cortados. Aqui a
       primeira página traz o count exato e o laço busca o resto por .range().

       QUANDO HÁ LIMITE a leitura é feita do MAIS NOVO para o mais antigo e o
       resultado é invertido no fim. Motivo: o id nasce de Date.now(), então
       ordenar por id crescente é ordenar do mais antigo para o mais novo — com
       limit(500) numa coleção de 3.000 documentos, a venda de hoje não voltava
       no F5 seguinte e sumia do Contas a Receber, da comissão e da agenda.
       Com o limite atingido e ainda havendo documentos, avisa por aoTruncar(). */
    async function buscarColecao(colecao, limite, filtros) {
      var alvo = (typeof limite === "number" && limite > 0) ? limite : Infinity;
      var crescente = !isFinite(alvo);  /* sem limite: crescente e completo */
      var linhas = [], total = null, offset = 0, guarda = 0;

      while (linhas.length < alvo) {
        var tam = Math.min(PAGINA, alvo - linhas.length);
        var q = montarConsulta(colecao, filtros, offset === 0, crescente).range(offset, offset + tam - 1);
        var r = conferir(await q, "ler " + colecao);
        var lote = r.data || [];
        if (offset === 0 && typeof r.count === "number") total = r.count;

        linhas = linhas.concat(lote);
        if (!lote.length) break;                                  /* acabou */
        offset += lote.length;
        if (total !== null && linhas.length >= total) break;       /* pegou tudo */
        if (total === null && lote.length < tam) break;            /* sem count: heurística */
        if (++guarda > 200) break;                                 /* trava anti-laço infinito */
      }

      /* veio do mais novo para o mais antigo: devolve na ordem de sempre */
      if (!crescente) linhas.reverse();

      var snap = fazerQuerySnap(linhas, total === null ? linhas.length : total);
      if (snap.truncado && typeof adapter.aoTruncar === "function") {
        try { adapter.aoTruncar(colecao, snap.total, snap.size); }
        catch (e) { console.warn("aoTruncar", e); }
      }
      if (snap.truncado) {
        console.warn("[adapter] " + colecao + ": carregados os " + snap.size +
          " mais recentes de " + snap.total + " no banco (limite da tela).");
      }
      return snap;
    }

    async function buscarDoc(colecao, id) {
      var r = conferir(
        await sb.from(TABELA).select("data").eq("colecao", colecao).eq("id", id).maybeSingle(),
        "ler " + colecao + "/" + id
      );
      /* documento inexistente: exists=false e data()===undefined (o HTML testa isso) */
      if (!r.data) return fazerDocSnap(id, undefined, false);
      return fazerDocSnap(id, r.data.data, true);
    }

    /* -------------------- grava (upsert integral, sem merge) ---------------
       ops.upsert === false força INSERT puro (coleção append-only). As coleções
       de COLECOES_SO_INSERIR já são insert por padrão. */
    async function gravarDoc(colecao, id, obj, ops) {
      if (obj === null || typeof obj !== "object") {
        estourar(ErroBanco("set() precisa de um objeto em " + colecao + ".", colecao, null));
      }
      /* id é obrigatório: gravar com id inventado cria documento órfão, que
         nunca mais é achado por id e é regravado num id diferente na próxima vez.
         Quem quer id automático usa add(). */
      var idFinal = ehTexto(id) ? id : (ehTexto(obj.id) ? obj.id : null);
      if (!ehTexto(idFinal)) {
        estourar(ErroBanco("set() sem id em " + colecao + " — informe doc(id) ou use add().", colecao, null));
      }

      var corpo = {};
      Object.keys(obj).forEach(function (k) { if (obj[k] !== undefined) corpo[k] = obj[k]; });
      corpo.id = idFinal; /* o HTML sempre espera obj.id === id do documento */

      var campo = campoLojaDe(colecao);
      var loja = null;
      if (campo) loja = ehTexto(corpo[campo]) ? corpo[campo] : (ehTexto(adapter.lojaPadrao) ? adapter.lojaPadrao : null);

      var linha = { colecao: colecao, id: idFinal, loja: loja, data: corpo };
      var contexto = "gravar " + colecao + "/" + idFinal;
      var apenasInserir = (ops && typeof ops.upsert === "boolean") ? !ops.upsert : soInserir(colecao);

      if (apenasInserir) {
        var r = await sb.from(TABELA).insert(linha);
        /* id repetido numa coleção append-only = o documento JÁ ESTÁ gravado.
           É o caso da foto de ponto reenviada porque o registro de "pontos"
           falhou: a foto certa já está no banco, então isto é sucesso, não erro.
           (Com upsert seria ON CONFLICT DO UPDATE e a RLS mataria a batida.) */
        if (r && r.error && String(r.error.code || "") === "23505") {
          limparFalha(contexto);
          return idFinal;
        }
        conferir(r, contexto, true);
        return idFinal;
      }

      conferir(
        await sb.from(TABELA).upsert(linha, { onConflict: "colecao,id" }),
        contexto,
        true
      );
      return idFinal;
    }

    async function apagarDoc(colecao, id) {
      /* sem id não há o que apagar: um delete de id vazio resolveria em silêncio
         e a tela diria "apagado" sem ter apagado nada. */
      if (!ehTexto(id)) {
        estourar(ErroBanco("delete() sem id em " + colecao + ".", colecao, null));
      }
      /* apagar id que existe no banco ou não resolve igual (o HTML conta com isso) */
      conferir(
        await sb.from(TABELA).delete().eq("colecao", colecao).eq("id", id),
        "apagar " + colecao + "/" + id,
        true
      );
    }

    /* -------------------- Realtime (onSnapshot) ---------------------------
       Assina postgres_changes em public.docs filtrado por colecao=eq.<nome> e,
       a cada evento, REFAZ o get() completo e chama o callback com a coleção
       inteira — que é exatamente o que ouvirPedidos() espera. Simples, e não
       depende de reconstruir estado a partir de deltas.
       Reconecta sozinho (backoff 1s→30s) e, ao reconectar, força um recarregamento
       porque eventos podem ter sido perdidos enquanto o socket estava caído. */
    var seqCanal = 0;

    function assinarColecao(colecao, cb, opcoesAssin) {
      /* o nome vai concatenado no filtro do canal ("colecao=eq.<nome>") */
      if (!nomeSeguro(colecao)) estourar(ErroBanco("Coleção inválida para Realtime: " + colecao, colecao, null));
      opcoesAssin = opcoesAssin || {};
      var aoFalhar = typeof opcoesAssin.aoFalhar === "function" ? opcoesAssin.aoFalhar : null;
      var filtros = opcoesAssin.filtros || null;
      var limite = typeof opcoesAssin.limite === "number" ? opcoesAssin.limite : null;

      var vivo = true, canal = null, timerRetry = null, espera = 1000;
      var buscando = false, refazer = false, timerJunta = null;
      /* trocando = estamos derrubando o canal velho de propósito. O
         removeChannel() dispara o callback do canal antigo com "CLOSED" e, sem
         esta trava, esse CLOSED agendaria um novo retry — o canal saudável que
         acabou de entrar seria derrubado 1s depois, para sempre, e cada
         reconexão refaria a leitura COMPLETA da coleção. */
      var trocando = false;

      /* uma entrada de NF dispara 50+ eventos seguidos; junta a rajada num get só */
      function agendarRecarga() {
        if (!vivo || timerJunta) return;
        timerJunta = setTimeout(function () { timerJunta = null; recarregar(); }, 150);
      }

      async function recarregar() {
        if (!vivo) return;
        if (buscando) { refazer = true; return; }   /* junta rajadas num get só */
        buscando = true;
        try {
          var snap = await buscarColecao(colecao, limite, filtros);
          if (vivo) { try { cb(snap); } catch (e) { console.warn("onSnapshot callback " + colecao, e); } }
        } catch (e) {
          anotar(e);
          if (aoFalhar) { try { aoFalhar(e); } catch (e2) { /* ignora */ } }
          else console.warn("onSnapshot " + colecao, e);
        } finally {
          buscando = false;
          if (refazer && vivo) { refazer = false; recarregar(); }
        }
      }

      function agendarRetry() {
        if (!vivo || timerRetry) return;
        timerRetry = setTimeout(function () {
          timerRetry = null;
          espera = Math.min(espera * 2, 30000);
          abrirCanal();
        }, espera);
      }

      function fecharCanal() {
        if (!canal) return;
        trocando = true;
        try { sb.removeChannel(canal); } catch (e) { /* ignora */ }
        canal = null;
        trocando = false;
      }

      function abrirCanal() {
        if (!vivo) return;
        fecharCanal();
        var meuCanal = sb.channel("docs:" + colecao + ":" + (++seqCanal));
        canal = meuCanal;
        meuCanal.on(
          "postgres_changes",
          { event: "*", schema: "public", table: TABELA, filter: "colecao=eq." + colecao },
          function () { if (meuCanal === canal) agendarRecarga(); }
        );
        meuCanal.subscribe(function (status, err) {
          /* callback de canal já substituído: ignora (senão o CLOSED do canal
             velho derruba o novo e a reconexão vira laço de 1 em 1 segundo) */
          if (!vivo || meuCanal !== canal) return;
          if (status === "SUBSCRIBED") {
            espera = 1000;
            recarregar(); /* estado atual na entrada e depois de cada reconexão */
          } else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
            if (err) anotar(traduzir(err, "realtime " + colecao));
            agendarRetry();
          } else if (status === "CLOSED") {
            /* fechamento nosso (troca de canal / cancelar) não pede retry */
            if (!trocando) agendarRetry();
          }
        });
      }

      /* voltou da aba dormindo / voltou a internet: o socket pode ter perdido eventos */
      function aoVoltar() { if (vivo && (!document.hidden)) agendarRecarga(); }
      window.addEventListener("online", aoVoltar);
      document.addEventListener("visibilitychange", aoVoltar);

      abrirCanal();

      /* devolve o unsubscribe (o HTML de hoje ignora — o INTEGRACAO.md manda
         guardar para cancelar no sairSistema e ao trocar de loja) */
      return function cancelar() {
        vivo = false;
        if (timerRetry) { clearTimeout(timerRetry); timerRetry = null; }
        if (timerJunta) { clearTimeout(timerJunta); timerJunta = null; }
        window.removeEventListener("online", aoVoltar);
        document.removeEventListener("visibilitychange", aoVoltar);
        fecharCanal();
      };
    }

    /* -------------------- referências (a superfície que o HTML usa) -------- */

    /* doc(id) SEM id (undefined, null ou "") vira uma referência VAZIA: dá para
       ler (devolve exists:false, como o Firestore devolve para id inexistente,
       e é isso que `col("facial").doc((usuarioPor(x)||{}).id||"")` espera), mas
       gravar ou apagar nela estoura. Antes o adapter inventava um id: o registro
       entrava no banco num id aleatório, nunca mais era achado, e a gravação
       seguinte criava OUTRO; e o delete "dava certo" sem apagar nada. */
    function refDoc(colecao, id) {
      var idRef = ehTexto(id) ? id : null;
      var vazia = idRef === null;
      /* REJEITA a promise (não estoura solto): quem chama está em `await ... catch` */
      function semId(acao) {
        return Promise.reject(anotar(ErroBanco(
          acao + "() sem id em " + colecao + " — o documento não tem identificador.",
          colecao, null
        )));
      }
      return {
        id: idRef || "",
        vazia: vazia,
        colecao: colecao,
        path: colecao + "/" + (idRef || ""),
        get: function () {
          if (vazia) return Promise.resolve(fazerDocSnap("", undefined, false));
          return buscarDoc(colecao, idRef);
        },
        set: function (obj, ops) {
          if (vazia) return semId("set");
          return gravarDoc(colecao, idRef, obj, ops);
        },
        delete: function () {
          if (vazia) return semId("delete");
          return apagarDoc(colecao, idRef);
        },
        /* atalhos que o HTML não usa hoje, mas que evitam surpresa se alguém tentar */
        update: function (obj, ops) {
          if (vazia) return semId("update");
          return gravarDoc(colecao, idRef, obj, ops);
        },
        onSnapshot: function () {
          throw ErroBanco("onSnapshot de documento não implementado — assine a coleção.", colecao, null);
        }
      };
    }

    function refColecao(colecao) {
      if (!ehTexto(colecao)) throw new Error("collection(): informe o nome da coleção.");
      conferirNomeColecao(colecao); /* recusa "pontos_fotos" (o certo é ponto_fotos) */

      function comLimite(n) {
        var limite = (typeof n === "number" && n > 0) ? Math.floor(n) : null;
        return {
          /* get() aceita os filtros opcionais {loja, de, ate, lojaEstrita, campoData} */
          get: function (filtros) { return buscarColecao(colecao, limite, filtros); },
          limit: function (m) { return comLimite(m); },
          onSnapshot: function (cb, seg) {
            return refColecao(colecao).onSnapshot(cb, seg, limite);
          }
        };
      }

      return {
        id: colecao,
        limit: comLimite,
        doc: function (id) { return refDoc(colecao, id); },
        get: function (filtros) { return buscarColecao(colecao, null, filtros); },
        /* onSnapshot(cb) — como no Firestore, o 2º argumento pode ser a função de
           erro OU um objeto {filtros, limite, aoFalhar}. */
        onSnapshot: function (cb, seg, limitePrevio) {
          if (typeof cb !== "function") throw new Error("onSnapshot(): informe a função de callback.");
          var op = {};
          if (typeof seg === "function") op.aoFalhar = seg;
          else if (seg && typeof seg === "object") op = seg;
          if (limitePrevio && op.limite == null) op.limite = limitePrevio;
          return assinarColecao(colecao, cb, op);
        },
        /* não implementados de propósito: o inventário confirma que o HTML não usa.
           Melhor um erro claro do que "undefined is not a function". */
        where: function () {
          throw ErroBanco("where() não existe neste adapter — use get({loja, de, ate}).", colecao, null);
        },
        orderBy: function () {
          throw ErroBanco("orderBy() não existe — a leitura já sai ordenada por id.", colecao, null);
        },
        /* add() é o ÚNICO lugar que inventa id (set()/delete() exigem um) */
        add: function (obj, ops) { return refDoc(colecao, novoId()).set(obj, ops); }
      };
    }

    /* db.doc("config/empresa") — o HTML só usa caminhos com uma barra.
       Aceita caminho mais fundo quebrando na ÚLTIMA barra. */
    function refCaminho(caminho) {
      if (!ehTexto(caminho)) throw new Error("doc(): informe o caminho, ex.: \"config/empresa\".");
      var corte = caminho.lastIndexOf("/");
      if (corte <= 0 || corte === caminho.length - 1) {
        throw new Error("doc(\"" + caminho + "\"): o caminho precisa ser \"colecao/id\".");
      }
      return refDoc(conferirNomeColecao(caminho.slice(0, corte)), caminho.slice(corte + 1));
    }

    /* -------------------- Auth ------------------------------------------- */
    adapter.auth = {
      /* rejeita com mensagem genérica: não dizemos se o e-mail existe */
      entrar: async function (email, senha) {
        if (!ehTexto(email) || !ehTexto(senha)) {
          throw anotar(ErroBanco("Informe e-mail e senha.", "login", null));
        }
        var r = await sb.auth.signInWithPassword({ email: String(email).trim(), password: senha });
        if (r.error) {
          var baixa = String(r.error.message || "").toLowerCase();
          if (baixa.indexOf("invalid login") >= 0 || baixa.indexOf("invalid_credentials") >= 0) {
            throw anotar(ErroBanco("E-mail ou senha inválidos.", "login", r.error));
          }
          if (baixa.indexOf("email not confirmed") >= 0) {
            throw anotar(ErroBanco("E-mail ainda não confirmado — abra o convite que enviamos.", "login", r.error));
          }
          throw anotar(traduzir(r.error, "login"));
        }
        return r.data; /* {user, session} */
      },
      sair: async function () {
        var r = await sb.auth.signOut();
        if (r && r.error) throw anotar(traduzir(r.error, "sair"));
        return true;
      },
      sessao: async function () {
        var r = await sb.auth.getSession();
        if (r && r.error) throw anotar(traduzir(r.error, "sessão"));
        return (r && r.data && r.data.session) || null;
      },
      usuario: async function () {
        var s = await adapter.auth.sessao();
        return (s && s.user) || null;
      },
      /* devolve a função para cancelar a escuta */
      aoMudar: function (cb) {
        if (typeof cb !== "function") throw new Error("aoMudar(): informe a função de callback.");
        var r = sb.auth.onAuthStateChange(function (evento, sessao) {
          try { cb(evento, sessao); } catch (e) { console.warn("aoMudar", e); }
        });
        return function () {
          try { r.data.subscription.unsubscribe(); } catch (e) { /* ignora */ }
        };
      },
      /* substitui o botão "zerar senha" do cadastro de colaborador */
      redefinirSenha: async function (email, urlRetorno) {
        var op = ehTexto(urlRetorno) ? { redirectTo: urlRetorno } : undefined;
        var r = await sb.auth.resetPasswordForEmail(String(email || "").trim(), op);
        if (r && r.error) throw anotar(traduzir(r.error, "redefinir senha"));
        return true;
      },
      /* usado na tela que o próprio colaborador abre pelo link do e-mail */
      trocarSenha: async function (novaSenha) {
        var r = await sb.auth.updateUser({ password: novaSenha });
        if (r && r.error) throw anotar(traduzir(r.error, "trocar senha"));
        return true;
      }
    };

    /* -------------------- perfil (public.perfis) --------------------------
       O "nome" desta tabela é a MESMA string que o HTML usa em vendedor,
       colaborador, criadoPor, metas[nome] etc. Trocar o nome aqui renomeia a
       pessoa no sistema inteiro — cuidado. */
    adapter.perfil = async function (userId) {
      var id = userId;
      if (!ehTexto(id)) {
        var s = await adapter.auth.sessao();
        if (!s || !s.user) return null; /* sem sessão: sem perfil, sem erro */
        id = s.user.id;
      }
      /* jornada, ultimo_acesso e consentiu_facial_em PRECISAM vir:
         - jornada: sem ela o cartão de ponto usa a jornada padrão para todo
           mundo, calcula atraso/falta com o horário errado e erra o prêmio de
           assiduidade (dinheiro); quem tem bateponto:"nao" volta a ser cobrado.
         - consentiu_facial_em: sem ele o termo LGPD reaparece em TODA batida.
         - ultimo_acesso: a tela de usuários mostra "nunca acessou" sem ele. */
      var r = conferir(
        await sb.from("perfis")
          .select("user_id,nome,funcao,loja,ativo,jornada,ultimo_acesso,consentiu_facial_em,criado_em")
          .eq("user_id", id).maybeSingle(),
        "ler perfil"
      );
      return r.data || null;
    };

    /* toda a equipe (alimenta USUARIOS/EQUIPE no lugar de config/usuarios).
       jornada vai junto: é ela que o cartão de ponto usa em jornadaDe(nome). */
    adapter.perfis = async function (somenteAtivos) {
      var q = sb.from("perfis").select("user_id,nome,funcao,loja,ativo,jornada").order("nome", { ascending: true });
      if (somenteAtivos !== false) q = q.eq("ativo", true);
      var r = conferir(await q, "ler perfis");
      return r.data || [];
    };

    /* -------------------- numeração atômica -------------------------------
       Fim do pedidos.filter(...).length+20801: o número sai de uma linha
       travada no Postgres, então dois vendedores nunca recebem o mesmo. */
    adapter.proximoNumero = async function (loja, tipo) {
      if (!ehTexto(loja) || !ehTexto(tipo)) {
        throw anotar(ErroBanco("proximoNumero(loja, tipo): os dois são obrigatórios.", "numeracao", null));
      }
      var r = conferir(
        await sb.rpc("proximo_numero", { p_loja: loja, p_tipo: tipo }),
        "gerar número de " + tipo,
        true /* muda o banco: entra no controle do banner */
      );
      var n = (r && r.data !== null && r.data !== undefined) ? Number(r.data) : NaN;
      if (!isFinite(n)) throw anotar(ErroBanco("O banco não devolveu o próximo número de " + tipo + ".", "numeracao", null));
      return n;
    };

    /* -------------------- extensões úteis --------------------------------- */

    /* total real no banco — para a tela dizer "mostrando 500 de 3.212" */
    adapter.contar = async function (colecao, filtros) {
      var q = sb.from(TABELA).select("id", { count: "exact", head: true }).eq("colecao", colecao);
      if (ehTexto(filtros && filtros.loja)) {
        if (!lojaSegura(filtros.loja)) estourar(ErroBanco("Loja inválida no filtro.", colecao, null));
        q = filtros.lojaEstrita ? q.eq("loja", filtros.loja) : q.or("loja.eq." + filtros.loja + ",loja.is.null");
      }
      var r = conferir(await q, "contar " + colecao);
      return r.count || 0;
    };

    /* backup diário: devolve {colecao:[documentos]} pronto para virar JSON */
    adapter.exportar = async function (filtros) {
      var saida = {}, nomes = adapter.colecoes.filter(function (c) {
        return COLECOES_RESTRITAS.indexOf(c) < 0; /* RH e biometria ficam de fora */
      });
      for (var i = 0; i < nomes.length; i++) {
        var snap = await buscarColecao(nomes[i], null, filtros);
        saida[nomes[i]] = snap.docs.map(function (d) { var o = d.data() || {}; o.id = d.id; return o; });
      }
      return saida;
    };

    /* uma ida ao banco só para saber se ele responde (banner de falha) */
    adapter.testar = async function () {
      conferir(await sb.from(TABELA).select("id", { count: "exact", head: true }).eq("colecao", "config"), "testar conexão");
      return true;
    };

    /* -------------------- superfície principal ---------------------------- */
    adapter.collection = refColecao;
    adapter.doc = refCaminho;
    adapter.campoLojaDe = campoLojaDe;
    adapter.campoDataDe = campoDataDe;

    /* Opcional: deixa o boot antigo (db=await claude.use("db")) funcionar sem
       edição. Prefira trocar a linha 10924 do HTML — está no INTEGRACAO.md. */
    adapter.instalarAtalhoClaude = function () {
      window.claude = window.claude || {};
      window.claude.use = async function (nome) {
        if (nome === "db") return adapter;
        throw new Error("claude.use(\"" + nome + "\") não existe fora do artifact.");
      };
      return adapter;
    };

    return adapter;
  }

  window.criarDbSupabase = criarDbSupabase;
})();
