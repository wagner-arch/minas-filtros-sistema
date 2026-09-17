-- Foto de referência própria (17/09): cada colaborador grava e lê a SUA foto.
-- A leitura já era permitida (docs_select_minha_biometria). Faltava gravar.
-- Rode no SQL Editor do Supabase. Pode rodar mais de uma vez.

drop policy if exists docs_insert_minha_facial on public.docs;
create policy docs_insert_minha_facial on public.docs
  for insert to authenticated
  with check (colecao = 'facial' and public.eh_meu_documento(data));

drop policy if exists docs_update_minha_facial on public.docs;
create policy docs_update_minha_facial on public.docs
  for update to authenticated
  using      (colecao = 'facial' and public.eh_meu_documento(data))
  with check (colecao = 'facial' and public.eh_meu_documento(data));
