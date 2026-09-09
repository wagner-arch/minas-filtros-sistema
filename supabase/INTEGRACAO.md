# INTEGRAÇÃO — trocar o banco do artifact pelo Supabase

Plano de edição do arquivo `sistema-minas.html`, item a item. Os itens estão
agrupados por assunto; **a ordem de aplicação é outra** e está logo abaixo, na
seção "Ordem de aplicação" — seguir a numeração dos itens deixa o sistema sem
abrir no meio do caminho.

**Nada aqui foi aplicado no HTML.** Este documento é a lista de tarefas; quem
edita é você (ou o Claude, num passo seguinte, com este arquivo na mão).

| | |
|---|---|
| Arquivo alvo | `C:\Users\User\Desktop\Notebook Wagner\MinasFiltros\Projetos\Sistema Minas Filtros Claude\sistema-minas.html` |
| Tamanho conferido | **11.515 linhas**, 1,78 MB (2026-09-09, 14h42) — e **crescendo**: eram 10.943 quando os itens foram escritos e 11.363 quarenta minutos atrás |
| Companheiros | `supabase\schema.sql` (roda no SQL Editor), `supabase\adapter.js` (vai junto do HTML) |
| Biblioteca | `https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.116.0/dist/umd/supabase.js` — **conferida hoje: HTTP 200**, 218 KB, define a global `supabase` (o cdnjs **não** publica o supabase-js) |

## Aviso sobre os números de linha — NÃO CONFIE EM NENHUM DELES

**Os números de linha deste documento apontam para um arquivo que não existe
mais.** Os itens foram escritos quando o `sistema-minas.html` tinha 10.943
linhas — e 10.943 era só até o `</script>` do sistema, nem era o fim do arquivo.
Desde então:

- o `<style id="estiloCelular">` do módulo de celular saiu do fim do arquivo e
  subiu para o cabeçalho (**hoje linhas 504–678**), empurrando **todo o JS**
  para baixo;
- o comportamento do celular (gaveta + barra inferior) continuou no fim, hoje
  nas linhas **11264–11515** — 250 linhas que nenhum inventário viu. É o
  **item 28**, novo;
- e o arquivo **continua sendo editado enquanto este documento é revisado**:
  11.363 linhas às 14h33, 11.515 às 14h42. O deslocamento não é uma constante
  que dá para anotar aqui — às 14h33 era `+184` no arquivo inteiro; às 14h42 já
  era `+204` no começo e `+317` perto do fim.

Renumerar 28 itens à mão a cada mudança é exatamente onde o erro entra, então
**os números ficaram como estavam, e a regra é: procure pelo texto.** Cada item
traz o trecho de hoje completo o bastante para servir de âncora de `Ctrl+F`, e o
texto em si não mudou. Quando precisar do número de verdade, pergunte ao
arquivo:

```
grep -n "async function gravarUsuarios" sistema-minas.html
grep -n '\$("fcSalvar").onclick'        sistema-minas.html
grep -n "function saldoCaixa"           sistema-minas.html
```

> Se você for aplicar isto com o Claude: mande-o **reconferir cada âncora com
> `grep -n` antes de editar**, e nunca abrir o arquivo por número de linha. Vale
> também para os inventários antigos que estiverem na mão.

## Ordem de aplicação — a ordem dos itens NÃO é a ordem de aplicação

Os itens estão numerados por assunto. Aplicados na sequência 1, 2, 3…, **o
sistema não abre**:

- o boot novo do item 3 passa `{aoEstado:bancoMudouEstado}` — identificador
  avaliado na hora. Sem o item 17, é `ReferenceError`, cai no
  `catch(e){db=null;erro(…)}` da linha seguinte e **todo mundo vê "Sem conexão
  com o banco."**, com o Supabase perfeito do outro lado;
- `entrarComSessao()` chama `ouvirRealtime()`, que só nasce no item 20: sem ele
  a senha certa é recusada com "ouvirRealtime is not defined";
- e `montarSelects()` roda antes do item 12a reescrevê-la — a versão de hoje faz
  `su.value=usuarioAtual` num `<select id="usuario">` que o item 11a ainda não
  converteu em `<span>`.

**Aplique nesta ordem:**

| Ordem | Itens | Por quê |
|---|---|---|
| 1º | 1, 1b, 2, 13 | constantes, globais e a lista de usuários vazia — nenhum deles quebra nada sozinho |
| 2º | **17** | `falhaBanco` e `bancoMudouEstado` **antes** de qualquer um que os cite |
| 3º | 15, 16, 18 | `janela()`, `soLoja()`, `carregar()` que propaga o erro, `grava/apaga` que avisam (todos chamam `falhaBanco`) |
| 4º | **20** | `ouvirRealtime()` / `pararRealtime()` — o item 3 chama as duas, e o item 20 usa `janela()`/`soLoja()` do 15 |
| 5º | 11, 12 | `#usuario` vira `<span>`, `montarSelects()` idempotente, troca de loja |
| 6º | **3, 3b** | só agora o boot novo tem tudo o que ele cita |
| 7º | 4–10, 14, 14b | tela de login, Supabase Auth e o fim do `config/usuarios` |
| 8º | 19, **22 antes do 21**, 23–25 | numeração atômica, RH/LGPD e travas de tela (o 21 usa `RH_CARREGADO` e `remDe()`, que nascem no 22) |
| 9º | 26, 27, 28 | produção: demo escondido, backup e o módulo celular |

Entre o 6º e o 7º passo o sistema **abre e loga** (ainda com a tela de login
antiga) — é o ponto natural para parar e testar. Antes disso não adianta
testar: falta metade das funções que o boot cita.

## Mapa da obra (28 itens em 9 blocos)

Números de linha da coluna da direita: **numeração antiga (arquivo de 10.943
linhas)**, para orientação de *onde no arquivo*, nunca para abrir direto. Veja o
aviso acima.

| Bloco | Itens | O que resolve | Linhas (antigas) |
|---|---|---|---|
| A — Ligar o Supabase | 1–3 | o HTML passa a falar com o Postgres | 3168, 3226, 10928 |
| B — Login de verdade | 4–12 | senha no servidor, fim do "troca de operador sem senha" | 498, 519, 521, 4826, 9985, 9991, 9996, 10084, 10649, 10830–10895 |
| C — Perfis no lugar de `config/usuarios` | 13–14b | CPF, salário e foto saem do doc que todo mundo baixa | 3213, 3306, 4525, 10174 |
| D — Carga por loja e erro visível | 15–18 | fim dos limits que congelam; toast que não mente | 3264–3348, 4523, 9247 |
| E — Numeração atômica | 19 | duas abas nunca mais geram o mesmo número | 3441, 3830, 4940, 5545, 8520, 8810 |
| F — Realtime | 20 | pedidos e clientes vivos entre as abas | 9344 |
| G — RH e biometria | 21–23b | LGPD: RH, remuneração e foto em coleções restritas | 4698, 4748, 6479, 6571, 6713, 6787, 6843, 6867, 6897, 10121 |
| H — Travas de tela | 24–25, 28 | `ir()` respeita permissão; reset de senha; barra do celular | 9732, 9979, 10068, 10080 · item 28 por âncora de texto |
| I — Produção | 26–27c | demo escondido, backup diário em JSON, `config/usuarios` apagado e trancado | 2568, 5991–6022, 10089, 2565 |

---

# BLOCO A — LIGAR O SUPABASE

## Item 1 — carregar a biblioteca e o adapter

**Linha 3168–3169** (a última tag externa antes do `<script>` gigante do sistema).

**Hoje:**
```html
<script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js"></script>
<script>
```

**Fica:**
```html
<script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js"></script>
<!-- Supabase: versão fixa de propósito. Atualizar só de caso pensado. -->
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.116.0/dist/umd/supabase.js"></script>
<script src="supabase/adapter.js"></script>
<script>
/* ================= CONEXÃO COM O BANCO =================
   A chave "anon public" é pública por natureza — quem protege os dados é a
   RLS do Postgres, não o segredo da chave. A service_role NUNCA entra aqui
   (o adapter recusa e lança erro). Os dois valores saem do painel:
   Project Settings › API. */
var SUPABASE_URL="https://SEUPROJETO.supabase.co";
var SUPABASE_ANON="SUA_CHAVE_ANON_PUBLICA";
</script>
<script>
```

> O caminho `supabase/adapter.js` é relativo ao HTML. Ao publicar, a pasta
> `supabase/` tem que subir junto (só `adapter.js`; o `schema.sql` fica de fora
> do site — ele não é segredo, mas não tem por que ir).

## Item 1b — `MODO_TESTE` e o gancho de diagnóstico

**No mesmo `<script>` do item 1**, junto de `SUPABASE_URL` e `SUPABASE_ANON`:

```js
/* Ambiente. NÃO usar querystring (`?teste=1`): qualquer pessoa logada digita
   isso na barra de endereço e traz de volta o gerador de dados falsos. O
   hostname o usuário não controla — no GitHub Pages / Firebase nunca é
   localhost. */
var MODO_TESTE=(location.hostname==="localhost"||location.hostname==="127.0.0.1"||location.hostname==="");
```

`location.hostname===""` cobre o arquivo aberto direto do disco (`file://`),
que é como você testa hoje.

**E, no fim do `<script>` gigante do sistema** — entre os **dois** `})();`
seguidos que fecham o arquivo: o de cima fecha a IIFE assíncrona do boot, o de
baixo fecha a IIFE geral (`(function(){ "use strict";`). Ache assim:

```
grep -n "^})();" sistema-minas.html
```
e cole **antes do último** dos dois:

```js
/* Ponte de diagnóstico. TODO o sistema vive dentro de
   `(function(){ "use strict"; … })()`, então `db`, `$` e `perfilLogado` são
   variáveis LOCAIS: no console do navegador elas não existem, e os testes de
   aceite 2, 6 e 7 devolveriam "db is not defined". Fora de produção, e só
   fora, publicamos um ponteiro para elas.
   Os `get` são de propósito: `db` é reatribuída no boot, então copiar o valor
   agora guardaria `null` para sempre. */
if(MODO_TESTE){
  window.mfDebug={
    $:$,
    get db(){return db;},
    get perfil(){return perfilLogado;},
    get loja(){return lojaAtual;}
  };
  console.log("mfDebug disponível (modo teste).");
}
```

> Em produção `MODO_TESTE` é `false` e `window.mfDebug` **não existe** — o
> console volta a não ter atalho nenhum para o banco. Para rodar os testes 6 e
> 7 do aceite (os que provam a LGPD) contra o site publicado sem ligar o modo
> teste, use o `curl` do próprio teste, que fala com o PostgREST com o
> `access_token` da sessão.

## Item 2 — globais: sem loja e sem usuário antes do login

**Linha 3226.**

**Hoje:**
```js
var db=null,lojaAtual="mf",clientes=[],produtos=[],pedidos=[],itens=[],editandoCli=null,editandoProd=null;
```

**Fica:**
```js
/* lojaAtual nasce vazia: quem define é o perfil do usuário, no login.
   usuarioId é o user_id do Supabase Auth — a chave à prova de renomeação. */
var db=null,lojaAtual="",usuarioId=null,perfilLogado=null,
    clientes=[],produtos=[],pedidos=[],itens=[],editandoCli=null,editandoProd=null;
```

## Item 3 — o boot: criar o adapter e só então decidir login ou sessão

