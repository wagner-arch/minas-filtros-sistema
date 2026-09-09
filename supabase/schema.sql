-- =====================================================================
-- ERP/CRM MINAS FILTROS - ESQUEMA SUPABASE (Postgres)
-- Arquivo: supabase/schema.sql
-- Como usar: abra o painel do Supabase > SQL Editor > New query,
--            cole ESTE arquivo inteiro e clique em Run. Uma vez so.
-- Idempotente: pode ser executado de novo sem quebrar nada
--            (create ... if not exists / create or replace /
--             drop policy if exists antes de create policy).
-- Projeto: regiao Sao Paulo (sa-east-1).
--
-- O QUE ESTE ARQUIVO CRIA
--   1. Extensoes
--   2. Tabela public.docs        - todos os documentos do sistema (jsonb)
--   3. Tabela public.perfis      - quem e cada usuario autenticado
--   4. Tabela public.numeradores - contadores de pedido/orcamento/OS
--   5. Funcoes auxiliares (meu_nome, minha_funcao, minha_loja...)
--   6. Triggers (atualizado_em, copia da loja, id coerente,
--               numerador que nao retrocede)
--   7. Indices - inclusive os UNICOS que impedem numero repetido (7.1)
--   8. RLS + policies (comuns, config, pontos, restritas)
--   9. RPC proximo_numero / registrar_acesso / contar_docs
--  10. Publicacao Realtime
--  11. Bloco COMENTADO de semente (numeradores e primeiro perfil)
--
-- DEPOIS DE RODAR ESTE ARQUIVO, no painel:
--   * Authentication > Providers: deixe so "Email"; desligue
--     "Enable email signups" (as contas sao criadas por convite).
--     ISTO NAO E OPCIONAL: a anon key fica dentro do HTML, que roda no
--     navegador de qualquer um. Com o cadastro ligado, um desconhecido
--     cria a propria conta e vira "authenticated" - as policies exigem
--     PERFIL ATIVO (public.perfis), entao ele nao le nada de docs, mas o
--     cadastro aberto continua sendo uma porta que nao precisa existir.
--   * Ao DESLIGAR um colaborador nao basta perfis.ativo = false: isso
--     corta o acesso a docs na hora, mas o token dele vale ate uma hora e
--     o refresh token se renova sozinho. Revogue a sessao em
--     Authentication > Users > (o usuario) > Sign out, ou banir.
--   * Project Settings > API: o teto padrao de linhas por resposta
--     (max-rows) e 1000. Ou eleve esse numero, ou o adapter pagina com
--     .range() - as cargas de pontos e movest passam de 1000 linhas.
--
-- NAO HA NENHUM DADO REAL NESTE ARQUIVO.
-- =====================================================================


-- =====================================================================
-- 1. EXTENSOES
-- ---------------------------------------------------------------------
-- pgcrypto: gen_random_uuid() e funcoes de hash (o Supabase ja costuma
-- deixar instalada no schema "extensions"; o if not exists evita erro).
-- =====================================================================
-- O bloco DO evita que o script inteiro morra na primeira linha caso a
-- extensao ja exista em outro schema ou o papel nao possa instalar.
do $blk$
begin
  create extension if not exists pgcrypto with schema extensions;
exception
  when others then
    raise notice 'pgcrypto nao instalada agora (%). O schema funciona sem ela.', sqlerrm;
end;
$blk$;


