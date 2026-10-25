import GravadorCore
import SwiftUI

struct LiveTranscriptView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if state.liveSegments.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: "text.bubble", description: Text(emptyMessage))
            } else {
                TranscriptList(segments: state.liveSegments, autoScroll: true)
            }
        }
        .frame(minWidth: 420, minHeight: 320)
    }

    private var header: some View {
        HStack {
            switch state.status {
            case .recording(let label, _):
                Image(systemName: "record.circle.fill").foregroundStyle(.red)
                Text("Gravando \(label)").font(.headline)
                Text(TimeFormatting.clock(state.elapsed)).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Button("Parar e salvar") { state.stopManually(save: true) }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            case .starting:
                ProgressView().controlSize(.small)
                Text("Iniciando…")
                Spacer()
            case .finishing:
                ProgressView().controlSize(.small)
                Text("Finalizando a transcrição…")
                Spacer()
            case .idle:
                Image(systemName: "waveform")
                Text("Sem gravação").font(.headline)
                Spacer()
                Button("Iniciar gravação") { state.startManually() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
    }

    private var emptyTitle: String {
        state.isRecording ? "Aguardando fala…" : "Nenhuma transcrição"
    }

    private var emptyMessage: String {
        switch state.modelState {
        case .missing: return "Instale um modelo em Preferências › Transcrição para transcrever."
        case .loading: return "Carregando o modelo de transcrição (a primeira vez pode levar alguns minutos)."
        default: return state.isRecording ? "O texto aparece alguns segundos depois de cada fala." : "Inicie uma gravação ou entre numa reunião."
        }
    }
}

/// Lista de falas `[mm:ss] Eu/Outros: texto`.
struct TranscriptList: View {
    let segments: [TranscriptSegment]
    var autoScroll = false

    var body: some View {
        ScrollViewReader { proxy in
            List(segments) { segment in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(TimeFormatting.clock(segment.start))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .leading)
                    Text(segment.track.speakerLabel)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(segment.track == .microphone ? Color.accentColor : Color.orange)
                        .frame(width: 52, alignment: .leading)
                    Text(segment.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(segment.language.uppercased())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .id(segment.id)
            }
            .onChange(of: segments.count) {
                guard autoScroll, let last = segments.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }
}