> **NÃO aplique este item ainda.** Ele é o 6º da tabela de ordem: cita
> `bancoMudouEstado` (item 17), `ouvirRealtime()` (item 20), `falhaBanco`
> (item 17) e a `montarSelects()` reescrita (item 12a). Aplicado antes deles, o
> sistema **para de abrir** e o sintoma aponta para o lugar errado ("Sem
> conexão com o banco" com o Supabase no ar). Aplique **17, 15, 16, 18, 20, 11
> e 12 primeiro**.

**Linhas 10928–10941** (a IIFE final).

**Hoje:**
```js
(async function(){
  navegacaoBasica();
  try{montarSelects();}catch(e){erro("montarSelects: "+e.message);}
  try{ligar();}catch(e){erro("ligar: "+e.message);}
  try{db=await claude.use("db");}catch(e){db=null;}
  if(!db&&$("offline").hidden)$("offline").hidden=false;
  try{await carregar();}catch(e){erro("carregar: "+e.message);}
  /* só agora as funções existem — é aqui que o menu ganha a forma final */
  try{sincronizarEquipe();aplicarPerfil();}catch(e){console.warn(e);}
  try{montarLogin();estadoDemo();}catch(e){console.warn(e);}
  try{opcoesProduto();render();}catch(e){erro("render: "+e.message);}
  try{ouvirPedidos();}catch(e){console.warn(e);}
  try{var nEq=await sincronizarEquipamentos();if(nEq){renderManut();console.log(nEq+" equipamento(s) criados de vendas antigas");}}catch(e){console.warn(e);}
})();
```

**Fica:**
```js
/* Rotina única de pós-login: vale para quem acabou de digitar a senha e para
   quem só apertou F5 com a sessão ainda válida. Nada de dado carrega antes
   daqui — era esse o furo do sistema antigo. */
async function entrarComSessao(){
  var p=await db.perfil();
  if(!p)throw new Error("Este acesso ainda não tem colaborador cadastrado. Fale com o Administrador.");
  if(p.ativo===false)throw new Error("Acesso desativado.");
  perfilLogado=p;
  usuarioId=p.user_id;
  usuarioAtual=p.nome;                 /* o mesmo nome que já está no histórico */
  lojaAtual=p.loja||LOJAS[0].id;
  db.lojaPadrao=lojaAtual;             /* o adapter carimba docs.loja com isto */

  /* a equipe vem de public.perfis — nunca mais de config/usuarios */
  USUARIOS=(await db.perfis(false)).map(function(r){
    return {id:r.user_id,nome:r.nome,perfil:r.funcao,loja:r.loja,
            ativo:r.ativo!==false,jornada:r.jornada||{}};
  });

  await carregar();                    /* traz funcoes[]; só depois dá para aplicar perfil */
  sincronizarEquipe();
  montarSelects();
  aplicarPerfil();
  $("login").hidden=true;
  alertados={};
  opcoesProduto();render();
  ouvirRealtime();
  estadoDemo();
  try{await db.registrarAcesso();}catch(e){console.warn("ultimo_acesso",e);}
  try{var nEq=await sincronizarEquipamentos();if(nEq){renderManut();}}catch(e){console.warn(e);}
}
function mostrarLogin(aviso){
  $("login").hidden=false;
  montarLogin();
  if(aviso)$("lg_alerta").innerHTML='<div class="note crit"><b>'+esc(aviso)+"</b></div>";
  try{$("lg_email").focus();}catch(e){}
}
(async function(){
  navegacaoBasica();
  try{ligar();}catch(e){erro("ligar: "+e.message);}
  /* 1) cria o cliente. Ainda não fala com o banco — só monta o objeto. */
  try{
    db=window.criarDbSupabase(SUPABASE_URL,SUPABASE_ANON,{aoEstado:bancoMudouEstado});
  }catch(e){db=null;erro("Supabase: "+e.message);}
  if(!db){$("offline").hidden=false;mostrarLogin("Sem conexão com o banco.");return;}
  /* 2) sessão guardada: F5 não pede senha de novo */
  var sessao=null;
  try{sessao=await db.auth.sessao();}catch(e){console.warn("sessao",e);}
  if(sessao){
    try{await entrarComSessao();}
    catch(e){try{await db.auth.sair();}catch(x){}mostrarLogin(e.message);}
  }else{
    mostrarLogin();
  }
  /* 3) sessão que cai em outro aparelho volta para o login aqui também */
  db.auth.aoMudar(function(evento){
    if(evento==="SIGNED_OUT")location.reload();
  });
})();
```

Mudanças de ordem que importam:

- `montarSelects()` saiu do início — ele depende de `lojaAtual` e de `EQUIPE`,
  que só existem depois do perfil (item 12 reescreve a função para poder ser
  chamada duas vezes sem duplicar `<option>`).
- `carregar()`, `render()` e o Realtime só rodam **depois** do login.
- `ouvirPedidos()` virou `ouvirRealtime()` (item 20).

### Item 3b — dois métodos a acrescentar no `adapter.js`

O `schema.sql` cria as RPCs `registrar_acesso()` e
`registrar_consentimento_facial()`.

> **Confira antes de colar: o `adapter.js` de hoje já as expõe.**
> ```
> grep -n "adapter.registrarAcesso\|adapter.registrarConsentimentoFacial\|adapter.perfilGravar" adapter.js
> ```
> Se as três aparecerem, **não cole nada** — este bloco fica só como referência
> do que a versão antiga do adapter não tinha (`adapter.perfilGravar` é a que o
> item 14 usa). Confira também o `select` de `adapter.perfil()`:
> ```
> grep -n "user_id,nome,funcao" adapter.js
> ```
> tem que trazer **`consentiu_facial_em`** e **`jornada`** na lista. Sem essas
> duas colunas o item 23 pede o aceite de LGPD em toda batida e o Cartão de
> Ponto perde a jornada de cada um.

Se faltar alguma, acrescente em `supabase\adapter.js` logo **antes** da linha
`adapter.collection = refColecao;`:

```js
    /* carimba perfis.ultimo_acesso sem abrir update de perfis para o cliente */
    adapter.registrarAcesso = async function () {
      var r = conferir(await sb.rpc("registrar_acesso"), "registrar acesso");
      return r.data || null;
    };

    /* LGPD art. 11 — chamado no aceite da primeira batida com foto */
    adapter.registrarConsentimentoFacial = async function () {
      var r = conferir(await sb.rpc("registrar_consentimento_facial"), "registrar consentimento");
      return r.data || null;
    };
```

---

# BLOCO B — LOGIN DE VERDADE

## Item 4 — a tela de login vira e-mail + senha

**Linhas 498–513.**

**Hoje** (o `<select>` lista a equipe inteira para quem só abriu a página):
```html
    <p class="login-sub" id="lg_sub">Entre com o seu usuário para começar</p>
    <div class="fld"><label for="lg_user">Usuário</label><select id="lg_user"></select></div>
    <div class="fld" style="margin-top:14px"><label for="lg_senha" id="lg_lblSenha">Senha</label>
      <input id="lg_senha" type="password" autocomplete="current-password" placeholder="••••"></div>
    <div class="fld" id="lg_confWrap" style="margin-top:14px" hidden><label for="lg_senha2">Repita a senha</label>
      <input id="lg_senha2" type="password" autocomplete="new-password"></div>
    <div class="fld" style="margin-top:14px"><label for="lg_loja">Loja</label><select id="lg_loja"></select></div>
```

**Fica:**
```html
    <p class="login-sub" id="lg_sub">Entre com o seu e-mail de trabalho</p>
    <div class="fld"><label for="lg_email">E-mail</label>
      <input id="lg_email" type="email" autocomplete="username" inputmode="email" placeholder="voce@minasfiltrosonline.com.br"></div>
    <div class="fld" style="margin-top:14px"><label for="lg_senha" id="lg_lblSenha">Senha</label>
      <input id="lg_senha" type="password" autocomplete="current-password" placeholder="••••"></div>
    <div class="fld" style="margin-top:14px" id="lg_esqueci">
      <button class="btn mut" type="button" id="lg_reset" style="width:100%;justify-content:center">Esqueci minha senha</button></div>
```

Some: `lg_user`, `lg_confWrap`, `lg_senha2` e `lg_loja`. **A loja não se escolhe
mais no login** — ela vem do perfil (`perfis.loja`).

## Item 5 — apagar `hashSenha`

**Linhas 10830–10839.** Apague a função inteira (o próprio comentário dela já
admite que não é criptografia). A senha passa a existir só no Supabase Auth,
com bcrypt, no servidor.

```js
function hashSenha(s){
  /* embaralha a senha para ela não ficar legível no banco.
     Não é criptografia de verdade — a proteção real vem no servidor. */
  var h=5381;
  ...
}
```
→ **removida**. Confira que não sobrou nenhuma chamada:
`grep -n "hashSenha" sistema-minas.html` tem que voltar vazio depois dos itens 5 e 8.

## Item 6 — `montarLogin` para de listar a equipe

**Linhas 10840–10853.**

**Hoje:**
```js
function montarLogin(){
  var s=$("lg_user");s.innerHTML="";
  var ativos=USUARIOS.filter(function(u){return u.ativo!==false;});
  if(!ativos.length)ativos=USUARIOS;
  ativos.forEach(function(u){
    var o=document.createElement("option");o.value=u.nome;
    o.textContent=u.nome+" · "+(u.perfil||"");s.appendChild(o);});
  s.value=usuarioAtual;
  var sl=$("lg_loja");sl.innerHTML="";
  LOJAS.forEach(function(l){var o=document.createElement("option");o.value=l.id;o.textContent=l.nome;sl.appendChild(o);});
  sl.value=lojaAtual;
  try{prepararLogo(function(b,branca){var e=$("loginLogo");if(e&&b)enquadrar(e,b,branca||LOGO);});}catch(e){}
  ajustarLogin();
}
```

**Fica:**
```js
function montarLogin(){
  /* Não listamos mais os colaboradores: a página aberta não precisa contar
     para o mundo quem trabalha aqui nem em que função. */
  var e=$("lg_email");
  try{e.value=localStorage.getItem("mf_ultimo_email")||"";}catch(x){}
  $("lg_senha").value="";
  $("lg_alerta").innerHTML="";
  $("lg_sub").textContent="Entre com o seu e-mail de trabalho";
  $("lg_entrar").textContent="Entrar";
  $("lg_pe").innerHTML="Primeiro acesso ou senha esquecida: use <b>Esqueci minha senha</b> — chega um link no seu e-mail.";
  try{prepararLogo(function(b,branca){var el=$("loginLogo");if(el&&b)enquadrar(el,b,branca||LOGO);});}catch(x){}
}
```

Guardar o último e-mail em `localStorage` é conveniência pura (não é sessão, não
é senha). É o **único** uso de `localStorage` no arquivo — envolva em
`try/catch` porque navegador com dados de site bloqueados lança na leitura.

## Item 7 — apagar `ajustarLogin`

**Linhas 10854–10867.** Apague a função inteira. O "primeiro acesso" deixa de
ser "crie uma senha aqui" e passa a ser o convite por e-mail do Supabase.

## Item 8 — `entrarSistema` com Supabase Auth

**Linhas 10868–10890.**

**Hoje:**
```js
async function entrarSistema(){
  var nome=$("lg_user").value,u=usuarioPor(nome);
  if(!u){$("lg_alerta").innerHTML='<div class="note crit"><b>Usuário não encontrado.</b></div>';return;}
  var s1=$("lg_senha").value;
  if(!u.senha){
    ...
    u.senha=hashSenha(s1);
    await gravarUsuarios();
  } else if(hashSenha(s1)!==u.senha){
    $("lg_alerta").innerHTML='<div class="note crit"><b>Senha incorreta.</b></div>';
    $("lg_senha").value="";$("lg_senha").focus();return;
  }
  usuarioAtual=nome;lojaAtual=$("lg_loja").value;
  try{$("usuario").value=nome;}catch(e){}
  try{$("loja").value=lojaAtual;}catch(e){}
  u.ultimoAcesso=new Date().toISOString();
  await gravarUsuarios();
  $("login").hidden=true;
  alertados={};
  aplicarPerfil();render();
  toast("Bem-vindo, "+nome.split(" ")[0]+".");
}
```

**Fica:**
```js
async function entrarSistema(){
  var email=$("lg_email").value.trim(),senha=$("lg_senha").value;
  if(!email||!senha){
    $("lg_alerta").innerHTML='<div class="note crit"><b>Informe o e-mail e a senha.</b></div>';return;}
  var bt=$("lg_entrar");bt.disabled=true;bt.textContent="Entrando…";
  $("lg_alerta").innerHTML="";
  try{
    await db.auth.entrar(email,senha);
    try{localStorage.setItem("mf_ultimo_email",email);}catch(x){}
    await entrarComSessao();                 /* carrega tudo e abre o sistema */
    toast("Bem-vindo, "+String(usuarioAtual).split(" ")[0]+".");
  }catch(e){
    /* mensagem genérica de propósito: não dizemos se o e-mail existe */
    try{await db.auth.sair();}catch(x){}
    $("lg_alerta").innerHTML='<div class="note crit"><b>'+esc(e.message||"Não foi possível entrar.")+"</b></div>";
    $("lg_senha").value="";$("lg_senha").focus();
  }finally{
    bt.disabled=false;bt.textContent="Entrar";
  }
}
async function redefinirSenha(){
  var email=$("lg_email").value.trim();
  if(!email){$("lg_alerta").innerHTML='<div class="note crit"><b>Escreva o seu e-mail primeiro.</b></div>';return;}
  try{
    await db.auth.redefinirSenha(email,location.href.split("#")[0]);
    /* resposta igual para e-mail que existe e que não existe */
    $("lg_alerta").innerHTML='<div class="note ok"><b>Se este e-mail estiver cadastrado, o link de redefinição já foi enviado.</b> Confira a caixa de entrada e o spam.</div>';
  }catch(e){
    $("lg_alerta").innerHTML='<div class="note crit"><b>'+esc(e.message)+"</b></div>";
  }
}
```

## Item 9 — `sairSistema` sair de verdade

**Linhas 10891–10895.**

**Hoje** (só esconde o overlay; os dados continuam todos em memória):
```js
function sairSistema(){
  $("login").hidden=false;
  montarLogin();
  $("lg_senha").focus();
}
```

**Fica:**
```js
async function sairSistema(){
  try{await db.auth.sair();}catch(e){console.warn("sair",e);}
  /* recarregar é a forma mais honesta de garantir que nada do usuário
     anterior sobrou em memória (arrays, timers, canais do Realtime). */
  location.reload();
}
```

## Item 10 — ligações do login

**Linhas 10084–10088** (dentro de `ligar()`).

**Hoje:**
```js
  $("lg_user").onchange=ajustarLogin;
  $("lg_entrar").onclick=entrarSistema;
  $("lg_senha").onkeydown=function(e){if(e.key==="Enter")entrarSistema();};
  $("lg_senha2").onkeydown=function(e){if(e.key==="Enter")entrarSistema();};
  $("btSair").onclick=sairSistema;
```

**Fica:**
```js
  $("lg_entrar").onclick=entrarSistema;
  $("lg_reset").onclick=redefinirSenha;
  $("lg_email").onkeydown=function(e){if(e.key==="Enter")$("lg_senha").focus();};
  $("lg_senha").onkeydown=function(e){if(e.key==="Enter")entrarSistema();};
  $("btSair").onclick=sairSistema;
```

> `ligar()` roda inteiro no boot: se sobrar um `$("lg_user")` apontando para
> elemento que não existe mais, a linha lança e **todo o resto de `ligar()` não
> é executado** (o sistema abre sem nenhum handler). Confira com
> `grep -n "lg_user\|lg_senha2\|lg_confWrap\|lg_loja" sistema-minas.html` — tem
> que voltar vazio.

## Item 11 — matar a troca de operador sem senha

Três lugares. É o maior buraco de hoje: dois cliques no cabeçalho e qualquer
um vira Administrador.

**11a — HTML, linha 521:**
```html
  <div class="lojasel"><select id="usuario" aria-label="Operador"></select></div>
```
**fica**
```html
  <div class="lojasel"><span id="usuario" class="pill" aria-label="Operador"></span></div>
```

**11b — handler, linhas 10649–10651:**
```js
  $("usuario").onchange=function(){
    usuarioAtual=this.value;alertados={};aplicarPerfil();render();
    toast("Operando como "+usuarioAtual+" · "+perfilDe(usuarioAtual)+".");};
```
→ **apagado**. Trocar de usuário passa a ser: Sair → entrar com outro e-mail.

**11c — `sincronizarEquipe`, linhas 4825–4833:**
```js
function sincronizarEquipe(){
  EQUIPE=USUARIOS.filter(function(u){return u.ativo;}).map(function(u){return u.nome;});
  if(EQUIPE.indexOf(usuarioAtual)<0&&EQUIPE.length)usuarioAtual=EQUIPE[0];
  try{
    var su=$("usuario");su.innerHTML="";
    EQUIPE.forEach(function(n){var o=document.createElement("option");o.textContent=n;su.appendChild(o);});
    su.value=usuarioAtual;
  }catch(e){}
}
```
**fica**
```js
function sincronizarEquipe(){
  EQUIPE=USUARIOS.filter(function(u){return u.ativo;}).map(function(u){return u.nome;});
  /* nada de "se o usuário atual sumiu, vira o primeiro da lista": quem manda
     agora é a sessão do Supabase, não a lista em memória */
  try{$("usuario").textContent=usuarioAtual||"";}catch(e){}
}
```

## Item 12 — a loja vem do perfil

**12a — `montarSelects`, linhas 9984–9993:**

**Hoje** (append sem limpar — chamar duas vezes duplica tudo; e todo mundo vê as 3 lojas):
```js
function montarSelects(){
  var sl=$("loja");LOJAS.forEach(function(l){var o=document.createElement("option");o.value=l.id;o.textContent=l.nome;sl.appendChild(o);});
  var so=$("c_origem");ORIGENS.forEach(function(x){var o=document.createElement("option");o.textContent=x;so.appendChild(o);});
  ["v_prosp","v_vend","v_inst","v_iresp","agendaPessoa"].forEach(function(id){
    var s=$(id);s.innerHTML=(id==="v_inst"||id==="v_iresp"||id==="agendaPessoa")?'<option value="">'+(id==="agendaPessoa"?"Equipe toda":"—")+"</option>":"";
    EQUIPE.forEach(function(n){var o=document.createElement("option");o.textContent=n;s.appendChild(o);});});
  $("v_prosp").value="Wagner";$("v_vend").value="Wagner";
  var su=$("usuario");EQUIPE.forEach(function(n){var o=document.createElement("option");o.textContent=n;su.appendChild(o);});
  su.value=usuarioAtual;
}
```

**Fica:**
```js
function montarSelects(){
  /* pode ser chamada de novo depois do login e na troca de loja: limpa antes */
  var sl=$("loja");sl.innerHTML="";
  var minhas=pode("verTudo")?LOJAS:LOJAS.filter(function(l){return l.id===lojaAtual;});
  minhas.forEach(function(l){var o=document.createElement("option");o.value=l.id;o.textContent=l.nome;sl.appendChild(o);});
  sl.value=lojaAtual;
  sl.disabled=(minhas.length<2);
  var so=$("c_origem");so.innerHTML="";
  ORIGENS.forEach(function(x){var o=document.createElement("option");o.textContent=x;so.appendChild(o);});
  ["v_prosp","v_vend","v_inst","v_iresp","agendaPessoa"].forEach(function(id){
    var s=$(id);s.innerHTML=(id==="v_inst"||id==="v_iresp"||id==="agendaPessoa")?'<option value="">'+(id==="agendaPessoa"?"Equipe toda":"—")+"</option>":"";
    EQUIPE.forEach(function(n){var o=document.createElement("option");o.textContent=n;s.appendChild(o);});});
  /* quem abre a venda já vem preenchido como o próprio usuário, não "Wagner" */
  try{$("v_prosp").value=usuarioAtual;$("v_vend").value=usuarioAtual;}catch(e){}
  try{$("usuario").textContent=usuarioAtual||"";}catch(e){}
}
```

**12b — troca de loja, linha 9996:**

**Hoje** (só re-renderiza; com a carga por loja isso passa a mostrar dados da loja errada):
```js
  $("loja").onchange=function(){lojaAtual=this.value;itens=[];render();toast(nomeLoja());};
```

**Fica:**
```js
  $("loja").onchange=async function(){
    if(!pode("verTudo")){this.value=lojaAtual;toast("Você opera só na "+nomeLoja()+".");return;}
    lojaAtual=this.value;db.lojaPadrao=lojaAtual;itens=[];
    toast("Carregando "+nomeLoja()+"…");
    try{
      await carregar();          /* a carga agora é por loja: precisa recarregar */
      ouvirRealtime();           /* e reassinar o Realtime na loja nova */
      render();toast(nomeLoja());
    }catch(e){
      /* NÃO dá para só avisar e continuar. carregar() atribui coleção por
         coleção, em sequência (linhas 3264 a 3347): se estourar em `titulos`,
         clientes/produtos/pedidos/orcamentos/pontos/caixas já são da loja NOVA
         e titulos/movs/movEst/requisicoes/equipamentos/ordens/notas continuam
         sendo da ANTERIOR. A tela fica com o Contas a Receber de uma loja em
         cima da carteira de clientes de outra — e dá para baixar título da
         loja errada com um banner vermelho como único aviso.
         Recarregar é a única saída honesta (o item 9 usa location.reload() no
         logout pelo mesmo motivo: não sobrar meia sessão em memória). */
      falhaBanco(e);
      toast("Não deu para carregar "+nomeLoja()+" — recarregando a página.");
      setTimeout(function(){location.reload();},1500);
    }
  };
```

---

# BLOCO C — PERFIS NO LUGAR DE `config/usuarios`

## Item 13 — o seed de USUARIOS vira só rede de segurança

**Linhas 3213–3224.**

**Hoje:**
```js
var USUARIOS=[
  {nome:"Wagner",perfil:"Administrador",ativo:true},
  {nome:"Erico",perfil:"Financeiro",ativo:true},
  ...
];
var EQUIPE=USUARIOS.map(function(u){return u.nome;});
function usuarioPor(n){return USUARIOS.filter(function(u){return u.nome===n;})[0]||null;}
```

**Fica:**
```js
/* Lista vazia de propósito: em produção ela é preenchida por public.perfis
   no login (entrarComSessao). Os nomes aqui embaixo ficam só como referência
   do que existe hoje no banco antigo — não são mais a fonte da verdade.
   Wagner · Administrador | Erico · Financeiro | Carol, Veronica Aparecida
   Marques, Franciele Neves · Vendedor | Guilherme Guimarães · Instalador |
   Jaqueline Nunes · Prospector */
var USUARIOS=[];
var EQUIPE=[];
function usuarioPor(n){return USUARIOS.filter(function(u){return u.nome===n;})[0]||null;}
function usuarioPorId(id){return USUARIOS.filter(function(u){return u.id===id;})[0]||null;}
```

## Item 14 — `carregar()` não lê mais `config/usuarios`

**Linhas 3306–3309.**

**Hoje:**
```js
    var us=await db.doc("config/usuarios").get();
    if(us.exists&&us.data()&&us.data().lista&&us.data().lista.length){USUARIOS=us.data().lista;}
    else{await gravarUsuarios();}
    sincronizarEquipe();
```

**Fica:**
```js
    /* A equipe já veio de public.perfis em entrarComSessao(). O antigo
       config/usuarios guardava senha, CPF, salário e foto facial num único
       documento que TODO cliente baixava no boot — ele não é mais lido nem
       gravado. Apagar o documento no banco é o passo 9 do painel (item 27b),
       e o item 27c tranca a recriação por policy. */
    sincronizarEquipe();
```

E **linha 4525**, o gravador correspondente:
```js
async function gravarUsuarios(){if(!db)return;try{await db.doc("config/usuarios").set({lista:USUARIOS});}catch(e){console.warn(e);}}
```
**fica**
```js
/* Substitui o antigo gravarUsuarios(). Identidade e jornada vão para
   public.perfis; RH e biometria têm gravadores próprios (item 21). */
async function gravarPerfil(u){
  if(!db||!u||!u.id)throw new Error("Perfil sem user_id — crie o acesso no painel do Supabase primeiro.");
  await db.perfilGravar({user_id:u.id,nome:u.nome,funcao:u.perfil,loja:u.loja,ativo:u.ativo!==false,
    jornada:{entrada:u.entrada,almocoIni:u.almocoIni,almocoFim:u.almocoFim,saida:u.saida,
             tolerancia:u.tolerancia,bateponto:u.bateponto}});
}
async function gravarRH(userId,dados){await grava("rh",Object.assign({id:userId},dados));}
async function gravarRemuneracao(userId,dados){await grava("remuneracao",Object.assign({id:userId},dados));}
async function gravarFacial(userId,foto,sig){await grava("facial",{id:userId,foto:foto,sig:sig,em:new Date().toISOString()});}
```

> Três coleções e não uma só: `rh` (CPF, RG, CTPS, PIS, endereço, filhos — só
> gestor lê), `remuneracao` (salário, VR e os dois prêmios — **o próprio
> colaborador lê a dele**, é a folha dele) e `facial` (biometria). O `id` de
> cada documento **é o `user_id`**: é por ele que a RLS reconhece o dono
> (`eh_meu_documento`, `schema.sql` item 5). Ver o item 22.

> `db.perfilGravar` **já existe** no `adapter.js` de hoje
> (`grep -n "adapter.perfilGravar" adapter.js`) — é este:
> ```js
>     adapter.perfilGravar = async function (linha) {
>       conferir(await sb.from("perfis").upsert(linha, { onConflict: "user_id" }), "gravar perfil");
>       return true;
>     };
> ```
> Se não encontrar, acrescente junto com o item 3b. A RLS só deixa
> `Administrador` gravar em `perfis` — é isso que queremos.

### Os 8 chamadores de `gravarUsuarios()` — nenhum pode ficar para trás

`grep -n "gravarUsuarios" sistema-minas.html` devolve **9 linhas**: a definição
e **8 chamadas**. Apagar a função e esquecer uma chamada dá `ReferenceError` no
meio de um `async` — e o que vem *depois* do `await` simplesmente não roda
(a tela fica pela metade, sem toast, até o F5). Mantê-la "por segurança" é pior:
ela regrava `{lista:USUARIOS}` em `config/usuarios`, e `config` é lido por
**todo autenticado** (`docs_select_config`, `schema.sql` item 8.1) — o vazamento
volta inteiro.

| Linha (antiga) | Onde | Quem resolve |
|---|---|---|
| 3308 | `carregar()` | item 14, acima |
| **6021** | `gerarDemo` | **item 26d** — a linha sai junto com o bloco 5992–6022 |
| 10073 | `usAdd` | item 25 |
| 10082 | `u_zerarSenha` | item 25 |
| 10145 | `usSalvar` | item 21 |
| **10174** | `fcSalvar` | **item 14b**, logo abaixo |
| 10876, 10885 | `entrarSistema` | item 8 |

Depois de aplicar os itens acima, `grep -n "gravarUsuarios" sistema-minas.html`
tem que voltar **vazio**.

## Item 14b — renomear uma função sem trancar todo mundo para fora

**Linhas 10159–10177 (`$("fcSalvar").onclick`).** É o item que faltava: nenhum
outro fala desta linha.

**Hoje:**
```js
    if(antigo&&antigo!==n)USUARIOS.forEach(function(u){if(u.perfil===antigo)u.perfil=n;});
    await gravarFuncoes();await gravarUsuarios();
```

Dois estragos, um de cada vez:

1. `gravarUsuarios` some no item 14 → `ReferenceError` **depois** do
   `await gravarFuncoes()`. A função é gravada, mas `aplicarPerfil()`,
   `renderFuncoes()`, `renderPermissoes()`, `renderUsuarios()` e o toast (as
   três linhas seguintes) **não rodam**. A tela fica mentindo até o F5.
2. Mesmo corrigindo o (1), a linha só mexe em `USUARIOS` **na memória**.
   `perfis.funcao` no Postgres continua com o nome ANTIGO. No próximo login
   `perfilDe(nome)` devolve o nome antigo, `funcaoPor(antigo)` devolve `null` e
   cai no fallback `funcaoPor("Vendedor")` (linha 9733). Se o Administrador
   renomear a função **`Administrador`**, ele perde Configurações e **não
   conserta mais pelo aplicativo**: `perfis_update_admin` (`schema.sql`, item
   10) exige `minha_funcao()='Administrador'`. Só pelo SQL Editor.

**Fica:**
```js
    await gravarFuncoes();
    if(antigo&&antigo!==n){
      /* renomear a função tem que valer no Postgres também: é de perfis.funcao
         que sai a permissão de cada um no próximo login. */
      try{
        await db.renomearFuncao(antigo,n);
        USUARIOS.forEach(function(u){if(u.perfil===antigo)u.perfil=n;});
        if(perfilLogado&&perfilLogado.funcao===antigo)perfilLogado.funcao=n;
      }catch(e){
        falhaBanco(e);
        toast("A função foi salva, mas os colaboradores continuam com o nome antigo: "+e.message);
        renderFuncoes();return;
      }
    }
```
(a linha `if(antigo&&antigo!==n)USUARIOS.forEach(...)` de cima **sai** — ela
passou para dentro do `try`, depois do banco aceitar.)

**E o método no `adapter.js`**, junto dos outros de perfil (logo depois de
`adapter.perfilGravar = async function`):
```js
    /* Renomeia a função de todo mundo que a usava. Só Administrador passa na
       RLS (perfis_update_admin) — para os demais isto rejeita, e é o certo. */
    adapter.renomearFuncao = async function (antigo, novo) {
      conferir(await sb.from("perfis").update({ funcao: novo }).eq("funcao", antigo),
               "renomear funcao");
      return true;
    };
```

> Vale um aviso na tela antes de deixar renomear `Administrador`: é a única
> função cujo nome está escrito à mão dentro das policies do Postgres
> (`minha_funcao() = 'Administrador'`). Renomeá-la **não** renomeia a policy.

---

# BLOCO D — CARGA POR LOJA E ERRO VISÍVEL

## Item 15 — `carregar()` filtrado por loja e período

**Linhas 3264–3348.** Não é para reescrever a função inteira: é para **trocar
cada `.get()`** acrescentando o filtro, e trocar o `catch` do fim.

Acrescente antes de `async function carregar(){` (linha 3245) o auxiliar de janela:

```js
/* Quanto histórico entra na memória. O resto continua no banco e volta por
   consulta quando alguém pedir — a tela deixa de mentir por corte silencioso. */
var MESES_HISTORICO=18;
function janela(){
  var d=new Date();d.setMonth(d.getMonth()-MESES_HISTORICO);
  return {loja:lojaAtual,de:iso(d)};
}
function soLoja(){return {loja:lojaAtual};}
```

Trocas, uma a uma (as linhas são as de hoje):

| Linha | Hoje | Fica |
|---|---|---|
| 3264 | `col("clientes").limit(500).get()` | `col("clientes").limit(5000).get(soLoja())` |
| 3266 | `col("produtos").limit(500).get()` | `col("produtos").limit(2000).get()` (catálogo é global — sem filtro) |
| 3290 | `col("atendimentos").limit(500).get()` | `col("atendimentos").limit(20000).get(janela())` |
| 3292 | `col("pedidos").limit(500).get()` | `col("pedidos").limit(20000).get(janela())` |
| 3294 | `col("orcamentos").limit(500).get()` | `col("orcamentos").limit(10000).get(janela())` |
| 3296 | `col("fechamentos").limit(200).get()` | `col("fechamentos").limit(500).get(soLoja())` |
| 3298 | `col("ajustes").limit(500).get()` | `col("ajustes").limit(10000).get(soLoja())` |
| 3304 | `col("pontos").limit(2000).get()` | `col("pontos").limit(20000).get(janela())` |
| 3313 | `col("caixas").limit(100).get()` | `col("caixas").limit(200).get(soLoja())` |
| 3321 | `col("centros").limit(200).get()` | `col("centros").limit(500).get()` (global) |
| 3328 | `col("fornecedores").limit(300).get()` | `col("fornecedores").limit(2000).get()` (global) |
| 3330 | `col("titulos").limit(1000).get()` | `col("titulos").limit(50000).get(soLoja())` |
| 3332 | `col("movs").limit(1000).get()` | `col("movs").limit(50000).get(soLoja())` ← **sem janela**, veja o aviso 1 |
| 3334 | `col("movest").limit(2000).get()` | `col("movest").limit(100000).get(soLoja())` |
| 3336 | `col("requisicoes").limit(500).get()` | `col("requisicoes").limit(5000).get(janela())` |
| 3338 | `col("equipamentos").limit(1000).get()` | `col("equipamentos").limit(20000).get(soLoja())` |
| 3340 | `col("ordens").limit(500).get()` | `col("ordens").limit(10000).get(soLoja())` |
| 3342 | `col("notas").limit(300).get()` | `col("notas").limit(10000).get(soLoja())` |

Três avisos que valem mais que a tabela:

1. **`movest`, `titulos` e `movs` não podem ter janela de tempo.** `saldoEm()`
   soma o razão de estoque inteiro, o saldo do caixa depende de todos os
   títulos — e `movs` **é o razão do caixa**: `saldoCaixa()` (linha 4836) faz
   `s = +c.saldo` e soma **todo** movimento com `m.data >= c.dataSaldo`. Os
   caixas semeados no primeiro boot ficam com `dataSaldo` congelado naquele dia
   (linha 3318, `nc.dataSaldo=hojeISO()`) e ninguém mexe nisso depois: passados
   18 meses, os movimentos entre `dataSaldo` e `hoje−18m` deixam de ser
   carregados e **o saldo da tela de Caixas e do Fluxo fica errado, sem nenhum
   aviso**. Cortar linha antiga nas três não "esconde histórico", **corrompe
   saldo**. Por isso ali é `soLoja()`, sem `de`.
   (Se um dia `movs` pesar demais, o caminho não é a janela de tempo: é
   guardar o saldo consolidado por caixa numa data de corte — mover o
   `dataSaldo` para frente junto com o valor — e só então cortar o que vier
   antes dela.)
2. O adapter **pagina sozinho** (`.range()` de 1000 em 1000): `limit(100000)`
   volta completo, não é mentira como no PostgREST cru.
3. As leituras saem **ordenadas por id**, então a lista é estável entre um F5 e
   outro (hoje "quais 500 voltam" é indefinido).

**E o fim da função, linha 3348:**

**Hoje** (uma falha na terceira coleção deixa as quinze seguintes vazias e o
sistema abre parecendo normal):
```js
  }catch(e){console.warn("db",e);}
}
```
**Fica:**
```js
  }catch(e){
    console.warn("db",e);
    falhaBanco(e);       /* banner persistente, não some sozinho */
    throw e;             /* quem chamou decide: o boot mostra o erro, a troca de loja avisa */
  }
}
```

E os blocos que **re-semeiam** quando a lista vem vazia (produtos 3268, caixas
3315, centros 3323) ganham uma trava — hoje um erro de leitura faz o boot
duplicar caixas e centros:

```js
    if(!produtos.length&&db.online){ ... }   /* só semeia se o banco respondeu de verdade */
```

## Item 16 — `grava()` e `apaga()` param de engolir erro

**Linhas 4523–4524.**

**Hoje:**
```js
async function grava(colecao,obj){if(db){try{await col(colecao).doc(obj.id).set(obj);}catch(e){console.warn(colecao,e);}}}
async function apaga(colecao,id){if(db){try{await col(colecao).doc(id).delete();}catch(e){console.warn(e);}}}
```

**Fica:**
```js
/* Antes estes dois helpers engoliam TODA falha de gravação: o await sempre
   "dava certo" e o toast de sucesso era incondicional — o usuário via
   "Pedido 20845 registrado" com o banco fora do ar. Agora eles avisam e
   propagam; quem chama decide o que fazer com a tela. */
async function grava(colecao,obj){
  if(!db)throw new Error("Sem conexão com o banco — nada foi salvo.");
  try{await col(colecao).doc(obj.id).set(obj);}
  catch(e){falhaBanco(e);throw e;}
}
async function apaga(colecao,id){
  if(!db)throw new Error("Sem conexão com o banco — nada foi apagado.");
  try{await col(colecao).doc(id).delete();}
  catch(e){falhaBanco(e);throw e;}
}
```

Os outros gravadores de `config/*` (linhas 4036 `gravarEmpresa`, 4526
`gravarOrigens`, 6941 `gravarMetas`, 7021 `gravarCelebracoes`, 7896/7897/7898
`gravarFechamento`/`gravarAjuste`/`gravarFaixas`, 9284 `gravarPedido`, 9373/9376/9419/9711
`gravarTipos`/`gravarCanais`/`gravarMotivos`/`gravarFuncoes`, 10735 `gravarFormas`)
seguem o mesmo molde: tire o `try/catch` que só faz `console.warn`.

## Item 17 — o banner de falha

Acrescente logo depois de `function erro(msg)` (linha 10924):

```js
/* Banner persistente de falha do banco. Diferente do toast, ele NÃO some
   sozinho — some quando a conexão volta (o adapter chama bancoMudouEstado). */
function falhaBanco(e){
  var b=$("offline");b.hidden=false;
  b.textContent=
    (e&&e.ehSessao)?"Sua sessão expirou. Entre de novo — o que você fizer agora não está sendo salvo."
   :(e&&e.ehRLS)  ?"O banco recusou: "+(e.message||"você não tem permissão para isto.")
   :(e&&e.ehRede) ?"Sem conexão com o banco. O que você fizer agora NÃO está sendo salvo."
   :"Falha ao salvar: "+((e&&e.message)||"erro desconhecido")+" — confira antes de continuar.";
}
function bancoMudouEstado(ok){
  if(ok){$("offline").hidden=true;toast("Conexão com o banco restabelecida.");}
  else falhaBanco(db&&db.ultimoErro&&db.ultimoErro.erro);
}
```

### A regra dos 80 pontos de gravação

`grep -c "await grava(" sistema-minas.html` → **80**. O padrão a aplicar em
todos é o mesmo, em três linhas:

```js
/* ANTES */
lista.push(obj);
await grava("colecao",obj);
toast("Registro salvo.");

/* DEPOIS */
try{ await grava("colecao",obj); }
catch(e){ toast("NÃO foi salvo — veja o aviso no topo."); return; }
lista.push(obj);                    /* memória só depois que o banco aceitou */
toast("Registro salvo.");
```

Três exemplos que valem por todos (aplique o mesmo raciocínio ao resto):

**17a — `confirmarBaixa`, linhas 5163–5175** (hoje o título pode ficar pago sem
o movimento no caixa e o toast diz que deu tudo certo):
```js
  bxTit.status="pago";await grava("titulos",bxTit);
  movs.push(m);await grava("movs",m);
  toast("Baixa registrada e lançada no caixa.");
```
→
```js
  try{
    bxTit.status="pago";await grava("titulos",bxTit);
    await grava("movs",m);movs.push(m);
  }catch(e){
    bxTit.status="aberto";                       /* desfaz na memória */
    toast("A baixa NÃO foi registrada.");return;
  }
  toast("Baixa registrada e lançada no caixa.");
```

**17b — `salvarMov` (transferência), linhas 5191–5203**: as duas pernas têm que
ir juntas. Enquanto não virar RPC transacional, grave a saída, e se a entrada
falhar, **apague a saída** e avise.

**17c — `darEntrada`, linhas 5724–5788**: mais de 50 writes soltos. Candidata
número 1 a virar RPC no Postgres numa fase 2. Por ora, envolva o laço todo num
`try` e, na falha, mostre exatamente **em que item** parou.

## Item 18 — o único toast antes do await

**Linha 9247.**

**Hoje** (`gravarPedido` sem `await` — o toast é síncrono e a gravação fica solta):
```js
    gravarPedido(p);toast("Alterações descartadas — venda reencerrada.");renderPedDet();render();});
```
**Fica:**
```js
    try{await gravarPedido(p);}catch(e){toast("As alterações NÃO foram descartadas no banco.");return;}
    toast("Alterações descartadas — venda reencerrada.");renderPedDet();render();});
```
> O handler é `on("pd_desistir",function(){...})` — troque para
> `on("pd_desistir",async function(){...})`.

---

# BLOCO E — NUMERAÇÃO ATÔMICA

Hoje pedido, orçamento e OS usam `array.filter(loja).length + base`. Isso
**conta documentos em memória**: duas abas geram o mesmo número, apagar um
registro reusa número já emitido, e passando do limit o contador congela.
A RPC `proximo_numero(loja,tipo)` resolve os três de uma vez.

## Item 19a — pedido

**Linha 3830** (dentro de `salvarPedido`), junto com a correção de toast do item 17.

**Hoje:**
```js
  var ped={id:uid(),loja:lojaAtual,numero:(pedidos.filter(function(p){return p.loja===lojaAtual;}).length+20801),
    data:new Date().toISOString().slice(0,10),cliente:cli?cli.nome:"—",clienteId:cli?cli.id:"",
    prospector:$("v_prosp").value,vendedor:$("v_vend").value,instalador:$("v_inst").value,
```
e, na **linha 3838–3839**:
```js
  pedidos.push(ped);
  if(db){try{await col("pedidos").doc(ped.id).set(ped);}catch(e){console.warn(e);}}
```

**Fica:**
```js
  var ped={id:uid(),loja:lojaAtual,numero:0,
    data:new Date().toISOString().slice(0,10),cliente:cli?cli.nome:"—",clienteId:cli?cli.id:"",
    prospector:$("v_prosp").value,vendedor:$("v_vend").value,instalador:$("v_inst").value,
    vendedorId:usuarioId,criadoPorId:usuarioId,
```
e:
```js
  /* o número sai do banco, travado por linha: duas abas nunca recebem o mesmo */
  try{
    ped.numero=await db.proximoNumero(lojaAtual,"pedido");
    await col("pedidos").doc(ped.id).set(ped);
  }catch(e){
    falhaBanco(e);toast("A venda NÃO foi registrada: "+e.message);return;
  }
  pedidos.push(ped);
```

## Item 19b — orçamento

**Linhas 8809–8811.**
```js
  var o=editandoOrc||{id:uid(),loja:lojaAtual,situacao:"aberto",
    numero:(orcamentos.filter(function(x){return x.loja===lojaAtual;}).length+1001),
    data:iso(new Date())};
```
**fica**
```js
  var o=editandoOrc||{id:uid(),loja:lojaAtual,situacao:"aberto",numero:0,
    data:iso(new Date()),criadoPorId:usuarioId};
  if(!o.numero){
    try{o.numero=await db.proximoNumero(lojaAtual,"orcamento");}
    catch(e){falhaBanco(e);toast("Não deu para gerar o número da proposta.");return null;}
  }
```

## Item 19c — ordem de serviço

**Linhas 8519–8521.**
```js
  var o=editandoOS||{id:uid(),loja:lojaAtual,
    numero:(ordens.filter(function(x){return x.loja===lojaAtual;}).length+3001),
    historico:[],criadoEm:hojeISO(),criadoPor:usuarioAtual};
```
**fica**
```js
  var o=editandoOS||{id:uid(),loja:lojaAtual,numero:0,
    historico:[],criadoEm:hojeISO(),criadoPor:usuarioAtual,criadoPorId:usuarioId};
  if(!o.numero){
    try{o.numero=await db.proximoNumero(lojaAtual,"os");}
    catch(e){falhaBanco(e);toast("Não deu para gerar o número da OS.");return null;}
  }
```

## Item 19d — código do cliente

**Linhas 3441–3446.**

**Hoje** (`Math.max` do sufixo — melhor que os outros, mas ainda racy e preso ao limit):
```js
function proxCodigo(){
  var pre={mf:"MF",wf:"WF",dv:"DV"}[lojaAtual]||"CL";
  var n=clientes.filter(function(c){return c.loja===lojaAtual;}).reduce(function(a,c){
    var m=/(\d+)$/.exec(c.codigo||"");return Math.max(a,m?+m[1]:0);},1000);
  return pre+"-"+String(n+1).padStart(5,"0");
}
```
**fica**
```js
async function proxCodigo(){
  var pre={mf:"MF",wf:"WF",dv:"DV"}[lojaAtual]||"CL";
  var n=await db.proximoNumero(lojaAtual,"cliente");   /* base 1001 = MF-01001 */
  return pre+"-"+String(n).padStart(5,"0");
}
```

**Atenção — a chamada da linha 3483 tem que sair.** Hoje o código é gerado ao
**abrir** o formulário; com a RPC isso **queima um número toda vez que alguém
abre a tela e desiste**.

Linha 3483:
```js
  $("c_codigo").value=v.codigo||proxCodigo();
```
**fica**
```js
  $("c_codigo").value=v.codigo||"";
  $("c_codigo").placeholder="gerado ao salvar";
```

E na linha 10463 (`cliSalvar`), que passa a ser o único ponto que consome número:
```js
    if(!c.codigo)c.codigo=$("c_codigo").value||proxCodigo();
```
**fica**
```js
    if(!c.codigo){
      try{c.codigo=await proxCodigo();}
      catch(e){falhaBanco(e);toast("Não deu para gerar o código do cliente.");return;}
    }
```
Idem na linha **9574** (lead criado pelo atendimento): `codigo:await proxCodigo()`
— a função que o contém já é `async`. E nas linhas **6085** e **6101** (gerador
de demo), que também viram `await`.

## Item 19e — código do fornecedor

Duas cópias da mesma fórmula, e nenhuma filtra por loja (fornecedor é global).

**Linha 4940:**
```js
  $("fn_codigo").value=v.codigo||("FOR-"+String(fornecedores.length+1001));
```
**fica** (mesmo motivo do cliente — não gerar ao abrir):
```js
  $("fn_codigo").value=v.codigo||"";
  $("fn_codigo").placeholder="gerado ao salvar";
```
e no `fnSalvar` (linha 10251) antes de gravar:
```js
    if(!f.codigo)f.codigo="FOR-"+String(await db.proximoNumero("global","fornecedor"));
```

**Linha 5545** (import de XML de NF-e cria fornecedor novo):
```js
    f={id:uid(),codigo:"FOR-"+String(fornecedores.length+1001),tipo:"Pessoa Jurídica",
```
**fica**
```js
    f={id:uid(),codigo:"FOR-"+String(await db.proximoNumero("global","fornecedor")),tipo:"Pessoa Jurídica",
```

> O fornecedor é um **contador único das três lojas** — o cadastro é
> compartilhado. `proximo_numero()` sabe disso: para os tipos globais ela
> ignora o `p_loja` que você mandar e usa `'*'`. Ou seja, o `"global"` das duas
> chamadas acima funciona, mas a linha na tabela `numeradores` é
> **`('*','fornecedor', …)`** — semear `('global','fornecedor', …)` cria uma
> linha que ninguém lê. Veja o passo 6 do painel.

---

# BLOCO F — REALTIME

## Item 20 — `ouvirPedidos` vira `ouvirRealtime`

**Linhas 9344–9357.**

**Hoje** (uma coleção só, sem `unsubscribe`, sem tratamento de erro, e o snapshot
substitui `pedidos` por **todas as lojas** — o que faz a numeração antiga saltar):
```js
function ouvirPedidos(){
  if(!db)return;
  try{
    col("pedidos").onSnapshot(function(snap){
      pedidos=snap.docs.map(function(d){var o=d.data()||{};o.id=d.id;return o;});
      try{renderPedidos();}catch(e){}
      if(pedAberto){
        var f=pedidos.filter(function(x){return x.id===pedAberto.id;})[0];
        if(f){pedAberto=f;try{renderPedDet();}catch(e){}}
      }
      checarPendencias();
    });
  }catch(e){console.warn("onSnapshot pedidos",e);}
}
```

**Fica:**
```js
var canais=[];
function pararRealtime(){
  canais.forEach(function(f){try{f();}catch(e){}});
  canais=[];
}
function ouvirRealtime(){
  if(!db||!lojaAtual)return;
  pararRealtime();                       /* troca de loja: reassina do zero */
  var op={filtros:janela(),aoFalhar:function(e){falhaBanco(e);}};

  canais.push(col("pedidos").onSnapshot(function(snap){
    pedidos=snap.docs.map(function(d){var o=d.data()||{};o.id=d.id;return o;});
    try{renderPedidos();}catch(e){}
    if(pedAberto){
      var f=pedidos.filter(function(x){return x.id===pedAberto.id;})[0];
      if(f){pedAberto=f;try{renderPedDet();}catch(e){}}
    }
    checarPendencias();
  },op));

  /* clientes: a vendedora cadastra na loja e o instalador vê na hora */
  canais.push(col("clientes").onSnapshot(function(snap){
    clientes=snap.docs.map(function(d){var o=d.data()||{};o.id=d.id;return o;});
    try{renderClientes();}catch(e){}
  },{filtros:soLoja(),aoFalhar:function(e){falhaBanco(e);}}));

  /* TÍTULOS FICAM DE FORA NA FASE 1 — veja o porquê logo abaixo. */
}
```

### Por que `titulos` não entra no Realtime

Era a terceira assinatura do rascunho e ela **não paga o que custa**:

- `onSnapshot` do adapter não recebe um delta: a cada evento ele **refaz o
  `get()` inteiro** da coleção (`assinarColecao` → `buscarColecao`), e sem
  `limite` o alvo é `Infinity` — pagina de 1000 em 1000 até o fim;
- uma venda em 12x grava **12 títulos** (`gerarReceberDoPedido`, linha 5059) e
  `darEntrada` grava **50+**. Cada rajada, mesmo com o debounce de 150 ms, faz
  **toda aba aberta** rebaixar a coleção de títulos da loja — que o próprio
  item 15 dimensiona em até 50.000 documentos jsonb;
- com 3 lojas e 7 pessoas, isso vira o gargalo do sistema e a conta de egress
  do projeto — para atualizar uma tela que quase ninguém está olhando na hora.

**Em troca, dê um recarregamento na entrada da tela.** Hoje `renderReceber()` e
`renderPagar()` desenham a partir do array `titulos` em memória, que só é
preenchido por `carregar()` — sem Realtime e sem isto, o financeiro veria a
baixa do colega só depois de um F5. No `ir()` (item 24), depois da troca de
tela:

```js
  /* Contas a Receber/Pagar não têm Realtime (veja o item 20): recarrega a
     coleção ao entrar na tela, que é quando o número precisa estar certo. */
  if(s==="receber"||s==="pagar"){
    (async function(){
      try{
        var q=await col("titulos").limit(50000).get(soLoja());
        titulos=q.docs.map(function(d){var o=d.data()||{};o.id=d.id;return o;});
        renderReceber();renderPagar();
      }catch(e){falhaBanco(e);}
    })();
  }
```

Se um dia quiser o tempo real ali, entre com filtro apertado e limite
explícito, nunca a coleção toda:

```js
  /* SÓ SE PRECISAR — o mês corrente, não os 50.000 títulos da loja */
  canais.push(col("titulos").onSnapshot(function(snap){
    titulos=snap.docs.map(function(d){var o=d.data()||{};o.id=d.id;return o;});
    try{renderReceber();renderPagar();}catch(e){}
  },{filtros:{loja:lojaAtual,de:iso(new Date(new Date().getFullYear(),new Date().getMonth(),1))},
     limite:5000,aoFalhar:function(e){falhaBanco(e);}}));
```

> **`renderTitulos` não existe** no `sistema-minas.html`. As funções são
> `renderReceber()` (linha 5043) e `renderPagar()` (5052) — e como o callback
> fica dentro de `try{}catch(e){}`, o `ReferenceError` seria **engolido**: o
> array `titulos` trocaria e as duas telas continuariam mostrando os dados
> velhos até o F5, sem sintoma nenhum. Confira `renderClientes` e
> `renderPedidos` da mesma forma antes de colar
> (`grep -n "^function render" sistema-minas.html`) — essas duas existem.
>
> O `onSnapshot` do adapter devolve a lista completa a cada evento, exatamente
> como o banco antigo fazia; a assinatura devolve o `unsubscribe`, que agora é
> guardado em `canais` e usado na troca de loja e no logout.

---

# BLOCO G — RH E BIOMETRIA (LGPD)

O `config/usuarios` de hoje é baixado por todo cliente **antes de qualquer
senha**, e leva junto CPF, RG, endereço, filhos, salário, CTPS/PIS e a foto
facial em base64 (~50–70 KB). A RLS do `schema.sql` já trata `rh`,
`remuneracao`, `facial` e `ponto_fotos` como coleções restritas: **escrita** só
para `Administrador`/`Financeiro`, e leitura idem, com **três exceções** — o
colaborador lê a própria biometria, insere a própria foto de ponto e lê a
própria remuneração (item 22).

## Item 21 — o cadastro de colaborador em quatro gravações

**Linhas 10121–10147 (`usSalvar`).**

> **Aplique o item 22 antes deste.** É lá que nascem `RH`, `REM`, `FACIAL`,
> `RH_CARREGADO`, `carregarRH()`, `rhDe()` e `remDe()` — o código abaixo usa os
> sete.

**Hoje** (tudo num objeto só, gravado no documento que todo mundo lê):
```js
    u.nome=n;u.perfil=$("u_perfil").value;u.ativo=($("u_ativo").value==="sim");
    CAMPOS_US.forEach(function(k){var e=$("u_"+k);if(e)u[k]=e.value.trim?e.value.trim():e.value;});
    ["salario","vr","assiduidade","desempenho"].forEach(function(k){u[k]=parseFloat($("u_"+k).value)||0;});
    ...
    u.facial=usFacial;u.facialSig=usFacialSig;
    ...
    await gravarUsuarios();sincronizarEquipe();aplicarPerfil();
```

**Fica:**
```js
    u.nome=n;u.perfil=$("u_perfil").value;u.ativo=($("u_ativo").value==="sim");
    u.loja=$("u_loja").value||u.loja||lojaAtual;
    /* Jornada CONTINUA no objeto em memória: não é dado sensível e mora em
       perfis.jornada, justamente para o Cartão de Ponto funcionar sem abrir
       'rh' (item 22). */
    ["entrada","almocoIni","almocoFim","saida"].forEach(function(k){u[k]=$("u_"+k).value;});
    u.tolerancia=parseInt($("u_tolerancia").value,10);if(isNaN(u.tolerancia))u.tolerancia=2;
    u.bateponto=$("u_bateponto").value;

    /* RH, remuneração e filhos são montados DIRETO DOS CAMPOS e NÃO voltam
       para `u`. `u` é um item de USUARIOS — a lista que a tela inteira usa e
       que qualquer gravador de config/usuarios levaria de volta para o
       documento que TODO autenticado lê. Enquanto CPF, RG, endereço, CTPS,
       PIS, filhos e salário estiverem dentro de USUARIOS, o vazamento que
       esta migração existe para matar volta pela primeira brecha. */
    var rh={nome:n};
    CAMPOS_US.forEach(function(k){var e=$("u_"+k);if(e)rh[k]=(e.value.trim?e.value.trim():e.value);});
    rh.temfilhos=$("u_temfilhos").value;
    rh.filhos=(rh.temfilhos==="sim")?usFilhos.filter(function(f){return f.nome||f.nasc;}):[];
    var rem={nome:n};
    ["salario","vr","assiduidade","desempenho"].forEach(function(k){rem[k]=parseFloat($("u_"+k).value)||0;});

    /* TRAVA CONTRA APAGAR RH REAL. grava() é upsert integral, sem merge: se o
       formulário foi preenchido antes de carregarRH() terminar (ou para quem
       não tem permissão de ler 'rh'), os campos vieram em branco e salvar
       agora ZERA CPF, RG, endereço, filhos, CTPS, PIS, salário e VR no banco.
       Não há de onde recuperar — o config/usuarios antigo é apagado no passo 9
       do painel. */
    if(!RH_CARREGADO){
      $("u_alerta").innerHTML='<div class="note crit"><b>O cadastro de RH ainda não carregou.</b> '+
        "Feche e abra este colaborador de novo antes de salvar — salvar agora apagaria CPF, endereço e salário.</div>";
      return;
    }
    try{
      /* 1) identidade, loja e jornada — todo autenticado pode ler */
      await gravarPerfil(u);
      /* 2) RH — coleção restrita: só Administrador e Financeiro leem */
      await gravarRH(u.id,rh);
      /* 3) remuneração — restrita para escrita, mas o dono lê a dele */
      await gravarRemuneracao(u.id,rem);
      /* 4) biometria — coleção restrita própria */
      if(usFacial)await gravarFacial(u.id,usFacial,usFacialSig);
      RH[u.id]=rh;REM[u.id]=rem;          /* os mapas em memória acompanham */
      if(usFacial)FACIAL[u.id]={foto:usFacial,sig:usFacialSig};
    }catch(e){
      toast("O cadastro NÃO foi salvo: "+e.message);return;
    }
    /* memória só DEPOIS que o banco aceitou (regra do item 17). O
       `USUARIOS.push` antes do try deixava um colaborador fantasma na lista
       toda vez que gravarPerfil recusasse — e ela recusa sempre para quem
       ainda não tem acesso criado no painel (item 25). */
    if(!editandoUs)USUARIOS.push(u);
    sincronizarEquipe();aplicarPerfil();
```

O bloco de renomeação das linhas 10138–10144 (`nomeAntigo`) pode **sair**: com
`user_id` como chave, renomear deixa de precisar reescrever histórico. Se quiser
manter por enquanto, deixe — mas ele hoje só muda a memória, sem regravar nada,
então é ilusão de correção. (Renomear **função** é outra história e tem item
próprio: 14b.)

**Falta um campo no formulário:** `u_loja`. Acrescente no HTML do cadastro, ao
lado de `u_perfil`, um `<select id="u_loja">` com as três lojas — hoje
`USUARIOS` não tem loja nenhuma, e é dela que sai a `lojaAtual` de cada pessoa
(item 3, `lojaAtual=p.loja||LOJAS[0].id`).

O campo fica ao lado de `u_perfil` (**linha 2344**):
```html
            <div class="fld"><label for="u_loja">Loja</label><select id="u_loja"></select></div>
```

**E precisa ser POPULADO** — um `<select>` sem `<option>` devolve `""` para
sempre, e a linha `u.loja=$("u_loja").value||u.loja||lojaAtual;` acima nunca
conseguiria **mudar** a loja de ninguém. Nada mais no documento preenche esse
select: `montarSelects()` (item 12a) não o toca, e `u_perfil` só se preenche
sozinho porque `abrirUsuario` tem o `funcoes.forEach` da linha 4755. Em
`abrirUsuario`, **logo depois** de `sp.value=u.perfil||"Vendedor";`
(**linha 4756**):
```js
  var sj=$("u_loja");sj.innerHTML="";
  LOJAS.forEach(function(l){var o=document.createElement("option");o.value=l.id;o.textContent=l.nome;sj.appendChild(o);});
  sj.value=u.loja||lojaAtual;
```

## Item 22 — ler RH e remuneração sob demanda

O `USUARIOS.forEach` de `renderUsuarios` lê `u.facial`, `u.email||u.tel`,
`u.salario`, `u.assiduidade` e `u.desempenho` direto da lista. Nenhum desses
campos vem mais no boot.

### A decisão que faltava: o colaborador VÊ a própria remuneração

`renderPonto` monta, **para o próprio colaborador**, cinco cartões — "Salário
fixo", "Vale refeição", "Assiduidade", "Desempenho" e "Total do mês" — a partir
de `totalRemuneracao(quem,c)` e `premioAssiduidade(quem,c)`. Se esses dois
passarem a ler `rh`, os cinco cartões viram **R$ 0,00** para Carol, Verônica,
Franciele, Guilherme e Jaqueline: `rh` é fechado a Administrador/Financeiro por
decisão do `schema.sql` ("'rh' fica de fora de proposito: CPF, RG, CTPS e
endereco so para gestor"). Zero silencioso é pior que "sem acesso" — vira "o
sistema novo apagou meu salário" no primeiro dia.

**A regra é esta: a folha é dele, ele vê a dele; CPF, RG, CTPS, endereço e
filhos continuam só para o gestor.** Se estiver errado, o que muda é a policy
`docs_select_minha_remuneracao` (e aí o item passa a mandar **apagar** os cinco
cartões de `renderPonto`, não deixá-los mostrando zero).

Por isso o `schema.sql` já traz **três** coleções restritas separadas, e não uma
só — é o que permite abrir o contracheque sem abrir o cadastro:

| Coleção | O que guarda | Quem lê |
|---|---|---|
| `rh` | CPF, RG, CTPS, PIS, endereço, filhos, admissão | só `sou_gestor_rh()` = Administrador, Financeiro |
| `remuneracao` | `salario`, `vr`, `assiduidade`, `desempenho` | o gestor **e o próprio dono** (`docs_select_minha_remuneracao`) |
| `facial` | foto de referência da conferência | o gestor **e o próprio dono** (`docs_select_minha_biometria`) |

O `id` do documento **é o `user_id`** nas três — é por ele que
`eh_meu_documento()` reconhece o dono. Escrita nas três continua só para o
gestor.

### O código

```js
/* Espelha sou_gestor_rh() do Postgres (schema.sql item 5). NÃO use ehGestor()
   aqui: ehGestor() é pode("verTudo"), que o Gerente também tem — e para ele a
   RLS devolveria 0 linhas SEM ERRO NENHUM, que é justamente o zero silencioso
   que queremos evitar. */
function ehGestorRH(){
  var f=perfilLogado&&perfilLogado.funcao;
  return f==="Administrador"||f==="Financeiro";
}

var RH={},REM={},FACIAL={},RH_CARREGADO=false;

async function carregarRH(){
  if(!db||!usuarioId)return;
  if(ehGestorRH()){
    var q=await col("rh").limit(200).get();
    RH={};q.docs.forEach(function(d){RH[d.id]=d.data()||{};});
    var r=await col("remuneracao").limit(200).get();
    REM={};r.docs.forEach(function(d){REM[d.id]=d.data()||{};});
    var f=await col("facial").limit(200).get();
    FACIAL={};f.docs.forEach(function(d){FACIAL[d.id]=d.data()||{};});
    RH_CARREGADO=true;                  /* o item 21 exige esta trava */
    return;
  }
  /* Não-gestor: nem tenta ler 'rh' (não é dele). Lê o PRÓPRIO contracheque e a
     PRÓPRIA foto de referência — cada um com policy própria no Postgres. */
  RH={};REM={};FACIAL={};RH_CARREGADO=false;
  try{
    var meu=await col("remuneracao").doc(usuarioId).get();
    if(meu.exists)REM[usuarioId]=meu.data()||{};
    var minha=await col("facial").doc(usuarioId).get();
    if(minha.exists)FACIAL[usuarioId]=minha.data()||{};
  }catch(e){console.warn("remuneracao/facial próprios",e);}
}
function rhDe(u){return (u&&RH[u.id])||{};}
function remDe(u){return (u&&REM[u.id])||{};}
```

### Quem chama `carregarRH()` — sem isto ela nunca roda

Este era o buraco: a função existia e ninguém a chamava. Dois pontos, e os dois
são obrigatórios.

**1) No login**, dentro de `entrarComSessao()` (item 3), **antes** de
`opcoesProduto();render();` — é o que enche `REM[usuarioId]` a tempo de
`renderPonto` desenhar os cinco cartões com o valor certo:
```js
  try{await carregarRH();}catch(e){console.warn("carregarRH",e);}
```

**2) Ao abrir um colaborador**, porque `abrirUsuario` preenche o formulário com
`rhDe(u)`: com `RH={}` os campos abrem **em branco** e o item 21 regrava esse
branco por cima do RH real. `abrirUsuario` **vira `async`** (linha 4748) e a
primeira linha passa a ser o `await`:
```js
async function abrirUsuario(i){
  try{await carregarRH();}
  catch(e){falhaBanco(e);toast("Não deu para carregar o cadastro de RH.");return;}
  editandoUs=(i==null?null:USUARIOS[i]);
  /* …o resto igual… */
```
Os dois chamadores (`tr.onclick` e o botão `data-ued`, no fim de
`renderUsuarios`) continuam iguais: chamam sem `await` e a função abre o
formulário sozinha quando termina.

