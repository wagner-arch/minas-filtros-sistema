package br.com.minasfiltros.sistema

/* O VIGIA DO RASTREIO (22/10) — e ele que religa o registro de localizacao
   SOZINHO, sem o vendedor abrir nada.

   O QUE ACONTECEU E FEZ ESTE ARQUIVO NASCER: ate a versao 1.6 o servico de
   localizacao nascia em DOIS lugares so — a pagina do sistema entregando a
   sessao depois do login (Ponte.sessao) e o aviso de BOOT_COMPLETED. Fora
   disso, nada. Entao:
     - o Thiago (Samsung, Android 14) ficou de 20/10 as 15:48 ate 22/10 as
       08:56 sem mandar um ponto, e so voltou quando ABRIU o aplicativo: o
       Android encerrou o aplicativo e ninguem o religou;
     - o Renan (Redmi) parou em 21/10 as 13:51, logo depois de ATUALIZAR: a
       instalacao por cima mata o processo, e nao havia nada atendendo
       MY_PACKAGE_REPLACED;
     - e no boot rapido do Xiaomi o aviso que chega muitas vezes e
       QUICKBOOT_POWERON, que tambem nao era atendido.
   O START_STICKY nao cobre isso: em varios aparelhos arrastar o aplicativo
   para fora da tela de recentes cancela o religar do sistema.

   COMO ELE FUNCIONA: um despertador do Android (AlarmManager) acorda de 15 em
   15 minutos, confere se o servico esta de pe, religa quando nao esta e manda
   o que ficou guardado na fila do celular. Cada disparo marca o proximo
   (alarme encadeado), entao ele nao depende de nada que possa morrer junto. */

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

object Vigia {
  const val ACAO = "br.com.minasfiltros.sistema.VIGIA"
  const val PASSO = 15L * 60L * 1000L   /* confere de 15 em 15 minutos */

  private fun pendente(ctx: Context): PendingIntent {
    /* intencao EXPLICITA (diz a classe): ninguem de fora consegue disparar isto,
       e por isso esta acao nao entra no filtro do manifesto. */
    val i = Intent(ctx, AoLigar::class.java).setAction(ACAO)
    var f = PendingIntent.FLAG_UPDATE_CURRENT
    if (Build.VERSION.SDK_INT >= 23) f = f or PendingIntent.FLAG_IMMUTABLE
    return PendingIntent.getBroadcast(ctx, 4702, i, f)
  }

  fun agendar(ctx: Context) {
    try {
      val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
      val quando = System.currentTimeMillis() + PASSO
      val p = pendente(ctx)
      /* O ALARME E EXATO DE PROPOSITO, e nao por capricho de precisao: do Android 12
         em diante o sistema PROIBE abrir servico em primeiro plano vindo do fundo, e
         uma das poucas isencoes e justamente o alarme exato. Com alarme inexato o
         vigia acordaria e seria recusado na hora de religar o rastreio.
         A permissao nao incomoda ninguem: SCHEDULE_EXACT_ALARM ja vem concedida na
         instalacao no Android 12, e do 13 em diante USE_EXACT_ALARM e automatica.
         Negada, cai no inexato — acorda igual, e ai o religar depende da isencao de
         bateria que a tela principal pede. */
      val exato = if (Build.VERSION.SDK_INT >= 31) am.canScheduleExactAlarms() else true
      if (exato && Build.VERSION.SDK_INT >= 23)
        am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, quando, p)
      else if (Build.VERSION.SDK_INT >= 23)
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, quando, p)
      else am.set(AlarmManager.RTC_WAKEUP, quando, p)
    } catch (e: Exception) { }
  }

  fun cancelar(ctx: Context) {
    try {
      (ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(pendente(ctx))
    } catch (e: Exception) { }
  }

  /* este aparelho deve estar registrando? E a MESMA conta de sempre: login
     guardado, funcao Vendedor e termo assinado (regra dele de 14/10). Sem um
     dos tres o vigia se desliga e nao religa nada. */
  fun deveRastrear(ctx: Context): Boolean =
    Guardado.tem(ctx) && Guardado.funcao(ctx) == "Vendedor" && Guardado.assinou(ctx)

  /* a conferencia: religa o servico quando ele nao esta de pe, manda a fila e
     marca o proximo despertar */
  fun conferir(ctx: Context) {
    if (!deveRastrear(ctx)) { cancelar(ctx); return }
    agendar(ctx)
    if (!ServicoLocalizacao.ligado) ligarServico(ctx)
    else esvaziarFila(ctx)
  }

  /* A FILA SAI MESMO QUANDO O SERVICO NAO PODE SUBIR: ponto guardado no celular
     tem dentro de si o horario em que foi medido (`em`), entao ele chega ao banco
     com a hora certa, por mais tarde que saia daqui. */
  fun esvaziarFila(ctx: Context) {
    if (Fila.quantos(ctx) <= 0) return
    Thread { try { Fila.enviarTudo(ctx) } catch (e: Exception) { } }.start()
  }

  fun ligarServico(ctx: Context) {
    try {
      val s = Intent(ctx, ServicoLocalizacao::class.java)
      if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(s) else ctx.startService(s)
    } catch (e: Throwable) {
      /* recusado pelo Android (sem isencao para abrir servico vindo do fundo):
         ao menos o que esta guardado vai ao banco, e o proximo alarme tenta de novo. */
      esvaziarFila(ctx)
    }
  }
}