-- =====================================================================
-- 2. TABELA public.docs
-- ---------------------------------------------------------------------
-- Tabela generica que substitui TODAS as colecoes do banco antigo
-- (clientes, produtos, pedidos, orcamentos, atendimentos, fechamentos,
--  ajustes, pontos, caixas, centros, fornecedores, titulos, movs,
--  movest, requisicoes, equipamentos, ordens, notas, config, rh,
--  remuneracao, ponto_fotos, facial...).
--
--   colecao  = nome da colecao (o que o HTML passa em db.collection(x)
--              e a primeira parte de db.doc("config/empresa"))
--   id       = id do documento (uid() do HTML, "p0".."p7", "mf-2026-08",
--              "empresa", "usuarios"...)
--   loja     = "mf" | "wf" | "dv" | NULL (NULL = documento global,
--              compartilhado pelas 3 lojas: produtos, centros,
--              fornecedores, config/*)
--   data     = o objeto JavaScript inteiro, do jeito que o HTML grava
--   criado_em / atualizado_em = mantidos por trigger, o cliente nao mexe
--
-- Chave primaria (colecao, id): e exatamente a chave que o adapter usa
-- no upsert de set() e no delete().
-- =====================================================================
create table if not exists public.docs (
  colecao       text        not null,
  id            text        not null,
  loja          text,
  data          jsonb       not null default '{}'::jsonb,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint docs_pk primary key (colecao, id),
  constraint docs_colecao_nao_vazia check (btrim(colecao) <> '' and length(colecao) <= 64),
  constraint docs_id_nao_vazio      check (btrim(id) <> ''      and length(id) <= 128)
);

-- Colunas adicionadas em versoes posteriores do schema entram aqui,
-- para que reexecutar o arquivo atualize uma tabela que ja existe.
alter table public.docs add column if not exists loja          text;
alter table public.docs add column if not exists criado_em     timestamptz not null default now();
alter table public.docs add column if not exists atualizado_em timestamptz not null default now();

comment on table  public.docs is 'Documento generico do ERP Minas Filtros: uma linha por doc de cada colecao.';
comment on column public.docs.colecao is 'Nome da colecao (clientes, pedidos, config, rh, ponto_fotos...).';
comment on column public.docs.loja is 'Id da loja (mf/wf/dv). NULL = documento global das 3 lojas.';
comment on column public.docs.data is 'Objeto completo gravado pelo HTML (mesmo formato de antes).';


-- =====================================================================
-- 3. TABELA public.perfis
-- ---------------------------------------------------------------------
-- Liga o usuario do Supabase Auth (auth.users) ao colaborador do
-- sistema. O campo "nome" TEM QUE SER IDENTICO ao nome que o HTML usa
-- dentro dos registros (pedido.vendedor, ponto.colaborador,
-- atendimento.colaborador, titulo.por, cliente.criadoPor, metas[nome]...),
-- porque o historico inteiro e indexado por nome.
--   Exemplos de nome: "Wagner", "Erico", "Carol" (o mesmo texto do
--   antigo config/usuarios).
--
--   funcao = nome da funcao/perfil ("Administrador", "Financeiro",
--            "Gerente", "Vendedor", "Prospector", "Instalador",
--            "Estoquista") - casa com a lista de docs colecao='config',
--            id='funcoes'.
--   loja   = loja padrao do colaborador; quem tem a acao "verTudo"
--            pode trocar de loja no cabecalho.
--
-- Campos extras (nao sensiveis) para o sistema nao precisar abrir a
-- colecao restrita "rh" no dia a dia:
--   jornada  = {entrada, almocoIni, almocoFim, saida, tolerancia, bateponto}
--   ultimo_acesso        = carimbo do ultimo login (gravado por RPC)
--   consentiu_facial_em  = consentimento LGPD para foto facial (art. 11)
-- Dados sensiveis de RH (CPF, RG, CTPS, filhos, endereco) NAO ficam
-- aqui: vao para docs com colecao='rh' (um doc por user_id).
-- Salario, vale refeicao e o valor dos premios ficam em
-- colecao='remuneracao' (tambem um doc por user_id) - separados de 'rh'
-- porque o proprio colaborador precisa ler os DELE para os KPIs do Cartao
-- de Ponto, enquanto CPF e CTPS continuam so para o gestor.
-- =====================================================================
create table if not exists public.perfis (
  user_id             uuid        primary key references auth.users (id) on delete cascade,
  nome                text        not null,
  funcao              text        not null,
  loja                text,
  ativo               boolean     not null default true,
  jornada             jsonb       not null default '{}'::jsonb,
  ultimo_acesso       timestamptz,
  consentiu_facial_em timestamptz,
  criado_em           timestamptz not null default now(),
  atualizado_em       timestamptz not null default now(),
  constraint perfis_nome_nao_vazio   check (btrim(nome) <> ''),
  constraint perfis_funcao_nao_vazia check (btrim(funcao) <> '')
);

alter table public.perfis add column if not exists jornada             jsonb       not null default '{}'::jsonb;
alter table public.perfis add column if not exists ultimo_acesso       timestamptz;
alter table public.perfis add column if not exists consentiu_facial_em timestamptz;
alter table public.perfis add column if not exists atualizado_em       timestamptz not null default now();

-- O nome e chave de negocio: dois colaboradores nao podem ter o mesmo
-- nome, senao o historico (ponto, comissao, metas) mistura as pessoas.
-- Indice unico (em vez de constraint) porque "if not exists" funciona.
create unique index if not exists ux_perfis_nome on public.perfis (lower(btrim(nome)));
create index        if not exists ix_perfis_loja on public.perfis (loja) where ativo;

comment on table public.perfis is 'Colaborador autenticado: nome (chave do historico), funcao, loja e jornada.';


-- =====================================================================
-- 4. TABELA public.numeradores
-- ---------------------------------------------------------------------
-- Contador atomico por loja e por tipo de documento. Substitui os
-- contadores calculados no navegador (array.filter(loja).length + base),
-- que colidiam entre dois usuarios, reusavam numero apos exclusao e
-- congelavam quando o limit de carga era atingido.
--   tipo: 'pedido' (base 20801), 'orcamento' (1001), 'os' (3001),
--         'cliente' (1001, vira MF-01002...), 'fornecedor' (1001)
--   loja: 'mf' | 'wf' | 'dv' para os tipos por loja, e '*' para os tipos
--         GLOBAIS. Hoje so 'fornecedor' e global: a colecao fornecedores
--         e um catalogo unico das 3 lojas e o codigo FOR-xxxx e
--         sequencial nele inteiro; com um contador por loja, mf, wf e dv
--         emitiriam FOR-1002 para tres fornecedores diferentes. Quem
--         troca a loja por '*' e a propria RPC (item 9.1), para o adapter
--         nao precisar conhecer a regra.
--   ultimo = ULTIMO numero JA usado. A RPC devolve ultimo+1.
--         O trigger do item 6 impede que este valor DIMINUA.
-- =====================================================================
create table if not exists public.numeradores (
  loja          text        not null,
  tipo          text        not null,
  ultimo        integer     not null default 0,
  atualizado_em timestamptz not null default now(),
  constraint numeradores_pk primary key (loja, tipo),
  constraint numeradores_ultimo_positivo check (ultimo >= 0)
);

alter table public.numeradores add column if not exists atualizado_em timestamptz not null default now();

comment on table public.numeradores is 'Contadores sequenciais por loja/tipo. So a RPC proximo_numero escreve aqui.';


-- =====================================================================
-- 5. FUNCOES AUXILIARES (usadas dentro das policies)
-- ---------------------------------------------------------------------
-- As que leem public.perfis (meu_nome, minha_funcao, minha_loja,
-- sou_gestor_rh, eh_meu_documento) sao SECURITY DEFINER + STABLE: rodam
-- com o dono do schema, por isso conseguem ler perfis sem cair na RLS da
-- propria perfis (evita recursao infinita de policy). search_path fixo
-- (public, pg_temp) para nao dar para sequestrar a funcao com uma tabela
-- plantada em outro schema.
-- As de classificacao (colecao_restrita, colecao_geral, base_numerador,
-- tipo_numerador_*) sao IMMUTABLE puras: nao leem tabela nenhuma, o
-- planner as inlineia e elas nao custam nada por linha.
--
-- ATENCAO ao usa-las em policy: funcao com SET search_path nunca e
-- inlineada, entao chamada direta vira uma execucao POR LINHA varrida.
-- Nas policies do item 8 elas aparecem sempre como (select public.f()),
-- que o planner avalia uma vez por comando (InitPlan).
-- =====================================================================

-- Nome do colaborador logado (o mesmo texto gravado nos documentos).
create or replace function public.meu_nome()
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select p.nome
    from public.perfis p
   where p.user_id = auth.uid()
     and p.ativo
   limit 1;
$fn$;

-- Funcao/perfil do usuario logado ('Administrador', 'Vendedor'...).
create or replace function public.minha_funcao()
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select p.funcao
    from public.perfis p
   where p.user_id = auth.uid()
     and p.ativo
   limit 1;
$fn$;

-- Loja padrao do usuario logado (pode ser NULL para quem ve tudo).
create or replace function public.minha_loja()
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select p.loja
    from public.perfis p
   where p.user_id = auth.uid()
     and p.ativo
   limit 1;
$fn$;

-- Tem acesso aos dados restritos de RH/biometria?
-- Regra fechada: apenas Administrador e Financeiro.
create or replace function public.sou_gestor_rh()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select coalesce(public.minha_funcao() in ('Administrador','Financeiro'), false);
$fn$;

-- E uma colecao restrita (dados de RH ou biometria)?
--   rh           -> CPF, RG, endereco, filhos, CTPS, PIS
--   remuneracao  -> salario, VR e valores dos premios (um doc por user_id).
--                   Separada de 'rh' de proposito: o PROPRIO colaborador
--                   precisa ler a dele (os KPIs "Salario fixo", "Vale
--                   refeicao" e "Total do mes" do Cartao de Ponto, HTML
--                   renderPonto/totalRemuneracao), enquanto CPF, RG e CTPS
--                   continuam so para o gestor. Ver a policy
--                   docs_select_minha_remuneracao no item 8.1.
--   ponto_fotos  -> foto JPEG de cada batida do cartao de ponto
--   pontos_fotos -> mesmo conteudo; os dois nomes ficam na lista porque
--                   o inventario usa o plural em um trecho. O adapter
--                   deve escolher UM e usar sempre o mesmo.
--   facial       -> foto facial de referencia + assinatura de luz
-- 'pontos' NAO entra nesta lista porque o proprio colaborador precisa
-- gravar a batida dele; a protecao dela (geolocalizacao, assinatura
-- facial, atestado) esta nas policies dedicadas do item 8.5.
create or replace function public.colecao_restrita(p_colecao text)
returns boolean
language sql
immutable
as $fn$
  select p_colecao in ('rh','remuneracao','ponto_fotos','pontos_fotos','facial');
$fn$;

-- E uma colecao "comum" (sem regra propria)? Serve as policies gerais.
-- Ficam de fora, alem das restritas:
--   config -> matriz de permissoes (config/funcoes), faixas de comissao e
--             coeficientes de forma de pagamento. E a configuracao do
--             sistema, nao dado operacional: so gestor grava (item 8.6).
--   pontos -> folha de ponto. Cada um grava a sua, o gestor ajusta e
--             ninguem le a do colega (item 8.5).
create or replace function public.colecao_geral(p_colecao text)
returns boolean
language sql
immutable
as $fn$
  select not public.colecao_restrita(p_colecao)
     and p_colecao not in ('config','pontos');
$fn$;

-- O documento pertence ao proprio usuario logado?
-- Aceita as duas formas de autoria que o HTML grava:
--   data->>'nome' / data->>'colaborador' (nome, padrao antigo)
--   data->>'colaboradorId' / data->>'id' (user_id, padrao novo)
--
-- Esta funcao e avaliada UMA VEZ POR LINHA (o argumento depende da linha),
-- por isso e escrita em plpgsql com variaveis: as comparacoes que NAO
-- tocam public.perfis vem primeiro e, quando elas resolvem, nem chega a
-- consultar a tabela. Na versao anterior, em SQL, meu_nome() era chamada
-- DUAS vezes por linha - dois selects em perfis para cada linha varrida.
create or replace function public.eh_meu_documento(p_data jsonb)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_uid  text;
  v_nome text;
begin
  if p_data is null then
    return false;
  end if;

  v_uid := auth.uid()::text;
  if v_uid is not null
     and (p_data->>'colaboradorId' = v_uid or p_data->>'id' = v_uid) then
    return true;                    -- resolveu sem ler public.perfis
  end if;

  v_nome := public.meu_nome();      -- uma unica leitura de perfis por linha
  if v_nome is null then
    return false;
  end if;

  return coalesce(p_data->>'nome'        = v_nome, false)
      or coalesce(p_data->>'colaborador' = v_nome, false);
end;
$fn$;

-- Base inicial de cada tipo de numeracao, usada apenas quando o
-- contador ainda nao foi semeado (mantem o mesmo ponto de partida do
-- sistema antigo, para nao repetir numero ja emitido).
create or replace function public.base_numerador(p_tipo text)
returns integer
language sql
immutable
as $fn$
  select case p_tipo
           when 'pedido'     then 20801
           when 'orcamento'  then 1001
           when 'os'         then 3001
           when 'cliente'    then 1001
           when 'fornecedor' then 1001
           else 1
         end;
$fn$;

-- Tipos de numeracao VALIDOS. Fora desta lista, proximo_numero recusa:
-- um tipo digitado errado cairia no "else 1" de base_numerador e
-- recomecaria a numeracao do 1 sem nenhum aviso.
create or replace function public.tipo_numerador_valido(p_tipo text)
returns boolean
language sql
immutable
as $fn$
  select p_tipo in ('pedido','orcamento','os','cliente','fornecedor');
$fn$;

-- Tipos cujo contador e UNICO para as 3 lojas.
-- 'fornecedor' e o caso de hoje: a colecao fornecedores e global (documento
-- sem loja, catalogo compartilhado) e o codigo FOR-xxxx e sequencial no
-- catalogo inteiro (HTML: "FOR-"+String(fornecedores.length+1001), sem
-- filtro de loja). Se cada loja tivesse o seu contador, mf, wf e dv
-- emitiriam FOR-1002 para tres fornecedores diferentes.
-- proximo_numero troca a loja por '*' nestes tipos, para o adapter poder
-- continuar chamando proximoNumero(lojaAtual, 'fornecedor') sem saber da
-- regra. Se um dia produto ou centro de custo ganhar codigo sequencial,
-- acrescente o tipo AQUI e em tipo_numerador_valido.
create or replace function public.tipo_numerador_global(p_tipo text)
returns boolean
language sql
immutable
as $fn$
  select p_tipo in ('fornecedor');
$fn$;


-- =====================================================================
-- 6. TRIGGERS
-- ---------------------------------------------------------------------
-- a) mantem atualizado_em e protege criado_em de sobrescrita do cliente
-- b) copia a loja de data->>'loja' quando o app nao mandar a coluna
-- c) garante que data->>'id' seja igual a coluna id (o HTML sempre
--    grava obj.id = id do doc; se vier divergente, o servidor corrige)
-- d) impede que um numerador ande para tras (numero ja emitido nao volta)
-- =====================================================================
create or replace function public.docs_antes_de_gravar()
returns trigger
language plpgsql
as $fn$
begin
  -- (b) loja: se o adapter nao mandou, tira do proprio documento.
  if new.loja is null or btrim(new.loja) = '' then
    new.loja := nullif(btrim(coalesce(new.data->>'loja','')), '');
  end if;

  -- (c) id coerente dentro do jsonb.
  if new.data is null then
    new.data := '{}'::jsonb;
  end if;
  if coalesce(new.data->>'id','') <> new.id then
    new.data := jsonb_set(new.data, '{id}', to_jsonb(new.id), true);
  end if;

  -- (a) carimbos de tempo sao do servidor, nunca do navegador.
  if tg_op = 'INSERT' then
    new.criado_em := now();
  else
    new.criado_em := old.criado_em;
  end if;
  new.atualizado_em := now();

  return new;
end;
$fn$;

drop trigger if exists tg_docs_antes_de_gravar on public.docs;
create trigger tg_docs_antes_de_gravar
  before insert or update on public.docs
  for each row execute function public.docs_antes_de_gravar();

-- Mesmo carimbo para perfis.
create or replace function public.perfis_antes_de_gravar()
returns trigger
language plpgsql
as $fn$
begin
  new.nome := btrim(new.nome);
  if tg_op = 'INSERT' then
    new.criado_em := now();
  else
    new.criado_em := old.criado_em;
  end if;
  new.atualizado_em := now();
  return new;
end;
$fn$;

drop trigger if exists tg_perfis_antes_de_gravar on public.perfis;
create trigger tg_perfis_antes_de_gravar
  before insert or update on public.perfis
  for each row execute function public.perfis_antes_de_gravar();

-- Numerador NUNCA anda para tras. Isto e uma trava fisica contra a causa
-- mais provavel de numero repetido depois da migracao: rodar o bloco de
-- semente 11.2 uma segunda vez (na semana seguinte, ao cadastrar a loja
-- dv, ao reconferir a carga) com os valores anotados no papel na data da
-- migracao - o contador ja avancou e o "ultimo" antigo o rebaixaria.
-- Vale tambem para um UPDATE manual errado no painel.
-- Se em algum caso legitimo for MESMO preciso baixar o contador:
--   alter table public.numeradores disable trigger tg_numeradores_antes_de_gravar;
--   update public.numeradores set ultimo = <valor> where loja='mf' and tipo='pedido';
--   alter table public.numeradores enable  trigger tg_numeradores_antes_de_gravar;
create or replace function public.numeradores_antes_de_gravar()
returns trigger
language plpgsql
as $fn$
begin
  if tg_op = 'UPDATE' and new.ultimo < old.ultimo then
    raise exception 'Numerador nao retrocede: %/% ja esta em % e a gravacao tentou %. Numero ja emitido nao pode ser reusado.',
      old.loja, old.tipo, old.ultimo, new.ultimo
      using errcode = '23514';
  end if;
  new.atualizado_em := now();
  return new;
end;
$fn$;

drop trigger if exists tg_numeradores_antes_de_gravar on public.numeradores;
create trigger tg_numeradores_antes_de_gravar
  before insert or update on public.numeradores
  for each row execute function public.numeradores_antes_de_gravar();


-- =====================================================================
-- 7. INDICES
-- ---------------------------------------------------------------------
-- A chave primaria (colecao, id) ja atende o get/set/delete por id.
-- Os indices abaixo atendem as duas cargas que o adapter faz:
--   1) tudo de uma colecao numa loja            -> (colecao, loja)
--   2) uma colecao numa loja dentro de um periodo -> indices parciais
--      por colecao sobre o campo de data que AQUELA colecao usa.
-- Os campos de data sao textos ISO (yyyy-mm-dd ou yyyy-mm), entao a
-- comparacao alfabetica funciona como comparacao cronologica.
-- =====================================================================

create index if not exists ix_docs_colecao_loja on public.docs (colecao, loja);

-- Busca por conteudo dentro do jsonb (ex.: data @> '{"clienteId":"..."}').
--
-- ATENCAO A OPCLASS - jsonb_path_ops, NAO o padrao jsonb_ops.
-- O padrao (gin (data), sem opclass) indexa CADA chave e CADA valor
-- escalar como uma entrada separada, e uma entrada de GIN nao pode passar
-- de ~2712 bytes (BLCKSZ/3): o insert morre com
--   ERROR: index row size N exceeds maximum 2712 for index "ix_docs_data_gin".
-- Os documentos deste sistema tem exatamente isso: a foto da batida de
-- ponto e a foto facial sao dataURL JPEG em base64 de 6 a 10 KB (e base64
-- de JPEG nao comprime, entao o TOAST/pglz nao salva), e os anexos de
-- pedido idem. Como o indice nasce com a tabela vazia, o script rodaria
-- sem erro no SQL Editor e a falha so apareceria em producao, na primeira
-- batida de ponto com foto - e ninguem mais bateria ponto.
-- jsonb_path_ops guarda um hash de caminho+valor (int32), nao tem limite
-- de tamanho, e continua atendendo @>, @? e @@ (perde so o operador "?"
-- de existencia de chave, que o adapter nao usa).
--
-- Hoje NENHUMA consulta do adapter usa containment (so .eq/.or/.gte/.lte
-- sobre data->>campo), entao este indice ainda e custo de escrita sem
-- beneficio de leitura. Ele fica aqui pronto para a primeira consulta que
-- precisar dele; se quiser economizar escrita ate la, apague com
--   drop index if exists public.ix_docs_data_gin;
-- O bloco DO so derruba o indice se ele existir com a opclass ERRADA
-- (versao anterior deste schema): assim reexecutar o arquivo numa base ja
-- carregada nao reconstroi um GIN gigante a toa.
do $blk$
declare v_opclass text;
begin
  select oc.opcname into v_opclass
    from pg_index i
    join pg_class c on c.oid = i.indexrelid
    join pg_opclass oc on oc.oid = i.indclass[0]
   where c.relname = 'ix_docs_data_gin'
     and c.relnamespace = 'public'::regnamespace;

  if v_opclass is not null and v_opclass <> 'jsonb_path_ops' then
    raise notice 'ix_docs_data_gin estava com a opclass % (estoura em foto base64); recriando com jsonb_path_ops.', v_opclass;
    execute 'drop index public.ix_docs_data_gin';
  end if;

  execute 'create index if not exists ix_docs_data_gin on public.docs using gin (data jsonb_path_ops)';
end;
$blk$;

-- Indices parciais por colecao + campo de data (ver inventario):
create index if not exists ix_docs_clientes_criadoem  on public.docs (loja, (data->>'criadoEm'))   where colecao = 'clientes';
create index if not exists ix_docs_pedidos_data       on public.docs (loja, (data->>'data'))       where colecao = 'pedidos';
create index if not exists ix_docs_orcamentos_data    on public.docs (loja, (data->>'data'))       where colecao = 'orcamentos';
create index if not exists ix_docs_atendimentos_data  on public.docs (loja, (data->>'data'))       where colecao = 'atendimentos';
create index if not exists ix_docs_fechamentos_comp   on public.docs (loja, (data->>'comp'))       where colecao = 'fechamentos';
create index if not exists ix_docs_ajustes_comp       on public.docs (loja, (data->>'comp'))       where colecao = 'ajustes';
create index if not exists ix_docs_pontos_data        on public.docs (loja, (data->>'data'))       where colecao = 'pontos';
create index if not exists ix_docs_caixas_datasaldo   on public.docs (loja, (data->>'dataSaldo'))  where colecao = 'caixas';
create index if not exists ix_docs_fornecedores_criadoem on public.docs ((data->>'criadoEm'))      where colecao = 'fornecedores';
create index if not exists ix_docs_titulos_vencimento on public.docs (loja, (data->>'vencimento')) where colecao = 'titulos';
create index if not exists ix_docs_movs_data          on public.docs (loja, (data->>'data'))       where colecao = 'movs';
create index if not exists ix_docs_movest_data        on public.docs (loja, (data->>'data'))       where colecao = 'movest';
create index if not exists ix_docs_requisicoes_data   on public.docs (loja, (data->>'data'))       where colecao = 'requisicoes';
create index if not exists ix_docs_equipamentos_criadoem on public.docs (loja, (data->>'criadoEm')) where colecao = 'equipamentos';
create index if not exists ix_docs_ordens_abertura    on public.docs (loja, (data->>'abertura'))   where colecao = 'ordens';
create index if not exists ix_docs_notas_emissao      on public.docs (loja, (data->>'emissao'))    where colecao = 'notas';

-- Indices de apoio a regras de negocio que hoje so existem no navegador
-- (e por isso falham quando a lista em memoria vem truncada):
--   ponto do dia por colaborador
create index if not exists ix_docs_pontos_colab_data  on public.docs (loja, (data->>'colaborador'), (data->>'data')) where colecao = 'pontos';
--   fotos de ponto do proprio colaborador
create index if not exists ix_docs_pontofotos_nome    on public.docs ((data->>'nome'), (data->>'data')) where colecao in ('ponto_fotos','pontos_fotos');

-- ---------------------------------------------------------------------
-- 7.1 INDICES UNICOS - a rede de protecao da numeracao
-- ---------------------------------------------------------------------
-- Indice NAO-UNICO nao impede nada: ele acelera a consulta que o
-- navegador nem faz. Quem garante que dois pedidos nao saiam com o mesmo
-- numero e o UNIQUE. Sem ele, basta esquecer a semente 11.2 depois de
-- importar o historico para o primeiro pedido novo sair como 20801 e
-- duplicar em silencio ~250 numeros de venda - exatamente o defeito que
-- esta migracao existe para matar.
--
-- Sao indices PARCIAIS: valem so para a colecao citada e so quando o
-- campo esta preenchido (documento antigo sem numero nao trava a carga).
--
-- IMPORTANTE - se um destes falhar, e porque JA existe duplicidade nos
-- dados importados. O bloco DO transforma o erro em NOTICE para nao
-- derrubar (e reverter) o schema inteiro; a consulta que lista os
-- duplicados esta no item 11.5.
--
-- Efeito no gerador de demonstracao: ele cria orcamentos com numero fixo
-- (1001..1005 por loja), entao rodar o gerador duas vezes na mesma loja
-- passa a dar erro 23505 na segunda em vez de duplicar calado. Rode
-- limparDemo() antes de gerar de novo - e, em producao, o gerador nem
-- deve aparecer (item 5 do INTEGRACAO.md).
do $blk$
declare
  v_ddl text;
  v_lista text[] := array[
    -- pedido: um numero por loja
    'create unique index if not exists ux_docs_pedidos_numero on public.docs (loja, (data->>''numero'')) where colecao = ''pedidos'' and (data->>''numero'') is not null',
    -- orcamento: um numero por loja
    'create unique index if not exists ux_docs_orcamentos_numero on public.docs (loja, (data->>''numero'')) where colecao = ''orcamentos'' and (data->>''numero'') is not null',
    -- ordem de servico: um numero por loja
    'create unique index if not exists ux_docs_ordens_numero on public.docs (loja, (data->>''numero'')) where colecao = ''ordens'' and (data->>''numero'') is not null',
    -- nota de fornecedor: o mesmo numero so entra uma vez por fornecedor
    -- (substitui o ix_docs_notas_forn_numero, que era so um indice de busca)
    'create unique index if not exists ux_docs_notas_forn_numero on public.docs (loja, (data->>''fornecedorId''), (data->>''numero'')) where colecao = ''notas'' and (data->>''numero'') is not null',
    -- equipamento: numero de serie nao se repete na loja
    -- (substitui o ix_docs_equipamentos_serie)
    'create unique index if not exists ux_docs_equip_serie on public.docs (loja, (data->>''serie'')) where colecao = ''equipamentos'' and nullif(data->>''serie'','''') is not null',
    -- cliente: o codigo MF-01002 nao se repete na loja
    'create unique index if not exists ux_docs_clientes_codigo on public.docs (loja, (data->>''codigo'')) where colecao = ''clientes'' and nullif(data->>''codigo'','''') is not null',
    -- fornecedor: o codigo FOR-xxxx e global (catalogo das 3 lojas)
    'create unique index if not exists ux_docs_fornecedores_codigo on public.docs ((data->>''codigo'')) where colecao = ''fornecedores'' and nullif(data->>''codigo'','''') is not null'
  ];
begin
  foreach v_ddl in array v_lista loop
    begin
      execute v_ddl;
    exception
      when others then
        raise notice 'Indice unico NAO criado (%). Ha duplicidade nos dados: veja o item 11.5, corrija e rode este comando de novo: %', sqlerrm, v_ddl;
    end;
  end loop;
end;
$blk$;

-- Os antigos ix_docs_equipamentos_serie e ix_docs_notas_forn_numero
-- viraram os unicos acima (mesmas colunas, agora com garantia). Se a base
-- veio de uma execucao anterior deste arquivo, apague os duplicados:
drop index if exists public.ix_docs_equipamentos_serie;
drop index if exists public.ix_docs_notas_forn_numero;


-- =====================================================================
-- 8. RLS (Row Level Security) E POLICIES
-- ---------------------------------------------------------------------
-- Principio: o anon (chave publica que fica dentro do HTML) NAO enxerga
-- nada. Todo acesso exige sessao autenticada COM PERFIL ATIVO.
--
-- Quatro grupos de colecao, cada um com o seu conjunto de policies:
--   a) comuns    (colecao_geral)    clientes, pedidos, titulos, produtos,
--                                   movest... todo mundo le e grava; so a
--                                   gestao apaga (8.4).
--   b) config                       matriz de permissoes e parametros
--                                   financeiros. Todos leem (o boot
--                                   precisa), so gestor grava (8.6).
--   c) pontos                       folha de ponto. Cada um le e grava a
--                                   SUA batida do dia; o gestor le e
--                                   ajusta todas (8.5).
--   d) restritas (colecao_restrita) rh, remuneracao, facial e as fotos de
--                                   ponto. So Administrador/Financeiro,
--                                   com duas excecoes de dono: a foto da
--                                   propria batida e o proprio
--                                   contracheque.
--
-- Policies do Postgres sao PERMISSIVAS por padrao: quando ha varias para
-- o mesmo comando, o acesso e liberado se QUALQUER uma aceitar. Por isso
-- cada policy abaixo cobre um caso e nada mais - e por isso as exclusoes
-- (colecao_geral tira 'config' e 'pontos') precisam estar em TODAS as
-- policies gerais, nao so em uma.
--
-- DESEMPENHO: toda chamada de funcao aparece como (select public.f()).
-- meu_nome(), minha_funcao(), minha_loja() e sou_gestor_rh() sao SECURITY
-- DEFINER com SET search_path, e funcao com SET nunca e inlineada pelo
-- planner: escrita direta, ela seria executada UMA VEZ POR LINHA varrida
-- - um select em public.perfis para cada linha de docs, que numa base com
-- anos de titulos, movest e pontos vira centenas de milhares de
-- subconsultas (o alerta auth_rls_initplan do Performance Advisor do
-- Supabase). Dentro de um (select ...) sem correlacao com a linha, o
-- planner vira InitPlan e avalia UMA vez por comando.
-- eh_meu_documento(data) e a unica que nao sai do por-linha, porque
-- depende da linha; por isso foi reescrita em plpgsql (item 5), com as
-- comparacoes baratas primeiro e no maximo UMA leitura de perfis.
--
-- ISOLAMENTO POR LOJA - o que este arquivo NAO faz:
-- a decisao de projeto e "authenticated le e escreve docs", entao os
-- dados das 3 lojas sao um pote so. Com a sessao dela e um GET direto na
-- API (sem passar por tela nenhuma), a vendedora de Divinopolis le
-- clientes, titulos, ajustes e movs das outras duas lojas, e grava
-- documento carimbado com a loja alheia. E uma escolha consciente, nao um
-- esquecimento. Para fechar, basta acrescentar esta linha ao using e ao
-- with check de cada policy geral:
--   and (loja is null
--        or loja = (select public.minha_loja())
--        or (select public.minha_funcao()) in ('Administrador','Financeiro'))
-- O adapter ja consulta com .or("loja.eq.<x>,loja.is.null"), entao o
-- cliente nao mudaria uma linha. A clausula ja esta valendo no DELETE
-- (8.4), que e o comando destrutivo.
-- =====================================================================

alter table public.docs        enable row level security;
alter table public.perfis      enable row level security;
alter table public.numeradores enable row level security;

-- Nao usamos "force row level security" de proposito: o dono da tabela
-- (o papel postgres, que o SQL Editor usa) e o service_role (Edge
-- Functions) precisam continuar passando por cima da RLS para semear o
-- primeiro Administrador, criar contas e rodar manutencao. Quem chega
-- pelo navegador e sempre anon ou authenticated, e esses obedecem.

-- Privilegios de tabela (a RLS filtra as linhas; o grant abre a porta).
revoke all on public.docs        from anon, public;
revoke all on public.perfis      from anon, public;
revoke all on public.numeradores from anon, public;

grant select, insert, update, delete on public.docs   to authenticated;
grant select                         on public.perfis to authenticated;
grant insert, update, delete         on public.perfis to authenticated;  -- so o Administrador passa pela policy
grant select                         on public.numeradores to authenticated;

-- ---------------------------------------------------------------------
-- 8.1 docs - SELECT
-- ---------------------------------------------------------------------
drop policy if exists docs_select_geral on public.docs;
create policy docs_select_geral on public.docs
  for select to authenticated
  using (
    public.colecao_geral(colecao)
    and (select public.meu_nome()) is not null      -- precisa ter perfil ativo
  );

-- config e lido por todo mundo: o boot carrega formas_pagamento, funcoes,
-- tipos de atendimento e metas antes de desenhar qualquer tela. Quem
-- GRAVA config e outra historia (8.6).
drop policy if exists docs_select_config on public.docs;
create policy docs_select_config on public.docs
  for select to authenticated
  using (
    colecao = 'config'
    and (select public.meu_nome()) is not null
  );

drop policy if exists docs_select_restrita_gestor on public.docs;
create policy docs_select_restrita_gestor on public.docs
  for select to authenticated
  using (
    public.colecao_restrita(colecao)
    and (select public.sou_gestor_rh())
  );

-- O colaborador le as SUAS fotos de ponto e a SUA foto facial de
-- referencia (a camera precisa comparar). Nunca as dos colegas.
-- 'rh' fica de fora de proposito: CPF, RG, CTPS e endereco so para gestor.
drop policy if exists docs_select_minha_biometria on public.docs;
create policy docs_select_minha_biometria on public.docs
  for select to authenticated
  using (
    colecao in ('ponto_fotos','pontos_fotos','facial')
    and public.eh_meu_documento(data)
  );

-- O colaborador le o PROPRIO contracheque.
-- Sem isto, os KPIs "Salario fixo", "Vale refeicao" e "Total do mes" que
-- o Cartao de Ponto mostra para o proprio colaborador (renderPonto ->
-- totalRemuneracao) apareceriam ZERADOS para quem nao e gestor - e um
-- numero errado apresentado como verdade e pior do que uma negativa de
-- acesso. A colecao 'remuneracao' (um doc por user_id com salario, vr,
-- assiduidade e desempenho) existe exatamente para isso: da para liberar
-- o contracheque sem abrir 'rh', que tem CPF, RG, CTPS e filhos.
-- Escrita continua so para sou_gestor_rh() (8.2/8.3, colecao restrita).
-- INTEGRACAO.md: totalRemuneracao, premioAssiduidade e premioDesempenho
-- devem ler 'remuneracao', nao 'rh'.
drop policy if exists docs_select_minha_remuneracao on public.docs;
create policy docs_select_minha_remuneracao on public.docs
  for select to authenticated
  using (
    colecao = 'remuneracao'
    and public.eh_meu_documento(data)
  );

-- ---------------------------------------------------------------------
-- 8.2 docs - INSERT
-- ---------------------------------------------------------------------
drop policy if exists docs_insert_geral on public.docs;
create policy docs_insert_geral on public.docs
  for insert to authenticated
  with check (
    public.colecao_geral(colecao)
    and (select public.meu_nome()) is not null
  );

drop policy if exists docs_insert_restrita_gestor on public.docs;
create policy docs_insert_restrita_gestor on public.docs
  for insert to authenticated
  with check (
    public.colecao_restrita(colecao)
    and (select public.sou_gestor_rh())
  );

-- Excecao pedida: a propria batida de ponto. O colaborador insere a foto
-- dele mesmo, identificada por data->>'nome' (ou colaboradorId).
drop policy if exists docs_insert_meu_ponto_foto on public.docs;
create policy docs_insert_meu_ponto_foto on public.docs
  for insert to authenticated
  with check (
    colecao in ('ponto_fotos','pontos_fotos')
    and public.eh_meu_documento(data)
  );

-- ---------------------------------------------------------------------
-- 8.3 docs - UPDATE
-- ---------------------------------------------------------------------
-- Obs.: o adapter grava com upsert (insert ... on conflict do update),
-- entao regravar um doc existente exige INSERT **e** UPDATE liberados.
drop policy if exists docs_update_geral on public.docs;
create policy docs_update_geral on public.docs
  for update to authenticated
  using (
    public.colecao_geral(colecao)
    and (select public.meu_nome()) is not null
  )
  with check (
    public.colecao_geral(colecao)
    and (select public.meu_nome()) is not null
  );

drop policy if exists docs_update_restrita_gestor on public.docs;
create policy docs_update_restrita_gestor on public.docs
  for update to authenticated
  using      (public.colecao_restrita(colecao) and (select public.sou_gestor_rh()))
  with check (public.colecao_restrita(colecao) and (select public.sou_gestor_rh()));

-- Regravar a foto da PROPRIA batida.
-- A ideia original era "batida registrada nao se altera", mas o adapter
-- grava SEMPRE por upsert e o id da foto e deterministico
-- (fotoId = <id do ponto> + "_" + marcacao). No insert ... on conflict do
-- update o Postgres cobra as policies de UPDATE quando a linha ja existe,
-- e as unicas eram as de gestor: a rede cai depois do commit e o
-- navegador reenvia, ou a pessoa refaz a mesma marcacao, e o segundo
-- envio morre com "new row violates row-level security policy" (42501).
-- Como o erro agora propaga ate a tela (INTEGRACAO.md item 4), a batida
-- simplesmente nao acontecia mais naquele dia. O colaborador so sobrescreve
-- a foto DELE; o ajuste da folha continua sendo do gestor (8.5).
drop policy if exists docs_update_meu_ponto_foto on public.docs;
create policy docs_update_meu_ponto_foto on public.docs
  for update to authenticated
  using      (colecao in ('ponto_fotos','pontos_fotos') and public.eh_meu_documento(data))
  with check (colecao in ('ponto_fotos','pontos_fotos') and public.eh_meu_documento(data));

-- ---------------------------------------------------------------------
-- 8.4 docs - DELETE
-- ---------------------------------------------------------------------
-- A policy geral de delete era larga demais. Com "qualquer autenticado
-- apaga qualquer colecao comum", uma sessao de vendedora mais a anon key
-- que esta dentro do HTML apagavam o ERP inteiro num round-trip:
--   DELETE /rest/v1/docs?colecao=eq.pedidos
--   DELETE /rest/v1/docs?colecao=eq.titulos
-- O PostgREST aceita filtro por qualquer coluna, nao exige id - e nao ha
-- log, lixeira nem exclusao logica para desfazer.
-- O HTML legitimo so apaga em tres pontos: centro de custo, estorno de
-- movimento de caixa e a limpeza dos dados de demonstracao.
drop policy if exists docs_delete_geral on public.docs;  -- substituida pelas duas abaixo

-- (a) o que o app apaga no dia a dia, por qualquer perfil ativo
drop policy if exists docs_delete_operacional on public.docs;
create policy docs_delete_operacional on public.docs
  for delete to authenticated
  using (
    colecao in ('centros','movs')
    and (select public.meu_nome()) is not null
  );

-- (b) todo o resto: so quem responde pela loja, e so na propria loja
-- (o Administrador passa em qualquer uma). E aqui que minha_loja() entra
-- de verdade; se um dia o isolamento por loja for estendido as demais
-- policies, esta e a clausula a copiar.
drop policy if exists docs_delete_gestao on public.docs;
create policy docs_delete_gestao on public.docs
  for delete to authenticated
  using (
    public.colecao_geral(colecao)
    and (select public.minha_funcao()) in ('Administrador','Financeiro','Gerente')
    and (loja is null
         or loja = (select public.minha_loja())
         or (select public.minha_funcao()) = 'Administrador')
  );

drop policy if exists docs_delete_restrita_gestor on public.docs;
create policy docs_delete_restrita_gestor on public.docs
  for delete to authenticated
  using (public.colecao_restrita(colecao) and (select public.sou_gestor_rh()));

-- Efeito colateral esperado: limparDemo(), que apaga os documentos
-- demo:true de varias colecoes, passa a exigir Administrador, Financeiro
-- ou Gerente. Combina com o item 5 do INTEGRACAO.md (esconder o gerador
-- de demonstracao em producao).
-- Isto reduz o estrago, mas nao impede um delete em massa DENTRO do que a
-- policy libera (um Gerente ainda apaga todos os pedidos da propria
-- loja). Teto por requisicao nao e schema, e configuracao de projeto:
-- Project Settings > API (max-rows / max-affected do PostgREST).

-- ---------------------------------------------------------------------
-- 8.5 docs - FOLHA DE PONTO (colecao 'pontos')
-- ---------------------------------------------------------------------
-- Por que 'pontos' saiu das policies gerais:
--   1) PRIVACIDADE. Cada uma das 4 marcacoes do dia guarda lat/lng com 6
--      casas decimais, precisao em metros, a assinatura 'sig' derivada da
--      foto facial, distFacial/conferirFace e o tipo do dia ('atestado',
--      'falta', 'ferias'). E geolocalizacao + dado derivado de biometria
--      + informacao de saude: LGPD art. 5 II e art. 11. Na policy geral,
--      qualquer vendedor baixava o rastro de localizacao da equipe
--      inteira com um GET - e o boot ja carrega a colecao inteira.
--   2) FRAUDE. Sem checagem de autoria, qualquer autenticado dava um
--      PATCH em checkin.hora nos proprios atrasos, apagava os dias de
--      falta ou inseria batida em nome de outra pessoa. O premio de
--      assiduidade e o desconto de atraso pagam por cima desses numeros.
-- A trava de tela (pode("ajustarPonto")) continua valendo, mas ela e
-- client-side; estas policies sao a versao que o servidor cobra.
-- Falta ainda o par no adapter: acrescentar 'pontos' a COLECOES_RESTRITAS
-- (adapter.js), senao o backup diario continua exportando o rastro de
-- localizacao de todo mundo num arquivo que sai da empresa.

-- Leitura: a sua; ou todas, se for gestor de RH ou Gerente.
drop policy if exists docs_select_ponto_proprio on public.docs;
create policy docs_select_ponto_proprio on public.docs
  for select to authenticated
  using (colecao = 'pontos' and public.eh_meu_documento(data));

drop policy if exists docs_select_ponto_gestao on public.docs;
create policy docs_select_ponto_gestao on public.docs
  for select to authenticated
  using (
    colecao = 'pontos'
    and ((select public.sou_gestor_rh()) or (select public.minha_funcao()) = 'Gerente')
  );

-- Insercao: a propria batida...
drop policy if exists docs_insert_ponto_proprio on public.docs;
create policy docs_insert_ponto_proprio on public.docs
  for insert to authenticated
  with check (colecao = 'pontos' and public.eh_meu_documento(data));

-- ...ou o lancamento manual que o gestor faz por outra pessoa
-- (abrirAjustePonto cria o documento do dia quando ele nao existe).
drop policy if exists docs_insert_ponto_gestao on public.docs;
create policy docs_insert_ponto_gestao on public.docs
  for insert to authenticated
  with check (colecao = 'pontos' and (select public.sou_gestor_rh()));

-- Atualizacao pelo dono: SOMENTE o documento do dia corrente.
-- O documento de ponto e UM por colaborador por dia, e a 2a, 3a e 4a
-- marcacao regravam a mesma linha por upsert - sem update do proprio
-- ponto, a pessoa bateria a entrada e nao conseguiria bater mais nada.
-- O recorte no dia (fuso de Sao Paulo, o mesmo que o hojeISO() do
-- navegador usa) impede reescrever o historico do mes passado.
drop policy if exists docs_update_ponto_proprio on public.docs;
create policy docs_update_ponto_proprio on public.docs
  for update to authenticated
  using (
    colecao = 'pontos'
    and public.eh_meu_documento(data)
    and (data->>'data') = to_char(now() at time zone 'America/Sao_Paulo', 'YYYY-MM-DD')
  )
  with check (
    colecao = 'pontos'
    and public.eh_meu_documento(data)
    and (data->>'data') = to_char(now() at time zone 'America/Sao_Paulo', 'YYYY-MM-DD')
  );

-- Ajuste de folha: gestor de RH (Administrador/Financeiro), qualquer dia.
-- O Gerente LE a folha da equipe, mas nao ajusta. Se a acao
-- "ajustarPonto" tiver de valer para Gerente tambem, e so acrescentar
--   or (select public.minha_funcao()) = 'Gerente'
-- nas duas clausulas abaixo - a trava de tela sozinha (item 23b do
-- INTEGRACAO.md) nao decide isto, porque quem edita config/funcoes muda
-- a trava de tela.
drop policy if exists docs_update_ponto_gestao on public.docs;
create policy docs_update_ponto_gestao on public.docs
  for update to authenticated
  using      (colecao = 'pontos' and (select public.sou_gestor_rh()))
  with check (colecao = 'pontos' and (select public.sou_gestor_rh()));

-- Apagar batida: so Administrador. A correcao normal e o ajuste, que
-- deixa o registro no lugar e no historico.
drop policy if exists docs_delete_ponto_admin on public.docs;
create policy docs_delete_ponto_admin on public.docs
  for delete to authenticated
  using (colecao = 'pontos' and (select public.minha_funcao()) = 'Administrador');

-- ---------------------------------------------------------------------
-- 8.6 docs - CONFIGURACAO DO SISTEMA (colecao 'config')
-- ---------------------------------------------------------------------
-- 'config' nao e dado operacional: e o modelo de autorizacao e a tabela
-- de precos do sistema.
--   config/funcoes          {lista:[{nome,telas[],acoes[]}]} - a fonte de
--                           pode(), veTela() e ehGestor() no HTML
--   config/faixas_comissao  as faixas que calculam a comissao
--   config/formas_pagamento os coeficientes que formam o preco da venda
--   config/metas, config/empresa, config/tipos...
-- Deixada na policy geral, um Vendedor autenticado gravava config/funcoes
-- com a anon key que esta dentro do HTML e se dava 'verTudo',
-- 'gerenciarUsuarios', 'ajustarPonto', 'aprovarFinanceiro' e
-- 'baixarTitulos' - ou mudava a propria faixa de comissao. A escalada por
-- public.perfis esta fechada (so Administrador escreve la, e nao existe
-- policy de "atualizo o meu proprio perfil"), mas isso protege so o que
-- passa por sou_gestor_rh(): todo o resto do controle de acesso mora em
-- config/funcoes.
-- Leitura continua liberada para todo autenticado (8.1): o boot precisa.
drop policy if exists docs_config_gestor on public.docs;
create policy docs_config_gestor on public.docs
  for all to authenticated
  using (
    colecao = 'config'
    and (select public.minha_funcao()) in ('Administrador','Financeiro')
  )
  with check (
    colecao = 'config'
    and (select public.minha_funcao()) in ('Administrador','Financeiro')
  );

-- Excecao: config/celebracoes so guarda quais parabens ja foram exibidos
-- para cada pessoa, e checarParabens()/gravarCelebracoes() gravam no boot
-- de QUALQUER usuario. Sem esta excecao, todo login de nao-gestor passaria
-- a bater em 42501 na primeira tela.
drop policy if exists docs_config_celebracoes_ins on public.docs;
create policy docs_config_celebracoes_ins on public.docs
  for insert to authenticated
  with check (
    colecao = 'config' and id = 'celebracoes'
    and (select public.meu_nome()) is not null
  );

drop policy if exists docs_config_celebracoes_upd on public.docs;
create policy docs_config_celebracoes_upd on public.docs
  for update to authenticated
  using (
    colecao = 'config' and id = 'celebracoes'
    and (select public.meu_nome()) is not null
  )
  with check (
    colecao = 'config' and id = 'celebracoes'
    and (select public.meu_nome()) is not null
  );

-- ATENCAO AO BOOT (anotar no INTEGRACAO.md): migrarTelasNovas() grava
-- config/funcoes e carregar() semeia config/* quando o documento nao
-- existe. As duas rodam hoje para qualquer usuario e passam a falhar para
-- quem nao e Administrador/Financeiro. Ou a semente e feita uma vez pelo
-- Administrador (no primeiro login) ou pelo bloco 11.3, e a migracao de
-- telas passa a rodar so quando o usuario e Administrador.

-- ---------------------------------------------------------------------
-- 8.7 perfis
-- ---------------------------------------------------------------------
-- Leitura: qualquer colaborador com PERFIL ATIVO ve a equipe (nome,
-- funcao, loja, situacao, jornada). Nada sensivel mora aqui, mas
-- auth.uid() is not null nao servia: bastava uma sessao autenticada
-- qualquer. Um colaborador desligado (ativo=false) tem o acesso a docs
-- cortado na hora e continuaria lendo a lista da equipe ate o token
-- expirar - e o refresh token do Supabase se renova sozinho.
-- Desligar alguem, portanto, e ativo=false E revogar a sessao no painel
-- (Authentication > Users > o usuario > Sign out), ou banir o usuario.
drop policy if exists perfis_select_autenticado on public.perfis;
create policy perfis_select_autenticado on public.perfis
  for select to authenticated
  using ((select public.meu_nome()) is not null);

-- Escrita: SOMENTE Administrador. De proposito nao existe policy de
-- "atualizar o meu proprio perfil": se existisse, qualquer vendedor
-- poderia trocar a propria funcao para Administrador. O carimbo de
-- ultimo acesso vai pela RPC registrar_acesso() (item 9.2).
drop policy if exists perfis_insert_admin on public.perfis;
create policy perfis_insert_admin on public.perfis
  for insert to authenticated
  with check ((select public.minha_funcao()) = 'Administrador');

drop policy if exists perfis_update_admin on public.perfis;
create policy perfis_update_admin on public.perfis
  for update to authenticated
  using      ((select public.minha_funcao()) = 'Administrador')
  with check ((select public.minha_funcao()) = 'Administrador');

drop policy if exists perfis_delete_admin on public.perfis;
create policy perfis_delete_admin on public.perfis
  for delete to authenticated
  using ((select public.minha_funcao()) = 'Administrador');

-- ---------------------------------------------------------------------
-- 8.8 numeradores
-- ---------------------------------------------------------------------
-- Leitura liberada para quem tem perfil ativo (util para conferir de onde
-- a numeracao partiu). Escrita: NINGUEM pelo PostgREST. So a RPC
-- proximo_numero, que e security definer, incrementa o contador.
drop policy if exists numeradores_select_autenticado on public.numeradores;
create policy numeradores_select_autenticado on public.numeradores
  for select to authenticated
  using ((select public.meu_nome()) is not null);

-- =====================================================================
-- 9. RPC (funcoes chamadas pelo adapter via supabase.rpc)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 9.1 proximo_numero(loja, tipo) -> integer
-- ---------------------------------------------------------------------
-- Reserva e devolve o proximo numero, de forma atomica: dois usuarios
-- gravando ao mesmo tempo recebem numeros diferentes, porque o
-- "insert ... on conflict do update" trava a linha do contador.
-- Substitui pedidos.filter(loja).length+20801 e companhia.
-- O numero devolvido e um inteiro; a formatacao (MF-01002) fica no HTML.
-- Na PRIMEIRA chamada de um par (loja,tipo) ainda nao semeado, a linha
-- nasce na base antiga e a funcao devolve a propria base (pedido 20801,
-- orcamento 1001, os 3001) - o mesmo primeiro numero que o sistema
-- antigo daria com a lista vazia. Da segunda chamada em diante,
-- devolve sempre ultimo + 1. Por isso semeie o item 11.2 ANTES de
-- emitir o primeiro documento em producao (e prefira a semente derivada
-- dos dados importados, que nao depende de ninguem lembrar do passo).
--
-- TIPOS GLOBAIS: 'fornecedor' vale para as 3 lojas ao mesmo tempo (a
-- colecao fornecedores e um catalogo compartilhado, sem loja, e o codigo
-- FOR-xxxx e sequencial no catalogo inteiro). A funcao troca a loja por
-- '*' nesses tipos, para o adapter poder continuar chamando
-- proximoNumero(lojaAtual,'fornecedor') sem conhecer a regra - se cada
-- loja tivesse o seu contador, mf, wf e dv emitiriam FOR-1002 para tres
-- fornecedores diferentes do MESMO catalogo.
--
-- VALIDACOES: exige perfil ATIVO (nao so sessao: um colaborador desligado
-- tem o token valido ate expirar e podia queimar numeracao em laco),
-- loja conhecida e tipo conhecido. Sem a lista de tipos, um tipo digitado
-- errado cairia no "else 1" de base_numerador e comecaria uma numeracao
-- paralela do 1, calado.
create or replace function public.proximo_numero(p_loja text, p_tipo text)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_loja text := btrim(coalesce(p_loja,''));
  v_tipo text := btrim(coalesce(p_tipo,''));
  v_num  integer;
begin
  if public.meu_nome() is null then
    raise exception 'Sem perfil ativo: a numeracao exige um colaborador autenticado e ativo.'
      using errcode = '42501';
  end if;
  if v_tipo = '' or not public.tipo_numerador_valido(v_tipo) then
    raise exception 'proximo_numero: tipo invalido (%). Use pedido, orcamento, os, cliente ou fornecedor.', v_tipo
      using errcode = '22023';
  end if;

  if public.tipo_numerador_global(v_tipo) then
    v_loja := '*';                      -- contador unico das 3 lojas
  elsif v_loja not in ('mf','wf','dv') then
    raise exception 'proximo_numero: loja invalida (%). Use mf, wf ou dv.', v_loja
      using errcode = '22023';
  end if;

  insert into public.numeradores as n (loja, tipo, ultimo)
  values (v_loja, v_tipo, public.base_numerador(v_tipo))
  on conflict (loja, tipo)
  do update set ultimo = n.ultimo + 1, atualizado_em = now()
  returning n.ultimo into v_num;

  return v_num;
end;
$fn$;

-- ---------------------------------------------------------------------
-- 9.2 registrar_acesso() -> timestamptz
-- ---------------------------------------------------------------------
-- Grava o ultimo login do proprio usuario SEM abrir update de perfis
-- (que permitiria trocar a propria funcao).
create or replace function public.registrar_acesso()
returns timestamptz
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare v_quando timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Sem sessao ativa.' using errcode = '42501';
  end if;
  update public.perfis
     set ultimo_acesso = now()
   where user_id = auth.uid()
  returning ultimo_acesso into v_quando;
  return v_quando;
end;
$fn$;

-- ---------------------------------------------------------------------
-- 9.3 registrar_consentimento_facial() -> timestamptz
-- ---------------------------------------------------------------------
-- LGPD art. 11: foto facial e dado biometrico e exige consentimento.
-- Chamar na primeira batida com foto, depois do aceite na tela.
create or replace function public.registrar_consentimento_facial()
returns timestamptz
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare v_quando timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Sem sessao ativa.' using errcode = '42501';
  end if;
  update public.perfis
     set consentiu_facial_em = coalesce(consentiu_facial_em, now())
   where user_id = auth.uid()
  returning consentiu_facial_em into v_quando;
  return v_quando;
end;
$fn$;

-- ---------------------------------------------------------------------
-- 9.4 contar_docs(colecao, loja) -> bigint
-- ---------------------------------------------------------------------
-- Total real de documentos, para a tela poder dizer
-- "mostrando 500 de 3.212" em vez de mentir silenciosamente.
-- NAO e security definer: respeita a RLS de quem chamou.
create or replace function public.contar_docs(p_colecao text, p_loja text default null)
returns bigint
language sql
stable
set search_path = public, pg_temp
as $fn$
  select count(*)
    from public.docs d
   where d.colecao = p_colecao
     and (p_loja is null or d.loja = p_loja or d.loja is null);
$fn$;

-- ---------------------------------------------------------------------
-- 9.5 Permissoes de execucao
-- ---------------------------------------------------------------------
-- Por padrao o Postgres da EXECUTE para PUBLIC: revogamos e liberamos
-- so para quem esta autenticado (e para o service_role das Edge
-- Functions). O anon nao executa nada.
revoke all on function public.proximo_numero(text,text)          from public, anon;
revoke all on function public.registrar_acesso()                 from public, anon;
revoke all on function public.registrar_consentimento_facial()   from public, anon;
revoke all on function public.contar_docs(text,text)             from public, anon;
revoke all on function public.meu_nome()                         from public, anon;
revoke all on function public.minha_funcao()                     from public, anon;
revoke all on function public.minha_loja()                       from public, anon;
revoke all on function public.sou_gestor_rh()                    from public, anon;
revoke all on function public.eh_meu_documento(jsonb)            from public, anon;
revoke all on function public.colecao_restrita(text)             from public, anon;
revoke all on function public.colecao_geral(text)                from public, anon;
revoke all on function public.base_numerador(text)               from public, anon;
revoke all on function public.tipo_numerador_valido(text)        from public, anon;
revoke all on function public.tipo_numerador_global(text)        from public, anon;

grant execute on function public.proximo_numero(text,text)        to authenticated, service_role;
grant execute on function public.registrar_acesso()               to authenticated, service_role;
grant execute on function public.registrar_consentimento_facial() to authenticated, service_role;
grant execute on function public.contar_docs(text,text)           to authenticated, service_role;
grant execute on function public.meu_nome()                       to authenticated, service_role;
grant execute on function public.minha_funcao()                   to authenticated, service_role;
grant execute on function public.minha_loja()                     to authenticated, service_role;
grant execute on function public.sou_gestor_rh()                  to authenticated, service_role;
grant execute on function public.eh_meu_documento(jsonb)          to authenticated, service_role;
grant execute on function public.colecao_restrita(text)           to authenticated, service_role;
grant execute on function public.colecao_geral(text)              to authenticated, service_role;
grant execute on function public.base_numerador(text)             to authenticated, service_role;
grant execute on function public.tipo_numerador_valido(text)      to authenticated, service_role;
grant execute on function public.tipo_numerador_global(text)      to authenticated, service_role;


-- =====================================================================
-- 10. REALTIME
-- ---------------------------------------------------------------------
-- Coloca public.docs na publicacao que o Realtime do Supabase escuta.
-- O adapter assina postgres_changes com filter colecao=eq.pedidos e, a
-- cada evento, refaz o select da colecao e chama o callback do HTML
-- (o onSnapshot antigo sempre recebia a lista completa).
-- A chave primaria (colecao, id) ja e a replica identity padrao, entao
-- o filtro por colecao tambem funciona nos eventos de DELETE - nao e
-- preciso "replica identity full" (que mandaria o jsonb inteiro no fio).
-- O bloco DO evita erro se a tabela ja estiver publicada.
--
-- O "exception when others" NAO e preguica, e a mesma defesa do bloco 1:
-- o SQL Editor roda o arquivo inteiro numa transacao so, e este e o
-- ULTIMO comando executado (o item 11 e todo comentario). Uma excecao
-- aqui daria rollback em TUDO - tabelas, funcoes, policies e indices
-- sumiriam, e a mensagem na tela falaria de publicacao, nao de schema.
-- O erro mais provavel nem e "publicacao nao existe": e
--   ERROR: 42501: must be owner of publication supabase_realtime
-- quando a publicacao pertence a supabase_admin e o SQL Editor esta como
-- postgres (varia com a idade e o plano do projeto, e em branches).
-- Falhar aqui custa o Realtime, que e um recurso; o schema fica de pe.
-- =====================================================================
do $blk$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'docs'
  ) then
    execute 'alter publication supabase_realtime add table public.docs';
  end if;
exception
  when others then
    raise notice 'Nao consegui publicar public.docs no Realtime (%). O resto do schema esta criado. Ative Realtime no painel (Database > Publications) e rode: alter publication supabase_realtime add table public.docs;', sqlerrm;
end;
$blk$;


-- =====================================================================
-- 11. SEMENTE (BLOCO COMENTADO - NAO RODA SOZINHO)
-- ---------------------------------------------------------------------
-- Rode estes comandos DEPOIS, um a um, trocando os placeholders.
-- Nada aqui contem dado real.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 11.1 PRIMEIRO ADMINISTRADOR
-- ---------------------------------------------------------------------
-- Passo 1: painel do Supabase > Authentication > Users > "Add user"
--          (ou "Invite user" para o convidado criar a propria senha).
--          Anote o e-mail; o user_id (uuid) e gerado ali.
-- Passo 2: rode o insert abaixo trocando o e-mail e o nome. O nome TEM
--          que ser identico ao usado nos registros antigos, senao o
--          historico de ponto, comissao e metas nao vai casar.
-- Atencao: enquanto NAO existir um perfil com funcao 'Administrador',
--          ninguem consegue inserir perfis pelo aplicativo (a policy
--          exige Administrador). Este primeiro insert e feito aqui, no
--          SQL Editor, que roda como dono do banco e ignora a RLS.
--
-- insert into public.perfis (user_id, nome, funcao, loja, ativo, jornada)
-- select u.id,
--        'NOME DO ADMINISTRADOR',         -- ex.: o mesmo nome usado no CRM antigo
--        'Administrador',
--        'mf',                            -- mf | wf | dv
--        true,
--        '{"entrada":"08:00","almocoIni":"12:00","almocoFim":"13:30","saida":"18:00","tolerancia":10,"bateponto":"sim"}'::jsonb
--   from auth.users u
--  where u.email = 'trocar-pelo-email@exemplo.com.br'
-- on conflict (user_id) do update
--    set nome = excluded.nome,
--        funcao = excluded.funcao,
--        loja = excluded.loja,
--        ativo = excluded.ativo;

-- Demais colaboradores: repita o passo 1 (Invite user) e depois este
-- insert, trocando funcao por 'Financeiro', 'Gerente', 'Vendedor',
-- 'Prospector', 'Instalador' ou 'Estoquista' e a loja correspondente.
-- Feito o primeiro Administrador, isso tambem pode ser feito pela tela
-- de Configuracoes > Usuarios (que chamara uma Edge Function com a
-- service_role para criar a conta - o HTML com a anon key nunca cria).

-- ---------------------------------------------------------------------
-- 11.2 NUMERADORES - ULTIMO NUMERO JA USADO NO SISTEMA ANTIGO
-- ---------------------------------------------------------------------
-- SEM ESTE PASSO A NUMERACAO REPETE. Importa-se o historico (pedidos ate
-- 21.050 na mf), esquece-se de semear, e o primeiro pedido novo sai como
-- 20801 - duplicando ~250 numeros de venda. Os indices unicos do item 7.1
-- barram a gravacao quando isso acontece (o usuario ve o erro em vez de
-- um numero repetido), mas o certo e semear.
--
-- FORMA PREFERIDA - derivada dos dados ja importados. Rode DEPOIS da
-- carga do historico, na ordem em que esta. Nao tem placeholder, nao tem
-- como digitar errado, e pode ser rodada quantas vezes quiser (o
-- greatest() so deixa o contador subir).
--
-- insert into public.numeradores (loja, tipo, ultimo)
-- select d.loja, 'pedido', max(nullif(d.data->>'numero','')::int)
--   from public.docs d
--  where d.colecao = 'pedidos' and d.loja is not null
--    and (d.data->>'numero') ~ '^[0-9]+$'
--  group by d.loja
-- on conflict (loja, tipo) do update
--    set ultimo = greatest(numeradores.ultimo, excluded.ultimo);
--
-- Repita trocando 'pedidos'/'pedido' por:
--   'orcamentos' / 'orcamento'
--   'ordens'     / 'os'
--
-- Cliente: o numero esta no sufixo do codigo (MF-01002 -> 1002):
-- insert into public.numeradores (loja, tipo, ultimo)
-- select d.loja, 'cliente', max(nullif(regexp_replace(d.data->>'codigo','\D','','g'),'')::int)
--   from public.docs d
--  where d.colecao = 'clientes' and d.loja is not null
--  group by d.loja
-- on conflict (loja, tipo) do update
--    set ultimo = greatest(numeradores.ultimo, excluded.ultimo);
--
-- Fornecedor: contador UNICO das 3 lojas, gravado na loja '*' (e assim
-- que proximo_numero grava - ver o item 9.1). Nao semeie ('mf',
-- 'fornecedor'): essa linha nao seria usada por ninguem.
-- insert into public.numeradores (loja, tipo, ultimo)
-- select '*', 'fornecedor', max(nullif(regexp_replace(d.data->>'codigo','\D','','g'),'')::int)
--   from public.docs d
--  where d.colecao = 'fornecedores'
-- on conflict (loja, tipo) do update
--    set ultimo = greatest(numeradores.ultimo, excluded.ultimo);
--
-- FORMA MANUAL (se preferir levantar os numeros no CRM antigo a mao).
-- Coloque o ULTIMO usado, nao o proximo: a RPC devolve ultimo + 1.
-- Se um tipo nunca foi usado numa loja, deixe a linha de fora - na
-- primeira chamada o contador nasce na base antiga (pedido 20801,
-- orcamento 1001, os 3001, cliente 1001, fornecedor 1001).
-- Os placeholders NAO sao numeros de proposito: se voce colar o bloco sem
-- preencher, o Postgres reclama ("column ... does not exist") em vez de
-- gravar zero e reiniciar a numeracao.
--
-- insert into public.numeradores (loja, tipo, ultimo) values
--   ('mf','pedido'    , TROCAR_ULTIMO_PEDIDO_MF),      -- maior numero de pedido ja emitido na Minas Filtros
--   ('mf','orcamento' , TROCAR_ULTIMO_ORCAMENTO_MF),   -- maior numero de orcamento na Minas Filtros
--   ('mf','os'        , TROCAR_ULTIMA_OS_MF),          -- maior numero de OS na Minas Filtros
--   ('mf','cliente'   , TROCAR_ULTIMO_CLIENTE_MF),     -- maior sufixo de MF-0xxxx (so o numero, sem o prefixo)
--   ('*','fornecedor'  , TROCAR_ULTIMO_FORNECEDOR),    -- maior sufixo de FOR-xxxx; a loja e '*' (sem espaco) porque o catalogo e das 3
--   ('wf','pedido'    , TROCAR_ULTIMO_PEDIDO_WF),
--   ('wf','orcamento' , TROCAR_ULTIMO_ORCAMENTO_WF),
--   ('wf','os'        , TROCAR_ULTIMA_OS_WF),
--   ('wf','cliente'   , TROCAR_ULTIMO_CLIENTE_WF),
--   ('dv','pedido'    , TROCAR_ULTIMO_PEDIDO_DV),
--   ('dv','orcamento' , TROCAR_ULTIMO_ORCAMENTO_DV),
--   ('dv','os'        , TROCAR_ULTIMA_OS_DV),
--   ('dv','cliente'   , TROCAR_ULTIMO_CLIENTE_DV)
-- on conflict (loja, tipo) do update
--    set ultimo = greatest(numeradores.ultimo, excluded.ultimo),
--        atualizado_em = now();
--
-- O greatest() acima nao e detalhe: com "= excluded.ultimo", colar este
-- bloco uma segunda vez (na semana seguinte, ao cadastrar a loja dv, ao
-- reconferir a migracao) REBAIXARIA o contador para o valor anotado no
-- papel na data da migracao, e os proximos pedidos repetiriam numeros ja
-- emitidos. O trigger tg_numeradores_antes_de_gravar (item 6) recusa o
-- retrocesso de qualquer forma - o greatest() evita o erro.
--
-- Conferencia depois de semear - NAO use proximo_numero() para conferir:
-- ela reserva de verdade e queima um numero. Olhe a tabela:
-- select loja, tipo, ultimo, ultimo + 1 as proximo from public.numeradores order by loja, tipo;

-- ---------------------------------------------------------------------
-- 11.3 CONFIGURACOES GLOBAIS (docs colecao='config')
-- ---------------------------------------------------------------------
-- Nao precisa semear: no primeiro boot o proprio HTML grava os padroes
-- (formas_pagamento, tipos_atendimento, funcoes, motivos_finalizacao...)
-- quando encontra o documento vazio. Se preferir criar antes, o formato
-- e este - documento global, sem loja:
--
-- insert into public.docs (colecao, id, loja, data) values
--   ('config','empresa', null, '{"id":"empresa","razao":"","cnpj":"","endereco":"","fone":"","cidade":""}'::jsonb)
-- on conflict (colecao, id) do update set data = excluded.data;
--
-- ATENCAO: o antigo config/usuarios NAO deve ser recriado. Ele guardava
-- senha, CPF, salario e foto facial num unico documento lido por todo
-- mundo no boot. Agora: identidade em public.perfis, RH em
-- colecao='rh' (um doc por user_id), salario e premios em
-- colecao='remuneracao' (um doc por user_id, que o proprio colaborador
-- le) e biometria em colecao='facial' / 'ponto_fotos', todas restritas
-- por RLS.
--
-- Formato de um documento de remuneracao (o id E o user_id do perfil, e
-- e por ele que a policy docs_select_minha_remuneracao reconhece o dono):
--
-- insert into public.docs (colecao, id, loja, data) values
--   ('remuneracao','00000000-0000-0000-0000-000000000000', null,
--    '{"salario":0,"vr":0,"assiduidade":0,"desempenho":0}'::jsonb)
-- on conflict (colecao, id) do update set data = excluded.data;

-- ---------------------------------------------------------------------
-- 11.4 CONFERENCIA RAPIDA (opcional)
-- ---------------------------------------------------------------------
-- select tablename, rowsecurity from pg_tables
--  where schemaname = 'public' and tablename in ('docs','perfis','numeradores');
-- select tablename, policyname, cmd from pg_policies
--  where schemaname = 'public' order by tablename, policyname;
-- select tablename from pg_publication_tables where pubname = 'supabase_realtime';
-- Indices unicos que devem existir (item 7.1) - se faltar algum, e
-- porque havia duplicidade nos dados na hora de criar:
-- select indexname from pg_indexes
--  where schemaname = 'public' and indexname like 'ux_docs_%' order by 1;

-- ---------------------------------------------------------------------
-- 11.5 DUPLICIDADES QUE IMPEDEM OS INDICES UNICOS
-- ---------------------------------------------------------------------
-- Se o item 7.1 avisou "Indice unico NAO criado", rode a consulta da
-- colecao correspondente para achar quem esta repetido, corrija (renumere
-- ou apague o documento errado) e crie o indice de novo com o comando que
-- o proprio aviso imprimiu.
--
-- select loja, data->>'numero' as numero, count(*), array_agg(id)
--   from public.docs where colecao = 'pedidos' and (data->>'numero') is not null
--  group by 1,2 having count(*) > 1 order by 3 desc;
--
-- Troque 'pedidos' por 'orcamentos' ou 'ordens' para os demais.
-- Equipamento (numero de serie):
-- select loja, data->>'serie' as serie, count(*), array_agg(id)
--   from public.docs where colecao = 'equipamentos' and nullif(data->>'serie','') is not null
--  group by 1,2 having count(*) > 1 order by 3 desc;
-- Nota de fornecedor:
-- select loja, data->>'fornecedorId' as fornecedor, data->>'numero' as nf, count(*), array_agg(id)
--   from public.docs where colecao = 'notas' and (data->>'numero') is not null
--  group by 1,2,3 having count(*) > 1 order by 4 desc;

-- =====================================================================
-- FIM DO SCHEMA
-- =====================================================================
