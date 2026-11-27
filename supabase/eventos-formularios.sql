-- =====================================================================
--  FORMULÁRIOS DE EVENTO + SORTEIO  (27/11/2026, decisão do Wagner)
--  Versão 3 — com os três acertos que ele pediu depois de ler a v2:
--    1. "é cliente" idêntico ao ehLead do sistema (importado OU venda
--       com status diferente de 'Cancelada'), para a base antiga
--       importada não ser tratada como "não cliente";
--    2. o limite por aparelho só com endereço confiável — sem ele, ou
--       com endereço interno, o limite não se aplica, para o evento não
--       travar depois de 5 inscrições;
--    3. o LEAD nasce no servidor, na mesma gravação da inscrição.
--
--  POR QUE ESTE ARQUIVO EXISTE
--    O link do formulário é PÚBLICO: quem abre não tem login. Então ele
--    não pode falar com a tabela public.docs — nem para ler, nem para
--    gravar. Este arquivo cria DUAS portas estreitas (duas funções) que
--    fazem TODAS as conferências do lado do servidor e devolvem só o que
--    a página pública precisa. A tabela docs continua fechada para quem
--    não tem login: nenhuma regra nova de acesso é dada ao papel "anon".
--
--  O QUE ELE FAZ
--    1. guarda uma cópia das regras de acesso e das permissões de hoje
--    2. ajudantes de comparação (dígitos, WhatsApp sem o 55, e-mail),
--       o nome curto de quem atende e o endereço de quem enviou
--    3. evt_aberto(): o formulário está aceitando inscrição?
--    4. evento_publico(id): o que a página pública pode mostrar — com os
--       nomes de quem atende JÁ ENCURTADOS e um código no lugar do nome
--    5. evento_inscrever(id, dados): grava a inscrição, conferindo tudo,
--       gravando SÓ os campos que o formulário pede e com limite de
--       tamanho, de envios por aparelho e de envios por formulário —
--       e CRIA O LEAD na mesma gravação (item 10)
--    6. os índices que impedem inscrição repetida no mesmo instante
--    7. um sorteio por formulário e por rodada
--    8. o registro do sorteio não se altera nem se apaga
--    9. permissões: só as duas portas ficam abertas para quem não tem login
--   10. conferências e como voltar atrás
--
--  O QUE ELE NÃO FAZ
--    Não mexe em nenhuma regra de acesso que já existe, não mexe em
--    nenhuma tabela, não apaga nada e não altera nenhum dado. As coleções
--    novas (eventos, evtinscr, evtsorteio) já entram nas regras gerais de
--    public.docs criadas em 23/10 — quem tem login vê as da empresa dele.
--
--  COMO RODAR
--    Supabase › SQL Editor › New query › cole tudo › Run.
--    A cópia de segurança do bloco 1 é feita antes de qualquer coisa.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. CÓPIA DE SEGURANÇA DO QUE EXISTE HOJE
--    (mesma receita de empresas-separadas.sql: a cópia é feita UMA VEZ)
-- ---------------------------------------------------------------------
create schema if not exists backup;

create table if not exists backup.politicas_20261127 as
select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
  from pg_policies
 where schemaname = 'public';

select count(*) as regras_guardadas from backup.politicas_20261127;

-- a lista de funções que o papel "anon" pode executar HOJE, para comparar depois
create table if not exists backup.anon_funcoes_20261127 as
select p.proname, pg_get_function_identity_arguments(p.oid) as argumentos
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and has_function_privilege('anon', p.oid, 'execute');

select count(*) as funcoes_do_anon_antes from backup.anon_funcoes_20261127;


-- ---------------------------------------------------------------------
-- 2. AJUDANTES
-- ---------------------------------------------------------------------
create or replace function public.evt_so_digitos(t text)
returns text language sql immutable parallel safe as $$
  select regexp_replace(coalesce(t,''), '[^0-9]', '', 'g')
$$;

comment on function public.evt_so_digitos(text) is
  'Só os dígitos do texto: usado para comparar CPF/CNPJ sem máscara. Formulários de evento, 27/11/2026.';

-- WHATSAPP SEM O 55 DA FRENTE (correção 2 dele): o mesmo número escrito
-- com e sem o código do país é a MESMA pessoa. Vale na conferência de
-- repetição e na comparação com o telefone do cadastro de clientes.
create or replace function public.evt_zap(t text)
returns text language sql immutable parallel safe as $$
  select case
           when length(public.evt_so_digitos(t)) between 12 and 13
                and left(public.evt_so_digitos(t), 2) = '55'
             then substr(public.evt_so_digitos(t), 3)
           else public.evt_so_digitos(t)
         end
$$;

comment on function public.evt_zap(text) is
  'O WhatsApp só em dígitos e sem o 55 do país: é assim que se compara repetição e cadastro. 27/11/2026.';

create or replace function public.evt_chave(t text)
returns text language sql immutable parallel safe as $$
  select lower(regexp_replace(coalesce(t,''), '[^0-9A-Za-z@._+-]', '', 'g'))
$$;

comment on function public.evt_chave(text) is
  'Texto em minúsculas e sem pontuação solta: usado para comparar e-mail. 27/11/2026.';

-- QUEM ATENDE — REGRA DE 27/11 (a última dele): aparecem TODOS os
-- usuários ATIVOS da empresa do formulário, QUALQUER função. Quem está
-- marcado para as duas empresas aparece nas duas. Inativo fica fora.
--
-- A função CONTINUA existindo, com o mesmo nome, o mesmo argumento e o
-- mesmo tipo de retorno, para evento_publico e evento_inscrever não
-- mudarem — e para um dia dar para restringir de novo num lugar só.
-- O que separa quem entra é o "ativo" e a empresa, nas duas portas.
--
-- A regra de antes (vendedor, consultor, gerente e administrador) ficou
-- guardada em backup.evt_funcao_atende_20261127, com o texto inteiro da
-- função, para voltar atrás copiando de lá:
--   select definicao from backup.evt_funcao_atende_20261127;
create table if not exists backup.evt_funcao_atende_20261127 as
select p.proname,
       pg_get_function_identity_arguments(p.oid) as argumentos,
       pg_get_functiondef(p.oid)                as definicao,
       now()                                    as guardado_em
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname = 'evt_funcao_atende';

create or replace function public.evt_funcao_atende(f text)
returns boolean language sql immutable parallel safe as $$
  select true
$$;

