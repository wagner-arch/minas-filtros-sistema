-- =====================================================================
--  A TRAVA DE EMPRESAS DEIXA DE SER LENTA  (23/10/2026)
--
--  O PROBLEMA, medido no banco de verdade:
--    ler os 22.350 clientes da Minas Filtros levava 1.064 ms (Wagner) e
--    1.322 ms (Thiago). Sem regra de acesso nenhuma, 4 ms.
--
--  A CAUSA
--    As regras chamam FUNÇÃO LINHA POR LINHA, e cada chamada dessas faz
--    uma consulta na tabela perfis:
--      minha_empresa(loja)    -> 22.350 chamadas  (veio com a trava)
--      colecao_geral(colecao) -> 22.350 chamadas  (já era assim antes;
--                                ela ainda chama colecao_restrita dentro)
--    Medido: colecao_geral sozinha custa 538 ms numa leitura de clientes.
--
--  A CORREÇÃO
--    Nada que dependa SÓ DO USUÁRIO LOGADO precisa ser perguntado por
--    linha — a resposta é a mesma nas 22.350. Pondo a pergunta dentro de
--    (select ...), o banco a responde UMA VEZ por consulta e reaproveita.
--    Para isso entram quatro funções sem argumento:
--      minhas_lojas()         as empresas que eu posso ver  (text[])
--      vejo_todas_lojas()     tenho a marca "ambas"?        (boolean)
--      colecoes_restritas()   as coleções de RH/biometria   (text[])
--      colecoes_nao_gerais()  essas + config e pontos       (text[])
--
--  O QUE CADA PESSOA VÊ: NÃO MUDA NADA.
--    Conferido linha por linha antes de escrever este arquivo:
--      Wagner (entra nas duas)   -> 22.350 clientes, no antigo e no novo
--      Thiago (só Minas Filtros) -> 22.349 nos dois (o cliente da WF
--      continua fora, e é a prova de que a trava continua de pé)
--
--  O GANHO, medido alternando as duas formas na mesma conexão:
--      Wagner  1.064 ms -> 20 ms
--      Thiago  1.322 ms -> 26 ms
--
--  COMO RODAR
--    Supabase > SQL Editor > New query > cole tudo > Run.
--
--  COMO CONFERIR DEPOIS
--    Rode o arquivo rls-desempenho-medir.sql: ele mede o tempo e conta
--    os clientes como Wagner e como Thiago, e desfaz tudo no fim.
--
--  COMO VOLTAR ATRÁS
--    O bloco 1 guarda as regras de agora em
--    backup.politicas_20261023_rapidas, e o arquivo
--    rls-desempenho-voltar-atras.sql as devolve.
--    A cópia backup.politicas_20261023 (de ANTES da trava de empresas)
--    NÃO é tocada, e o empresas-voltar-atras.sql continua valendo.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. CÓPIA DE SEGURANÇA DAS REGRAS DE AGORA
--    (já com a trava de empresas, antes desta troca)
--
--    Feita UMA VEZ: rodando o arquivo de novo ela NÃO é refeita, senão
--    guardaria as regras já trocadas e a original se perderia.
-- ---------------------------------------------------------------------
create schema if not exists backup;

create table if not exists backup.politicas_20261023_rapidas as
select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
  from pg_policies
 where schemaname = 'public';

-- confira: tem de trazer as regras de ANTES desta troca (hoje são 39)
select count(*) as regras_guardadas from backup.politicas_20261023_rapidas;


-- ---------------------------------------------------------------------
-- 2. AS QUATRO FUNÇÕES NOVAS
--    Todas sem argumento, para caberem dentro de (select ...).
--    As antigas (minha_empresa, colecao_geral, colecao_restrita)
--    CONTINUAM existindo, intactas: nada se apaga, e o voltar-atrás
--    precisa delas.
-- ---------------------------------------------------------------------

