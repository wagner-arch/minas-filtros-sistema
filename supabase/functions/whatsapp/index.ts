// Edge Function "whatsapp" — Sistema Minas Filtros (06/11/2026)
//
// PARA QUE SERVE
//   É a ÚNICA peça que fala com o WhatsApp. Hoje o provedor é a Evolution API da Minas Filtros
//   (VPS, /opt/minasfiltros); para trocar pelo caminho oficial da Meta no futuro, troca-se só o
//   objeto PROVEDOR abaixo — as telas e os botões do sistema continuam iguais.
//
// QUEM CHAMA
//   - o sistema, com a sessão de quem está logado (Authorization: Bearer <token>);
//   - o banco, de 5 em 5 minutos (acao "faxina", cabeçalho x-segredo);
//   - a Evolution, quando uma conexão cai ou volta (aviso "connection.update", ?s=<segredo>).
//   Por isso "Verify JWT" fica DESLIGADO: a função confere o token por conta própria.
//
// REGRAS (aprovadas por ele em 06/11)
//   - só conecta quem o Administrador marcou na ficha (config/usuarios: zapConectar) e está ativo;
//     uma conexão por pessoa, presa à empresa em que conectou; ninguém envia pela conexão de outro;
//   - envia só para cliente com pedido, orçamento, atendimento/atividade ou OS nos últimos 30 dias
//     (na manutenção, também quem tem troca de refil vencida ou vencendo em 30 dias),
//     só celular válido com DDD e que tenha WhatsApp; 20 s entre envios e no máximo 30 por hora por
//     pessoa; nada de envio em massa (um cliente por chamada);
//   - tudo fica em whatsapp_envios (enviado, falhou ou aberto no celular);
//   - colaborador inativado ou sem a marca: a conexão é desligada sozinha (faxina).
//
// SEGREDOS (nenhum no repositório): endereço, chave da Evolution e o segredo da faxina ficam no
//   cofre do banco, lidos por public.whatsapp_config() (só o servidor executa).

import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const SUPA_URL = Deno.env.get("SUPABASE_URL")!;
const SUPA_SR = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const sb = createClient(SUPA_URL, SUPA_SR, { auth: { persistSession: false } });

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const TIPOS = ["pedido_pdf", "link_assinatura", "manutencao"];
const DIAS_TROCA = 30;   // manutenção: troca de refil vencida ou vencendo nos próximos 30 dias (Etapa 2, 09/11)
const INTERVALO_S = 20, POR_HORA = 30, DIAS_ATENDIMENTO = 30;
const DDDS = new Set(("11 12 13 14 15 16 17 18 19 21 22 24 27 28 31 32 33 34 35 37 38 41 42 43 44 45 46 47 48 49 51 53 54 55 " +
  "61 62 63 64 65 66 67 68 69 71 73 74 75 77 79 81 82 83 84 85 86 87 88 89 91 92 93 94 95 96 97 98 99").split(" "));

