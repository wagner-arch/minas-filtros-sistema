-- ============================================================================
-- CHAVE PRÓPRIA DO APARELHO PARA GRAVAR A LOCALIZAÇÃO (17/11/2026, v573)
--
-- O PROBLEMA: desde a v547 o aplicativo não renova mais a sessão (quem renova é
-- só a página). Com a tela do celular apagada a página dorme, ninguém renova, o
-- acesso vence em ~1 hora e o aplicativo passa o resto do dia recebendo 401 —
-- mais da metade do trajeto não era gravada. E um único ponto ruim dentro de um
-- lote da fila fazia o banco recusar o LOTE INTEIRO (403), que era reenviado e
-- recusado para sempre.
--
-- A SOLUÇÃO: uma chave própria do aparelho, criada pela página quando a pessoa
-- entra, ligada ao usuário E ao aparelho. O aplicativo manda os pontos para a
-- função `rastro_gravar`, que descobre quem é pela chave e grava com o NOME e a
-- EMPRESA tirados do cadastro (perfis) — nunca do que o celular guardou.
--
-- O QUE A CHAVE PODE: só gravar localização. A função não lê, não altera e não
-- apaga mais nada; é o único caminho aberto por ela.
-- A CHAVE PARA DE FUNCIONAR SOZINHA quando: a pessoa sai do sistema, o
-- colaborador é desativado no cadastro, o Administrador revoga, ou o aparelho
-- passa 30 dias sem mandar nenhum ponto.
-- A chave NUNCA é guardada em texto: fica só a impressão digital (sha256).
-- ============================================================================

-- ---------------------------------------------------------------- as chaves
create table if not exists public.rastro_chaves (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  aparelho        text not null,                 -- código do aparelho, gerado no celular
  modelo          text,                          -- o que o celular diz ser (só para a lista)
  chave_hash      text not null unique,          -- sha256 da chave; a chave em si não fica aqui
  criada_em       timestamptz not null default now(),
  criada_por      text,
  ultimo_ponto_em timestamptz,
  pontos_gravados bigint not null default 0,
  janela_em       timestamptz,                   -- teto de envios por minuto
  janela_envios   integer not null default 0,
  revogada_em     timestamptz,
  revogada_por    text,
  motivo          text
);
create index if not exists rastro_chaves_user on public.rastro_chaves(user_id);
-- um aparelho tem UMA chave ativa: entrou outra pessoa no mesmo celular, a de antes é revogada
create unique index if not exists rastro_chaves_aparelho_ativa
  on public.rastro_chaves(aparelho) where revogada_em is null;

-- ------------------------------------------------- os pontos que foram recusados
-- Nada some calado: o que a função recusar fica aqui, com o motivo, para o
-- Administrador ver na tela.
create table if not exists public.rastro_recusados (
  id          bigserial primary key,
  chave_id    uuid,
  user_id     uuid,
  aparelho    text,
  vendedor    text,
  loja        text,
  em          timestamptz,
  lat         double precision,
  lng         double precision,
  motivo      text not null,
  recebido_em timestamptz not null default now()
);
create index if not exists rastro_recusados_em on public.rastro_recusados(recebido_em desc);

alter table public.rastro_chaves    enable row level security;
alter table public.rastro_recusados enable row level security;

-- quem já vê o rastro vê as chaves e as recusas; ninguém grava por fora da função
drop policy if exists rastro_chaves_select on public.rastro_chaves;
create policy rastro_chaves_select on public.rastro_chaves for select to authenticated
  using (user_id = (select auth.uid()) or (select sou_gestao_rastreio()));

drop policy if exists rastro_recusados_select on public.rastro_recusados;
create policy rastro_recusados_select on public.rastro_recusados for select to authenticated
  using (user_id = (select auth.uid()) or (select sou_gestao_rastreio()));

-- ---------------------------------------------------------- criar a chave
-- Chamada pela PÁGINA, com a pessoa logada. Devolve a chave em texto UMA vez:
-- é a única vez que ela existe fora do celular.
create or replace function public.rastro_chave_criar(p_aparelho text, p_modelo text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $$
declare
  v_uid uuid := auth.uid();
  v_nome text;
  v_chave text;
  v_id uuid;
begin
  if v_uid is null then return jsonb_build_object('ok', false, 'erro', 'sem sessão'); end if;
  if coalesce(trim(p_aparelho), '') = '' then return jsonb_build_object('ok', false, 'erro', 'sem aparelho'); end if;

  select p.nome into v_nome from public.perfis p where p.user_id = v_uid and p.ativo limit 1;
  if v_nome is null then return jsonb_build_object('ok', false, 'erro', 'cadastro inativo'); end if;

  /* este aparelho não fica com duas chaves: a anterior (de quem for) é revogada */
  update public.rastro_chaves
     set revogada_em = now(), revogada_por = v_nome,
         motivo = case when user_id = v_uid then 'chave trocada ao entrar' else 'outra pessoa entrou neste aparelho' end
   where aparelho = p_aparelho and revogada_em is null;

  v_chave := encode(gen_random_bytes(32), 'hex');
  insert into public.rastro_chaves (user_id, aparelho, modelo, chave_hash, criada_por)
  values (v_uid, p_aparelho, nullif(trim(coalesce(p_modelo, '')), ''),
          encode(digest(v_chave, 'sha256'), 'hex'), v_nome)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id, 'chave', v_chave);
