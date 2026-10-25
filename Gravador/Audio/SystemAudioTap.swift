import AVFoundation
import CoreAudio
import OSLog

/// Captura todo o áudio de saída do sistema (o que os participantes falam) com Core Audio process taps.
/// Padrão baseado no insidegui/AudioCap (BSD-2): tap global → aggregate device privado → IO proc.
final class SystemAudioTap {
    typealias BufferHandler = (AVAudioPCMBuffer, AVAudioTime?) -> Void

    private static let log = Logger(subsystem: "com.tiagospineli.gravador", category: "system-tap")

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private let ioQueue = DispatchQueue(label: "gravador.system-tap.io", qos: .userInitiated)
    private(set) var format: AVAudioFormat?

    deinit { stop() }

    func start(handler: @escaping BufferHandler) throws {
        guard ioProcID == nil else { return }

        // Exclui o próprio app (se ele já tiver objeto de processo no HAL).
        let excluded = AudioObjects.processObject(for: getpid()).map { [$0] } ?? []
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
        description.uuid = UUID()
        description.name = "Gravador de Reuniões"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var newTap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &newTap)
        guard status == noErr else { throw CoreAudioError(operation: "AudioHardwareCreateProcessTap", status: status) }
        tapID = newTap

        do {
            var streamDescription = try AudioObjects.value(tapID, kAudioTapPropertyFormat,
                                                           initial: AudioStreamBasicDescription())
            guard let tapFormat = AVAudioFormat(streamDescription: &streamDescription) else {
                throw CoreAudioError(operation: "Formato do tap", status: -1)
            }
            format = tapFormat

            let outputDevice = try AudioObjects.value(AudioObjectID(kAudioObjectSystemObject),
                                                      kAudioHardwarePropertyDefaultSystemOutputDevice,
                                                      initial: AudioObjectID(kAudioObjectUnknown))
            guard let outputUID = AudioObjects.string(outputDevice, kAudioDevicePropertyDeviceUID) else {
                throw CoreAudioError(operation: "UID da saída padrão", status: -1)
            }

            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Gravador Tap",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                ]],
            ]
            var newAggregate = AudioObjectID(kAudioObjectUnknown)
            status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &newAggregate)
            guard status == noErr else { throw CoreAudioError(operation: "AudioHardwareCreateAggregateDevice", status: status) }
            aggregateID = newAggregate

            var procID: AudioDeviceIOProcID?
            status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, ioQueue) { _, inputData, inputTime, _, _ in
                // O buffer do HAL só vale durante o callback: copia antes de entregar.
                guard let view = AVAudioPCMBuffer(pcmFormat: tapFormat, bufferListNoCopy: inputData, deallocator: nil),
                      let copy = view.deepCopy() else { return }
                let time = AVAudioTime(hostTime: inputTime.pointee.mHostTime)
                handler(copy, time)
            }
            guard status == noErr, let procID else { throw CoreAudioError(operation: "AudioDeviceCreateIOProcIDWithBlock", status: status) }
            ioProcID = procID

            status = AudioDeviceStart(aggregateID, procID)
            guard status == noErr else { throw CoreAudioError(operation: "AudioDeviceStart", status: status) }
            Self.log.info("Tap do sistema iniciado: \(tapFormat.description, privacy: .public)")
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        ioProcID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }
}