comment on function public.evt_funcao_atende(text) is
  'Quem atende cliente no formulário de evento: QUALQUER função (regra dele de 27/11). O que filtra é o ativo e a empresa. A definição anterior está em backup.evt_funcao_atende_20261127.';

-- O NOME CURTO DE QUEM ATENDE (correção 6 dele): a página pública recebe
-- só o primeiro nome; havendo dois com o mesmo primeiro nome, entra a
-- inicial do sobrenome. O nome completo NUNCA sai por esta porta.
create or replace function public.evt_nome_curto(nome text, repetido boolean)
returns text language sql immutable parallel safe as $$
  select case
           when coalesce(repetido,false)
                and array_length(regexp_split_to_array(btrim(coalesce(nome,'')), '\s+'), 1) > 1
             then (regexp_split_to_array(btrim(nome), '\s+'))[1] || ' ' ||
                  upper(left((regexp_split_to_array(btrim(nome), '\s+'))[2], 1)) || '.'
           else coalesce((regexp_split_to_array(btrim(coalesce(nome,'')), '\s+'))[1], '')
         end
$$;

comment on function public.evt_nome_curto(text, boolean) is
  'Primeiro nome de quem atendeu; com o primeiro nome repetido, entra a inicial do sobrenome. 27/11/2026.';

-- O ENDEREÇO DE QUEM ENVIOU (acerto 2 dele, 27/11): SÓ cf-connecting-ip
-- (posto pela Cloudflare, que fica na frente do Supabase e sobrescreve o
-- que vier) e, na falta dele, x-real-ip (posto pelo servidor da frente).
-- O x-forwarded-for NÃO entra mais, nem o último item dele: se um dia a
-- lista chegar de um jeito que faça todo mundo cair no mesmo endereço, o
-- evento travaria nas 5 primeiras inscrições. Vale a decisão dele: na
-- dúvida, não aplicar o limite por aparelho.
create or replace function public.evt_ip()
returns text language plpgsql stable as $$
declare h json;
begin
  begin
    h := current_setting('request.headers', true)::json;
  exception when others then
    return '';
  end;
  if h is null then return ''; end if;
  if coalesce(h->>'cf-connecting-ip','') <> '' then
    return btrim(h->>'cf-connecting-ip');
  end if;
  return btrim(coalesce(h->>'x-real-ip',''));
end
$$;

comment on function public.evt_ip() is
  'O endereço de quem enviou: cf-connecting-ip ou, na falta dele, x-real-ip. Nunca o x-forwarded-for. 27/11/2026.';

-- ENDEREÇO INTERNO não identifica aparelho nenhum: é a rede de dentro.
-- Com um destes, o limite por aparelho não se aplica (acerto 2 dele).
-- 10.x, 172.16–172.31.x, 192.168.x, 127.x, ::1 e as faixas fc/fd do IPv6.
create or replace function public.evt_ip_interno(p_ip text)
returns boolean language plpgsql immutable as $$
declare t text := lower(btrim(coalesce(p_ip,'')));
begin
  if t = '' then return true; end if;
  -- IPv4 escrito dentro de IPv6 (::ffff:10.0.0.1) conta pela parte de IPv4
  if position('.' in t) > 0 and position(':' in t) > 0 then
    t := regexp_replace(t, '^.*:', '');
  end if;
  if t like '10.%' or t like '192.168.%' or t like '127.%' or t = '::1'
     or t like 'fc%' or t like 'fd%' or t like '169.254.%' or t = '0.0.0.0' then
    return true;
  end if;
  if t ~ '^172\.(1[6-9]|2[0-9]|3[01])\.' then
    return true;
  end if;
  return false;
end
$$;

comment on function public.evt_ip_interno(text) is
  'O endereço é da rede de dentro (10.x, 172.16-31.x, 192.168.x, 127.x, ::1, fc/fd)? Nele o limite por aparelho não se aplica. 27/11/2026.';

-- PARA TESTAR DEPOIS DE APLICAR (pedido dele): diz QUAL cabeçalho chegou e
-- o que o limite por aparelho vai fazer. Não conta nada de ninguém: só o
-- endereço de quem está chamando, que quem chama já sabe. Como testar, com
-- a chave publicável que a página pública já usa:
--
--   curl -s -X POST "https://clnccthtvfuetmfwuanu.supabase.co/rest/v1/rpc/evt_qual_ip" \
--     -H "apikey: <chave publicável>" -H "Content-Type: application/json" -d '{}'
--
-- Medido em 27/11, pela internet, do computador dele:
--   {"de": "cf-connecting-ip", "usado": "<o endereço>", "limite": "aplica",
--    "interno": false, "x_real_ip": "", "x_forwarded_for": "<o mesmo endereço>"}
-- Ela roda como as duas portas ("security definer"): chamada por quem não
-- tem login, precisa usar evt_ip e evt_ip_interno, que estão fechadas para
-- o anon. Sem isto, a resposta era "permission denied for function evt_ip"
-- (achado no teste de 27/11, pela internet).
create or replace function public.evt_qual_ip()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare h json; ip text;
begin
  begin
    h := current_setting('request.headers', true)::json;
  exception when others then
    h := null;
  end;
  ip := public.evt_ip();
  return jsonb_build_object(
    'cf_connecting_ip', coalesce(h->>'cf-connecting-ip',''),
    'x_real_ip',        coalesce(h->>'x-real-ip',''),
    'x_forwarded_for',  coalesce(h->>'x-forwarded-for',''),   -- só para ver; não é usado
    'usado',            ip,
    'de',               case when coalesce(h->>'cf-connecting-ip','') <> '' then 'cf-connecting-ip'
                             when coalesce(h->>'x-real-ip','')        <> '' then 'x-real-ip'
                             else 'nenhum' end,
    'interno',          public.evt_ip_interno(ip),
    'limite',           case when ip <> '' and not public.evt_ip_interno(ip)
                             then 'aplica' else 'nao aplica' end);
end
$$;

comment on function public.evt_qual_ip() is
  'Conferência: qual cabeçalho de endereço chegou e se o limite por aparelho se aplica. Devolve só o endereço de quem chama. 27/11/2026.';

