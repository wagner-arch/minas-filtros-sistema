# A chave do aplicativo — o que fazer, na ordem

**Leia isto antes de qualquer coisa:** essa chave é o que prova que o aplicativo é
nosso. É só com ela que a versão nova instala **por cima** da antiga, sem o
vendedor perder o login nem assinar o termo de novo.

**Se a chave se perder, não existe jeito de recuperar.** Teria de nascer um
aplicativo novo, e cada celular precisaria **desinstalar o atual e instalar o
novo** — perdendo login e termo assinado. É por isso que o item 2 desta lista
(a cópia de segurança) é tão importante quanto o item 1.

A chave **não está** dentro do projeto. O repositório é público, e um arquivo de
chave ali dentro ficaria à vista de qualquer pessoa. Ela foi gerada **fora** do
projeto e os tipos de arquivo de chave (`.jks`, `.keystore`, `.p12`, `.pfx`)
estão no `.gitignore`, para nunca entrarem por acidente.

---

## Onde a chave está agora

Na área de trabalho do seu computador, na pasta:

```
Área de trabalho \ Chave do Aplicativo Minas Filtros
```

Dentro dela, três arquivos:

| Arquivo | O que é |
|---|---|
| `minas-filtros.p12` | **a chave** (2,7 KB) |
| `senha-da-chave.txt` | a senha dela |
| `chave-em-texto-base64.txt` | a mesma chave escrita como texto, para colar no cofre do GitHub |

Dados dela, para conferência: apelido **minasfiltros**, RSA 2048, validade até
**14/10/2056**, impressão digital
`9A3ED34D57C087C775270979A0B0197238ADC91F`.

---

## Passo 1 — Guardar a chave no cofre do GitHub (uns 5 minutos)

É daí que a compilação vai ler a chave. **Segredo do GitHub não pode ser lido de
volta por ninguém**, nem por você: dá para substituir, nunca para ver.

1. Abra **github.com/wagner-arch/minas-filtros-sistema**.
2. Clique em **Settings** (a engrenagem, no alto, à direita).
3. Na coluna da esquerda, desça até **Secrets and variables** e clique em
   **Actions**.
4. Clique no botão verde **New repository secret**. Faça isto **três vezes**:

   **O primeiro — a chave**
   - Name: `MF_CHAVE_BASE64`
   - Secret: abra o arquivo **`chave-em-texto-base64.txt`** (clique duas vezes,
     ele abre no Bloco de Notas), aperte **Ctrl+A** e **Ctrl+C**, e cole aqui
     com **Ctrl+V**. É um texto comprido, de uma linha só.
   - **Add secret**.

   **O segundo — a senha**
   - Name: `MF_CHAVE_SENHA`
   - Secret: abra **`senha-da-chave.txt`**, copie o que está lá e cole aqui.
     Sem espaço antes nem depois.
   - **Add secret**.

   **O terceiro — o apelido**
   - Name: `MF_CHAVE_ALIAS`
   - Secret: escreva exatamente `minasfiltros`
   - **Add secret**.

5. Confira que a lista mostra os três nomes. Os valores aparecem como
   `***` — é assim mesmo.

**Como saber que deu certo:** vá em **Actions › Aplicativo Android › Run
workflow**. Em uns 5 minutos a execução fica **verde**. Se faltar algum segredo,
ela fica vermelha com o recado dizendo qual.

---

## Passo 2 — Duas cópias fora do computador (NÃO pule este passo)

O computador pode queimar, ser formatado ou ser roubado. Faça as duas cópias
hoje.

### Cópia A — pen drive

1. Pegue um pen drive e deixe-o **guardado na gaveta da loja**, não no chaveiro.
2. Espete no computador.
3. Abra a pasta **Chave do Aplicativo Minas Filtros** na área de trabalho.
4. Marque os **três arquivos** (clique no primeiro, segure **Shift**, clique no
   último) e aperte **Ctrl+C**.
5. Abra o pen drive e aperte **Ctrl+V**.
6. Dentro do pen drive, crie uma pasta com o nome
   **`CHAVE DO APLICATIVO - NAO APAGAR`** e ponha os três arquivos dentro.
7. Tire o pen drive e guarde. **Não use esse pen drive para o dia a dia.**

### Cópia B — Google Drive

1. Abra **drive.google.com** com a sua conta da empresa.
2. Clique em **+ Novo › Nova pasta** e chame de
   **`Chave do Aplicativo Minas Filtros`**.
3. Entre na pasta e arraste os **três arquivos** para dentro.
4. Clique com o botão direito na pasta › **Compartilhar** › e confira que está
   **"Restrito — somente pessoas com acesso"**. **Nunca** deixe
   "qualquer pessoa com o link".
5. *(Recomendado)* Clique com o botão direito na pasta e escolha
   **Adicionar atalho ao Drive › Com estrela**, para achar rápido depois.

### Por último, uma anotação de papel

Escreva num papel: *"A chave do aplicativo está no pen drive da gaveta e no
Google Drive, na pasta Chave do Aplicativo Minas Filtros"* e guarde junto dos
documentos da empresa. Quem precisar disso daqui a três anos vai agradecer.

---

## Perguntas

**Preciso guardar a chave no computador depois disso?**
Pode deixar. Só não apague antes de fazer as duas cópias.

**A senha pode ficar no mesmo lugar da chave?**
No seu caso, sim: a chave sozinha não serve para nada sem a senha, e as duas
estão em lugares que só você abre. O risco maior, de longe, é **perder** a
chave, não alguém achá-la.

**Alguém que pegue a chave pode fazer o que?**
Pode montar um aplicativo que o Android aceita instalar por cima do nosso. Como
o aplicativo **não mostra nada sem login**, o estrago possível é pequeno — mas
troque a chave e nos avise se isso acontecer.

**E se eu quiser trocar a chave algum dia?**
Dá, mas todo celular precisa **desinstalar e instalar** uma vez. Trocando,
atualize também a impressão digital conferida em
`.github/workflows/android.yml` (a linha com `9a3ed34d...`), senão a compilação
recusa o arquivo de propósito.

**O que a compilação faz com a chave?**
Escreve a chave num arquivo temporário **fora** da pasta do projeto, assina,
confere que a assinatura é a da empresa e **apaga a chave** em seguida. O
servidor do GitHub é descartado no fim.
