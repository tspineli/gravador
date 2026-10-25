import AudioToolbox
import AVFoundation
import OSLog

/// Captura o microfone (o escolhido nas Preferências ou o padrão do sistema) com AVAudioEngine. Reinicia sozinho quando o dispositivo muda
/// (ex.: conectar AirPods no meio da reunião).
final class MicrophoneCapture {
    typealias BufferHandler = (AVAudioPCMBuffer, AVAudioTime?) -> Void

    private static let log = Logger(subsystem: "com.tiagospineli.gravador", category: "microphone")

    private var engine = AVAudioEngine()
    private var handler: BufferHandler?
    private var configObserver: NSObjectProtocol?
    private let voiceProcessing: Bool
    /// UID do dispositivo escolhido nas Preferências; `nil` usa a entrada padrão do sistema.
    private let deviceUID: String?

    /// Formato entregue ao handler; pode mudar depois de uma troca de dispositivo.
    private(set) var format: AVAudioFormat?

    init(voiceProcessing: Bool, deviceUID: String?) {
        self.voiceProcessing = voiceProcessing
        self.deviceUID = deviceUID
    }

    deinit { stop() }

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func start(handler: @escaping BufferHandler) throws {
        self.handler = handler
        try startEngine()
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.restartAfterConfigurationChange()
        }
    }

    func stop() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        handler = nil
    }

    private func startEngine() throws {
        let input = engine.inputNode
        if let deviceUID, let device = AudioObjects.device(withUID: deviceUID), let unit = input.audioUnit {
            var deviceID = device
            let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                              &deviceID, UInt32(MemoryLayout<AudioObjectID>.size))
            if status != noErr {
                Self.log.error("Não foi possível usar o microfone escolhido (OSStatus \(status)); usando o padrão")
            }
        }
        if voiceProcessing {
            // Cancelamento de eco do sistema, sem abafar o áudio dos outros apps.
            try input.setVoiceProcessingEnabled(true)
            input.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)
        }
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw CoreAudioError(operation: "Microfone sem formato válido", status: -1)
        }
        format = inputFormat
        input.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [weak self] buffer, time in
            self?.handler?(buffer, time)
        }
        engine.prepare()
        try engine.start()
        Self.log.info("Microfone iniciado: \(inputFormat.description, privacy: .public)")
    }

    private func restartAfterConfigurationChange() {
        guard let handler else { return }
        Self.log.info("Dispositivo de entrada mudou; reiniciando o microfone")
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine = AVAudioEngine()
        do {
            try start(handler: handler)
        } catch {
            Self.log.error("Falha ao reiniciar o microfone: \(error.localizedDescription, privacy: .public)")
        }
    }
}
