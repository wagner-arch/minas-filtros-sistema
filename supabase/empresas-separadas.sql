-- =====================================================================
--  MINAS FILTROS E WF FILTROS VIRAM DUAS EMPRESAS NO BANCO  (23/10/2026)
--  Regra do Wagner: "são DUAS EMPRESAS DIFERENTES, cada uma com
--  financeiro, estoque, produtos, clientes e equipe próprios. Não existe
--  junção entre elas."
--
--  O QUE ESTE ARQUIVO FAZ
--    1. guarda uma cópia das regras de acesso de hoje (para voltar atrás)
--    2. cria a marca "entra nas duas empresas" no perfil
--    3. cria a função que diz se um documento é da minha empresa
--    4. troca as regras de acesso de docs, perfis, rastreio e assinaturas
--       para conferirem a empresa
--    5. tira o 'dv' (Divinópolis) da trava da numeração
--
--  POR QUE É SEGURO RODAR AGORA
--    Hoje TODOS os perfis estão em 'mf' e TODO documento com empresa está
--    em 'mf'. O que está sem empresa (produtos, centros, fornecedores e
--    configurações) continua visível para todos — é só quando o sistema
--    gravar a empresa neles que a separação passa a valer. Ou seja:
--    ninguém perde acesso no instante em que isto roda.
--
--  COMO RODAR
--    Supabase › SQL Editor › New query › cole tudo › Run.
--
--  COMO VOLTAR ATRÁS
--    O bloco 1 guarda as regras antigas em backup.politicas_20261023.
--    O fim do arquivo tem o comando de volta, comentado.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. CÓPIA DE SEGURANÇA DAS REGRAS DE ACESSO DE HOJE
-- ---------------------------------------------------------------------
create schema if not exists backup;

-- a cópia é feita UMA VEZ. Rodando este arquivo de novo (por erro no meio, por exemplo),
-- ela NÃO é refeita — senão guardaria as regras já trocadas e a original se perderia.
create table if not exists backup.politicas_20261023 as
select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
  from pg_policies
 where schemaname = 'public';

-- confira: deve trazer as regras de ANTES da troca (hoje são 39)
select count(*) as regras_guardadas from backup.politicas_20261023;


-- ---------------------------------------------------------------------
-- 2. A MARCA "ENTRA NAS DUAS EMPRESAS"
--    Decisão dele: só Wagner e Renan Administrador.
-- ---------------------------------------------------------------------
alter table public.perfis
  add column if not exists ambas boolean not null default false;

comment on column public.perfis.ambas is
  'true = este usuário entra nas duas empresas (uma de cada vez, pelo login). Regra do Wagner, 23/10/2026.';

-- os dois são identificados pelo CÓDIGO do usuário (user_id), não pelo nome: nome de
-- perfil pode ser editado e aí a marca iria para a pessoa errada.
--   Wagner               wagner@minasfiltrosonline.com.br
--   Renan Administrador  renan@minasfiltrosonline.com.br
update public.perfis set ambas = (user_id in (
  'e5eff953-e84a-4945-af4c-e8ed9c34a44a',   -- Wagner
  '20692b72-8775-48c7-96d6-fbaf111d4d4d'    -- Renan Administrador
));

-- confira: só os dois podem ficar com "sim"
select nome, funcao, loja, ativo, ambas from public.perfis order by ambas desc, nome;

-- ATENÇÃO: perfil ATIVO sem empresa gravada passaria a enxergar quase nada.
-- Esta consulta tem de voltar VAZIA. Voltando alguém, grave a empresa dele antes de seguir.
select nome, funcao, loja, 'PERFIL SEM EMPRESA — corrija antes de seguir' as aviso
  from public.perfis
 where ativo and (loja is null or btrim(loja) = '');


