import Foundation
import Observation

protocol PotaBoardFetching: Sendable {
    func get(_ url: URL) async throws -> Data
}

struct URLSessionPotaBoardFetcher: PotaBoardFetching {
    private let session: URLSession
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = [
            "User-Agent": "QSOPartyLogger/1.5 (+https://github.com/KE5CW) macOS"
        ]
        session = URLSession(configuration: config)
    }
    func get(_ url: URL) async throws -> Data {
        try await session.data(from: url).0
    }
}

/// The POTA activator board, polled while a log wants it (spec 2026-08-25
/// decision 3). `api.pota.app` refuses HEAD, so each poll is a plain GET of
/// the same list the site reads (`PotaSpot.boardURL`, banked in
/// docs/research/pota/SOURCES.md); a minute keeps well under the site's own
/// refresh habits. A failed poll keeps the last board and says so in the
/// console — the map fades stale spots on its own age-out.
@MainActor
@Observable
final class PotaBoardClient {
    private(set) var spots: [Spot] = []
    private(set) var console: [String] = []
    private(set) var isPolling = false

    static let interval: TimeInterval = 60

    private let fetcher: PotaBoardFetching
    private var pollTask: Task<Void, Never>?

    init(fetcher: PotaBoardFetching = URLSessionPotaBoardFetcher()) {
        self.fetcher = fetcher
    }

    func start() {
        guard !isPolling else { return }
        isPolling = true
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                try? await Task.sleep(nanoseconds: UInt64(Self.interval * 1_000_000_000))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        isPolling = false
    }

    /// One fetch — the poll loop's body, and the tests' direct entry.
    func pollOnce() async {
        do {
            let data = try await fetcher.get(PotaSpot.boardURL)
            guard let rows = PotaSpot.board(from: data) else {
                log("board: unreadable reply — keeping the last list")
                return
            }
            spots = PotaSpot.mapToSpots(rows, now: Date())
        } catch {
            log("board: \(error.localizedDescription) — keeping the last list")
        }
    }

    private func log(_ line: String) {
        console.append(line)
        if console.count > 100 { console.removeFirst(console.count - 100) }
    }
}
