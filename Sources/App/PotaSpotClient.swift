import Foundation
import Observation

/// How the client reaches api.pota.app — a seam, so tests script the
/// server's answers and never touch the network.
protocol PotaSpotPosting: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct LivePotaSpotPoster: PotaSpotPosting {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = [
            "User-Agent": "QSOPartyLogger/1.0 (+https://github.com/KE5CW) macOS",
        ]
        return URLSession(configuration: config)
    }()

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// Posts a spot to pota.app the way the site's own form does, and says what
/// became of it. `HubSpotClient`'s posture: quiet, inline, never modal, and
/// a 2xx means *sent* — the board's own list is the confirmation. The POST
/// answers with that list, so most sends confirm at once; one that does not
/// is looked for twice more before it is called unconfirmed.
@MainActor
@Observable
final class PotaSpotClient {

    private(set) var sendState: SpotSendState = .idle {
        didSet { onSendStateChange?(sendState) }
    }
    /// The dispatcher's window on the send — every change, including a
    /// verdict a follow-up delivers.
    var onSendStateChange: ((SpotSendState) -> Void)?
    /// Recent activity, newest last (capped) — the same diagnostic the
    /// cluster and hub windows give.
    private(set) var console: [String] = []

    /// Follow-up looks at the board after a 2xx that did not show the spot,
    /// in seconds after the send.
    static let confirmationDelays: [TimeInterval] = [10, 40]
    private static let maxConsoleLines = 100

    private let poster: PotaSpotPosting
    private let confirmationDelays: [TimeInterval]
    private var lastSent: PotaSpot.Fields?
    private var lastSentAt: Date?
    private var confirmationTask: Task<Void, Never>?

    init(
        poster: PotaSpotPosting = LivePotaSpotPoster(),
        confirmationDelays: [TimeInterval] = PotaSpotClient.confirmationDelays
    ) {
        self.poster = poster
        self.confirmationDelays = confirmationDelays
    }

    private enum Refusal: Error {
        case server(status: Int, body: Data)
    }

    /// Post a spot — the caller has confirmed it with the operator; this
    /// reaches a public board at once.
    func post(_ fields: PotaSpot.Fields, now: Date = Date()) async {
        if let problem = PotaSpot.validate(fields) {
            sendState = .failed(problem.errorDescription ?? "Invalid spot.")
            return
        }
        if SpotRepeat.isRepeat(fields, of: lastSent, lastSentAt: lastSentAt, now: now) {
            sendState = .failed("That spot just went out to pota.app — nothing has changed since.")
            return
        }
        var request = URLRequest(url: PotaSpot.postURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            request.httpBody = try PotaSpot.jsonBody(fields)
        } catch {
            sendState = .failed("Couldn't build the spot: \(error.localizedDescription)")
            return
        }

        confirmationTask?.cancel()
        sendState = .sending
        log("> spot \(fields.activator) \(SpotFrequency.text(kHz: fields.frequencyKHz)) "
            + "\(fields.reference) \(fields.mode)")
        do {
            let (data, http) = try await poster.send(request)
            guard (200..<300).contains(http.statusCode) else {
                throw Refusal.server(status: http.statusCode, body: data)
            }
            lastSent = fields
            lastSentAt = now
            if let board = PotaSpot.board(from: data), PotaSpot.contains(fields, in: board) {
                sendState = .confirmed
                log("*** spot on pota.app")
            } else {
                sendState = .sent(now)
                log("*** spot sent — checking pota.app for it")
                scheduleConfirmation(of: fields)
            }
        } catch Refusal.server(let status, let body) {
            let text = PotaSpot.failureText(status: status, body: body)
            sendState = .failed(text)
            log("*** \(text)")
        } catch {
            sendState = .failed("Couldn't reach pota.app: \(error.localizedDescription)")
            log("*** spot failed: \(error.localizedDescription)")
        }
    }

    /// The board is read at each delay; the first look that shows the spot
    /// confirms it, and running out of looks is reported rather than left
    /// hanging — an unverified send would leave the operator sitting on a
    /// frequency believing they are advertised.
    private func scheduleConfirmation(of fields: PotaSpot.Fields) {
        let delays = confirmationDelays
        confirmationTask = Task { [weak self] in
            var elapsed: TimeInterval = 0
            for delay in delays {
                try? await Task.sleep(nanoseconds: UInt64(max(0, delay - elapsed) * 1_000_000_000))
                elapsed = delay
                guard !Task.isCancelled, let self else { return }
                if await self.boardShows(fields) {
                    self.sendState = .confirmed
                    self.log("*** spot on pota.app")
                    return
                }
            }
            guard !Task.isCancelled, let self else { return }
            self.sendState = .failed(
                "The spot was sent but hasn't appeared on pota.app. It may not have been "
                + "accepted — check the page before relying on it."
            )
            self.log("*** spot not seen on pota.app")
        }
    }

    private func boardShows(_ fields: PotaSpot.Fields) async -> Bool {
        var request = URLRequest(url: PotaSpot.boardURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, http) = try? await poster.send(request),
              (200..<300).contains(http.statusCode),
              let board = PotaSpot.board(from: data)
        else { return false }
        return PotaSpot.contains(fields, in: board)
    }

    private func log(_ line: String) {
        console.append(line)
        if console.count > Self.maxConsoleLines {
            console.removeFirst(console.count - Self.maxConsoleLines)
        }
    }
}
