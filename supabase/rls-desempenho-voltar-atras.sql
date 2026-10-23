-- =====================================================================
--  VOLTAR ATRÁS da correção de desempenho  (par do rls-desempenho.sql)
--
--  COLE E RODE. Não precisa editar nada.
--
--  O QUE ELE FAZ
--    Devolve todas as regras de acesso ao que eram ANTES desta correção
--    — ou seja, com a trava de empresas de pé, mas lentas —, lendo a
--    cópia backup.politicas_20261023_rapidas.
--
--  ATENÇÃO: ele NÃO volta para antes da trava de empresas.
--    Para isso é o outro arquivo, empresas-voltar-atras.sql, que lê a
--    cópia backup.politicas_20261023 e continua valendo.
--
--  O QUE ELE NÃO MEXE, de propósito (nada disso trava ninguém):
--    - as quatro funções novas continuam existindo, sem ninguém usar
--    Querendo apagá-las também, os comandos estão no fim, comentados.
-- =====================================================================

do $$
declare
  r record;
  v_qtd int;
begin
  select count(*) into v_qtd from backup.politicas_20261023_rapidas;
  if v_qtd = 0 then
    raise exception 'A cópia backup.politicas_20261023_rapidas está vazia — não dá para voltar atrás por aqui.';
  end if;

  for r in select * from backup.politicas_20261023_rapidas loop
    execute format('drop policy if exists %I on public.%I', r.policyname, r.tablename);
    execute format('create policy %I on public.%I as %s for %s to %s %s %s',
      r.policyname,
      r.tablename,
      case when r.permissive = 'PERMISSIVE' then 'permissive' else 'restrictive' end,
      case when r.cmd = 'ALL' then 'all' else lower(r.cmd) end,
      array_to_string(r.roles, ', '),
      case when r.qual       is null then '' else 'using ('||r.qual||')' end,
      case when r.with_check is null then '' else 'with check ('||r.with_check||')' end);
  end loop;

  raise notice 'Regras devolvidas ao que eram antes da correcao de desempenho: %', v_qtd;
end $$;

-- conferência: TEM DE VOLTAR VAZIA (nenhuma regra usando as funções novas)
select tablename, policyname, cmd, 'ainda usa a conta nova' as aviso
  from pg_policies
 where schemaname = 'public'
   and (coalesce(qual,'')       like '%minhas_lojas%'
     or coalesce(with_check,'') like '%minhas_lojas%'
     or coalesce(qual,'')       like '%vejo_todas_lojas%'
     or coalesce(with_check,'') like '%vejo_todas_lojas%'
     or coalesce(qual,'')       like '%colecoes_restritas%'
     or coalesce(with_check,'') like '%colecoes_restritas%'
     or coalesce(qual,'')       like '%colecoes_nao_gerais%'
     or coalesce(with_check,'') like '%colecoes_nao_gerais%');

-- e a trava de empresas tem de continuar de pé: esta tem de trazer as 15 regras
select count(*) as regras_conferindo_a_empresa
  from pg_policies
 where schemaname = 'public'
   and (coalesce(qual,'') like '%minha_empresa%' or coalesce(with_check,'') like '%minha_empresa%');


-- =====================================================================
--  SÓ SE QUISER APAGAR TAMBÉM AS FUNÇÕES NOVAS (não é preciso)
-- =====================================================================
-- drop function if exists public.minhas_lojas();
-- drop function if exists public.vejo_todas_lojas();
-- drop function if exists public.colecoes_restritas();
-- drop function if exists public.colecoes_nao_gerais();
