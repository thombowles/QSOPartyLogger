import XCTest
@testable import QSOPartyLogger

/// The Advisor's four preferences — their defaults, their persistence, and the
/// fallback that keeps the goal from ever being unset.
final class AdvisorPreferenceTests: XCTestCase {

    /// A fixed suite name rather than a per-run UUID, for the reason
    /// `SpotLabelSizePreferenceTests` gives: `removePersistentDomain` empties
    /// the domain but leaves the plist, so unique names litter the container.
    private func scratchStore(seeding seed: [String: Any] = [:]) throws -> UserDefaults {
        let suiteName = "org.b5n.QSOPartyLogger.tests.advisor"
        UserDefaults().removePersistentDomain(forName: suiteName)
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        let scratch = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        for (key, value) in seed { scratch.set(value, forKey: key) }
        return scratch
    }

    @MainActor
    func testAFreshInstallGetsTheAdvisorOnExpandedUnmutedAndScoring() throws {
        let settings = AppSettings(defaults: try scratchStore())
        XCTAssertTrue(settings.advisorEnabled)
        XCTAssertFalse(settings.advisorCollapsed)
        XCTAssertTrue(settings.advisorMutedKinds.isEmpty)
        XCTAssertEqual(settings.advisorGoal, .score)
    }

    @MainActor
    func testTheGoalPersistsUnderItsOwnKey() throws {
        let scratch = try scratchStore()
        AppSettings(defaults: scratch).advisorGoal = .qsos
        XCTAssertEqual(scratch.string(forKey: "advisorGoal"), "qsos")
        // Global, not per-log: a Challenge season is a season, so it has to
        // still be there for the next contest that opens.
        XCTAssertEqual(AppSettings(defaults: scratch).advisorGoal, .qsos)
    }

    /// A hand-edited or downgraded preference file must never leave the
    /// advisor with no yardstick — every weighting reads one.
    @MainActor
    func testAnUnreadableGoalFallsBackToScore() throws {
        let scratch = try scratchStore(seeding: ["advisorGoal": "points-per-minute"])
        XCTAssertEqual(AppSettings(defaults: scratch).advisorGoal, .score)
    }

    @MainActor
    func testMutedKindsRoundTripAndUnknownOnesAreDropped() throws {
        let scratch = try scratchStore()
        AppSettings(defaults: scratch).advisorMutedKinds = [.runFading, .scheduleEdge]
        XCTAssertEqual(scratch.stringArray(forKey: "advisorMutedKinds"),
                       ["runFading", "scheduleEdge"].sorted())
        XCTAssertEqual(AppSettings(defaults: scratch).advisorMutedKinds,
                       [.runFading, .scheduleEdge])

        let stale = try scratchStore(
            seeding: ["advisorMutedKinds": ["moveCall", "weatherReport"]])
        XCTAssertEqual(AppSettings(defaults: stale).advisorMutedKinds, [.moveCall],
                       "a kind that no longer exists is dropped, not fatal")
    }

    @MainActor
    func testTheSectionCanBeCollapsedAndSwitchedOffIndependently() throws {
        let scratch = try scratchStore()
        let settings = AppSettings(defaults: scratch)
        settings.advisorCollapsed = true
        settings.advisorEnabled = false
        XCTAssertTrue(scratch.bool(forKey: "advisorCollapsed"))
        XCTAssertFalse(scratch.bool(forKey: "advisorEnabled"))

        let reopened = AppSettings(defaults: scratch)
        XCTAssertTrue(reopened.advisorCollapsed)
        XCTAssertFalse(reopened.advisorEnabled)
    }

    /// Every kind the engine can raise is mutable from the menu, so a kind
    /// added later cannot quietly become unsilenceable.
    @MainActor
    func testEveryAdvisoryKindCanBeMuted() throws {
        let scratch = try scratchStore()
        let settings = AppSettings(defaults: scratch)
        settings.advisorMutedKinds = Set(Advisor.Advisory.Kind.allCases)
        XCTAssertEqual(AppSettings(defaults: scratch).advisorMutedKinds.count,
                       Advisor.Advisory.Kind.allCases.count)
        for kind in Advisor.Advisory.Kind.allCases {
            XCTAssertFalse(kind.label.isEmpty, "\(kind) needs a name for the menu")
        }
    }
}
