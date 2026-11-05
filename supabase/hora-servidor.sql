-- HORA DO SERVIDOR (05/11/2026, v508): a trava do ponto ("o sistema só funciona depois de bater o
-- ponto") usa a hora do banco, e não a do aparelho, para ninguém burlar mudando o relógio.
-- Só devolve a hora atual; não lê nem grava dado nenhum.
create or replace function public.hora_servidor()
returns timestamptz
language sql
stable
security invoker
set search_path = public
as $$ select now() $$;

revoke all on function public.hora_servidor() from public;
grant execute on function public.hora_servidor() to authenticated;
