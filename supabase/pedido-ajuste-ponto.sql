-- PEDIDO DE AJUSTE DO PONTO PELO COLABORADOR (05/11/2026, defeito da v511)
--
-- O DEFEITO: o pedido de ajuste e gravado DENTRO do documento de ponto do dia. A regra
-- docs_update_ponto_proprio so deixa o colaborador ATUALIZAR o proprio ponto do DIA DE HOJE (ela
-- protege as batidas e CONTINUA como esta). Pedir ajuste de um dia anterior que ja tinha batida
-- era recusado ("Sem permissao para gravar pontos/<id>"). O mesmo acontecia, calado, ao marcar
-- como vista a resposta de um pedido de dia anterior (o aviso voltava no sino).
--
-- A CORRECAO: duas funcoes que rodam com permissao propria e fazem SO o que o pedido precisa:
--   pedir_ajuste_ponto            acrescenta solicitacoes no ponto do PROPRIO colaborador (nome do
--                                 perfil do login), da empresa dele, de hoje ou de dia anterior;
--                                 nunca mexe em batida, foto, localizacao, tipo do dia nem ajustes.
--                                 Sem documento no dia, cria um so com o id, o colaborador, a data,
--                                 a empresa e as solicitacoes.
--   marcar_respostas_vistas_ponto troca "visto" para true nas respostas dos pedidos dele. So isso.
--
-- E FECHA UMA BRECHA: a regra docs_insert_ponto_proprio deixava o colaborador CRIAR ponto de
-- qualquer dia, inclusive passado, com batidas dentro. Agora so o de hoje (a batida). Dia anterior
-- nasce so pela funcao do pedido, sem batida. Administrador e Financeiro continuam pela
-- docs_insert_ponto_gestao. A batida nao fica guardada no celular para enviar depois: sem internet
-- ela e recusada na hora e a tela pede para bater de novo — entao nao ha batida "atrasada" a recusar.

create or replace function public.pedir_ajuste_ponto(p_loja text, p_data date, p_id text, p_solicitacoes jsonb)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_nome  text := public.meu_nome();
  v_hoje  date := (now() at time zone 'America/Sao_Paulo')::date;
  v_doc_id text; v_doc jsonb;
  v_marcs text[] := '{}';
  v_novas jsonb := '[]'::jsonb;
  v_res   jsonb;
  s jsonb; v_id text;
  nomes jsonb := '{"checkin":"a entrada","almocoIni":"a saída do almoço","almocoFim":"a volta do almoço","checkout":"a saída"}';
