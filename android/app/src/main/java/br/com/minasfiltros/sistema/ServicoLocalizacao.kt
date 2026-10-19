package br.com.minasfiltros.sistema

/* O servico que registra a localizacao com a tela desligada.
   O Android exige o aviso fixo na barra ("Minas Filtros: localizacao ativa") —
   e isso tambem deixa claro ao vendedor que o rastreio esta ligado.

   PARADA (regra dele, 14/10): 10 minutos ou mais dentro de um raio de 100 m.
   O celular reconhece a parada e grava; QUEM CONFERE se houve atendimento, se
   foi na loja ou no almoco e o SISTEMA — a regra fica num lugar so. */

import android.app.*
import android.content.Context
import android.content.Intent
import android.location.Location
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.*
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.*

class ServicoLocalizacao : Service() {

  companion object {
    var ligado = false
    const val CANAL = "mf_loc"
    const val AVISO_ID = 4701
    const val RAIO_PARADA = 100.0      /* metros */
    const val MIN_PARADA = 10          /* minutos */
    const val PASSO_ANDANDO = 60_000L  /* 1 ponto por minuto andando */
    const val PASSO_PARADO = 300_000L  /* 1 a cada 5 minutos parado: economiza banco e bateria */
  }

  private var cliente: FusedLocationProviderClient? = null
  private var pedido: LocationCallback? = null
  private var ultimoGravado = 0L
  private var paradaId: Long? = null
  /* LINHA DE TRABALHO PROPRIA (19/10) — ver a explicacao em `comecar()`: gravar o ponto e
     uma chamada de rede, e o Android PROIBE rede na linha principal. */
  private var linha: android.os.HandlerThread? = null

  private fun iso(t: Long): String {
    val f = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSXXX", Locale.US)
    f.timeZone = TimeZone.getDefault()
    return f.format(Date(t))
  }

  override fun onCreate() {
    super.onCreate()
    startForeground(AVISO_ID, aviso("Registrando a localização para a Minas Filtros."))
    ligado = true
    comecar()
  }

  override fun onStartCommand(i: Intent?, f: Int, id: Int): Int = START_STICKY

  override fun onDestroy() {
    ligado = false
    try { pedido?.let { cliente?.removeLocationUpdates(it) } } catch (e: Exception) { }
    try { linha?.quitSafely() } catch (e: Exception) { }
    linha = null
    super.onDestroy()
  }

  override fun onBind(i: Intent?): IBinder? = null

