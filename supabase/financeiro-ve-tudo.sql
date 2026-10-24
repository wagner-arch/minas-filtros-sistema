-- ============================================================================
-- O FINANCEIRO PASSA A VER TODAS AS TELAS (decisão dele de 23/10, Etapa 2)
--
-- Regra: "o Financeiro vê tudo; nas Configurações, só olha". A parte de "só
-- olha" já está no sistema desde a v400 (a tela de Configurações abre em
-- leitura para ele e a gravação é recusada por dentro). O que falta é LIBERAR
-- as telas, porque quem manda é o `config/funcoes` gravado no banco — o que
-- está no código só vale para instalação nova.
--
-- Hoje o Financeiro tem 34 telas e o Administrador 50. Faltam estas 16:
--   aniver, beneficios, cadcaixas, centros, cfgmetas, empresa, funcoes,
--   metas, motivos, origens, os, permissoes, pgto, planos, tipos, usuarios
--
-- Nada é apagado: as ações do Financeiro (verTudo, verCustos,
-- aprovarFinanceiro, reabrirVenda, baixarTitulos, exportar) continuam as
-- mesmas. Só a lista de telas passa a ser a do Administrador.
--
-- Vale para as DUAS empresas: `funcoes` (Minas Filtros) e `wf:funcoes` (WF).
--
-- Como rodar: Supabase › SQL Editor › New query › cole tudo › Run.
-- Rodar duas vezes não faz mal (a cópia não é refeita e o resultado é o mesmo).
-- ============================================================================

-- 1. CÓPIA DE SEGURANÇA, ANTES DE QUALQUER COISA ----------------------------
create table if not exists backup.config_funcoes_20261024 as
  select * from public.docs where colecao = 'config' and id in ('funcoes','wf:funcoes');

-- confira: tem de devolver 2 linhas
select count(*) as copias_guardadas from backup.config_funcoes_20261024;

-- 2. O FINANCEIRO RECEBE AS MESMAS TELAS DO ADMINISTRADOR -------------------
update public.docs d
set data = jsonb_set(
      d.data,
      '{lista}',
      (select jsonb_agg(
         case when f->>'nome' = 'Financeiro'
           then jsonb_set(
                  jsonb_set(f, '{telas}',
                    (select a->'telas' from jsonb_array_elements(d.data->'lista') a
                      where a->>'nome' = 'Administrador')),
                  '{desc}', '"Vê tudo; nas Configurações, só olha"'::jsonb)
           else f end)
       from jsonb_array_elements(d.data->'lista') f))
where d.colecao = 'config'
  and d.id in ('funcoes','wf:funcoes');

-- 3. CONFERÊNCIA -------------------------------------------------------------
-- 3.1 as duas empresas com o Financeiro no mesmo tamanho do Administrador
select id,
       (select jsonb_array_length(f->'telas') from jsonb_array_elements(data->'lista') f
         where f->>'nome' = 'Financeiro')    as telas_financeiro,
       (select jsonb_array_length(f->'telas') from jsonb_array_elements(data->'lista') f
         where f->>'nome' = 'Administrador') as telas_admin
from public.docs
where colecao = 'config' and id in ('funcoes','wf:funcoes');
-- esperado: telas_financeiro = telas_admin nas duas linhas

-- 3.2 não sobrou nenhuma tela de fora (tem de voltar VAZIA)
with f as (
  select id,
    (select f->'telas' from jsonb_array_elements(data->'lista') f where f->>'nome'='Financeiro')    as fin,
    (select f->'telas' from jsonb_array_elements(data->'lista') f where f->>'nome'='Administrador') as adm
  from public.docs where colecao='config' and id in ('funcoes','wf:funcoes'))
select id, x as tela_que_ficou_de_fora
from f, lateral (select jsonb_array_elements_text(adm) except select jsonb_array_elements_text(fin)) t(x);

-- 3.3 as ações do Financeiro continuam as mesmas (nada foi dado de quebra)
select id,
       (select f->'acoes' from jsonb_array_elements(data->'lista') f where f->>'nome'='Financeiro') as acoes_financeiro
from public.docs where colecao='config' and id in ('funcoes','wf:funcoes');
-- esperado: ["verTudo","verCustos","aprovarFinanceiro","reabrirVenda","baixarTitulos","exportar"]

-- ============================================================================
-- PARA VOLTAR ATRÁS (se algo não ficar como você quer):
--
--   update public.docs d
--   set data = b.data
--   from backup.config_funcoes_20261024 b
--   where d.colecao = 'config' and d.id = b.id;
--
-- Depois de rodar, quem estiver com o sistema aberto precisa recarregar (F5)
-- para o menu novo aparecer.
-- ============================================================================
