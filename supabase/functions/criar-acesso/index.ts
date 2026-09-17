// Edge Function "criar-acesso" — Sistema Minas Filtros (v138, 17/09)
//
// PARA QUE SERVE
//   O Administrador cadastra o colaborador e a SENHA de acesso pela própria tela
//   Configurações › Usuários, sem abrir o painel do Supabase e sem SQL.
//   Criar usuário exige a chave service_role, que NÃO pode ficar no HTML (o
//   navegador de qualquer um baixaria). Aqui ela fica no servidor do Supabase,
//   na variável de ambiente que o próprio projeto já injeta.
//
// COMO PUBLICAR (painel do Supabase, sem instalar nada)
//   Edge Functions › Deploy a new function › Via Editor
//   Nome: criar-acesso        (exatamente assim)
//   Cole este arquivo inteiro e clique em Deploy.
//   Em "Function Configuration", deixe "Verify JWT" LIGADO ou desligado: a
//   função confere o usuário por conta própria.
//
// O QUE ELA FAZ
//   1. lê o token de quem chamou (o login do sistema) e descobre o user_id;
//   2. confere em public.perfis se esse usuário é Administrador e está ativo;
//   3. cria o usuário no Auth com a senha informada (e-mail já confirmado) ou,
//      se o e-mail já existir, troca a senha dele;
//   4. grava/atualiza a linha de public.perfis (nome, função, loja, jornada).
//
// SEGURANÇA
//   - Só Administrador ativo passa. Qualquer outro recebe 403.
//   - A senha vai do navegador para cá por HTTPS e não é gravada em log.
//   - Nada de service_role no site: ela só existe dentro desta função.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.116.0";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function resposta(corpo: unknown, status = 200) {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return resposta({ erro: "Use POST." }, 405);

  const URL_PROJ = Deno.env.get("SUPABASE_URL")!;
  const CHAVE_ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
  const CHAVE_ADMIN = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  if (!URL_PROJ || !CHAVE_ADMIN) return resposta({ erro: "Função sem as variáveis do projeto." }, 500);

  // ---- quem está chamando? ----
  const autorizacao = req.headers.get("Authorization") || "";
  if (!autorizacao.startsWith("Bearer ")) return resposta({ erro: "Entre no sistema de novo: sessão não enviada." }, 401);

  const comoUsuario = createClient(URL_PROJ, CHAVE_ANON, {
    global: { headers: { Authorization: autorizacao } },
  });
  const { data: dadosUsuario, error: erroUsuario } = await comoUsuario.auth.getUser();
  if (erroUsuario || !dadosUsuario?.user) return resposta({ erro: "Sessão inválida ou expirada." }, 401);

  const admin = createClient(URL_PROJ, CHAVE_ADMIN, { auth: { persistSession: false } });

  const { data: perfilQuemChama } = await admin
    .from("perfis")
    .select("nome, funcao, ativo")
    .eq("user_id", dadosUsuario.user.id)
    .maybeSingle();

  if (!perfilQuemChama || perfilQuemChama.ativo === false || perfilQuemChama.funcao !== "Administrador") {
    return resposta({ erro: "Só o Administrador cadastra acesso de colaborador." }, 403);
  }

  // ---- o que foi pedido ----
  let corpo: Record<string, unknown> = {};
  try { corpo = await req.json(); } catch { return resposta({ erro: "Envio inválido." }, 400); }

  const email = String(corpo.email || "").trim().toLowerCase();
  const senha = String(corpo.senha || "");
  const nome = String(corpo.nome || "").trim();
  const funcao = String(corpo.funcao || "").trim();
  const loja = String(corpo.loja || "").trim();
  const jornada = (corpo.jornada && typeof corpo.jornada === "object") ? corpo.jornada : {};

  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return resposta({ erro: "E-mail inválido." }, 400);
  if (senha.length < 8) return resposta({ erro: "A senha precisa de pelo menos 8 caracteres." }, 400);
  if (!nome) return resposta({ erro: "Informe o nome do colaborador." }, 400);
  if (!funcao) return resposta({ erro: "Informe a função." }, 400);
  if (!["mf", "wf", "dv"].includes(loja)) return resposta({ erro: "Loja inválida (use mf, wf ou dv)." }, 400);

  // ---- o e-mail já existe? ----
  let idUsuario = "";
  let criado = false;
  const { data: lista } = await admin.auth.admin.listUsers({ page: 1, perPage: 200 });
  const achado = (lista?.users || []).find((u) => String(u.email || "").toLowerCase() === email);

  if (achado) {
    idUsuario = achado.id;
    const { error } = await admin.auth.admin.updateUserById(idUsuario, { password: senha, email_confirm: true });
    if (error) return resposta({ erro: "Não consegui trocar a senha: " + error.message }, 400);
  } else {
    const { data, error } = await admin.auth.admin.createUser({
      email,
      password: senha,
      email_confirm: true,
      user_metadata: { nome },
    });
    if (error || !data?.user) return resposta({ erro: "Não consegui criar o acesso: " + (error?.message || "erro") }, 400);
    idUsuario = data.user.id;
    criado = true;
  }

  // ---- perfil (quem a pessoa é no sistema) ----
  const linha: Record<string, unknown> = { user_id: idUsuario, nome, funcao, loja, ativo: true };
  if (Object.keys(jornada).length) linha.jornada = jornada;
  const { error: erroPerfil } = await admin.from("perfis").upsert(linha, { onConflict: "user_id" });
  if (erroPerfil) {
    const repetido = /duplicate key|ux_perfis_nome/i.test(erroPerfil.message);
    return resposta({
      erro: repetido
        ? 'Já existe outro colaborador com o nome "' + nome + '". Use o mesmo nome do cadastro antigo ou mude o nome.'
        : "Acesso criado, mas o perfil não gravou: " + erroPerfil.message,
      user_id: idUsuario,
      criado,
    }, 400);
  }

  return resposta({ ok: true, criado, user_id: idUsuario, nome, funcao, loja });
});