  private fun aviso(texto: String): Notification =
    NotificationCompat.Builder(this, CANAL)
      .setContentTitle(getString(R.string.loc_titulo))
      .setContentText(texto)
      .setSmallIcon(android.R.drawable.ic_menu_mylocation)
      .setOngoing(true)
      .setOnlyAlertOnce(true)
      .setContentIntent(PendingIntent.getActivity(this, 0,
        Intent(this, TelaPrincipal::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
      .build()

  private fun comecar() {
    cliente = LocationServices.getFusedLocationProviderClient(this)
    /* DEFEITO CORRIGIDO EM 19/10 (teste real com o Renan, Redmi Note 8): aqui havia
       `setMinUpdateDistanceMeters(15f)`, ou seja, o Android so entregava uma localizacao
       nova depois que o aparelho ANDAVA 15 metros. Parado, NENHUMA localizacao chegava,
       `tratar` nunca rodava e o aplicativo nunca chamava o banco — por isso o aviso fixo
       ficava na barra o dia todo e `rastro_pontos` continuava com ZERO pontos, sem erro
       nenhum nos registros do Supabase. E era uma contradicao com a propria regra da casa:
       o que interessa achar e justamente a PARADA de 10 minutos.
       Quem controla o ritmo e o `ultimoGravado` la embaixo (1 ponto por minuto andando,
       1 a cada 5 minutos parado) — a trava por distancia nao tem o que fazer aqui. */
    val req = LocationRequest.Builder(Priority.PRIORITY_BALANCED_POWER_ACCURACY, PASSO_ANDANDO)
      .setMinUpdateIntervalMillis(30_000L)
      .setWaitForAccurateLocation(false)
      .build()
    pedido = object : LocationCallback() {
      override fun onLocationResult(r: LocationResult) {
        r.lastLocation?.let { tratar(it) }
      }
    }
    /* O DEFEITO QUE SEGUROU O RASTREIO ATE 19/10, E ELE ERA O SEGUNDO DA FILA:
       a resposta da localizacao chegava na LINHA PRINCIPAL (`Looper.getMainLooper()`), e
       e nela que `tratar` gravava o ponto — so que gravar o ponto e uma chamada de REDE, e
       o Android PROIBE rede na linha principal (NetworkOnMainThreadException). O `catch`
       generico do Banco engolia essa excecao e devolvia "nao consegui", entao o ponto ia
       para a fila do celular e NUNCA saia — nenhum pedido chegava ao banco, nem com erro,
       e na tela parecia falta de internet. Agora a resposta chega numa linha de trabalho
       propria, onde a rede e permitida. */
    linha = android.os.HandlerThread("mf-localizacao").also { it.start() }
    try {
      cliente!!.requestLocationUpdates(req, pedido!!, linha!!.looper)
      primeiroPonto()
    } catch (e: SecurityException) {
      atualizarAviso("Sem permissão de localização — fale com a gestão.")
      stopSelf()   /* sem permissao de localizacao nao ha o que registrar */
    }
  }

  /* PRIMEIRO PONTO NA HORA (19/10): o modo economico pode levar minutos para a primeira
     entrega, e ate la o vendedor nao tem sinal nenhum de que funcionou. Uma leitura
     forcada, so no arranque, resolve isso e ja prova que o caminho ate o banco esta de pe. */
  private fun primeiroPonto() {
    try {
      /* o resultado tambem e tratado FORA da linha principal, pelo mesmo motivo acima */
      val executor = java.util.concurrent.Executors.newSingleThreadExecutor()
      cliente!!.getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, null)
        .addOnSuccessListener(executor) { l -> if (l != null) tratar(l) }
        .addOnFailureListener(executor) { atualizarAviso("Procurando o sinal de localização…") }
    } catch (e: SecurityException) { }
  }

  private fun tratar(l: Location) {
    val ctx = applicationContext
    if (!Guardado.tem(ctx)) { stopSelf(); return }   /* ninguem logado: nao registra */

    val agora = System.currentTimeMillis()
    val p = Guardado.paradaSalva(ctx)
    var parado = false

    if (p == null) {
      /* comeca a acompanhar um lugar */
      Guardado.salvarParada(ctx, JSONObject()
        .put("lat", l.latitude).put("lng", l.longitude)
        .put("desde", agora).put("id", JSONObject.NULL))
    } else {
      val d = distancia(p.getDouble("lat"), p.getDouble("lng"), l.latitude, l.longitude)
      if (d <= RAIO_PARADA) {
        parado = true
        val min = ((agora - p.getLong("desde")) / 60000L).toInt()
        /* passou dos 10 minutos: abre a parada no banco (uma vez) */
        if (min >= MIN_PARADA && p.isNull("id")) {
          val id = Banco.abrirParada(ctx, JSONObject()
            .put("vendedor", Guardado.nome(ctx))
            .put("loja", Guardado.loja(ctx))
            .put("inicio", iso(p.getLong("desde")))
            .put("lat", p.getDouble("lat")).put("lng", p.getDouble("lng")))
          if (id != null) {
            paradaId = id
            p.put("id", id); Guardado.salvarParada(ctx, p)
            atualizarAviso("Parado há $min min neste local.")
          }
        }
      } else {
        /* saiu do lugar: fecha a parada que estava aberta */
        val min = ((agora - p.getLong("desde")) / 60000L).toInt()
        if (!p.isNull("id")) {
          Banco.fecharParada(ctx, p.getLong("id"), iso(agora), min)
          pedirConferenciaAoSistema()
        }
        paradaId = null
        Guardado.salvarParada(ctx, JSONObject()
          .put("lat", l.latitude).put("lng", l.longitude)
          .put("desde", agora).put("id", JSONObject.NULL))
        atualizarAviso("Em deslocamento.")
      }
    }

    /* ritmo: 1 ponto por minuto andando, 1 a cada 5 minutos parado */
    val passo = if (parado) PASSO_PARADO else PASSO_ANDANDO
    if (agora - ultimoGravado < passo) return
    ultimoGravado = agora

    val ponto = JSONObject()
      .put("vendedor", Guardado.nome(ctx))
      .put("loja", Guardado.loja(ctx))
      .put("em", iso(agora))
      .put("lat", l.latitude).put("lng", l.longitude)
      .put("precisao", l.accuracy)
      .put("velocidade", if (l.hasSpeed()) l.speed else 0f)
      .put("bateria", bateria())
      .put("parado", parado)

    /* tenta gravar; nao conseguiu, guarda no celular e manda depois */
    if (!Banco.gravarPontos(ctx, JSONArray().put(ponto))) {
      Fila.guardar(ctx, ponto)
      val motivo = Banco.ultimoErro
      atualizarAviso(Fila.quantos(ctx).toString() + " ponto(s) esperando" +
        (if (motivo.isEmpty()) " — sem internet." else " — " + motivo))
    } else {
      Fila.enviarTudo(ctx)
      /* O AVISO FIXO PASSOU A PRESTAR CONTAS (19/10): antes dizia so "Registrando a
         localizacao", e foi por isso que ninguem percebeu que nada estava sendo enviado.
         Agora ele mostra a hora do ultimo ponto e quantos sairam hoje — da para conferir
         no celular, sem abrir nada e sem olhar o banco. */
      Guardado.contarEnvio(ctx, agora)
      atualizarAviso("Último registro às " + hora(agora) + " · " +
        Guardado.enviadosHoje(ctx) + " hoje" + (if (parado) " · parado" else " · em deslocamento"))
    }
  }

  private fun hora(t: Long): String {
    val f = SimpleDateFormat("HH:mm", Locale.US)
    f.timeZone = TimeZone.getDefault()
    return f.format(Date(t))
  }

  /* a pagina esta aberta? entao o SISTEMA confere a parada (atendimento, loja, almoco) */
  private fun pedirConferenciaAoSistema() {
    try {
      android.os.Handler(android.os.Looper.getMainLooper()).post {
        TelaPrincipal.pagina?.evaluateJavascript(
          "window.__conferirParadasMF&&window.__conferirParadasMF();", null)
      }
    } catch (e: Exception) { }
  }

  private fun atualizarAviso(texto: String) {
    try {
      (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
        .notify(AVISO_ID, aviso(texto))
    } catch (e: Exception) { }
  }

  private fun bateria(): Int = try {
    val bm = getSystemService(Context.BATTERY_SERVICE) as android.os.BatteryManager
    bm.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY)
  } catch (e: Exception) { -1 }

  /* distancia em metros entre dois pontos (formula do circulo maximo) */
  private fun distancia(la1: Double, lo1: Double, la2: Double, lo2: Double): Double {
    val r = 6371000.0
    val d1 = Math.toRadians(la2 - la1)
    val d2 = Math.toRadians(lo2 - lo1)
    val a = Math.sin(d1 / 2) * Math.sin(d1 / 2) +
      Math.cos(Math.toRadians(la1)) * Math.cos(Math.toRadians(la2)) *
      Math.sin(d2 / 2) * Math.sin(d2 / 2)
    return r * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  }
}
