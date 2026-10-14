package br.com.minasfiltros.sistema

/* O que o aplicativo guarda no armazenamento privado dele: a sessao entregue
   pelo sistema e a parada em andamento. Nada aqui e visivel a outro aplicativo. */

import android.content.Context
import org.json.JSONObject

object Guardado {
  private fun p(ctx: Context) = ctx.getSharedPreferences("mf", Context.MODE_PRIVATE)

  fun salvarSessao(ctx: Context, o: JSONObject) {
    p(ctx).edit()
      .putString("url", o.optString("url"))
      .putString("chave", o.optString("chave"))
      .putString("token", o.optString("token"))
      .putString("refresh", o.optString("refresh"))
      .putString("nome", o.optString("nome"))
      .putString("funcao", o.optString("funcao"))
      .putString("loja", o.optString("loja"))
      .putBoolean("assinou", o.optBoolean("assinou", false))
      .apply()
  }

  fun limparSessao(ctx: Context) {
    p(ctx).edit().remove("token").remove("refresh").remove("nome").apply()
  }

  fun tem(ctx: Context): Boolean =
    !(p(ctx).getString("token", "") ?: "").isEmpty() &&
    !(p(ctx).getString("nome", "") ?: "").isEmpty()

  fun url(ctx: Context) = p(ctx).getString("url", "") ?: ""
  fun chave(ctx: Context) = p(ctx).getString("chave", "") ?: ""
  fun token(ctx: Context) = p(ctx).getString("token", "") ?: ""
  fun refresh(ctx: Context) = p(ctx).getString("refresh", "") ?: ""
  fun nome(ctx: Context) = p(ctx).getString("nome", "") ?: ""
  fun funcao(ctx: Context) = p(ctx).getString("funcao", "") ?: ""
  fun loja(ctx: Context) = p(ctx).getString("loja", "") ?: ""
  fun assinou(ctx: Context) = p(ctx).getBoolean("assinou", false)

  fun trocarToken(ctx: Context, novo: String, novoRefresh: String) {
    p(ctx).edit().putString("token", novo).putString("refresh", novoRefresh).apply()
  }

  /* a parada em andamento: centro, quando comecou e quantos pontos ja caíram nela */
  fun paradaSalva(ctx: Context): JSONObject? {
    val s = p(ctx).getString("parada", "") ?: ""
    return if (s.isEmpty()) null else try { JSONObject(s) } catch (e: Exception) { null }
  }
  fun salvarParada(ctx: Context, o: JSONObject?) {
    if (o == null) p(ctx).edit().remove("parada").apply()
    else p(ctx).edit().putString("parada", o.toString()).apply()
  }
}
