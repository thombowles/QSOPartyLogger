import XCTest
@testable import QSOPartyLogger

/// The CW messages editor's working state — Restore Defaults, the
/// exchange-mismatch banner, and the padding that keeps eight F-key rows
/// writable. None of the three had a test before 2026-07-25, when the editor
/// was a SwiftUI `View` and all of it was private.
final class MessagesDraftTests: XCTestCase {

    // MARK: Restore Defaults (⇧⌘R)

    /// The button exists so an operator who has broken their macros can get a
    /// working set back. It has to produce *this party's* set — a CQP operator
    /// handed Kansas's `{RST}` macros sends a report CQP does not want and
    /// leaves out the QSO number it does.
    func testRestoreDefaultsFollowsThePartysExchangeShape() throws {
        let cqp = try XCTUnwrap(PartyCatalog.party(id: "cqp"))
        var draft = MessagesDraft(.standard)
        XCTAssertEqual(draft[.run, 1], "{CALL} {RST} {EXCH}", "precondition")

        draft.restoreDefaults(for: cqp)

        XCTAssertEqual(draft[.run, 1], "{CALL} {SERIAL} {EXCH}")
        XCTAssertEqual(draft[.searchPounce, 1], "{SERIAL} {EXCH}")
        XCTAssertEqual(draft.edited, MessageSets.defaults(for: cqp))
    }

    /// Both sets, always. A half-restored set is a set that disagrees with
    /// itself: Run answering with a QSO number while S&P still sends a report.
    func testRestoreDefaultsReplacesBothSets() throws {
        let cqp = try XCTUnwrap(PartyCatalog.party(id: "cqp"))
        var draft = MessagesDraft(.standard)
        draft[.run, 0] = "CQ CQP W6ABC W6ABC"
        draft[.searchPounce, 0] = "W6ABC W6ABC"

        draft.restoreDefaults(for: cqp)

        XCTAssertEqual(draft[.run, 0], "CQ TEST {MYCALL}")
        XCTAssertEqual(draft[.searchPounce, 0], "{MYCALL}")
    }

    /// An unknown party takes the report form — the common shape, and better
    /// than handing an operator eight empty F-keys.
    func testRestoreDefaultsForAnUnknownPartyTakesTheReportForm() {
        var draft = MessagesDraft(.standard)
        draft.restoreDefaults(for: nil)
        XCTAssertEqual(draft.edited, MessageSets.defaults(for: nil))
        XCTAssertEqual(draft[.run, 1], "{CALL} {RST} {EXCH}")
    }

    // MARK: The warning banner

    /// The banner's whole job: a party that sends a QSO number, and macros that
    /// do not send one. This is what CQP's operator sees before going on the
    /// air with a blank where the number should be.
    func testTheBannerFiresWhenTheMacrosDropThePartysQSONumber() throws {
        let cqp = try XCTUnwrap(PartyCatalog.party(id: "cqp"))
        let draft = MessagesDraft(.standard)
        XCTAssertEqual(draft.mismatch(with: cqp), .missingSerial)
    }

    func testTheBannerFiresOnAReportAPartyDoesNotWant() throws {
        let cqp = try XCTUnwrap(PartyCatalog.party(id: "cqp"))
        var draft = MessagesDraft(MessageSets.defaults(for: cqp))
        XCTAssertNil(draft.mismatch(with: cqp), "precondition: the defaults agree")

        draft[.run, 1] = "{CALL} {RST} {SERIAL} {EXCH}"
        XCTAssertEqual(draft.mismatch(with: cqp), .extraneousRST)
    }

    /// A party whose exchange the macros match raises nothing.
    func testAMatchingSetRaisesNoBanner() throws {
        for id in ["cqp", "ksqp", "paqp", "mdc"] {
            let party = try XCTUnwrap(PartyCatalog.party(id: id), id)
            let draft = MessagesDraft(MessageSets.defaults(for: party))
            XCTAssertNil(draft.mismatch(with: party), id)
        }
    }

    /// No party, no verdict — there is nothing to check against, and a banner
    /// with no actionable fix is worse than none.
    func testAnUnknownPartyRaisesNoBanner() {
        XCTAssertNil(MessagesDraft(.standard).mismatch(with: nil))
    }

    /// The banner reads what is typed, not what is saved, so it clears the
    /// moment the operator types the fix — and Restore Defaults clears it too.
    func testTheBannerClearsAsSoonAsTheFixIsTyped() throws {
        let cqp = try XCTUnwrap(PartyCatalog.party(id: "cqp"))
        var draft = MessagesDraft(.standard)
        XCTAssertEqual(draft.mismatch(with: cqp), .missingSerial, "precondition")

        draft.restoreDefaults(for: cqp)
        XCTAssertNil(draft.mismatch(with: cqp))
    }

