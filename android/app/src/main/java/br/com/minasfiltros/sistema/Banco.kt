package br.com.minasfiltros.sistema

/* Fala com o banco por rede, com a credencial que o sistema entregou.
   Toda gravacao CONFERE a resposta: nao deu certo, o ponto volta para a fila
   e sai de novo quando a internet voltar (regra da casa). */

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.net.HttpURLConnection
import java.net.URL

object Banco {

  /* grava um lote de pontos. Devolve true so quando o banco confirmou. */
  fun gravarPontos(ctx: Context, linhas: JSONArray): Boolean =
    enviar(ctx, "/rest/v1/rastro_pontos", linhas.toString(), "POST") != null

  /* abre a parada e devolve o id que o banco deu */
  fun abrirParada(ctx: Context, o: JSONObject): Long? {
    val r = enviar(ctx, "/rest/v1/rastro_paradas", JSONArray().put(o).toString(), "POST",
      mapOf("Prefer" to "return=representation")) ?: return null
    return try { JSONArray(r).getJSONObject(0).getLong("id") } catch (e: Exception) { null }
  }

  /* fecha a parada: hora de saida e minutos parado */
  fun fecharParada(ctx: Context, id: Long, fim: String, minutos: Int): Boolean {
    val corpo = JSONObject().put("fim", fim).put("minutos", minutos).toString()
    return enviar(ctx, "/rest/v1/rastro_paradas?id=eq.$id", corpo, "PATCH") != null
  }

  /* avisos novos para o celular da gestao: parada acesa no sino e ainda nao mostrada */
  fun avisosNovos(ctx: Context, desde: String): JSONArray? {
    val cols = "vendedor,endereco,minutos,inicio,fim,avisado_em"
    val r = enviar(ctx,
      "/rest/v1/rastro_paradas?select=$cols&avisado_em=gt.$desde&com_atendimento=is.false" +
      "&na_loja=is.false&no_almoco=is.false&order=avisado_em.desc&limit=20", null, "GET") ?: return null
    return try { JSONArray(r) } catch (e: Exception) { null }
  }

  /* ---------- o motor ---------- */
  private fun enviar(ctx: Context, caminho: String, corpo: String?, metodo: String,
                     extras: Map<String, String> = emptyMap()): String? {
    val r1 = chamar(ctx, caminho, corpo, metodo, extras, Guardado.token(ctx))
    if (r1 != null) return r1
    /* a credencial vence de hora em hora: renova uma vez e tenta de novo */
    if (!renovar(ctx)) return null
    return chamar(ctx, caminho, corpo, metodo, extras, Guardado.token(ctx))
  }

  private fun chamar(ctx: Context, caminho: String, corpo: String?, metodo: String,
                     extras: Map<String, String>, token: String): String? {
    val base = Guardado.url(ctx)
    if (base.isEmpty() || token.isEmpty()) return null
    var c: HttpURLConnection? = null
    return try {
      c = (URL(base + caminho).openConnection() as HttpURLConnection)
      c.requestMethod = metodo
      c.connectTimeout = 20000
      c.readTimeout = 25000
      c.setRequestProperty("apikey", Guardado.chave(ctx))
      c.setRequestProperty("Authorization", "Bearer $token")
      c.setRequestProperty("Content-Type", "application/json")
      extras.forEach { (k, v) -> c!!.setRequestProperty(k, v) }
      if (corpo != null) {
        c.doOutput = true
        c.outputStream.use { it.write(corpo.toByteArray(Charsets.UTF_8)) }
      }
      val cod = c.responseCode
      if (cod in 200..299) {
        ultimoErro = ""
        val txt = try { c.inputStream.bufferedReader().use(BufferedReader::readText) } catch (e: Exception) { "" }
        txt
      } else {
        /* O `catch` GENERICO ESCONDEU UM DEFEITO POR DIAS (19/10): a rede na linha principal
           lancava NetworkOnMainThreadException, era engolida aqui e virava "nao consegui" —
           na tela, isso parecia falta de internet. Agora o motivo fica guardado e o aviso
           fixo do celular o mostra: erro de programacao nao se disfarca de falta de sinal. */
        ultimoErro = "o banco respondeu " + cod
        null
      }
    } catch (e: Exception) {
      ultimoErro = (e.javaClass.simpleName ?: "falha") + ": " + (e.message ?: "")
      null
    } finally { try { c?.disconnect() } catch (e: Exception) { } }
  }

  /* o motivo da ultima falha, para o aviso fixo dizer a verdade */
  @Volatile var ultimoErro: String = ""

  private fun renovar(ctx: Context): Boolean {
    val rt = Guardado.refresh(ctx)
    val base = Guardado.url(ctx)
    if (rt.isEmpty() || base.isEmpty()) return false
    var c: HttpURLConnection? = null
    return try {
      c = (URL("$base/auth/v1/token?grant_type=refresh_token").openConnection() as HttpURLConnection)
      c.requestMethod = "POST"
      c.connectTimeout = 20000
      c.readTimeout = 25000
      c.setRequestProperty("apikey", Guardado.chave(ctx))
      c.setRequestProperty("Content-Type", "application/json")
      c.doOutput = true
      c.outputStream.use { it.write(JSONObject().put("refresh_token", rt).toString().toByteArray()) }
      val cod = c.responseCode
      if (cod !in 200..299) {
        /* CELULAR PERDIDO OU ROUBADO: quando a gestao desconecta o usuario a
           distancia, o banco passa a RECUSAR a credencial. Aqui o aplicativo
           entende isso, apaga a sessao guardada e DESLIGA o rastreio — nada
           mais e registrado neste aparelho. Falha de internet nao entra neste
           caminho: ela nem chega a receber resposta (cai no catch). */
        if (cod == 400 || cod == 401 || cod == 403) desconectado(ctx)
        return false
      }
      val o = JSONObject(c.inputStream.bufferedReader().use(BufferedReader::readText))
      val novo = o.optString("access_token")
      if (novo.isEmpty()) return false
      Guardado.trocarToken(ctx, novo, o.optString("refresh_token", rt))
      true
    } catch (e: Exception) { false } finally { try { c?.disconnect() } catch (e: Exception) { } }
  }

  /* apaga a sessao do aparelho e para o servico de localizacao */
  private fun desconectado(ctx: Context) {
    try {
      Guardado.limparSessao(ctx)
      ctx.stopService(android.content.Intent(ctx, ServicoLocalizacao::class.java))
      Avisos.mostrar(ctx, "Sessão encerrada",
        "Este celular foi desconectado do sistema Minas Filtros. Fale com a gestão.")
    } catch (e: Exception) { }
  }
}