-- As empresas que o usuário logado pode ver.
-- Perfil sem empresa, ou usuário sem perfil ativo, devolve lista vazia —
-- e aí ele não vê documento de empresa nenhuma. A regra falha FECHADA.
create or replace function public.minhas_lojas()
 returns text[]
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  select coalesce(array_agg(distinct p.loja), '{}'::text[])
    from public.perfis p
   where p.user_id = auth.uid()
     and p.ativo
     and p.loja is not null;
$function$;

comment on function public.minhas_lojas() is
  'As empresas que o usuario logado pode ver. Usar SEMPRE dentro de (select public.minhas_lojas()) nas regras de acesso, para o banco responder uma vez por consulta em vez de uma vez por linha.';

-- Quem tem a marca "ambas" vê QUALQUER empresa — é o mesmo que a
-- minha_empresa fazia com "or p.ambas". Função separada de propósito:
-- se amanhã nascer uma empresa nova, quem tem a marca continua vendo,
-- sem ninguém precisar lembrar de pôr a empresa numa lista.
create or replace function public.vejo_todas_lojas()
 returns boolean
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  select exists (
    select 1 from public.perfis p
     where p.user_id = auth.uid()
       and p.ativo
       and p.ambas
  );
$function$;

comment on function public.vejo_todas_lojas() is
  'true = o usuario logado entra nas duas empresas (marca ambas no perfil). Usar dentro de (select ...).';

-- As mesmas coleções de public.colecao_restrita, agora como lista.
create or replace function public.colecoes_restritas()
 returns text[]
 language sql
 immutable
 set search_path to 'public', 'pg_temp'
as $function$
  select array['rh','remuneracao','ponto_fotos','pontos_fotos','facial']::text[];
$function$;

-- O que NÃO é coleção geral: as restritas mais config e pontos.
-- É o contrário exato de public.colecao_geral.
create or replace function public.colecoes_nao_gerais()
 returns text[]
 language sql
 immutable
 set search_path to 'public', 'pg_temp'
as $function$
  select array['config','pontos','rh','remuneracao','ponto_fotos','pontos_fotos','facial']::text[];
$function$;

comment on function public.colecoes_nao_gerais() is
  'Colecoes que NAO sao gerais (restritas + config + pontos). Colecao nova de RH ou biometria entra aqui E em colecoes_restritas E nas funcoes colecao_restrita/colecao_geral — as quatro tem de dizer a mesma coisa, e a conferencia 4.2 deste arquivo cobra isso.';


-- ---------------------------------------------------------------------
-- 3. AS 21 REGRAS DE ACESSO, REESCRITAS
--
--    Em todas, a conferência de empresa passou de
--        minha_empresa(loja)
--    para
--        (loja is null
--         or (select public.vejo_todas_lojas())
--         or loja = any((select public.minhas_lojas())::text[]))
--
--    O ::text[] do fim é OBRIGATÓRIO: sem ele o banco entende
--    "any (subconsulta)" e recusa com
--    "operator does not exist: text = text[]".
--
--    Nada muda em permissive (todas PERMISSIVE) nem em para quem valem
--    (todas "to authenticated", como já eram).
-- ---------------------------------------------------------------------

-- ---- docs: coleções gerais (clientes, pedidos, produtos, estoque...) ----

drop policy if exists docs_select_geral on public.docs;
create policy docs_select_geral on public.docs
  as permissive for select to authenticated
  using (
    colecao <> all((select public.colecoes_nao_gerais())::text[])
    and (select public.meu_nome()) is not null
    and (loja is null
         or (select public.vejo_todas_lojas())
         or loja = any((select public.minhas_lojas())::text[]))
  );

drop policy if exists docs_insert_geral on public.docs;
create policy docs_insert_geral on public.docs
  as permissive for insert to authenticated
  with check (
    colecao <> all((select public.colecoes_nao_gerais())::text[])
    and (select public.meu_nome()) is not null
    and (loja is null
         or (select public.vejo_todas_lojas())
         or loja = any((select public.minhas_lojas())::text[]))
  );

