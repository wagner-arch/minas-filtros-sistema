package br.com.minasfiltros.sistema

/* A ponte entre o sistema (a pagina) e o aplicativo.
   A pagina chama window.MFApp.* ; o aplicativo nunca inventa dado nenhum:
   quem diz quem esta logado, qual a funcao e qual a credencial e o sistema. */

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Base64
import android.webkit.JavascriptInterface
import androidx.core.content.FileProvider
import org.json.JSONObject
import java.io.File

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

  /* LEMBRETE DE PONTO (21/10, regra dele): o sistema sabe se a batida de entrada saiu;
     o servico sabe quando a pessoa comeca a andar. O sistema avisa aqui, e o servico
     escolhe a hora. Batido o ponto, o sistema chama com `false` e o lembrete some. */
  @JavascriptInterface
  fun cobrarPonto(falta: Boolean) {
    Guardado.cobrarPonto(ctx, falta)
    if (!falta) Avisos.tirarLembretePonto(ctx)
  }
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

  /* O PDF DIRETO NA CONVERSA DO CLIENTE (28/10, print dele: o WhatsApp recebia so o texto).
     Dentro do aplicativo o "compartilhar com arquivo" do navegador nao existe, entao o sistema
     entrega o arquivo aqui: ele vira um arquivo do aplicativo, e o WhatsApp recebe o PDF e a
     mensagem ja na conversa do numero do cliente (o WhatsApp Business primeiro, que e o dos
     celulares da empresa; depois o comum; sem nenhum dos dois, a lista de aplicativos). */
  @JavascriptInterface
  fun compartilharArquivo(base64: String, nome: String, texto: String, telefone: String): Boolean {
    return try {
      val pasta = File(ctx.getExternalFilesDir(null), "compartilhar")
      pasta.mkdirs()
      pasta.listFiles()?.forEach { it.delete() }
      val limpo = nome.replace(Regex("[^A-Za-z0-9._-]"), "_").ifEmpty { "documento.pdf" }
      val arq = File(pasta, limpo)
      arq.writeBytes(Base64.decode(base64, Base64.DEFAULT))
      val uri = FileProvider.getUriForFile(ctx, ctx.packageName + ".arquivos", arq)
      val dig = telefone.filter { it.isDigit() }
      fun intencao(pacote: String?): Intent {
        val i = Intent(Intent.ACTION_SEND)
        i.type = "application/pdf"
        i.putExtra(Intent.EXTRA_STREAM, uri)
        if (texto.isNotEmpty()) i.putExtra(Intent.EXTRA_TEXT, texto)
        if (dig.length >= 10) i.putExtra("jid", dig + "@s.whatsapp.net")
        i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        if (pacote != null) i.setPackage(pacote)
        return i
      }
      val ui = (ctx as? android.app.Activity)
      fun abrir(i: Intent) {
        if (ui != null) ui.runOnUiThread { ui.startActivity(i) }
        else { i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK); ctx.startActivity(i) }
      }
      val pm = ctx.packageManager
      val pacote = listOf("com.whatsapp.w4b", "com.whatsapp").firstOrNull { p ->
        try { pm.getPackageInfo(p, 0); true } catch (e: Exception) { false } }
      if (pacote != null) {
        try { abrir(intencao(pacote)); return true } catch (e: ActivityNotFoundException) { }
      }
      val esc = Intent.createChooser(intencao(null), "Enviar o PDF")
      esc.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
      abrir(esc)
      true
    } catch (e: Throwable) {
      false
    }
  }

  private fun ligar() {
    if (ServicoLocalizacao.ligado) return
    val i = Intent(ctx, ServicoLocalizacao::class.java)
    if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
  }

  private fun desligar() {
    ctx.stopService(Intent(ctx, ServicoLocalizacao::class.java))
  }
}
