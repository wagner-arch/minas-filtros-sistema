package br.com.minasfiltros.sistema

/* O ouvido do aplicativo: tudo que pode ter derrubado o rastreio passa por aqui,
   e a resposta e sempre a mesma — pedir ao Vigia que confira e religue.

   SAO QUATRO AVISOS, e cada um deles corresponde a um caso real de 20 e 21/10:
     BOOT_COMPLETED       o celular reiniciou (ou a bateria acabou e ele voltou);
     QUICKBOOT_POWERON    o mesmo, no boot rapido da Xiaomi/Redmi, que muitas vezes
                          manda ESTE aviso e nao o de cima — era o caso do Renan;
     MY_PACKAGE_REPLACED  o aplicativo foi atualizado. A instalacao por cima mata o
                          processo, e ate a 1.6 nada religava o servico: foi assim
                          que o Renan parou em 21/10 as 13:51, logo depois de
                          atualizar, e nao voltou mais sozinho;
     VIGIA                o despertador de 15 em 15 minutos, que cobre o caso do
                          Thiago — o Android encerrou o aplicativo e nenhum aviso
                          do sistema chega quando isso acontece.

   Sem login, sem funcao de Vendedor ou sem o termo assinado, nada liga: quem
   decide isso e o Vigia, num lugar so. */

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class AoLigar : BroadcastReceiver() {
  override fun onReceive(ctx: Context, i: Intent) {
    val a = i.action ?: return
    val conhecido =
      a == Intent.ACTION_BOOT_COMPLETED ||
      a == "android.intent.action.QUICKBOOT_POWERON" ||
      a == "com.htc.intent.action.QUICKBOOT_POWERON" ||
      a == Intent.ACTION_MY_PACKAGE_REPLACED ||
      a == Vigia.ACAO
    if (!conhecido) return
    Vigia.conferir(ctx.applicationContext)
  }
}
