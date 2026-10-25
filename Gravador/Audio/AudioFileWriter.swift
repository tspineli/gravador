import AVFoundation
import OSLog

/// Grava uma trilha em AAC dentro de CAF durante a reunião (um crash perde no máximo os últimos
/// pacotes) e converte para .m4a sem recodificar ao final.
final class AudioFileWriter {
    private static let log = Logger(subsystem: "com.tiagospineli.gravador", category: "audio-file")

    let cafURL: URL
    private var file: AVAudioFile?
    private var fileFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private let maxChannels: AVAudioChannelCount

    init(url: URL, maxChannels: AVAudioChannelCount) {
        cafURL = url.deletingPathExtension().appendingPathExtension("caf")
        self.maxChannels = maxChannels
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        do {
            if file == nil {
                let channels = min(buffer.format.channelCount, maxChannels)
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: buffer.format.sampleRate,
                    AVNumberOfChannelsKey: channels,
                    AVEncoderBitRateKey: channels > 1 ? 96_000 : 64_000,
                ]
                let newFile = try AVAudioFile(forWriting: cafURL, settings: settings,
                                              commonFormat: .pcmFormatFloat32, interleaved: false)
                file = newFile
                fileFormat = newFile.processingFormat
            }
            guard let file, let fileFormat else { return }
            if buffer.format == fileFormat {
                try file.write(from: buffer)
            } else if let converted = convert(buffer, to: fileFormat) {
                try file.write(from: converted)
            }
        } catch {
            Self.log.error("Falha ao gravar áudio: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Fecha o arquivo e gera o .m4a ao lado. Devolve a URL final (m4a, ou o caf se a conversão falhar).
    func finish() async -> URL? {
        file = nil // AVAudioFile fecha ao ser liberado.
        guard FileManager.default.fileExists(atPath: cafURL.path) else { return nil }
        let m4aURL = cafURL.deletingPathExtension().appendingPathExtension("m4a")
        let asset = AVURLAsset(url: cafURL)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else { return cafURL }
        do {
            try await export.export(to: m4aURL, as: .m4a)
            try? FileManager.default.removeItem(at: cafURL)
            return m4aURL
        } catch {
            Self.log.error("Conversão para m4a falhou, mantendo .caf: \(error.localizedDescription, privacy: .public)")
            return cafURL
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
            converter?.downmix = true
        }
        guard let converter else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        return status == .error ? nil : output
    }
}
