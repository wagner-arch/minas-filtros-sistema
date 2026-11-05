// Edge Function "lembrete-ponto" — Sistema Minas Filtros (05/11/2026)
//
// PARA QUE SERVE
//   O banco confere de minuto em minuto quem precisa de aviso para bater o ponto
//   (public.disparar_lembretes_ponto, ver supabase/lembrete-ponto.sql) e, só quando há
//   alguém, chama esta função com a lista. Ela manda a notificação:
//     - ao aplicativo Android, pelo Firebase (mensagem de dados de prioridade alta: é o
//       próprio aplicativo que monta o aviso, com o som próprio, a vibração e a tela de bloqueio);
//     - ao iPhone (sistema na Tela de Início) e aos navegadores, pelo Web Push.
//
// QUEM PODE CHAMAR: só o banco. Ele manda o segredo guardado no cofre (vault) no cabeçalho
//   x-segredo, e a função confere com public.lembrete_ponto_confere. Por isso "Verify JWT" fica
//   DESLIGADO nesta função.
//
// SEGREDOS (nenhum no repositório):
//   FCM_CONTA     o arquivo JSON da "conta de serviço" do Firebase, inteiro (segredo da função,
//                 colocado pelo Wagner no painel: Edge Functions › Secrets)
//   web_push_publica / web_push_privada   no cofre do banco (vault), lidos por RPC
//
// Vários horários do mesmo colaborador no mesmo minuto viram UM aviso só.

import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import webpush from "npm:web-push@3.6.7";

const SUPA_URL = Deno.env.get("SUPABASE_URL")!;
const SUPA_SR = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const sb = createClient(SUPA_URL, SUPA_SR, { auth: { persistSession: false } });

type Aviso = { id: number; loja: string; nome: string; marc: string; tipo: string; titulo: string; texto: string };

const NOMES: Record<string, string> = {
  checkin: "entrada", almocoIni: "saída do almoço", almocoFim: "volta do almoço", checkout: "saída",
};

/* junta os avisos do mesmo colaborador no mesmo minuto */
function juntar(avisos: Aviso[]) {
  const g = new Map<string, Aviso[]>();
  for (const a of avisos) {
    const k = a.nome;
    if (!g.has(k)) g.set(k, []);
    g.get(k)!.push(a);
  }
  const saida: { nome: string; ids: number[]; titulo: string; texto: string; marcs: string[] }[] = [];
  for (const [nome, L] of g) {
    let texto = L[0].texto;
    if (L.length > 1) {
      const atr = L.filter((x) => x.tipo === "atraso"), ant = L.filter((x) => x.tipo === "antes");
      const partes: string[] = [];
      if (atr.length) {
        const hora = (atr[0].texto.match(/Já são ([0-9]{2}:[0-9]{2})/) || [])[1] || "";
        const ns = atr.map((x) => NOMES[x.marc] || x.marc);
        const lista = ns.length > 1 ? ns.slice(0, -1).join(", ") + " e " + ns[ns.length - 1] : ns[0];
        partes.push(`Já são ${hora} e você ainda não bateu o ponto de ${lista}.`);
      }
      for (const x of ant) partes.push(x.texto);
      texto = partes.join(" ");
    }
    saida.push({ nome, ids: L.map((x) => x.id), titulo: "Lembrete de ponto", texto, marcs: L.map((x) => x.marc) });
  }
  return saida;
}

