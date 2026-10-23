-- =====================================================================
--  MEDIR O TEMPO E CONFERIR O QUE CADA UM VÊ  (23/10/2026)
--
--  Este arquivo NÃO MUDA NADA. Ele abre uma transação, finge estar
--  logado como uma pessoa, mede a leitura dos clientes e DESFAZ tudo
--  no fim (rollback).
--
--  RODE ELE SOZINHO, numa aba limpa do SQL Editor, DEPOIS do
--  rls-desempenho.sql — e não junto com outro comando. O editor do
--  Supabase já abre uma transação por conta dele, e o rollback do fim
--  desfaz TUDO o que estiver na mesma execução: rodando junto com o
--  arquivo da correção, as regras novas seriam desfeitas.
--
--  O QUE ESPERAR (medido aqui em 23/10, alternando as duas formas na
--  mesma conexão, com o cache quente):
--
--      pessoa   antes            depois
--      Wagner   1.064 ms         20 ms
--      Thiago   1.322–2.138 ms   26 ms
--
--  E a contagem de clientes tem de continuar a mesma de antes:
--      Wagner (entra nas duas) -> 22.350
--      Thiago (só Minas Filtros) -> 22.349
--  A diferença de 1 é o cliente da WF, que o Thiago não pode ver.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. QUEM VAMOS SIMULAR
--    Se algum nome estiver diferente no cadastro, troque aqui.
-- ---------------------------------------------------------------------
select nome, funcao, loja, ambas, user_id
  from public.perfis
 where ativo
   and nome in ('Wagner','Renan Administrador','Thiago')
 order by nome;


-- ---------------------------------------------------------------------
-- 2. O TEMPO, COMO WAGNER (entra nas duas empresas)
-- ---------------------------------------------------------------------
begin;

select set_config(
  'request.jwt.claims',
  json_build_object(
     'sub',  (select user_id::text from public.perfis where nome='Wagner' and ativo limit 1),
     'role', 'authenticated'
  )::text,
  true
) as fingindo_ser_wagner;

set local role authenticated;

-- a primeira leitura esquenta o cache; a segunda é a que vale
explain (analyze, timing off, buffers off)
  select count(*) from public.docs where colecao='clientes' and loja='mf';

explain (analyze, timing off, buffers off)
  select count(*) from public.docs where colecao='clientes' and loja='mf';

-- quantos clientes ele vê (tem de dar 22.350, contando a WF)
select count(*) as clientes_que_wagner_ve from public.docs where colecao='clientes';

rollback;


-- ---------------------------------------------------------------------
-- 3. O TEMPO, COMO THIAGO (só Minas Filtros)
-- ---------------------------------------------------------------------
begin;

select set_config(
  'request.jwt.claims',
  json_build_object(
     'sub',  (select user_id::text from public.perfis where nome='Thiago' and ativo limit 1),
     'role', 'authenticated'
  )::text,
  true
) as fingindo_ser_thiago;

set local role authenticated;

explain (analyze, timing off, buffers off)
  select count(*) from public.docs where colecao='clientes' and loja='mf';

explain (analyze, timing off, buffers off)
  select count(*) from public.docs where colecao='clientes' and loja='mf';

-- tem de dar 22.349: o cliente da WF continua fora
select count(*) as clientes_que_thiago_ve from public.docs where colecao='clientes';

-- e ele não pode ver NADA da WF: tem de dar 0
select count(*) as docs_da_wf_que_thiago_ve from public.docs where loja='wf';

rollback;


-- ---------------------------------------------------------------------
-- 4. O PISO: quanto custa a mesma leitura SEM regra de acesso nenhuma
--    (é o número com que a gente compara; aqui deu 4 ms, e os 67 ms que
--    ele mediu incluem a ida e volta da internet)
-- ---------------------------------------------------------------------
explain (analyze, timing off, buffers off)
  select count(*) from public.docs where colecao='clientes' and loja='mf';


-- ---------------------------------------------------------------------
-- 5. CONFERÊNCIA DE SEGURANÇA: ninguém passou a ver mais do que via
--    TEM DE VOLTAR VAZIA.
--    Para cada perfil ativo, compara a resposta da conta ANTIGA
--    (minha_empresa) com a da conta NOVA, nas duas empresas e no
--    documento sem empresa.
-- ---------------------------------------------------------------------
select p.nome, p.funcao, p.loja, p.ambas, l.loja_testada,
       (l.loja_testada is null or p.ambas or p.loja = l.loja_testada) as antes,
       (l.loja_testada is null or p.ambas or l.loja_testada = any(
          coalesce((select array_agg(distinct q.loja) from public.perfis q
                     where q.user_id = p.user_id and q.ativo and q.loja is not null),
                   '{}'::text[]))) as depois,
       'DIVERGIU - nao publique assim' as aviso
  from public.perfis p
 cross join (select unnest(array['mf','wf',null]::text[]) as loja_testada) l
 where p.ativo
   and (l.loja_testada is null or p.ambas or p.loja = l.loja_testada)
       is distinct from
       (l.loja_testada is null or p.ambas or l.loja_testada = any(
          coalesce((select array_agg(distinct q.loja) from public.perfis q
                     where q.user_id = p.user_id and q.ativo and q.loja is not null),
                   '{}'::text[])));
