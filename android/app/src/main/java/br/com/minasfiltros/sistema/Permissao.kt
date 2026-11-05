package br.com.minasfiltros.sistema

/* Se este celular deixa o lembrete de ponto aparecer (05/11). O sistema mostra o estado no
   Cartao de Ponto e grava no banco, para a gestao ver quem autorizou.
     "autorizado" — notificacoes ligadas e o canal do lembrete nao foi desligado;
     "perguntar"  — Android 13 ou mais novo e o aplicativo ainda nao perguntou;
     "recusado"   — a pessoa negou, ou desligou as notificacoes ou o canal nos ajustes. */

import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationManagerCompat

object Permissao {
  fun estado(ctx: Context): String {
    return try {
      if (NotificationManagerCompat.from(ctx).areNotificationsEnabled()) {
        if (Build.VERSION.SDK_INT >= 26) {
          val m = ctx.getSystemService(NotificationManager::class.java)
          val c = m?.getNotificationChannel(Avisos.CANAL_LEMBRETE)
          if (c != null && c.importance == NotificationManager.IMPORTANCE_NONE) return "recusado"
        }
        "autorizado"
      } else if (Build.VERSION.SDK_INT >= 33 && !Guardado.perguntouAvisos(ctx)) "perguntar"
      else "recusado"
    } catch (e: Exception) { "perguntar" }
  }
}