drop policy if exists docs_update_geral on public.docs;
create policy docs_update_geral on public.docs
  as permissive for update to authenticated
  using (
    colecao <> all((select public.colecoes_nao_gerais())::text[])
    and (select public.meu_nome()) is not null
    and (loja is null
         or (select public.vejo_todas_lojas())
         or loja = any((select public.minhas_lojas())::text[]))
  )
  with check (
    colecao <> all((select public.colecoes_nao_gerais())::text[])
    and (select public.meu_nome()) is not null
    and (loja is null
         or (select public.vejo_todas_lojas())
         or loja = any((select public.minhas_lojas())::text[]))
  );

drop policy if exists docs_delete_gestao on public.docs;
create policy docs_delete_gestao on public.docs
  as permissive for delete to authenticated
  using (
    colecao <> all((select public.colecoes_nao_gerais())::text[])
    and (select public.minha_funcao()) = any (array['Administrador','Financeiro','Gerente'])
    and (loja is null
         or (select public.vejo_todas_lojas())
         or loja = any((select public.minhas_lojas())::text[]))
  );

-- ---- docs: configurações ----

drop policy if exists docs_select_config on public.docs;
create policy docs_select_config on public.docs
  as permissive for select to authenticated
  using (
    colecao = 'config'
    and (select public.meu_nome()) is not null
    and (loja is null
         or (select public.vejo_todas_lojas())
         or loja = any((select public.minhas_lojas())::text[]))
  );

drop policy if exists docs_config_gestor on public.docs;
create policy docs_config_gestor on public.docs
  as permissive for all to authenticated
  using (
    colecao = 'config'
    and (select public.minha_funcao()) = any (array['Administrador','Financeiro'])
    and (loja is null
         or (select public.vejo_todas_lojas())
         or loja = any((select public.minhas_lojas())::text[]))
  )
  with check (
    colecao = 'config'
    and (select public.minha_funcao()) = any (array['Administrador','Financeiro'])
    and (loja is null
         or (select public.vejo_todas_lojas())
         or loja = any((select public.minhas_lojas())::text[]))
  );

-- ---- docs: cartão de ponto (a gestão vê o da própria empresa) ----

drop policy if exists docs_select_ponto_gestao on public.docs;
create policy docs_select_ponto_gestao on public.docs
  as permissive for select to authenticated
  using (
    colecao = 'pontos'
    and ((select public.sou_gestor_rh()) or (select public.minha_funcao()) = 'Gerente')
    and (loja is null
         or (select public.vejo_todas_lojas())
         or loja = any((select public.minhas_lojas())::text[]))
  );

-- ---- docs: RH e biometria (sem conferência de empresa, como já era) ----

drop policy if exists docs_select_restrita_gestor on public.docs;
create policy docs_select_restrita_gestor on public.docs
  as permissive for select to authenticated
  using (
    colecao = any((select public.colecoes_restritas())::text[])
    and (select public.sou_gestor_rh())
  );

drop policy if exists docs_insert_restrita_gestor on public.docs;
create policy docs_insert_restrita_gestor on public.docs
  as permissive for insert to authenticated
  with check (
    colecao = any((select public.colecoes_restritas())::text[])
    and (select public.sou_gestor_rh())
  );

drop policy if exists docs_update_restrita_gestor on public.docs;
create policy docs_update_restrita_gestor on public.docs
  as permissive for update to authenticated
  using (
    colecao = any((select public.colecoes_restritas())::text[])
    and (select public.sou_gestor_rh())
  )
  with check (
    colecao = any((select public.colecoes_restritas())::text[])
    and (select public.sou_gestor_rh())
  );

drop policy if exists docs_delete_restrita_gestor on public.docs;
create policy docs_delete_restrita_gestor on public.docs
  as permissive for delete to authenticated
  using (
    colecao = any((select public.colecoes_restritas())::text[])
    and (select public.sou_gestor_rh())
  );

-- ---- numeradores ----

drop policy if exists numeradores_select_autenticado on public.numeradores;
create policy numeradores_select_autenticado on public.numeradores
  as permissive for select to authenticated
  using (
    (select public.meu_nome()) is not null
    and (loja is null
         or (select public.vejo_todas_lojas())
         or loja = any((select public.minhas_lojas())::text[]))
  );

