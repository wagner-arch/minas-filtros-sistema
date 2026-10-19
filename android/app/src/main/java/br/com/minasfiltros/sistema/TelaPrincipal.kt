package br.com.minasfiltros.sistema

/* O aplicativo abre o PROPRIO sistema que ja existe (mesmo endereco, mesmo login),
   para nao haver dois sistemas. As telas continuam atualizando sozinhas, como hoje.
   O que e novo aqui e so a localizacao, que o navegador do celular nao consegue
   pegar com a tela desligada. */

import android.Manifest
import android.annotation.SuppressLint
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.webkit.*
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.appcompat.app.AlertDialog

class TelaPrincipal : AppCompatActivity() {

  companion object {
    const val ENDERECO = "https://wagner-arch.github.io/minas-filtros-sistema/"
    var pagina: WebView? = null
    /* a tela aberta, para o sistema poder pedir a conferencia de versao */
    var tela: TelaPrincipal? = null
  }

  private lateinit var web: WebView

  @SuppressLint("SetJavaScriptEnabled")
  override fun onCreate(estado: Bundle?) {
    super.onCreate(estado)
    Avisos.criarCanais(this)

    web = WebView(this)
    setContentView(web)
    pagina = web
    tela = this

    web.settings.apply {
      javaScriptEnabled = true
      domStorageEnabled = true          /* o sistema guarda a sessao e a configuracao do aparelho */
      databaseEnabled = true
      mediaPlaybackRequiresUserGesture = false   /* leitor de codigo de barras e foto do ponto */
      useWideViewPort = true
      loadWithOverviewMode = true
      javaScriptCanOpenWindowsAutomatically = true
      setSupportMultipleWindows(false)
      userAgentString = "$userAgentString MinasFiltrosApp/1.0"
    }
    WebView.setWebContentsDebuggingEnabled(false)
    /* o Android nao inverte as cores do sistema (19/10): com o celular em modo escuro, o
       quadro branco da assinatura virava preto e o traco do dedo sumia. O tema ja desliga
       isso (res/values/themes.xml); aqui e a segunda tranca, para a versao do WebView que
       decide por conta propria. */
    try {
      @Suppress("DEPRECATION")
      if (Build.VERSION.SDK_INT >= 29) web.settings.forceDark = android.webkit.WebSettings.FORCE_DARK_OFF
    } catch (e: Throwable) { }
    try { web.setBackgroundColor(android.graphics.Color.WHITE) } catch (e: Exception) { }
    CookieManager.getInstance().setAcceptCookie(true)

    /* a ponte: e por ela que o sistema entrega a sessao e pede notificacao */
    web.addJavascriptInterface(Ponte(this), "MFApp")

    /* camera e GPS pedidos pela propria pagina (foto do ponto, "marcar onde estou") */
    web.webChromeClient = object : WebChromeClient() {
      override fun onPermissionRequest(p: PermissionRequest) { p.grant(p.resources) }
      override fun onGeolocationPermissionsShowPrompt(o: String, cb: GeolocationPermissions.Callback) {
        cb.invoke(o, true, false)
      }
    }

    /* WhatsApp, telefone, mapa e PDF saem para fora; o resto fica na pagina */
    web.webViewClient = object : WebViewClient() {
      override fun shouldOverrideUrlLoading(v: WebView, r: WebResourceRequest): Boolean {
        val u = r.url.toString()
        if (u.startsWith(ENDERECO)) return false
        return try {
          startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(u)))
          true
        } catch (e: Exception) { false }
      }
      override fun onPageFinished(v: WebView, u: String) {
        /* avisa a pagina que ela esta dentro do aplicativo */
        v.evaluateJavascript("window.__dentroDoAppMF=true;", null)
      }
    }

    web.loadUrl(ENDERECO)
    pedirPermissoes()
    /* confere se ha versao nova do aplicativo (nao atrapalha a abertura: espera 4 s) */
    web.postDelayed({ conferirAtualizacao(false) }, 4000)
  }

  /* Android pede a localizacao em duas etapas: primeiro durante o uso, depois
     "sempre" (segundo plano). Pedir as duas de uma vez o sistema recusa. */
  private fun pedirPermissoes() {
    val faltam = mutableListOf<String>()
    if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
        != PackageManager.PERMISSION_GRANTED) {
      faltam += Manifest.permission.ACCESS_FINE_LOCATION
      faltam += Manifest.permission.ACCESS_COARSE_LOCATION
    }
    if (Build.VERSION.SDK_INT >= 33 &&
        ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
        != PackageManager.PERMISSION_GRANTED) {
      faltam += Manifest.permission.POST_NOTIFICATIONS
    }
    if (faltam.isNotEmpty()) ActivityCompat.requestPermissions(this, faltam.toTypedArray(), 10)
    else pedirSempre()
  }

  private fun pedirSempre() {
    if (Build.VERSION.SDK_INT >= 29 &&
        ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        != PackageManager.PERMISSION_GRANTED) {
      Toast.makeText(this,
        "Na próxima tela, escolha PERMITIR SEMPRE — sem isso a localização para quando a tela apaga.",
        Toast.LENGTH_LONG).show()
      ActivityCompat.requestPermissions(this,
        arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION), 11)
    }
  }

  override fun onRequestPermissionsResult(c: Int, p: Array<out String>, r: IntArray) {
    super.onRequestPermissionsResult(c, p, r)
    if (c == 10) pedirSempre()
  }

  /* ---------- atualizacao do aplicativo ---------- */

  /* pedida = o usuario mandou conferir pelo sistema; ai avisa tambem quando ja esta em dia */
  fun conferirAtualizacao(pedida: Boolean) {
    Thread {
      val nova = Atualizador.procurar(this)
      runOnUiThread {
        if (!isFinishing && !isDestroyed) {
          if (nova == null) {
            if (pedida) Toast.makeText(this,
              "O aplicativo já está na versão mais nova (" + Atualizador.nomeInstalado(this) + ").",
              Toast.LENGTH_LONG).show()
          } else {
            val t = StringBuilder("Versão nova do aplicativo: " + nova.nome + ".\n\n")
            if (nova.novidades.isNotEmpty()) t.append(nova.novidades).append("\n\n")
            t.append("A atualização baixa uns poucos megabytes e o Android vai pedir uma ")
             .append("confirmação na tela. O login e o termo assinado continuam valendo.")
            AlertDialog.Builder(this)
              .setTitle("Atualizar agora?")
              .setMessage(t.toString())
              .setPositiveButton("Atualizar agora") { _, _ -> baixarEInstalar(nova) }
              .setNegativeButton("Depois", null)
              .show()
          }
        }
      }
    }.start()
  }

  private fun baixarEInstalar(nova: Atualizador.Nova) {
    if (!Atualizador.podeInstalar(this)) {
      AlertDialog.Builder(this)
        .setTitle("Liberar a instalação")
        .setMessage("O Android precisa da sua autorização para este aplicativo instalar a " +
          "versão nova. Na tela que vai abrir, ligue a chave e volte.")
        .setPositiveButton("Abrir a tela") { _, _ -> Atualizador.abrirPermissaoInstalar(this) }
        .setNegativeButton("Depois", null)
        .show()
      return
    }
    Toast.makeText(this, "Baixando a versão nova…", Toast.LENGTH_LONG).show()
    Thread {
      val arq = Atualizador.baixar(this, nova)
      runOnUiThread {
        if (!isFinishing && !isDestroyed) {
          if (arq == null) Toast.makeText(this,
            "Não deu para baixar a versão nova. Confira a internet e tente de novo.",
            Toast.LENGTH_LONG).show()
          else if (!Atualizador.instalar(this, arq)) Toast.makeText(this,
            "Não deu para abrir o instalador do Android.", Toast.LENGTH_LONG).show()
        }
      }
    }.start()
  }

  override fun onBackPressed() {
    /* o Voltar do celular e o Voltar do sistema (modal, formulario, tela anterior) */
    web.evaluateJavascript(
      "(function(){var b=document.getElementById('btVoltar');" +
      "if(b){b.click();return 'sistema';}return 'nada';})();") { res ->
      if (res == null || res.contains("nada")) {
        if (web.canGoBack()) web.goBack() else moveTaskToBack(true)
      }
    }
  }

  override fun onDestroy() {
    if (pagina === web) pagina = null
    if (tela === this) tela = null
    super.onDestroy()
  }
}
