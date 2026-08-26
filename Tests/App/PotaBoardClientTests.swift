import XCTest
@testable import QSOPartyLogger

/// The board poller: wholesale-published rows, failures keep the last board
/// and land in the console — never a modal, never a block. Tests drive the
/// fetch directly; no timers fire here.
@MainActor
final class PotaBoardClientTests: XCTestCase {

    final class ScriptedFetcher: PotaBoardFetching, @unchecked Sendable {
        var responses: [Result<String, Error>]
        private(set) var calls = 0
        init(_ responses: [Result<String, Error>]) { self.responses = responses }
        func get(_ url: URL) async throws -> Data {
            calls += 1
            guard !responses.isEmpty else { throw URLError(.badServerResponse) }
            return Data(try responses.removeFirst().get().utf8)
        }
    }

    private let board = """
        [{"activator": "W8EKM", "frequency": "21320", "mode": "SSB",
          "reference": "US-6653", "spotter": "W8EKM", "source": "Web"}]
        """

    func testPollPublishesSpots() async {
        let fetcher = ScriptedFetcher([.success(board)])
        let client = PotaBoardClient(fetcher: fetcher)
        await client.pollOnce()
        XCTAssertEqual(client.spots.count, 1)
        XCTAssertEqual(client.spots.first?.park, "US-6653")
        XCTAssertEqual(client.spots.first?.source, .pota)
    }

    func testFailureKeepsTheLastBoardAndSaysSo() async {
        let fetcher = ScriptedFetcher([.success(board), .failure(URLError(.timedOut))])
        let client = PotaBoardClient(fetcher: fetcher)
        await client.pollOnce()
        await client.pollOnce()
        XCTAssertEqual(client.spots.count, 1, "a hiccup never empties the map")
        XCTAssertFalse(client.console.isEmpty)
    }

    func testNonListBodyIsAFailureNotAnEmptyBoard() async {
        let fetcher = ScriptedFetcher([.success(board), .success("<html>maintenance</html>")])
        let client = PotaBoardClient(fetcher: fetcher)
        await client.pollOnce()
        await client.pollOnce()
        XCTAssertEqual(client.spots.count, 1)
    }

    func testStopClearsNothingButStopsPolling() async {
        let fetcher = ScriptedFetcher([.success(board)])
        let client = PotaBoardClient(fetcher: fetcher)
        await client.pollOnce()
        client.stop()
        XCTAssertEqual(client.spots.count, 1,
                       "the store's age-out fades them; stop just stops asking")
        XCTAssertFalse(client.isPolling)
    }
}
