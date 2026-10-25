import AppKit
import GravadorCore
import SwiftUI

/// Gera as imagens da documentação renderizando as telas reais com dados de exemplo:
/// `open -W Gravador.app --args --screenshots` → PNGs em `<container>/tmp/screenshots/`.
/// Não precisa de permissão de Gravação de Tela: as views são desenhadas fora da tela.
@MainActor
enum Screenshots {
    /// Dispositivos fictícios para não expor nomes reais nas imagens.
    static var demoInputDevices: [InputDevice]?

    static var requested: Bool { CommandLine.arguments.contains("--screenshots") }

    static func run() async -> Int32 {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("screenshots", isDirectory: true)
        try? FileManager.default.removeItem(at: out)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let state = AppState.shared
        state.outputFolder.overrideURL = makeDemoMeetings()
        demoInputDevices = [
            InputDevice(id: 1, uid: "demo.headset", name: "Headset USB"),
            InputDevice(id: 2, uid: "demo.airpods", name: "AirPods Pro"),
        ]
        let startedAt = Date().addingTimeInterval(-(12 * 60 + 34))
        let models = ["openai_whisper-large-v3-v20240930_turbo", "openai_whisper-large-v3-v20240930_turbo_632MB"]

        state.applyDemo(status: .recording(label: "Zoom", startedAt: startedAt), segments: demoSegments,
                        detected: .zoom, suppressed: false, models: models,
                        microphoneClients: ["com.google.Chrome.helper", "us.zoom.xos"])

        await window("Transcrição ao vivo", size: CGSize(width: 620, height: 470),
                     LiveTranscriptView().environmentObject(state), to: out, name: "transcricao-ao-vivo")
        await window("Reuniões gravadas", size: CGSize(width: 900, height: 480),
                     MeetingsListView(selectFirst: true).environmentObject(state), to: out, name: "reunioes-gravadas")
        await image(MenuMock(variant: .recording), to: out, name: "menu-gravando")
        await image(MenuMock(variant: .idle), to: out, name: "menu-parado")
        await image(MenuBarStates(), to: out, name: "barra-de-menu")

        let tabs: [(SettingsView.Tab, CGFloat, String)] = [
            (.general, 720, "preferencias-geral"),
            (.transcription, 620, "preferencias-transcricao"),
            (.storage, 300, "preferencias-armazenamento"),
            (.privacy, 520, "preferencias-privacidade"),
        ]
        for (tab, height, name) in tabs {
            await window("Preferências", size: nil,
                         SettingsView(tab: tab, height: height).environmentObject(state), to: out, name: name)
        }

        state.applyDemo(status: .idle, segments: [], detected: nil, suppressed: false, models: models, microphoneClients: [])
        await window("Configuração inicial", size: nil, SetupView().environmentObject(state), to: out, name: "configuracao-inicial")

        print("SCREENSHOTS: \(out.path)")
        return 0
    }

    // MARK: - Renderização

    /// Desenha a view numa janela real (com barra de título) e salva em PNG 2x.
    private static func window<V: View>(_ title: String, size: CGSize?, _ view: V, to folder: URL, name: String) async {
        let hosting = NSHostingView(rootView: view)
        let contentSize = size ?? hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: contentSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = title
        window.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: 40, y: 40))
        window.alphaValue = 0.001 // fica "na tela" para o SwiftUI montar listas, mas invisível
        // Janela ativa (key) para os controles aparecerem com a cor de destaque, como no uso real.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(900))
        hosting.layoutSubtreeIfNeeded()
        let frame = window.contentView?.superview ?? hosting
        save(frame, to: folder.appendingPathComponent("\(name).png"))
        window.close()
    }

    /// Desenha uma view sem janela (menus e ícones).
    private static func image<V: View>(_ view: V, to folder: URL, name: String) async {
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, .light))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = hosting
        window.alphaValue = 0.001
        window.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(400))
        save(hosting, to: folder.appendingPathComponent("\(name).png"))
        window.close()
    }

    private static func save(_ view: NSView, to url: URL, scale: CGFloat = 2) {
        let bounds = view.bounds
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * scale),
                                         pixelsHigh: Int(bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    // MARK: - Dados de exemplo

    static let demoSegments: [TranscriptSegment] = [
        .init(track: .system, start: 3, end: 9, language: "pt", text: "Bom dia, pessoal! Vamos começar a reunião de planejamento do próximo trimestre."),
        .init(track: .microphone, start: 10, end: 14, language: "pt", text: "Bom dia! Eu trouxe os números de marketing para a gente revisar."),
        .init(track: .system, start: 15, end: 22, language: "pt", text: "Ótimo. Primeiro item da pauta é o orçamento. Tiveram algum desvio no último mês?"),
        .init(track: .microphone, start: 23, end: 31, language: "pt", text: "Ficamos uns oito por cento abaixo do previsto, principalmente por causa da campanha que foi adiada."),
        .init(track: .system, start: 33, end: 40, language: "en", text: "Thanks for joining, everyone. I think we should prioritize the mobile release before the end of November."),
        .init(track: .microphone, start: 41, end: 45, language: "en", text: "Agreed. I'll share the updated timeline after the call."),
        .init(track: .system, start: 47, end: 53, language: "es", text: "Perfecto, yo me encargo de enviar el informe de ventas al equipo de Ciudad de México mañana."),
        .init(track: .microphone, start: 55, end: 60, language: "pt", text: "Fechado. Então os próximos passos ficam registrados aqui na transcrição."),
    ]

    private static func makeDemoMeetings() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("demo-reunioes", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        let meetings: [(String, TimeInterval)] = [("Zoom", -3_600), ("Teams", -86_400), ("Google Meet", -2 * 86_400), ("Manual", -5 * 86_400)]
        for (label, offset) in meetings {
            let date = Date().addingTimeInterval(offset)
            let folder = MeetingFolderNaming.folder(in: root, startedAt: date, label: label)
            if let writer = try? TranscriptWriter(folder: folder, title: label, startedAt: date) {
                for segment in demoSegments { try? writer.append(segment) }
                try? writer.finish(endedAt: date.addingTimeInterval(60), duration: 60)
            }
            try? FileManager.default.setAttributes([.creationDate: date], ofItemAtPath: folder.path)
        }
        return root
    }
}

