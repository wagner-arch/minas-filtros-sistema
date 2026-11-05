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
  /* O LEMBRETE DE PONTO COM SOM (05/11, pedido dele): substitui o lembrete mudo de 21/10.
     Canal novo de proposito — o Android nao deixa mudar o som de um canal que ja existe. */
  const val CANAL_LEMBRETE = "mf_lembrete_ponto_som"
  const val ID_LEMBRETE = 5002
  const val TAG_LEMBRETE = "lembrete_ponto"
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
    /* o lembrete mudo de 21/10 saiu: o canal dele e apagado para nao confundir nos ajustes */
    try { nm.deleteNotificationChannel(CANAL_PONTO) } catch (e: Exception) { }
    /* O LEMBRETE DE PONTO (05/11): prioridade alta (aparece no topo da tela), som proprio do
       aplicativo, vibracao e visivel na tela de bloqueio. No silencioso ou em "Nao perturbe"
       o Android nao deixa tocar — e a tela de autorizacao explica isso. */
    val som = android.net.Uri.parse("android.resource://" + ctx.packageName + "/" + R.raw.lembrete_ponto)
    val atr = android.media.AudioAttributes.Builder()
      .setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION)
      .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
    nm.createNotificationChannel(NotificationChannel(
      CANAL_LEMBRETE, ctx.getString(R.string.canal_lembrete),
      NotificationManager.IMPORTANCE_HIGH).apply {
        description = "Avisa 3 minutos antes de cada horário do ponto e, passado o horário, a cada 2 minutos até bater."
        setSound(som, atr)
        enableVibration(true)
        vibrationPattern = VIBRA
        lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        setShowBadge(true)
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
      val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
      nm.cancel(ID_PONTO)
      nm.cancel(TAG_LEMBRETE, ID_LEMBRETE)
    } catch (e: Exception) { }
  }

  private val VIBRA = longArrayOf(0, 400, 150, 400, 150, 400)

  /* o lembrete que vem do servidor. O anterior e TIRADO antes do novo entrar: assim o aviso
     nao se empilha na barra e o Android toca e vibra de novo em TODA repeticao. */
  fun mostrarLembretePonto(ctx: Context, titulo: String, texto: String) {
    try {
      criarCanais(ctx)
      val abrir = Intent(ctx, TelaPrincipal::class.java)
        .putExtra("abrir", "ponto")
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
      val som = android.net.Uri.parse("android.resource://" + ctx.packageName + "/" + R.raw.lembrete_ponto)
      val n = NotificationCompat.Builder(ctx, CANAL_LEMBRETE)
        .setContentTitle(titulo)
        .setContentText(texto)
        .setStyle(NotificationCompat.BigTextStyle().bigText(texto))
        .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
        .setPriority(NotificationCompat.PRIORITY_HIGH)
        .setCategory(NotificationCompat.CATEGORY_REMINDER)
        .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
        .setSound(som)                 /* Android 7 e anteriores, que nao tem canal */
        .setVibrate(VIBRA)
        .setOnlyAlertOnce(false)
        .setAutoCancel(true)
        .setContentIntent(PendingIntent.getActivity(ctx, 7, abrir,
          PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        .build()
      val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
      nm.cancel(TAG_LEMBRETE, ID_LEMBRETE)
      nm.notify(TAG_LEMBRETE, ID_LEMBRETE, n)
    } catch (e: Exception) { }
  }
}
