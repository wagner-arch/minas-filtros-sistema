/* O AJUDANTE DO SISTEMA NO APARELHO (sw-ponto.js)
   1) LEMBRETE DE PONTO (05/11/2026) — recebe o aviso do servidor no iPhone (sistema aberto pela Tela
      de Início) e nos navegadores de celular, mesmo com o sistema fechado, e mostra a notificação.
      Tocar no aviso abre o sistema no Cartão de Ponto.
   2) ABRIR SEM INTERNET (05/11/2026, Etapa 1) — guarda os ARQUIVOS do sistema (a página, o adaptador,
      a biblioteca do banco, as fontes e os ícones) para abrir sem sinal. Com internet vale SEMPRE o
      que vem do servidor (a versão obrigatória continua igual); só sem resposta do servidor é que
      entra a cópia guardada. Os DADOS não passam por aqui: ficam no cofre do próprio sistema.
      Nada do banco (supabase.co) é guardado aqui. */
var GUARDA = "mf-sistema-1";
var ARQUIVOS = ["index.html", "sistema-minas.html", "supabase/adapter.js", "manifest.webmanifest", "icone-192.png",
  "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.116.0/dist/umd/supabase.js",
  "https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js"];

/* o endereço com que cada arquivo fica guardado: a página e o adaptador SEM o "?v=", para que
   qualquer versão pedida sem internet ache a última guardada */
function chaveDe(url) {
  var u = new URL(url);
  if (u.origin === self.location.origin) {
    var p = u.pathname;
    if (/\/$/.test(p)) p += "index.html";
    return u.origin + p;
  }
  return url;
}
function ehNosso(u) {
  return u.origin === self.location.origin &&
    /(\/|index\.html|sistema-minas\.html|adapter\.js|manifest\.webmanifest|icone-[0-9]+\.png)$/.test(u.pathname);
}
function ehBiblioteca(u) {
  return /^(cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com|fonts\.googleapis\.com|fonts\.gstatic\.com)$/.test(u.hostname);
}

self.addEventListener("install", function (e) {
  /* já guarda os arquivos na instalação: sem isto, só a SEGUNDA abertura com internet deixaria tudo guardado */
  e.waitUntil(caches.open(GUARDA).then(function (c) {
    return Promise.all(ARQUIVOS.map(function (a) {
      var url = new URL(a, self.registration.scope).href;
      return fetch(url, { cache: "no-store" }).then(function (r) {
        if (r && (r.ok || r.type === "opaque")) return c.put(chaveDe(url), r);
      }).catch(function () {});
    }));
  }).catch(function () {}).then(function () { return self.skipWaiting(); }));
});
self.addEventListener("activate", function (e) {
  e.waitUntil(caches.keys().then(function (ks) {
    return Promise.all(ks.filter(function (k) { return /^mf-sistema-/.test(k) && k !== GUARDA; })
      .map(function (k) { return caches.delete(k); }));
  }).then(function () { return self.clients.claim(); }));
});

self.addEventListener("fetch", function (e) {
  var r = e.request;
  if (r.method !== "GET") return;
  var u;
  try { u = new URL(r.url); } catch (x) { return; }
  if (!ehNosso(u) && !ehBiblioteca(u)) return;          /* o resto (inclusive o banco) segue normal */
  var chave = ehNosso(u) ? chaveDe(r.url) : r.url;
  e.respondWith(fetch(r).then(function (resp) {
    if (resp && (resp.ok || resp.type === "opaque")) {
      var copia = resp.clone();
      caches.open(GUARDA).then(function (c) { c.put(chave, copia); }).catch(function () {});
    }
    return resp;
  }).catch(function () {
    return caches.match(chave).then(function (m) { return m || Response.error(); });
  }));
});

self.addEventListener("push", function (e) {
  var d = {};
  try { d = e.data ? e.data.json() : {}; } catch (x) { d = { texto: e.data ? e.data.text() : "" }; }
  var titulo = d.titulo || "Lembrete de ponto";
  var texto = d.texto || "Não esqueça de bater o ponto.";
  e.waitUntil(self.registration.showNotification(titulo, {
    body: texto,
    tag: "lembrete-ponto",          /* o aviso novo toma o lugar do anterior */
    renotify: true,                 /* e toca de novo a cada repetição */
    requireInteraction: true,
    vibrate: [400, 150, 400, 150, 400],
    icon: "icone-192.png",
    badge: "icone-192.png",
    data: { abrir: "ponto" }
  }));
});

self.addEventListener("notificationclick", function (e) {
  e.notification.close();
  e.waitUntil(self.clients.matchAll({ type: "window", includeUncontrolled: true }).then(function (lista) {
    for (var i = 0; i < lista.length; i++) {
      var c = lista[i];
      if (/sistema-minas\.html|\/minas-filtros-sistema\/?$/.test(c.url) && "focus" in c) {
        c.postMessage({ abrir: "ponto" });
        return c.focus();
      }
    }
    return self.clients.openWindow("index.html#ponto");
  }));
});
