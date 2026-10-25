# Gravador de Reuniões

App de barra de menu para macOS que **grava e transcreve em tempo real** reuniões de **Zoom, Microsoft Teams e Google Meet**, tanto no app nativo quanto no navegador. Tudo roda **100% no seu Mac**: o app não tem permissão de acesso à rede, então áudio, transcrição e arquivos nunca saem da máquina.

<p align="center">
  <img src="docs/images/transcricao-ao-vivo.png" width="620" alt="Janela de transcrição ao vivo durante uma reunião do Zoom">
</p>

- 🎙️ **Início automático:** detecta quando Zoom, Teams, Meet, Webex ou Slack começam a usar o microfone.
- ✋ **Início e parada manuais:** sempre disponíveis no menu. Uma parada manual não é desfeita pela detecção automática.
- 📝 **Transcrição ao vivo:** usa Whisper large-v3 turbo no Neural Engine, com cerca de 1 s por fala, e separa **Eu** (seu microfone) de **Outros** (áudio da reunião).
- 🌎 **Português, inglês e espanhol:** o idioma é detectado a cada fala, inclusive em reuniões que misturam idiomas.
- 🔒 **Sem nuvem:** o app roda em sandbox sem permissão de rede, e um script verifica isso.

---

## Sumário

1. [Requisitos](#requisitos)
2. [Instalação](#instalação)
3. [Primeiro uso](#primeiro-uso)
4. [Como usar](#como-usar)
5. [Preferências](#preferências)
6. [Onde ficam as gravações](#onde-ficam-as-gravações)
7. [Privacidade: como garantir que nada vai para a nuvem](#privacidade-como-garantir-que-nada-vai-para-a-nuvem)
8. [Solução de problemas](#solução-de-problemas)
9. [Desenvolvimento](#desenvolvimento)

---

## Requisitos

| | |
|---|---|
| Mac | Apple Silicon (M1 ou mais novo) |
| macOS | 15 (Sequoia) ou mais novo |
| Ferramentas | Xcode 16+ e [Homebrew](https://brew.sh) |
| Espaço | ~1,5 GB para o modelo de transcrição |

## Instalação

### 1. Baixe o código e as ferramentas

```bash
git clone https://github.com/tspineli/gravador.git
cd gravador
brew install xcodegen
```

### 2. Baixe o modelo de transcrição (uma única vez)

```bash
scripts/fetch-model.sh
```

O script baixa o Whisper large-v3 turbo (~1,5 GB) do Hugging Face para `./models/`. Esse é o **único** download do processo, e ele roda fora do app. O Gravador nunca acessa a internet.

> Para um modelo menor e mais rápido (com precisão um pouco menor):
> `scripts/fetch-model.sh ./models openai_whisper-large-v3-v20240930_turbo_632MB`

### 3. Compile e instale

```bash
scripts/install.sh
```

O script gera o projeto, compila em Release, verifica que o app não tem acesso à rede e o copia para `/Applications`.

**Assinatura:** o `project.yml` usa o Team ID do autor. Escolha uma das opções:

```bash
TEAM=SEU_TEAM_ID scripts/install.sh   # com conta Apple Developer (recomendado)
ADHOC=1 scripts/install.sh            # sem conta: assinatura local
```

Com `ADHOC=1`, o macOS pede as permissões de novo a cada recompilação.

### 4. Abra o app

```bash
open /Applications/Gravador.app
```

O ícone de ondas sonoras aparece na barra de menu. O app não tem ícone no Dock.

## Primeiro uso

Na primeira vez, abre a janela **Configuração inicial**:

<p align="center">
  <img src="docs/images/configuracao-inicial.png" width="540" alt="Janela de configuração inicial">
</p>

1. **Pasta das reuniões:** escolha onde salvar as gravações (sugestão: `Documentos/Gravador Reuniões`).
2. **Modelo de transcrição:** clique em **Importar…** e selecione `models/openai_whisper-large-v3-v20240930_turbo`. O app copia o modelo para a área dele.
3. **Microfone:** clique em **Permitir…** e aceite o pedido do macOS.
4. **Reuniões no navegador (opcional):** permita "Gravação de Tela" para o início automático de Meet, Teams e Zoom no navegador. A permissão serve **só para ler o título das abas**; nenhuma imagem da tela é capturada.

Na primeira gravação, o macOS pede a permissão de **áudio do sistema**, necessária para gravar a voz dos outros participantes.

> A primeira carga do modelo leva de 1 a 2 minutos, porque o macOS o compila para o seu chip. Depois disso, carrega em cerca de 1 segundo.

Dá para reabrir esta janela pelo menu › **Configuração inicial…**.

## Como usar

### O ícone na barra de menu

<p align="center">
  <img src="docs/images/barra-de-menu.png" width="360" alt="Estados do ícone: aguardando, pausado e gravando">
</p>

| Ícone | Significado |
|---|---|
| Ondas | Aguardando: monitorando se alguma reunião começa |
| Ondas cortadas | Você parou manualmente; o app não grava de novo até essa reunião terminar |
| ● vermelho + tempo | Gravando |

### Gravação automática

Ao entrar numa reunião, o Gravador começa a gravar sozinho em cerca de 2 segundos e mostra uma notificação. Ao sair da chamada, ele espera 15 segundos (configurável), encerra, termina a transcrição e salva tudo.

| Onde está a reunião | Como é detectada |
|---|---|
| Zoom, Teams, Webex ou Slack (app) | O app de reunião abre o microfone |
| Meet, Teams ou Zoom no navegador (Chrome, Safari, Edge, Brave, Arc, Firefox) | O navegador abre o microfone **e** o título da aba confirma a reunião |
| Navegador **sem** a permissão de títulos | Chega uma notificação **"Reunião no Chrome? Gravar"** e um clique inicia a gravação |

### Parar e iniciar manualmente

Clique no ícone da barra de menu:

<p align="center">
  <img src="docs/images/menu-gravando.png" width="420" alt="Menu durante uma gravação">
  &nbsp;&nbsp;
  <img src="docs/images/menu-parado.png" width="420" alt="Menu sem gravação">
</p>

- **Parar e salvar** (⌘S): encerra e salva áudio e transcrição.
- **Parar e descartar:** encerra e **apaga** tudo o que foi gravado nessa reunião. Use quando você não tiver permissão para gravar.
- **Iniciar gravação** (⌘R): grava na hora, mesmo sem reunião detectada (ex.: uma ligação em outro app). A gravação manual só para quando você mandar.

> **Parou no meio da reunião?** O Gravador **não volta a gravar sozinho** até você sair daquela chamada. A próxima reunião volta a ser gravada automaticamente.

### Transcrição ao vivo

Menu › **Transcrição ao vivo…** (⌘T) abre a janela do topo desta página. Cada fala aparece de 1 a 3 segundos depois de terminar, com horário, quem falou (**Eu** / **Outros**) e o idioma detectado.

### Reuniões gravadas

Menu › **Reuniões gravadas…** lista as reuniões salvas e mostra a transcrição de cada uma:

<p align="center">
  <img src="docs/images/reunioes-gravadas.png" width="760" alt="Lista de reuniões gravadas">
</p>

## Preferências

Menu › **Preferências…** (⌘,)

<table>
<tr>
<td width="50%"><img src="docs/images/preferencias-geral.png" alt="Preferências: Geral"></td>
<td width="50%"><img src="docs/images/preferencias-transcricao.png" alt="Preferências: Transcrição"></td>
</tr>
<tr>
<td><b>Geral:</b> liga e desliga o início automático, a notificação, o tempo até encerrar, quais apps monitorar, a detecção no navegador e a abertura junto com o Mac.</td>
<td><b>Transcrição:</b> modelo, idiomas das reuniões, <b>qual microfone gravar</b> e cancelamento de eco.</td>
</tr>
<tr>
<td><img src="docs/images/preferencias-armazenamento.png" alt="Preferências: Armazenamento"></td>
<td><img src="docs/images/preferencias-privacidade.png" alt="Preferências: Privacidade"></td>
</tr>
<tr>
<td><b>Armazenamento:</b> pasta onde as reuniões são salvas.</td>
<td><b>Privacidade:</b> status das permissões e diagnóstico de quais apps estão usando o microfone agora.</td>
</tr>
</table>

Dicas:

- **Escolha o mesmo microfone do Zoom/Teams/Meet** em Transcrição › Microfone. O padrão do sistema pode ser outro dispositivo (ex.: um microfone virtual).
- **Sem fone de ouvido**, o microfone capta a voz dos outros pelo alto-falante. O app descarta automaticamente essas falas repetidas. Se ainda aparecerem, ligue o **Cancelamento de eco**.
- **Reunião só em português?** Deixe só Português marcado. A transcrição fica mais rápida e não confunde com outros idiomas.

## Onde ficam as gravações

Cada reunião vira uma pasta dentro da pasta escolhida:

```
Gravador Reuniões/
└── 2026-10-25 14h30 - Zoom/
    ├── mic.m4a             sua voz
    ├── sistema.m4a         os outros participantes
    ├── transcricao.md      transcrição legível
    └── transcricao.jsonl   um trecho por linha (para scripts)
```

Exemplo de `transcricao.md`:

```markdown
# Reunião Zoom — 25/10/2026 14:30

_Início: 25/10/2026 14:30_

**[00:03] Outros:** Bom dia, pessoal! Vamos começar a reunião de planejamento do próximo trimestre.

**[00:10] Eu:** Bom dia! Eu trouxe os números de marketing para a gente revisar.

---
_Fim: 25/10/2026 15:12 · duração 42:10_
```

A transcrição é salva **enquanto** a reunião acontece. Se o Mac travar, o que já foi transcrito não se perde.

## Privacidade: como garantir que nada vai para a nuvem

Três camadas garantem isso:

1. **Bloqueio pelo macOS:** o app roda no **App Sandbox sem os entitlements `network.client`/`network.server`**. O próprio sistema operacional impede qualquer conexão, inclusive de bibliotecas de terceiros.
2. **Código:** o app não usa nenhuma API de rede.
3. **Execução:** dá para conferir que o processo não abre nenhum socket.

Para verificar as três:

```bash
scripts/verify-no-network.sh /Applications/Gravador.app
```

```
1) Entitlements de /Applications/Gravador.app
  ✅ App Sandbox ligado
  ✅ nenhum entitlement de rede (o macOS bloqueia qualquer conexão)
2) APIs de rede no código do app
  ✅ nenhuma ocorrência de: URLSession, URLRequest, NWConnection, ...
3) Sockets do processo em execução
  ✅ PID 33441 sem nenhum socket de rede

OK: o Gravador não acessa a rede.
```

Também dá para gravar uma reunião com o Wi-Fi desligado: tudo funciona igual.

> ⚖️ **Consentimento:** o Gravador avisa com notificação e mostra o indicador vermelho enquanto grava, mas cabe a você seguir as regras da empresa e da legislação local e avisar os participantes. Na dúvida, use **Parar e descartar**.

## Solução de problemas

| Problema | O que fazer |
|---|---|
| A minha voz não aparece (só "Outros") | Em Preferências › Transcrição, escolha o microfone certo. Confira a permissão em Ajustes do Sistema › Privacidade e Segurança › **Microfone**. |
| A voz dos outros não aparece | Libere o Gravador em Ajustes do Sistema › Privacidade e Segurança › **Gravação de Tela e Áudio do Sistema** › seção "Somente Áudio do Sistema". |
| Não começa a gravar sozinho no navegador | Sem a permissão de títulos, chega uma notificação: clique em **Gravar**. Para iniciar sem confirmar, permita "Gravação de Tela" em Preferências › Geral. |
| Não começa a gravar sozinho num app | Veja em Preferências › Privacidade › Diagnóstico qual bundle ID está usando o microfone e confira se o app está ligado em Preferências › Geral. |
| "Transcrição: nenhum modelo instalado" | Rode `scripts/fetch-model.sh` e importe a pasta em Preferências › Transcrição › **Importar modelo…**. |
| A primeira transcrição demora | É normal na primeira carga do modelo (1–2 min) e depois de atualizar o macOS. |
| Aparecem falas repetidas como "Eu" | É eco do alto-falante: use fone de ouvido ou ligue o Cancelamento de eco. |

Logs detalhados (inclusive quais apps usam o microfone):

```bash
log stream --info --predicate 'subsystem == "com.tiagospineli.gravador"'
```

## Desenvolvimento

Arquitetura, testes, autotestes e como regenerar estes prints: veja [docs/DESENVOLVIMENTO.md](docs/DESENVOLVIMENTO.md).

### Créditos

- [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) (MIT): Whisper em Core ML.
- [AudioCap](https://github.com/insidegui/AudioCap) (BSD-2): referência para captura de áudio com Core Audio process taps.
- [OpenAI Whisper](https://github.com/openai/whisper) (MIT): modelo de reconhecimento de fala.
