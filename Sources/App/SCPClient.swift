import Foundation
import Observation

/// How the client reaches supercheckpartial.com — a seam, so tests script
/// the server's answers and never touch the network (constitution
/// Article 5).
protocol SCPFetching: Sendable {
    /// The `Last-Modified` a HEAD reports, without downloading the body.
    func head(_ url: URL) async throws -> String?
    func get(_ url: URL) async throws -> (Data, String?)
}

/// Keeps the super check partial database current by watching MASTER.SCP
/// at supercheckpartial.com.
///
/// Quiet by construction, like `DXCCLabelClient` and `CallHistoryClient`:
/// a volunteer-run site, a convenience feature, and a failure must never
/// reach the entry path. Errors land in `lastError` and the console;
/// whatever file is already cached stays in service.
///
/// ## The intelligent time
///
/// Called at launch and at every contest load, throttled to one check a
/// day — so opening six logs in an afternoon makes at most one HEAD, and
/// the ~360 KB body moves only when the release actually changed
/// (upstream re-releases every few weeks). The cached copy is published
/// before any network is considered, and nothing in the entry path ever
/// triggers a request. First launch has no file at all, so it skips the
/// HEAD and downloads directly — which is what makes the feature
/// zero-setup.
@MainActor
@Observable
final class SCPClient {

    enum Status: Equatable {
        case idle
        case checking
        case downloading
        /// A parsed database is published.
        case ready(records: Int, release: String)
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var lastError: String?
    /// Recent activity, newest last (capped) — the same diagnostic surface
    /// the other clients give.
    private(set) var console: [String] = []

    /// A freshly available database: the cached file at activation, or a
    /// just-installed download.
    var onDatabase: ((SCPDatabase) -> Void)?

    private let store: SCPStore
    private let fetcher: SCPFetching

    /// Upstream re-releases every few weeks, so a daily check is already
    /// generous — and is what keeps this off a volunteer's server.
    static let checkInterval: TimeInterval = 24 * 60 * 60

    static let scpURL = URL(string: "https://www.supercheckpartial.com/MASTER.SCP")!

    private static let maxConsoleLines = 200

    init(store: SCPStore = SCPStore(folder: SCPStore.defaultFolder),
         fetcher: SCPFetching = LiveSCPFetcher()) {
        self.store = store
        self.fetcher = fetcher
    }

    /// What the setup sheet shows: the cached release and its dates,
    /// independent of network state.
    func cachedMeta() -> SCPStore.Meta? {
        store.loadMeta()
    }

    /// The cached database, published immediately — what activation calls
    /// before any network is considered.
    func publishCached() {
        guard let cached = store.loadCached() else { return }
        publish(cached.database)
    }

    /// Consult upstream when it has not been consulted lately. `force` is
    /// the operator's Refresh button; the automatic path holds to the
    /// once-a-day throttle.
    func refreshIfStale(now: Date = Date(), force: Bool = false) async {
        if !force, let meta = store.loadMeta(),
           now.timeIntervalSince(meta.lastCheckedAt) < Self.checkInterval {
            return
        }
        await refresh(now: now)
    }

    func refresh(now: Date = Date()) async {
        status = .checking
        lastError = nil

        do {
            let cached = store.loadCached()
            // Freshness is judged only when there is a file to protect and
            // a token to compare; otherwise the download is the point.
            if let cached, let held = cached.meta?.sourceLastModified,
               !held.isEmpty {
                log("*** checking MASTER.SCP (held: \(held))")
                guard let upstream = try await fetcher.head(Self.scpURL) else {
                    // No Last-Modified means freshness cannot be judged at
                    // all; downloading blind would be worse than doing
                    // nothing.
                    throw Failure.noReleaseHeader
                }
                guard isNewer(upstream, than: held) else {
                    log("current: \(upstream)")
                    try? store.touchLastChecked(at: now)
                    publish(cached.database)
                    return
                }
                log("newer upstream: \(upstream) — downloading")
            } else {
                log("*** no cached MASTER.SCP — downloading")
            }

            status = .downloading
            let (data, release) = try await fetcher.get(Self.scpURL)
            guard !looksLikeHTML(data) else { throw Failure.refused }
            guard let database = SCPDatabase.parse(data: data),
                  database.recordCount >= SCPDatabase.minimumRecords else {
                throw Failure.unusable
            }
            try store.save(
                data: data,
                meta: SCPStore.Meta(
                    sourceLastModified: release ?? "",
                    fetchedAt: now,
                    lastCheckedAt: now
                )
            )
            log("*** installed release \(database.release ?? release ?? "?") — "
                + "\(database.recordCount) calls")
            publish(database)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            lastError = message
            log("*** \(message)")
            status = .failed(message)
        }
    }

    enum Failure: LocalizedError {
        case noReleaseHeader
        case refused
        case unusable

        var errorDescription: String? {
            switch self {
            case .noReleaseHeader:
                "supercheckpartial.com sent no Last-Modified, so freshness "
                + "cannot be judged. The cached file, if any, stays in use."
            case .refused:
                "The server answered with a page instead of the file — not "
                + "installing it. The cached file, if any, stays in use."
            case .unusable:
                "MASTER.SCP came back unreadable or truncated — not "
                + "installing it. The cached file, if any, stays in use."
            }
        }
    }

    private func publish(_ database: SCPDatabase) {
        status = .ready(
            records: database.recordCount,
            release: database.release
                ?? store.loadMeta()?.sourceLastModified
                ?? "cached file"
        )
        onDatabase?(database)
    }

    /// Both dates are HTTP-date strings; anything unparseable upstream is
    /// treated as not-newer, because acting on a date we cannot read is
    /// the worse error. (`DXCCLabelClient.httpDate` is the shared, tested
    /// parser.)
    private func isNewer(_ upstream: String, than held: String) -> Bool {
        guard let a = DXCCLabelClient.httpDate(upstream) else { return false }
        guard let b = DXCCLabelClient.httpDate(held) else { return true }
        return a > b
    }

    private func looksLikeHTML(_ data: Data) -> Bool {
        guard let head = String(data: data.prefix(256), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else { return false }
        return head.hasPrefix("<!doctype") || head.hasPrefix("<html")
    }

    private func log(_ line: String) {
        console.append(line)
        if console.count > Self.maxConsoleLines {
            console.removeFirst(console.count - Self.maxConsoleLines)
        }
    }
}

/// The real transport. Never used by tests.
struct LiveSCPFetcher: SCPFetching {
    private static let userAgent = "QSOPartyLogger/1.0 (+https://github.com/KE5CW) macOS"

    func head(_ url: URL) async throws -> String? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 20
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Last-Modified")
    }

    func get(_ url: URL) async throws -> (Data, String?) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Last-Modified"))
    }
}