-- ---- perfis: cada um vê o próprio e os colegas da mesma empresa ----

drop policy if exists perfis_select_autenticado on public.perfis;
create policy perfis_select_autenticado on public.perfis
  as permissive for select to authenticated
  using (
    (select public.meu_nome()) is not null
    and (user_id = (select auth.uid())
         or loja is null
         or (select public.vejo_todas_lojas())
         or loja = any((select public.minhas_lojas())::text[]))
  );

-- ---- links de assinatura do pedido ----

drop policy if exists assinaturas_link_select on public.assinaturas_link;
create policy assinaturas_link_select on public.assinaturas_link
  as permissive for select to authenticated
  using (
    (select public.meu_nome()) is not null
    and (loja is null
         or (select public.vejo_todas_lojas())
         or loja = any((select public.minhas_lojas())::text[]))
  );

drop policy if exists assinaturas_link_insert on public.assinaturas_link;
create policy assinaturas_link_insert on public.assinaturas_link
  as permissive for insert to authenticated
  with check (
    (select public.meu_nome()) is not null
    and (loja is null
         or (select public.vejo_todas_lojas())
         or loja = any((select public.minhas_lojas())::text[]))
  );

drop policy if exists assinaturas_link_update on public.assinaturas_link;
create policy assinaturas_link_update on public.assinaturas_link
  as permissive for update to authenticated
  using (
    (select public.meu_nome()) is not null
    and (loja is null
         or (select public.vejo_todas_lojas())
         or loja = any((select public.minhas_lojas())::text[]))
  )
  with check (
    (select public.meu_nome()) is not null
    and (loja is null
         or (select public.vejo_todas_lojas())
         or loja = any((select public.minhas_lojas())::text[]))
  );

-- ---- rastreio dos vendedores ----

drop policy if exists rastro_pontos_select on public.rastro_pontos;
create policy rastro_pontos_select on public.rastro_pontos
  as permissive for select to authenticated
  using (
    user_id = (select auth.uid())
    or ((select public.sou_gestao_rastreio())
        and (loja is null
             or (select public.vejo_todas_lojas())
             or loja = any((select public.minhas_lojas())::text[])))
  );

drop policy if exists rastro_pontos_insert_meu on public.rastro_pontos;
create policy rastro_pontos_insert_meu on public.rastro_pontos
  as permissive for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and vendedor = (select public.meu_nome())
  );

drop policy if exists rastro_paradas_select on public.rastro_paradas;
create policy rastro_paradas_select on public.rastro_paradas
  as permissive for select to authenticated
  using (
    user_id = (select auth.uid())
    or ((select public.sou_gestao_rastreio())
        and (loja is null
             or (select public.vejo_todas_lojas())
             or loja = any((select public.minhas_lojas())::text[])))
  );

drop policy if exists rastro_paradas_update on public.rastro_paradas;
create policy rastro_paradas_update on public.rastro_paradas
  as permissive for update to authenticated
  using (
    user_id = (select auth.uid())
    or ((select public.sou_gestao_rastreio())
        and (loja is null
             or (select public.vejo_todas_lojas())
             or loja = any((select public.minhas_lojas())::text[])))
  )
  with check (
    user_id = (select auth.uid())
    or ((select public.sou_gestao_rastreio())
        and (loja is null
             or (select public.vejo_todas_lojas())
             or loja = any((select public.minhas_lojas())::text[])))
  );

drop policy if exists rastro_paradas_insert_meu on public.rastro_paradas;
create policy rastro_paradas_insert_meu on public.rastro_paradas
  as permissive for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and vendedor = (select public.meu_nome())
  );


-- ---------------------------------------------------------------------
-- 4. CONFERÊNCIAS
-- ---------------------------------------------------------------------

