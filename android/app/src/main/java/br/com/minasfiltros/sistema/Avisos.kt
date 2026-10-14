package br.com.minasfiltros.sistema

/* Os dois avisos na barra do celular: o fixo da localizacao (obrigatorio no
   Android) e o da gestao, que toca quando o sistema acende um aviso no sino. */

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

object Avisos {
  const val CANAL_AVISO = "mf_avisos"
  private var proximoId = 5100

  fun criarCanais(ctx: Context) {
    if (Build.VERSION.SDK_INT < 26) return
    val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    nm.createNotificationChannel(NotificationChannel(
      ServicoLocalizacao.CANAL, ctx.getString(R.string.canal_loc),
      NotificationManager.IMPORTANCE_LOW).apply {
        description = "Aviso fixo enquanto a localização está sendo registrada."
        setShowBadge(false)
      })
    nm.createNotificationChannel(NotificationChannel(
      CANAL_AVISO, ctx.getString(R.string.canal_avisos),
      NotificationManager.IMPORTANCE_HIGH).apply {
        description = "Paradas sem atendimento e rastreio desligado."
      })
  }

  fun mostrar(ctx: Context, titulo: String, texto: String) {
    try {
      val n = NotificationCompat.Builder(ctx, CANAL_AVISO)
        .setContentTitle(titulo)
        .setContentText(texto)
        .setStyle(NotificationCompat.BigTextStyle().bigText(texto))
        .setSmallIcon(android.R.drawable.ic_dialog_info)
        .setAutoCancel(true)
        .setContentIntent(PendingIntent.getActivity(ctx, 0,
          Intent(ctx, TelaPrincipal::class.java),
          PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        .build()
      (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
        .notify(proximoId++, n)
    } catch (e: Exception) { }
  }
}