### As trocas, uma a uma

| Onde | Hoje | Fica |
|---|---|---|
| `renderUsuarios` | `u.facial` | `(FACIAL[u.id]||{}).foto` |
| `renderUsuarios` | `u.email\|\|u.tel` | `rhDe(u).email\|\|rhDe(u).tel` |
| `renderUsuarios` | `u.salario` | `remDe(u).salario` |
| `renderUsuarios` | `(+u.assiduidade\|\|0)+(+u.desempenho\|\|0)` | `(+remDe(u).assiduidade\|\|0)+(+remDe(u).desempenho\|\|0)` |
| `abrirUsuario` | `CAMPOS_US.forEach(…e.value=u[k]…)` | `var rh=rhDe(u);CAMPOS_US.forEach(function(k){var e=$("u_"+k);if(e)e.value=rh[k]\|\|"";});` |
| `abrirUsuario` | `$("u_"+k).value=(u[k]!=null?u[k]:"")` (salário, vr, prêmios) | mesma linha lendo `remDe(u)` |
| `abrirUsuario` | `usFilhos=(u.filhos\|\|[]).slice()` | `usFilhos=(rhDe(u).filhos\|\|[]).slice()` |
| `abrirUsuario` | `usFacial=u.facial\|\|""` | `usFacial=(FACIAL[u.id]\|\|{}).foto\|\|""` |
| `premioAssiduidade` | `var u=usuarioPor(quem)\|\|{},valor=+u.assiduidade\|\|0;` | `var valor=+remDe(usuarioPor(quem)).assiduidade\|\|0;` |
| `premioDesempenho` | `var u=usuarioPor(quem)\|\|{},valor=+u.desempenho\|\|0;` | `var valor=+remDe(usuarioPor(quem)).desempenho\|\|0;` |
| `totalRemuneracao` | `+u.salario`, `+u.vr` | `var m=remDe(usuarioPor(quem));` e `+m.salario`, `+m.vr` |