-- ---------------------------------------------------------------------
-- 2b. O LEAD DO SERVIDOR: AS AJUDANTES
--     O lead nasce com a MESMA estrutura do lead que o Atendimento cria
--     hoje (item 10 dele): mesmo formato de id, mesmo código da
--     numeração, maiúsculas e a loja do formulário.
-- ---------------------------------------------------------------------
-- O MESMO FORMATO DE ID do sistema: uid() no HTML é
-- Date.now().toString(36) + 5 letras/dígitos sorteados.
create or replace function public.evt_base36(p_n bigint)
returns text language plpgsql immutable as $$
declare d text := '0123456789abcdefghijklmnopqrstuvwxyz'; r text := ''; v bigint := p_n;
begin
  if v <= 0 then return '0'; end if;
  while v > 0 loop
    r := substr(d, (v % 36)::int + 1, 1) || r;
    v := v / 36;
  end loop;
  return r;
end
$$;

create or replace function public.evt_uid()
returns text language plpgsql volatile as $$
declare d text := '0123456789abcdefghijklmnopqrstuvwxyz'; r text := ''; i int;
begin
  for i in 1..5 loop
    r := r || substr(d, floor(random() * 36)::int + 1, 1);
  end loop;
  return public.evt_base36((extract(epoch from clock_timestamp()) * 1000)::bigint) || r;
end
$$;

comment on function public.evt_uid() is
  'Id no mesmo formato do uid() do sistema: tempo em base 36 + 5 sorteados. 27/11/2026.';

-- O CÓDIGO DO CLIENTE pela mesma numeração do sistema. Não dá para chamar
-- proximo_numero aqui: ela exige colaborador autenticado (meu_nome()), e
-- quem preenche o formulário não tem login. Então o contador é o MESMO
-- (public.numeradores, tipo 'cliente'), incrementado do mesmo jeito, numa
-- linha travada pelo Postgres — dois envios no mesmo instante nunca
-- recebem o mesmo código. O formato é o do HTML: prefixo + (último + 1)
-- com 5 casas.
create or replace function public.evt_codigo_cliente(p_loja text)
returns text language plpgsql volatile as $$
declare v_num int;
begin
  insert into public.numeradores as n (loja, tipo, ultimo)
  values (p_loja, 'cliente', public.base_numerador('cliente'))
  on conflict (loja, tipo)
  do update set ultimo = n.ultimo + 1, atualizado_em = now()
  returning n.ultimo into v_num;
  return (case p_loja when 'mf' then 'MF' when 'wf' then 'WF' else 'CL' end)
         || '-' || lpad((v_num + 1)::text, 5, '0');
end
$$;

comment on function public.evt_codigo_cliente(text) is
  'O próximo código de cliente da loja, pelo mesmo contador do sistema (numeradores/cliente). 27/11/2026.';

-- "É CLIENTE" IGUAL AO ehLead DO SISTEMA (acerto 1 dele): cliente é quem
-- tem a marca de importado OU uma venda com status diferente de
-- 'Cancelada'. Sem a marca de importado, a base antiga inteira seria
-- tratada como "não cliente" nos formulários "Só clientes" e "Só novos".
-- A marca 'cancelado' saiu: o ehLead olha SÓ o status, e as duas regras
-- têm de dar a mesma resposta.
create or replace function public.evt_eh_cliente(p_loja text, p_whats text, p_cpf text)
returns boolean language sql stable as $$
  select exists(
    select 1
      from public.docs c
     where c.colecao = 'clientes'
       and c.loja = p_loja
       and ( (p_whats <> '' and ( public.evt_zap(c.data->>'tel')  = p_whats
                               or public.evt_zap(c.data->>'tel2') = p_whats
                               or public.evt_zap(c.data->>'tel3') = p_whats
                               or public.evt_zap(c.data->>'tel4') = p_whats ))
          or (p_cpf   <> '' and public.evt_so_digitos(c.data->>'doc') = p_cpf) )
       and ( lower(coalesce(c.data->>'importado','')) in ('true','t','1')
          or exists( select 1
                       from public.docs p
                      where p.colecao = 'pedidos'
                        and p.loja = p_loja
                        and p.data->>'clienteId' = c.id
                        and coalesce(p.data->>'status','') <> 'Cancelada' ) )
  );
$$;

comment on function public.evt_eh_cliente(text, text, text) is
  'É cliente feito? Igual ao ehLead do sistema: importado OU venda com status diferente de Cancelada. 27/11/2026.';


-- ---------------------------------------------------------------------
-- 3. O FORMULÁRIO ESTÁ ACEITANDO INSCRIÇÃO?
--    Fechado quando: foi encerrado à mão, foi arquivado, já teve sorteio
--    válido, ou chegou a hora do encerramento automático (item 17).
--    O horário é o de Brasília, como no resto do sistema.
-- ---------------------------------------------------------------------
create or replace function public.evt_aberto(d jsonb)
returns boolean language plpgsql stable as $$
declare fim timestamp;
begin
  if coalesce(d->>'status','aberto') <> 'aberto'
     or coalesce((d->>'arquivado')::boolean, false)
     or coalesce((d->>'sorteado')::boolean, false) then
    return false;
  end if;
  if coalesce(d->>'fecharEm','') = '' then
    return true;
  end if;
  -- data de encerramento escrita errada não pode derrubar a página pública:
  -- não dá para ler, o formulário segue aberto e quem cuida vê na tela do sistema
  begin
    fim := (d->>'fecharEm')::timestamp;
  exception when others then
    return true;
  end;
  return fim > (now() at time zone 'America/Sao_Paulo');
end
$$;

comment on function public.evt_aberto(jsonb) is
  'Diz se o formulário de evento ainda aceita inscrição. 27/11/2026.';


