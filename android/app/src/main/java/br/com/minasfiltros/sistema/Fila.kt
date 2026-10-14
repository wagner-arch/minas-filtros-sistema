package br.com.minasfiltros.sistema

/* Sem internet, o ponto fica guardado no celular (uma linha por ponto) e sai
   quando a internet voltar. Teto de 20 mil linhas: mais que isso e porque algo
   esta errado, e nao vale encher o aparelho. */

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

object Fila {
  private const val TETO = 20000
  private fun arq(ctx: Context) = File(ctx.filesDir, "pontos.fila")

  @Synchronized
  fun guardar(ctx: Context, o: JSONObject) {
    try {
      val f = arq(ctx)
      if (quantos(ctx) >= TETO) return
      f.appendText(o.toString() + "\n")
    } catch (e: Exception) { }
  }

  @Synchronized
  fun quantos(ctx: Context): Int {
    val f = arq(ctx)
    if (!f.exists()) return 0
    return try { f.readLines().count { it.isNotBlank() } } catch (e: Exception) { 0 }
  }

  /* manda o que esta guardado, de 200 em 200; o que nao passou continua guardado */
  @Synchronized
  fun enviarTudo(ctx: Context) {
    val f = arq(ctx)
    if (!f.exists()) return
    val linhas = try { f.readLines().filter { it.isNotBlank() } } catch (e: Exception) { return }
    if (linhas.isEmpty()) { try { f.delete() } catch (e: Exception) { }; return }
    var i = 0
    val sobrou = mutableListOf<String>()
    while (i < linhas.size) {
      val lote = linhas.subList(i, minOf(i + 200, linhas.size))
      val arr = JSONArray()
      lote.forEach { l -> try { arr.put(JSONObject(l)) } catch (e: Exception) { } }
      val ok = if (arr.length() == 0) true else Banco.gravarPontos(ctx, arr)
      if (!ok) sobrou.addAll(lote)
      i += 200
    }
    try {
      if (sobrou.isEmpty()) f.delete()
      else f.writeText(sobrou.joinToString("\n") + "\n")
    } catch (e: Exception) { }
  }
}