`premioDesempenho` entra na lista de propósito: ele lê o mesmo campo pelo mesmo
caminho e ficaria zerado junto com os outros dois.

**`jornadaDe` NÃO muda de lugar**: jornada não é dado sensível e vive em
`perfis.jornada`, justamente para o Cartão de Ponto funcionar sem abrir `rh`.
Ajuste só a origem:
```js
function jornadaDe(n){
  var u=usuarioPor(n)||{},j=u.jornada||{};
  return {entrada:j.entrada||JORNADA_PADRAO.entrada, /* ...idem para os outros campos... */
          bate:((j.bateponto||"sim")==="sim")};
}
```

### `remuneracao` no `adapter.js`

A coleção é nova e o adapter ainda não a conhece
(`grep -n remuneracao adapter.js` volta vazio). Em `supabase\adapter.js`:

- em `var CAMPO_LOJA = {`, ao lado de `rh: null,`: **`remuneracao: null,`**
  (é global, um documento por pessoa, sem loja — sem isso `set()` tenta carimbar
  uma loja que não existe);
- em `var COLECOES_RESTRITAS = [`: `["rh", "remuneracao", "facial", "ponto_fotos"]`;
- **não** acrescente em `COLECOES_DADOS`: backup não leva salário.

Do lado do Postgres já está tudo pronto —
`grep -n "colecao_restrita" schema.sql` mostra `remuneracao` na lista, e a
policy `docs_select_minha_remuneracao` já existe.

