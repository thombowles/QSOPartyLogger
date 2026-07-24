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
        let party = try JSONDecoder().decode(PartyDefinition.self, from: data)
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

    static func party(id: String, bundle: Bundle = .main) -> PartyDefinition? {
        allParties(bundle: bundle).first { $0.id == id }
    }
}