-- ---------------------------------------------------------------------
-- 3. A FUNÇÃO QUE DIZ SE O DOCUMENTO É DA MINHA EMPRESA
--    Documento SEM empresa continua de todos: é o caso dos produtos,
--    centros de custo, fornecedores e configurações até o sistema gravar
--    a empresa neles. Depois disso, esta mesma função já os separa.
-- ---------------------------------------------------------------------
create or replace function public.minha_empresa(p_loja text)
returns boolean
language sql
stable
security definer
set search_path to 'public','pg_temp'
as $$
  select p_loja is null
      or exists (
           select 1 from public.perfis p
            where p.user_id = auth.uid()
              and p.ativo
              and (p.loja = p_loja or p.ambas)
         );
$$;

comment on function public.minha_empresa(text) is
  'O documento é da empresa de quem está logado? Documento sem empresa é de todos. Regra do Wagner, 23/10/2026.';


-- ---------------------------------------------------------------------
-- 4. AS REGRAS DE ACESSO PASSAM A CONFERIR A EMPRESA
-- ---------------------------------------------------------------------

-- 4.1  docs: ler, gravar e alterar
drop policy if exists docs_select_geral on public.docs;
create policy docs_select_geral on public.docs for select to authenticated
  using ( colecao_geral(colecao)
          and (select meu_nome()) is not null
          and public.minha_empresa(loja) );

drop policy if exists docs_insert_geral on public.docs;
create policy docs_insert_geral on public.docs for insert to authenticated
  with check ( colecao_geral(colecao)
               and (select meu_nome()) is not null
               and public.minha_empresa(loja) );

drop policy if exists docs_update_geral on public.docs;
create policy docs_update_geral on public.docs for update to authenticated
  using ( colecao_geral(colecao)
          and (select meu_nome()) is not null
          and public.minha_empresa(loja) )
  with check ( colecao_geral(colecao)
               and (select meu_nome()) is not null
               and public.minha_empresa(loja) );

-- 4.2  docs: configurações (passam a ser de cada empresa)
drop policy if exists docs_select_config on public.docs;
create policy docs_select_config on public.docs for select to authenticated
  using ( colecao = 'config'
          and (select meu_nome()) is not null
          and public.minha_empresa(loja) );

drop policy if exists docs_config_gestor on public.docs;
create policy docs_config_gestor on public.docs for all to authenticated
  using ( colecao = 'config'
          and (select minha_funcao()) = any (array['Administrador','Financeiro'])
          and public.minha_empresa(loja) )
  with check ( colecao = 'config'
               and (select minha_funcao()) = any (array['Administrador','Financeiro'])
               and public.minha_empresa(loja) );

-- 4.3  docs: ponto (cada empresa com o seu)
drop policy if exists docs_select_ponto_gestao on public.docs;
create policy docs_select_ponto_gestao on public.docs for select to authenticated
  using ( colecao = 'pontos'
          and ((select sou_gestor_rh()) or (select minha_funcao()) = 'Gerente')
          and public.minha_empresa(loja) );

-- 4.4  docs: apagar (a regra já olhava a loja; agora usa a mesma função)
drop policy if exists docs_delete_gestao on public.docs;
create policy docs_delete_gestao on public.docs for delete to authenticated
  using ( colecao_geral(colecao)
          and (select minha_funcao()) = any (array['Administrador','Financeiro','Gerente'])
          and public.minha_empresa(loja) );

-- 4.5  perfis: cada um enxerga a equipe da própria empresa
drop policy if exists perfis_select_autenticado on public.perfis;
create policy perfis_select_autenticado on public.perfis for select to authenticated
  using ( (select meu_nome()) is not null
          and ( user_id = auth.uid()                       -- o meu, sempre
                or public.minha_empresa(loja) ) );

-- 4.6  numeradores: a numeração é de cada empresa
drop policy if exists numeradores_select_autenticado on public.numeradores;
create policy numeradores_select_autenticado on public.numeradores for select to authenticated
  using ( (select meu_nome()) is not null
          and public.minha_empresa(loja) );

