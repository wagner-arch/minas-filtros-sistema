-- =====================================================================
-- LINK DE ASSINATURA DO CLIENTE  (Sistema Minas Filtros, 03/10/2026)
--
-- Para que serve: a venda fechada por telefone precisa da assinatura do
-- cliente. O sistema gera um LINK; o cliente abre no celular dele, le o
-- pedido inteiro (o mesmo documento do PDF), assina com o dedo e pronto:
-- a assinatura volta para o sistema e entra no pedido.
--
-- Como rodar: painel do Supabase > SQL Editor > cole este arquivo > Run.
-- Pode rodar quantas vezes quiser (tudo e "if not exists" / "or replace").
--
-- Seguranca, em uma linha: o cliente NAO entra no banco. Ele so chama
-- duas funcoes (security definer) que leem e gravam UMA linha, a do token
-- que esta no link dele. Nenhuma tabela fica aberta para quem nao tem login.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Tabela: um link por venda enviada para assinar
-- ---------------------------------------------------------------------
create table if not exists public.assinaturas_link (
  token          uuid        primary key default gen_random_uuid(),
  loja           text,
  pedido_id      text        not null,
  pedido_numero  integer,
  cliente        text,
  cliente_doc    text,
  total          numeric,
  documento      text        not null,   -- HTML do pedido, do jeito que o cliente ve
  estilo         text,                   -- CSS do documento (vai junto, para nao depender do sistema)
  criado_por     text,
  criado_em      timestamptz not null default now(),
  expira_em      timestamptz not null,
  status         text        not null default 'pendente',
  assinatura     text,                   -- imagem da assinatura (dataURL)
  assinante_nome text,
  assinante_doc  text,
  assinado_em    timestamptz,
  navegador      text,
  aplicado_em    timestamptz,            -- quando o sistema trouxe a assinatura para o pedido
  constraint assinaturas_link_status_ok
    check (status in ('pendente','assinado','cancelado')),
  constraint assinaturas_link_doc_tamanho
    check (length(documento) <= 4000000),
  constraint assinaturas_link_assinatura_tamanho
    check (assinatura is null or length(assinatura) <= 2000000)
);

alter table public.assinaturas_link add column if not exists estilo text;
alter table public.assinaturas_link add column if not exists navegador text;
alter table public.assinaturas_link add column if not exists aplicado_em timestamptz;

create index if not exists assinaturas_link_pedido_idx
  on public.assinaturas_link (pedido_id);
create index if not exists assinaturas_link_status_idx
  on public.assinaturas_link (status, criado_em desc);

comment on table public.assinaturas_link is
  'Link enviado ao cliente para ele ver e assinar a venda (vendas por telefone).';

-- ---------------------------------------------------------------------
-- 2. RLS: quem tem login cuida dos links; quem nao tem nao enxerga nada
-- ---------------------------------------------------------------------
alter table public.assinaturas_link enable row level security;

drop policy if exists assinaturas_link_select on public.assinaturas_link;
create policy assinaturas_link_select on public.assinaturas_link
  for select to authenticated
  using (public.meu_nome() is not null);

drop policy if exists assinaturas_link_insert on public.assinaturas_link;
create policy assinaturas_link_insert on public.assinaturas_link
  for insert to authenticated
  with check (public.meu_nome() is not null);

drop policy if exists assinaturas_link_update on public.assinaturas_link;
create policy assinaturas_link_update on public.assinaturas_link
  for update to authenticated
  using (public.meu_nome() is not null)
  with check (public.meu_nome() is not null);

revoke all on public.assinaturas_link from anon, public;
grant select, insert, update on public.assinaturas_link to authenticated;
grant all on public.assinaturas_link to service_role;

-- ---------------------------------------------------------------------
-- 3. O que o CLIENTE pode fazer: duas funcoes, so com o token do link
-- ---------------------------------------------------------------------

-- 3.1 abrir a venda para ler e assinar
create or replace function public.venda_para_assinar(p_token uuid)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v record;
begin
  if p_token is null then
    return json_build_object('ok', false, 'motivo', 'link_invalido');
  end if;

  select * into v from public.assinaturas_link where token = p_token;

  if not found then
    return json_build_object('ok', false, 'motivo', 'link_invalido');
  end if;
  if v.status = 'cancelado' then
    return json_build_object('ok', false, 'motivo', 'cancelado', 'numero', v.pedido_numero);
  end if;
  if v.status = 'pendente' and v.expira_em < now() then
    return json_build_object('ok', false, 'motivo', 'expirado',
      'numero', v.pedido_numero, 'expira_em', v.expira_em);
  end if;

  return json_build_object(
    'ok',          true,
    'numero',      v.pedido_numero,
    'cliente',     v.cliente,
    'cliente_doc', v.cliente_doc,
    'total',       v.total,
    'documento',   v.documento,
    'estilo',      v.estilo,
    'status',      v.status,
    'expira_em',   v.expira_em,
    'assinatura',  v.assinatura,
    'assinado_em', v.assinado_em
  );
end;
$fn$;

-- 3.2 assinar (uma vez; depois disso o link so mostra o que foi assinado)
create or replace function public.assinar_venda(
  p_token      uuid,
  p_assinatura text,
  p_nome       text default null,
  p_doc        text default null,
  p_navegador  text default null
)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v record;
  v_quando timestamptz := now();
begin
  if p_token is null then
    return json_build_object('ok', false, 'motivo', 'link_invalido');
  end if;

  select * into v from public.assinaturas_link where token = p_token for update;

  if not found then
    return json_build_object('ok', false, 'motivo', 'link_invalido');
  end if;
  if v.status = 'assinado' then
    return json_build_object('ok', false, 'motivo', 'ja_assinado', 'assinado_em', v.assinado_em);
  end if;
  if v.status = 'cancelado' then
    return json_build_object('ok', false, 'motivo', 'cancelado');
  end if;
  if v.expira_em < now() then
    return json_build_object('ok', false, 'motivo', 'expirado', 'expira_em', v.expira_em);
  end if;
  if p_assinatura is null or p_assinatura !~ '^data:image/(png|jpeg);base64,' then
    return json_build_object('ok', false, 'motivo', 'assinatura_invalida');
  end if;
  if length(p_assinatura) > 2000000 then
    return json_build_object('ok', false, 'motivo', 'assinatura_grande');
  end if;

  update public.assinaturas_link
     set status         = 'assinado',
         assinatura     = p_assinatura,
         assinante_nome = nullif(btrim(coalesce(p_nome,'')),''),
         assinante_doc  = nullif(btrim(coalesce(p_doc,'')),''),
         navegador      = left(coalesce(p_navegador,''), 300),
         assinado_em    = v_quando
   where token = p_token;

  return json_build_object('ok', true, 'assinado_em', v_quando, 'numero', v.pedido_numero);
end;
$fn$;

-- As duas funcoes sao o UNICO caminho de quem nao tem login.
revoke all on function public.venda_para_assinar(uuid) from public;
revoke all on function public.assinar_venda(uuid, text, text, text, text) from public;
grant execute on function public.venda_para_assinar(uuid)                   to anon, authenticated;
grant execute on function public.assinar_venda(uuid, text, text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------
-- 4. Conferencia rapida (opcional)
-- ---------------------------------------------------------------------
-- select token, pedido_numero, cliente, status, criado_em, expira_em, assinado_em
--   from public.assinaturas_link order by criado_em desc limit 20;
