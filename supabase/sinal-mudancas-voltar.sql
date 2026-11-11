-- =====================================================================
-- VOLTAR ATRÁS da v541 (aviso de mudança entre aparelhos)
--
-- Quando usar: se qualquer gravação falhar depois de aplicar o
-- supabase/sinal-mudancas.sql. Rode tudo de uma vez no SQL do Supabase.
--
-- O que faz:
--   1. tira o gatilho, a função e a regra de leitura do aviso novo
--      (os aparelhos na v541 caem sozinhos na conferência de 30 s);
--   2. devolve a tabela docs ao "postgres_changes" antigo (o aviso dos
--      pedidos da v540), caso seja preciso voltar o site para a v540.
-- Nenhum dado é tocado. Cópia do estado de antes: backup.sinal_antes_v541.
-- =====================================================================

drop trigger if exists docs_sinal_mudanca on public.docs;
drop function if exists public.docs_sinal_mudanca();
drop policy if exists sinal_mudancas_ler on realtime.messages;

do $volta$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'docs') then
    alter publication supabase_realtime add table public.docs;
  end if;
end $volta$;

-- conferência: as três primeiras devem dar 0 e a última 1
select (select count(*) from pg_trigger where tgname = 'docs_sinal_mudanca') as gatilho,
       (select count(*) from pg_proc where proname = 'docs_sinal_mudanca') as funcao,
       (select count(*) from pg_policies where policyname = 'sinal_mudancas_ler') as regra,
       (select count(*) from pg_publication_tables
         where pubname = 'supabase_realtime' and tablename = 'docs') as aviso_antigo;
