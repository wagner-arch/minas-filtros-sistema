-- Permissao para o documento config/celebracoes
--
-- Para que serve: config/celebracoes guarda apenas QUAIS PARABENS ja foram
-- mostrados para cada pessoa (meta do dia, da semana e do mes). Nao ha dinheiro,
-- venda nem cadastro nesse documento.
--
-- Por que rodar: config/* so pode ser gravado por Administrador e Financeiro.
-- O sistema grava celebracoes no boot de QUALQUER usuario, entao sem esta
-- excecao o login de um vendedor batia em "Sem permissao para gravar
-- config/celebracoes" e acendia a faixa vermelha na tela (relato do Wagner em
-- 24/09, com print).
--
-- Como rodar: painel do Supabase > SQL Editor > cole tudo > Run.
-- Pode rodar quantas vezes quiser: as policies sao recriadas.
--
-- Depois disso a lembranca dos parabens volta a ser gravada no banco e passa a
-- valer em qualquer aparelho. Mesmo sem rodar, o sistema ja nao mostra mais o
-- aviso vermelho por causa disso (a partir da v217): a lembranca fica guardada
-- no proprio aparelho.

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

-- Conferencia: deve listar as duas policies acima.
select policyname, cmd
  from pg_policies
 where schemaname = 'public'
   and tablename = 'docs'
   and policyname like 'docs_config_celebracoes%'
 order by policyname;
