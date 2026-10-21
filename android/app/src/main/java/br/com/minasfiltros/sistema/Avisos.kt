package br.com.minasfiltros.sistema

/* Os avisos na barra do celular: o fixo da localizacao (obrigatorio no Android),
   o da gestao (que toca quando o sistema acende um aviso no sino) e o LEMBRETE DE
   PONTO, que e mudo de proposito — ele nao pode atrapalhar quem esta trabalhando. */

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

object Avisos {
  const val CANAL_AVISO = "mf_avisos"
  const val CANAL_PONTO = "mf_ponto"
  const val ID_PONTO = 5001          /* id FIXO: e por ele que o lembrete e apagado depois */
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
    /* MUDO DE PROPOSITO (21/10, regra dele): "sem som e sem vibrar, so na barra".
       IMPORTANCE_LOW nao toca, nao vibra e nao aparece por cima da tela. */
    nm.createNotificationChannel(NotificationChannel(
      CANAL_PONTO, ctx.getString(R.string.canal_ponto),
      NotificationManager.IMPORTANCE_LOW).apply {
        description = "Lembrete de bater o ponto de entrada."
        setShowBadge(false)
        enableVibration(false)
        setSound(null, null)
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

  /* O LEMBRETE DE PONTO: mudo, com id fixo, e some sozinho quando o ponto e batido. */
  fun lembrarPonto(ctx: Context) {
    try {
      val n = NotificationCompat.Builder(ctx, CANAL_PONTO)
        .setContentTitle("Você ainda não bateu o ponto de entrada")
        .setContentText("Toque para abrir o Cartão de Ponto.")
        .setSmallIcon(android.R.drawable.ic_menu_recent_history)
        .setPriority(NotificationCompat.PRIORITY_LOW)
        .setSilent(true)
        .setAutoCancel(true)
        .setContentIntent(PendingIntent.getActivity(ctx, 0,
          Intent(ctx, TelaPrincipal::class.java),
          PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        .build()
      (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
        .notify(ID_PONTO, n)
    } catch (e: Exception) { }
  }

  fun tirarLembretePonto(ctx: Context) {
    try {
      (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
        .cancel(ID_PONTO)
    } catch (e: Exception) { }
  }
}
