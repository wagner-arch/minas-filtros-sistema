-- LIMPEZA DEFINITIVA DOS PRODUTOS (06/11/2026, planilha "Plano-final-produtos-v2" aprovada pelo Wagner)
-- A planilha fica fora do repositório (interno/produtos); aqui só a rotina. O plano é carregado na
-- tabela de trabalho public.limpeza_produtos_plano (aba F fica, J junta, I inativa, S sistema), já
-- ligada a cada cadastro em produto_id.
--
-- public.limpeza_produtos_executar(p_simular):
--   p_simular = true  → faz tudo, confere tudo e DESFAZ no fim (ensaio). A resposta vem no erro "ENSAIO OK".
--   p_simular = false → faz de verdade; se qualquer conferência falhar, desfaz tudo sozinha.
-- Regras (respostas dele de 06/11):
--   F: grava o código final (maiúsculo) e o nome final; o código e o nome antigos ficam em
--      "limpezaProdutos" e todos os códigos antigos (o dele e o dos juntados) em "codigosAntigos".
--   J: o que fica herda só o que falta (preço, custo, mínimo, frete, marca, barras, unidade, grupo,
--      composição...), igual à junção do sistema (fundirRepetido); o saldo de cada lugar passa por
--      movimento (sai de um, entra no outro, por empresa, sem misturar); aparelhos de clientes e séries
--      passam para o que fica (o antigo em trocasProduto); composições de outros produtos idem;
--      pedidos não aprovados, orçamentos abertos, rascunhos e requisições pendentes trocam o item
--      (o antigo guardado no próprio item). Pedido aprovado e PDF não mudam. O que sai fica inativo,
--      "juntado em <código>".
--   I: inativo com o motivo; o saldo fica onde está.
--   S: não mexe.