-- 4.7  rastreio: a gestão vê só a equipe da própria empresa
drop policy if exists rastro_pontos_select on public.rastro_pontos;
create policy rastro_pontos_select on public.rastro_pontos for select to authenticated
  using ( user_id = auth.uid()
          or (sou_gestao_rastreio() and public.minha_empresa(loja)) );

drop policy if exists rastro_paradas_select on public.rastro_paradas;
create policy rastro_paradas_select on public.rastro_paradas for select to authenticated
  using ( user_id = auth.uid()
          or (sou_gestao_rastreio() and public.minha_empresa(loja)) );

drop policy if exists rastro_paradas_update on public.rastro_paradas;
create policy rastro_paradas_update on public.rastro_paradas for update to authenticated
  using ( user_id = auth.uid()
          or (sou_gestao_rastreio() and public.minha_empresa(loja)) )
  with check ( user_id = auth.uid()
               or (sou_gestao_rastreio() and public.minha_empresa(loja)) );

-- 4.8  links de assinatura: cada empresa com os seus
drop policy if exists assinaturas_link_select on public.assinaturas_link;
create policy assinaturas_link_select on public.assinaturas_link for select to authenticated
  using ( meu_nome() is not null and public.minha_empresa(loja) );

drop policy if exists assinaturas_link_insert on public.assinaturas_link;
create policy assinaturas_link_insert on public.assinaturas_link for insert to authenticated
  with check ( meu_nome() is not null and public.minha_empresa(loja) );

drop policy if exists assinaturas_link_update on public.assinaturas_link;
create policy assinaturas_link_update on public.assinaturas_link for update to authenticated
  using ( meu_nome() is not null and public.minha_empresa(loja) )
  with check ( meu_nome() is not null and public.minha_empresa(loja) );

-- (as funções venda_para_assinar e assinar_venda continuam como estão:
--  elas são security definer e abrem UMA linha pelo token do link, para o
--  cliente que não tem login. A separação por empresa não as atinge.)


-- ---------------------------------------------------------------------
-- 5. DIVINÓPOLIS SAI DA TRAVA DA NUMERAÇÃO
--    Decisão dele: remoção total da LOJA. Divinópolis como cidade de
--    cliente continua existindo normalmente.
-- ---------------------------------------------------------------------
-- A função é a MESMA que já está no banco, copiada linha por linha: muda só a lista de
-- lojas da trava (saiu o 'dv') e a mensagem de erro. O tipo de retorno continua INTEGER e os
-- parâmetros continuam (p_loja text, p_tipo text) — trocar qualquer um dos dois exigiria
-- DROP FUNCTION, que derrubaria a numeração dos pedidos.
create or replace function public.proximo_numero(p_loja text, p_tipo text)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
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
    v_loja := '*';                      -- contador unico das lojas
  elsif v_loja not in ('mf','wf') then
    raise exception 'proximo_numero: loja invalida (%). Use mf ou wf.', v_loja
      using errcode = '22023';
  end if;

  insert into public.numeradores as n (loja, tipo, ultimo)
  values (v_loja, v_tipo, public.base_numerador(v_tipo))
  on conflict (loja, tipo)
  do update set ultimo = n.ultimo + 1, atualizado_em = now()
  returning n.ultimo into v_num;

  return v_num;
end;
$function$;


-- ---------------------------------------------------------------------
-- 6. CONFERÊNCIA FINAL
-- ---------------------------------------------------------------------
select tablename, policyname, cmd
  from pg_policies
 where schemaname = 'public'
   and (qual like '%minha_empresa%' or with_check like '%minha_empresa%')
 order by tablename, policyname;
-- esperado: 14 regras conferindo a empresa


-- =====================================================================
--  PARA VOLTAR ATRÁS
--  Está pronto no arquivo ao lado: supabase/empresas-voltar-atras.sql
--  É só colar e rodar — não precisa editar nada.
-- =====================================================================
