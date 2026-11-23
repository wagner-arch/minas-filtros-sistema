-- ============================================================================
-- VOLTAR ATRAS DA v591 (23/11/2026): a funcao dos lembretes de ponto COMO ERA
-- antes, avisando 3 minutos antes de CADA um dos quatro horarios e, passado o
-- horario, a cada 2 minutos ate a pessoa bater.
--
-- Guardado so para poder voltar: foi ESTA regra que gerou 186 avisos num dia
-- para um vendedor e 342 para o login "Admin". A regra nova avisa 5, 3 e 1
-- minuto ANTES, e so da entrada e da volta do almoco.
--
-- Para voltar atras, rode este arquivo inteiro no SQL editor do Supabase.
-- ============================================================================

create or replace function public.lembretes_ponto_calc(
  p_data date, p_min int, p_pessoas jsonb, p_pontos jsonb, p_feriados jsonb, p_ligado jsonb)
returns table(loja text, nome text, marc text, prevista text, tipo text, titulo text, texto text)
language plpgsql immutable as $$
declare
  u jsonb; pt jsonb; lj text; m text; prev int; bat text; d int; dur int; ai text; hj text;
  nomes  jsonb := '{"checkin":"entrada","almocoIni":"saída do almoço","almocoFim":"volta do almoço","checkout":"saída"}';
  campos jsonb := '{"checkin":"entrada","almocoIni":"almocoIni","almocoFim":"almocoFim","checkout":"saida"}';
  padrao jsonb := '{"almocoIni":"12:00","almocoFim":"13:30"}';
begin
  if extract(isodow from p_data) > 5 then return; end if;
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
      if coalesce(bat,'') <> '' then continue; end if;
      hj := coalesce(nullif(u->>(campos->>m),''), padrao->>m);
      prev := public.ponto_hm_min(hj);
      if prev is null then continue; end if;
      if m = 'almocoFim' then
        ai := pt->'almocoIni'->>'hora';
        dur := public.ponto_hm_min(coalesce(nullif(u->>'almocoFim',''),padrao->>'almocoFim'))
             - public.ponto_hm_min(coalesce(nullif(u->>'almocoIni',''),padrao->>'almocoIni'));
        if coalesce(ai,'') <> '' and dur > 0 then prev := public.ponto_hm_min(ai) + dur; end if;
      end if;
      if prev >= 24*60 then continue; end if;
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
