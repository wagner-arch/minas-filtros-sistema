package br.com.minasfiltros.sistema

/* O celular reiniciou: se havia vendedor logado, a localizacao volta sozinha.
   Sem sessao guardada nao liga nada. */

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class AoLigar : BroadcastReceiver() {
  override fun onReceive(ctx: Context, i: Intent) {
    if (i.action != Intent.ACTION_BOOT_COMPLETED) return
    if (!Guardado.tem(ctx)) return
    if (Guardado.funcao(ctx) != "Vendedor" || !Guardado.assinou(ctx)) return
    val s = Intent(ctx, ServicoLocalizacao::class.java)
    if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(s) else ctx.startService(s)
  }
}
