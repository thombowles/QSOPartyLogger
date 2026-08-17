import Foundation

/// The operator's F-key messages, remembered per party between logs.
///
/// Messages live in the log file (`ContestLog.messages`), so each contest
/// window carries its own — but a *new* log for a party the operator had
/// already customised started from the party defaults, and the work was
/// redone every year (2026-08-16: "make sure CW memories are remembered per
/// contest"). Voice recordings solved this per party on disk (`VoiceLibrary`);
/// CW text and the phone mapping are small, so they go where every other
/// per-machine memory goes — one JSON dictionary in `Preferences.store`, party
/// id → `MessageSets`.
///
/// Written by `LogDocument.updateMessages` (the editor's Save, and its undo);
/// read by `LogDocument.updateStation` when a log takes on a party whose set
/// it has not customised itself. Injected into the document by the window,
/// nil in tests — see `LogDocument.messageMemory`.
struct MessageMemory {
    static let key = "messagesByParty"

    private let defaults: UserDefaults

    /// `defaults` is injected so a test can exercise the memory against a
    /// scratch suite. It defaults to `Preferences.store`, which is `.standard`
    /// in the app.
    init(defaults: UserDefaults = Preferences.store) {
        self.defaults = defaults
    }

    /// The set saved last for `partyID`, or nil when none was.
    func messages(for partyID: String) -> MessageSets? {
        table[partyID]
    }

    func remember(_ sets: MessageSets, for partyID: String) {
        var table = table
        table[partyID] = sets
        write(table)
    }

    func forget(_ partyID: String) {
        var table = table
        table.removeValue(forKey: partyID)
        write(table)
    }

    /// Unreadable data reads as nothing remembered rather than an error: a
    /// hand-edited or downgraded preference file must never take the memory
    /// down with it, and the next save writes over it.
    private var table: [String: MessageSets] {
        defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([String: MessageSets].self, from: $0) }
            ?? [:]
    }

    private func write(_ table: [String: MessageSets]) {
        if let data = try? JSONEncoder().encode(table) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
