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

  /* a versao deste aplicativo, lida do proprio pacote (nao e escrita a mao) */
  @JavascriptInterface
  fun versaoApp(): String = Atualizador.nomeInstalado(ctx)

  @JavascriptInterface
  fun versaoCodigo(): Int = Atualizador.versaoInstalada(ctx)

  /* o sistema manda conferir se ha versao nova (botao do aviso de versao) */
  @JavascriptInterface
  fun procurarAtualizacao() {
    val t = TelaPrincipal.tela
    if (t != null) t.runOnUiThread { t.conferirAtualizacao(true) }
  }

  /* quantos pontos estao esperando internet */
  @JavascriptInterface
  fun naFila(): Int = Fila.quantos(ctx)

  /* o sistema mostra isto na tela para a conferencia do dia (19/10) */
  @JavascriptInterface
  fun pontosHoje(): Int = Guardado.enviadosHoje(ctx)

  @JavascriptInterface
  fun ultimoPonto(): String {
    val t = Guardado.ultimoEnvio(ctx)
    if (t <= 0L) return ""
    val f = java.text.SimpleDateFormat("HH:mm", java.util.Locale.US)
    f.timeZone = java.util.TimeZone.getDefault()
    return f.format(java.util.Date(t))
  }

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
