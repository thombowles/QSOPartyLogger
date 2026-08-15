import Foundation
import CoreAudio

/// One CoreAudio device as the pickers need it: the UID (stable across
/// launches and replugs) and the name. UIDs are what the settings store;
/// names are display.
struct AudioDevice: Identifiable, Equatable, Hashable, Sendable {
    let uid: String
    let name: String
    var id: String { uid }
}

/// CoreAudio's device list. Read on demand — the editor refreshes it when it
/// appears — and never cached, because USB audio comes and goes.
enum AudioDevices {
    static func inputDevices() -> [AudioDevice] { devices(input: true) }
    static func outputDevices() -> [AudioDevice] { devices(input: false) }

    /// The device with this UID, if it is present right now.
    static func device(uid: String) -> AudioDevice? {
        (outputDevices() + inputDevices()).first { $0.uid == uid }
    }

    static func deviceID(uid: String) -> AudioDeviceID? {
        allDeviceIDs().first { self.uid(of: $0) == uid }
    }

    // MARK: CoreAudio plumbing

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func devices(input: Bool) -> [AudioDevice] {
        allDeviceIDs().compactMap { id in
            guard channelCount(id, input: input) > 0,
                  let uid = uid(of: id), let name = name(of: id) else { return nil }
            return AudioDevice(uid: uid, name: name)
        }
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func uid(of id: AudioDeviceID) -> String? { string(id, kAudioDevicePropertyDeviceUID) }
    private static func name(of id: AudioDeviceID) -> String? { string(id, kAudioObjectPropertyName) }

    private static func channelCount(_ id: AudioDeviceID, input: Bool) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