-- 4.1 TEM DE VOLTAR VAZIA
--     Procura, em TODAS as regras do banco, chamada de função que o
--     banco faria LINHA POR LINHA — isto é, fora de um (select ...).
--     Rodada ANTES desta correção, ela aponta exatamente as 21 regras
--     que o bloco 3 reescreve. Depois, tem de vir vazia.
with p as (
  select tablename, policyname, cmd,
         regexp_replace(coalesce(qual,'') || ' ' || coalesce(with_check,''),
                        '\( SELECT [a-z_.]+\(\) AS [a-z_]+\)', '', 'g') as sobra
    from pg_policies
   where schemaname = 'public'
)
select tablename, policyname, cmd,
       substring(sobra from '(minha_empresa\(|colecao_geral\(|colecao_restrita\(|meu_nome\(|minha_funcao\(|sou_gestor_rh\(|sou_gestao_rastreio\(|auth\.uid\(|minhas_lojas\(|vejo_todas_lojas\(|colecoes_restritas\(|colecoes_nao_gerais\()')
         as chamada_por_linha,
       'esta regra chama funcao linha por linha' as aviso
  from p
 where sobra ~ 'minha_empresa\(|colecao_geral\(|colecao_restrita\(|meu_nome\(|minha_funcao\(|sou_gestor_rh\(|sou_gestao_rastreio\(|auth\.uid\(|minhas_lojas\(|vejo_todas_lojas\(|colecoes_restritas\(|colecoes_nao_gerais\('
 order by tablename, policyname;

-- 4.2 TEM DE VOLTAR VAZIA: as listas novas dizem exatamente o mesmo que
--     as funções antigas, para toda coleção que existe no banco
select c as colecao,
       public.colecao_restrita(c)               as restrita_pela_funcao,
       (c = any(public.colecoes_restritas()))   as restrita_pela_lista,
       public.colecao_geral(c)                  as geral_pela_funcao,
       (c <> all(public.colecoes_nao_gerais())) as geral_pela_lista,
       'as duas fontes divergem - corrija antes de confiar' as aviso
  from (select distinct colecao as c from public.docs) t
 where public.colecao_restrita(c) <> (c = any(public.colecoes_restritas()))
    or public.colecao_geral(c)    <> (c <> all(public.colecoes_nao_gerais()));

-- 4.3 TEM DE VOLTAR VAZIA: para cada perfil ativo e cada empresa, a conta
--     nova responde o mesmo que a antiga. Divergência aqui quer dizer que
--     alguém passaria a ver mais, ou menos, do que vê hoje.
select p.nome, p.funcao, p.loja, p.ambas, l.loja_testada,
       'a conta nova diverge da antiga' as aviso
  from public.perfis p
 cross join (select unnest(array['mf','wf',null]::text[]) as loja_testada) l
 where p.ativo
   and (
     -- resposta da regra ANTIGA (minha_empresa) para este perfil
     (l.loja_testada is null or p.ambas or p.loja = l.loja_testada)
     is distinct from
     -- resposta da regra NOVA para o mesmo perfil
     (l.loja_testada is null or p.ambas or l.loja_testada = any(
        coalesce((select array_agg(distinct q.loja) from public.perfis q
                   where q.user_id = p.user_id and q.ativo and q.loja is not null),
                 '{}'::text[])))
   );

-- 4.4 só para olhar: tem de dizer 19.
--     São as 21 reescritas menos as duas de gravar ponto de rastreio
--     (rastro_pontos_insert_meu e rastro_paradas_insert_meu), que não
--     conferem empresa — elas só deixam cada um gravar o próprio ponto.
select count(*) as regras_usando_a_conta_nova
  from pg_policies
 where schemaname = 'public'
   and (coalesce(qual,'')       ~ 'minhas_lojas|colecoes_restritas|colecoes_nao_gerais'
     or coalesce(with_check,'') ~ 'minhas_lojas|colecoes_restritas|colecoes_nao_gerais');

-- 4.5 só para olhar: a trava de empresas continua de pé em 15 regras,
--     agora pela conta nova
select count(*) as regras_conferindo_a_empresa
  from pg_policies
 where schemaname = 'public'
   and (coalesce(qual,'')       like '%minhas_lojas%'
     or coalesce(with_check,'') like '%minhas_lojas%');
