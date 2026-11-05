/* LEMBRETE DE PONTO (05/11/2026) — recebe o aviso do servidor no iPhone (sistema aberto pela Tela de
   Início) e nos navegadores de celular, mesmo com o sistema fechado, e mostra a notificação.
   Tocar no aviso abre o sistema no Cartão de Ponto. Este arquivo não guarda nada e não lê dados. */
self.addEventListener("install", function () { self.skipWaiting(); });
self.addEventListener("activate", function (e) { e.waitUntil(self.clients.claim()); });

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
