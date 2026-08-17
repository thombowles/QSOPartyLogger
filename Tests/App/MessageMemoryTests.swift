import XCTest
@testable import QSOPartyLogger

/// The operator's F-key messages, remembered per party between logs.
///
/// Messages live in the log file, so a new log for a party the operator had
/// already customised started from the party defaults and the work was redone
/// every year (2026-08-16: "make sure CW memories are remembered per
/// contest"). Voice recordings solved this per party on disk; CW text is
/// small and goes where every other per-machine memory goes.
final class MessageMemoryTests: XCTestCase {

    /// A fixed suite name — `removePersistentDomain` leaves the plist behind,
    /// so a per-run UUID would litter Preferences.
    private func scratchStore() throws -> UserDefaults {
        let suiteName = "org.b5n.QSOPartyLogger.tests.messagememory"
        UserDefaults().removePersistentDomain(forName: suiteName)
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        return try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    private var custom: MessageSets {
        var sets = MessageSets.standard
        sets.run[0] = "CQ SKEETER {MYCALL} {MYCALL}"
        sets.phoneRun = [5, nil, nil, nil, nil, nil, nil, nil]
        sets.voiceMemoryNames[4] = "CQ long"
        return sets
    }

    func testAnUnknownPartyHasNothing() throws {
        let memory = MessageMemory(defaults: try scratchStore())
        XCTAssertNil(memory.messages(for: "skeeter"))
    }

    /// The whole set comes back — CW text, the phone mapping and the memory
    /// names alike — and it survives a re-read from the same store, which is
    /// what "between logs" means.
    func testRemembersAWholeSetAcrossAReRead() throws {
        let store = try scratchStore()
        MessageMemory(defaults: store).remember(custom, for: "skeeter")
        XCTAssertEqual(MessageMemory(defaults: store).messages(for: "skeeter"), custom)
    }

    func testPartiesAreIndependent() throws {
        let memory = MessageMemory(defaults: try scratchStore())
        memory.remember(custom, for: "skeeter")
        memory.remember(.standard, for: "ksqp")
        XCTAssertEqual(memory.messages(for: "skeeter"), custom)
        XCTAssertEqual(memory.messages(for: "ksqp"), .standard)
        XCTAssertNil(memory.messages(for: "cqp"))
    }

    func testRememberingAgainReplaces() throws {
        let memory = MessageMemory(defaults: try scratchStore())
        memory.remember(.standard, for: "skeeter")
        memory.remember(custom, for: "skeeter")
        XCTAssertEqual(memory.messages(for: "skeeter"), custom)
    }

    func testForgetting() throws {
        let memory = MessageMemory(defaults: try scratchStore())
        memory.remember(custom, for: "skeeter")
        memory.remember(.standard, for: "ksqp")
        memory.forget("skeeter")
        XCTAssertNil(memory.messages(for: "skeeter"))
        XCTAssertEqual(memory.messages(for: "ksqp"), .standard, "forgetting one leaves the rest")
    }

    /// A hand-edited or downgraded preference file must never take the
    /// memory down with it: unreadable data reads as nothing remembered.
    func testUnreadableDataReadsAsEmpty() throws {
        let store = try scratchStore()
        store.set(Data("not json".utf8), forKey: MessageMemory.key)
        let memory = MessageMemory(defaults: store)
        XCTAssertNil(memory.messages(for: "skeeter"))
        memory.remember(custom, for: "skeeter")
        XCTAssertEqual(memory.messages(for: "skeeter"), custom, "and writing over it works")
    }
}
