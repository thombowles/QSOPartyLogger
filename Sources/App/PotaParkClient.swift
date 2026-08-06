import Foundation
import Observation

/// How the client reaches api.pota.app — a seam, so tests script the
/// server's answers and never touch the network.
protocol PotaParkFetching: Sendable {
    func get(_ url: URL) async throws -> Data
}

struct LivePotaParkFetcher: PotaParkFetching {
    func get(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

/// Keeps the POTA park directory current from POTA's own API.
///
/// `SCPClient`'s posture — quiet by construction, the cached copy published
/// before any network is considered, failures inline and never modal — with
/// one difference the API forces: api.pota.app answers HEAD with 403 (API
/// Gateway routes GET only; see docs/research/pota/SOURCES.md), so there is
/// no cheap freshness probe to make. The client re-downloads once a week or
/// on the operator's Refresh, and the ~2.7 MB body is why that interval is a
/// week and why the *first* download is an explicit button rather than a
/// launch or sheet-open side effect: every party's Contest Setup shows the
/// POTA section, and an operator who never leaves the shack must not pay for
/// it.
@MainActor
@Observable
final class PotaParkClient {

    enum Status: Equatable {
        case idle
        case downloading
        case ready(parks: Int)
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var directory: PotaParkDirectory?

    private let store: PotaParkStore
    private let fetcher: PotaParkFetching

    /// Parks churn slowly — a week-old list still locates you.
    static let checkInterval: TimeInterval = 7 * 24 * 60 * 60

    static let parksURL = URL(string: "https://api.pota.app/program/parks/US")!

    init(store: PotaParkStore = PotaParkStore(folder: PotaParkStore.defaultFolder),
         fetcher: PotaParkFetching = LivePotaParkFetcher()) {
        self.store = store
        self.fetcher = fetcher
    }

    /// What the picker's status row shows, independent of network state.
    func cachedMeta() -> PotaParkStore.Meta? {
        store.loadMeta()
    }

    /// The cached directory, published immediately — what the picker calls
    /// on appear, before any network is considered.
    func publishCached() {
        guard directory == nil, let cached = store.loadCached() else { return }
        directory = cached.directory
        status = .ready(parks: cached.directory.parks.count)
    }

    /// Re-download when the cached copy has aged out. With no cache at all
    /// this does nothing — the first download is the explicit button.
    /// `force` is that button's Refresh sibling.
    func refreshIfStale(now: Date = Date(), force: Bool = false) async {
        guard let meta = store.loadMeta() else { return }
        if !force, now.timeIntervalSince(meta.lastCheckedAt) < Self.checkInterval {
            return
        }
        await download(now: now)
    }

    func download(now: Date = Date()) async {
        status = .downloading
        do {
            let data = try await fetcher.get(Self.parksURL)
            guard let parsed = PotaParkDirectory.parse(data: data) else {
                throw URLError(.cannotParseResponse)
            }
            try store.save(data: data, meta: .init(fetchedAt: now, lastCheckedAt: now))
            directory = parsed
            status = .ready(parks: parsed.parks.count)
        } catch {
            // Whatever is cached stays in service; the failure is a status
            // line, never an interruption.
            if let cached = store.loadCached() {
                directory = cached.directory
                let held = cached.meta?.fetchedAt
                    .formatted(date: .abbreviated, time: .omitted)
                status = .failed("Park list refresh failed — still using the copy from "
                                 + (held ?? "an earlier download") + ".")
            } else {
                status = .failed("Park list download failed — check the connection "
                                 + "and try again.")
            }
        }
    }
}