-- ---------------------------------------------------------------------
-- 4. O QUE A PÁGINA PÚBLICA PODE MOSTRAR
--    Devolve SÓ: nome do evento, empresa, campos pedidos, prêmio, regras,
--    data do sorteio e — se o formulário pedir — a lista de quem atende,
--    com o NOME CURTO e um CÓDIGO (correção 6). Nada de cliente, nada de
--    lead, nada de outro formulário, nenhum nome completo.
--    Quem atende: TODOS os usuários ATIVOS da empresa do formulário,
--    qualquer função (regra dele de 27/11); quem está marcado para as
--    duas aparece nas duas, e inativo fica fora.
-- ---------------------------------------------------------------------
create or replace function public.evento_publico(p_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  d jsonb; l text; nomes jsonb;
begin
  select data, loja into d, l
    from public.docs
   where colecao = 'eventos' and id = p_id;

  if d is null or coalesce((d->>'arquivado')::boolean, false) then
    return jsonb_build_object('erro', 'nao_existe');
  end if;

  if coalesce((d->>'pedeAtendente')::boolean, false) then
    with equipe as (
      select p.user_id::text as cod, p.nome,
             count(*) over (partition by lower((regexp_split_to_array(btrim(p.nome), '\s+'))[1])) > 1 as repetido
        from public.perfis p
       where p.ativo
         and public.evt_funcao_atende(p.funcao)
         and (p.loja = l or p.ambas)
    )
    select coalesce(jsonb_agg(jsonb_build_object('cod', cod,
                                                 'curto', public.evt_nome_curto(nome, repetido))
                              order by public.evt_nome_curto(nome, repetido)), '[]'::jsonb)
      into nomes
      from equipe;
  else
    nomes := '[]'::jsonb;
  end if;

  return jsonb_build_object(
    'id',            p_id,
    'loja',          l,
    'nome',          coalesce(d->>'nome',''),
    'campos',        coalesce(d->'campos', '[]'::jsonb),
    'pedeAtendente', coalesce((d->>'pedeAtendente')::boolean, false),
    'atendentes',    coalesce(nomes, '[]'::jsonb),
    'premio',        coalesce(d->>'premio',''),
    'regras',        coalesce(d->>'regras',''),
    'sorteioEm',     coalesce(d->>'sorteioEm',''),
    'aberto',        public.evt_aberto(d)
  );
end
$$;

comment on function public.evento_publico(text) is
  'Porta pública de LEITURA do formulário de evento: só os dados da página, com quem atende em nome curto e código. 27/11/2026.';


-- ---------------------------------------------------------------------
-- 5. GRAVAR A INSCRIÇÃO
--    Confere, do lado do servidor: tamanho do que chegou, formulário
--    aberto, encerramento automático, aceite, campo isca e tempo mínimo
--    (robô), limite de envios do mesmo aparelho e do formulário inteiro,
--    nome e WhatsApp, CPF/CNPJ, campos obrigatórios, inscrição repetida
--    e "quem pode participar".
--    GRAVA SÓ O QUE O FORMULÁRIO PEDE (correção 1): nome, WhatsApp, o
--    atendente e as chaves que estão em campos. Qualquer outra chave que
--    chegue é ignorada — nada do que o cliente mandar entra sem pedir.
--    Nunca conta para fora POR QUE recusou quando o assunto é ser ou não
--    ser cliente: devolve 'nao_pode', e a página mostra a mensagem
--    genérica (regra dele, item 4).
--    "Cliente" é quem o ehLead do sistema chama de cliente: cadastro com a
--    marca de importado OU com venda de status diferente de 'Cancelada'
--    (acerto 1 dele) — por evt_eh_cliente.
--    E O LEAD NASCE AQUI (item 10, aprovado por ele): na mesma gravação,
--    com a mesma estrutura do lead do Atendimento. Cadastro que já existe
--    não é tocado; achando mais de um, a inscrição fica "a conferir".
-- ---------------------------------------------------------------------
create or replace function public.evento_inscrever(p_id text, p_dados jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  d jsonb; l text; campos jsonb; campo jsonb;
  dados jsonb := '{}'::jsonb;
  chave text; valor text; lim int;
  whats text; cpf text; email text;
  seg numeric; ip text; iph text;
  n int; ja int; eh_cliente boolean; novo_id text; agora text;
  at_cod text; at_nome text;
  quantos int; cli_id text; lead jsonb; hoje text;
begin
  -- o pacote inteiro tem limite (correção 1)
  if length(coalesce(p_dados::text,'')) > 8192 then
    return jsonb_build_object('erro', 'invalido');
  end if;

  select data, loja into d, l
    from public.docs
   where colecao = 'eventos' and id = p_id;

  if d is null or coalesce((d->>'arquivado')::boolean, false) then
    return jsonb_build_object('erro', 'nao_existe');
  end if;
  if not public.evt_aberto(d) then
    return jsonb_build_object('erro', 'fechado');
  end if;

  -- robô: o campo isca tem de chegar vazio e o preenchimento leva tempo
  if coalesce(p_dados->>'isca','') <> '' then
    return jsonb_build_object('erro', 'robo');
  end if;
  begin
    seg := coalesce((p_dados->>'segundos')::numeric, 0);
  exception when others then
    seg := 0;
  end;
  if seg < 4 then
    return jsonb_build_object('erro', 'rapido');
  end if;

  if coalesce((p_dados->>'aceite')::boolean, false) is not true then
    return jsonb_build_object('erro', 'aceite');
  end if;

  -- ---- a LISTA FECHADA de campos: nome, WhatsApp e o que o formulário pede ----
  campos := coalesce(d->'campos', '[]'::jsonb);

  foreach chave in array (array['nome','whats'] ||
      coalesce((select array_agg(c->>'k') from jsonb_array_elements(campos) c), array[]::text[]))
  loop
    valor := btrim(coalesce(p_dados->>chave, ''));
    -- endereço, complemento e ponto de referência são mais compridos
    lim := case when chave in ('rua','ref','comp') then 300 else 200 end;
    if length(valor) > lim then
      return jsonb_build_object('erro', 'invalido');
    end if;
    if valor <> '' then
      dados := dados || jsonb_build_object(chave, valor);
    end if;
  end loop;

  -- campos obrigatórios do formulário, conferidos aqui também
  for campo in select * from jsonb_array_elements(campos) loop
    if coalesce((campo->>'obrig')::boolean, false)
       and coalesce(dados->>(campo->>'k'), '') = '' then
      return jsonb_build_object('erro', 'faltou', 'campo', campo->>'k');
    end if;
  end loop;

  -- o atendente vem por CÓDIGO e tem de ser um da lista daquele formulário;
  -- não sendo, grava vazio (correções 1 e 6). O nome completo quem escreve é aqui.
  if coalesce((d->>'pedeAtendente')::boolean, false) then
    at_cod := btrim(coalesce(p_dados->>'atendenteId', ''));
    if at_cod <> '' and length(at_cod) <= 64 then
      select p.nome into at_nome
        from public.perfis p
       where p.user_id::text = at_cod
         and p.ativo
         and public.evt_funcao_atende(p.funcao)
         and (p.loja = l or p.ambas);
    end if;
    if at_nome is not null then
      dados := dados || jsonb_build_object('atendenteId', at_cod, 'atendente', at_nome);
    end if;
  end if;

  -- ---- o que precisa estar certo ----
  whats := public.evt_zap(dados->>'whats');
  cpf   := public.evt_so_digitos(dados->>'doc');
  email := public.evt_chave(dados->>'email');

  if coalesce(dados->>'nome','') = '' then
    return jsonb_build_object('erro', 'invalido');
  end if;
  if length(whats) < 10 or length(whats) > 13 then
    return jsonb_build_object('erro', 'invalido');
  end if;
  if cpf <> '' and length(cpf) not in (11, 14) then
    return jsonb_build_object('erro', 'invalido');
  end if;

  -- LIMITE DE ENVIOS DO MESMO APARELHO (o endereço não é guardado: só o
  -- resumo dele). Sem endereço confiável, ou com endereço interno, o
  -- limite NÃO se aplica (acerto 2 dele): o risco de todo mundo cair no
  -- mesmo endereço e o evento travar na 6ª inscrição é pior que o do
  -- envio repetido, que o limite do formulário inteiro já segura.
  ip := public.evt_ip();
  if ip <> '' and not public.evt_ip_interno(ip) then
    iph := md5(ip || '|' || p_id);
    select count(*) into n
      from public.docs
     where colecao = 'evtinscr'
       and data->>'ipHash' = iph
       and criado_em > now() - interval '10 minutes';
    if n >= 5 then
      return jsonb_build_object('erro', 'muitos');
    end if;
  else
    iph := '';     -- sem endereço de que o servidor possa responder
  end if;

  -- e o limite do formulário inteiro, contra ataque em massa (correção 8)
  select count(*) into n
    from public.docs
   where colecao = 'evtinscr'
     and data->>'formId' = p_id
     and criado_em > now() - interval '10 minutes';
  if n >= 300 then
    return jsonb_build_object('erro', 'muitos');
  end if;

  -- uma inscrição por pessoa em cada formulário
  select count(*) into ja
    from public.docs
   where colecao = 'evtinscr'
     and data->>'formId' = p_id
     and ( data->>'kWhats' = whats
        or (cpf   <> '' and data->>'kCpf'   = cpf)
        or (email <> '' and data->>'kEmail' = email) );
  if ja > 0 then
    return jsonb_build_object('erro', 'repetido');
  end if;

  -- QUEM PODE PARTICIPAR, pela mesma regra do ehLead (acerto 1 dele)
  if coalesce(d->>'quemPode','todos') <> 'todos' then
    eh_cliente := public.evt_eh_cliente(l, whats, cpf);

    if (d->>'quemPode') = 'clientes' and not eh_cliente then
      return jsonb_build_object('erro', 'nao_pode');
    end if;
    if (d->>'quemPode') = 'novos' and eh_cliente then
      return jsonb_build_object('erro', 'nao_pode');
    end if;
  end if;

  agora   := to_char(now() at time zone 'America/Sao_Paulo', 'YYYY-MM-DD HH24:MI');
  -- o lead do Atendimento grava criadoEm e origemEm com o DIA (iso(new Date())),
  -- não com a hora: aqui é igual, para o cadastro sair do mesmo jeito
  hoje    := to_char(now() at time zone 'America/Sao_Paulo', 'YYYY-MM-DD');
  novo_id := 'evti-' || replace(gen_random_uuid()::text, '-', '');

  -- duas pessoas enviando no mesmo instante: quem chegar depois bate nos
  -- índices do bloco 6 e recebe a mesma resposta de repetido (correção 3)
  begin
    insert into public.docs(colecao, id, loja, data)
    values ('evtinscr', novo_id, l,
      dados ||
      jsonb_build_object(
        'formId',   p_id,
        'kWhats',   whats,
        'kCpf',     cpf,
        'kEmail',   email,
        'ipHash',   iph,
        'em',       agora,
        'aceiteEm', agora,
        'aceite',   true,
        'publica',  true,
        'historico', jsonb_build_array(
          jsonb_build_object('em', agora, 'por', 'página pública',
                             'texto', 'Inscrição feita pelo link do evento'))
      ));
  exception when unique_violation then
    return jsonb_build_object('erro', 'repetido');
  end;

  -- ---------------------------------------------------------------------
  -- O LEAD NASCE AQUI (item 10, aprovado por ele em 27/11)
  --   Procura na coleção 'clientes' da MESMA empresa, por WhatsApp sem o
  --   55 (tel, tel2, tel3, tel4) e por CPF/CNPJ.
  --     não achou      -> cria o lead, com a estrutura do lead do
  --                       Atendimento, e grava o id na inscrição
  --     achou um       -> NÃO encosta no cadastro; grava só o clienteId.
  --                       A nota "Inscrito no evento X" continua sendo do
  --                       sistema: ele grava o cadastro INTEIRO quando
  --                       alguém salva a ficha, e uma nota escrita aqui
  --                       enquanto a ficha está aberta seria apagada na
  --                       próxima gravação da tela.
  --     achou mais de  -> não cria e não liga: marca "a conferir" para a
  --     um               equipe escolher na tela.
  --   Tudo isto está dentro do seu próprio "begin": dando qualquer
  --   problema, a INSCRIÇÃO continua gravada e o sistema liga depois, do
  --   jeito que já fazia. Uma inscrição nunca se perde por causa do lead.
  -- ---------------------------------------------------------------------
  begin
    select count(*), min(c.id) into quantos, cli_id
      from public.docs c
     where c.colecao = 'clientes'
       and c.loja = l
       and ( public.evt_zap(c.data->>'tel')  = whats
          or public.evt_zap(c.data->>'tel2') = whats
          or public.evt_zap(c.data->>'tel3') = whats
          or public.evt_zap(c.data->>'tel4') = whats
          or (cpf <> '' and public.evt_so_digitos(c.data->>'doc') = cpf) );

    if quantos = 1 then
      update public.docs
         set data = data || jsonb_build_object('clienteId', cli_id, 'ehNovo', false),
             atualizado_em = now()
       where colecao = 'evtinscr' and id = novo_id;

    elsif quantos > 1 then
      update public.docs
         set data = data || jsonb_build_object('aConferir', true,
               'historico', coalesce(data->'historico','[]'::jsonb) ||
                 jsonb_build_array(jsonb_build_object('em', agora, 'por', 'página pública',
                   'texto', 'Mais de um cadastro com este WhatsApp ou CPF: a equipe escolhe qual é'))),
             atualizado_em = now()
       where colecao = 'evtinscr' and id = novo_id;

    else
      cli_id := public.evt_uid();
      -- os MESMOS campos do lead que o Atendimento cria hoje, na mesma ordem
      lead := jsonb_build_object(
        'id',                cli_id,
        'loja',              l,
        'codigo',            public.evt_codigo_cliente(l),
        'tipo',              coalesce(nullif(btrim(coalesce(dados->>'tipo','')),''), 'Pessoa Física'),
        'nome',              upper(coalesce(dados->>'nome','')),
        'sexo',              coalesce(dados->>'sexo',''),
        'tel',               coalesce(dados->>'whats',''),
        'nasc',              coalesce(dados->>'nasc',''),
        'doc',               coalesce(dados->>'doc',''),
        'cidade',            upper(coalesce(dados->>'cidade','')),
        'uf',                upper(coalesce(dados->>'uf','')),
        'origem',            coalesce(d->>'nome',''),
        'origemEm',          hoje,
        'cep',               coalesce(dados->>'cep',''),
        'rua',               upper(coalesce(dados->>'rua','')),
        'num',               upper(coalesce(dados->>'num','')),
        'bairro',            upper(coalesce(dados->>'bairro','')),
        'comp',              upper(coalesce(dados->>'comp','')),
        'ref',               upper(coalesce(dados->>'ref','')),
        'tipoend',           'urbano',
        'geo',               '',
        'geoOrigem',         '',
        'geoNivel',          '',
        'geoFonte',          '',
        'indicado',          '',
        'tipoPrimeiroAtend', '',
        'primeiroAtendEm',   '',
        'criadoEm',          hoje,
        'criadoPor',         'Formulário de evento',
        'criadoVia',         'evento')
        -- e o que é deste caminho: de qual formulário veio, quem atendeu,
        -- o e-mail em minúsculas e a nota do cadastro novo
        || jsonb_build_object(
        'eventoId',          p_id,
        'atendente',         coalesce(dados->>'atendente',''),
        'email',             lower(coalesce(dados->>'email','')),
        'tel2',              '',
        'tel3',              '',
        'tel4',              '',
        'notas',             jsonb_build_array(jsonb_build_object(
                               'quando', agora, 'por', 'Formulário de evento',
                               'texto',  'Inscrito no evento ' || coalesce(d->>'nome','') ||
                                 ' em ' || agora ||
                                 case when coalesce(dados->>'atendente','') <> ''
                                      then ' · atendente: ' || (dados->>'atendente') else '' end)));

      insert into public.docs(colecao, id, loja, data)
      values ('clientes', cli_id, l, lead);

      update public.docs
         set data = data || jsonb_build_object('clienteId', cli_id, 'ehNovo', true,
               'ligadoEm', agora, 'ligadoPor', 'Formulário de evento',
               'historico', coalesce(data->'historico','[]'::jsonb) ||
                 jsonb_build_array(jsonb_build_object('em', agora, 'por', 'página pública',
                   'texto', 'Lead criado com a origem ' || coalesce(d->>'nome','')))),
             atualizado_em = now()
       where colecao = 'evtinscr' and id = novo_id;
    end if;
  exception when others then
    null;   -- a inscrição está gravada; o sistema liga ao cadastro depois
  end;

  return jsonb_build_object('ok', true);
end
$$;

comment on function public.evento_inscrever(text, jsonb) is
  'Porta pública de GRAVAÇÃO da inscrição: lista fechada de campos, limites de tamanho e de envio, e todas as conferências no servidor. 27/11/2026.';


-- ---------------------------------------------------------------------
-- 6. NADA DE DUAS INSCRIÇÕES DA MESMA PESSOA NO MESMO INSTANTE
--    A conferência de repetição acima resolve o caso normal; estes dois
--    índices resolvem o caso de dois envios no mesmo segundo, em que as
--    duas conferências passam antes de qualquer uma gravar (correção 3).
--    Só valem para chave preenchida — por isso o "Apagar dados a pedido
--    do titular", que esvazia kWhats e kCpf, continua funcionando, e mais
--    de uma inscrição apagada convive sem bater no índice.
--    "Corrigir o WhatsApp" também continua: ele só é recusado se o número
--    novo já for de outra inscrição DAQUELE formulário — que é a regra.
-- ---------------------------------------------------------------------
create unique index if not exists docs_evtinscr_um_zap_por_form
  on public.docs ((data->>'formId'), (data->>'kWhats'))
  where colecao = 'evtinscr' and coalesce(data->>'kWhats','') <> '';

create unique index if not exists docs_evtinscr_um_cpf_por_form
  on public.docs ((data->>'formId'), (data->>'kCpf'))
  where colecao = 'evtinscr' and coalesce(data->>'kCpf','') <> '';


-- ---------------------------------------------------------------------
-- 7. UM SORTEIO VÁLIDO POR FORMULÁRIO, POR RODADA
--    Dois aparelhos sorteando no mesmo instante: o primeiro grava, o
--    segundo bate neste índice e recebe "o sorteio já foi realizado"
--    (item 6). Anulação, substituição e aviso são registros NOVOS, de
--    outro tipo, e por isso não disputam este índice.
--    A "rodada" existe por causa do item 13: anulado o sorteio, pode-se
--    sortear de novo — a rodada 2 é outro sorteio, e os dois continuam no
--    registro. Rodada sem valor conta como 1 (correção 4), para um
--    registro escrito sem ela não escapar da trava.
-- ---------------------------------------------------------------------
drop index if exists public.docs_evtsorteio_um_por_form;
create unique index docs_evtsorteio_um_por_form
  on public.docs ((data->>'formId'), (coalesce(data->>'rodada','1')))
  where colecao = 'evtsorteio' and data->>'tipo' = 'sorteio';


-- ---------------------------------------------------------------------
-- 8. O REGISTRO DO SORTEIO NÃO SE ALTERA NEM SE APAGA
--    Nem o Administrador (item 8). Anular não apaga: grava um registro
--    novo do tipo 'anulacao' apontando para o sorteio.
--    POR ISSO o registro guarda só a POSIÇÃO e o ID da inscrição: o nome
--    aparece vindo da inscrição, e o "Apagar dados a pedido do titular"
--    some do registro sem precisar mexer nele (correção 5).
-- ---------------------------------------------------------------------
create or replace function public.evt_registro_nao_muda()
returns trigger language plpgsql as $$
begin
  if coalesce(old.colecao,'') = 'evtsorteio' then
    raise exception
      'O registro do sorteio não pode ser alterado nem apagado. Para desfazer, use Anular sorteio: o anulado continua no registro.';
  end if;
  return null;
end
$$;

drop trigger if exists docs_evtsorteio_append_only on public.docs;
create trigger docs_evtsorteio_append_only
  before update or delete on public.docs
  for each row
  when (old.colecao = 'evtsorteio')
  execute function public.evt_registro_nao_muda();


-- ---------------------------------------------------------------------
-- 9. QUEM NÃO TEM LOGIN SÓ PODE EXECUTAR AS DUAS PORTAS
--    As ajudantes ficam só para quem tem login (as portas as usam por
--    dentro, por serem "security definer") — correção 9, para a
--    conferência (a) mostrar SÓ as duas portas novas a mais.
--    Nenhuma regra nova em public.docs: a tabela continua fechada.
-- ---------------------------------------------------------------------
revoke all on function public.evento_publico(text)           from public, anon, authenticated;
revoke all on function public.evento_inscrever(text, jsonb)  from public, anon, authenticated;
revoke all on function public.evt_so_digitos(text)           from public, anon;
revoke all on function public.evt_zap(text)                  from public, anon;
revoke all on function public.evt_chave(text)                from public, anon;
revoke all on function public.evt_funcao_atende(text)        from public, anon;
revoke all on function public.evt_nome_curto(text, boolean)  from public, anon;
revoke all on function public.evt_ip()                       from public, anon;
revoke all on function public.evt_ip_interno(text)           from public, anon;
revoke all on function public.evt_base36(bigint)             from public, anon;
revoke all on function public.evt_uid()                      from public, anon;
revoke all on function public.evt_codigo_cliente(text)       from public, anon;
revoke all on function public.evt_eh_cliente(text,text,text) from public, anon;
revoke all on function public.evt_qual_ip()                  from public, anon, authenticated;
revoke all on function public.evt_aberto(jsonb)              from public, anon;
revoke all on function public.evt_registro_nao_muda()        from public, anon;

grant execute on function public.evento_publico(text)          to anon, authenticated;
grant execute on function public.evento_inscrever(text, jsonb) to anon, authenticated;

grant execute on function public.evt_so_digitos(text)          to authenticated;
grant execute on function public.evt_zap(text)                 to authenticated;
grant execute on function public.evt_chave(text)               to authenticated;
grant execute on function public.evt_funcao_atende(text)       to authenticated;
grant execute on function public.evt_nome_curto(text, boolean) to authenticated;
grant execute on function public.evt_aberto(jsonb)             to authenticated;
grant execute on function public.evt_eh_cliente(text,text,text) to authenticated;

-- a conferência do endereço: quem chama recebe só o endereço de quem chamou,
-- e nada mais. Fica aberta para a página pública PARA PODERMOS TESTAR logo
-- depois de aplicar (pedido dele). Para fechar depois do teste, basta:
--   revoke execute on function public.evt_qual_ip() from anon;
grant execute on function public.evt_qual_ip()                 to anon, authenticated;


-- ---------------------------------------------------------------------
-- 10. CONFERÊNCIAS DEPOIS DE RODAR
-- ---------------------------------------------------------------------
-- a) o papel sem login tem de ter EXATAMENTE estas três a mais: as duas
--    portas e a conferência do endereço (evt_qual_ip, que só devolve o
--    endereço de quem chama e pode ser fechada depois do teste).
--    Esta consulta tem de voltar só evento_inscrever, evento_publico e
--    evt_qual_ip:
select p.proname, pg_get_function_identity_arguments(p.oid) as argumentos
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and has_function_privilege('anon', p.oid, 'execute')
   and p.proname not in (select proname from backup.anon_funcoes_20261127)
 order by 1;

-- b) a tabela docs NÃO pode ter regra nenhuma para quem não tem login
--    (esta consulta tem de voltar VAZIA):
select policyname, roles, cmd
  from pg_policies
 where schemaname = 'public' and tablename = 'docs'
   and ('anon' = any(roles) or 'public' = any(roles));