> Vendedor que abrir Configurações › Usuários vai receber **lista vazia de RH**
> (a RLS corta no servidor) — e é esse o comportamento correto. O teste 7 do
> aceite verifica exatamente isso. O que ele **vê** é a própria remuneração, na
> própria tela de Ponto, e só ela: o teste 7b verifica esse par.

## Item 23 — a foto de ponto sai de dentro do ponto

Hoje um dia completo de batidas carrega 4 fotos JPEG dentro do documento
(~25–40 KB por pessoa por dia) — e **todas** vêm no boot para todo mundo.

**`baterPonto`, linhas 6720–6726:**

**Hoje:**
```js
      var reg=p||{id:uid(),loja:lojaAtual,colaborador:quem,data:hoje,tipo:"normal",criadoEm:hoje};
      reg[k]={hora:hora,lat:loc?loc.lat:null,lng:loc?loc.lng:null,prec:loc?loc.prec:null,
        semGeo:!loc,motivoGeo:erro||"",foto:foto,sig:sig,
        distFacial:dist,conferirFace:conferir,semFotoRef:!u.facial,
        em:new Date().toISOString()};
      if(!p)pontos.push(reg);
      await grava("pontos",reg);
```

**Fica:**
```js
      var reg=p||{id:uid(),loja:lojaAtual,colaborador:quem,colaboradorId:usuarioId,
                  data:hoje,tipo:"normal",criadoEm:hoje};
      var fotoId=reg.id+"_"+k;
      reg[k]={hora:hora,lat:loc?loc.lat:null,lng:loc?loc.lng:null,prec:loc?loc.prec:null,
        semGeo:!loc,motivoGeo:erro||"",fotoId:fotoId,sig:sig,
        distFacial:dist,conferirFace:conferir,semFotoRef:!refFacial,
        em:new Date().toISOString()};
      try{
        /* a imagem vai para a coleção restrita; o ponto guarda só o ponteiro.
           'nome' é o campo que a RLS usa para deixar o colaborador inserir a
           SUA foto (policy docs_insert_meu_ponto_foto). */
        await grava("ponto_fotos",{id:fotoId,nome:quem,colaboradorId:usuarioId,
          loja:lojaAtual,data:hoje,marcacao:k,foto:foto,em:new Date().toISOString()});
        await grava("pontos",reg);
        if(!p)pontos.push(reg);
      }catch(e){
        $("po_status").innerHTML='<div class="note crit"><b>A batida NÃO foi registrada.</b> '+esc(e.message)+"</div>";
        toast("Batida não registrada.");return;
      }
```

