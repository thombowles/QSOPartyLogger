import Foundation

/// What the messages editor holds while it is open, before Save writes it back
/// to the log: the eight Run and eight Search & Pounce CW macros as edited, and
/// on the phone side which voice memory each of those keys fires, plus a name
/// for each of the radio's memories.
///
/// A value rather than `@State` on the view, because Restore Defaults, the
/// exchange-mismatch banner and the padding rules decide what the operator
/// sends on the air, and inside a SwiftUI `View` none of them could be tested.
/// That is the same gap that let two keying bugs ship on 2026-07-25; see
/// `docs/superpowers/specs/2026-07-25-keying-path-seam-design.md`.
///
/// **Two cardinalities live here, and they are not the same thing** even though
/// both are currently 8: `slotCount` counts F-keys, `MessageSets.voiceMemorySlots`
/// counts the radio's recordings. `run`, `searchPounce`, `phoneRun` and
/// `phoneSearchPounce` are indexed by F-key; `voiceMemoryNames` is indexed by
/// memory. Pair each array with the wrong constant and it compiles, passes, and
/// mis-sizes the day the two diverge.
struct MessagesDraft: Equatable {
    /// F1–F8. Every F-key-indexed set is always this long, padded, so the
    /// editor's eight rows always have somewhere to write. Not the number of
    /// voice memories — see `MessageSets.voiceMemorySlots` for that.
    static let slotCount = 8

    private(set) var run: [String]
    private(set) var searchPounce: [String]
    private(set) var phoneRun: [Int?]
    private(set) var phoneSearchPounce: [Int?]
    private(set) var voiceMemoryNames: [String]

    init(_ sets: MessageSets = .standard) {
        run = Self.padded(sets.run)
        searchPounce = Self.padded(sets.searchPounce)
        phoneRun = Self.paddedMemories(sets.phoneRun)
        phoneSearchPounce = Self.paddedMemories(sets.phoneSearchPounce)
        voiceMemoryNames = Self.paddedNames(sets.voiceMemoryNames)
    }

    /// What is currently in the fields, not what is saved — so the warning
    /// banner clears the moment the operator types a fix.
    var edited: MessageSets {
        var sets = MessageSets(run: normalized(run), searchPounce: normalized(searchPounce))
        sets.phoneRun = phoneRun
        sets.phoneSearchPounce = phoneSearchPounce
        sets.voiceMemoryNames = voiceMemoryNames.map { $0.trimmingCharacters(in: .whitespaces) }
        return sets
    }

    subscript(mode: OperatingMode, index: Int) -> String {
        get {
            let set = mode == .run ? run : searchPounce
            return set.indices.contains(index) ? set[index] : ""
        }
        set {
            guard (0..<Self.slotCount).contains(index) else { return }
            if mode == .run {
                run[index] = newValue
            } else {
                searchPounce[index] = newValue
            }
        }
    }

    /// Which memory F<index+1> fires in `mode`, or nil when the key is
    /// unassigned. Labelled `voice:` to sit beside the CW subscript rather
    /// than overload it — the two return different things.
    subscript(voice mode: OperatingMode, index: Int) -> Int? {
        get {
            let set = mode == .run ? phoneRun : phoneSearchPounce
            return set.indices.contains(index) ? set[index] : nil
        }
        set {
            guard (0..<Self.slotCount).contains(index) else { return }
            if mode == .run {
                phoneRun[index] = newValue
            } else {
                phoneSearchPounce[index] = newValue
            }
        }
    }

    /// `memoryIndex` is 0-based: memory M1 is index 0.
    mutating func setVoiceMemoryName(_ name: String, at memoryIndex: Int) {
        guard (0..<MessageSets.voiceMemorySlots).contains(memoryIndex) else { return }
        voiceMemoryNames[memoryIndex] = name
    }

    /// "M4 AGN?" from the names being edited right now. Delegates so the
    /// composition lives in one place — and so the editor's pickers do not
    /// rebuild the whole `edited` value once per row per memory.
    ///
    /// The throwaway `.standard` is sound only while `voiceMemoryCaption` reads
    /// nothing but `voiceMemoryNames`. Teach it to consult the mappings too and
    /// this silently captions from the defaults instead of the live edits, so
    /// move this to `edited` if that day comes.
    func voiceMemoryCaption(_ memory: Int) -> String {
        var sets = MessageSets.standard
        sets.voiceMemoryNames = voiceMemoryNames
        return sets.voiceMemoryCaption(memory)
    }

    /// Replace all 16 messages with the party's defaults. Whole-set on purpose:
    /// a half-restored set is a set that disagrees with itself.
    mutating func restoreDefaults(for party: PartyDefinition?) {
        let defaults = MessageSets.defaults(for: party)
        run = Self.padded(defaults.run)
        searchPounce = Self.padded(defaults.searchPounce)
        phoneRun = Self.paddedMemories(MessageSets.defaultPhoneRun)
        phoneSearchPounce = Self.paddedMemories(MessageSets.defaultPhoneSearchPounce)
        voiceMemoryNames = Self.paddedNames(MessageSets.defaultVoiceMemoryNames)
    }

    /// How what is typed right now disagrees with the party's exchange, or nil
    /// when it agrees — the editor's warning banner. Nil for an unknown party:
    /// there is nothing to check against.
    func mismatch(with party: PartyDefinition?) -> MessageSets.ExchangeMismatch? {
        guard let party else { return nil }
        return edited.exchangeMismatch(with: party)
    }

    private static func padded(_ set: [String]) -> [String] {
        var out = Array(set.prefix(slotCount))
        while out.count < slotCount { out.append("") }
        return out
    }

    /// F-key-indexed, so `slotCount` — one entry per key, each holding the
    /// memory that key fires. Not `voiceMemorySlots`: this array is as long as
    /// there are keys, not as long as there are recordings.
    private static func paddedMemories(_ set: [Int?]) -> [Int?] {
        var out = Array(set.prefix(slotCount))
        while out.count < slotCount { out.append(nil) }
        return out
    }

    /// Memory-indexed, so `MessageSets.voiceMemorySlots` — one name per
    /// recording. Not `slotCount`: two keys may name the same memory, and a
    /// memory no key points at still has a name.
    private static func paddedNames(_ names: [String]) -> [String] {
        var out = Array(names.prefix(MessageSets.voiceMemorySlots))
        while out.count < MessageSets.voiceMemorySlots { out.append("") }
        return out
    }

    private func normalized(_ set: [String]) -> [String] {
        Self.padded(set).map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
