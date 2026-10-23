-- =====================================================================
--  VOLTAR ATRÁS da separação das empresas  (par do empresas-separadas.sql)
--
--  COLE E RODE. Não precisa editar nada.
--
--  O QUE ELE FAZ
--    Devolve TODAS as regras de acesso ao que eram antes, lendo a cópia
--    guardada em backup.politicas_20261023.
--
--  O QUE ELE NÃO MEXE, de propósito (nada disso trava ninguém):
--    - a coluna perfis.ambas continua lá, com a marca de quem entra nas duas
--    - a função public.minha_empresa continua existindo, sem ninguém usar
--    - a função proximo_numero continua sem o 'dv'
--  Querendo desfazer também isso, os comandos estão no fim, comentados.
-- =====================================================================

do $$
declare
  r record;
  v_qtd int;
begin
  select count(*) into v_qtd from backup.politicas_20261023;
  if v_qtd = 0 then
    raise exception 'A cópia backup.politicas_20261023 está vazia — não dá para voltar atrás por aqui.';
  end if;

  for r in select * from backup.politicas_20261023 loop
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

  raise notice 'Regras devolvidas ao que eram: %', v_qtd;
end $$;

-- conferência: esta consulta tem de voltar VAZIA (nenhuma regra conferindo a empresa)
select tablename, policyname, cmd
  from pg_policies
 where schemaname = 'public'
   and (qual like '%minha_empresa%' or with_check like '%minha_empresa%');


-- =====================================================================
--  SÓ SE QUISER APAGAR TAMBÉM O RESTO (não é preciso)
-- =====================================================================
-- alter table public.perfis drop column if exists ambas;
-- drop function if exists public.minha_empresa(text);