E, antes disso, o consentimento (LGPD art. 11) — uma vez por pessoa:
```js
  if(perfilLogado&&!perfilLogado.consentiu_facial_em){
    if(!confirm("Para bater o ponto, o sistema guarda uma foto sua e a localização "+
                "no momento da batida, usadas só para conferir a presença. Você autoriza?")){
      toast("Sem o aceite não dá para bater o ponto com foto.");return;}
    try{perfilLogado.consentiu_facial_em=await db.registrarConsentimentoFacial();}catch(e){console.warn(e);}
  }
```

> **A condição só funciona se a coluna chegar no login.** `adapter.perfil()`
> tem que trazer `consentiu_facial_em` no `select` — se não trouxer, o campo é
> sempre `undefined`, a condição é sempre verdadeira e o `confirm()` aparece
> **nas 4 batidas de cada dia, de cada pessoa, para sempre**. Além do incômodo,
> quem clicar em Cancelar por engano não bate o ponto, e
> `registrar_consentimento_facial()` é chamada toda vez — o consentimento fica
> registrado no banco e nunca é consultado, que é o contrário do que o art. 11
> pede. O `adapter.js` de hoje já traz a coluna (`grep -n "consentiu_facial_em"
> adapter.js`); confira antes de testar. Prova rápida, em modo teste:
> `mfDebug.perfil.consentiu_facial_em`
> tem que sair com uma data depois da primeira batida — e continuar lá no F5
> seguinte.

**Renders que liam `b.foto`:**

- **Linha 6787** (tabela do dia): troque a miniatura por contagem/pill —
  `(b&&b.fotoId?'<span class="pill p-ok">com foto</span>'+(b.conferirFace?' <span class="pill p-warn">conferir</span>':""):"—")`.
- **`verFotosDia`, linhas 6867–6894**: vira `async` e busca as imagens só ao
  abrir o modal:
```js
async function verFotosDia(quem,data){
  var p=pontoDe(quem,data);if(!p)return;
  var refDoc=await col("facial").doc((usuarioPor(quem)||{}).id||"").get();
  var ref=refDoc.exists?(refDoc.data()||{}).foto:"";
  var fotos={};
  for(var i=0;i<MARCACOES.length;i++){
    var b=p[MARCACOES[i].k];
    if(b&&b.fotoId){
      var f=await col("ponto_fotos").doc(b.fotoId).get();
      if(f.exists)fotos[b.fotoId]=(f.data()||{}).foto||"";
    }
  }
  /* ...o resto do HTML igual, trocando u.facial por ref e b.foto por fotos[b.fotoId]... */
}
```
  Os chamadores passam a usar `verFotosDia(...)` sem esperar retorno — tudo bem,
  ela mesma abre o modal no fim.
- **`tirarFoto` (6626) / comparação facial (6713–6716)**: `u.facialSig` sai de
  `FACIAL[u.id].sig`, carregado ao abrir a câmera (o colaborador lê a **sua** por
  RLS; o gestor lê a de quem estiver conferindo).

## Item 23b — ajuste de ponto usa a ação certa

**Linha 6897.**
```js
  if(!ehGestor()){toast("Só o Administrador ou o Financeiro ajusta ponto.");return;}
```
**fica**
```js
  if(!pode("ajustarPonto")){toast("Você não tem permissão para ajustar ponto.");return;}
```

**Atenção: sozinha, essa troca TIRA do Erico o ajuste de ponto.** A mensagem de
hoje promete "Só o Administrador **ou o Financeiro**", e `ehGestor()` é
`pode("verTudo")`, que o Financeiro tem. Mas em `SEED_FUNCOES` o Financeiro é

```js
    acoes:["verTudo","verCustos","aprovarFinanceiro","reabrirVenda","baixarTitulos","exportar"]
```

— **sem `ajustarPonto`**. Só o Administrador tem a ação (por `ACOES.map`). Quem
faz esse ajuste hoje é o Erico; trocar a checagem sem trocar a semente é tirar
dele a tarefa no dia da virada.

**Duas correções junto com a troca:**

1. Em `SEED_FUNCOES`, na linha do Financeiro, acrescente a ação:
```js
    acoes:["verTudo","verCustos","aprovarFinanceiro","reabrirVenda","baixarTitulos","exportar","ajustarPonto"]
```

2. A semente **não conserta quem já está no banco**: `config/funcoes` foi
   gravado no primeiro boot, e `migrarTelasNovas()` (linha 9714) só acrescenta
   **telas** a quem tem `verTudo` — nunca ações. Acrescente a migração de ação
   dentro dela, antes do `if(mudou)await gravarFuncoes();`:
```js
  /* ações novas não entram por migrarTelasNovas (ela só cuida de telas):
     'ajustarPonto' passou a ser exigida pelo item 23b e o Financeiro precisa
     dela para continuar fazendo o que já fazia. */
  funcoes.forEach(function(f){
    if(f.nome==="Financeiro"&&(f.acoes||[]).indexOf("ajustarPonto")<0){
      f.acoes=(f.acoes||[]).concat(["ajustarPonto"]);mudou=true;}
  });
```
   `migrarTelasNovas()` sai cedo (`if(!novas.length)return;`) quando não há tela
   nova: **mova esse `return` para depois do bloco acima**, ou troque-o por
   `var novas=…` sem `return` e deixe as duas migrações decidirem juntas o
   `mudou`. Senão a ação nunca é acrescentada.

> Quem grava `config/funcoes` agora é só Administrador/Financeiro
> (`docs_config_gestor`, `schema.sql` item 8.6) — a migração roda no login de
> um dos dois e passa a valer para todo mundo. No login de um Vendedor ela
> falha com 42501; deixe a chamada dentro de `try/catch`.

A ação `ajustarPonto` já existia em `ACOES` e nunca tinha sido usada. Espelhe na
RLS: `update` de `docs` com `colecao='pontos'` só para quem tem a ação — na Fase
1 a policy de update geral já cobre `authenticated`; se quiser apertar,
acrescente uma policy própria no `schema.sql`.

---

# BLOCO H — TRAVAS DE TELA E USUÁRIOS

## Item 24 — `ir()` respeita a permissão e `funcaoDe` fecha por padrão

**Linha 9979:**
```js
function ir(s){
  Array.prototype.forEach.call(document.querySelectorAll(".rail button"),function(b){b.setAttribute("aria-current",String(b.dataset.s===s));});
```
**fica**
```js
function ir(s){
  /* defesa em profundidade: a trava de verdade é a RLS, mas não custa impedir
     que ir("usuarios") no console abra a tela de RH */
  if(usuarioId&&!veTela(s)){toast("Você não tem acesso a esta tela.");return;}
  Array.prototype.forEach.call(document.querySelectorAll(".rail button"),function(b){b.setAttribute("aria-current",String(b.dataset.s===s));});
```

**Linha 9732** (`funcaoDe`) — hoje, enquanto `funcoes` não carregou, libera tudo:
```js
  if(!funcoes.length)return {telas:TODAS_TELAS,acoes:ACOES.map(function(a){return a[0];})};
```
**fica**
```js
  /* antes do login não existe tela liberada; depois, funcoes[] já carregou */
  if(!usuarioId)return {telas:[],acoes:[]};
  if(!funcoes.length)return {telas:TELAS_OPERACAO,acoes:[]};
```

## Item 25 — criar colaborador e redefinir senha

**Linha 10068 (`usAdd`)** — hoje cria a pessoa só empurrando no array:
```js
    USUARIOS.push({nome:n,perfil:$("usPerfil").value,ativo:true});
    await gravarUsuarios();sincronizarEquipe();$("usNome").value="";
```
**fica** (Fase 1 — sem Edge Function; o HTML com anon key **não pode** criar contas):
```js
    $("usAlerta").innerHTML='<div class="note"><b>Criar acesso é no painel do Supabase.</b> '+
      "Authentication › Users › Invite user, com o e-mail de trabalho. Assim que a pessoa aceitar o convite, "+
      "volte aqui e complete o cadastro dela — ela já aparece na lista.</div>";
    return;
```
> `usAlerta` **não existe** hoje (o único aviso da tela é o `u_alerta` do
> formulário, linha 2387). Acrescente o `<div id="usAlerta"></div>` dentro do
> card `usLista`, logo depois da linha do contador `usCount` (**linha 2398**).
> Fase 2 (opcional): uma Edge Function `convidar_usuario` com a service_role
> chamando `auth.admin.inviteUserByEmail` + `insert perfis`. Só vale a pena
> quando entrar gente nova com frequência; com 7 colaboradores, o painel resolve.

**Linhas 10080–10083 (`u_zerarSenha`)**:
```js
  $("u_zerarSenha").onclick=async function(){
    if(!editandoUs){toast("Salve o colaborador primeiro.");return;}
    delete editandoUs.senha;await gravarUsuarios();
    toast("Senha zerada. No próximo acesso "+editandoUs.nome+" cria uma nova.");};
```
**fica**
```js
  $("u_zerarSenha").textContent="Enviar link de redefinição";
  $("u_zerarSenha").onclick=async function(){
    if(!editandoUs){toast("Salve o colaborador primeiro.");return;}
    var em=(rhDe(editandoUs).email||"").trim();
    if(!em){toast("Cadastre o e-mail do colaborador primeiro.");return;}
    try{await db.auth.redefinirSenha(em,location.href.split("#")[0]);
      toast("Link enviado para "+em+".");}
    catch(e){toast("Não deu para enviar: "+e.message);}};
```

## Item 28 — o MÓDULO CELULAR, que nenhum inventário viu

O arquivo tem um segundo par `<style>`+`<script>` que os inventários não
alcançaram: o **estilo** em `<style id="estiloCelular">` (às 14h42, linhas
504–678, logo depois do estilo principal) e o **comportamento** — gaveta, barra
inferior e cabeçalho compacto — no fim do arquivo (11264–11515 no mesmo
momento; ache com `grep -n "AJUSTES DE CELULAR" sistema-minas.html`). Ele mexe
justamente nos elementos que os itens 11, 12 e 24 alteram:

- move `.lojasel` (que contém `#loja` **e** `#usuario`), `#perfilPill` e
  `#btSair` do cabeçalho para dentro da gaveta
  (`Array.prototype.forEach.call(topo.querySelectorAll(".lojasel"),guardar);`);
- esconde os originais no topo (`.top .lojasel,.top #perfilPill,.top .sair{display:none}`);
- e estiliza `.gaveta-pe .lojasel select{width:100%;padding:11px 12px;font-size:16px}`
  — regra que **deixa de valer** quando o item 11a troca o `<select id="usuario">`
  por um `<span>`.

**28a — a barra inferior oferece telas proibidas.** Ache a linha:
```
grep -n "b.hidden=!alvo" sistema-minas.html
```
**Hoje:**
```js
      b.hidden=!alvo||alvo.hidden;
```
**Fica:**
```js
      /* aplicarPerfil() esconde tela proibida com style.display="none", NÃO com
         o atributo hidden — sem esta segunda condição a barra do celular
         continua oferecendo "Clientes" e "Ponto" a quem não tem acesso, e o
         toque passa a devolver "Você não tem acesso a esta tela." (item 24). */
      b.hidden=!alvo||alvo.hidden||alvo.style.display==="none";
```

**28b — e o observador não acorda quando isso muda.** Ache:
```
grep -n 'attributeFilter:\["aria-current","hidden"\]' sistema-minas.html
```
**Hoje:**
```js
      subtree:true,attributes:true,attributeFilter:["aria-current","hidden"]
```
**Fica:**
```js
      subtree:true,attributes:true,attributeFilter:["aria-current","hidden","style"]
```
Sem `"style"` na lista, `sincronizar()` não é chamada quando `aplicarPerfil()`
roda — a barra fica com o desenho do login anterior até a próxima navegação.

**28c — confira o `<span id="usuario">` dentro da gaveta.** A regra
`.gaveta-pe .pill{display:inline-block;align-self:flex-start}` já existe e pega
o `<span class="pill">` do item 11a, então ele **deve** aparecer. Abra o site no
celular (ou F12 → 375×812), abra a gaveta e confirme que o nome do operador
aparece legível ao lado do cargo. Se ficar apertado, a regra a ajustar é essa,
não o HTML.

> Este item é **cosmético + permissão**: nada aqui fala com o banco. Deixe-o
> por último, mas não o pule — todo o módulo existe porque parte da equipe usa o
> sistema no celular, e "o menu de baixo abre uma tela que dá erro" é o tipo de
> coisa que vira chamado no primeiro dia.

---

# BLOCO I — PRODUÇÃO

## Item 26 — esconder o gerador de dados de teste

Cinco edições (26a a 26d), **e a ordem importa**: se apagar o card sem apagar o
wiring, `$("dtGerar")` vira `null` e **todo o `ligar()` quebra** — nenhum botão
do sistema volta a funcionar.

Esconder não é o mesmo que desligar: 26a e 26b tiram o card da tela, 26c troca a
chave de ambiente, **26c-bis** tranca as duas funções por perfil e **26d** apaga
os dois estragos que o gerador faz em dado real. Os quatro primeiros sem o
último ainda deixam o botão apagar as metas do mês.

**26a — wiring, linhas 10089–10090** (apague primeiro):
```js
  $("dtGerar").onclick=gerarDemo;
  $("dtLimpar").onclick=limparDemo;
```
**fica**
```js
  /* Dados de teste: só aparecem fora de produção. */
  if(MODO_TESTE){$("dtGerar").onclick=gerarDemo;$("dtLimpar").onclick=limparDemo;}
  else{var cd=$("dtCard");if(cd)cd.hidden=true;}
```

**26b — card, linhas 2568–2577**: acrescente o id no `<div class="card">`:
```html
      <div class="card" id="dtCard">
        <h2>Dados de teste</h2>
```

**26c — a chave já está no item 1b.** `var MODO_TESTE` é definida lá, e **não**
por querystring:

```js
/* ERRADO — não use: */
var MODO_TESTE=(location.search.indexOf("teste=1")>=0);
```

`?teste=1` esconde o **botão**, não a função. Qualquer pessoa logada digita
`.../sistema-minas.html?teste=1` na barra de endereço e o card volta inteiro. A
chave tem que ser algo que o usuário não controle — o `location.hostname` do
item 1b, que em produção (GitHub Pages / Firebase) nunca é `localhost`.