    // MARK: Eight slots, always

    /// The editor draws eight rows and writes into them by index. A log saved
    /// with a short set must not make those writes fall on the floor.
    func testAShortSetIsPaddedToEightWritableSlots() {
        var draft = MessagesDraft(MessageSets(run: ["CQ TEST {MYCALL}"], searchPounce: []))
        XCTAssertEqual(draft[.run, 7], "")

        draft[.run, 7] = "73 TU {MYCALL}"
        draft[.searchPounce, 3] = "{MYCALL}"

        XCTAssertEqual(draft.edited.run.count, MessagesDraft.slotCount)
        XCTAssertEqual(draft.edited.searchPounce.count, MessagesDraft.slotCount)
        XCTAssertEqual(draft.edited.run[7], "73 TU {MYCALL}")
        XCTAssertEqual(draft.edited.searchPounce[3], "{MYCALL}")
    }

    /// Out-of-range writes are dropped rather than trapping. The editor cannot
    /// produce one today, but a crash mid-contest is the worst outcome here.
    func testAnOutOfRangeSlotIsIgnored() {
        var draft = MessagesDraft(.standard)
        draft[.run, 99] = "nope"
        draft[.run, -1] = "nope"
        XCTAssertEqual(draft.edited, .standard)
    }

    /// Trailing whitespace is invisible in the field and would key as an extra
    /// inter-word gap, so what is saved is trimmed.
    func testSavedMessagesAreTrimmed() {
        var draft = MessagesDraft(.standard)
        draft[.run, 0] = "  CQ TEST {MYCALL}  "
        XCTAssertEqual(draft.edited.run[0], "CQ TEST {MYCALL}")
    }

    /// The two sets are independent: F1 in Run is the CQ, F1 in S&P is your own
    /// call, and editing one must never write through to the other.
    func testTheTwoSetsAreIndependent() {
        var draft = MessagesDraft(.standard)
        draft[.run, 0] = "CQ CQP {MYCALL}"
        XCTAssertEqual(draft[.searchPounce, 0], "{MYCALL}")
    }

    /// Round-trip: what came out of the log goes back unchanged when nothing is
    /// touched, so opening and cancelling the editor cannot dirty a log.
    func testAnUntouchedDraftRoundTripsTheLogsMessages() throws {
        let cqp = try XCTUnwrap(PartyCatalog.party(id: "cqp"))
        let stored = MessageSets.defaults(for: cqp)
        XCTAssertEqual(MessagesDraft(stored).edited, stored)
    }

    // MARK: Phone (voice memory) mappings

    func testDraftRoundTripsPhoneMappings() {
        var draft = MessagesDraft(.standard)
        draft[voice: .run, 3] = 6
        XCTAssertEqual(draft[voice: .run, 3], 6)
        XCTAssertEqual(draft.edited.phoneRun[3], 6)
        // The other set is untouched — Run and S&P map independently.
        XCTAssertNil(draft.edited.phoneSearchPounce[3])
    }

    func testDraftRoundTripsMemoryNames() {
        var draft = MessagesDraft(.standard)
        draft.setVoiceMemoryName("59 BELL", at: 1)
        XCTAssertEqual(draft.edited.voiceMemoryCaption(2), "M2 59 BELL")
    }

    func testDraftIgnoresOutOfRangeWrites() {
        var draft = MessagesDraft(.standard)
        draft[voice: .run, 99] = 3
        draft.setVoiceMemoryName("nope", at: 99)
        XCTAssertEqual(draft.edited.phoneRun, MessageSets.defaultPhoneRun)
        XCTAssertEqual(draft.edited.voiceMemoryNames, MessageSets.defaultVoiceMemoryNames)
    }

    /// Restore Defaults is whole-set on purpose — a half-restored set is a set
    /// that disagrees with itself — and the phone side restores from constants,
    /// since a party's exchange shape cannot change what is on a recording.
    func testRestoreDefaultsAlsoRestoresThePhoneSide() {
        var draft = MessagesDraft(.standard)
        draft[voice: .run, 0] = 8
        draft.setVoiceMemoryName("stale", at: 0)

        draft.restoreDefaults(for: nil)

        XCTAssertEqual(draft.edited.phoneRun, MessageSets.defaultPhoneRun)
        XCTAssertEqual(draft.edited.voiceMemoryNames, MessageSets.defaultVoiceMemoryNames)
    }
}