-- c) a porta pública de um formulário que não existe responde "não existe":
select public.evento_publico('nao-existe-isto');

-- d) os três índices novos têm de aparecer:
select indexname from pg_indexes
 where schemaname = 'public' and tablename = 'docs'
   and indexname in ('docs_evtinscr_um_zap_por_form','docs_evtinscr_um_cpf_por_form','docs_evtsorteio_um_por_form')
 order by 1;

-- e) o WhatsApp com e sem o 55 é a mesma chave (as duas colunas têm de vir iguais):
select public.evt_zap('+55 (37) 98888-0001') as com_55, public.evt_zap('37988880001') as sem_55;

-- f) quem atende: TODAS as funções entram (regra dele de 27/11) — esta
--    consulta tem de dar true em todas as linhas, inclusive sem função
-- select 'f) '||coalesce(f,'(sem funcao)') as funcao,
--        public.evt_funcao_atende(f) as entra
--   from (values ('Vendedor'),('Consultor'),('Gerente'),('Administrador'),
--                ('Financeiro'),('Almoxarifado'),('Instalador'),('Prestador'),
--                ('Marketing'),(''),(null)) as t(f);
--
--    E o que separa de verdade quem entra: ativo e a empresa do
--    formulario. Esta consulta tem de trazer a equipe ATIVA da loja, com
--    inativo nenhum:
-- select p.nome, p.funcao, p.ativo, p.loja, p.ambas
--   from public.perfis p
--  where p.ativo and (p.loja = 'mf' or p.ambas)
--  order by p.nome;


