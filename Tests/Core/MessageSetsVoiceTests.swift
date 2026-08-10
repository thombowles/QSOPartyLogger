import XCTest
@testable import QSOPartyLogger

final class MessageSetsVoiceTests: XCTestCase {

    // MARK: Captions

    func testCaptionLeadsWithTheMemoryNumber() {
        let sets = MessageSets.standard
        XCTAssertEqual(sets.voiceMemoryCaption(1), "M1 CQ")
        XCTAssertEqual(sets.voiceMemoryCaption(4), "M4 AGN?")
    }

    /// An unnamed memory still says which memory it is. The number is the part
    /// the app can vouch for; the name is the operator's own note.
    func testCaptionForAnUnnamedMemoryIsJustTheNumber() {
        XCTAssertEqual(MessageSets.standard.voiceMemoryCaption(6), "M6")
    }

    func testCaptionTrimsAWhitespaceOnlyName() {
        var sets = MessageSets.standard
        sets.voiceMemoryNames[5] = "   "
        XCTAssertEqual(sets.voiceMemoryCaption(6), "M6")
    }

    func testCaptionOutOfRangeIsStillTheNumber() {
        XCTAssertEqual(MessageSets.standard.voiceMemoryCaption(99), "M99")
    }

    /// The property the per-memory indexing exists for: one rename reaches
    /// every F-key pointing at that memory, in both operating styles at once.
    func testRenamingAMemoryChangesEveryKeyThatPointsAtIt() {
        var sets = MessageSets.standard
        sets.voiceMemoryNames[1] = "59 TRAVIS"

        let runMemory = try? XCTUnwrap(sets.voiceMemories(for: .run)[1])
        let spMemory = try? XCTUnwrap(sets.voiceMemories(for: .searchPounce)[1])
        XCTAssertEqual(runMemory, 2)
        XCTAssertEqual(spMemory, 2)
        XCTAssertEqual(sets.voiceMemoryCaption(2), "M2 59 TRAVIS")
    }

    // MARK: Defaults

    /// Defaults stay inside memories 1-4 so the common case never triggers a
    /// bank change on a K3.
    func testDefaultMappingsNeverReachBankTwo() {
        for memory in MessageSets.standard.phoneRun.compactMap({ $0 })
            + MessageSets.standard.phoneSearchPounce.compactMap({ $0 }) {
            XCTAssertLessThanOrEqual(memory, 4, "default mapping reached memory \(memory)")
        }
    }

    func testDefaultRunMapping() {
        XCTAssertEqual(MessageSets.standard.phoneRun, [1, 2, 3, nil, 4, nil, nil, nil])
    }

    /// S&P F1 is the "send my call" step, deliberately unassigned: a callsign
    /// is faster spoken than recorded.
    func testDefaultSearchPounceLeavesF1Unassigned() {
        XCTAssertEqual(MessageSets.standard.phoneSearchPounce, [nil, 2, 3, nil, 4, nil, nil, nil])
    }

    func testVoiceMemoriesSelectsBySet() {
        XCTAssertEqual(MessageSets.standard.voiceMemories(for: .run).first ?? nil, 1)
        XCTAssertNil(MessageSets.standard.voiceMemories(for: .searchPounce).first ?? nil)
    }

    // MARK: Codable

    /// A log written before this shipped carries only `run` and `searchPounce`.
    /// It must decode with those untouched and the phone defaults filled in.
    func testDecodingAPreVoiceLogFillsInPhoneDefaults() throws {
        let json = """
        {"run":["CQ TEST {MYCALL}","X"],"searchPounce":["{MYCALL}"]}
        """
        let sets = try JSONDecoder().decode(MessageSets.self, from: Data(json.utf8))

        XCTAssertEqual(sets.run, ["CQ TEST {MYCALL}", "X"])
        XCTAssertEqual(sets.searchPounce, ["{MYCALL}"])
        XCTAssertEqual(sets.phoneRun, MessageSets.defaultPhoneRun)
        XCTAssertEqual(sets.voiceMemoryNames, MessageSets.defaultVoiceMemoryNames)
    }

    func testPhoneFieldsSurviveARoundTrip() throws {
        var sets = MessageSets.standard
        sets.phoneRun = [7, nil, 3, nil, nil, nil, nil, nil]
        sets.voiceMemoryNames[6] = "QRZ"

        let data = try JSONEncoder().encode(sets)
        let back = try JSONDecoder().decode(MessageSets.self, from: data)

        XCTAssertEqual(back.phoneRun, [7, nil, 3, nil, nil, nil, nil, nil])
        XCTAssertEqual(back.voiceMemoryCaption(7), "M7 QRZ")
        XCTAssertEqual(back.run, sets.run)
    }

    // MARK: Mismatch checks stay off the phone set

    /// `ExchangeMismatch` asks whether a message mentions {SERIAL} or {RST}.
    /// A recording cannot be inspected, so phone content must never trip it —
    /// a warning the operator cannot act on is worse than none.
    func testPhoneContentNeverTripsTheExchangeMismatchCheck() throws {
        let cqp = try XCTUnwrap(PartyCatalog.party(id: "cqp"))
        var sets = MessageSets.defaults(for: cqp)
        sets.phoneRun = [1, 2, 3, nil, 4, nil, nil, nil]
        sets.voiceMemoryNames = Array(repeating: "", count: 8)

        XCTAssertNil(sets.exchangeMismatch(with: cqp))
    }
}
