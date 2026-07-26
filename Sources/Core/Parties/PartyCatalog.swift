import Foundation

/// Loads party definitions from the app bundle and the user's party folder.
enum PartyCatalog {
    /// `~/Library/Application Support/QSOPartyLogger/Parties` (container-relative when sandboxed).
    static var userPartiesDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QSOPartyLogger/Parties", isDirectory: true)
    }

    static func decode(_ data: Data) throws -> PartyDefinition {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let party = try decoder.decode(PartyDefinition.self, from: data)
        try party.validate()
        return party
    }

    static func loadBundled(bundle: Bundle = .main) -> [PartyDefinition] {
        guard let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: "Parties") else {
            return []
        }
        return urls
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decode(data)
            }
            .sorted { $0.name < $1.name }
    }

    /// User-supplied parties; failures are returned so the UI can explain bad files.
    static func loadUserParties() -> [(url: URL, result: Result<PartyDefinition, Error>)] {
        let dir = userPartiesDirectory
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [] }
        return urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                do {
                    let party = try decode(try Data(contentsOf: url))
                    return (url, .success(party))
                } catch {
                    return (url, .failure(error))
                }
            }
    }

    /// All loadable parties, user files overriding bundled ones with the same id.
    static func allParties(bundle: Bundle = .main) -> [PartyDefinition] {
        var byID: [String: PartyDefinition] = [:]
        for p in loadBundled(bundle: bundle) { byID[p.id] = p }
        for (_, result) in loadUserParties() {
            if case .success(let p) = result { byID[p.id] = p }
        }
        return byID.values.sorted { $0.name < $1.name }
    }

    /// The party to open by default at `date` for an operator in `state`.
    ///
    /// Where several sponsors share a weekend and accept one combined log, an
    /// operator **outside all of them** is better served by the combined entry —
    /// that is what it is for. An operator inside any member gets that member
    /// back instead, because the combined entry would give them the wrong
    /// exchange and multipliers.
    ///
    /// Returns `nil` when no party is running, so the caller keeps whatever the
    /// operator last chose.
    static func suggestedParty(
        on date: Date,
        operatorState: String,
        bundle: Bundle = .main
    ) -> PartyDefinition? {
        let state = operatorState.uppercased()
        let running = allParties(bundle: bundle).filter { party in
            party.schedule?.contains { $0.start <= date && date < $0.end } == true
        }
        guard !running.isEmpty else { return nil }

        // Prefer a combined entry, but only for an operator outside every one
        // of the parties it combines.
        if let combined = running.first(where: { party in
            !party.combines.isEmpty && !party.homeStates.contains(state)
        }) {
            return combined
        }

        // Otherwise the operator's own party. A combined entry also lists their
        // state among its members', and sorts before them by name, so it has to
        // be excluded here or an Indiana operator gets the combined entry back.
        let single = running.filter { $0.combines.isEmpty }
        return single.first { $0.homeStates.contains(state) }
            ?? single.first
            ?? running.first
    }

    /// One row of the party picker: a party, and whether it is shown nested
    /// under the combined entry above it.
    struct PickerEntry: Identifiable, Equatable, Sendable {
        let party: PartyDefinition
        /// True for a party that some other party `combines`.
        let isMember: Bool
        var id: String { party.id }
    }

    /// The parties in picker order, with each combined entry followed by the
    /// parties it combines.
    ///
    /// The members are **kept, not hidden**. An operator inside one of them
    /// needs that party's own exchange and multipliers — an Indiana station is
    /// in-state for Indiana and out-of-state for the other three — which is why
    /// N1MM keeps all four alongside its combined `IN7QPNE` module and why this
    /// does too. Grouping them stops four parties on one weekend reading as four
    /// unrelated choices.
    static func pickerEntries(bundle: Bundle = .main) -> [PickerEntry] {
        let all = allParties(bundle: bundle)
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

        // A party is a member if some other party combines it. Membership is
        // declared by the combiner, so no party needs to know it has a parent.
        var memberOf: [String: String] = [:]
        for party in all {
            for member in party.combines where byID[member] != nil {
                memberOf[member] = party.id
            }
        }

        var entries: [PickerEntry] = []
        for party in all where memberOf[party.id] == nil {
            entries.append(PickerEntry(party: party, isMember: false))
            for member in party.combines {
                guard let m = byID[member] else { continue }
                entries.append(PickerEntry(party: m, isMember: true))
            }
        }
        return entries
    }

    static func party(id: String, bundle: Bundle = .main) -> PartyDefinition? {
        allParties(bundle: bundle).first { $0.id == id }
    }
}
