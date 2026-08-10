import Foundation
import Observation

/// How the client reaches SWPC — a seam, so tests script the server's answers
/// and never touch the network (constitution Article 5).
protocol SpaceWeatherFetching: Sendable {
    func get(_ url: URL) async throws -> Data
}

/// Keeps one coarse space-weather reading current for the advisor's solar
/// strand.
///
/// Quiet by construction, like `DXCCLabelClient` and `HubSpotClient`: two small
/// GETs an hour at most, every failure landing in `lastError` and the console
/// and nowhere near the entry path, and the last good reading cached to disk so
/// a contest that opens offline still starts with whatever was true last time.
///
/// **Nothing here can make an advisory appear.** The reading only ever scales
/// weights the geometry already produced, and a missing or stale one scales
/// them by 1.0 — see `SpaceWeather.modifier(band:now:)`.
@MainActor
@Observable
final class SpaceWeatherClient {

    enum Status: Equatable {
        case idle
        case fetching
        case current(SpaceWeather)
        case failed(String)
    }

    private(set) var status: Status = .idle
    /// The last good reading, from this session or from the disk cache.
    /// `nil` until one has ever been fetched on this machine.
    private(set) var reading: SpaceWeather?
    private(set) var lastError: String?
    private(set) var console: [String] = []

    /// Hourly. The flux is reported three times a day and Kp every three
    /// hours, so anything faster would be asking a public server for an answer
    /// that cannot have changed.
    static let refreshInterval: TimeInterval = 60 * 60

    static let fluxURL = URL(string: "https://services.swpc.noaa.gov/json/f107_cm_flux.json")!
    static let planetaryKURL = URL(
        string: "https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json"
    )!

    private static let maxConsoleLines = 200

    private let fetcher: SpaceWeatherFetching
    private let cacheURL: URL?

    init(
        fetcher: SpaceWeatherFetching = LiveSpaceWeatherFetcher(),
        cacheURL: URL? = SpaceWeatherStore.cacheURL
    ) {
        self.fetcher = fetcher
        self.cacheURL = cacheURL
        // Start from disk, so the first advisory of a contest does not have to
        // wait on a network round trip — and so a launch with no network at
        // all still has whatever was last true.
        if let cached = SpaceWeatherStore.load(at: cacheURL) {
            reading = cached.reading
            status = .current(cached.reading)
        }
    }

    /// Fetch unless one has run inside `refreshInterval`.
    ///
    /// Called at launch and at every contest load, like the DXCC check — the
    /// throttle is what makes those triggers free.
    func refreshIfStale(now: Date = Date(), force: Bool = false) async {
        if !force, let last = SpaceWeatherStore.load(at: cacheURL)?.checkedAt,
           now.timeIntervalSince(last) < Self.refreshInterval {
            return
        }
        await refresh(now: now)
    }

    func refresh(now: Date = Date()) async {
        status = .fetching
        lastError = nil

        // Fetched independently: one product being down is not a reason to
        // discard the other, and a reading with only a Kp in it still weighs
        // the bands it can.
        let flux = await body(Self.fluxURL, label: "F10.7 flux")
        let planetaryK = await body(Self.planetaryKURL, label: "planetary K")

        guard let fresh = SpaceWeather.reading(flux: flux, planetaryK: planetaryK) else {
            let message = "no usable reading from SWPC"
            lastError = message
            log("failed: \(message)")
            status = .failed(message)
            // Whatever was already in service stays in service. A failed fetch
            // must never be worse than no fetch.
            return
        }

        reading = fresh
        status = .current(fresh)
        log("\(fresh.summary(now: now) ?? "reading with no values")")
        SpaceWeatherStore.save(.init(reading: fresh, checkedAt: now), to: cacheURL)
    }

    private func body(_ url: URL, label: String) async -> Data? {
        do {
            return try await fetcher.get(url)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            lastError = message
            log("\(label): \(message)")
            return nil
        }
    }

    private func log(_ line: String) {
        console.append(line)
        if console.count > Self.maxConsoleLines {
            console.removeFirst(console.count - Self.maxConsoleLines)
        }
    }
}

/// Where the last good reading lives between launches, beside the DXCC label
/// overlay and the user's own party overrides.
enum SpaceWeatherStore {

    struct Cached: Codable, Equatable, Sendable {
        let reading: SpaceWeather
        /// When the fetch happened — which is not `reading.observedAt`, and is
        /// what the throttle counts.
        let checkedAt: Date
    }

    static var cacheURL: URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        return base
            .appendingPathComponent("QSOPartyLogger", isDirectory: true)
            .appendingPathComponent("space_weather.json")
    }

    static func load(at url: URL?) -> Cached? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Cached.self, from: data)
    }

    @discardableResult
    static func save(_ cached: Cached, to url: URL?) -> Bool {
        guard let url else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(cached) else { return false }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}

/// The real transport. Never used by tests.
struct LiveSpaceWeatherFetcher: SpaceWeatherFetching {
    func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("QSOPartyLogger/1.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }
}