function resp(o: unknown, status = 200) {
  return new Response(JSON.stringify(o), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}
class Recusa extends Error {}

/* celular brasileiro com DDD: 55 + DDD + 9 + 8 dígitos (o mesmo teste do sistema) */
export function celularBR(t: string): string | null {
  let d = String(t || "").replace(/\D/g, "");
  if (d.length >= 12 && d.startsWith("55")) d = d.slice(2);
  if (d.length === 10 && /^[6-9]/.test(d.slice(2))) d = d.slice(0, 2) + "9" + d.slice(2);   /* celular antigo sem o 9 */
  if (d.length !== 11) return null;
  if (!DDDS.has(d.slice(0, 2)) || d[2] !== "9") return null;
  return "55" + d;
}

let CFG: { url: string; chave: string; segredo: string | null } | null = null;
async function cfg() {
  if (CFG) return CFG;
  const { data, error } = await sb.rpc("whatsapp_config");
  if (error || !data || !data.url || !data.chave) throw new Error("WhatsApp do sistema sem configuração no cofre.");
  CFG = { url: String(data.url).replace(/\/$/, ""), chave: data.chave, segredo: data.segredo || null };
  return CFG;
}

/* ===================== PROVEDOR (hoje: Evolution API v2) ===================== */
async function evo(metodo: string, caminho: string, corpo?: unknown) {
  const c = await cfg();
  const r = await fetch(c.url + caminho, {
    method: metodo,
    headers: { "Content-Type": "application/json", apikey: c.chave },
    body: corpo === undefined ? undefined : JSON.stringify(corpo),
    signal: AbortSignal.timeout(25000),
  });
  const txt = await r.text();
  let dados: any = {};
  try { dados = txt ? JSON.parse(txt) : {}; } catch { dados = { texto: txt }; }
  return { ok: r.ok, status: r.status, dados };
}
const PROVEDOR = {
  async existe(inst: string) {
    const r = await evo("GET", "/instance/fetchInstances?instanceName=" + encodeURIComponent(inst));
    const x = Array.isArray(r.dados) ? r.dados[0] : null;
    return x || null;
  },
  async estado(inst: string): Promise<{ situacao: string; numero: string | null }> {
    const x = await PROVEDOR.existe(inst);
    if (!x) return { situacao: "desconectado", numero: null };
    const st = String(x.connectionStatus || x.instance?.state || "").toLowerCase();
    const num = String(x.ownerJid || x.owner || "").split("@")[0].replace(/\D/g, "") || null;
    return { situacao: st === "open" ? "conectado" : st === "connecting" ? "aguardando" : "desconectado", numero: num };
  },
  async criar(inst: string) {
    const c = await cfg();
    const corpo: any = { instanceName: inst, qrcode: true, integration: "WHATSAPP-BAILEYS",
      rejectCall: false, groupsIgnore: true, alwaysOnline: false, readMessages: false, readStatus: false, syncFullHistory: false };
    if (c.segredo) corpo.webhook = { enabled: true, url: SUPA_URL + "/functions/v1/whatsapp?s=" + c.segredo,
      byEvents: false, base64: false, events: ["CONNECTION_UPDATE"] };
    const r = await evo("POST", "/instance/create", corpo);
    if (!r.ok) throw new Error("A Evolution não criou a conexão (" + r.status + ").");
    return r.dados;
  },
  async qr(inst: string): Promise<string | null> {
    const r = await evo("GET", "/instance/connect/" + encodeURIComponent(inst));
    return (r.dados && (r.dados.base64 || r.dados.qrcode?.base64)) || null;
  },
  async sair(inst: string) { await evo("DELETE", "/instance/logout/" + encodeURIComponent(inst)); },
  async temWhatsApp(inst: string, numero: string): Promise<boolean | null> {
    const r = await evo("POST", "/chat/whatsappNumbers/" + encodeURIComponent(inst), { numbers: [numero] });
    if (!r.ok || !Array.isArray(r.dados)) return null;           /* não deu para conferir: segue */
    return !!(r.dados[0] && r.dados[0].exists);
  },
  async enviarTexto(inst: string, numero: string, texto: string) {
    const r = await evo("POST", "/message/sendText/" + encodeURIComponent(inst), { number: numero, text: texto, delay: 1200 });
    if (!r.ok) throw new Error("O WhatsApp recusou o envio (" + r.status + ").");
    return r.dados?.key?.id || null;
  },
  async enviarPdf(inst: string, numero: string, base64: string, arquivo: string, legenda: string) {
    const r = await evo("POST", "/message/sendMedia/" + encodeURIComponent(inst), { number: numero, mediatype: "document",
      mimetype: "application/pdf", media: base64, fileName: arquivo, caption: legenda, delay: 1200 });
    if (!r.ok) throw new Error("O WhatsApp recusou o envio do PDF (" + r.status + ").");
    return r.dados?.key?.id || null;
  },
};

/* ===================== quem é quem ===================== */
async function fichaDe(nome: string) {
  const { data } = await sb.from("docs").select("data").eq("colecao", "config").eq("id", "usuarios").maybeSingle();
  const lista = (data?.data?.lista || []) as any[];
  return lista.find((u) => u && u.nome === nome) || null;
}
async function pessoa(req: Request) {
  const tok = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  if (!tok) throw new Recusa("Sessão expirada — entre no sistema de novo.");
  const { data, error } = await sb.auth.getUser(tok);
  if (error || !data?.user) throw new Recusa("Sessão expirada — entre no sistema de novo.");
  const { data: p } = await sb.from("perfis").select("user_id,nome,funcao,loja,ativo,ambas").eq("user_id", data.user.id).maybeSingle();
  if (!p || p.ativo === false) throw new Recusa("Usuário inativo.");
  const f = await fichaDe(p.nome);
  return { ...p, ficha: f, pode: !!(f && f.zapConectar === true && f.ativo !== false) };
}
function lojaPermitida(p: any, loja: string) { return !!loja && (p.ambas === true || p.loja === loja); }
function nomeInstancia(loja: string, uid: string) { return loja + "-" + uid.replace(/-/g, ""); }

async function atualizarConexao(uid: string, campos: Record<string, unknown>) {
  await sb.from("whatsapp_conexoes").update({ ...campos, atualizado_em: new Date().toISOString() }).eq("user_id", uid);
}
/* confere na Evolution e grava; caiu (estava conectado e não está mais) → aviso no sino */
async function sincronizar(c: any) {
  let e;
  try { e = await PROVEDOR.estado(c.instancia); } catch { return c; }
  const caiu = c.situacao === "conectado" && e.situacao !== "conectado";
  const campos: any = { situacao: e.situacao };
  if (e.numero) campos.numero = e.numero;
  if (e.situacao === "conectado" && c.situacao !== "conectado") { campos.conectado_em = new Date().toISOString(); campos.motivo = null; }
  if (caiu) { campos.desconectado_em = new Date().toISOString(); campos.aviso_visto = false; campos.motivo = "o WhatsApp desconectou"; }
  if (campos.situacao !== c.situacao || caiu || (e.numero && e.numero !== c.numero)) await atualizarConexao(c.user_id, campos);
  return { ...c, ...campos };
}
async function minhaConexao(uid: string) {
  const { data } = await sb.from("whatsapp_conexoes").select("*").eq("user_id", uid).maybeSingle();
  return data;
}
function publico(c: any) {
  if (!c) return null;
  return { loja: c.loja, situacao: c.situacao, numero: c.numero, conectado_em: c.conectado_em,
    desconectado_em: c.desconectado_em, motivo: c.motivo, aviso_visto: c.aviso_visto };
}
async function registrar(o: Record<string, unknown>) {
  const { error } = await sb.from("whatsapp_envios").insert(o);
  if (error) console.error("registrar envio", error.message);
}

/* ===================== ações ===================== */
async function emAtendimento(loja: string, clienteId: string) {
  if (!clienteId) return false;
  const desde = new Date(Date.now() - DIAS_ATENDIMENTO * 864e5).toISOString();
  const { count } = await sb.from("docs").select("id", { count: "exact", head: true })
    .eq("loja", loja).in("colecao", ["pedidos", "orcamentos", "atendimentos", "ordens"])
    .eq("data->>clienteId", clienteId).gte("atualizado_em", desde);
  return (count || 0) > 0;
}

/* Etapa 2 (09/11): na Manutenção periódica também pode receber quem tem aparelho com a troca de
   refil vencida ou vencendo nos próximos 30 dias. A conta é a mesma da tela, pelo cadastro do
   aparelho: base = a data mais nova entre compra, instalação e última manutenção; próxima troca =
   base + manutDias. (Uma venda aprovada depois disso só adiaria a troca; aqui ela não é olhada,
   então a conferência nunca recusa quem a tela mostra.) */
function somaDiasISO(iso: string, d: number) {
  const x = new Date(iso.slice(0, 10) + "T12:00:00Z"); x.setUTCDate(x.getUTCDate() + d); return x.toISOString().slice(0, 10);
}
export function trocaPertoDe(eqs: any[], hoje: string) {
  const ate = somaDiasISO(hoje, DIAS_TROCA);
  return eqs.some((e) => {
    if (!e || e.ativo === false) return false;
    if (e.naoNosso && !e.acompanhar) return false;
    const dias = +e.manutDias || 0;
    if (!dias) return false;
    const base = [e.compradoEm, e.instaladoEm, e.ultimaManut].map((v) => String(v || "").slice(0, 10)).filter(Boolean).sort().pop();
    if (!base) return false;
    return somaDiasISO(base, dias) <= ate;
  });
}
async function trocaPerto(loja: string, clienteId: string) {
  if (!clienteId) return false;
  const { data } = await sb.from("docs").select("data").eq("loja", loja).eq("colecao", "equipamentos")
    .eq("data->>clienteId", clienteId).limit(200);
  const hoje = new Date(Date.now() - 3 * 3600e3).toISOString().slice(0, 10);   // dia em Brasília
  return trocaPertoDe((data || []).map((x: any) => x.data), hoje);
}

async function enviar(p: any, b: any) {
  const loja = String(b.loja || "");
  const base = { loja, user_id: p.user_id, nome: p.nome, cliente_id: b.clienteId || null, cliente_nome: b.clienteNome || null,
    telefone: String(b.telefone || ""), tipo: String(b.tipo || ""), ref_id: b.refId || null, ref_numero: b.refNumero ? String(b.refNumero) : null };
  if (!TIPOS.includes(base.tipo)) throw new Recusa("Este envio ainda não sai pelo WhatsApp do sistema.");
  if (!p.pode) throw new Recusa("Você não tem o WhatsApp do sistema liberado.");
  if (!lojaPermitida(p, loja)) throw new Recusa("Empresa errada para este usuário.");
  let c = await minhaConexao(p.user_id);
  if (!c) throw new Recusa("Seu WhatsApp não está conectado ao sistema.");
  if (c.loja !== loja) throw new Recusa("Seu WhatsApp está conectado na outra empresa.");
  c = await sincronizar(c);
  if (c.situacao !== "conectado") throw new Recusa("Seu WhatsApp está desconectado.");
  const numero = celularBR(base.telefone);
  if (!numero) throw new Recusa("O telefone do cliente não é um celular válido com DDD.");
  if (!(await emAtendimento(loja, base.cliente_id || ""))) {
    if (base.tipo !== "manutencao") throw new Recusa("O cliente não está em atendimento (sem pedido, orçamento ou atendimento nos últimos 30 dias).");
    if (!(await trocaPerto(loja, base.cliente_id || ""))) throw new Recusa("O cliente não está em atendimento e não tem troca de refil vencida nem vencendo nos próximos 30 dias.");
  }
  const agora = Date.now();
  const { data: ult } = await sb.from("whatsapp_envios").select("criado_em").eq("user_id", p.user_id).eq("situacao", "enviado")
    .order("criado_em", { ascending: false }).limit(1);
  if (ult && ult[0]) {
    const s = Math.ceil(INTERVALO_S - (agora - Date.parse(ult[0].criado_em)) / 1000);
    if (s > 0) throw new Recusa("Espere " + s + " segundos entre um envio e outro.");
  }
  const { count } = await sb.from("whatsapp_envios").select("id", { count: "exact", head: true }).eq("user_id", p.user_id)
    .eq("situacao", "enviado").gte("criado_em", new Date(agora - 3600e3).toISOString());
  if ((count || 0) >= POR_HORA) throw new Recusa("Limite de " + POR_HORA + " envios por hora atingido.");
  const tem = await PROVEDOR.temWhatsApp(c.instancia, numero);
  if (tem === false) throw new Recusa("Este número não tem WhatsApp.");
  try {
    const id = b.pdf
      ? await PROVEDOR.enviarPdf(c.instancia, numero, String(b.pdf), String(b.arquivo || "documento.pdf"), String(b.texto || ""))
      : await PROVEDOR.enviarTexto(c.instancia, numero, String(b.texto || ""));
    await registrar({ ...base, telefone: numero, situacao: "enviado", mensagem_id: id });
    return { ok: true, numero };
  } catch (e) {
    await registrar({ ...base, telefone: numero, situacao: "falhou", motivo: String((e as Error).message || e) });
    throw new Recusa(String((e as Error).message || e));
  }
}

async function faxina() {
  const { data: L } = await sb.from("whatsapp_conexoes").select("*");
  const { data: cfgU } = await sb.from("docs").select("data").eq("colecao", "config").eq("id", "usuarios").maybeSingle();
  const fichas = (cfgU?.data?.lista || []) as any[];
  let desligadas = 0, conferidas = 0;
  for (const c of L || []) {
    const { data: p } = await sb.from("perfis").select("nome,ativo").eq("user_id", c.user_id).maybeSingle();
    const f = p ? fichas.find((u) => u && u.nome === p.nome) : null;
    const pode = !!(p && p.ativo !== false && f && f.ativo !== false && f.zapConectar === true);
    if (!pode) {
      if (c.situacao !== "desconectado" || c.motivo !== "colaborador inativo ou sem permissão") {
        try { await PROVEDOR.sair(c.instancia); } catch { /* segue */ }
        await atualizarConexao(c.user_id, { situacao: "desconectado", desconectado_em: new Date().toISOString(),
          motivo: "colaborador inativo ou sem permissão", aviso_visto: true });
        desligadas++;
      }
      continue;
    }
    await sincronizar(c); conferidas++;
  }
  return { ok: true, conferidas, desligadas };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const url = new URL(req.url);
    const b = await req.json().catch(() => ({}));
    /* aviso da Evolution (conexão caiu ou voltou) */
    if (url.searchParams.get("s")) {
      const c = await cfg();
      if (!c.segredo || url.searchParams.get("s") !== c.segredo) return resp({ erro: "recusado" }, 403);
      const inst = String(b.instance || b.instanceName || "");
      const { data: con } = await sb.from("whatsapp_conexoes").select("*").eq("instancia", inst).maybeSingle();
      if (con) await sincronizar(con);
      return resp({ ok: true });
    }
    /* faxina do banco */
    if (b.acao === "faxina") {
      const c = await cfg();
      if (!c.segredo || req.headers.get("x-segredo") !== c.segredo) return resp({ erro: "recusado" }, 403);
      return resp(await faxina());
    }
    const p = await pessoa(req);
    const loja = String(b.loja || "");
    switch (b.acao) {
      case "estado": {
        let c = await minhaConexao(p.user_id);
        if (c) c = await sincronizar(c);
        return resp({ ok: true, pode: p.pode, conexao: publico(c) });
      }
      case "conectar": {
        if (!p.pode) throw new Recusa("Você não tem o WhatsApp do sistema liberado. Peça ao Administrador.");
        if (!lojaPermitida(p, loja)) throw new Recusa("Empresa errada para este usuário.");
        let c = await minhaConexao(p.user_id);
        if (c && c.loja !== loja) {
          c = await sincronizar(c);
          if (c.situacao === "conectado") throw new Recusa("Seu WhatsApp está conectado na outra empresa. Desconecte lá primeiro.");
          await sb.from("whatsapp_conexoes").update({ loja }).eq("user_id", p.user_id);
        }
        const inst = c ? c.instancia : nomeInstancia(loja, p.user_id);
        if (!c) {
          await sb.from("whatsapp_conexoes").insert({ user_id: p.user_id, loja, nome: p.nome, instancia: inst, situacao: "aguardando" });
          c = await minhaConexao(p.user_id);
        }
        if (!(await PROVEDOR.existe(inst))) await PROVEDOR.criar(inst);
        const e = await PROVEDOR.estado(inst);
        if (e.situacao === "conectado") { c = await sincronizar(c); return resp({ ok: true, conexao: publico(c) }); }
        const qr = await PROVEDOR.qr(inst);
        await atualizarConexao(p.user_id, { situacao: "aguardando", nome: p.nome, aviso_visto: true });
        return resp({ ok: true, qr, conexao: publico({ ...c, situacao: "aguardando" }) });
      }
      case "desconectar": {
        const c = await minhaConexao(p.user_id);
        if (c) {
          try { await PROVEDOR.sair(c.instancia); } catch { /* segue */ }
          await atualizarConexao(p.user_id, { situacao: "desconectado", desconectado_em: new Date().toISOString(),
            motivo: "desconectado por você", aviso_visto: true });
        }
        return resp({ ok: true });
      }
      case "visto": {
        await atualizarConexao(p.user_id, { aviso_visto: true });
        return resp({ ok: true });
      }
      case "enviar":
        return resp(await enviar(p, b));
      case "registrar": {
        /* não deu pelo WhatsApp conectado e abriu o do celular: fica anotado */
        if (!TIPOS.includes(String(b.tipo)) || !lojaPermitida(p, loja)) throw new Recusa("Registro inválido.");
        await registrar({ loja, user_id: p.user_id, nome: p.nome, cliente_id: b.clienteId || null, cliente_nome: b.clienteNome || null,
          telefone: String(b.telefone || ""), tipo: String(b.tipo), ref_id: b.refId || null, ref_numero: b.refNumero ? String(b.refNumero) : null,
          situacao: "celular", motivo: b.motivo ? String(b.motivo).slice(0, 300) : null });
        return resp({ ok: true });
      }
      case "lista": {
        if (p.funcao !== "Administrador" || !lojaPermitida(p, loja)) throw new Recusa("Só o Administrador vê as conexões.");
        const { data: L } = await sb.from("whatsapp_conexoes").select("*").eq("loja", loja);
        const out = [];
        for (const c of L || []) out.push(await sincronizar(c));
        const { data: cfgU } = await sb.from("docs").select("data").eq("colecao", "config").eq("id", "usuarios").maybeSingle();
        const marcados = ((cfgU?.data?.lista || []) as any[]).filter((u) => u && u.zapConectar === true && u.ativo !== false && (u.loja || "mf") === loja)
          .map((u) => u.nome);
        return resp({ ok: true, conexoes: out.map((c) => ({ nome: c.nome, ...publico(c) })), marcados });
      }
      case "desligar": {
        if (p.funcao !== "Administrador" || !lojaPermitida(p, loja)) throw new Recusa("Só o Administrador desliga a conexão de outra pessoa.");
        const { data: c } = await sb.from("whatsapp_conexoes").select("*").eq("loja", loja).eq("nome", String(b.nome || "")).maybeSingle();
        if (c) {
          try { await PROVEDOR.sair(c.instancia); } catch { /* segue */ }
          await atualizarConexao(c.user_id, { situacao: "desconectado", desconectado_em: new Date().toISOString(),
            motivo: "desligado pelo Administrador", aviso_visto: true });
        }
        return resp({ ok: true });
      }
    }
    throw new Recusa("Pedido desconhecido.");
  } catch (e) {
    if (e instanceof Recusa) return resp({ ok: false, motivo: e.message });
    console.error("whatsapp", e);
    return resp({ ok: false, motivo: "O WhatsApp do sistema não respondeu: " + String((e as Error).message || e) });
  }
});