**26c-bis — e esconder o botão não basta.** `gerarDemo` e `limparDemo`
continuam sendo funções globais dentro da IIFE, chamáveis por qualquer coisa
que tenha alcance a elas; e do lado do servidor **não há trava nenhuma**: as
~120 gravações do gerador caem em `pedidos`, `titulos`, `movs`, `movest` e
`clientes`, todas liberadas por `docs_insert_geral` para qualquer autenticado.
Ponha a trava **dentro das duas funções**, na primeira linha:

```js
async function gerarDemo(){
  if(!MODO_TESTE||!perfilLogado||perfilLogado.funcao!=="Administrador"){
    toast("Indisponível em produção.");return;}
  /* …resto igual… */
}
async function limparDemo(){
  if(!MODO_TESTE||!perfilLogado||perfilLogado.funcao!=="Administrador"){
    toast("Indisponível em produção.");return;}
  /* …resto igual… */
}
```

Sem isso, um clique curioso numa tarde apaga as metas do mês da equipe inteira
(veja 26d) e enche o faturamento de vendas falsas — com números de pedido que
**consomem a numeração real**: depois do item 19 o número vem da RPC
`proximo_numero`, e número queimado não volta.

**26d — dois estragos do demo que precisam sumir antes de ir para produção:**

- **Apague as linhas 5991–6022 de `gerarDemo`.** Não é "remova ou condicione":
  é apagar. O bloco escreve CPF, salário, endereço e filhos **falsos por cima
  dos 7 colaboradores reais** (`u.demoTocado=true`) e `limparDemo` **não
  desfaz**. A faixa termina **quatro linhas depois** do que os inventários
  indicavam, porque a gravação está fora do `forEach`. Âncoras:
  do comentário `/* --- remuneração e jornada dos colaboradores --- */` até a
  linha `log.push("remuneração, jornada, endereço e dados pessoais dos 7 colaboradores");`,
  inclusive — a próxima linha a sobreviver é o comentário
  `/* --- fornecedores --- */`.

  | Linha (antiga) | Conteúdo | Sai? |
  |---|---|---|
  | 5991 | `/* --- remuneração e jornada dos colaboradores --- */` | sim |
  | 5992–6018 | `var rem={…}` + o `USUARIOS.forEach(…)` que carimba CPF/salário | sim |
  | 6019–6020 | o comentário e `var inativo={…}` — **variável morta**, ninguém a usa | sim |
  | **6021** | **`await gravarUsuarios();sincronizarEquipe();`** | **sim** |
  | 6022 | `log.push("remuneração, jornada, endereço e dados pessoais dos 7 colaboradores");` | sim |

  Parar na 6018, como dizia a versão anterior deste item, deixa a **chamada
  órfã** da 6021 — e `gravarUsuarios` foi apagada no item 14. `gerarDemo`
  morreria de `ReferenceError` no meio do cenário, deixando o banco com meio
  conjunto de teste e sem o toast final. E o sintoma apareceria justamente
  quando alguém fosse testar. Confira o resultado com
  `grep -n "demoTocado\|gravarUsuarios" sistema-minas.html` — as duas têm que
  sumir.

- **`limparDemo`, linhas 6460–6462:** apaga `metas[nm]` de **toda** a EQUIPE e
  zera `celebracoes={}` — dados reais, que nunca tiveram flag `demo`, das 3
  lojas.

  O estrago começa antes: **`gerarDemo` já sobrescreve as metas reais.** No
  bloco `/* --- metas --- */` ele faz `metas[n]=JSON.parse(JSON.stringify(alvo))`
  para **todo** membro da EQUIPE que não seja Administrador, Financeiro ou
  Estoquista. Não há flag `demo` em lugar nenhum, então `limparDemo` não tem
  como saber o que era teste e apaga tudo. E `celebracoes` o gerador **nem
  escreve** — `limparDemo` zera um dado que o demo nunca criou.

  São duas edições, uma em cada função.

  **Em `gerarDemo`, antes do `EQUIPE.forEach` das metas:**
  ```js
    /* guarda as metas reais antes de escrever por cima: é o que limparDemo
       devolve depois. Sem isto, o teste apaga o mês da equipe e não há
       de onde recuperar. */
    try{await db.doc("config/metas_pre_demo").set({dados:JSON.parse(JSON.stringify(metas)),em:new Date().toISOString()});}
    catch(e){toast("Não deu para guardar as metas atuais — o teste foi cancelado.");return;}
  ```

  **E em `limparDemo`, no lugar das três linhas de hoje:**
  ```js
    /* Devolve as metas que gerarDemo guardou. A versão anterior apagava
       metas[nm] de TODA a equipe e zerava celebracoes — dados reais, das 3
       lojas, que nunca tiveram flag 'demo'. Um clique apagava o mês. */
    try{
      var bkp=await db.doc("config/metas_pre_demo").get();
      if(bkp.exists&&bkp.data()&&bkp.data().dados){
        metas=bkp.data().dados;
        await gravarMetas();
        await db.doc("config/metas_pre_demo").delete();
      }
    }catch(e){toast("As metas anteriores NÃO foram restauradas: "+e.message);}
    /* celebracoes NÃO se apaga: guarda quais parabéns já foram exibidos para
       cada pessoa, e o gerador nunca escreve nela. Zerar só faz o sistema
       parabenizar todo mundo de novo. */
  ```
  Ajuste o texto do `dt_log` logo abaixo, que hoje promete "mais as metas e as
  comemorações que o teste tinha criado" — agora ele **devolve** as metas e não
  mexe nas comemorações.

## Item 27 — export diário em JSON

Acrescente a função perto de `gravarEmpresa` e o botão no card da empresa
(**linha 2565**, ao lado de `emSalvar`):

```html
        <div class="actions">
          <button class="btn" type="button" id="emSalvar">Salvar dados da empresa</button>
          <button class="btn mut" type="button" id="emBackup">Baixar backup do dia (JSON)</button>
        </div>
```

```js
/* Backup diário: um arquivo por loja. O que entra é a lista branca
   COLECOES_DADOS do adapter (as 18 coleções do dia a dia). Ficam de fora, de
   propósito: 'rh', 'remuneracao', 'facial' e 'ponto_fotos' (nem constam da
   lista) e, dentro de 'config', os documentos 'usuarios' e 'celebracoes'
   (CONFIG_NAO_EXPORTA) — backup não é motivo para espalhar CPF e salário. */
async function baixarBackup(){
  if(!db){toast("Sem banco.");return;}
  if(!pode("exportar")){toast("Você não tem permissão para exportar.");return;}
  var bt=$("emBackup");bt.disabled=true;bt.textContent="Montando…";
  try{
    var dados=await db.exportar({loja:lojaAtual});
    dados._meta={loja:lojaAtual,nomeLoja:nomeLoja(),quando:new Date().toISOString(),
                 por:usuarioAtual,versaoAdapter:db.versao||""};
    var txt=JSON.stringify(dados);
    var a=document.createElement("a");
    a.href=URL.createObjectURL(new Blob([txt],{type:"application/json"}));
    a.download="minasfiltros-"+lojaAtual+"-"+hojeISO()+".json";
    document.body.appendChild(a);a.click();
    setTimeout(function(){URL.revokeObjectURL(a.href);a.remove();},4000);
    toast("Backup baixado · "+Math.round(txt.length/1024)+" KB.");
  }catch(e){falhaBanco(e);toast("O backup falhou: "+e.message);}
  finally{bt.disabled=false;bt.textContent="Baixar backup do dia (JSON)";}
}
```
E em `ligar()`: `$("emBackup").onclick=baixarBackup;`

> **Confira no `adapter.js` antes de confiar nessa lista** — o backup só é
> seguro se as duas variáveis estiverem certas:
> ```
> grep -n "COLECOES_DADOS\|CONFIG_NAO_EXPORTA" adapter.js
> ```
> `COLECOES_DADOS` tem que ter **18** nomes e nenhum deles pode ser `rh`,
> `remuneracao`, `facial`, `ponto_fotos` ou `config`; `CONFIG_NAO_EXPORTA` tem
> que conter `"usuarios"` e `"celebracoes"`. Uma versão antiga do adapter
> percorria `Object.keys(CAMPO_LOJA)`, que **inclui `config`**, e filtrava só as
> coleções restritas: o backup saía com o `config/usuarios` inteiro — hash de
> senha, CPF, RG, endereço, filhos, salário, CTPS, PIS e a foto facial em base64
> dos 7 — dentro de um `.json` que qualquer um com a ação `exportar` baixa e
> manda por WhatsApp.

**27b — apagar o `config/usuarios` NÃO é rodapé: é o passo 9 do painel.**
Enquanto esse documento existir, `docs_select_config` o entrega a **qualquer
autenticado** pelo REST — o vendedor lê salário e CPF de todo mundo com um
`GET /rest/v1/docs?colecao=eq.config&id=eq.usuarios`, sem passar pela tela.
O comando está no passo a passo, e o teste 9 do aceite confere que ele foi
rodado.

**27c — e feche no servidor, para não depender da revisão do HTML.** Mesmo com
os itens 14, 21, 25, 26d e 14b aplicados, basta **uma** aba antiga do
`sistema-minas.html` aberta em algum celular para recriar o documento no
primeiro `carregar()`. Acrescente ao `schema.sql`, junto das policies de
`config` (item 8.6):

```sql
-- config/usuarios NAO existe mais: identidade em public.perfis, RH em
-- colecao='rh', salario em 'remuneracao', biometria em 'facial'. Esta policy
-- e RESTRICTIVE de proposito: policies PERMISSIVE se somam (basta UMA liberar),
-- as RESTRICTIVE se multiplicam (todas precisam liberar). Assim nem o
-- Administrador recria o documento por engano - e uma aba antiga do HTML
-- ainda apontando para la falha na hora, em vez de vazar de novo.
drop policy if exists docs_bloqueia_usuarios on public.docs;
create policy docs_bloqueia_usuarios on public.docs
  as restrictive
  for all to authenticated
  using      (not (colecao = 'config' and id = 'usuarios'))
  with check (not (colecao = 'config' and id = 'usuarios'));
```

> Rode isto **depois** de conferir que a migração dos dados terminou: enquanto
> alguém ainda precisar ler o documento velho para copiar CPF e salário para
> `rh`/`remuneracao`, a policy atrapalha. A ordem certa é: migrar → conferir →
> `delete` (27b) → policy (27c).

---

# PASSO A PASSO NO PAINEL DO SUPABASE

**1. Criar o projeto**
`supabase.com` → New project. Organização sua, nome `minas-filtros`, região
**South America (São Paulo)**. Guarde a senha do banco que ele pede (é a senha
do Postgres, não a de nenhum usuário do sistema) num lugar seguro — ela não é
usada pelo HTML.

**2. Rodar o schema**
SQL Editor → New query → cole o conteúdo de `supabase\schema.sql` → **Run**.
O arquivo é idempotente (`if not exists`, `drop policy if exists`): pode rodar
de novo sem estragar nada. No fim, confira:
```sql
select tablename, rowsecurity from pg_tables
 where schemaname='public' and tablename in ('docs','perfis','numeradores');
```
As três têm que aparecer com `rowsecurity = true`.

**3. Ligar o Realtime**
Database → Replication → publicação `supabase_realtime` → marque `public.docs`.
O bloco final do `schema.sql` já tenta fazer isso; se ele avisou
"Publicacao supabase_realtime nao encontrada", faça pelo painel e rode o bloco
de novo.

**4. Criar os 7 acessos**
Authentication → Users → **Invite user** (manda o convite e a pessoa cria a
própria senha) ou **Add user** com senha temporária, se preferir entregar na mão.
Um por colaborador, com o e-mail de trabalho:

| Nome (tem que bater com o histórico) | Função | Loja |
|---|---|---|
| Wagner | Administrador | mf |
| Erico | Financeiro | mf |
| Carol | Vendedor | mf |
| Veronica Aparecida Marques | Vendedor | mf |
| Franciele Neves | Vendedor | mf |
| Guilherme Guimarães | Instalador | mf |
| Jaqueline Nunes | Prospector | mf |

> **Confirme loja por loja antes de inserir.** A tabela acima repete `mf` porque
> hoje o `USUARIOS` do HTML não tem campo de loja nenhum — quem sabe quem é de
> WF Filtros e de Divinópolis é você. Corrija na hora do insert.
>
> **O nome é chave de negócio.** `pontos.colaborador`, `pedidos.vendedor`,
> `metas[nome]`, `criadoPor` — tudo casa por nome. Um "Verônica" com acento onde
> o histórico tem "Veronica" separa a pessoa em duas. Copie exatamente como está
> no CRM antigo.

**5. Inserir os perfis**
SQL Editor, um bloco por pessoa (o `schema.sql` traz este modelo comentado no
item 11.1). O primeiro **tem** que ser feito aqui: enquanto não existir um
`Administrador`, a policy não deixa ninguém inserir perfil pelo aplicativo.
```sql
insert into public.perfis (user_id, nome, funcao, loja, ativo, jornada)
select u.id, 'Wagner', 'Administrador', 'mf', true,
       '{"entrada":"08:00","almocoIni":"12:00","almocoFim":"13:30","saida":"18:00","tolerancia":10,"bateponto":"nao"}'::jsonb
  from auth.users u
 where u.email = 'wagner@minasfiltrosonline.com.br'
on conflict (user_id) do update
   set nome=excluded.nome, funcao=excluded.funcao, loja=excluded.loja, ativo=excluded.ativo;
```
Confira no fim: `select nome, funcao, loja, ativo from public.perfis order by nome;`
— sete linhas.

**6. Semear os numeradores** ← **o passo que ninguém pode pular**

Este passo roda **depois** de importar o histórico, não antes — e o número não
se levanta na tela do CRM antigo. Não dá: o número de pedido de hoje sai de
`pedidos.filter(loja).length+20801` sobre um array truncado em 500, então a
lista de Pedidos **não mostra** o maior número emitido de forma confiável.
Pergunte ao banco, que é onde os dados já estão:

```sql
-- 6.1 — quanto cada contador tem que valer (só olha, não grava)
select loja, max((data->>'numero')::int) as maior
  from public.docs
 where colecao='pedidos' and loja is not null and (data->>'numero') ~ '^[0-9]+$'
 group by loja order by loja;
-- repita trocando 'pedidos' por 'orcamentos' e por 'ordens'
```

```sql
-- 6.2 — e então grave, derivado dos mesmos dados (sem digitar número nenhum)
insert into public.numeradores (loja, tipo, ultimo)
select d.loja, 'pedido', max(nullif(d.data->>'numero','')::int)
  from public.docs d
 where d.colecao='pedidos' and d.loja is not null and (d.data->>'numero') ~ '^[0-9]+$'
 group by d.loja
on conflict (loja, tipo) do update
   set ultimo = greatest(numeradores.ultimo, excluded.ultimo);
```
Repita trocando `'pedidos'/'pedido'` por `'orcamentos'/'orcamento'` e
`'ordens'/'os'`. Para **cliente**, o número está no sufixo do código
(`MF-01002` → 1002):
```sql
insert into public.numeradores (loja, tipo, ultimo)
select d.loja, 'cliente', max(nullif(regexp_replace(d.data->>'codigo','\D','','g'),'')::int)
  from public.docs d
 where d.colecao='clientes' and d.loja is not null
 group by d.loja
on conflict (loja, tipo) do update
   set ultimo = greatest(numeradores.ultimo, excluded.ultimo);
```
E para **fornecedor** — que é um contador só para as três lojas:
```sql
insert into public.numeradores (loja, tipo, ultimo)
select '*', 'fornecedor', max(nullif(regexp_replace(d.data->>'codigo','\D','','g'),'')::int)
  from public.docs d
 where d.colecao='fornecedores'
on conflict (loja, tipo) do update
   set ultimo = greatest(numeradores.ultimo, excluded.ultimo);
```

Três armadilhas neste passo, todas já vistas:

