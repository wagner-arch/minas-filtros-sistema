# Aplicativo Minas Filtros — como gerar e instalar nos celulares

Tudo em português simples, na ordem de fazer. Você não precisa instalar nada no
computador: o GitHub monta o arquivo de instalação de graça.

---

## Parte 1 — Pegar o arquivo de instalação (você faz uma vez)

1. Abra **github.com/wagner-arch/minas-filtros-sistema** e entre na sua conta.
2. Clique na aba **Actions** (fica no alto, ao lado de Code e Issues).
3. Na coluna da esquerda, clique em **Aplicativo Android**.
4. Clique na execução mais recente da lista (a de cima).
5. Role até o fim da página, na caixa **Artifacts**, e clique em
   **minas-filtros-apk**. Vai baixar um arquivo `.zip`.
6. Abra o `.zip`: dentro dele está o arquivo que termina em **`.apk`**. Esse é o
   aplicativo. Tire-o de dentro do zip.

> **Dica:** faça isso **pelo celular**, direto no navegador. Aí o arquivo já
> fica no celular e você pula a parte de passar do computador para o telefone.
> Se baixar no computador, mande para o celular por WhatsApp, cabo ou Drive.

Se a lista de execuções estiver vazia, clique no botão **Run workflow** (do lado
direito) para o GitHub montar o aplicativo agora. Leva uns 5 minutos.

---

## Parte 2 — Instalar em cada celular (uns 3 minutos por aparelho)

1. No celular, abra o arquivo `.apk` (pela pasta **Downloads** ou pela
   notificação do download).
2. O Android vai avisar que **não instala aplicativo de fora da loja**. Toque em
   **Configurações** no próprio aviso e ligue a chave
   **Permitir desta fonte** (ou "Instalar apps desconhecidos"). Volte e toque em
   **Instalar**.
3. Pode aparecer **"Enviar para análise?"** do Play Protect — toque em
   **Instalar sem verificar** (ou "Instalar mesmo assim"). É normal: o
   aplicativo é só nosso, não está na loja.
4. Abra o aplicativo **Minas Filtros** (ícone azul com a gota).
5. Ele vai pedir permissões, nesta ordem — **aceite todas**:
   - **Localização** → escolha **Ao usar o app**;
   - em seguida aparece outra tela de localização → escolha
     **PERMITIR SEMPRE**. *Esta é a mais importante: sem ela a localização
     para quando a tela apaga.*
   - **Notificações** → **Permitir**.
6. Faça o login do vendedor, com o mesmo e-mail e senha do sistema.
7. Na primeira entrada aparece o **termo de ciência**. O vendedor lê, assina com
   o dedo e toca em **Li, concordo e assino**.
8. Pronto: aparece na barra de cima o aviso fixo
   **"Minas Filtros: localização ativa"**. É assim que se sabe que está ligado.

**Confira que ficou certo:** arraste a barra de notificações para baixo. O aviso
"Minas Filtros: localização ativa" tem de estar lá. Se não estiver, o rastreio
não está rodando.

---

## Parte 3 — Liberar a bateria (OBRIGATÓRIO, senão o celular desliga o aplicativo)

O Android economiza bateria matando aplicativos que ficam rodando. Sem estes
ajustes, a localização **para sozinha** depois de algumas horas. Faça em cada
celular, uma vez.

### Samsung (One UI)

1. **Ajustes** → **Bateria e cuidados do dispositivo** → **Bateria**.
2. Toque em **Limites de uso em segundo plano**.
3. Entre em **Apps em suspensão** e em **Apps em suspensão profunda**: se o
   **Minas Filtros** estiver em alguma das duas listas, **remova** (toque no
   lixo ou no "−").
4. Volte, toque em **Apps nunca suspensos** → **+** → marque **Minas Filtros**.
5. Ainda em Ajustes: **Aplicativos** → **Minas Filtros** → **Bateria** →
   escolha **Sem restrições**.
6. Em **Ajustes** → **Aplicativos** → **Minas Filtros** → **Permissões** →
   **Localização** → confirme **Permitir sempre**.
7. *(Recomendado)* **Ajustes** → **Bateria** → desligue
   **Otimizar configurações** e **Colocar apps não usados em suspensão**.

### Xiaomi / Redmi / Poco (MIUI e HyperOS) — o mais chato, são 4 passos

1. **Ajustes** → **Aplicativos** → **Gerenciar aplicativos** → **Minas Filtros**:
   - **Economia de bateria** → escolha **Sem restrições**;
   - ligue **Início automático** (ou "Autostart");
   - em **Permissões** → **Localização** → **Permitir sempre**;
   - ligue **Exibir janela pop-up** e **Mostrar em segundo plano**, se aparecer.