// MARK: - Reconstruções do menu da barra

/// Reconstrução visual do menu da barra (NSMenu não pode ser desenhado fora da tela).
/// Os itens espelham `MenuContent`.
private struct MenuMock: View {
    enum Variant { case recording, idle }
    let variant: Variant

    private enum Row: Hashable {
        case info(String)
        case item(String, shortcut: String? = nil, highlighted: Bool = false)
        case separator
    }

    private var rows: [Row] {
        var rows: [Row]
        switch variant {
        case .recording:
            rows = [.info("● Gravando Zoom — 12:34"), .item("Parar e salvar", shortcut: "⌘S", highlighted: true),
                    .item("Parar e descartar")]
        case .idle:
            rows = [.info("Revisando transcrição… 42%"), .info("Teams detectado"), .item("Iniciar gravação", shortcut: "⌘R", highlighted: true)]
        }
        rows += [.separator, .item("Transcrição ao vivo…", shortcut: "⌘T"), .item("Reuniões gravadas…"),
                 .item("Abrir última reunião"), .separator, .info("Transcrição local: pronta"), .separator,
                 .item("Configuração inicial…"), .item("Preferências…", shortcut: "⌘,"), .item("Sair", shortcut: "⌘Q")]
        return rows
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            MenuBarStrip(recording: variant == .recording)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    rowView(row)
                }
            }
            .padding(5)
            .frame(width: 290)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.965)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
            .padding(.trailing, 70)
        }
        .padding(.bottom, 28)
        .frame(width: 460)
        .background(Color.white)
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        switch row {
        case .separator:
            Divider().padding(.vertical, 5).padding(.horizontal, 9)
        case .info(let text):
            Text(text).foregroundStyle(.secondary).padding(.horizontal, 9).padding(.vertical, 3)
        case .item(let text, let shortcut, let highlighted):
            HStack {
                Text(text)
                Spacer()
                if let shortcut { Text(shortcut).foregroundStyle(highlighted ? .white.opacity(0.85) : .secondary) }
            }
            .foregroundStyle(highlighted ? .white : .primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(highlighted ? Color.accentColor : .clear))
        }
    }
}

/// Faixa da barra de menu com o ícone do Gravador.
private struct MenuBarStrip: View {
    let recording: Bool

    var body: some View {
        HStack(spacing: 18) {
            Spacer()
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            HStack(spacing: 4) {
                if recording {
                    Image(nsImage: MenuBarLabel.recordingIcon)
                    Text("12:34").monospacedDigit()
                } else {
                    Image(systemName: "waveform")
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.1)))
            Text("sáb. 14:42")
        }
        .font(.system(size: 13))
        .padding(.horizontal, 14)
        .frame(height: 26)
        .background(Color(white: 0.92))
    }
}

/// Os três estados do ícone na barra de menu.
private struct MenuBarStates: View {
    var body: some View {
        HStack(spacing: 28) {
            state(Image(systemName: "waveform"), caption: "Aguardando reunião")
            state(Image(systemName: "waveform.slash"), caption: "Pausado por você")
            state(HStack(spacing: 4) {
                Image(nsImage: MenuBarLabel.recordingIcon)
                Text("12:34").monospacedDigit()
            }, caption: "Gravando")
        }
        .padding(20)
        .background(Color.white)
    }

    private func state<V: View>(_ icon: V, caption: String) -> some View {
        VStack(spacing: 8) {
            icon
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color(white: 0.92)))
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
    }
}
