-- AVISO DO SISTEMA E TRAVA "SÓ CONSULTA" (06/11/2026, pedido do Wagner)
-- Para atualizações grandes no banco (a primeira foi a limpeza dos produtos) com a equipe trabalhando:
-- o documento config/aviso_sistema (Minas Filtros) e config/wf:aviso_sistema (WF) dizem o texto da
-- faixa que todos veem no alto da tela; com "trava": true o banco RECUSA toda gravação dos usuários
-- na tabela docs, menos a batida de ponto (pontos) e a foto de referência (facial). Quem recusa é o
-- banco, então vale também para quem está com uma versão antiga aberta. O servidor (funções e
-- tarefas agendadas, que não entram como usuário) continua gravando.
--
-- Ligar:    update docs set data = data || '{"trava":true,"texto":"..."}' where colecao='config' and id in ('aviso_sistema','wf:aviso_sistema');
-- Desligar: update docs set data = data || '{"trava":false,"texto":"...","ate":"<data e hora ISO>"}' where ...;
-- A trava lê só o documento da Minas Filtros (aviso_sistema): as duas empresas travam juntas.

create or replace function public.trava_sistema_docs() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_trava boolean;
begin
  -- só os usuários do sistema (entram como "authenticated" ou "anon"); o servidor passa direto
  if coalesce(auth.role(), '') not in ('authenticated', 'anon') then
    return coalesce(new, old);
  end if;
  if coalesce(new.colecao, old.colecao) in ('pontos', 'facial') then
    return coalesce(new, old);
  end if;
  select coalesce((d.data->>'trava')::boolean, false) into v_trava
    from public.docs d where d.colecao = 'config' and d.id = 'aviso_sistema';
  if coalesce(v_trava, false) then
    raise exception using errcode = 'P0001',
      message = 'O sistema está atualizando os produtos e códigos: por alguns minutos só consulta. Nada foi salvo e o que você preencheu continua na tela. Salve de novo depois do aviso de liberado.';
  end if;
  return coalesce(new, old);
end $$;

drop trigger if exists tg_trava_sistema_docs on public.docs;
create trigger tg_trava_sistema_docs before insert or update or delete on public.docs
  for each row execute function public.trava_sistema_docs();

-- os dois avisos nascem desligados
insert into public.docs (colecao, id, loja, data) values
  ('config', 'aviso_sistema', 'mf', '{"id":"aviso_sistema","texto":"","trava":false}'),
  ('config', 'wf:aviso_sistema', 'wf', '{"id":"wf:aviso_sistema","texto":"","trava":false}')
on conflict (colecao, id) do nothing;
