import AppKit
import GravadorCore
import SwiftUI

@main
struct GravadorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(state)
        } label: {
            MenuBarLabel(state: state)
        }
        .menuBarExtraStyle(.menu)

        Window("Transcrição ao vivo", id: WindowID.live) {
            LiveTranscriptView()
                .environmentObject(state)
        }
        .defaultSize(width: 560, height: 640)

        Window("Configuração inicial", id: WindowID.setup) {
            SetupView()
                .environmentObject(state)
        }
        .windowResizability(.contentSize)

        Window("Reuniões gravadas", id: WindowID.meetings) {
            MeetingsListView()
                .environmentObject(state)
        }
        .defaultSize(width: 820, height: 560)

        Settings {
            SettingsView()
                .environmentObject(state)
        }
    }
}

enum WindowID {
    static let live = "live"
    static let meetings = "meetings"
    static let setup = "setup"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let file = SelfTest.requestedFile {
            Task {
                Preferences.registerDefaults()
                setvbuf(stdout, nil, _IOLBF, 0)
                exit(await SelfTest.run(file: file))
            }
            return
        }
        if Screenshots.requested {
            Task { @MainActor in
                Preferences.registerDefaults()
                exit(await Screenshots.run())
            }
            return
        }
        if let seconds = SelfTest.requestedCaptureSeconds {
            Task { @MainActor in
                Preferences.registerDefaults()
                exit(await SelfTest.runCapture(seconds: seconds))
            }
            return
        }
        if let seconds = SelfTest.requestedAppTestSeconds {
            Task { @MainActor in exit(await SelfTest.runAppFlow(seconds: seconds)) }
            return
        }
        MainActor.assumeIsolated { AppState.shared.launch() }
    }
}

/// Ícone da barra de menu: vermelho com o tempo decorrido enquanto grava.
struct MenuBarLabel: View {
    @ObservedObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        label
            .task {
                // Primeira execução (ou configuração incompleta): abre a janela de configuração.
                if state.outputFolder.url == nil || state.installedModels.isEmpty {
                    openWindow(id: WindowID.setup)
                }
            }
    }

    @ViewBuilder
    private var label: some View {
        switch state.status {
        case .recording:
            HStack(spacing: 4) {
                Image(nsImage: Self.recordingIcon)
                Text(TimeFormatting.clock(state.elapsed)).monospacedDigit()
            }
        case .starting, .finishing:
            Image(systemName: "ellipsis.circle")
        case .idle:
            Image(systemName: state.isSuppressed ? "waveform.slash" : "waveform")
        }
    }

    static let recordingIcon: NSImage = {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            .applying(.init(paletteColors: [.systemRed]))
        let image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Gravando")!
            .withSymbolConfiguration(config)!
        image.isTemplate = false
        return image
    }()
}
