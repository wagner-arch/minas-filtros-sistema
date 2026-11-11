-- =====================================================================
-- AVISO ÚNICO POR LOTE (v542, 11/11/2026) — substitui o gatilho por registro da v541
--
-- Antes (v541): um aviso por registro. Um lote de 2.000 registros = 2.000 avisos,
-- cada um contado 1 + 1 por aparelho conectado, e acima de 500 mensagens/s o
-- Realtime corta.
-- Agora: o gatilho roda UMA VEZ POR GRAVAÇÃO (comando), não por linha, e manda
-- um aviso por (coleção, empresa) daquele comando:
--   * 1 registro no comando  → o mesmo aviso de sempre {c, id, op, por, loja}
--   * vários                 → {c, op, n, por, loja} (+ "ids" quando é exclusão
--                              de até 1.000 registros; acima disso o aparelho
--                              vê que a contagem não fecha e relê a coleção uma vez)
-- O aparelho não usa o aviso como dado: busca só o que mudou desde o carimbo.
--
-- PROTEÇÃO (igual à v541): o corpo inteiro está num bloco que engole QUALQUER
-- erro; o gatilho roda DEPOIS da gravação e nunca a desfaz. Falhou: o registro
-- fica gravado e só fica anotado "sinal_lote falhou" nos logs do Postgres.
-- Chave só de teste: "set local minas.sinal_teste_falha = '1'" força a falha.
--
-- Só ACRESCENTA funções e gatilhos novos; o gatilho por linha da v541 é tirado
-- (a função dele fica, sem uso, para o voltar atrás).
--
-- VOLTAR ATRÁS (volta ao aviso por registro da v541):
--   drop trigger if exists docs_sinal_lote_ins on public.docs;
--   drop trigger if exists docs_sinal_lote_upd on public.docs;
--   drop trigger if exists docs_sinal_lote_del on public.docs;
--   create trigger docs_sinal_mudanca after insert or update or delete on public.docs
--     for each row execute function public.docs_sinal_mudanca();
-- =====================================================================

-- manda o aviso de um grupo (coleção + empresa) de um comando
create or replace function public.docs_sinal_mandar(
  p_col text, p_loja text, p_n bigint, p_um text, p_ids text[], p_op text, p_por text)
 returns void
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_msg jsonb; r record;
begin
  if p_n = 1 then
    v_msg := jsonb_build_object('c', p_col, 'id', p_um, 'op', p_op, 'por', p_por);
  else
    -- id vazio de propósito: o realtime.send põe um id aleatório quando falta, e o aparelho
    -- reconhece o lote pelo id vazio
    v_msg := jsonb_build_object('c', p_col, 'id', null, 'op', p_op, 'n', p_n, 'por', p_por);
    if p_op = 'DELETE' and p_ids is not null and p_n <= 1000 then
      v_msg := v_msg || jsonb_build_object('ids', to_jsonb(p_ids));
    end if;
  end if;
  if p_loja is not null then
    perform realtime.send(v_msg || jsonb_build_object('loja', p_loja), 'mudou', 'sinal:' || p_loja, true);
  else
    for r in select distinct p.loja from public.perfis p where p.loja is not null loop
      perform realtime.send(v_msg, 'mudou', 'sinal:' || r.loja, true);
    end loop;
  end if;
end;
$function$;

-- criar e alterar: lê a tabela de transição "novos"
create or replace function public.docs_sinal_lote_novos()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_por text; g record;
begin
  begin
    if coalesce(current_setting('minas.sinal_teste_falha', true), '') = '1' then
      raise exception 'falha forcada para teste';
    end if;
    begin v_por := public.meu_nome(); exception when others then v_por := null; end;
    for g in
      select colecao c, loja l, count(*) n, min(id) um
        from novos
       where colecao = any(array['atendimentos','pedidos','requisicoes','ordens','orcamentos',
                                 'equipamentos','produtos','clientes'])
       group by colecao, loja
    loop
      perform public.docs_sinal_mandar(g.c, g.l, g.n, g.um, null, tg_op, v_por);
    end loop;
  exception when others then
    begin raise warning 'sinal_lote falhou (%): %', tg_op, sqlerrm;
    exception when others then null; end;
  end;
  return null;
end;
$function$;

-- apagar: lê a tabela de transição "velhos" (manda os códigos até 1.000)
create or replace function public.docs_sinal_lote_velhos()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_por text; g record;
begin
  begin
    if coalesce(current_setting('minas.sinal_teste_falha', true), '') = '1' then
      raise exception 'falha forcada para teste';
    end if;
    begin v_por := public.meu_nome(); exception when others then v_por := null; end;
    for g in
      select colecao c, loja l, count(*) n, min(id) um,
             case when count(*) <= 1000 then array_agg(id) end ids
        from velhos
       where colecao = any(array['atendimentos','pedidos','requisicoes','ordens','orcamentos',
                                 'equipamentos','produtos','clientes'])
       group by colecao, loja
    loop
      perform public.docs_sinal_mandar(g.c, g.l, g.n, g.um, g.ids, 'DELETE', v_por);
    end loop;
  exception when others then
    begin raise warning 'sinal_lote falhou (DELETE): %', sqlerrm;
    exception when others then null; end;
  end;
  return null;
end;
$function$;

comment on function public.docs_sinal_lote_novos() is
  'v542: um aviso por comando (colecao+empresa) no canal privado sinal:<loja>, em vez de um por registro. Nunca impede a gravacao.';
comment on function public.docs_sinal_lote_velhos() is
  'v542: aviso de exclusao por comando (com os codigos ate 1.000). Nunca impede a gravacao.';

drop trigger if exists docs_sinal_lote_ins on public.docs;
drop trigger if exists docs_sinal_lote_upd on public.docs;
drop trigger if exists docs_sinal_lote_del on public.docs;
create trigger docs_sinal_lote_ins after insert on public.docs
  referencing new table as novos for each statement execute function public.docs_sinal_lote_novos();
create trigger docs_sinal_lote_upd after update on public.docs
  referencing new table as novos for each statement execute function public.docs_sinal_lote_novos();
create trigger docs_sinal_lote_del after delete on public.docs
  referencing old table as velhos for each statement execute function public.docs_sinal_lote_velhos();

-- o aviso por registro da v541 sai (a função fica para o voltar atrás)
drop trigger if exists docs_sinal_mudanca on public.docs;