end;
$$;

-- --------------------------------------------------------- revogar a chave
-- O Administrador revoga qualquer uma (celular perdido ou roubado); a própria
-- pessoa revoga a dela (é o que acontece no "Sair").
create or replace function public.rastro_chave_revogar(p_id uuid default null, p_aparelho text default null,
                                                       p_motivo text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_uid uuid := auth.uid();
  v_nome text;
  v_adm boolean := false;
  v_n integer;
begin
  if v_uid is null then return jsonb_build_object('ok', false, 'erro', 'sem sessão'); end if;
  select p.nome, (p.funcao = 'Administrador') into v_nome, v_adm
    from public.perfis p where p.user_id = v_uid and p.ativo limit 1;
  if v_nome is null then return jsonb_build_object('ok', false, 'erro', 'cadastro inativo'); end if;

  update public.rastro_chaves c
     set revogada_em = now(), revogada_por = v_nome,
         motivo = coalesce(nullif(trim(coalesce(p_motivo, '')), ''), 'revogada')
   where c.revogada_em is null
     and (p_id is null or c.id = p_id)
     and (p_aparelho is null or c.aparelho = p_aparelho)
     and (p_id is not null or p_aparelho is not null)
     and (v_adm or c.user_id = v_uid);
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', true, 'revogadas', v_n);
end;
$$;

-- ------------------------------------------- a lista de aparelhos com chave
create or replace function public.rastro_chaves_ativas()
returns table (id uuid, colaborador text, aparelho text, modelo text, loja text,
               criada_em timestamptz, ultimo_ponto_em timestamptz, pontos_gravados bigint)
language sql
security definer
set search_path to 'public', 'pg_temp'
as $$
  select c.id, p.nome, c.aparelho, c.modelo, p.loja, c.criada_em, c.ultimo_ponto_em, c.pontos_gravados
    from public.rastro_chaves c
    left join public.perfis p on p.user_id = c.user_id
   where c.revogada_em is null
     and (c.user_id = auth.uid() or sou_gestao_rastreio())
   order by p.nome, c.criada_em desc;
$$;

-- ====================================================== GRAVAR A LOCALIZAÇÃO
-- O único caminho que a chave abre. Confere a chave, descobre quem é, lê o NOME
-- e a EMPRESA do cadastro e grava. O que não puder ser gravado é RECUSADO E
-- CONTADO, com o motivo — nunca some calado.
create or replace function public.rastro_gravar(p_chave text, p_pontos jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $$
declare
  TETO_MINUTO constant integer := 30;    -- envios por aparelho por minuto
  TETO_PONTOS constant integer := 300;   -- pontos por envio
  DIAS_PARADO constant integer := 30;    -- aparelho sem mandar nada: a chave morre
  DIAS_ATRAS  constant integer := 7;     -- ponto mais velho que isto não entra
  v_hash text;
  v_c public.rastro_chaves%rowtype;
  v_nome text; v_loja text; v_ativo boolean;
  v_p jsonb;
  v_em timestamptz; v_lat double precision; v_lng double precision;
  v_motivo text;
  v_gravados integer := 0;
  v_recusados integer := 0;
begin
  if coalesce(p_chave, '') = '' then return jsonb_build_object('ok', false, 'erro', 'sem chave'); end if;
  v_hash := encode(digest(p_chave, 'sha256'), 'hex');

  select * into v_c from public.rastro_chaves where chave_hash = v_hash limit 1;
  if v_c.id is null then return jsonb_build_object('ok', false, 'erro', 'chave desconhecida'); end if;
  if v_c.revogada_em is not null then return jsonb_build_object('ok', false, 'erro', 'chave revogada'); end if;

  /* 30 dias sem mandar nada: a chave morre sozinha */
  if coalesce(v_c.ultimo_ponto_em, v_c.criada_em) < now() - (DIAS_PARADO || ' days')::interval then
    update public.rastro_chaves set revogada_em = now(), revogada_por = 'sistema',
           motivo = 'aparelho passou ' || DIAS_PARADO || ' dias sem mandar localização'
     where id = v_c.id;
    return jsonb_build_object('ok', false, 'erro', 'chave vencida');
  end if;

  /* o nome e a empresa vêm do CADASTRO, nunca do celular */
  select p.nome, p.loja, p.ativo into v_nome, v_loja, v_ativo
    from public.perfis p where p.user_id = v_c.user_id limit 1;
  if v_nome is null or v_ativo is not true then
    update public.rastro_chaves set revogada_em = now(), revogada_por = 'sistema',
           motivo = 'colaborador desativado no cadastro'
     where id = v_c.id;
    return jsonb_build_object('ok', false, 'erro', 'cadastro inativo');
  end if;

  /* teto de envios por minuto: um celular com defeito não enche o banco */
  if v_c.janela_em is null or v_c.janela_em < now() - interval '1 minute' then
    update public.rastro_chaves set janela_em = now(), janela_envios = 1 where id = v_c.id;
  elsif v_c.janela_envios >= TETO_MINUTO then
    return jsonb_build_object('ok', false, 'erro', 'muitos envios por minuto');
  else
    update public.rastro_chaves set janela_envios = janela_envios + 1 where id = v_c.id;
  end if;

  if p_pontos is null or jsonb_typeof(p_pontos) <> 'array' then
    return jsonb_build_object('ok', true, 'gravados', 0, 'recusados', 0);
  end if;
  if jsonb_array_length(p_pontos) > TETO_PONTOS then
    return jsonb_build_object('ok', false, 'erro', 'pontos demais num envio só');
  end if;

  for v_p in select * from jsonb_array_elements(p_pontos) loop
    v_motivo := null;
    begin v_em := (v_p->>'em')::timestamptz; exception when others then v_em := null; end;
    begin v_lat := (v_p->>'lat')::double precision; exception when others then v_lat := null; end;
    begin v_lng := (v_p->>'lng')::double precision; exception when others then v_lng := null; end;

    if v_em is null then v_motivo := 'sem a hora do ponto';
    elsif v_lat is null or v_lng is null then v_motivo := 'sem a localização';
    elsif v_em > now() + interval '5 minutes' then v_motivo := 'hora no futuro';
    elsif v_em < now() - (DIAS_ATRAS || ' days')::interval then v_motivo := 'ponto com mais de ' || DIAS_ATRAS || ' dias';
    end if;

    if v_motivo is not null then
      insert into public.rastro_recusados (chave_id, user_id, aparelho, vendedor, loja, em, lat, lng, motivo)
      values (v_c.id, v_c.user_id, v_c.aparelho, v_nome, v_loja, v_em, v_lat, v_lng, v_motivo);
      v_recusados := v_recusados + 1;
    else
      /* reenvio não duplica: o mesmo ponto (pessoa e hora) entra uma vez só */
      insert into public.rastro_pontos (user_id, vendedor, loja, em, lat, lng, precisao, velocidade, bateria, parado)
      select v_c.user_id, v_nome, v_loja, v_em, v_lat, v_lng,
             nullif(v_p->>'precisao','')::real, nullif(v_p->>'velocidade','')::real,
             nullif(v_p->>'bateria','')::smallint, coalesce((v_p->>'parado')::boolean, false)
       where not exists (select 1 from public.rastro_pontos r
                          where r.user_id = v_c.user_id and r.em = v_em);
      if found then v_gravados := v_gravados + 1; end if;
    end if;
  end loop;

  update public.rastro_chaves
     set ultimo_ponto_em = greatest(coalesce(ultimo_ponto_em, now()), now()),
         pontos_gravados = pontos_gravados + v_gravados
   where id = v_c.id;

  return jsonb_build_object('ok', true, 'gravados', v_gravados, 'recusados', v_recusados);
end;
$$;

-- Quem pode chamar o quê. A gravação é chamada pelo APLICATIVO, que não tem
-- sessão de usuário: por isso vale para `anon` — mas sem uma chave boa ela não
-- faz nada, e ela não abre nenhum outro caminho no banco.
revoke all on function public.rastro_gravar(text, jsonb) from public;
grant execute on function public.rastro_gravar(text, jsonb) to anon, authenticated;
revoke all on function public.rastro_chave_criar(text, text) from public;
grant execute on function public.rastro_chave_criar(text, text) to authenticated;
revoke all on function public.rastro_chave_revogar(uuid, text, text) from public;
grant execute on function public.rastro_chave_revogar(uuid, text, text) to authenticated;
revoke all on function public.rastro_chaves_ativas() from public;
grant execute on function public.rastro_chaves_ativas() to authenticated;

-- PARA VOLTAR ATRÁS (se um dia precisar): basta revogar o direito de chamar a
-- função de gravar; o aplicativo volta sozinho ao caminho antigo, com a sessão.
--   revoke execute on function public.rastro_gravar(text, jsonb) from anon, authenticated;
