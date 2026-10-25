# Desenvolvimento

## Visão geral

```
                    ┌────────────────────────────────────────────┐
 Core Audio (HAL) ──▶ AudioProcessMonitor: quem usa o microfone? │
 CGWindowList ──────▶ BrowserMeetingClassifier: título da aba    │
                    └──────────────────┬─────────────────────────┘
                                       ▼  (a cada 1 s)
                          MeetingDetector → RecordingStateMachine
                                       │ start / stop / suggest
                                       ▼
                               MeetingRecorder
              ┌────────────────────────┴───────────────────────┐
     MicrophoneCapture (AVAudioEngine)          SystemAudioTap (process tap)
              │                                                 │
       TrackPipeline "Eu"                            TrackPipeline "Outros"
       ├─ AudioFileWriter → mic.m4a                  ├─ AudioFileWriter → sistema.m4a
       └─ ASRResampler → SpeechSegmenter (VAD)       └─ ASRResampler → SpeechSegmenter
                          └──────────────┬──────────────────┘
                                         ▼
                     TranscriptionQueue (um trecho por vez)
                     ├─ WhisperKitEngine (detecção de idioma restrita a PT/EN/ES)
                     ├─ EchoGate (descarta eco do alto-falante na trilha "Eu")
                     └─ TranscriptWriter → transcricao.md / .jsonl  +  UI ao vivo
```

## Estrutura

| Caminho | Conteúdo |
|---|---|
| `project.yml` | Definição do projeto (XcodeGen). O `.xcodeproj` é gerado e não fica versionado. |
| `Packages/GravadorCore` | Lógica pura, sem Core Audio ou AppKit, testada com `swift test`: `RecordingStateMachine`, `SpeechSegmenter`, `EchoGate`, `MeetingCatalog`, `TranscriptFilters`, `LanguagePicker`, `TranscriptWriter`. |
| `Gravador/Audio` | `SystemAudioTap` (Core Audio process tap + aggregate device), `MicrophoneCapture`, `ASRResampler` (16 kHz mono), `AudioFileWriter` (AAC em CAF → m4a). |
| `Gravador/Detection` | `AudioProcessMonitor` (`kAudioProcessPropertyIsRunningInput`), `BrowserMeetingClassifier`, `MeetingDetector`. |
| `Gravador/Transcription` | Protocolo `TranscriptionEngine` e `WhisperKitEngine`. |
| `Gravador/Session` | `MeetingRecorder`, `TrackPipeline`, `TranscriptionQueue`. |
| `Gravador/Storage` | Modelos importados, pasta de saída (bookmark com escopo de segurança), lista de reuniões. |
| `Gravador/App`, `Gravador/UI` | `AppState`, notificações, preferências, menu, janelas, autotestes e gerador de prints. |
| `scripts/` | `fetch-model.sh`, `install.sh`, `verify-no-network.sh`. |

## Build

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project Gravador.xcodeproj -scheme Gravador -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Gravador.app
```

Depois de criar ou remover arquivos `.swift`, rode `xcodegen generate` de novo.

## Testes

```bash
cd Packages/GravadorCore && swift test
```

Os testes cobrem:
- a máquina de estados (início e parada automáticos, supressão depois de parada manual, sugestão para navegador);
- o VAD (cortes, trechos longos, entrada fragmentada);
- a classificação de bundle IDs e títulos de janela;
- os filtros de alucinação e o eco;
- a escrita e releitura da transcrição.

## Autotestes no app real (dentro do sandbox)

```bash
APP=build/Build/Products/Debug/Gravador.app
C=~/Library/Containers/com.tiagospineli.gravador/Data

# Transcrição de um arquivo (o arquivo precisa estar no container, ex.: $C/tmp/)
$APP/Contents/MacOS/Gravador --selftest "$C/tmp/teste.wav"

# Gravação real de mic + sistema por 30 s (pede as permissões em nome do Gravador)
open -n -W $APP --args --capture-test 30 && cat "$C/tmp/capture-test.txt"
```

Para gerar áudio de teste em vários idiomas:

```bash
say -v Luciana -o pt.aiff "Bom dia, vamos começar a reunião."
say -v Samantha -o en.aiff "Let's prioritize the mobile release."
say -v Paulina -o es.aiff "Yo me encargo del informe de ventas."
```

## Regenerar os prints da documentação

```bash
pkill -x Gravador
open -n -W build/Build/Products/Debug/Gravador.app --args --screenshots
cp ~/Library/Containers/com.tiagospineli.gravador/Data/tmp/screenshots/*.png docs/images/
```

O modo `--screenshots` (`Gravador/App/Screenshots.swift`) renderiza as **janelas reais** do app com dados de exemplo, fora da tela, em PNG 2x. Ele não precisa de permissão de Gravação de Tela.

O menu da barra é um `NSMenu`, que não pode ser desenhado fora da tela. Por isso `menu-gravando.png`, `menu-parado.png` e `barra-de-menu.png` são reconstruções em SwiftUI que espelham os itens de `MenuContent.swift`. Se o menu mudar, atualize também `MenuMock` em `Screenshots.swift`.

## Adicionar um app de reunião

1. Com o app numa chamada, veja o bundle ID em Preferências › Privacidade › Diagnóstico, ou nos logs da categoria `detection`.
2. Adicione o prefixo em `MeetingCatalog.nativeApps` (ou um navegador em `MeetingCatalog.browsers`) e, se for um app novo, um caso em `MeetingApp`.
3. Adicione um teste em `CatalogAndFiltersTests`.

## Decisões técnicas

- **Sandbox sem rede** em vez de só "não chamar a rede": garante compliance mesmo que uma dependência tente se conectar.
- **WhisperKit** carrega o modelo de uma pasta local com `download: false`. O tokenizer vem junto na pasta do modelo, então nada é buscado no Hugging Face.
- **Detecção por consulta a cada 1 s**, em vez de property listeners: é mais simples, robusta a processos que aparecem e somem, e tem custo desprezível (<2% de CPU parado).
- **Duas trilhas separadas** dão uma diarização "Eu × Outros" sem custo. A diarização entre os outros participantes pode vir depois (ex.: SpeakerKit).
- **Áudio em AAC dentro de CAF** durante a gravação, porque CAF é tolerante a crash; no fim, é remuxado para `.m4a` sem recodificar.
