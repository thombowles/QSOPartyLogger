import XCTest
@testable import QSOPartyLogger

/// Telnet-level handling for cluster nodes: when to answer the login prompt,
/// and stripping telnet negotiation bytes.
final class ClusterProtocolTests: XCTestCase {

    // MARK: Login prompt detection

    func testDetectsRealLoginPrompts() {
        XCTAssertTrue(ClusterProtocol.isAwaitingLogin("login: "))
        XCTAssertTrue(ClusterProtocol.isAwaitingLogin("Please enter your call: "))
        XCTAssertTrue(ClusterProtocol.isAwaitingLogin("enter your callsign:"))
        XCTAssertTrue(ClusterProtocol.isAwaitingLogin("Hello\r\nlogin:"))
        XCTAssertTrue(ClusterProtocol.isAwaitingLogin("Your call: "))
        XCTAssertTrue(ClusterProtocol.isAwaitingLogin("call:"))
    }

    /// The bug that broke VE7CC: its banner mentions "callsign" many lines
    /// before the prompt, so a naive `contains("call")` fires the login too
    /// early and the node never gets the callsign it eventually asks for.
    func testBannerMentioningCallsignIsNotAPrompt() {
        let banner = """
            Greetings from the VE7CC-1 cluster.
            *     Please login with a callsign indicating your correct country      *
            *                          Portable calls are ok.                       *
            Running CC Cluster software version 3.397
            """
        XCTAssertFalse(
            ClusterProtocol.isAwaitingLogin(banner),
            "the word 'callsign' in banner text must not trigger login"
        )
        XCTAssertFalse(ClusterProtocol.isAwaitingLogin("To see FT8 spots you MUST enter SET/FT8"))
        XCTAssertFalse(ClusterProtocol.isAwaitingLogin(""))
    }

    /// Verbatim VE7CC-1 banner (CC Cluster 3.397), captured from the live
    /// node. Answering anywhere before the final prompt is the bug.
    func testRealCCClusterBannerOnlyTriggersAtTheFinalPrompt() {
        let banner = """
            *** Connected to VE7CC-1:
            Greetings from the VE7CC-1 cluster.
            To see FT8 spots you MUST enter SET/FT8
            Running CC Cluster software version 3.397
            *     Please login with a callsign indicating your correct country      *
            *                          Portable calls are ok.                       *
            For information on CC Cluster software see:
            AR User program now at ver. 2.447
            """
        XCTAssertFalse(ClusterProtocol.isAwaitingLogin(banner), "banner alone is not a prompt")
        XCTAssertTrue(
            ClusterProtocol.isAwaitingLogin(banner + "\r\nPlease enter your call: "),
            "the trailing prompt is what we answer"
        )
        XCTAssertTrue(ClusterProtocol.isAwaitingLogin(banner + "\r\nPlease enter your call: \r\nlogin: "))
    }

    func testPromptOnlyCountsAtTheEndOfTheStream() {
        // A prompt followed by more banner text is stale — the node moved on.
        XCTAssertFalse(ClusterProtocol.isAwaitingLogin("login:\r\nWelcome, spots follow\r\n"))
        XCTAssertTrue(ClusterProtocol.isAwaitingLogin("Welcome\r\nPlease enter your call: "))
    }

    func testRepeatedPromptMeansLoginWasNotAccepted() {
        XCTAssertTrue(ClusterProtocol.isAwaitingLogin("login: "), "re-prompt is detectable")
    }

    // MARK: Line splitting

    /// Swift stores "\r\n" as ONE Character, so a naive
    /// `firstIndex(where: { $0 == "\n" || $0 == "\r" })` matches neither and
    /// no line is ever extracted. Every cluster node sends CRLF, which made
    /// the whole spot feed silently empty.
    func testSplitsCRLFLines() {
        var buffer = "Welcome to WA9PIE-2\r\n===\r\nlogin: "
        let lines = ClusterProtocol.takeLines(from: &buffer)
        XCTAssertEqual(lines, ["Welcome to WA9PIE-2", "==="])
        XCTAssertEqual(buffer, "login: ", "the unterminated prompt stays for the caller")
    }

