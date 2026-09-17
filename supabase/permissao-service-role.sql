-- Correção de 17/09: libera as tabelas para o service_role (Edge Functions).
-- Rode no SQL Editor do Supabase. Pode rodar mais de uma vez.
grant all on public.docs        to service_role;
grant all on public.perfis      to service_role;
grant all on public.numeradores to service_role;
