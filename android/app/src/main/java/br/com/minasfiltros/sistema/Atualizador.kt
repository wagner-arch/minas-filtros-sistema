package br.com.minasfiltros.sistema

/* ATUALIZACAO AUTOMATICA DO APLICATIVO.
   Ao abrir, o aplicativo le um arquivo pequeno no PROPRIO SITE do sistema
   (mesmo endereco que ele ja abre, sem bloqueio de origem e sem limite de
   consultas) e compara com a versao instalada. Sendo mais nova, oferece
   atualizar: baixa o arquivo do Releases do GitHub e chama o instalador do
   Android — o toque de confirmacao do Android e obrigatorio e nao da para
   pular, porque o aplicativo nao vem da loja.

   O endereco do arquivo e CONFERIDO contra o nosso repositorio: mesmo que
   alguem mexa no arquivo de versao, o aplicativo nao baixa de outro lugar. */

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

object Atualizador {

  const val AVISO_VERSAO = TelaPrincipal.ENDERECO + "app/versao-app.json"
  /* so baixa de dentro do nosso repositorio */
  private const val PERMITIDO = "https://github.com/wagner-arch/minas-filtros-sistema/releases/"

  data class Nova(val codigo: Int, val nome: String, val arquivo: String, val novidades: String)

  @Suppress("DEPRECATION")
  fun versaoInstalada(ctx: Context): Int =
    try {
      val p = ctx.packageManager.getPackageInfo(ctx.packageName, 0)
      if (android.os.Build.VERSION.SDK_INT >= 28) p.longVersionCode.toInt() else p.versionCode
    } catch (e: Exception) { 0 }

  fun nomeInstalado(ctx: Context): String =
    try { ctx.packageManager.getPackageInfo(ctx.packageName, 0).versionName ?: "" } catch (e: Exception) { "" }

  /* le o arquivo de versao no site. Devolve null quando nao ha nada novo
     (ou quando nao deu para conferir, que nao e motivo para incomodar ninguem) */
  fun procurar(ctx: Context): Nova? {
    val txt = baixarTexto(AVISO_VERSAO) ?: return null
    return try {
      val o = JSONObject(txt)
      val cod = o.optInt("versionCode", 0)
      val arq = o.optString("arquivo", "")
      if (cod <= versaoInstalada(ctx)) return null
      if (!arq.startsWith(PERMITIDO)) return null
      Nova(cod, o.optString("versionName", ""), arq, o.optString("novidades", ""))
    } catch (e: Exception) { null }
  }

  /* baixa o arquivo de instalacao e devolve onde ele ficou */
  fun baixar(ctx: Context, nova: Nova): File? {
    if (!nova.arquivo.startsWith(PERMITIDO)) return null
    val pasta = File(ctx.getExternalFilesDir(null), "atualizacao")
    if (!pasta.exists()) pasta.mkdirs()
    val destino = File(pasta, "minas-filtros-" + nova.codigo + ".apk")
    pasta.listFiles()?.forEach { if (it.name != destino.name) it.delete() }
    var endereco = nova.arquivo
    var voltas = 0
    while (voltas < 5) {
      var con: HttpURLConnection? = null
      try {
        val c = (URL(endereco).openConnection() as HttpURLConnection)
        con = c
        c.instanceFollowRedirects = false
        c.connectTimeout = 25000
        c.readTimeout = 120000
        val cod = c.responseCode
        if (cod == 301 || cod == 302 || cod == 303 || cod == 307 || cod == 308) {
          val para = c.getHeaderField("Location") ?: return null
          if (!para.startsWith("https://")) return null   /* nunca cai para endereco sem protecao */
          endereco = para
          voltas++
          c.disconnect()
          continue
        }
        if (cod !in 200..299) return null
        destino.outputStream().use { saida -> c.inputStream.use { entrada -> entrada.copyTo(saida) } }
        return if (destino.length() > 100000) destino else null   /* arquivo cortado nao serve */
      } catch (e: Exception) {
        return null
      } finally {
        try { con?.disconnect() } catch (e: Exception) { }
      }
    }
    return null
  }

  /* chama o instalador do Android. O Android confere a assinatura: o arquivo
     novo so instala por cima se foi assinado com a MESMA chave. */
  fun instalar(ctx: Context, arq: File): Boolean =
    try {
      val uri: Uri = FileProvider.getUriForFile(ctx, ctx.packageName + ".arquivos", arq)
      val i = Intent(Intent.ACTION_VIEW)
        .setDataAndType(uri, "application/vnd.android.package-archive")
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      ctx.startActivity(i)
      true
    } catch (e: Exception) { false }

  fun podeInstalar(ctx: Context): Boolean =
    if (android.os.Build.VERSION.SDK_INT >= 26) ctx.packageManager.canRequestPackageInstalls() else true

  /* abre a tela do Android onde se libera "instalar aplicativos desconhecidos" */
  fun abrirPermissaoInstalar(ctx: Context) {
    try {
      ctx.startActivity(Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
        .setData(Uri.parse("package:" + ctx.packageName))
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (e: Exception) { }
  }

  private fun baixarTexto(endereco: String): String? {
    var c: HttpURLConnection? = null
    return try {
      c = (URL(endereco).openConnection() as HttpURLConnection)
      c.connectTimeout = 15000
      c.readTimeout = 20000
      c.setRequestProperty("Cache-Control", "no-cache")
      if (c.responseCode !in 200..299) null
      else c.inputStream.bufferedReader().use { it.readText() }
    } catch (e: Exception) { null } finally { try { c?.disconnect() } catch (e: Exception) { } }
  }
}
