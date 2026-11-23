-- ============================================================================
-- v591 (23/11/2026): O AVISO DE PONTO SO ANTES DO HORARIO
--
-- O que estava acontecendo: passado o horario, o servidor mandava um aviso a
-- cada 2 minutos ate a pessoa bater, para as QUATRO marcacoes. Num dia um
-- vendedor recebeu 186 avisos e o login "Admin" (que nem e pessoa) 342.
--
-- Regra nova (decisao dele):
--   * so a ENTRADA e a VOLTA DO ALMOCO avisam;
--   * so ANTES do horario: 5, 3 e 1 minuto antes;
--   * NADA depois do horario, nada para a saida do almoco e nada para a saida;
--   * quem ja bateu aquela marcacao nao recebe;
--   * folga, ferias, falta justificada, falta, feriado e fim de semana: nada;
--   * quem nao tem jornada ou nao bate ponto continua fora (e por isso o login
--     "Admin" ficou sem jornada no cadastro).
-- O liga/desliga por empresa (config/lembrete_ponto) nao muda.
--
-- A funcao antiga esta guardada em supabase/lembrete-ponto-v591-voltar-atras.sql.
-- A tela usa a MESMA regra em lembretesDevidos (LEMBRETE_MARCS/LEMBRETE_ANTES).
-- ============================================================================

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
    -- v591: SO a entrada e a volta do almoco
    foreach m in array array['checkin','almocoFim'] loop
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
      d := prev - p_min;                                                -- quantos minutos FALTAM
      -- v591: so 5, 3 e 1 minuto ANTES. Depois do horario, nada.
      if d not in (5,3,1) then continue; end if;
      tipo := 'antes';
      texto := format('Daqui a %s %s é o seu horário de %s (%s). Não esqueça de bater o ponto.',
        d, case when d = 1 then 'minuto' else 'minutos' end, nomes->>m, public.ponto_min_hm(prev));
      loja := lj; nome := u->>'nome'; marc := m; prevista := public.ponto_min_hm(prev); titulo := 'Lembrete de ponto';
      return next;
    end loop;
  end loop;
end $$;
