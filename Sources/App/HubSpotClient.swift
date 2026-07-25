import Foundation
import Observation

/// Polls the active party's page on qsopartyhub.com and hands the spots to the
/// same store the cluster feeds, so the band map, filters, stacking and
/// ⌘←/⌘→ all work on them without knowing where they came from.
///
/// Deliberately quiet. The hub is a small volunteer-run board, and a failure
/// there must never disturb the cluster feed or the entry path: errors land in
/// `lastError` and the console, the poll backs off, and cluster spots keep
/// arriving throughout.
@MainActor
@Observable
final class HubSpotClient {

    enum Status: Equatable {
        case stopped
        /// Running, and inside the party's operating window.
        case polling
        /// Running, but the party is not on for hours yet — the site is a
        /// volunteer's, so we leave it alone until it matters.
        case waitingForWindow
    }

    private(set) var status: Status = .stopped
    private(set) var lastError: String?
    /// Recent activity, newest last (capped) — the same diagnostic the cluster
    /// node window gives, for the same reason.
    private(set) var console: [String] = []
    private(set) var spotsReceived = 0
    /// Rows the parser could not read. A silently shrinking spot list looks
    /// exactly like a quiet band; this is how drift becomes visible.
    private(set) var rejectedRows: [String] = []

    var onSpots: (([Spot]) -> Void)?

    private static let maxConsoleLines = 200
    private static let userAgent = "QSOPartyLogger/1.0 (+https://github.com/KE5CW) macOS"

    private var task: Task<Void, Never>?
    private var consecutiveFailures = 0

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = ["User-Agent": HubSpotClient.userAgent]
        return URLSession(configuration: config)
    }()

    func start(source: HubSpotSource, party: PartyDefinition) {
        stop()
        guard let url = URL(string: source.tableURL) else {
            lastError = "Bad hub URL for \(party.name)."
            return
        }
        status = .polling
        lastError = nil
        console = []
        spotsReceived = 0
        rejectedRows = []
        log("*** polling \(url.host ?? source.tableURL) for \(party.name)")

        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay: TimeInterval

                if HubPollPolicy.shouldPoll(now: Date(), schedule: party.schedule) {
                    if self.status != .polling {
                        self.status = .polling
                        self.log("*** \(party.name) window is open — polling resumed")
                    }
                    delay = await self.pollOnce(url: url, party: party)
                } else {
                    if self.status != .waitingForWindow {
                        self.status = .waitingForWindow
                        self.log("*** outside the \(party.name) window — idle until it opens")
                    }
                    delay = HubPollPolicy.healthyInterval
                }

                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        status = .stopped
        consecutiveFailures = 0
    }

    /// One fetch-and-parse. Returns how long to wait before the next.
    private func pollOnce(url: URL, party: PartyDefinition) async -> TimeInterval {
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw URLError(.badServerResponse)
            }
            guard let html = String(data: data, encoding: .utf8) else {
                throw URLError(.cannotDecodeContentData)
            }

            let result = HubSpotParser.parse(html: html, party: party)

            if result.headerMismatch {
                // Columns are read by position, so a changed layout is not
                // something to guess at: it would put wrong counties on the
                // band map with total confidence.
                lastError = "The hub's spot table has changed shape — not reading it "
                    + "until the app is updated. Cluster spots are unaffected."
                log("*** header mismatch — parsing stopped")
                consecutiveFailures = 0
                return HubPollPolicy.healthyInterval
            }

            consecutiveFailures = 0
            lastError = nil
            rejectedRows = result.rejected
            for row in result.rejected {
                log("? could not read: \(row)")
            }
            if !result.spots.isEmpty {
                spotsReceived += result.spots.count
                onSpots?(result.spots)
            }
            return HubPollPolicy.healthyInterval
        } catch {
            consecutiveFailures += 1
            let wait = HubPollPolicy.interval(consecutiveFailures: consecutiveFailures)
            lastError = "Hub unreachable: \(error.localizedDescription) "
                + "Retrying in \(Int(wait))s. Cluster spots are unaffected."
            log("*** fetch failed (\(consecutiveFailures)): \(error.localizedDescription)")
            return wait
        }
    }

    private func log(_ line: String) {
        console.append(line)
        if console.count > Self.maxConsoleLines {
            console.removeFirst(console.count - Self.maxConsoleLines)
        }
    }
}