2. **Travar o aplicativo na memória** (este é o que mais resolve no Redmi):
   abra a tela de **aplicativos recentes** (o botão de quadradinhos ou o
   arrastar para cima), **arraste o cartão do Minas Filtros para baixo** até
   aparecer um **cadeado**. Com o cadeado, o sistema não fecha mais.
3. **Ajustes** → **Bateria** → desligue **Economia de bateria** e, se existir,
   **Economia de bateria do MIUI** para este aplicativo.
4. **Ajustes** → **Senha e segurança** → **Privacidade** → **Permissões** →
   confirme **Localização: permitir sempre**.

> No Redmi, se depois de alguns dias o aviso "localização ativa" sumir sozinho,
> quase sempre é o **cadeado dos aplicativos recentes** que se perdeu numa
> atualização. Refaça o passo 2.

---

## Parte 4 — Atualização: daqui para a frente é automática

**As telas do sistema continuam atualizando sozinhas**, como hoje: nada a fazer.

**A parte do aplicativo (a localização) agora também se atualiza sozinha:**

1. Ao abrir, o aplicativo confere se há versão nova.
2. Havendo, ele mostra **"Atualizar agora?"** com o que mudou.
3. O vendedor toca em **Atualizar agora**: o aplicativo baixa (uns poucos
   megabytes) e o Android pede **uma confirmação na tela** — toque em
   **Instalar**. Essa confirmação é obrigatória do Android, para aplicativo que
   não vem da loja; não existe jeito de pular.
4. **O login e o termo assinado continuam valendo.** Não precisa entrar de novo
   nem assinar outra vez.

Se o celular ficar dias sem reabrir o aplicativo, o próprio **sistema avisa**:
aparece uma faixa amarela no alto da tela dizendo que há versão nova, com o
botão **Atualizar agora**.

Na primeira vez, o Android pode pedir para **liberar a instalação** por este
aplicativo: ele abre a tela certa, basta ligar a chave e voltar.

> **Só uma vez, nesta troca:** quem já instalou a versão anterior precisa
> **desinstalar e instalar de novo** (Parte 1 e Parte 2). Isso acontece porque a
> assinatura do aplicativo mudou — antes ela mudava a cada compilação, e era
> justamente isso que impedia atualizar por cima. **Desta vez para a frente, a
> atualização é por cima**, sem desinstalar nada.

---

## Perguntas que costumam aparecer

**O vendedor pode desligar o rastreio?**
Saindo do sistema, sim — e o Administrador recebe o aviso no sino
("Rastreio de [nome] desligado às [hora]"). O sistema vê isso pelo último ponto
registrado, então o aviso sai também quando o celular mata o aplicativo.

**Gasta muita internet?**
Uns 30 a 50 MB por mês em cada celular.

**Gasta muita bateria?**
O aplicativo usa a localização econômica do Android (rede e Wi-Fi, não só GPS),
registra 1 ponto por minuto andando e 1 a cada 5 minutos parado. Num dia de
trabalho, gasta em torno de 10% a 15% da bateria. O celular fica carregando na
loja depois do expediente.

**E se o celular ficar sem internet?**
Os pontos ficam guardados no próprio celular e sobem quando a internet voltar.
Nada se perde.

**O aplicativo registra fora do expediente?**
Registra sempre que o usuário estiver conectado — é o que está escrito no termo.
Para parar, basta sair do sistema.

**E se um celular da empresa for perdido ou roubado?**
A gestão desconecta aquele usuário à distância, de qualquer computador:
**Configurações › Usuários**, abre o colaborador e clica em
**"Celular perdido — desconectar à distância"**. Na hora:

- a sessão aberta naquele celular é encerrada;
- o registro de localização **para**;
- aquele login não entra mais, nem no celular nem no computador;
- nada do histórico é apagado.

Quando o celular for recuperado (ou o colaborador receber outro), o mesmo botão
vira **"Reconectar o acesso"** e ele volta a entrar com o mesmo e-mail e a mesma
senha. Como o aplicativo **não mostra nada sem login**, quem estiver com o
aparelho não vê cliente, venda nem valor.

**Preciso assinar o termo de novo quando trocar de celular?**
Não. O termo assinado fica **guardado no sistema**, ligado ao usuário — não no
aparelho. Reinstalar o aplicativo ou trocar o celular não pede assinatura nova.
Só se pede de novo quando o **texto** do termo mudar, e aí a tela explica o
motivo (a assinatura anterior continua guardada).
