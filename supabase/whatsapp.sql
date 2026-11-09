-- WHATSAPP PELO SISTEMA (06/11/2026, plano aprovado pelo Wagner)
-- Cada colaborador marcado pelo Administrador ("Pode conectar o WhatsApp", campo zapConectar na ficha,
-- config/usuarios) conecta o PRÓPRIO chip lendo um QR Code: uma conexão (instância da Evolution API)
-- por pessoa. Quem fala com a Evolution é SÓ a função "whatsapp" do servidor (supabase/functions/
-- whatsapp): a chave fica no cofre e nunca vai para o navegador. A tela só pede "conectar", "enviar
-- este PDF/este texto para este cliente" etc. Para trocar pelo caminho oficial da Meta no futuro,
-- troca-se só o "provedor" dentro da função.
--
-- whatsapp_conexoes: a conexão de cada pessoa (uma por usuário, presa à empresa em que conectou).
-- whatsapp_envios:   tudo o que foi enviado (ou aberto no celular quando não deu), por quem, quando.
-- Os usuários só LEEM (a própria conexão e os próprios envios; o Administrador os da empresa).
-- Quem grava é a função, com a chave de serviço.

create table if not exists public.whatsapp_conexoes (
  user_id         uuid primary key references auth.users(id) on delete cascade,
  loja            text not null,
  nome            text not null default '',
  instancia       text not null unique,
  situacao        text not null default 'desconectado',   -- conectado | aguardando | desconectado
  numero          text,
  conectado_em    timestamptz,
  desconectado_em timestamptz,
  motivo          text,                                    -- por que caiu ou foi desligada
  aviso_visto     boolean not null default true,           -- false: caiu e a pessoa ainda não viu no sino
  atualizado_em   timestamptz not null default now()
);
alter table public.whatsapp_conexoes enable row level security;

create table if not exists public.whatsapp_envios (
  id            bigint generated always as identity primary key,
  loja          text not null,
  user_id       uuid not null,
  nome          text not null default '',
  cliente_id    text,
  cliente_nome  text,
  telefone      text,
  tipo          text not null,           -- pedido_pdf | link_assinatura | manutencao (Etapa 2, 09/11)
  ref_id        text,                    -- o pedido
  ref_numero    text,
  situacao      text not null,           -- enviado | falhou | celular
  motivo        text,
  mensagem_id   text,
  criado_em     timestamptz not null default now()
);
create index if not exists whatsapp_envios_user_quando on public.whatsapp_envios (user_id, criado_em desc);
create index if not exists whatsapp_envios_loja_quando on public.whatsapp_envios (loja, criado_em desc);
alter table public.whatsapp_envios enable row level security;

drop policy if exists zapcon_le on public.whatsapp_conexoes;
create policy zapcon_le on public.whatsapp_conexoes for select to authenticated
  using (user_id = (select auth.uid())
         or ((select public.minha_funcao()) = 'Administrador' and public.minha_empresa(loja)));
drop policy if exists zapenv_le on public.whatsapp_envios;
create policy zapenv_le on public.whatsapp_envios for select to authenticated
  using (user_id = (select auth.uid())
         or ((select public.minha_funcao()) = 'Administrador' and public.minha_empresa(loja)));

-- neste banco tabela nova não ganha permissão sozinha
grant select on public.whatsapp_conexoes, public.whatsapp_envios to authenticated;
grant all on public.whatsapp_conexoes, public.whatsapp_envios to service_role;

-- a função lê endereço, chave e segredo do cofre (só o servidor)
create or replace function public.whatsapp_config() returns json
language sql security definer set search_path = public, vault as $$
  select json_build_object(
    'url',     (select decrypted_secret from vault.decrypted_secrets where name = 'evolution_api_url'),
    'chave',   (select decrypted_secret from vault.decrypted_secrets where name = 'evolution_api_chave'),
    'segredo', (select decrypted_secret from vault.decrypted_secrets where name = 'whatsapp_segredo'))
$$;
revoke all on function public.whatsapp_config() from public, anon, authenticated;
grant execute on function public.whatsapp_config() to service_role;

-- faxina a cada 5 minutos: confere a situação de cada conexão (se o aviso da Evolution se perdeu) e
-- desconecta sozinha a de quem foi inativado ou perdeu a marca. Só chama a função; ela faz o resto.
create or replace function public.disparar_faxina_whatsapp() returns void
language plpgsql security definer set search_path = public, vault as $$
declare v_seg text;
begin
  if not exists (select 1 from public.whatsapp_conexoes) then return; end if;
  select decrypted_secret into v_seg from vault.decrypted_secrets where name = 'whatsapp_segredo';
  perform net.http_post(
    url := 'https://clnccthtvfuetmfwuanu.supabase.co/functions/v1/whatsapp',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-segredo', v_seg),
    body := jsonb_build_object('acao', 'faxina'),
    timeout_milliseconds := 25000);
end $$;
revoke all on function public.disparar_faxina_whatsapp() from public, anon, authenticated;

-- o segredo da faxina e do aviso da Evolution (webhook) nasce no cofre:
--   select vault.create_secret(encode(gen_random_bytes(24),'hex'), 'whatsapp_segredo', '...');
-- a tarefa agendada:
--   select cron.schedule('whatsapp-faxina', '*/5 * * * *', 'select public.disparar_faxina_whatsapp()');
-- desligar: select cron.unschedule('whatsapp-faxina');
