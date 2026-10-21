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
    /* EM DESLOCAMENTO O RITMO MUDOU (20/10, pedido dele depois de ver o trajeto do Thiago
       cortando quarteirao): era 1 ponto por minuto, e de carro isso pula esquina inteira.
       Agora e 1 a cada 15 segundos OU a cada 30 metros andados, o que vier primeiro.
       PARADO continua como estava: 1 a cada 5 minutos, para nao gastar bateria a toa. */
    const val PASSO_ANDANDO = 15_000L  /* 1 ponto a cada 15 segundos em deslocamento */
    const val PASSO_PARADO = 300_000L  /* 1 a cada 5 minutos parado: economiza banco e bateria */
    const val METROS_ANDANDO = 30.0    /* ...ou a cada 30 metros, o que vier primeiro */
    /* O ENVIO VAI EM LOTE (20/10): gravar 4x mais pontos NAO pode custar 4x mais internet.
       Cada POST sozinho carrega ~1,2 KB de cabecalho (credencial, chave, tipo) para 230
       bytes de ponto. Juntando um minuto de pontos num envio so, o cabecalho e pago uma
       vez — a conta fica em ~0,3 MB por dia em vez de 0,8 MB. Parado, manda na hora. */
    const val LOTE_MS = 60_000L        /* junta os pontos de ate 1 minuto */
    const val LOTE_MAX = 6             /* ...ou ate 6 pontos, o que vier primeiro */
  }

  private var cliente: FusedLocationProviderClient? = null
  private var pedido: LocationCallback? = null
  private var ultimoGravado = 0L
  private var paradaId: Long? = null
  /* o modo de pedido que esta valendo agora: "andando" (GPS) ou "parado" (economico) */
  private var modoAtual = ""
  /* o ultimo ponto GRAVADO, para medir os 30 metros */
  private var ultLat = 0.0
  private var ultLng = 0.0
  /* o lote esperando para ir ao banco */
  private val lote = ArrayList<JSONObject>()
  private var loteDesde = 0L
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
    /* O LOTE NAO SE PERDE (20/10): o que estava esperando para ser enviado vai para a fila
       do celular, que e gravada em disco. Sem isto, o celular que mata o servico levaria
       junto ate um minuto de trajeto. */
    try {
      val ctx = applicationContext
      lote.forEach { Fila.guardar(ctx, it) }
      lote.clear(); loteDesde = 0L
    } catch (e: Exception) { }
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
      pedirLocalizacao("andando")
      primeiroPonto()
    } catch (e: SecurityException) {
      atualizarAviso("Sem permissão de localização — fale com a gestão.")
      stopSelf()   /* sem permissao de localizacao nao ha o que registrar */
    }
  }

  /* O PEDIDO MUDA CONFORME A PESSOA ESTA ANDANDO OU PARADA (20/10).
     ANDANDO: `PRIORITY_HIGH_ACCURACY`, o GPS de verdade. E ele que da precisao de 5 a 15
     metros e preenche a VELOCIDADE — com a antena, medido no banco dele em 20/10, a
     precisao media era de 96 metros no Renan e a velocidade vinha 0,0 em quase todo ponto.
     PARADO: volta ao modo economico, porque parado nao ha caminho para desenhar.
     NAO existe `setMinUpdateDistanceMeters` em lugar nenhum: foi ele que, ate a versao
     1.1, impediu QUALQUER localizacao de chegar com o aparelho parado (v363). Os 30 metros
     do pedido dele sao conferidos aqui embaixo, no nosso proprio codigo, onde a regra da
     parada continua valendo. */

  /* o lembrete de ponto: so em dia util, so quando o sistema disse que falta a batida,
     e UMA vez por dia (se ele ignorar, nao volta). */
  private fun lembrarPontoSePrecisar() {
    try {
      val c0 = applicationContext
      if (!Guardado.precisaBaterPonto(c0)) return
      val c = java.util.Calendar.getInstance()
      val s = c.get(java.util.Calendar.DAY_OF_WEEK)
      if (s == java.util.Calendar.SATURDAY || s == java.util.Calendar.SUNDAY) return
      val f = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US)
      val hoje = f.format(java.util.Date())
      if (Guardado.lembrouPontoEm(c0) == hoje) return
      Guardado.marcarLembrouPonto(c0, hoje)
      Avisos.lembrarPonto(c0)
    } catch (e: Exception) { }
  }
  private fun pedirLocalizacao(modo: String) {
    if (modo == modoAtual) return
    val cl = cliente ?: return
    val lin = linha ?: return
    val andando = modo == "andando"
    val req = LocationRequest.Builder(
        if (andando) Priority.PRIORITY_HIGH_ACCURACY else Priority.PRIORITY_BALANCED_POWER_ACCURACY,
        if (andando) PASSO_ANDANDO else PASSO_PARADO)
      .setMinUpdateIntervalMillis(if (andando) 5_000L else 60_000L)
      .setWaitForAccurateLocation(false)
      .build()
    try {
      pedido?.let { cl.removeLocationUpdates(it) }
      cl.requestLocationUpdates(req, pedido!!, lin.looper)
      modoAtual = modo
    } catch (e: SecurityException) {
      atualizarAviso("Sem permissão de localização — fale com a gestão.")
      stopSelf()
    } catch (e: Exception) { /* um pedido recusado nao pode derrubar o servico */ }
  }

  /* PRIMEIRO PONTO NA HORA (19/10): o modo economico pode levar minutos para a primeira
     entrega, e ate la o vendedor nao tem sinal nenhum de que funcionou. Uma leitura
     forcada, so no arranque, resolve isso e ja prova que o caminho ate o banco esta de pe. */
  private fun primeiroPonto() {
    try {
      /* O RESULTADO VEM NA MESMA LINHA DE TRABALHO, e isto conserta um defeito que a
         propria correcao de 19/10 criou: aqui havia um executor PROPRIO, separado do
         HandlerThread. Eram duas linhas chamando `tratar` ao mesmo tempo — e as duas
         achavam a parada local ainda SEM id, entao as duas abriam a parada no banco.
         Foi assim que o Renan ficou com DUAS paradas iguais, criadas no mesmo segundo
         (19/10 16:43:12), e uma delas nunca mais seria fechada: o celular so guarda o
         id da ultima. Uma linha so, e o `tratar` sincronizado, fecham esse caminho. */
      val exec = java.util.concurrent.Executor { r -> android.os.Handler(linha!!.looper).post(r) }
      cliente!!.getCurrentLocation(Priority.PRIORITY_HIGH_ACCURACY, null)
        .addOnSuccessListener(exec) { l -> if (l != null) tratar(l) }
        .addOnFailureListener(exec) { atualizarAviso("Procurando o sinal de localização…") }
    } catch (e: SecurityException) { }
  }

  /* SINCRONIZADO (20/10): duas localizacoes que chegam no mesmo instante nao podem
     abrir a parada duas vezes. Com uma linha de trabalho so isto ja nao aconteceria,
     mas a trava fica como segunda garantia — abrir parada em dobro deixa registro
     orfao no banco, e orfao nunca fecha. */
  @Synchronized private fun tratar(l: Location) {
    val ctx = applicationContext
    if (!Guardado.tem(ctx)) { stopSelf(); return }   /* ninguem logado: nao registra */

    val agora = System.currentTimeMillis()
    val p = Guardado.paradaSalva(ctx)
    var parado = false
    /* PARADA QUE ATRAVESSA O DIA (20/10): o celular que fica na mesa a noite inteira
       mantinha a MESMA parada aberta — a do Renan comecou 19/10 as 16:00 e nunca
       fechou, porque so fecha quando o aparelho SAI do raio. Parada de mais de 12
       horas e fechada aqui e outra comeca no lugar: assim a gestao ve "parado desde
       ontem" como um registro fechado, e nao como uma parada eterna no banco. */
    if (p != null && agora - p.getLong("desde") > 12L * 3600_000L) {
      if (!p.isNull("id")) {
        Banco.fecharParada(ctx, p.getLong("id"), iso(agora),
          ((agora - p.getLong("desde")) / 60000L).toInt())
        pedirConferenciaAoSistema()
      }
      paradaId = null
      Guardado.salvarParada(ctx, JSONObject()
        .put("lat", l.latitude).put("lng", l.longitude)
        .put("desde", agora).put("id", JSONObject.NULL))
      atualizarAviso("Parada longa encerrada — começando outra.")
      return
    }


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

    /* o modo do GPS acompanha a situacao: andando pede alta precisao, parado economiza */
    pedirLocalizacao(if (parado) "parado" else "andando")

    /* LEMBRETE DE BATER O PONTO (21/10, regra dele): UMA vez por dia, quando a pessoa
       COMECA A SE MOVIMENTAR num dia util sem ter batido a entrada. E mudo (canal
       IMPORTANCE_LOW), some sozinho quando o ponto e batido e, se ela ignorar, nao
       volta naquele dia — nao pode atrapalhar quem esta trabalhando. */
    if (!parado) lembrarPontoSePrecisar()

    /* RITMO: parado, 1 a cada 5 minutos. Andando, 1 a cada 15 segundos OU a cada 30
       metros andados, o que vier primeiro — e a regra que ele pediu, conferida aqui e
       nao por `setMinUpdateDistanceMeters`, que desligaria o caso parado (v363). */
    val passo = if (parado) PASSO_PARADO else PASSO_ANDANDO
    val andou = if (ultLat == 0.0 && ultLng == 0.0) 1e9
                else distancia(ultLat, ultLng, l.latitude, l.longitude)
    val naHora = agora - ultimoGravado >= passo
    val longe = !parado && andou >= METROS_ANDANDO
    if (!naHora && !longe) return
    ultimoGravado = agora
    ultLat = l.latitude; ultLng = l.longitude

    val ponto = JSONObject()
      .put("vendedor", Guardado.nome(ctx))
      .put("loja", Guardado.loja(ctx))
      .put("em", iso(agora))
      .put("lat", l.latitude).put("lng", l.longitude)
      .put("precisao", l.accuracy)
      .put("velocidade", if (l.hasSpeed()) l.speed else 0f)
      .put("bateria", bateria())
      .put("parado", parado)

    /* O LOTE (20/10): andando, o ponto espera ate 1 minuto (ou ate juntar 6) antes de ir
       ao banco. PARADO, vai na hora — ali o ritmo ja e de 5 em 5 minutos e segurar o ponto
       so atrasaria o aviso de parada. E o lote NUNCA fica preso: o que nao for enviado
       agora vai junto do proximo, e no `onDestroy` ele e despejado na fila do celular. */
    lote.add(ponto)
    if (loteDesde == 0L) loteDesde = agora
    val fechar = parado || lote.size >= LOTE_MAX || (agora - loteDesde) >= LOTE_MS
    if (!fechar) {
      atualizarAviso("Último registro às " + hora(agora) + " · " +
        Guardado.enviadosHoje(ctx) + " hoje · em deslocamento")
      return
    }
    val pacote = JSONArray()
    val quantos = lote.size
    lote.forEach { pacote.put(it) }
    lote.clear(); loteDesde = 0L

    /* tenta gravar; nao conseguiu, guarda no celular e manda depois */
    if (!Banco.gravarPontos(ctx, pacote)) {
      for (i in 0 until pacote.length()) Fila.guardar(ctx, pacote.getJSONObject(i))
      val motivo = Banco.ultimoErro
      atualizarAviso(Fila.quantos(ctx).toString() + " ponto(s) esperando" +
        (if (motivo.isEmpty()) " — sem internet." else " — " + motivo))
    } else {
      for (i in 1 until quantos) Guardado.contarEnvio(ctx, agora)
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
