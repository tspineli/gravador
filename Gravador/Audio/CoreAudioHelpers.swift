import AVFoundation
import CoreAudio
import Foundation

struct CoreAudioError: LocalizedError {
    let operation: String
    let status: OSStatus

    var errorDescription: String? { "\(operation) falhou (OSStatus \(status))" }
}

/// Acesso tipado às propriedades do HAL (AudioObjectGetPropertyData).
enum AudioObjects {
    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, initial: T) throws -> T {
        var addr = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        var result = initial
        let status = AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &result)
        guard status == noErr else { throw CoreAudioError(operation: "Leitura de \(fourCC(selector))", status: status) }
        return result
    }

    static func array<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, of _: T.Type) throws -> [T] {
        var addr = address(selector)
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size)
        guard status == noErr else { throw CoreAudioError(operation: "Tamanho de \(fourCC(selector))", status: status) }
        let count = Int(size) / MemoryLayout<T>.stride
        guard count > 0 else { return [] }
        let buffer = UnsafeMutablePointer<T>.allocate(capacity: count)
        defer { buffer.deallocate() }
        status = AudioObjectGetPropertyData(object, &addr, 0, nil, &size, buffer)
        guard status == noErr else { throw CoreAudioError(operation: "Leitura de \(fourCC(selector))", status: status) }
        return Array(UnsafeBufferPointer(start: buffer, count: Int(size) / MemoryLayout<T>.stride))
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: Unmanaged<CFString>?
        let status = AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value)
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    /// Objeto de processo do HAL para um PID (só existe se o processo já usou áudio).
    static func processObject(for pid: pid_t) -> AudioObjectID? {
        var addr = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr,
                                                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        guard status == noErr, object != kAudioObjectUnknown else { return nil }
        return object
    }

    static func fourCC(_ value: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((value >> $0) & 0xFF) }
        return String(bytes: bytes, encoding: .ascii) ?? String(value)
    }
}

extension AVAudioPCMBuffer {
    /// Cópia independente dos samples. Buffers vindos do HAL ou de taps do AVAudioEngine
    /// podem ser reaproveitados depois do callback, então nunca são guardados diretamente.
    func deepCopy() -> AVAudioPCMBuffer? {
        guard frameLength > 0, let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else { return nil }
        copy.frameLength = frameLength
        let src = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: audioBufferList))
        let dst = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (s, d) in zip(src, dst) {
            guard let sData = s.mData, let dData = d.mData else { continue }
            memcpy(dData, sData, Int(min(s.mDataByteSize, d.mDataByteSize)))
        }
        return copy
    }
}

/// Dispositivo de entrada de áudio (microfone).
struct InputDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
}

extension AudioObjects {
    static func inputDevices() -> [InputDevice] {
        let devices = (try? array(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices, of: AudioObjectID.self)) ?? []
        return devices.compactMap { device in
            var addr = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size > 0,
                  let uid = string(device, kAudioDevicePropertyDeviceUID),
                  let name = string(device, kAudioObjectPropertyName),
                  !uid.contains("CADefaultDeviceAggregate") else { return nil }
            return InputDevice(id: device, uid: uid, name: name)
        }
    }

    static func device(withUID uid: String) -> AudioObjectID? {
        inputDevices().first { $0.uid == uid }?.id
    }
}
