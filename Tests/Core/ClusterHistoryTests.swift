import XCTest
@testable import QSOPartyLogger

/// Recently-used cluster list: most recent first, no duplicates, capped.
final class ClusterHistoryTests: XCTestCase {

    func testAddsMostRecentFirst() {
        var list = ClusterHistory.adding("dxc.a.com:7300", to: [])
        list = ClusterHistory.adding("dxc.b.com:7373", to: list)
        XCTAssertEqual(list, ["dxc.b.com:7373", "dxc.a.com:7300"])
    }

    func testReconnectingMovesEntryToFront() {
        let list = ClusterHistory.adding(
            "dxc.a.com:7300",
            to: ["dxc.b.com:7373", "dxc.a.com:7300", "dxc.c.com:8000"]
        )
        XCTAssertEqual(list, ["dxc.a.com:7300", "dxc.b.com:7373", "dxc.c.com:8000"])
    }

    func testDeduplicatesCaseInsensitively() {
        let list = ClusterHistory.adding("DXC.A.COM:7300", to: ["dxc.a.com:7300"])
        XCTAssertEqual(list, ["DXC.A.COM:7300"], "hostnames are case-insensitive")
    }

    func testIgnoresEmptyEntries() {
        XCTAssertEqual(ClusterHistory.adding("   ", to: ["dxc.a.com:7300"]), ["dxc.a.com:7300"])
        XCTAssertEqual(ClusterHistory.adding("", to: []), [])
    }

    func testCapsListLength() {
        var list: [String] = []
        for i in 1...12 {
            list = ClusterHistory.adding("node\(i).com:7300", to: list)
        }
        XCTAssertEqual(list.count, ClusterHistory.maxEntries)
        XCTAssertEqual(list.first, "node12.com:7300")
        XCTAssertFalse(list.contains("node1.com:7300"), "oldest entries drop off")
    }

    func testEntryFormatting() {
        XCTAssertEqual(ClusterHistory.entry(host: "dxc.a.com", port: 7300), "dxc.a.com:7300")
        let parsed = ClusterHistory.parse("dxc.a.com:7373")
        XCTAssertEqual(parsed?.host, "dxc.a.com")
        XCTAssertEqual(parsed?.port, 7373)
        XCTAssertNil(ClusterHistory.parse("no-port-here"))
        XCTAssertNil(ClusterHistory.parse("bad:port"))
    }
}
