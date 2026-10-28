-- ALMOXARIFADO COMPLETO (28/10): a função Almoxarifado passa a poder GRAVAR os Grupos de Produtos.
-- Hoje as configurações (colecao 'config') só o Administrador e o Financeiro gravam
-- (regra docs_config_gestor). Grupos e subgrupos de produto são cadastro do almoxarifado,
-- então esta regra libera SÓ esse documento, nas duas empresas, para a função Almoxarifado (o nome antigo, Estoquista, também vale).
-- Nenhuma regra existente é alterada: as duas abaixo são novas e somam às de hoje.
-- Rodar no Supabase: SQL Editor › New query › colar tudo › Run.

-- 1) cópia de segurança das regras de hoje (rodar duas vezes não refaz a cópia)
create table if not exists backup.politicas_antes_almox_20261028 as
  select * from pg_policies where schemaname='public' and tablename='docs';

-- 2) as duas regras novas
drop policy if exists docs_config_grupos_almox_ins on public.docs;
create policy docs_config_grupos_almox_ins on public.docs for insert to authenticated
  with check (colecao='config' and id in ('grupos_produtos','wf:grupos_produtos')
    and (select public.minha_funcao()) in ('Almoxarifado','Estoquista')
    and (loja is null or (select public.vejo_todas_lojas()) or loja = any((select public.minhas_lojas())::text[])));

drop policy if exists docs_config_grupos_almox_upd on public.docs;
create policy docs_config_grupos_almox_upd on public.docs for update to authenticated
  using (colecao='config' and id in ('grupos_produtos','wf:grupos_produtos')
    and (select public.minha_funcao()) in ('Almoxarifado','Estoquista')
    and (loja is null or (select public.vejo_todas_lojas()) or loja = any((select public.minhas_lojas())::text[])))
  with check (colecao='config' and id in ('grupos_produtos','wf:grupos_produtos')
    and (select public.minha_funcao()) in ('Almoxarifado','Estoquista')
    and (loja is null or (select public.vejo_todas_lojas()) or loja = any((select public.minhas_lojas())::text[])));

-- 3) conferência: devem aparecer as duas regras
select policyname, cmd from pg_policies
 where schemaname='public' and tablename='docs' and policyname like 'docs_config_grupos_almox%';

-- PARA VOLTAR ATRÁS:
--   drop policy if exists docs_config_grupos_almox_ins on public.docs;
--   drop policy if exists docs_config_grupos_almox_upd on public.docs;
