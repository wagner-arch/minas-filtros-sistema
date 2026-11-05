-- LEMBRETE DE PONTO NO CELULAR (05/11/2026, pedido do Wagner)
--
-- O QUE FAZ: de minuto em minuto, o proprio banco confere quem precisa de aviso para bater o ponto
-- e, so quando ha alguem, chama a funcao "lembrete-ponto" (Edge Function), que manda a notificacao
-- ao celular (aplicativo Android, pelo Firebase) e ao iPhone na Tela de Inicio (Web Push).
--
-- REGRAS (iguais as da tela):
--   * so quem tem jornada (entrada e saida) e "Bate ponto: sim", ativo, de segunda a sexta;
--   * nao avisa em folga, ferias, falta justificada, falta, feriado da empresa nem com o
--     liga/desliga "Lembretes de ponto no celular" desligado (config/lembrete_ponto; wf:lembrete_ponto);
--   * para cada marcacao (entrada, saida do almoco, volta do almoco, saida): 3 minutos ANTES o
--     primeiro aviso; a partir do horario, a cada 2 minutos enquanto nao bater; para ao bater e na
--     meia-noite. A volta do almoco e a saida do almoco batida + a duracao do almoco da jornada;
--   * hora do servidor, em Brasilia.
--
-- PESO: le so a lista de colaboradores (config/usuarios), os feriados e o liga/desliga (config) e
-- as batidas DO DIA (indice ix_docs_pontos_data). Nunca le clientes, aparelhos ou pedidos.
-- A chamada para fora so acontece quando ha aviso a mandar.
--
-- NENHUMA CHAVE NESTE ARQUIVO: o segredo entre o banco e a funcao e as chaves do Web Push ficam no
-- cofre do banco (vault), gravados a parte. A conta do Firebase fica nos segredos da funcao.

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- ---------- o celular de cada pessoa ----------
create table if not exists public.dispositivos_ponto(
  user_id      uuid not null default auth.uid() references auth.users(id) on delete cascade,
  aparelho     text not null,                 -- codigo do aparelho (o aplicativo ou o navegador)
  nome         text not null default '',      -- vem do perfil, nao do aparelho (gatilho abaixo)
  loja         text,
  tipo         text not null check (tipo in ('android','web')),
  token        text,                          -- endereco do Firebase (Android)
  assinatura   jsonb,                         -- endereco do Web Push (iPhone e navegadores)
  permissao    text not null default 'perguntar' check (permissao in ('autorizado','recusado','perguntar')),
  modelo       text,
  ativo        boolean not null default true,
  atualizado_em timestamptz not null default now(),
  primary key (user_id, aparelho)
);
alter table public.dispositivos_ponto enable row level security;

create or replace function public.dispositivos_ponto_nome() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.nome := coalesce((select p.nome from public.perfis p where p.user_id = new.user_id), new.nome, '');
  new.atualizado_em := now();
  return new;
end $$;
drop trigger if exists tg_dispositivos_ponto_nome on public.dispositivos_ponto;
create trigger tg_dispositivos_ponto_nome before insert or update on public.dispositivos_ponto
  for each row execute function public.dispositivos_ponto_nome();

drop policy if exists dp_proprio on public.dispositivos_ponto;
create policy dp_proprio on public.dispositivos_ponto for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
drop policy if exists dp_admin_ve on public.dispositivos_ponto;
create policy dp_admin_ve on public.dispositivos_ponto for select to authenticated
  using ((select public.minha_funcao()) = 'Administrador');

-- ---------- o registro dos avisos (para nao repetir no mesmo minuto e para conferir) ----------
create table if not exists public.lembretes_ponto_log(
  id        bigint generated always as identity primary key,
  dia       date not null,
  loja      text not null,
  nome      text not null,
  marc      text not null,
  minuto    text not null,
  tipo      text not null,
  titulo    text not null,
  texto     text not null,
  criado_em timestamptz not null default now(),
  enviados  int,
  resultado text,
  unique (dia, loja, nome, marc, minuto)
);
alter table public.lembretes_ponto_log enable row level security;
drop policy if exists lpl_admin_ve on public.lembretes_ponto_log;
create policy lpl_admin_ve on public.lembretes_ponto_log for select to authenticated
  using ((select public.minha_funcao()) = 'Administrador');

-- neste banco tabela nova NAO ganha permissao sozinha (ver permissao-service-role.sql): sem estas
-- linhas a funcao de envio nao le os celulares nem grava o resultado, e ninguem percebe.
grant select, insert, update on public.dispositivos_ponto to authenticated;
grant select on public.lembretes_ponto_log to authenticated;
grant select, insert, update, delete on public.dispositivos_ponto to service_role;
grant select, insert, update, delete on public.lembretes_ponto_log to service_role;

-- ---------- horas ----------
create or replace function public.ponto_hm_min(t text) returns int language sql immutable as $$
  select case when t ~ '^[0-9]{1,2}:[0-9]{2}' then split_part(t,':',1)::int*60 + substr(split_part(t,':',2),1,2)::int end
