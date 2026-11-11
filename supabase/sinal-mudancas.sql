-- =====================================================================
-- AVISO DE MUDANÇA ENTRE APARELHOS (v541, 11/11/2026)
--
-- O que faz: toda gravação (criar, alterar, apagar) nas 8 coleções do dia a
-- dia manda um AVISO PEQUENO pelo Realtime — só {coleção, código, tipo,
-- quem gravou} — no canal da empresa ("sinal:mf", "sinal:wf"). O aparelho
-- que recebe NÃO usa o aviso como dado: ele busca só os registros alterados
-- depois do último carimbo (atualizado_em) e mescla na memória.
--
-- Por que assim e não o "postgres_changes" que os pedidos usavam:
--   * o postgres_changes manda o REGISTRO INTEIRO para cada aparelho (um
--     pedido com assinatura passa de 100 KB) e, para cada aparelho, o banco
--     confere a regra de acesso linha a linha;
--   * aqui vai ~150 bytes por mudança, num canal só por aparelho (o da empresa
--     aberta). Produto não tem empresa: o aviso dele vai para o canal de cada
--     empresa que tem colaborador.
--
-- Separação das empresas: o canal é PRIVADO; a regra de acesso abaixo só deixa
-- entrar no "sinal:mf" quem lê a Minas Filtros (ou tem a marca "ambas"). E o
-- aparelho, ao buscar, ainda pede só a empresa aberta.
--
-- Só ACRESCENTA: uma função, um gatilho e uma regra de leitura nova. Nenhum
-- dado é alterado. O aviso NUNCA impede a gravação: qualquer erro é engolido e
-- fica só anotado nos logs do Postgres ("sinal_mudanca falhou").
--
-- VOLTAR ATRÁS (desliga tudo, os aparelhos caem na conferência de 30 s):
--   drop trigger if exists docs_sinal_mudanca on public.docs;
--   drop function if exists public.docs_sinal_mudanca();
--   drop policy if exists sinal_mudancas_ler on realtime.messages;
-- =====================================================================

create or replace function public.docs_sinal_mudanca()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_col text; v_id text; v_loja text; v_por text; r record;
begin
  -- PROTEÇÃO: tudo aqui dentro está num bloco que engole QUALQUER erro.
  -- O gatilho roda DEPOIS da gravação e nunca a desfaz: se o aviso falhar,
  -- o registro fica gravado e o erro só fica anotado nos logs do Postgres
  -- ("sinal_mudanca falhou ...").
  begin
    -- chave só de teste: "set local minas.sinal_teste_falha = '1'" força a falha
    if coalesce(current_setting('minas.sinal_teste_falha', true), '') = '1' then
      raise exception 'falha forcada para teste';
    end if;

    if tg_op = 'DELETE' then v_col := old.colecao; v_id := old.id; v_loja := old.loja;
    else v_col := new.colecao; v_id := new.id; v_loja := new.loja; end if;

    if v_col <> all(array['atendimentos','pedidos','requisicoes','ordens','orcamentos',
                          'equipamentos','produtos','clientes']) then
      return null;
    end if;

    begin v_por := public.meu_nome(); exception when others then v_por := null; end;

    if v_loja is not null then
      perform realtime.send(
        jsonb_build_object('c', v_col, 'id', v_id, 'op', tg_op, 'por', v_por, 'loja', v_loja),
        'mudou', 'sinal:' || v_loja, true);
    else
      for r in select distinct p.loja from public.perfis p where p.loja is not null loop
        perform realtime.send(
          jsonb_build_object('c', v_col, 'id', v_id, 'op', tg_op, 'por', v_por),
          'mudou', 'sinal:' || r.loja, true);
      end loop;
    end if;
  exception when others then
    begin
      raise warning 'sinal_mudanca falhou (%, %, %): %', tg_op, v_col, v_id, sqlerrm;
    exception when others then null;
    end;
  end;
  return null;
end;
$function$;

comment on function public.docs_sinal_mudanca() is
  'v541: avisa pelo Realtime (canal privado sinal:<loja>) que um registro das 8 colecoes do dia a dia mudou. So o aviso, sem o dado.';

drop trigger if exists docs_sinal_mudanca on public.docs;
create trigger docs_sinal_mudanca
  after insert or update or delete on public.docs
  for each row execute function public.docs_sinal_mudanca();

-- quem pode ouvir o canal de cada empresa
drop policy if exists sinal_mudancas_ler on realtime.messages;
create policy sinal_mudancas_ler on realtime.messages
  as permissive for select to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and realtime.topic() like 'sinal:%'
    and (select public.meu_nome()) is not null
    and ((select public.vejo_todas_lojas())
         or substr(realtime.topic(), 7) = any((select public.minhas_lojas())::text[]))
  );
