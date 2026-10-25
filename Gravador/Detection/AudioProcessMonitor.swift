import CoreAudio
import Foundation
import OSLog

/// Processo que está capturando áudio de entrada (microfone) segundo o HAL.
struct MicrophoneClient: Hashable {
    let pid: pid_t
    let bundleID: String
}

/// Lista quem está usando o microfone agora, via `kAudioProcessPropertyIsRunningInput` (macOS 14.4+).
/// Não lê nenhum áudio dos outros apps: só os metadados que o próprio HAL expõe.
enum AudioProcessMonitor {
    private static let log = Logger(subsystem: "com.tiagospineli.gravador", category: "detection")

    static func microphoneClients() -> [MicrophoneClient] {
        let ownPID = getpid()
        let objects: [AudioObjectID]
        do {
            objects = try AudioObjects.array(AudioObjectID(kAudioObjectSystemObject),
                                             kAudioHardwarePropertyProcessObjectList, of: AudioObjectID.self)
        } catch {
            log.error("Lista de processos de áudio indisponível: \(error.localizedDescription, privacy: .public)")
            return []
        }

        return objects.compactMap { object in
            let running = (try? AudioObjects.value(object, kAudioProcessPropertyIsRunningInput, initial: UInt32(0))) ?? 0
            guard running != 0,
                  let pid = try? AudioObjects.value(object, kAudioProcessPropertyPID, initial: pid_t(0)),
                  pid != ownPID else { return nil }
            let bundleID = AudioObjects.string(object, kAudioProcessPropertyBundleID) ?? ""
            return MicrophoneClient(pid: pid, bundleID: bundleID)
        }
    }
}