-- g) O ENDEREÇO DE QUEM ENVIA (acerto 2 dele). No SQL Editor não chega
--    cabeçalho nenhum, então aqui a resposta certa é "nao aplica" — é só
--    para ver que a função responde. O teste de verdade é pelo celular,
--    com a chave publicável:
--      curl -s -X POST "https://clnccthtvfuetmfwuanu.supabase.co/rest/v1/rpc/evt_qual_ip" \
--        -H "apikey: <chave publicável>" -H "Content-Type: application/json" -d '{}'
--    Pela internet tem de vir de = cf-connecting-ip (ou x-real-ip),
--    interno = false e limite = aplica.
-- select public.evt_qual_ip();
--
--    E as faixas internas, que NÃO aplicam o limite (tudo true):
-- select public.evt_ip_interno('10.1.2.3')      as dez,
--        public.evt_ip_interno('172.20.0.9')     as cento_setenta_e_dois,
--        public.evt_ip_interno('192.168.0.5')    as cento_noventa_e_dois,
--        public.evt_ip_interno('127.0.0.1')      as local,
--        public.evt_ip_interno('::1')            as local6,
--        public.evt_ip_interno('fd00::1')        as fd,
--        public.evt_ip_interno('')               as vazio;
--    E um de verdade, que aplica (tem de vir false):
-- select public.evt_ip_interno('177.45.12.9')    as de_fora,
--        public.evt_ip_interno('172.15.0.1')     as fora_da_faixa;
--
-- h) "É CLIENTE" IGUAL AO ehLead (acerto 1 dele): quem tem a marca de
--    importado conta como cliente mesmo sem nenhuma venda. Troque o
--    WhatsApp por um da base para conferir:
-- select public.evt_eh_cliente('mf', public.evt_zap('(37) 99999-0000'), '') as eh_cliente;
--
--    E a conta geral: quantos cadastros da empresa são cliente por
--    importado e quantos por venda não cancelada.
-- select count(*) filter (where lower(coalesce(data->>'importado','')) in ('true','t','1')) as por_importado,
--        count(*) as cadastros
--   from public.docs where colecao = 'clientes' and loja = 'mf';
--
-- i) O LEAD DO SERVIDOR (item 10): depois da primeira inscrição pelo link,
--    o lead tem de aparecer com a origem = nome do formulário e o código
--    da numeração normal:
-- select c.data->>'codigo' as codigo, c.data->>'nome' as nome,
--        c.data->>'origem' as origem, c.data->>'criadoPor' as criado_por,
--        c.data->>'criadoVia' as criado_via, c.data->>'atendente' as atendente
--   from public.docs c
--  where c.colecao = 'clientes' and c.data->>'criadoVia' = 'evento'
--  order by c.criado_em desc limit 10;
--
--    e a inscrição tem de estar ligada a ele:
-- select i.data->>'nome' as inscrito, i.data->>'clienteId' as cliente,
--        i.data->>'ehNovo' as lead_novo, i.data->>'aConferir' as a_conferir
--   from public.docs i
--  where i.colecao = 'evtinscr' order by i.criado_em desc limit 10;
--
--    O contador do cliente é o MESMO do sistema (não pode ter pulado nem
--    repetido): o último código da tela tem de bater com este número + 1.
-- select loja, tipo, ultimo from public.numeradores where tipo = 'cliente';


