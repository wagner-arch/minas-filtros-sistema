package br.com.minasfiltros.sistema

/* A ponte entre o sistema (a pagina) e o aplicativo.
   A pagina chama window.MFApp.* ; o aplicativo nunca inventa dado nenhum:
   quem diz quem esta logado, qual a funcao e qual a credencial e o sistema. */

import android.content.Context
import android.content.Intent
import android.os.Build
import android.webkit.JavascriptInterface
import org.json.JSONObject

class Ponte(private val ctx: Context) {

  /* O sistema entrega a sessao depois do login. Sem isto o rastreio nao liga.
     json: {url, chave, token, refresh, expira, nome, funcao, loja, assinou} */
  @JavascriptInterface
  fun sessao(json: String) {
    try {
      val o = JSONObject(json)
      Guardado.salvarSessao(ctx, o)
      /* REGRA DELE (14/10): o rastreio liga SO para a funcao Vendedor.
         No celular do Administrador e do Gerente o aplicativo so recebe avisos. */
      val rastreia = o.optString("funcao") == "Vendedor"
      val assinou  = o.optBoolean("assinou", false)
      if (rastreia && assinou) ligar() else desligar()
    } catch (e: Exception) { }
  }

  /* o vendedor saiu do sistema: para de registrar na hora */
  @JavascriptInterface
  fun saiu() {
    Guardado.limparSessao(ctx)
    desligar()
  }

  /* o sistema acende um aviso novo no sino: o celular da gestao toca */
  @JavascriptInterface
  fun notificar(titulo: String, texto: String) {
    Avisos.mostrar(ctx, titulo, texto)
  }

  /* o sistema pergunta se esta registrando, para mostrar na tela */
  @JavascriptInterface
  fun rastreando(): Boolean = ServicoLocalizacao.ligado

  @JavascriptInterface
  fun versaoApp(): String = "1.0"

  /* quantos pontos estao esperando internet */
  @JavascriptInterface
  fun naFila(): Int = Fila.quantos(ctx)

  /* abre a tela de bateria do proprio celular, para liberar o aplicativo */
  @JavascriptInterface
  fun abrirAjustesBateria() {
    try {
      ctx.startActivity(Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (e: Exception) {
      try {
        ctx.startActivity(Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
          .setData(android.net.Uri.parse("package:" + ctx.packageName))
          .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
      } catch (e2: Exception) { }
    }
  }

  @JavascriptInterface
  fun marcaDoCelular(): String = (Build.MANUFACTURER ?: "") + " " + (Build.MODEL ?: "")

  private fun ligar() {
    if (ServicoLocalizacao.ligado) return
    val i = Intent(ctx, ServicoLocalizacao::class.java)
    if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
  }

  private fun desligar() {
    ctx.stopService(Intent(ctx, ServicoLocalizacao::class.java))
  }
}