/* ---------- Firebase (FCM v1): a chave de acesso vale 1 hora ---------- */
let fcmToken = "", fcmVence = 0, fcmProjeto = "";
function b64url(b: ArrayBuffer | Uint8Array | string) {
  const bytes = typeof b === "string" ? new TextEncoder().encode(b) : new Uint8Array(b as ArrayBuffer);
  let s = "";
  for (const x of bytes) s += String.fromCharCode(x);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
async function acessoFirebase(): Promise<string> {
  if (fcmToken && Date.now() < fcmVence - 60000) return fcmToken;
  const txt = Deno.env.get("FCM_CONTA");
  if (!txt) throw new Error("falta o segredo FCM_CONTA");
  const conta = JSON.parse(txt);
  fcmProjeto = conta.project_id;
  const agora = Math.floor(Date.now() / 1000);
  const cab = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const corpo = b64url(JSON.stringify({
    iss: conta.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token", iat: agora, exp: agora + 3600,
  }));
  const pem = String(conta.private_key).replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const chave = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const ass = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", chave, new TextEncoder().encode(cab + "." + corpo));
  const jwt = cab + "." + corpo + "." + b64url(ass);
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=" + jwt,
  });
  const j = await r.json();
  if (!j.access_token) throw new Error("Firebase recusou o acesso: " + JSON.stringify(j).slice(0, 200));
  fcmToken = j.access_token; fcmVence = Date.now() + (j.expires_in || 3600) * 1000;
  return fcmToken;
}
async function mandarAndroid(token: string, titulo: string, texto: string, marcs: string[]) {
  const ac = await acessoFirebase();
  const r = await fetch(`https://fcm.googleapis.com/v1/projects/${fcmProjeto}/messages:send`, {
    method: "POST",
    headers: { "Authorization": "Bearer " + ac, "Content-Type": "application/json" },
    body: JSON.stringify({ message: {
      token,
      /* mensagem de DADOS: o aplicativo monta o aviso com o som próprio. ttl curto: um
         lembrete que chega atrasado mais de 2 minutos já foi trocado pelo seguinte */
      data: { tipo: "lembrete_ponto", titulo, texto, marcs: marcs.join(",") },
      android: { priority: "HIGH", ttl: "110s" },
    } }),
  });
  if (r.ok) return "ok";
  const t = await r.text();
  if (r.status === 404 || /UNREGISTERED|INVALID_ARGUMENT/.test(t)) return "invalido";
  return "erro " + r.status + " " + t.slice(0, 120);
}

/* ---------- Web Push (iPhone na Tela de Início e navegadores) ---------- */
let vapidPronto = false;
async function prepararWeb() {
  if (vapidPronto) return true;
  const { data } = await sb.rpc("lembrete_ponto_chaves_web");
  if (!data || !data.publica || !data.privada) return false;
  webpush.setVapidDetails("mailto:avisos@minasfiltros.invalid", data.publica, data.privada);
  vapidPronto = true;
  return true;
}
async function mandarWeb(assinatura: unknown, titulo: string, texto: string) {
  if (!(await prepararWeb())) return "sem chaves do Web Push";
  try {
    await webpush.sendNotification(assinatura as webpush.PushSubscription,
      JSON.stringify({ tipo: "lembrete_ponto", titulo, texto }), { TTL: 110, urgency: "high" });
    return "ok";
  } catch (e) {
    const st = (e as { statusCode?: number }).statusCode;
    if (st === 404 || st === 410) return "invalido";
    return "erro " + (st || "") + " " + String((e as Error).message || e).slice(0, 120);
  }
}

Deno.serve(async (req) => {
  try {
    const seg = req.headers.get("x-segredo") || "";
    const { data: ok } = await sb.rpc("lembrete_ponto_confere", { p_segredo: seg });
    if (!ok) return new Response("recusado", { status: 401 });
    const corpo = await req.json();
    const avisos: Aviso[] = Array.isArray(corpo?.avisos) ? corpo.avisos : [];
    if (!avisos.length) return new Response("nada", { status: 200 });

    const grupos = juntar(avisos);
    const nomes = grupos.map((g) => g.nome);
    const { data: aps } = await sb.from("dispositivos_ponto")
      .select("user_id,aparelho,nome,tipo,token,assinatura,permissao,ativo")
      .in("nome", nomes).eq("ativo", true).eq("permissao", "autorizado");

    for (const g of grupos) {
      const meus = (aps || []).filter((a) => a.nome === g.nome);
      let enviados = 0;
      const res: string[] = [];
      for (const a of meus) {
        let r = "";
        try {
          if (a.tipo === "android" && a.token) r = await mandarAndroid(a.token, g.titulo, g.texto, g.marcs);
          else if (a.tipo === "web" && a.assinatura) r = await mandarWeb(a.assinatura, g.titulo, g.texto);
          else r = "sem endereço";
        } catch (e) { r = "erro " + String((e as Error).message || e).slice(0, 120); }
        if (r === "ok") enviados++;
        if (r === "invalido") {
          /* o endereço morreu (aplicativo desinstalado ou permissão tirada): para de mandar */
          await sb.from("dispositivos_ponto").update({ ativo: false })
            .eq("user_id", a.user_id).eq("aparelho", a.aparelho);
        }
        res.push(a.tipo + ":" + r);
      }
      await sb.from("lembretes_ponto_log")
        .update({ enviados, resultado: meus.length ? res.join(" | ").slice(0, 500) : "sem celular autorizado" })
        .in("id", g.ids);
    }
    return new Response("ok", { status: 200 });
  } catch (e) {
    return new Response("erro: " + String((e as Error).message || e), { status: 500 });
  }
});