-- =====================================================================
--  COMO VOLTAR ATRÁS  (rode só se precisar desfazer tudo isto)
-- =====================================================================
-- drop trigger if exists docs_evtsorteio_append_only on public.docs;
-- drop function if exists public.evt_registro_nao_muda();
-- drop index  if exists public.docs_evtsorteio_um_por_form;
-- drop index  if exists public.docs_evtinscr_um_zap_por_form;
-- drop index  if exists public.docs_evtinscr_um_cpf_por_form;
-- drop function if exists public.evento_inscrever(text, jsonb);
-- drop function if exists public.evento_publico(text);
-- drop function if exists public.evt_aberto(jsonb);
-- drop function if exists public.evt_qual_ip();
-- drop function if exists public.evt_eh_cliente(text,text,text);
-- drop function if exists public.evt_codigo_cliente(text);
-- drop function if exists public.evt_uid();
-- drop function if exists public.evt_base36(bigint);
-- drop function if exists public.evt_ip_interno(text);
-- drop function if exists public.evt_ip();
-- drop function if exists public.evt_nome_curto(text, boolean);
-- drop function if exists public.evt_funcao_atende(text);
-- drop function if exists public.evt_chave(text);
-- drop function if exists public.evt_zap(text);
-- drop function if exists public.evt_so_digitos(text);
-- -- as inscrições, os formulários e os LEADS já gravados ficam em
-- -- public.docs: nada é apagado por este arquivo nem pelo desfazer.
-- -- Desfeito o arquivo, o lead volta a nascer no sistema, quando alguém
-- -- com a marca Marketing entra ou abre a tela Formulários de evento.