begin
  if v_nome is null then raise exception 'Seu cadastro não foi encontrado. Saia do sistema e entre de novo.'; end if;
  if p_loja is null or not (p_loja = any(public.minhas_lojas()) or public.vejo_todas_lojas()) then
    raise exception 'Esta empresa não é a do seu cadastro.'; end if;
  if p_data is null then raise exception 'Escolha o dia.'; end if;
  if p_data > v_hoje then raise exception 'O dia não pode ser no futuro.'; end if;
  if p_solicitacoes is null or jsonb_typeof(p_solicitacoes) <> 'array'
     or jsonb_array_length(p_solicitacoes) = 0 or jsonb_array_length(p_solicitacoes) > 4 then
    raise exception 'Informe o horário certo de pelo menos uma marcação.'; end if;

  select d.id, d.data into v_doc_id, v_doc
    from docs d
   where d.colecao = 'pontos' and d.loja = p_loja
     and d.data->>'colaborador' = v_nome and d.data->>'data' = p_data::text
   order by d.criado_em nulls last
   limit 1
   for update;

  if v_doc_id is not null then
    select coalesce(array_agg(x->>'marc'), '{}') into v_marcs
      from jsonb_array_elements(coalesce(v_doc->'solicitacoes','[]'::jsonb)) x
     where x->>'status' = 'pendente';
  end if;

  for s in select e from jsonb_array_elements(p_solicitacoes) e loop
    if coalesce(s->>'marc','') not in ('checkin','almocoIni','almocoFim','checkout') then
      raise exception 'Marcação inválida no pedido.'; end if;
    if coalesce(s->>'hora','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
      raise exception 'Horário inválido no pedido.'; end if;
    if length(trim(coalesce(s->>'motivo',''))) = 0 then
      raise exception 'Escreva o motivo do pedido.'; end if;
    if (s->>'marc') = any(v_marcs) then
      raise exception 'Já há um pedido esperando resposta para %.', nomes->>(s->>'marc'); end if;
    v_marcs := v_marcs || (s->>'marc');
    v_novas := v_novas || jsonb_build_array(jsonb_build_object(
      'id',     coalesce(nullif(s->>'id',''), gen_random_uuid()::text),
      'grupo',  coalesce(s->>'grupo',''),
      'marc',   s->>'marc',
      'hora',   s->>'hora',
      'de',     coalesce(v_doc->(s->>'marc')->>'hora',''),     -- o horário de antes vem do banco, não da tela
      'motivo', left(trim(s->>'motivo'), 500),
      'por',    v_nome,
      'em',     to_char(now() at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'quando', to_char(now() at time zone 'America/Sao_Paulo','YYYY-MM-DD HH24:MI'),
      'status', 'pendente'));
  end loop;

  if v_doc_id is not null then
    update docs
       set data = jsonb_set(data, '{solicitacoes}', coalesce(data->'solicitacoes','[]'::jsonb) || v_novas),
           atualizado_em = now()
     where colecao = 'pontos' and id = v_doc_id
     returning data into v_res;
  else
    v_id := coalesce(nullif(p_id,''), gen_random_uuid()::text);
    if exists (select 1 from docs where colecao = 'pontos' and id = v_id) then v_id := gen_random_uuid()::text; end if;
    v_res := jsonb_build_object('id', v_id, 'loja', p_loja, 'colaborador', v_nome, 'data', p_data::text,
                                'solicitacoes', v_novas);
    insert into docs(colecao, id, loja, data) values ('pontos', v_id, p_loja, v_res);
  end if;
  return v_res;
end $$;

create or replace function public.marcar_respostas_vistas_ponto(p_loja text)
returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_nome text := public.meu_nome(); n int;
begin
  if v_nome is null then return 0; end if;
  update docs d
     set data = jsonb_set(d.data, '{solicitacoes}',
           (select jsonb_agg(case when x->>'status' <> 'pendente' and x->>'visto' = 'false'
                                  then x || '{"visto":true}'::jsonb else x end order by o)
              from jsonb_array_elements(d.data->'solicitacoes') with ordinality as t(x, o))),
         atualizado_em = now()
   where d.colecao = 'pontos' and d.loja = p_loja
     and d.data->>'colaborador' = v_nome
     and d.data->'solicitacoes' @> '[{"visto":false}]'::jsonb;
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.pedir_ajuste_ponto(text, date, text, jsonb) from public, anon;
revoke all on function public.marcar_respostas_vistas_ponto(text) from public, anon;
grant execute on function public.pedir_ajuste_ponto(text, date, text, jsonb) to authenticated;
grant execute on function public.marcar_respostas_vistas_ponto(text) to authenticated;

-- a brecha: o colaborador so CRIA o ponto de hoje (a batida). Dia anterior, so pela funcao acima.
drop policy if exists docs_insert_ponto_proprio on public.docs;
create policy docs_insert_ponto_proprio on public.docs for insert to authenticated
  with check (colecao = 'pontos' and public.eh_meu_documento(data)
              and (data->>'data') = to_char((now() at time zone 'America/Sao_Paulo'), 'YYYY-MM-DD'));

-- VOLTAR ATRAS da brecha (volta a regra antiga, sem a data):
--   drop policy docs_insert_ponto_proprio on public.docs;
--   create policy docs_insert_ponto_proprio on public.docs for insert to authenticated
--     with check (colecao = 'pontos' and public.eh_meu_documento(data));