    func testSplitsLFAndCROnlyLines() {
        var lf = "one\ntwo\n"
        XCTAssertEqual(ClusterProtocol.takeLines(from: &lf), ["one", "two"])
        XCTAssertEqual(lf, "")

        var cr = "one\rtwo\r"
        XCTAssertEqual(ClusterProtocol.takeLines(from: &cr), ["one", "two"])
        XCTAssertEqual(cr, "")
    }

    func testKeepsPartialLineForNextChunk() {
        var buffer = "DX de W3LPL:  14025.0  K5ABC\r\nDX de N0AX:  70"
        XCTAssertEqual(ClusterProtocol.takeLines(from: &buffer).count, 1)
        XCTAssertEqual(buffer, "DX de N0AX:  70")
        buffer += "40.0  W0BH  test  1523Z\r\n"
        let rest = ClusterProtocol.takeLines(from: &buffer)
        XCTAssertEqual(rest.count, 1)
        XCTAssertTrue(rest[0].contains("W0BH"))
        XCTAssertEqual(buffer, "")
    }

    func testSplitAcrossChunkBoundaryInsideCRLF() {
        // A chunk can end on the CR with the LF arriving next — that must
        // still yield exactly one line, not two.
        var buffer = "spot one\r"
        XCTAssertEqual(ClusterProtocol.takeLines(from: &buffer), ["spot one"])
        buffer += "\nspot two\r\n"
        XCTAssertEqual(ClusterProtocol.takeLines(from: &buffer), ["spot two"])
    }

    func testDropsBlankLines() {
        var buffer = "a\r\n\r\n\r\nb\r\n"
        XCTAssertEqual(ClusterProtocol.takeLines(from: &buffer), ["a", "b"])
    }

    /// End-to-end on the real WA9PIE-2 banner: lines come out, and the
    /// trailing prompt is left behind for the login check.
    func testRealDXSpiderBannerYieldsLinesThenPrompt() {
        var buffer = "Welcome to the WA9PIE-2 Global DX Spotting Network running on DXSpider\r\n"
            + "===\r\n"
            + "This is the recommended DX cluster system for Ham Radio Deluxe, but\r\n"
            + "everyone is welcome.\r\n"
            + "===\r\n"
            + "login: "
        let lines = ClusterProtocol.takeLines(from: &buffer)
        XCTAssertEqual(lines.count, 5)
        XCTAssertEqual(lines.first, "Welcome to the WA9PIE-2 Global DX Spotting Network running on DXSpider")
        XCTAssertTrue(ClusterProtocol.isAwaitingLogin(buffer))
    }

    // MARK: Telnet negotiation

    func testStripsIACSequences() {
        // IAC DO ECHO, IAC WILL SGA around plain text.
        var bytes: [UInt8] = [255, 253, 1]
        bytes += Array("DX de W3LPL:".utf8)
        bytes += [255, 251, 3]
        bytes += Array(" 14025.0".utf8)
        let (text, replies) = ClusterProtocol.stripTelnet(Data(bytes))
        XCTAssertEqual(text, "DX de W3LPL: 14025.0")
        XCTAssertFalse(replies.isEmpty, "server negotiation gets a refusal so it stops asking")
    }

    func testStripsEscapedIACLiteral() {
        // IAC IAC is a literal 0xFF byte, not a command.
        let bytes: [UInt8] = Array("A".utf8) + [255, 255] + Array("B".utf8)
        let (text, _) = ClusterProtocol.stripTelnet(Data(bytes))
        XCTAssertEqual(text.count, 3, "escaped IAC collapses to one byte")
    }

    func testPlainTextPassesThroughUntouched() {
        let (text, replies) = ClusterProtocol.stripTelnet(Data("DX de N0AX: 7040.0 W0BH\r\n".utf8))
        XCTAssertEqual(text, "DX de N0AX: 7040.0 W0BH\r\n")
        XCTAssertTrue(replies.isEmpty)
    }

    func testHandlesSubnegotiationBlocks() {
        // IAC SB ... IAC SE must be dropped whole.
        var bytes: [UInt8] = Array("X".utf8)
        bytes += [255, 250, 24, 0, 65, 66, 255, 240]   // IAC SB TERMINAL-TYPE ... IAC SE
        bytes += Array("Y".utf8)
        let (text, _) = ClusterProtocol.stripTelnet(Data(bytes))
        XCTAssertEqual(text, "XY")
    }
}