$$;
create or replace function public.ponto_min_hm(m int) returns text language sql immutable as $$
  select lpad(((m/60) % 24)::text,2,'0') || ':' || lpad((m % 60)::text,2,'0')
$$;

-- ---------- a conta (sem ler nada: recebe tudo pronto; e ela que os testes conferem) ----------
create or replace function public.lembretes_ponto_calc(
  p_data date, p_min int, p_pessoas jsonb, p_pontos jsonb, p_feriados jsonb, p_ligado jsonb)
returns table(loja text, nome text, marc text, prevista text, tipo text, titulo text, texto text)
language plpgsql immutable as $$
declare
  u jsonb; pt jsonb; lj text; m text; prev int; bat text; d int; dur int; ai text; hj text;
  nomes  jsonb := '{"checkin":"entrada","almocoIni":"saída do almoço","almocoFim":"volta do almoço","checkout":"saída"}';
  campos jsonb := '{"checkin":"entrada","almocoIni":"almocoIni","almocoFim":"almocoFim","checkout":"saida"}';
  padrao jsonb := '{"almocoIni":"12:00","almocoFim":"13:30"}';   -- o mesmo padrao da tela (JORNADA_PADRAO)
begin
  if extract(isodow from p_data) > 5 then return; end if;            -- so de segunda a sexta
  for u in select e from jsonb_array_elements(coalesce(p_pessoas,'[]'::jsonb)) e loop
    if coalesce(u->>'ativo','true') = 'false' then continue; end if;
    if coalesce(u->>'entrada','') = '' or coalesce(u->>'saida','') = '' or coalesce(u->>'bateponto','') <> 'sim' then continue; end if;
    lj := coalesce(nullif(u->>'loja',''),'mf');
    if coalesce(p_ligado->>lj,'true') = 'false' then continue; end if;
    if coalesce(p_feriados->lj,'[]'::jsonb) ? p_data::text then continue; end if;
    pt := null;
    select e into pt from jsonb_array_elements(coalesce(p_pontos,'[]'::jsonb)) e
      where e->>'colaborador' = u->>'nome' and coalesce(e->>'loja','mf') = lj and e->>'data' = p_data::text limit 1;
    if pt is not null and coalesce(pt->>'tipo','normal') in ('folga','ferias','justificada','falta') then continue; end if;
    foreach m in array array['checkin','almocoIni','almocoFim','checkout'] loop
      bat := pt->m->>'hora';
      if coalesce(bat,'') <> '' then continue; end if;                  -- ja bateu: para
      hj := coalesce(nullif(u->>(campos->>m),''), padrao->>m);
      prev := public.ponto_hm_min(hj);
      if prev is null then continue; end if;
      if m = 'almocoFim' then
        ai := pt->'almocoIni'->>'hora';
        dur := public.ponto_hm_min(coalesce(nullif(u->>'almocoFim',''),padrao->>'almocoFim'))
             - public.ponto_hm_min(coalesce(nullif(u->>'almocoIni',''),padrao->>'almocoIni'));
        if coalesce(ai,'') <> '' and dur > 0 then prev := public.ponto_hm_min(ai) + dur; end if;
      end if;
      if prev >= 24*60 then continue; end if;                           -- passa da meia-noite: para
      d := p_min - prev;
      if d = -3 then
        tipo := 'antes';
        texto := format('Daqui a 3 minutos é o seu horário de %s (%s). Não esqueça de bater o ponto.', nomes->>m, public.ponto_min_hm(prev));
      elsif d >= 0 and d % 2 = 0 then
        tipo := 'atraso';
        texto := format('Já são %s e você ainda não bateu o ponto de %s.', public.ponto_min_hm(p_min), nomes->>m);
      else
        continue;
      end if;
      loja := lj; nome := u->>'nome'; marc := m; prevista := public.ponto_min_hm(prev); titulo := 'Lembrete de ponto';
      return next;
    end loop;
  end loop;
end $$;

-- ---------- quem precisa de aviso AGORA (le o banco, de leve) ----------
create or replace function public.lembretes_ponto_agora(p_agora timestamptz default now())
returns table(loja text, nome text, marc text, prevista text, tipo text, titulo text, texto text)
language plpgsql stable security definer set search_path = public as $$
declare
  loc timestamp := p_agora at time zone 'America/Sao_Paulo';
  dia date := loc::date;
  mi  int  := extract(hour from loc)::int*60 + extract(minute from loc)::int;
  pessoas jsonb; pontos jsonb; fer jsonb := '{}'; lig jsonb := '{}'; l text; doc jsonb; achou boolean;
  nacionais jsonb := '["2026-01-01","2026-04-03","2026-04-21","2026-05-01","2026-09-07","2026-10-12","2026-11-02","2026-11-15","2026-11-20","2026-12-25","2027-01-01","2027-03-26","2027-04-21","2027-05-01","2027-09-07","2027-10-12","2027-11-02","2027-11-15","2027-11-20","2027-12-25"]';