1. **A loja do fornecedor é `'*'`, não `'global'`.** `proximo_numero()` força
   `v_loja := '*'` para os tipos globais (item 9.1 do `schema.sql`). Uma linha
   semeada em `('global','fornecedor', …)` **nunca é lida por ninguém**: a RPC
   cria `('*','fornecedor')` do zero, na base 1001, e volta a emitir códigos já
   usados.
2. **O valor é o maior SUFIXO já emitido, não a contagem de fornecedores.** Os
   códigos de hoje são `FOR-1001`, `FOR-1002`… (as duas fórmulas do HTML são
   `"FOR-"+String(fornecedores.length+1001)`) e `base_numerador('fornecedor')`
   é **1001**. Semear `87` — a contagem — faz o próximo nascer `FOR-88` e a
   sequência voltar a passar por 1001, 1002…, colidindo com o que já existe. E
   não há checagem de código duplicado de fornecedor no HTML: a única checagem é
   sobre o CNPJ.
3. **`on conflict … do update set ultimo = excluded.ultimo` REBAIXA o
   contador.** Use `greatest(...)`, como acima. Rodar o bloco uma segunda vez na
   semana seguinte (ao cadastrar a loja `dv`, ao reconferir a carga) devolveria
   o contador ao valor do dia da migração e os próximos pedidos repetiriam
   números já emitidos. O trigger `tg_numeradores_antes_de_gravar` recusa o
   retrocesso de qualquer jeito — o `greatest()` evita o erro.

Se preferir digitar os valores à mão, o `schema.sql` traz o bloco com
placeholders no item 11.2 (`TROCAR_ULTIMO_PEDIDO_MF`…). Eles são texto de
propósito: colar sem preencher dá erro do Postgres em vez de gravar zero e
reiniciar a numeração.

Confira **sem consumir número** (`proximo_numero()` reserva de verdade — não a
use para conferir):
```sql
select loja, tipo, ultimo, ultimo+1 as proximo from public.numeradores order by loja, tipo;
```

**7. Pegar URL e chave**
Project Settings → API. Copie:
- **Project URL** → `SUPABASE_URL` (item 1)
- **anon public** → `SUPABASE_ANON` (item 1)

A **service_role** fica no painel. Ela ignora a RLS; se ela for para o HTML,
qualquer pessoa com F12 lê salário e CPF de todo mundo. O adapter recusa a chave
e lança erro se alguém colar por engano.

**8. Publicar**
Suba `sistema-minas.html` **e** a pasta `supabase/` com o `adapter.js`. Depois
abra o site e siga o teste de aceite abaixo.

**9. Apagar o `config/usuarios` — e trancar a porta** ← **não é opcional**

Assim que o teste de aceite passar (em especial o 1, o 6 e o 7), rode:
```sql
-- confira o que vai embora, primeiro
select id, jsonb_array_length(data->'lista') as pessoas from public.docs
 where colecao='config' and id='usuarios';

delete from public.docs where colecao='config' and id='usuarios';
```
Enquanto esse documento existir, `docs_select_config` o entrega a **qualquer
autenticado**: um `GET /rest/v1/docs?colecao=eq.config&id=eq.usuarios` com a
anon key e um login de vendedor devolve hash de senha, CPF, RG, endereço,
filhos, salário, CTPS, PIS e a foto facial em base64 dos 7 — sem passar por
tela nenhuma. É o vazamento que esta migração existe para fechar.

Depois do `delete`, aplique a policy **restritiva** do item 27c, senão qualquer
aba antiga do HTML ainda aberta recria o documento no próximo `carregar()`.

Confira que sumiu **e** que não volta:
```sql
select count(*) from public.docs where colecao='config' and id='usuarios';  -- 0
select policyname, permissive from pg_policies
 where schemaname='public' and tablename='docs' and policyname='docs_bloqueia_usuarios';
```
A segunda consulta tem que devolver uma linha com `permissive = RESTRICTIVE`.

---

# TESTE DE ACEITE

Doze verificações objetivas (1 a 11, mais a 7b). Faça na ordem; cada uma tem um
resultado que dá para apontar com o dedo. Se alguma falhar, o item correspondente é o que voltar
a mexer.

> **Antes de começar — os testes de console precisam do `mfDebug`.** Todo o JS
> do sistema vive dentro de `(function(){ "use strict"; … })()`: `db`, `$` e
> `perfilLogado` são variáveis **locais** dessa IIFE. Digitar `db` ou
> `$("usuario")` no console de um site publicado devolve
> `ReferenceError: db is not defined` — não é bug, é escopo. O item 1b publica
> `window.mfDebug` **só fora de produção**, e é por ele que os testes 2, 6, 7 e
> 7b falam com o banco. Duas formas de rodá-los:
>
> - **em `localhost`** (`python -m http.server` na pasta, ou o arquivo aberto
>   direto do disco): `MODO_TESTE` é verdadeiro e `mfDebug` existe;
> - **contra o site publicado**, sem ligar modo teste: use o `curl` do teste 7,
>   que fala com o PostgREST com o `access_token` da sessão.
>
> **O SQL Editor do painel não vale como teste de RLS** — ele roda como
> `postgres`, que **ignora** todas as policies. Um `select` lá dando resultado
> não prova nada sobre o que o vendedor consegue ler.

### 1. Login de verdade
Abra o site numa janela anônima. **Espere ver:** só logo, e-mail, senha e
"Esqueci minha senha" — **nenhum nome de colaborador na tela**. Entre com o
e-mail do Wagner. Antes de digitar a senha, abra o F12 → Network e confirme que
**nenhuma requisição a `/rest/v1/docs`** aconteceu. Senha errada: mensagem
genérica, sem dizer se o e-mail existe. (Itens 3, 4, 6, 8)

### 2. A loja vem do perfil
Entre como **Carol** (Vendedor, loja `mf`). **Espere ver:** o seletor de loja no
cabeçalho **desabilitado**, marcando "Minas Filtros"; o nome dela ao lado, como
texto — **não como `<select>`**. Confirme sem console, com o F12 → Elements:
procure `id="usuario"` e veja que a tag é `<span>`, não `<select>` — não há como
virar Administrador. (Em `localhost`, `mfDebug.$("usuario").tagName` devolve
`"SPAN"`.) Entre como Wagner: o seletor está habilitado com as três lojas, e
trocar de loja recarrega os dados (toast "Carregando…"). (Itens 11, 12)

### 3. Venda gera número sem colisão com 2 abas
Abra o sistema em **duas abas**, as duas na mesma loja, logadas com pessoas
diferentes. Monte uma venda em cada uma **sem salvar**. Salve as duas **quase ao
mesmo tempo**. **Espere ver:** dois números **diferentes e consecutivos** (ex.
20848 e 20849). Confira no banco:
```sql
select data->>'numero' as numero, count(*) from public.docs
 where colecao='pedidos' and loja='mf' group by 1 having count(*)>1;
```
**Zero linhas.** Repita para `orcamentos` e `ordens`. (Item 19)

### 4. Toast só depois de gravar
Com o sistema aberto, F12 → Network → **Offline**. Salve um cliente.
**Espere ver:** toast dizendo que **NÃO** foi salvo, o cliente **não** aparece na
lista, e o banner vermelho no topo. Volte a rede: o banner some sozinho com
"Conexão restabelecida". Salve de novo: agora sim o toast de sucesso e o registro
na lista. (Itens 16, 17)

### 5. Falha de rede mostra banner
Ainda offline, dê F5. **Espere ver:** a tela de login com o banner de falha —
e **não** o sistema abrindo vazio como se estivesse tudo bem (que é o que
acontece hoje quando `carregar()` explode na terceira coleção). (Itens 3, 15, 17)

### 6. Ponto grava foto só onde é permitido
Entre como **Carol** e bata o ponto. **Espere ver:** o aceite de consentimento na
primeira vez; depois a batida registrada. Confira no banco:
```sql
select colecao, id, data->>'nome' from public.docs where colecao='ponto_fotos' order by criado_em desc limit 5;
select data ? 'foto' from public.docs where colecao='pontos' order by atualizado_em desc limit 1;
```
A foto está em `ponto_fotos`; o documento de `pontos` **não tem** campo `foto`
(só `fotoId`). Ainda como Carol, **em `localhost`**, no console:
```js
(await mfDebug.db.collection("ponto_fotos").limit(50).get()).docs.map(d=>d.data().nome)
```
**Só o nome dela.** As fotos dos colegas não vêm. (Item 23)

### 7. Vendedor não lê RH
Logada como Carol, **em `localhost`**, no console:
```js
(await mfDebug.db.collection("rh").limit(50).get()).size
```
**Espere ver: `0`** — a RLS corta no servidor, não é a tela que esconde. Tente
gravar:
```js
await mfDebug.db.collection("rh").doc("x").set({id:"x",salario:99999})
```
**Espere ver:** promessa **rejeitada**, com mensagem de permissão. Entre como
Wagner e repita: agora a leitura traz os documentos. (Itens 21, 22)

**Contra o site publicado**, sem modo teste, o mesmo par de verificações pelo
PostgREST — pegue o `access_token` em F12 → Application → Local Storage
(`sb-<projeto>-auth-token`) e:
```
curl -s "https://SEUPROJETO.supabase.co/rest/v1/docs?colecao=eq.rh&select=id" \
     -H "apikey: SUA_CHAVE_ANON_PUBLICA" \
     -H "Authorization: Bearer <access_token da Carol>"
```
**Espere ver:** `[]`. Repetindo com o token do Wagner, os documentos aparecem.

### 7b. Mas a Carol VÊ o próprio salário
Ainda como Carol, abra **Cartão de Ponto**. **Espere ver:** os cartões "Salário
fixo", "Vale refeição", "Assiduidade", "Desempenho" e "Total do mês" com os
**valores dela**, não `R$ 0,00`. Zero nesses cinco cartões é o sintoma de
`carregarRH()` não ter sido chamada no login (item 22) ou de `totalRemuneracao`
ainda estar lendo `rh` em vez de `remuneracao`. E confirme o outro lado — que é
**só** a dela:
```
curl -s "https://SEUPROJETO.supabase.co/rest/v1/docs?colecao=eq.remuneracao&select=id" \
     -H "apikey: SUA_CHAVE_ANON_PUBLICA" -H "Authorization: Bearer <token da Carol>"
```
**Espere ver:** exatamente **uma** linha, com o `user_id` dela. (Item 22)

### 8. Realtime entre duas abas
Duas abas na mesma loja. Na aba A, registre uma venda. **Espere ver:** a venda
aparecer na lista da aba B **sem F5**, em poucos segundos. Repita com um cliente
novo. Feche a aba A e confirme, no painel (Database → Realtime inspector), que a
assinatura dela caiu.

**Títulos NÃO entram neste teste.** Na fase 1 há Realtime só em `pedidos` e
`clientes` (item 20): uma baixa de título feita na aba A **não** aparece sozinha
na aba B, e isso é o comportamento esperado — Contas a Receber recarrega quando
alguém entra na tela. (Item 20)

### 9. Export JSON — e o `config/usuarios` fora do mapa
Configurações › Empresa → **Baixar backup do dia**. **Espere ver:** um arquivo
`minasfiltros-mf-2026-09-09.json`. Abra e confira, com o `Ctrl+F` do editor:

- tem as coleções da **loja atual** e `_meta` com data e autor;
- **não tem** `rh`, `remuneracao`, `facial` nem `ponto_fotos`;
- dentro de `config`, **não tem** o documento `usuarios` nem `celebracoes`;
- busque por `"senha"`, `"salario"`, `"ctps"` e `"facial"` no arquivo inteiro:
  **zero ocorrências** (são campos que só existiam no `config/usuarios` e no RH).

> O **CPF do cliente** continua no backup, e isso é de propósito: ele está em
> `clientes.doc` (e `conjcpf`, do cônjuge), é a carteira da empresa e sem ele o
> JSON não restaura nada. O que o teste procura é dado de **colaborador**. O
> arquivo baixado é, ainda assim, um documento com dado pessoal de cliente:
> guarde-o como tal, não mande por WhatsApp.

E no SQL Editor, que o documento antigo já foi embora (passo 9 do painel):
```sql
select count(*) from public.docs where colecao='config' and id='usuarios';
```
**Espere ver: `0`.** Se vier `1`, o backup pode estar limpo e o vazamento
continuar de pé — o documento é legível por qualquer autenticado pelo REST,
sem passar por tela nenhuma.

Como Carol (sem a ação `exportar`), o botão avisa que ela não tem permissão.
(Itens 27, 27b, 27c)

### 10. Gerador de demo escondido
Abra o site publicado: em Configurações › Empresa **não existe** o card "Dados
de teste". Tente forçar com `?teste=1` na URL — **continua não existindo**
(a chave é o `location.hostname`, não a querystring). Abra o mesmo arquivo em
`localhost` logado como Wagner: o card aparece e funciona. Logado como Carol em
`localhost`, o card aparece mas os dois botões respondem "Indisponível em
produção." Confirme que o resto da tela continua respondendo (se `ligar()`
tivesse quebrado, **nenhum** botão do sistema funcionaria — é o sintoma de ter
apagado o card sem apagar o wiring). (Item 26)

### 11. Renomear função não tranca ninguém
Como Wagner, em Configurações › Permissões, renomeie a função **`Prospector`**
para `Prospecção` e salve. **Espere ver:** o toast "Função salva.", a lista
redesenhada na hora (sem F5) e, no banco:
```sql
select nome, funcao from public.perfis where funcao in ('Prospector','Prospecção');
```
a Jaqueline já com `Prospecção`. Depois **entre como ela**: o menu tem que vir
igual ao de antes. Se vier o menu de Vendedor, `perfis.funcao` ficou com o nome
antigo — é o item 14b que não foi aplicado. Renomeie de volta ao terminar.
(Item 14b)

---

# ANEXO — o que NÃO muda

Vale registrar, para ninguém procurar problema onde não tem:

- **`col(n)`, `grava()`, `apaga()` mantêm a assinatura.** O adapter imita a
  superfície do banco antigo de propósito; os ~80 pontos de gravação continuam
  chamando `grava("titulos",t)` como sempre. O que muda é que agora o erro
  chega até eles.
- **`db.doc("config/<id>").get()` continua devolvendo `exists` como
  propriedade** (não método) e `data()` idempotente — como o HTML espera nas
  onze leituras de `config/*`.
- **Produtos, fornecedores, centros de custo e todos os `config/*` continuam
  globais**, sem coluna `loja` (o adapter grava `loja = null` neles).
  Estoque continua dentro do produto, em `p.estoque[loja]`.
- **`d.data()` pode voltar vazio** e o HTML já trata com `||{}`.
- **Ordem de retorno agora é estável** (id ascendente), o que antes era
  indefinido.

## O que ficou de fora desta fase (proposital)

1. **Transação nas operações compostas.** `darEntrada` (50+ writes), a baixa de
   título e a transferência entre caixas continuam sem tudo-ou-nada. O item 17
   faz elas **avisarem** quando quebram no meio; virar RPC transacional é fase 2.
2. **Edge Function de convite.** Com 7 pessoas, criar acesso pelo painel é mais
   barato que manter uma função com service_role.
3. **Storage para as fotos.** `ponto_fotos` em `jsonb` aguenta o volume atual
   (~8–13 MB/mês em base64 se todos baterem 4 vezes por dia). Passando disso,
   troque por Supabase Storage guardando só o caminho no documento.
4. **Migração dos dados antigos.** Este documento trata da troca do banco. Levar
   o conteúdo do artifact para o Postgres é tarefa própria — e a ordem certa é:
   exportar do artifact → conferir → importar → **só então** semear os
   numeradores (passo 6 do painel, que os deriva por SQL do que foi importado) →
   copiar CPF/salário do `config/usuarios` velho para `rh` e `remuneracao` →
   apagar o `config/usuarios` e ligar a policy restritiva (passo 9).
5. **Realtime em `titulos`.** Fica em `pedidos` e `clientes`. A razão está no
   item 20: cada evento rebaixa a coleção inteira, e uma venda em 12x gera 12
   eventos.
