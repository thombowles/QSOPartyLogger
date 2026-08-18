import Foundation
import os

/// Every contest the app knows: the bundled parties, lowered, plus bundled v2
/// files under `Resources/Contests/`, with user files overriding by id from
/// `~/Library/Application Support/QSOPartyLogger/{Parties,Contests}`.
enum ContestCatalog {
    private static let log = Logger(subsystem: "org.b5n.QSOPartyLogger", category: "catalog")
    private static let bundledCache = OSAllocatedUnfairLock<[URL: [ContestDefinition]]>(initialState: [:])

    static var userContestsDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QSOPartyLogger/Contests", isDirectory: true)
    }

    /// Bundled parties (lowered) and bundled v2 contests, by name — decoded
    /// once per bundle (its files never change while the app runs). A bundled
    /// file that fails is logged, once, and skipped: it used to vanish from
    /// the catalogue without a word.
    static func loadBundled(bundle: Bundle = .main) -> [ContestDefinition] {
        if let cached = bundledCache.withLock({ $0[bundle.bundleURL] }) { return cached }
        var byID: [String: ContestDefinition] = [:]
        for party in PartyCatalog.loadBundled(bundle: bundle) {
            do { let lowered = try PartyLowering.lower(party); byID[lowered.id] = lowered }
            catch { log.error("bundled party \(party.id, privacy: .public) does not lower: \(error.localizedDescription, privacy: .public)") }
        }
        for url in bundle.urls(forResourcesWithExtension: "json", subdirectory: "Contests") ?? [] {
            do { let contest = try ContestDefinition.decode(try Data(contentsOf: url), bundle: bundle); byID[contest.id] = contest }
            catch { log.error("bundled contest \(url.lastPathComponent, privacy: .public) failed to load: \(error.localizedDescription, privacy: .public)") }
        }
        let contests = byID.values.sorted { $0.name < $1.name }
        bundledCache.withLock { $0[bundle.bundleURL] = contests }
        return contests
    }

    /// User v2 files in a folder; failures are returned so the UI can explain them.
    static func loadUserContests(in dir: URL = userContestsDirectory) -> [(url: URL, result: Result<ContestDefinition, Error>)] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                do { return (url, .success(try ContestDefinition.decode(try Data(contentsOf: url)))) }
                catch {
                    // Logged as well as returned, like the bundled and user
                    // party loaders: a file that stops loading must never
                    // vanish from the catalogue without a word.
                    log.error("user contest \(url.lastPathComponent, privacy: .public) failed to load: \(error.localizedDescription, privacy: .public)")
                    return (url, .failure(error))
                }
            }
    }

    /// Everything, user party files (lowered) and user v2 files overriding
    /// bundled contests of the same id — v2 last, so it wins.
    static func all(bundle: Bundle = .main, userContestsDirectory: URL = userContestsDirectory) -> [ContestDefinition] {
        var byID = Dictionary(uniqueKeysWithValues: loadBundled(bundle: bundle).map { ($0.id, $0) })
        for (_, result) in PartyCatalog.loadUserParties() {
            if case .success(let party) = result, let lowered = try? PartyLowering.lower(party) { byID[lowered.id] = lowered }
        }
        for (_, result) in loadUserContests(in: userContestsDirectory) {
            if case .success(let contest) = result { byID[contest.id] = contest }
        }
        return byID.values.sorted { $0.name < $1.name }
    }

    static func contest(id: String, bundle: Bundle = .main) -> ContestDefinition? {
        all(bundle: bundle).first { $0.id == id }
    }
}
