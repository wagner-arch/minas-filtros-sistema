-- =====================================================================
-- TROCAR UM PRODUTO POR OUTRO E APAGAR O ANTIGO (regra dele, 03/11/2026)
--
-- "Excluir produto: se ele tiver em algum lançamento de venda, pedir para
-- informar qual produto entrará no lugar daquele que está sendo excluído."
-- E, perguntado se o antigo ficava desativado: "apagar em vez de desativar".
--
-- Feita no banco, e não no navegador, por três motivos:
--   1. alcança as DUAS empresas (o catálogo é um só, as vendas não);
--   2. alcança os registros antigos que o celular não carregou (limites);
--   3. ou troca tudo, ou não troca nada (uma transação só).
--
-- Só a FUNÇÃO Administrador (public.minha_funcao()). Produto de sistema
-- (troca, OS, serviços, planos) nunca. Inventário em andamento com o
-- produto trava a troca: a contagem cega mudaria no meio.
--
-- O que muda, em todo documento que cita o produto antigo:
--   * item de pedido, orçamento, rascunho, requisição e OS (itens, itensOS,
--     pecas): pid, nome e código passam a ser os do novo; o antigo fica em
--     "trocadoDe" dentro do item. VALOR, desconto e quantidade não mudam.
--   * documento com produtoId (aparelho, movimento de estoque, série, OS):
--     produtoId e o nome (produto / equipamento) passam a ser os do novo.
--     Os movimentos trocados levam o saldo do antigo para o novo.
--   * qualquer outra citação (kit de outro produto, histórico de peças do
--     aparelho, inventário encerrado): o código interno passa a ser o novo.
--   * cada documento tocado ganha uma linha em "trocasProduto".
-- Antes de tudo, a cópia de cada documento vai para backup.troca_produto.
-- Com p_so_contar = true, só conta (é o que a janela mostra antes).
-- =====================================================================

create table if not exists backup.troca_produto (
  quando   timestamptz not null default now(),
  por      text,
  antigo   text not null,
  novo     text not null,
  colecao  text not null,
  id       text not null,
  loja     text,
  data     jsonb
);
revoke all on backup.troca_produto from public, anon, authenticated;