create or replace function public._lp_num(x jsonb) returns numeric language sql immutable as $$
  select case when jsonb_typeof(x) = 'number' then (x #>> '{}')::numeric
              when jsonb_typeof(x) = 'string' and btrim(x #>> '{}') ~ '^-?[0-9]+([.,][0-9]+)?$'
                then replace(btrim(x #>> '{}'), ',', '.')::numeric
              else null end $$;

create or replace function public.limpeza_produtos_executar(p_simular boolean default true)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_dia  text := to_char(now() at time zone 'America/Sao_Paulo', 'YYYY-MM-DD');
  v_hora text := to_char(now() at time zone 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI');
  v_em   text := to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
  v_por  text := 'Limpeza de produtos';
  r record; m record; sr record;
  v jsonb; vs jsonb; vf jsonb; hist jsonb; codigos jsonb;
  v_mudou boolean; v_n int; v_k text; v_a numeric; v_b numeric;
  n_f_cod int := 0; n_f_nome int := 0; n_j int := 0; n_i int := 0; n_mov int := 0; n_un numeric := 0;
  n_eq int := 0; n_ser int := 0; n_comp int := 0; n_herda int := 0;
  n_ped int := 0; n_orc int := 0; n_ras int := 0; n_req int := 0;
  eq_esperado int; prod_antes int; falhas text := '';
  motivos text[] := array['não existe no sistema antigo / decisão Wagner', 'decisão Wagner', 'não existe no sistema antigo'];
  rel text;
begin
  ---------------------------------------------------------------- pré-condições
  if exists (select 1 from docs where colecao = 'inventarios'
             and coalesce(data->>'status', '') not in ('fechado', 'cancelado', 'aprovado', 'desfeito')) then
    raise exception 'PARADO: há inventário aberto (feche ou cancele antes).';
  end if;
  if exists (select 1 from limpeza_produtos_plano where produto_id is null)
     or (select count(*) from limpeza_produtos_plano) <> (select count(distinct produto_id) from limpeza_produtos_plano) then
    raise exception 'PARADO: há linha da planilha sem cadastro ligado (ou ligada duas vezes).';
  end if;
  if exists (select 1 from limpeza_produtos_plano t left join docs d on d.colecao = 'produtos' and d.id = t.produto_id
             where d.id is null
                or (upper(btrim(coalesce(d.data->>'cod', ''))) <> case when upper(t.cod_hoje) like '(SEM C%' then '' else upper(btrim(t.cod_hoje)) end
                    and not (t.aba = 'F' and upper(btrim(coalesce(d.data->>'cod', ''))) = upper(t.cod_final)))) then
    raise exception 'PARADO: algum cadastro mudou de código depois da simulação. Refazer a simulação.';
  end if;

  drop table if exists lp_map, lp_saldo_antes, lp_tot_antes, lp_sis_antes, lp_saldo_depois;
  create temp table lp_map on commit drop as
    select j.produto_id sai, f.produto_id fica, f.cod_final, j.linha,
           coalesce(ds.data->>'cod', '') cod_sai, coalesce(ds.data->>'nome', '') nome_sai
      from limpeza_produtos_plano j
      join limpeza_produtos_plano f on f.aba = 'F' and upper(f.cod_final) = upper(j.cod_final)
      join docs ds on ds.colecao = 'produtos' and ds.id = j.produto_id
     where j.aba = 'J';
  if (select count(*) from lp_map) <> (select count(*) from limpeza_produtos_plano where aba = 'J') then
    raise exception 'PARADO: junção sem cadastro de destino.';
  end if;

  create temp table lp_saldo_antes on commit drop as
    select loja, pid, local, sum(q) s from (
      select loja, data->>'produtoId' pid, data->>'destino' local, _lp_num(data->'qtd') q from docs where colecao = 'movest'
      union all
      select loja, data->>'produtoId', data->>'origem', -_lp_num(data->'qtd') from docs where colecao = 'movest') x
     where split_part(local, ':', 1) in ('empresa', 'colab', 'eloja', 'recuperacao', 'desmanche', 'consumo')
     group by 1, 2, 3 having sum(q) <> 0;
  create temp table lp_tot_antes on commit drop as select loja, local, sum(s) s from lp_saldo_antes group by 1, 2;
  create temp table lp_sis_antes on commit drop as
    select d.id, d.data from docs d join limpeza_produtos_plano t on t.produto_id = d.id and t.aba = 'S' where d.colecao = 'produtos';
  select count(*) into eq_esperado from docs where colecao = 'equipamentos' and data->>'produtoId' in (select sai from lp_map);
  select count(*) into prod_antes from docs where colecao = 'produtos';

  ---------------------------------------------------------------- 1) os que ficam: código e nome
  for r in select t.*, d.data from limpeza_produtos_plano t join docs d on d.colecao = 'produtos' and d.id = t.produto_id
            where t.aba = 'F' order by t.linha loop
    v := r.data; v_mudou := false;
    if coalesce(v->>'cod', '') <> r.cod_final then v := jsonb_set(v, '{cod}', to_jsonb(r.cod_final)); n_f_cod := n_f_cod + 1; v_mudou := true; end if;
    if r.nome_final <> '' and coalesce(v->>'nome', '') <> r.nome_final then v := jsonb_set(v, '{nome}', to_jsonb(r.nome_final)); n_f_nome := n_f_nome + 1; v_mudou := true; end if;
    -- códigos antigos: o dele e o de cada cadastro que junta nele (a busca acha por qualquer um)
    select coalesce(jsonb_agg(c order by c), '[]'::jsonb) into codigos from (
      select distinct c from (
        select jsonb_array_elements_text(case when jsonb_typeof(r.data->'codigosAntigos') = 'array' then r.data->'codigosAntigos' else '[]' end) c
        union all select coalesce(r.data->>'cod', '')
        union all select cod_sai from lp_map where fica = r.produto_id) z
      where btrim(c) <> '' and upper(btrim(c)) <> upper(r.cod_final)) w;
    if jsonb_array_length(codigos) > 0 then v := v || jsonb_build_object('codigosAntigos', codigos); v_mudou := true; end if;
    if v_mudou then
      v := v || jsonb_build_object('limpezaProdutos', jsonb_build_object('quando', v_hora, 'por', v_por,
             'codAntes', coalesce(r.data->>'cod', ''), 'nomeAntes', coalesce(r.data->>'nome', ''), 'planilha', 'v2 linha ' || r.linha));
      update docs set data = v where colecao = 'produtos' and id = r.produto_id;
    end if;
  end loop;

  ---------------------------------------------------------------- 2) junções
  for m in select lp_map.*, df.data->>'nome' nome_fica from lp_map join docs df on df.colecao = 'produtos' and df.id = lp_map.fica
            order by fica, linha loop
    select data into vs from docs where colecao = 'produtos' and id = m.sai;
    select data into vf from docs where colecao = 'produtos' and id = m.fica;
    hist := case when jsonb_typeof(vf->'histPreco') = 'array' then vf->'histPreco' else '[]'::jsonb end;
    v_mudou := false;
    -- o que fica herda só o que FALTA nele (fundirRepetido)
    foreach v_k in array array['cheia', 'campanha', 'minimo', 'custo', 'frete', 'pontos', 'manut', 'gar'] loop
      v_a := _lp_num(vf->v_k); v_b := _lp_num(vs->v_k);
      if not coalesce(v_a > 0, false) and coalesce(v_b > 0, false) then
        vf := jsonb_set(vf, array[v_k], vs->v_k); v_mudou := true;
        if v_k in ('cheia', 'campanha', 'minimo', 'custo', 'frete') then
          hist := hist || jsonb_build_array(jsonb_build_object('campo', v_k, 'de', coalesce(v_a, 0), 'para', v_b,
                    'origem', 'Junção de produtos repetidos (limpeza, ' || m.cod_sai || ')', 'por', v_por, 'quando', v_hora));
        end if;
      end if;
    end loop;
    foreach v_k in array array['marca', 'barras', 'un', 'pop'] loop
      if btrim(coalesce(vf->>v_k, '')) = '' and btrim(coalesce(vs->>v_k, '')) <> '' then vf := jsonb_set(vf, array[v_k], vs->v_k); v_mudou := true; end if;
    end loop;
    if coalesce(vf->>'grupo', '') in ('', 'A classificar') and coalesce(vs->>'grupo', '') not in ('', 'A classificar') then
      vf := jsonb_set(vf, '{grupo}', vs->'grupo');
      if coalesce(vs->>'subgrupo', '') not in ('', 'A classificar') then vf := jsonb_set(vf, '{subgrupo}', vs->'subgrupo'); end if;
      v_mudou := true;
    end if;
    if (vf->'composto' is null or jsonb_typeof(vf->'composto') <> 'array' or jsonb_array_length(vf->'composto') = 0)
       and jsonb_typeof(vs->'composto') = 'array' and jsonb_array_length(vs->'composto') > 0 then
      vf := jsonb_set(vf, '{composto}', vs->'composto'); v_mudou := true;
    end if;
    if v_mudou then
      n_herda := n_herda + 1;
      vf := jsonb_set(vf, '{histPreco}', hist);
      vf := jsonb_set(vf, '{completar}', to_jsonb(coalesce(vf->>'grupo', '') in ('', 'A classificar') or not coalesce(_lp_num(vf->'cheia') > 0, false)));
    end if;
    vf := jsonb_set(vf, '{juntadoDe}', (case when jsonb_typeof(vf->'juntadoDe') = 'array' then vf->'juntadoDe' else '[]'::jsonb end)
            || jsonb_build_array(jsonb_build_object('id', m.sai, 'cod', m.cod_sai, 'nome', m.nome_sai, 'quando', v_dia, 'por', v_por)));
    update docs set data = vf where colecao = 'produtos' and id = m.fica;

    -- saldo: sai de um, entra no outro, em cada lugar e empresa (o negativo vai junto)
    for sr in select * from lp_saldo_antes where pid = m.sai loop
      insert into docs (colecao, id, loja, data) values ('movest', 'lp' || substr(md5(random()::text || clock_timestamp()::text), 1, 11), sr.loja,
        jsonb_build_object('loja', sr.loja, 'produtoId', m.sai, 'qtd', abs(sr.s),
          'origem', case when sr.s > 0 then sr.local else 'ajuste' end, 'destino', case when sr.s > 0 then 'ajuste' else sr.local end,
          'data', v_dia, 'em', v_em, 'por', v_por, 'doc', 'Junção de produtos · ' || m.cod_sai || ' → ' || m.cod_final,
          'obs', 'Limpeza de produtos: saldo passado para o cadastro que fica', 'juncaoProduto', jsonb_build_object('de', m.sai, 'para', m.fica)));
      insert into docs (colecao, id, loja, data) values ('movest', 'lp' || substr(md5(random()::text || clock_timestamp()::text), 1, 11), sr.loja,
        jsonb_build_object('loja', sr.loja, 'produtoId', m.fica, 'qtd', abs(sr.s),
          'origem', case when sr.s > 0 then 'ajuste' else sr.local end, 'destino', case when sr.s > 0 then sr.local else 'ajuste' end,
          'data', v_dia, 'em', v_em, 'por', v_por, 'doc', 'Junção de produtos · ' || m.cod_sai || ' → ' || m.cod_final,
          'obs', 'Limpeza de produtos: saldo vindo do cadastro juntado', 'juncaoProduto', jsonb_build_object('de', m.sai, 'para', m.fica)));
      n_mov := n_mov + 2; n_un := n_un + abs(sr.s);
    end loop;

    -- aparelhos de clientes e séries
    update docs set data = data || jsonb_build_object('produtoId', m.fica, 'produto', m.nome_fica,
             'trocasProduto', (case when jsonb_typeof(data->'trocasProduto') = 'array' then data->'trocasProduto' else '[]'::jsonb end)
               || jsonb_build_array(jsonb_build_object('de', m.sai, 'deCod', m.cod_sai, 'deNome', coalesce(data->>'produto', m.nome_sai),
                    'para', m.fica, 'paraCod', m.cod_final, 'em', v_hora, 'por', v_por, 'motivo', 'Junção de produtos repetidos (limpeza)')))
           || case when data ? 'produtoAnteriorId' then '{}'::jsonb else jsonb_build_object('produtoAnteriorId', m.sai,
                'produtoAnteriorNome', coalesce(data->>'produto', m.nome_sai), 'produtoTrocadoEm', v_dia, 'produtoTrocadoPor', v_por) end
     where colecao = 'equipamentos' and data->>'produtoId' = m.sai;
    get diagnostics v_n = row_count; n_eq := n_eq + v_n;
    update docs set data = data || jsonb_build_object('produtoId', m.fica, 'produto', m.nome_fica,
             'trocasProduto', (case when jsonb_typeof(data->'trocasProduto') = 'array' then data->'trocasProduto' else '[]'::jsonb end)
               || jsonb_build_array(jsonb_build_object('de', m.sai, 'deCod', m.cod_sai, 'para', m.fica, 'paraCod', m.cod_final, 'em', v_hora, 'por', v_por)))
     where colecao = 'series' and data->>'produtoId' = m.sai;
    get diagnostics v_n = row_count; n_ser := n_ser + v_n;

    -- o que sai: inativo, juntado em <código>
    update docs set data = data || jsonb_build_object('status', 'inativo', 'inativadoEm', v_dia, 'inativadoPor', v_por,
             'inativadoMotivo', 'juntado em ' || m.cod_final, 'juntadoEm', jsonb_build_object('id', m.fica, 'cod', m.cod_final, 'quando', v_dia))
     where colecao = 'produtos' and id = m.sai;
    n_j := n_j + 1;
  end loop;

  -- composições de outros produtos (o que sai vira o que fica; se o que fica já estava, soma)
  for r in select d.id, d.data from docs d where d.colecao = 'produtos' and jsonb_typeof(d.data->'composto') = 'array'
            and exists (select 1 from jsonb_array_elements(d.data->'composto') c where c->>'pid' in (select sai from lp_map)) loop
    select jsonb_agg(el order by o) into v from (
      select min(o) o, (array_agg(e order by o))[1] || jsonb_build_object('pid', p, 'qtd', sum(coalesce(_lp_num(e->'qtd'), 1))) el
        from (select ord o, e, coalesce((select fica from lp_map where sai = e->>'pid'), e->>'pid') p
                from jsonb_array_elements(r.data->'composto') with ordinality x(e, ord)) y group by p) z;
    update docs set data = jsonb_set(data, '{composto}', v) where colecao = 'produtos' and id = r.id;
    n_comp := n_comp + 1;
  end loop;

  -- pedidos não aprovados, orçamentos abertos, rascunhos e requisições pendentes: troca o item
  for r in select d.colecao, d.id, d.data from docs d
            where ((d.colecao = 'pedidos' and coalesce(d.data->>'status', '') not in ('Aprovada', 'Cancelada', 'Teste — não contabilizada')
                      and coalesce(d.data->'aprovado', 'null'::jsonb) in ('null'::jsonb, 'false'::jsonb) and not d.data ? 'aprovadoEm')
                or (d.colecao = 'orcamentos' and coalesce(d.data->>'situacao', 'aberto') = 'aberto')
                or (d.colecao = 'rascunhos' and coalesce(d.data->'virouPedido', 'null'::jsonb) in ('null'::jsonb, 'false'::jsonb) and not d.data ? 'descartadoEm')
                or (d.colecao = 'requisicoes' and d.data->>'status' in ('pendente', 'separada')))
              and jsonb_typeof(d.data->'itens') = 'array'
              and exists (select 1 from jsonb_array_elements(d.data->'itens') i where i->>'pid' in (select sai from lp_map)) loop
    select jsonb_agg(case when mp.sai is null then e else e || jsonb_build_object('pid', mp.fica, 'cod', mp.cod_final, 'nome', df.data->>'nome',
              'pidAntes', mp.sai, 'codAntes', coalesce(e->>'cod', mp.cod_sai), 'nomeAntes', coalesce(e->>'nome', mp.nome_sai), 'trocadoNaLimpeza', v_hora) end order by o)
      into v
      from jsonb_array_elements(r.data->'itens') with ordinality x(e, o)
      left join lp_map mp on mp.sai = e->>'pid'
      left join docs df on df.colecao = 'produtos' and df.id = mp.fica;
    update docs set data = jsonb_set(data, '{itens}', v) where colecao = r.colecao and id = r.id;
    if r.colecao = 'pedidos' then n_ped := n_ped + 1; elsif r.colecao = 'orcamentos' then n_orc := n_orc + 1;
    elsif r.colecao = 'rascunhos' then n_ras := n_ras + 1; else n_req := n_req + 1; end if;
  end loop;

  ---------------------------------------------------------------- 3) inativar (o saldo fica onde está)
  for r in select t.*, d.data from limpeza_produtos_plano t join docs d on d.colecao = 'produtos' and d.id = t.produto_id where t.aba = 'I' loop
    if coalesce(r.data->>'status', 'ativo') <> 'inativo' then
      update docs set data = data || jsonb_build_object('status', 'inativo', 'inativadoEm', v_dia, 'inativadoPor', v_por,
               'inativadoMotivo', 'Limpeza de produtos: ' || coalesce(motivos[r.motivo + 1], 'decisão Wagner'))
       where colecao = 'produtos' and id = r.produto_id;
      n_i := n_i + 1;
    end if;
  end loop;

  ---------------------------------------------------------------- 4) conferência
  if exists (select 1 from limpeza_produtos_plano t join docs d on d.colecao = 'produtos' and d.id = t.produto_id where t.aba = 'F'
             and (d.data->>'cod' <> t.cod_final or (t.nome_final <> '' and d.data->>'nome' <> t.nome_final))) then
    falhas := falhas || 'código/nome final; '; end if;
  if exists (select 1 from docs where colecao = 'produtos' and coalesce(data->>'status', 'ativo') <> 'inativo' and btrim(coalesce(data->>'cod', '')) <> ''
             group by upper(btrim(data->>'cod')) having count(*) > 1) then falhas := falhas || 'código repetido entre ativos; '; end if;
  if exists (select 1 from docs d where colecao = 'produtos' and coalesce(data->>'status', 'ativo') <> 'inativo'
             and coalesce(data->>'cod', '') !~ '^[ABCFGIPRST]MF[0-9]{3}$'
             and d.id not in (select produto_id from limpeza_produtos_plano where aba = 'S')) then falhas := falhas || 'ativo fora do formato; '; end if;
  if exists (select 1 from limpeza_produtos_plano t join docs d on d.colecao = 'produtos' and d.id = t.produto_id
             where t.aba in ('J', 'I') and coalesce(d.data->>'status', '') <> 'inativo') then falhas := falhas || 'juntado/inativado ainda ativo; '; end if;
  if exists (select 1 from docs where colecao in ('equipamentos', 'series') and data->>'produtoId' in (select sai from lp_map)) then
    falhas := falhas || 'aparelho ou série no cadastro juntado; '; end if;
  if n_eq <> eq_esperado then falhas := falhas || 'aparelhos movidos ' || n_eq || ' de ' || eq_esperado || '; '; end if;
  -- estoque: o juntado zera em todo lugar; o que fica = o dele + o dos juntados; o total de cada lugar não muda
  create temp table lp_saldo_depois on commit drop as
    select loja, pid, local, sum(q) s from (
      select loja, data->>'produtoId' pid, data->>'destino' local, _lp_num(data->'qtd') q from docs where colecao = 'movest'
      union all
      select loja, data->>'produtoId', data->>'origem', -_lp_num(data->'qtd') from docs where colecao = 'movest') x
     where split_part(local, ':', 1) in ('empresa', 'colab', 'eloja', 'recuperacao', 'desmanche', 'consumo')
     group by 1, 2, 3 having sum(q) <> 0;
  if exists (select 1 from lp_saldo_depois where pid in (select sai from lp_map)) then falhas := falhas || 'saldo sobrou no juntado; '; end if;
  if exists (
      with esperado as (
        select a.loja, coalesce(mp.fica, a.pid) pid, a.local, sum(a.s) s from lp_saldo_antes a left join lp_map mp on mp.sai = a.pid group by 1, 2, 3)
      select 1 from esperado e full join lp_saldo_depois d on d.loja = e.loja and d.pid = e.pid and d.local = e.local
       where coalesce(e.s, 0) <> coalesce(d.s, 0)) then falhas := falhas || 'saldo do que fica não confere; '; end if;
  if exists (select 1 from (select loja, local, sum(s) s from lp_saldo_depois group by 1, 2) d full join lp_tot_antes a using (loja, local)
             where coalesce(a.s, 0) <> coalesce(d.s, 0)) then falhas := falhas || 'total de algum lugar mudou; '; end if;
  if exists (select 1 from docs d, jsonb_array_elements(d.data->'composto') c where d.colecao = 'produtos' and jsonb_typeof(d.data->'composto') = 'array'
             and c->>'pid' in (select sai from lp_map)) then falhas := falhas || 'composição com juntado; '; end if;
  if exists (select 1 from docs d, jsonb_array_elements(d.data->'itens') i
             where ((d.colecao = 'pedidos' and coalesce(d.data->>'status', '') not in ('Aprovada', 'Cancelada', 'Teste — não contabilizada')
                      and coalesce(d.data->'aprovado', 'null'::jsonb) in ('null'::jsonb, 'false'::jsonb) and not d.data ? 'aprovadoEm')
                 or (d.colecao = 'orcamentos' and coalesce(d.data->>'situacao', 'aberto') = 'aberto')
                 or (d.colecao = 'rascunhos' and coalesce(d.data->'virouPedido', 'null'::jsonb) in ('null'::jsonb, 'false'::jsonb) and not d.data ? 'descartadoEm')
                 or (d.colecao = 'requisicoes' and d.data->>'status' in ('pendente', 'separada')))
               and jsonb_typeof(d.data->'itens') = 'array' and i->>'pid' in (select sai from lp_map)) then
    falhas := falhas || 'item em aberto no juntado; '; end if;
  if (select count(*) from docs where colecao = 'produtos') <> prod_antes then falhas := falhas || 'número de produtos mudou; '; end if;
  if exists (select 1 from lp_sis_antes a join docs d on d.colecao = 'produtos' and d.id = a.id where d.data <> a.data) then
    falhas := falhas || 'produto do sistema mudou; '; end if;

  rel := 'Ficam: ' || n_f_cod || ' códigos e ' || n_f_nome || ' nomes trocados. Junções: ' || n_j || ' (' || n_herda || ' herdaram o que faltava). '
      || 'Estoque: ' || n_mov || ' movimentos, ' || n_un || ' unidades. Aparelhos: ' || n_eq || '. Séries: ' || n_ser || '. Composições: ' || n_comp || '. '
      || 'Em aberto trocados: ' || n_ped || ' pedidos, ' || n_orc || ' orçamentos, ' || n_ras || ' rascunhos, ' || n_req || ' requisições. '
      || 'Inativados agora: ' || n_i || '.';
  if falhas <> '' then raise exception 'CONFERÊNCIA FALHOU (nada foi gravado): % | %', falhas, rel; end if;
  if p_simular then raise exception 'ENSAIO OK (nada foi gravado): %', rel; end if;
  return 'FEITO: ' || rel;
end $$;

revoke all on function public.limpeza_produtos_executar(boolean) from public, anon, authenticated;
revoke all on function public._lp_num(jsonb) from public, anon, authenticated;
