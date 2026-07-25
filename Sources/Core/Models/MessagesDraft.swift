import Foundation

/// What the messages editor holds while it is open: the eight Run and eight
/// Search & Pounce macros as edited, before Save writes them back to the log.
///
/// A value rather than `@State` on the view, because Restore Defaults, the
/// exchange-mismatch banner and the padding rules decide what the operator
/// sends on the air, and inside a SwiftUI `View` none of them could be tested.
/// That is the same gap that let two keying bugs ship on 2026-07-25; see
/// `docs/superpowers/specs/2026-07-25-keying-path-seam-design.md`.
struct MessagesDraft: Equatable {
    /// F1–F8. Both sets are always this long, padded with empties, so the
    /// editor's eight rows always have somewhere to write.
    static let slotCount = 8

    private(set) var run: [String]
    private(set) var searchPounce: [String]

    init(_ sets: MessageSets = .standard) {
        run = Self.padded(sets.run)
        searchPounce = Self.padded(sets.searchPounce)
    }

    /// What is currently in the fields, not what is saved — so the warning
    /// banner clears the moment the operator types a fix.
    var edited: MessageSets {
        MessageSets(run: normalized(run), searchPounce: normalized(searchPounce))
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

    /// Replace all 16 messages with the party's defaults. Whole-set on purpose:
    /// a half-restored set is a set that disagrees with itself.
    mutating func restoreDefaults(for party: PartyDefinition?) {
        let defaults = MessageSets.defaults(for: party)
        run = Self.padded(defaults.run)
        searchPounce = Self.padded(defaults.searchPounce)
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

    private func normalized(_ set: [String]) -> [String] {
        Self.padded(set).map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