-- =====================================================================
--  OS CAMPOS DO LEAD: O DO SERVIDOR × O DO ATENDIMENTO (pedido dele)
-- =====================================================================
--  Lead do Atendimento (sistema-minas.html, salvarAtend)  ->  o deste arquivo
--  ---------------------------------------------------------------------
--  id                 uid()                     ->  evt_uid() (mesmo formato)
--  loja               lojaAtual                 ->  a loja do formulário
--  codigo             codigoClienteNovo()       ->  evt_codigo_cliente(loja), mesmo contador
--  tipo               Pessoa Física/Jurídica    ->  igual (Pessoa Física quando não vem)
--  nome               do atendimento            ->  do formulário, em maiúsculas
--  sexo               do atendimento            ->  do formulário (vazio se não pedir)
--  tel                o telefone                ->  o WhatsApp da inscrição
--  nasc               do atendimento            ->  do formulário (vazio se não pedir)
--  doc                CPF/CNPJ                  ->  igual
--  cidade, uf         do atendimento            ->  do formulário, em maiúsculas
--  origem             a escolhida na tela       ->  o NOME DO FORMULÁRIO
--  origemEm           iso(new Date()) (o dia)   ->  o dia, igual
--  cep, rua, num,     do atendimento            ->  do formulário, em maiúsculas
--  bairro, comp, ref                                (só o que o formulário pedir)
--  tipoend            urbano                    ->  urbano
--  geo, geoOrigem,    do atendimento            ->  vazios: a página pública não
--  geoNivel, geoFonte                               acha endereço no mapa
--  indicado           do atendimento            ->  vazio
--  tipoPrimeiroAtend  o 1º tipo do atendimento  ->  vazio: não houve atendimento
--  primeiroAtendEm    iso(new Date())           ->  vazio, pelo mesmo motivo
--  criadoEm           iso(new Date()) (o dia)   ->  o dia, igual
--  criadoPor          usuarioAtual              ->  'Formulário de evento'
--  criadoVia          'atendimento'             ->  'evento'
--  ---------------------------------------------------------------------
--  E o que só existe neste caminho (igual ao que o sistema já gravava
--  quando era ele que criava o lead do evento):
--    eventoId   de qual formulário veio
--    atendente  quem a pessoa disse que a atendeu (o cadastro de cliente
--               não tem campo de vendedor; fica aqui e na nota)
--    email      em minúsculas, como no resto do sistema
--    tel2, tel3, tel4   vazios
--    notas      uma linha: "Inscrito no evento X em <data> · atendente: Y"
--  ---------------------------------------------------------------------
--  O que o servidor NÃO faz, de propósito:
--    * não acha a cidade oficial com acento (cidadeOficialDe mora no
--      sistema, com a lista dos 5.571 municípios): a cidade entra em
--      maiúsculas como a pessoa escreveu, e a tela corrige na primeira
--      vez que alguém salvar a ficha;
--    * não encosta em cadastro que já existe;
--    * não escolhe entre dois cadastros parecidos: marca "a conferir".
