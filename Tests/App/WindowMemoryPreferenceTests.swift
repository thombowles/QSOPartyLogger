import XCTest
@testable import QSOPartyLogger

/// `AppSettings.logWindowFrame`, `bandMapShown` and `bandMapFrame` — the
/// three preferences that let a log window and its band map come back where
/// they were: defaults, persistence, and the fallback for an unreadable frame.
final class WindowMemoryPreferenceTests: XCTestCase {

    private func scratchStore(seeding seed: [String: Any] = [:]) throws -> UserDefaults {
        let suiteName = "org.b5n.QSOPartyLogger.tests.windowMemory"
        UserDefaults().removePersistentDomain(forName: suiteName)
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        let scratch = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        for (key, value) in seed { scratch.set(value, forKey: key) }
        return scratch
    }

    /// Nothing remembered: the system places the window, the map is closed.
    @MainActor
    func testAnEmptyStoreRemembersNothing() throws {
        let settings = AppSettings(defaults: try scratchStore())
        XCTAssertNil(settings.logWindowFrame)
        XCTAssertFalse(settings.bandMapShown)
        XCTAssertNil(settings.bandMapFrame)
    }

    @MainActor
    func testTheFramesPersistAsRectStrings() throws {
        let scratch = try scratchStore()
        let settings = AppSettings(defaults: scratch)
        settings.logWindowFrame = CGRect(x: 10, y: 20, width: 1300, height: 820)
        // The scene reads the frame at launch straight from the store.
        XCTAssertEqual(AppSettings.storedFrame(forKey: "logWindowFrame", in: scratch)?.height, 820)
        settings.bandMapFrame = CGRect(x: 1320, y: 300, width: 260, height: 540)
        settings.bandMapShown = true
        XCTAssertEqual(scratch.string(forKey: "logWindowFrame"), "{{10, 20}, {1300, 820}}")
        XCTAssertEqual(scratch.string(forKey: "bandMapFrame"), "{{1320, 300}, {260, 540}}")
        XCTAssertEqual(scratch.bool(forKey: "bandMapShown"), true)
    }

    @MainActor
    func testStoredFramesAreReadBackOnTheNextLaunch() throws {
        let scratch = try scratchStore()
        let first = AppSettings(defaults: scratch)
        first.logWindowFrame = CGRect(x: 10, y: 20, width: 1300, height: 820)
        first.bandMapFrame = CGRect(x: 1320, y: 300, width: 260, height: 540)
        first.bandMapShown = true
        let next = AppSettings(defaults: scratch)
        XCTAssertEqual(next.logWindowFrame, CGRect(x: 10, y: 20, width: 1300, height: 820))
        XCTAssertEqual(next.bandMapFrame, CGRect(x: 1320, y: 300, width: 260, height: 540))
        XCTAssertTrue(next.bandMapShown)
    }

    /// Clearing a frame removes the key, so the next launch is placed by the
    /// system rather than at an empty rect.
    @MainActor
    func testClearingAFrameRemovesIt() throws {
        let scratch = try scratchStore()
        let settings = AppSettings(defaults: scratch)
        settings.logWindowFrame = CGRect(x: 10, y: 20, width: 1300, height: 820)
        settings.logWindowFrame = nil
        XCTAssertNil(scratch.object(forKey: "logWindowFrame"))
        XCTAssertNil(AppSettings(defaults: scratch).logWindowFrame)
    }

    /// A hand-edited or downgraded preference file must not produce an empty
    /// or absurd frame: an unreadable string, or one with no size, reads as
    /// nothing remembered.
    @MainActor
    func testAnUnreadableFrameReadsAsNothingRemembered() throws {
        let scratch = try scratchStore(seeding: [
            "logWindowFrame": "somewhere",
            "bandMapFrame": "{{0, 0}, {0, 0}}",
        ])
        let settings = AppSettings(defaults: scratch)
        XCTAssertNil(settings.logWindowFrame)
        XCTAssertNil(settings.bandMapFrame)
    }
}
