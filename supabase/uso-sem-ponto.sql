-- USO DO SISTEMA SEM INTERNET E SEM O PONTO BATIDO (05/11/2026, proposta B do Wagner)
-- Sem internet o sistema abre so para consulta, mesmo depois do horario de entrada sem batida; o
-- celular anota cada uso e, com a internet de volta, manda para esta tabela. O Administrador ve no
-- sino. Cada um grava so o proprio (o nome vem do perfil, no banco); so o Administrador le todos.
create table if not exists public.uso_sem_ponto(
  id         bigint generated always as identity primary key,
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nome       text not null default '',
  loja       text not null,
  dia        date not null,
  de         text not null,
  ate        text not null,
  motivo     text,
  criado_em  timestamptz not null default now()
);
alter table public.uso_sem_ponto enable row level security;

create or replace function public.uso_sem_ponto_nome() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.user_id := auth.uid();
  new.nome := coalesce((select p.nome from public.perfis p where p.user_id = auth.uid()), '');
  return new;
end $$;
drop trigger if exists tg_uso_sem_ponto_nome on public.uso_sem_ponto;
create trigger tg_uso_sem_ponto_nome before insert on public.uso_sem_ponto
  for each row execute function public.uso_sem_ponto_nome();

drop policy if exists usp_proprio_grava on public.uso_sem_ponto;
create policy usp_proprio_grava on public.uso_sem_ponto for insert to authenticated
  with check (user_id = (select auth.uid()));
drop policy if exists usp_admin_le on public.uso_sem_ponto;
create policy usp_admin_le on public.uso_sem_ponto for select to authenticated
  using ((select public.minha_funcao()) = 'Administrador' or user_id = (select auth.uid()));

-- neste banco tabela nova nao ganha permissao sozinha
grant select, insert on public.uso_sem_ponto to authenticated;
grant select, insert, update, delete on public.uso_sem_ponto to service_role;