create or replace function public.trocar_produto(p_antigo text, p_novo text, p_so_contar boolean default false)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_quem   text := public.meu_nome();
  v_ant    jsonb;
  v_nov    jsonb;
  v_q_ant  text := '"' || p_antigo || '"';
  v_q_nov  text := '"' || p_novo || '"';
  v_agora  text := to_char(now() at time zone 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI');
  v_marca  jsonb;
  v_contas jsonb;
  v_inv    text;
  v_presos int := 0;
  r        record;
  v_dado   jsonb;
  v_campo  text;
begin
  if coalesce(public.minha_funcao(), '') <> 'Administrador' then
    raise exception 'Só o Administrador troca e exclui produto.';
  end if;
  if p_antigo is null or p_novo is null or btrim(p_antigo) = '' or btrim(p_novo) = '' or p_antigo = p_novo then
    raise exception 'Escolha um produto diferente para entrar no lugar.';
  end if;
  if p_antigo !~ '^[A-Za-z0-9_-]+$' or p_novo !~ '^[A-Za-z0-9_-]+$' then
    raise exception 'Código de produto inválido.';
  end if;

  select data into v_ant from docs where colecao = 'produtos' and id = p_antigo for update;
  select data into v_nov from docs where colecao = 'produtos' and id = p_novo for update;
  if v_ant is null then raise exception 'O produto a excluir não existe mais.'; end if;
  if v_nov is null then raise exception 'O produto escolhido para entrar no lugar não existe.'; end if;
  if coalesce(v_nov->>'status', 'ativo') <> 'ativo' then
    raise exception 'O produto que entra no lugar está desativado. Ative-o antes.';
  end if;
  if upper(coalesce(v_ant->>'cod', '')) in ('SUCATA','USADO-TROCA','OS-CLIENTE','SRV-ATEND','SRV-ORC','PLANO-PI','PLANO-PII')
     or v_ant->>'grupo' = 'Planos' then
    raise exception 'Este produto é usado pelo próprio sistema e não pode ser excluído.';
  end if;

  select string_agg('nº ' || coalesce(data->>'numero', '?'), ', ') into v_inv
    from docs
   where colecao = 'inventarios'
     and data->>'status' in ('contagem', 'recontagem', 'aprovacao')
     and (data::text like '%' || v_q_ant || '%' or data::text like '%' || v_q_nov || '%');
  if v_inv is not null then
    raise exception 'Há inventário em andamento com um destes produtos (%). Termine o inventário antes de trocar.', v_inv;
  end if;

  -- quantos documentos citam o antigo, por coleção (a janela mostra isto antes)
  select coalesce(jsonb_object_agg(colecao, n), '{}'::jsonb) into v_contas
    from (select colecao, count(*) n from docs
           where colecao <> 'produtos' and data::text like '%' || v_q_ant || '%'
           group by colecao) x;
  select v_contas || jsonb_build_object('produtos', count(*)) into v_contas
    from docs where colecao = 'produtos' and id <> p_antigo and data::text like '%' || v_q_ant || '%';
  if p_so_contar then
    return jsonb_build_object('contas', v_contas, 'apagado', false);
  end if;

  v_marca := jsonb_build_object(
    'quando', v_agora, 'por', v_quem,
    'de',   jsonb_build_object('id', p_antigo, 'cod', coalesce(v_ant->>'cod',''), 'nome', coalesce(v_ant->>'nome','')),
    'para', jsonb_build_object('id', p_novo,   'cod', coalesce(v_nov->>'cod',''), 'nome', coalesce(v_nov->>'nome','')));

  -- 1. cópia de segurança de tudo o que vai mudar, e do próprio produto
  insert into backup.troca_produto (por, antigo, novo, colecao, id, loja, data)
  select v_quem, p_antigo, p_novo, colecao, id, loja, data from docs
   where (colecao = 'produtos' and id = p_antigo)
      or (not (colecao = 'produtos' and id = p_antigo) and data::text like '%' || v_q_ant || '%');

  -- 2. documento a documento
  for r in select colecao, id, data from docs
            where not (colecao = 'produtos' and id = p_antigo)
              and data::text like '%' || v_q_ant || '%'
            for update
  loop
    v_dado := r.data;

    -- inventário encerrado que já tem os dois produtos: a chave repetida apagaria
    -- uma das contagens. Fica como está (é só histórico) e entra na conta.
    if r.colecao = 'inventarios' and jsonb_typeof(v_dado->'itens') = 'object'
       and (v_dado->'itens') ? p_antigo and (v_dado->'itens') ? p_novo then
      v_presos := v_presos + 1;
      continue;
    end if;

    -- itens de venda: pid, nome e código do novo; o antigo guardado no item
    foreach v_campo in array array['itens', 'itensOS', 'pecas'] loop
      if jsonb_typeof(v_dado->v_campo) = 'array' then
        v_dado := jsonb_set(v_dado, array[v_campo], (
          select coalesce(jsonb_agg(
                   case when jsonb_typeof(e) = 'object' and e->>'pid' = p_antigo then
                     e || jsonb_build_object('pid', p_novo)
                       || case when e ? 'nome' then jsonb_build_object('nome', coalesce(v_nov->>'nome', e->>'nome')) else '{}'::jsonb end
                       || case when e ? 'cod'  then jsonb_build_object('cod',  coalesce(v_nov->>'cod',  e->>'cod'))  else '{}'::jsonb end
                       || jsonb_build_object('trocadoDe', jsonb_build_object('pid', '@@TROCA_ANTIGO@@', 'nome', e->>'nome', 'cod', e->>'cod'))
                   else e end order by o), '[]'::jsonb)
            from jsonb_array_elements(v_dado->v_campo) with ordinality t(e, o)));
      end if;
    end loop;

    -- documento do produto (aparelho, movimento, série, OS): o nome acompanha
    if v_dado->>'produtoId' = p_antigo then
      v_dado := v_dado || jsonb_build_object('produtoId', p_novo);
      if jsonb_typeof(v_dado->'produto') = 'string' then
        v_dado := v_dado || jsonb_build_object('produto', coalesce(v_nov->>'nome', v_dado->>'produto'));
      end if;
      if jsonb_typeof(v_dado->'equipamento') = 'string' and v_dado->>'equipamento' = coalesce(v_ant->>'nome', '') then
        v_dado := v_dado || jsonb_build_object('equipamento', coalesce(v_nov->>'nome', v_dado->>'equipamento'));
      end if;
    end if;

    -- o que sobrou (kit, peças do histórico, inventário encerrado, plano do aparelho)
    -- (o antigo guardado no item passa por fora: senão seria trocado também)
    v_dado := replace(replace(v_dado::text, v_q_ant, v_q_nov), '"@@TROCA_ANTIGO@@"', v_q_ant)::jsonb;

    -- a marca da troca, sem tocar no histórico de cada tela
    v_dado := jsonb_set(v_dado, '{trocasProduto}',
                coalesce(case when jsonb_typeof(v_dado->'trocasProduto') = 'array' then v_dado->'trocasProduto' end, '[]'::jsonb)
                || jsonb_build_array(v_marca));

    update docs set data = v_dado where colecao = r.colecao and id = r.id;
  end loop;

  -- 3. o antigo sai do catálogo (a cópia ficou no backup)
  delete from docs where colecao = 'produtos' and id = p_antigo;

  return jsonb_build_object('contas', v_contas, 'apagado', true, 'mantidos', v_presos, 'marca', v_marca);
end;
$function$;

revoke all on function public.trocar_produto(text, text, boolean) from public, anon;
grant execute on function public.trocar_produto(text, text, boolean) to authenticated;
