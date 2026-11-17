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

  /* manda o que esta guardado, de 200 em 200; o que nao passou continua guardado.
     17/11 (2.2) — O DEFEITO QUE CUSTOU METADE DO TRAJETO: bastava UM ponto ruim dentro do
     lote para o banco recusar o LOTE INTEIRO, e como o que nao passa volta para a fila, o
     mesmo lote saia e era recusado para sempre, sem nunca esvaziar. Agora, quando a recusa
     vem do BANCO (e nao da falta de internet), a fila manda um a um: passa o que presta, e
     o que o banco recusar sozinho e contado e sai da fila — some da frente dos outros, mas
     nao some calado: o sistema mostra a lista com o motivo. */
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
      if (!ok) {
        /* COM A CHAVE do aparelho a funcao do banco nunca recusa o lote por causa de um
           ponto: ela grava o que presta e guarda o resto na lista de recusados, com o
           motivo. Entao aqui so ha um caminho: o lote espera e sai depois. O um a um e
           para o caminho ANTIGO, que e onde o lote travava. */
        if (Guardado.chaveRastro(ctx).isEmpty() && Banco.recusaDoBanco()) {
          var recusados = 0
          lote.forEach { l ->
            val o = try { JSONObject(l) } catch (e: Exception) { null }
            if (o == null) recusados++                       /* linha estragada: nao volta para a fila */
            else if (!Banco.gravarUmPonto(ctx, o)) {
              if (Banco.recusaDoBanco()) recusados++         /* o banco recusou ESTE: sai da fila */
              else sobrou.add(l)                             /* foi a internet: fica para depois */
            }
          }
          if (recusados > 0) Guardado.contarRecusado(ctx, recusados)
        } else sobrou.addAll(lote)                           /* sem internet: fica tudo para depois */
      }
      i += 200
    }
    try {
      if (sobrou.isEmpty()) f.delete()
      else f.writeText(sobrou.joinToString("\n") + "\n")
    } catch (e: Exception) { }
  }
}