begin
  if extract(isodow from dia) > 5 then return; end if;
  select d.data->'lista' into pessoas from docs d where d.colecao = 'config' and d.id = 'usuarios';
  if pessoas is null then return; end if;
  foreach l in array array['mf','wf'] loop
    select d.data, true into doc, achou from docs d where d.colecao = 'config' and d.id = case when l = 'mf' then 'feriados' else 'wf:feriados' end;
    if coalesce(achou,false) and jsonb_typeof(doc->'lista') = 'array' then
      fer := fer || jsonb_build_object(l, coalesce((select jsonb_agg(f->>'data') from jsonb_array_elements(doc->'lista') f
                                                    where coalesce(f->>'ativo','true') <> 'false'),'[]'::jsonb));
    else
      fer := fer || jsonb_build_object(l, nacionais);
    end if;
    achou := false; doc := null;
    select d.data, true into doc, achou from docs d where d.colecao = 'config' and d.id = case when l = 'mf' then 'lembrete_ponto' else 'wf:lembrete_ponto' end;
    lig := lig || jsonb_build_object(l, case when coalesce(achou,false) then coalesce(doc->>'ligado','true') <> 'false' else true end);
    achou := false; doc := null;
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('colaborador', d.data->>'colaborador', 'data', d.data->>'data', 'loja', d.loja,
           'tipo', d.data->>'tipo', 'checkin', d.data->'checkin', 'almocoIni', d.data->'almocoIni',
           'almocoFim', d.data->'almocoFim', 'checkout', d.data->'checkout')), '[]'::jsonb)
    into pontos
    from docs d where d.colecao = 'pontos' and d.loja in ('mf','wf') and d.data->>'data' = dia::text;
  return query select * from public.lembretes_ponto_calc(dia, mi, pessoas, pontos, fer, lig);
end $$;

-- ---------- o disparo de cada minuto ----------
create or replace function public.disparar_lembretes_ponto() returns int
language plpgsql security definer set search_path = public as $$
declare
  loc timestamp := now() at time zone 'America/Sao_Paulo';
  corpo jsonb; seg text; n int;
begin
  with novos as (
    insert into public.lembretes_ponto_log(dia, loja, nome, marc, minuto, tipo, titulo, texto)
      select loc::date, a.loja, a.nome, a.marc, to_char(loc,'HH24:MI'), a.tipo, a.titulo, a.texto
        from public.lembretes_ponto_agora(now()) a
      on conflict do nothing
      returning id, loja, nome, marc, tipo, titulo, texto)
  select count(*), coalesce(jsonb_agg(to_jsonb(novos)),'[]'::jsonb) into n, corpo from novos;
  if n = 0 then return 0; end if;
  select decrypted_secret into seg from vault.decrypted_secrets where name = 'lembrete_ponto_segredo';
  if seg is null then return -1; end if;
  perform net.http_post(
    url := 'https://clnccthtvfuetmfwuanu.supabase.co/functions/v1/lembrete-ponto',
    body := jsonb_build_object('avisos', corpo),
    headers := jsonb_build_object('Content-Type','application/json','x-segredo', seg),
    timeout_milliseconds := 20000);
  return n;
end $$;
revoke all on function public.disparar_lembretes_ponto() from public, anon, authenticated;
revoke all on function public.lembretes_ponto_agora(timestamptz) from public, anon, authenticated;

-- ---------- o que so a funcao de envio (service_role) pode ler ----------
create or replace function public.lembrete_ponto_confere(p_segredo text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from vault.decrypted_secrets where name = 'lembrete_ponto_segredo' and decrypted_secret = p_segredo)
$$;
create or replace function public.lembrete_ponto_chaves_web() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'publica', (select decrypted_secret from vault.decrypted_secrets where name = 'web_push_publica'),
    'privada', (select decrypted_secret from vault.decrypted_secrets where name = 'web_push_privada'))
$$;
revoke all on function public.lembrete_ponto_confere(text) from public, anon, authenticated;
revoke all on function public.lembrete_ponto_chaves_web() from public, anon, authenticated;
grant execute on function public.lembrete_ponto_confere(text) to service_role;
grant execute on function public.lembrete_ponto_chaves_web() to service_role;

-- ---------- as tarefas agendadas ----------
-- a cada minuto (o proprio disparo para no fim de semana); e uma faxina diaria as 03:10 (Brasilia)
-- do historico do agendador (que ganha uma linha por execucao) e dos avisos com mais de 30 dias.
select cron.unschedule(jobid) from cron.job where jobname in ('lembretes-ponto','lembretes-ponto-faxina');
select cron.schedule('lembretes-ponto', '* * * * *', $$select public.disparar_lembretes_ponto()$$);
select cron.schedule('lembretes-ponto-faxina', '10 6 * * *', $$
  delete from cron.job_run_details where end_time < now() - interval '2 days';
  delete from public.lembretes_ponto_log where criado_em < now() - interval '30 days';
$$);

-- VOLTAR ATRAS (desliga tudo, sem apagar nada):
--   select cron.unschedule('lembretes-ponto');
