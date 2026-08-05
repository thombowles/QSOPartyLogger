import Foundation
import Observation

/// How the client reaches country-files.com — a seam, so tests script the
/// server's answers and never touch the network (constitution Article 5).
protocol DXCCFetching: Sendable {
    /// The `Last-Modified` a HEAD reports, without downloading the body.
    func head(_ url: URL) async throws -> String?
    func get(_ url: URL) async throws -> (Data, String?)
}

/// Keeps DX multiplier **labels** current by watching AD1C's `cty.dat`.
///
/// Quiet by construction, like `CallHistoryClient` and `HubSpotClient`: this is
/// a volunteer-run site, the app is useless to nobody without it, and a failure
/// must never reach the entry path. Errors land in `lastError` and the console;
/// whatever labels are already in service stay.
///
/// ## What it is allowed to change
///
/// The prefix an entity is *displayed* as, and nothing else. It cannot add a
/// DXCC entity, cannot change a prefix the engine resolves against, and cannot
/// move a score — those come from the bundled ARRL table and need a generator
/// run and a release. `DXCCLabelRefresh` enforces that boundary, and refuses a
/// file it cannot fully account for.
///
/// ## Why the check is cheap
///
/// It is a HEAD request comparing one date, throttled to once a day, and the
/// ~350 KB body is only fetched when that date has actually moved. Nearly every
/// AD1C release only adds `=CALL` DXpedition entries this ignores, so in normal
/// service this makes one small request a day and does nothing with the answer.
@MainActor
@Observable
final class DXCCLabelClient {

    enum Status: Equatable {
        case idle
        case checking
        /// The bundled labels are current as of this release date.
        case current(release: String)
        /// New labels are stored and take effect at the next launch.
        case updated(count: Int, release: String)
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var lastError: String?
    private(set) var console: [String] = []

    private let fetcher: DXCCFetching
    private let table: DXCCTable
    private let overlayURL: URL?

    /// AD1C republishes every few days to weeks, and the field consumed here
    /// moves a few times a decade — so a daily check is already generous, and
    /// is what keeps this off a volunteer's server.
    static let checkInterval: TimeInterval = 24 * 60 * 60

    static let ctyURL = URL(string: "https://www.country-files.com/bigcty/cty.dat")!

    init(
        fetcher: DXCCFetching = LiveDXCCFetcher(),
        table: DXCCTable = .shared,
        overlayURL: URL? = DXCCLabelStore.overlayURL
    ) {
        self.fetcher = fetcher
        self.table = table
        self.overlayURL = overlayURL
    }

    private func log(_ line: String) {
        console.append(line)
        if console.count > 200 { console.removeFirst(console.count - 200) }
    }

    /// The release date the running table's labels came from: whatever a
    /// previous download recorded, else the bundled table's own.
    private var heldRelease: String {
        DXCCLabelStore.load(at: overlayURL)?.release ?? table.fetched
    }

    /// Check unless one has run inside `checkInterval`.
    ///
    /// Called at launch and at every contest load, so the throttle is what
    /// makes those triggers free — opening six logs in an afternoon still
    /// makes at most one request.
    func refreshIfStale(now: Date = Date(), force: Bool = false) async {
        if !force, let last = DXCCLabelStore.load(at: overlayURL)?.checkedAt,
           now.timeIntervalSince(last) < Self.checkInterval {
            return
        }
        await refresh(now: now)
    }

    func refresh(now: Date = Date()) async {
        guard !table.entities.isEmpty else { return }
        status = .checking
        lastError = nil
        let held = heldRelease
        log("*** checking cty.dat (held: \(held))")

        do {
            guard let upstream = try await fetcher.head(Self.ctyURL) else {
                // No Last-Modified means freshness cannot be judged at all;
                // downloading blind would be worse than doing nothing.
                throw Failure.noReleaseHeader
            }
            guard isNewer(upstream, than: held) else {
                log("current: \(upstream)")
                status = .current(release: upstream)
                record(release: held, labels: nil, at: now)
                return
            }

            log("newer upstream: \(upstream) — downloading")
            let (data, downloadRelease) = try await fetcher.get(Self.ctyURL)
            let release = downloadRelease ?? upstream
            guard let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) else {
                throw Failure.undecodable
            }
            let labels = try DXCCLabelRefresh.labels(
                fromCTY: text, entities: table.entities, byteCount: data.count
            )
            record(release: release, labels: labels, at: now)
            for (code, label) in labels.sorted(by: { $0.key < $1.key }) {
                let name = table.entities.first { $0.code == code }?.name ?? code
                log("  \(name): \(table.entities.first { $0.code == code }?.primaryPrefix ?? "?") -> \(label)")
            }
            log("\(labels.count) label(s) updated, in service at the next launch")
            status = .updated(count: labels.count, release: release)
        } catch DXCCLabelRefresh.Rejection.noLabelsChanged {
            // The commonest outcome by far: a new file that moved nothing we
            // read. Record the check so the throttle counts it as a success.
            log("new file, no label changed")
            status = .current(release: held)
            record(release: held, labels: nil, at: now)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            lastError = message
            log("failed: \(message)")
            status = .failed(message)
        }
    }

    enum Failure: LocalizedError {
        case noReleaseHeader
        case undecodable

        var errorDescription: String? {
            switch self {
            case .noReleaseHeader:
                "the server sent no Last-Modified, so freshness cannot be judged"
            case .undecodable:
                "cty.dat was not readable as text"
            }
        }
    }

    /// Both dates are HTTP-date strings; anything unparseable is treated as
    /// not-newer, because acting on a date we cannot read is the worse error.
    private func isNewer(_ upstream: String, than held: String) -> Bool {
        guard let a = Self.httpDate(upstream) else { return false }
        guard let b = Self.httpDate(held) else { return true }
        return a > b
    }

    static func httpDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "yyyy-MM-dd"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    /// Stamp the check. Passing nil labels keeps whatever is already stored,
    /// so a "nothing moved" check never discards an earlier update.
    private func record(release: String, labels: [String: String]?, at now: Date) {
        let existing = DXCCLabelStore.load(at: overlayURL)
        DXCCLabelStore.save(
            .init(release: labels == nil ? (existing?.release ?? release) : release,
                  checkedAt: now,
                  labels: labels ?? existing?.labels ?? [:]),
            to: overlayURL
        )
    }
}

/// The real transport. Never used by tests.
struct LiveDXCCFetcher: DXCCFetching {
    func head(_ url: URL) async throws -> String? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 20
        request.setValue("QSOPartyLogger/1.0", forHTTPHeaderField: "User-Agent")
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Last-Modified")
    }

    func get(_ url: URL) async throws -> (Data, String?) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("QSOPartyLogger/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Last-Modified"))
    }
}
