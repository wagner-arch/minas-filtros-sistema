package br.com.minasfiltros.sistema

/* O LEMBRETE DE PONTO QUE VEM DO SERVIDOR (05/11/2026, pedido dele).
   O banco confere de minuto em minuto quem precisa bater o ponto e manda, pelo Firebase, uma
   mensagem de DADOS de prioridade alta. Ela chega mesmo com o aplicativo fechado e a tela
   bloqueada, e quem monta o aviso e o proprio aplicativo (Avisos.mostrarLembretePonto): com o
   som proprio, a vibracao, a tela de bloqueio e o topo da tela — em TODA repeticao.
   Quando o Firebase troca o endereco deste celular, ele fica guardado e o sistema grava no
   banco na proxima vez que abrir. */

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class MensagensPonto : FirebaseMessagingService() {

  override fun onMessageReceived(m: RemoteMessage) {
    try {
      val d = m.data
      if (d["tipo"] != "lembrete_ponto") return
      Avisos.mostrarLembretePonto(applicationContext,
        d["titulo"] ?: "Lembrete de ponto",
        d["texto"] ?: "Não esqueça de bater o ponto.")
    } catch (e: Exception) { }
  }

  override fun onNewToken(token: String) {
    try { Guardado.salvarTokenAviso(applicationContext, token) } catch (e: Exception) { }
  }
}
