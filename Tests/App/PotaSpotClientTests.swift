import XCTest
@testable import QSOPartyLogger

/// Posting a spot to pota.app the way the site's own form does, and saying
/// what became of it — driven through a scripted poster, never the network.
@MainActor
final class PotaSpotClientTests: XCTestCase {

    /// Answers each request in turn from a script; records what was sent.
    final class ScriptedPoster: PotaSpotPosting, @unchecked Sendable {
        var answers: [Result<(Data, Int), Error>] = []
        private(set) var requests: [URLRequest] = []

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            requests.append(request)
            guard !answers.isEmpty else { throw URLError(.notConnectedToInternet) }
            let (data, status) = try answers.removeFirst().get()
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
            )!
            return (data, response)
        }
    }

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func fields(reference: String = "US-0817") -> PotaSpot.Fields {
        .init(activator: "KE5CW", spotter: "KE5CW", frequencyKHz: 7047,
              reference: reference, mode: "CW", comments: "")
    }

    private func boardData(withOurs: Bool) -> Data {
        let ours = #"{"spotId":1,"activator":"KE5CW","frequency":"7047","mode":"CW","reference":"US-0817","spotter":"KE5CW","source":"QSOPartyLogger","spotTime":"2026-08-15T16:04:15"}"#
        let other = #"{"spotId":2,"activator":"W8EKM","frequency":"21320","mode":"SSB","reference":"US-6653","spotter":"W8EKM","source":"Web","spotTime":"2026-08-15T16:04:15"}"#
        return Data("[\(withOurs ? ours + "," : "")\(other)]".utf8)
    }

    private func client(_ poster: ScriptedPoster) -> PotaSpotClient {
        PotaSpotClient(poster: poster, confirmationDelays: [0.01, 0.02])
    }

    private func settle() async {
        try? await Task.sleep(nanoseconds: 200_000_000)
    }

    // MARK: The request

    func testThePostIsTheFormsRequest() async throws {
        let poster = ScriptedPoster()
        poster.answers = [.success((boardData(withOurs: true), 200))]
        await client(poster).post(fields(), now: t0)
        let request = try XCTUnwrap(poster.requests.first)
        XCTAssertEqual(request.url, PotaSpot.postURL)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.httpBody, try PotaSpot.jsonBody(fields()))
    }

    // MARK: Confirmation

    func testABoardThatShowsTheSpotConfirmsAtOnce() async {
        let poster = ScriptedPoster()
        poster.answers = [.success((boardData(withOurs: true), 200))]
        let c = client(poster)
        await c.post(fields(), now: t0)
        XCTAssertEqual(c.sendState, .confirmed)
        await settle()
        XCTAssertEqual(poster.requests.count, 1, "no follow-up when the response already confirmed")
    }

    func testASendTheBoardDoesNotShowIsConfirmedByAFollowUp() async {
        let poster = ScriptedPoster()
        poster.answers = [
            .success((boardData(withOurs: false), 200)),
            .success((boardData(withOurs: true), 200)),
        ]
        let c = client(poster)
        await c.post(fields(), now: t0)
        XCTAssertEqual(c.sendState, .sent(t0))
        await settle()
        XCTAssertEqual(c.sendState, .confirmed)
        XCTAssertEqual(poster.requests.count, 2)
        XCTAssertEqual(poster.requests.last?.url, PotaSpot.boardURL)
        XCTAssertEqual(poster.requests.last?.httpMethod, "GET")
    }

    func testTwoMissedFollowUpsFail() async {
        let poster = ScriptedPoster()
        poster.answers = [
            .success((boardData(withOurs: false), 200)),
            .success((boardData(withOurs: false), 200)),
            .success((boardData(withOurs: false), 200)),
        ]
        let c = client(poster)
        await c.post(fields(), now: t0)
        await settle()
        XCTAssertEqual(
            c.sendState,
            .failed("The spot was sent but hasn't appeared on pota.app. It may not have been "
                    + "accepted — check the page before relying on it.")
        )
        XCTAssertEqual(poster.requests.count, 3)
    }

    /// A follow-up that cannot be read is a miss, not a crash — and not a
    /// confirmation either.
    func testAnUnreadableFollowUpCountsAsAMiss() async {
        let poster = ScriptedPoster()
        poster.answers = [
            .success((boardData(withOurs: false), 200)),
            .failure(URLError(.timedOut)),
            .success((boardData(withOurs: true), 200)),
        ]
        let c = client(poster)
        await c.post(fields(), now: t0)
        await settle()
        XCTAssertEqual(c.sendState, .confirmed)
    }

    // MARK: Failure

    func testTheServersRefusalIsShownInItsOwnWords() async {
        let poster = ScriptedPoster()
        poster.answers = [.success((Data("Invalid callsign".utf8), 400))]
        let c = client(poster)
        await c.post(fields(), now: t0)
        XCTAssertEqual(c.sendState, .failed("pota.app refused the spot: Invalid callsign"))
    }

    func testAnUnreachableServerFailsInline() async {
        let poster = ScriptedPoster()
        poster.answers = [.failure(URLError(.notConnectedToInternet))]
        let c = client(poster)
        await c.post(fields(), now: t0)
        XCTAssertEqual(c.sendState.failure?.hasPrefix("Couldn't reach pota.app:"), true)
    }

    func testAnInvalidSpotNeverReachesTheNetwork() async {
        let poster = ScriptedPoster()
        let c = client(poster)
        await c.post(fields(reference: "bad"), now: t0)
        XCTAssertEqual(c.sendState, .failed("BAD isn't a reference pota.app accepts — they look like US-0817."))
        XCTAssertTrue(poster.requests.isEmpty)
    }

    func testAnIdenticalSpotInsideFiveMinutesIsRefused() async {
        let poster = ScriptedPoster()
        poster.answers = [.success((boardData(withOurs: true), 200))]
        let c = client(poster)
        await c.post(fields(), now: t0)
        await c.post(fields(), now: t0.addingTimeInterval(60))
        XCTAssertEqual(c.sendState, .failed("That spot just went out to pota.app — nothing has changed since."))
        XCTAssertEqual(poster.requests.count, 1)
    }

    /// A refused send is not "sent", so the same spot may go again at once.
    func testARefusedSpotDoesNotArmTheRepeatGuard() async {
        let poster = ScriptedPoster()
        poster.answers = [
            .failure(URLError(.notConnectedToInternet)),
            .success((boardData(withOurs: true), 200)),
        ]
        let c = client(poster)
        await c.post(fields(), now: t0)
        await c.post(fields(), now: t0.addingTimeInterval(5))
        XCTAssertEqual(c.sendState, .confirmed)
    }

    // MARK: Reporting

    func testStateChangesAreReported() async {
        let poster = ScriptedPoster()
        poster.answers = [.success((boardData(withOurs: true), 200))]
        let c = client(poster)
        var seen: [SpotSendState] = []
        c.onSendStateChange = { seen.append($0) }
        await c.post(fields(), now: t0)
        XCTAssertEqual(seen, [.sending, .confirmed])
    }

    func testTheConsoleRecordsTheSend() async {
        let poster = ScriptedPoster()
        poster.answers = [.success((boardData(withOurs: true), 200))]
        let c = client(poster)
        await c.post(fields(), now: t0)
        XCTAssertEqual(c.console.first, "> spot KE5CW 7047 US-0817 CW")
        XCTAssertEqual(c.console.last, "*** spot on pota.app")
    }
}
