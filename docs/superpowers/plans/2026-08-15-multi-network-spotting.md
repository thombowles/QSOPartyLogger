# Multi-Network Spotting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One ⇧⌘S composes one spot and posts it to every network that applies — DX cluster, QSO Party Hub, POTA — from one sheet with a live receipt of what went where.

**Architecture:** Pure Core types decide availability, compose each network's payload, validate it and word the receipt; two App clients (`PotaSpotClient`, the existing `HubSpotClient`) and the existing telnet `SpotClient` are the transports; a `SpotDispatcher` fans a `SpotDraft` out and collects per-network `SpotSendState`s into a `SpotReceipt`; the UI is a rewritten `SpotSheet` with a network row per transport and a `SpotReceiptView` capsule in the station strip. Spec: `docs/superpowers/specs/2026-08-15-multi-network-spotting-design.md`.

**Tech Stack:** Swift 6, SwiftUI (macOS 15), XCTest, XcodeGen. Tests never touch the network: `PotaSpotPosting` seam, `SpotDispatcher.Transports` closures.

**Commands** (run from the worktree root; `xcodegen generate` first whenever files are added/renamed):

```bash
xcodegen generate
set -o pipefail; xcodebuild build -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -quiet 2>&1 | tail -20
set -o pipefail; xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/<Suite> 2>&1 | grep -E "Test Suite|Test Case|error:|failed|passed" | tail -30
```

The full suite is `xcodebuild test … -destination 'platform=macOS'` with the output saved to a file (never `tail` alone — the summary line is what counts).

---

## File map

| Path | Responsibility |
| --- | --- |
| `Sources/Core/Spotting/SpotFrequency.swift` (new) | clean-kHz text every board takes |
| `Sources/Core/Spotting/SpotRepeat.swift` (new) | five-minute identical-spot guard, generic |
| `Sources/Core/Spotting/SpotSendState.swift` (new) | idle/sending/sent/confirmed/failed for every network |
| `Sources/Core/Spotting/HubSelfSpot.swift` (modify) | delegates frequency text and repeat guard |
| `Sources/Core/Spotting/SpotNetwork.swift` (new) | the three networks + preference rules |
| `Sources/Core/Spotting/SpotNetworkAvailability.swift` (new) | which networks are on offer and why not |
| `Sources/Core/Spotting/ClusterSpot.swift` (new) | `DX` command, remarks, echo match |
| `Sources/Core/Spotting/PotaSpot.swift` (new) | pota.app form rules, JSON body, board parsing |
| `Sources/Core/Spotting/SpotDraft.swift` (new) | the sheet's model → per-network payloads, problems, previews |
| `Sources/Core/Spotting/SpotReceipt.swift` (new) | per-network states, wording, tint, visibility |
| `Sources/App/HubSpotClient.swift` (modify) | `SpotSendState` + `onSendStateChange` |
| `Sources/App/PotaSpotClient.swift` (new) | POST + confirmation follow-ups behind a seam |
| `Sources/App/SpotDispatcher.swift` (new) | fan-out, receipt, cluster echo |
| `Sources/App/AppSettings.swift` (modify) | `spotNetworks` preference |
| `Sources/UI/SpotSheet.swift` (renamed from `SelfSpotSheet.swift`) | the confirming sheet with network rows |
| `Sources/UI/SpotReceiptView.swift` (new) | the receipt capsule |
| `Sources/UI/MainView.swift`, `BandMap.swift`, `LogTable.swift` (modify) | wiring, `canSpot`, menu labels |
| `Tests/Core/…`, `Tests/App/…`, `Tests/Fixtures/pota_spots_sample.json` | see tasks |
| `docs/research/pota/SOURCES.md`, `docs/research/dxcluster-dx-command.md`, `docs/PROVENANCE.md`, `README.md` | provenance and docs |

---

### Task 1: Lift `SpotFrequency`, `SpotRepeat`, `SpotSendState` out of the hub code (structural, behaviour-preserving)

**Files:**
- Create: `Sources/Core/Spotting/SpotFrequency.swift`, `Sources/Core/Spotting/SpotRepeat.swift`, `Sources/Core/Spotting/SpotSendState.swift`
- Modify: `Sources/Core/Spotting/HubSelfSpot.swift`, `Sources/App/HubSpotClient.swift`
- Test: `Tests/Core/SpotFrequencyTests.swift` (new), `Tests/Core/SpotRepeatTests.swift` (new)

- [ ] **Step 1: Write the failing tests**

`Tests/Core/SpotFrequencyTests.swift`:

```swift
import XCTest
@testable import QSOPartyLogger

/// Kilohertz the way every board's form asks for it. Not `%g`: six
/// significant digits turn 14045.25 into 14045.2 — 50 Hz off, broadcast.
final class SpotFrequencyTests: XCTestCase {
    func testWholeKilohertzHaveNoDecimalPoint() {
        XCTAssertEqual(SpotFrequency.text(kHz: 7047), "7047")
        XCTAssertEqual(SpotFrequency.text(kHz: 14150.0), "14150")
    }
    func testFractionsKeepTwoDecimalsAndDropTrailingZeros() {
        XCTAssertEqual(SpotFrequency.text(kHz: 14045.25), "14045.25")
        XCTAssertEqual(SpotFrequency.text(kHz: 7047.5), "7047.5")
        XCTAssertEqual(SpotFrequency.text(kHz: 7047.10), "7047.1")
    }
    func testTheHubFormatterIsTheSameFormatter() {
        XCTAssertEqual(HubSelfSpot.formattedFrequency(14045.25), SpotFrequency.text(kHz: 14045.25))
    }
}
```

`Tests/Core/SpotRepeatTests.swift`:

```swift
import XCTest
@testable import QSOPartyLogger

/// An identical spot repeated inside five minutes is a stuck key, not news.
final class SpotRepeatTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func testNothingSentBeforeIsNeverARepeat() {
        XCTAssertFalse(SpotRepeat.isRepeat("a", of: nil, lastSentAt: nil, now: t0))
    }
    func testTheSamePayloadInsideTheWindowIsARepeat() {
        XCTAssertTrue(SpotRepeat.isRepeat("a", of: "a", lastSentAt: t0, now: t0.addingTimeInterval(299)))
    }
    func testTheSamePayloadAfterTheWindowIsNotARepeat() {
        XCTAssertFalse(SpotRepeat.isRepeat("a", of: "a", lastSentAt: t0, now: t0.addingTimeInterval(300)))
    }
    func testAChangedPayloadIsNeverARepeat() {
        XCTAssertFalse(SpotRepeat.isRepeat("b", of: "a", lastSentAt: t0, now: t0.addingTimeInterval(1)))
    }
    func testTheHubGuardIsTheSameGuard() {
        XCTAssertEqual(HubSelfSpot.duplicateWindow, SpotRepeat.window)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `xcodegen generate && xcodebuild test … -only-testing:QSOPartyLoggerTests/SpotFrequencyTests -only-testing:QSOPartyLoggerTests/SpotRepeatTests`
Expected: build error — `SpotFrequency`/`SpotRepeat` undefined.

- [ ] **Step 3: Implement**

`Sources/Core/Spotting/SpotFrequency.swift`:

```swift
import Foundation

/// Kilohertz the way every board's own form asks for it — `14150`, or
/// `14045.25` — with no trailing zeros and never more than two decimals. Ten
/// hertz is the finest any spot carries; below that is noise.
///
/// Not `%g`: its six significant digits turn 14045.25 into 14045.2, which
/// would broadcast a frequency 50 Hz off to everyone reading the board.
enum SpotFrequency {
    static func text(kHz: Double) -> String {
        if kHz == kHz.rounded() { return String(Int(kHz)) }
        var text = String(format: "%.2f", kHz)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
```

`Sources/Core/Spotting/SpotRepeat.swift`:

```swift
import Foundation

/// The guard every outgoing spot passes: an identical spot repeated inside
/// this window is a stuck key, not news, and every network here is public.
/// A changed frequency, county or park is never a repeat — those are the
/// moments a re-spot matters.
enum SpotRepeat {
    static let window: TimeInterval = 5 * 60

    static func isRepeat<Payload: Equatable>(
        _ payload: Payload, of previous: Payload?, lastSentAt: Date?, now: Date
    ) -> Bool {
        guard let previous, let lastSentAt else { return false }
        guard now.timeIntervalSince(lastSentAt) < window else { return false }
        return payload == previous
    }
}
```

`Sources/Core/Spotting/SpotSendState.swift`:

```swift
import Foundation

/// Where one spot stands with one network. Shared by the cluster, the hub
/// and POTA so the receipt reads the same way whatever the transport.
enum SpotSendState: Equatable, Sendable {
    case idle
    case sending
    /// The network took the message. *Sent*, not *accepted*: the hub's page
    /// re-renders rather than reporting a status, and a node acknowledges
    /// nothing, so this is provisional until the network shows the spot back.
    case sent(Date)
    /// Seen back from the network — the board's own list, the node's echo.
    /// The only real confirmation.
    case confirmed
    case failed(String)

    var isSettled: Bool { self != .sending }

    var failure: String? {
        if case .failed(let why) = self { return why }
        return nil
    }
}
```

In `HubSelfSpot.swift`: replace the body of `formattedFrequency` with `SpotFrequency.text(kHz: kHz)`; make `duplicateWindow` `SpotRepeat.window`; make `isDuplicate` return `SpotRepeat.isRepeat(fields, of: previous, lastSentAt: lastSentAt, now: now)`.

In `HubSpotClient.swift`: delete the nested `enum SendState`; declare
```swift
    private(set) var sendState: SpotSendState = .idle {
        didSet { onSendStateChange?(sendState) }
    }
    /// The dispatcher's window on the send — every change, including the
    /// confirmation a later poll delivers.
    var onSendStateChange: ((SpotSendState) -> Void)?
```

- [ ] **Step 4: Run the new tests plus `HubSelfSpotTests`** — expected PASS.
- [ ] **Step 5: Commit** — `refactor: lift SpotFrequency, SpotRepeat, SpotSendState out of the hub code`.

---

### Task 2: `SpotNetwork` and `SpotNetworkAvailability`

**Files:** create `Sources/Core/Spotting/SpotNetwork.swift`, `Sources/Core/Spotting/SpotNetworkAvailability.swift`; tests `Tests/Core/SpotNetworkTests.swift`, `Tests/Core/SpotNetworkAvailabilityTests.swift`.

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

final class SpotNetworkTests: XCTestCase {
    func testTheSheetOpensWithTheOfferedNetworksTheOperatorKeptLastTime() {
        XCTAssertEqual(SpotNetwork.initialSelection(available: [.cluster, .hub], preferred: [.hub, .pota]), [.hub])
    }
    func testAPostMovesOnlyTheNetworksTheSheetOffered() {
        // POTA was not on offer (home weekend) — it keeps its bit for the next park.
        XCTAssertEqual(
            SpotNetwork.updatedPreference(preferred: [.cluster, .hub, .pota], available: [.cluster, .hub], selected: [.hub]),
            [.hub, .pota])
    }
    func testTickingAnOfferedNetworkRemembersIt() {
        XCTAssertEqual(
            SpotNetwork.updatedPreference(preferred: [.hub], available: [.cluster, .hub], selected: [.cluster, .hub]),
            [.cluster, .hub])
    }
    func testShortcutDigitsAreOneTwoThreeInListOrder() {
        XCTAssertEqual(SpotNetwork.allCases.map(\.shortcutDigit), ["1", "2", "3"])
    }
    func testRawValuesRoundTrip() {
        for n in SpotNetwork.allCases { XCTAssertEqual(SpotNetwork(rawValue: n.rawValue), n) }
    }
}
```

```swift
import XCTest
@testable import QSOPartyLogger

/// Which networks the sheet offers, and the reason given when one is not.
final class SpotNetworkAvailabilityTests: XCTestCase {
    private func context(
        clusterConnected: Bool = true, clusterHost: String = "dxc.wa9pie.net",
        clusterBlockedReason: String? = nil, hubHost: String? = "qsopartyhub.com",
        target: SpotNetworkAvailability.Target = .myself, myParks: [String] = ["US-0817"],
        draftPark: String = ""
    ) -> SpotNetworkAvailability.Context {
        .init(clusterConnected: clusterConnected, clusterHost: clusterHost,
              clusterBlockedReason: clusterBlockedReason, hubHost: hubHost,
              target: target, myParks: myParks, draftPark: draftPark)
    }

    func testAConnectedClusterIsOfferedByHost() {
        XCTAssertEqual(SpotNetworkAvailability.availability(of: .cluster, in: context()), .available("dxc.wa9pie.net"))
    }
    func testADisconnectedClusterSaysHowToConnect() {
        XCTAssertEqual(SpotNetworkAvailability.availability(of: .cluster, in: context(clusterConnected: false)),
                       .unavailable(SpotNetworkAvailability.clusterNotConnected))
    }
    /// NON-ASSISTED cannot connect at all; the reason is the policy's own.
    func testABlockedClusterCarriesThePolicyReason() {
        XCTAssertEqual(SpotNetworkAvailability.availability(of: .cluster, in: context(clusterBlockedReason: "blocked")),
                       .unavailable("blocked"))
    }
    func testTheHubIsOfferedOnlyWhenThePartyHasAPage() {
        XCTAssertEqual(SpotNetworkAvailability.availability(of: .hub, in: context()), .available("qsopartyhub.com"))
        XCTAssertEqual(SpotNetworkAvailability.availability(of: .hub, in: context(hubHost: nil)),
                       .unavailable(SpotNetworkAvailability.noHubPage))
    }
    func testSpottingYourselfOnPotaNeedsAnActivation() {
        XCTAssertEqual(SpotNetworkAvailability.availability(of: .pota, in: context()), .available("pota.app · US-0817"))
        XCTAssertEqual(SpotNetworkAvailability.availability(of: .pota, in: context(myParks: [])),
                       .unavailable(SpotNetworkAvailability.noOwnPark))
    }
    func testSpottingAnotherStationOnPotaNeedsTheirPark() {
        XCTAssertEqual(SpotNetworkAvailability.availability(of: .pota, in: context(target: .station, draftPark: "")),
                       .unavailable(SpotNetworkAvailability.noTheirPark))
        XCTAssertEqual(SpotNetworkAvailability.availability(of: .pota, in: context(target: .station, draftPark: "us-3051")),
                       .available("pota.app"))
    }
    func testAvailableIsTheSetOfOfferedNetworks() {
        XCTAssertEqual(SpotNetworkAvailability.available(in: context(clusterConnected: false)), [.hub, .pota])
    }
    /// The sheet can open for another station with nothing on offer yet: the
    /// POTA row carries the park field, so typing one is the way in.
    func testTheSheetOpensForAStationEvenWithNothingOffered() {
        let bare = context(clusterConnected: false, hubHost: nil, target: .station, myParks: [])
        XCTAssertTrue(SpotNetworkAvailability.canOpenSheet(in: bare))
        let bareSelf = context(clusterConnected: false, hubHost: nil, target: .myself, myParks: [])
        XCTAssertFalse(SpotNetworkAvailability.canOpenSheet(in: bareSelf))
    }
}
```

- [ ] **Step 2: Run — expected build failure (types undefined).**
- [ ] **Step 3: Implement**

`SpotNetwork.swift`:

```swift
import Foundation

/// A place a spot can be *sent*. (`SpotSource` is where one *came from*; the
/// two lists differ — nothing is read from POTA, and `.local` is never a
/// destination.)
enum SpotNetwork: String, CaseIterable, Codable, Sendable, Identifiable {
    case cluster
    case hub
    case pota

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cluster: "DX cluster"
        case .hub: "QSO Party Hub"
        case .pota: "POTA"
        }
    }

    /// The word the receipt uses — short, because three of them share a line.
    var shortName: String {
        switch self {
        case .cluster: "Cluster"
        case .hub: "Hub"
        case .pota: "POTA"
        }
    }

    /// ⌘1, ⌘2, ⌘3 toggle the rows in the sheet, in list order.
    var shortcutDigit: Character {
        switch self {
        case .cluster: "1"
        case .hub: "2"
        case .pota: "3"
        }
    }

    /// What the sheet opens ticked: whatever is on offer that the operator
    /// kept ticked last time.
    static func initialSelection(available: Set<SpotNetwork>, preferred: Set<SpotNetwork>) -> Set<SpotNetwork> {
        available.intersection(preferred)
    }

    /// The remembered choice after a post. Only the networks the sheet
    /// actually offered move; one that was unavailable keeps its old bit, so
    /// a home weekend never un-ticks POTA for the next park.
    static func updatedPreference(
        preferred: Set<SpotNetwork>, available: Set<SpotNetwork>, selected: Set<SpotNetwork>
    ) -> Set<SpotNetwork> {
        preferred.subtracting(available).union(selected.intersection(available))
    }
}
```

`SpotNetworkAvailability.swift`:

```swift
import Foundation

/// Which networks the spot sheet offers right now, and — when one is not on
/// offer — the thing to change, named. Pure, so every reason is assertable
/// and no view decides policy.
enum SpotNetworkAvailability {

    enum Availability: Equatable, Sendable {
        /// On offer, with where it goes — the host the operator recognises.
        case available(String)
        /// Not on offer, and why.
        case unavailable(String)

        var isAvailable: Bool {
            if case .available = self { return true }
            return false
        }
        var text: String {
            switch self {
            case .available(let where): where
            case .unavailable(let why): why
            }
        }
    }

    /// Who the spot is for — the two cases `SpotCommand` already draws.
    enum Target: Equatable, Sendable {
        case myself
        case station
    }

    struct Context: Equatable, Sendable {
        var clusterConnected: Bool
        var clusterHost: String
        /// The spotting policy's reason when the declared category forbids a
        /// cluster at all; `nil` when it does not. Passed in rather than read,
        /// so this file owes nothing to the UI layer that owns the policy.
        var clusterBlockedReason: String?
        /// The hub's host when the party has a page there; `nil` when not.
        var hubHost: String?
        var target: Target
        var myParks: [String]
        /// The park reference in the draft — for another station, the only
        /// way POTA becomes available is the operator typing one.
        var draftPark: String
    }

    static let clusterNotConnected = "Not connected — Spots ▸ Connect"
    static let noHubPage = "This party has no page on qsopartyhub.com"
    static let noOwnPark = "Set your park in Contest Setup to spot yourself on POTA"
    static let noTheirPark = "Enter their park to spot them on POTA"
    static let potaHost = "pota.app"

    static func availability(of network: SpotNetwork, in context: Context) -> Availability {
        switch network {
        case .cluster:
            if let reason = context.clusterBlockedReason { return .unavailable(reason) }
            return context.clusterConnected
                ? .available(context.clusterHost.trimmingCharacters(in: .whitespaces))
                : .unavailable(clusterNotConnected)
        case .hub:
            return context.hubHost.map { .available($0) } ?? .unavailable(noHubPage)
        case .pota:
            switch context.target {
            case .myself:
                guard let park = context.myParks.first else { return .unavailable(noOwnPark) }
                return .available("\(potaHost) · \(park)")
            case .station:
                return PotaSpot.reference(from: context.draftPark) != nil
                    ? .available(potaHost) : .unavailable(noTheirPark)
            }
        }
    }

    static func available(in context: Context) -> Set<SpotNetwork> {
        Set(SpotNetwork.allCases.filter { availability(of: $0, in: context).isAvailable })
    }

    /// Whether ⇧⌘S has anywhere to go. For another station the sheet opens
    /// even with nothing on offer yet, because its POTA row carries the park
    /// field and typing one is the way in.
    static func canOpenSheet(in context: Context) -> Bool {
        context.target == .station || !available(in: context).isEmpty
    }
}
```

(`PotaSpot.reference(from:)` arrives in Task 3 — implement Task 3's `PotaSpot` before running this task's tests, or run both tasks' tests together.)

- [ ] **Step 4: Run both suites — PASS.**
- [ ] **Step 5: Commit with Task 3.**

---

### Task 3: `ClusterSpot` and `PotaSpot`

**Files:** create `Sources/Core/Spotting/ClusterSpot.swift`, `Sources/Core/Spotting/PotaSpot.swift`, `Tests/Fixtures/pota_spots_sample.json`; tests `Tests/Core/ClusterSpotTests.swift`, `Tests/Core/PotaSpotTests.swift`; docs `docs/research/dxcluster-dx-command.md`, `docs/research/pota/SOURCES.md` (append).

- [ ] **Step 1: Failing tests**

`ClusterSpotTests.swift`:

```swift
import XCTest
@testable import QSOPartyLogger

/// The `DX` command as DXSpider and AR-Cluster both take it — frequency
/// first, in kilohertz, remarks after the call. Sources banked in
/// docs/research/dxcluster-dx-command.md.
final class ClusterSpotTests: XCTestCase {
    private func fields(call: String = "KE5CW", kHz: Double = 7047, remarks: String = "") -> ClusterSpot.Fields {
        .init(call: call, frequencyKHz: kHz, remarks: remarks)
    }

    func testTheCommandIsFrequencyThenCallThenRemarks() {
        XCTAssertEqual(ClusterSpot.command(fields(remarks: "AL-QSO-PARTY MDSN")), "DX 7047 KE5CW AL-QSO-PARTY MDSN")
    }
    func testNoRemarksMeansNoTrailingSpace() {
        XCTAssertEqual(ClusterSpot.command(fields()), "DX 7047 KE5CW")
    }
    func testTheCallGoesOutUpperCasedAndTrimmed() {
        XCTAssertEqual(ClusterSpot.command(fields(call: " ke5cw ")), "DX 7047 KE5CW")
    }
    func testFractionalKilohertzKeepTheirDecimals() {
        XCTAssertEqual(ClusterSpot.command(fields(kHz: 14045.25)), "DX 14045.25 KE5CW")
    }
    /// A newline would end the command early and send the rest as a second one.
    func testRemarksAreOneLineSingleSpacedAndPrintable() {
        XCTAssertEqual(ClusterSpot.sanitize("MDSN\r\nsh/dx\t  30 \u{7}bell"), "MDSN sh/dx 30 bell")
    }
    func testRemarksAreContestThenCountyThenComment() {
        XCTAssertEqual(ClusterSpot.remarks(contest: "AL-QSO-PARTY", county: "MDSN/LIME", comment: "mobile"),
                       "AL-QSO-PARTY MDSN/LIME mobile")
        XCTAssertEqual(ClusterSpot.remarks(contest: "NAQP-CW", county: nil, comment: ""), "NAQP-CW")
    }
    func testValidationNeedsACallAndAFrequency() {
        XCTAssertEqual(ClusterSpot.validate(fields(call: " ")), .missingCall)
        XCTAssertEqual(ClusterSpot.validate(fields(kHz: 0)), .missingFrequency)
        XCTAssertNil(ClusterSpot.validate(fields()))
    }

    // MARK: Echo — the node's "proof of receipt"

    private func spot(call: String = "KE5CW", spotter: String = "KE5CW", kHz: Double = 7047.0) -> Spot {
        Spot(call: call, freqKHz: kHz, spotter: spotter, comment: "", receivedAt: Date())
    }
    func testOurOwnSpotBackFromTheNodeIsAnEcho() {
        XCTAssertTrue(ClusterSpot.isEcho(spot(), of: fields(), poster: "ke5cw"))
    }
    func testAnotherSpotterOrCallIsNotOurEcho() {
        XCTAssertFalse(ClusterSpot.isEcho(spot(spotter: "N4RT"), of: fields(), poster: "KE5CW"))
        XCTAssertFalse(ClusterSpot.isEcho(spot(call: "N4RT"), of: fields(), poster: "KE5CW"))
    }
    func testTheEchoMayBeRoundedButNotMoved() {
        XCTAssertTrue(ClusterSpot.isEcho(spot(kHz: 7047.2), of: fields(kHz: 7047.25), poster: "KE5CW"))
        XCTAssertFalse(ClusterSpot.isEcho(spot(kHz: 7048), of: fields(), poster: "KE5CW"))
    }
}
```

`PotaSpotTests.swift`:

```swift
import XCTest
@testable import QSOPartyLogger

/// The spot pota.app's own "Add Spot" form posts, rule for rule. Sources
/// banked in docs/research/pota/SOURCES.md.
final class PotaSpotTests: XCTestCase {
    private func fields(activator: String = "KE5CW", spotter: String = "KE5CW", kHz: Double = 7047,
                        reference: String = "US-0817", mode: String = "CW", comments: String = "") -> PotaSpot.Fields {
        .init(activator: activator, spotter: spotter, frequencyKHz: kHz, reference: reference, mode: mode, comments: comments)
    }

    // MARK: The form's own rules

    func testCallsignsTheFormAccepts() {
        for call in ["KE5CW", "ke5cw", "W1AW/M", "VE3/KE5CW", "K5D", "4U1UN", "9A1A"] {
            XCTAssertTrue(PotaSpot.isValidCallsign(call), call)
        }
        for call in ["", "KE5CW/", "/KE5CW", "K E5CW", "KECW", "KE5CW/MOBILE", "KE5CW-#"] {
            XCTAssertFalse(PotaSpot.isValidCallsign(call), call)
        }
    }
    func testReferencesTheFormAccepts() {
        XCTAssertEqual(PotaSpot.reference(from: " us-0817 "), "US-0817")
        XCTAssertEqual(PotaSpot.reference(from: "K-10000"), "K-10000")
        XCTAssertEqual(PotaSpot.reference(from: "K-TEST"), "K-TEST")
        // The spot page's regex has no room for a subdivision — it comes off.
        XCTAssertEqual(PotaSpot.reference(from: "K-4562@US-CA"), "K-4562")
        for bad in ["", "US0817", "US-817", "US-123456", "USA-0817", "US-08I7"] {
            XCTAssertNil(PotaSpot.reference(from: bad), bad)
        }
    }
    func testValidationSpeaksInTheFormsTerms() {
        XCTAssertNil(PotaSpot.validate(fields()))
        XCTAssertEqual(PotaSpot.validate(fields(activator: "")), .missingActivator)
        XCTAssertEqual(PotaSpot.validate(fields(spotter: " ")), .missingSpotter)
        XCTAssertEqual(PotaSpot.validate(fields(activator: "KE5CW/MOBILE")), .badCallsign("KE5CW/MOBILE"))
        XCTAssertEqual(PotaSpot.validate(fields(reference: "")), .missingReference)
        XCTAssertEqual(PotaSpot.validate(fields(reference: "USA-0817")), .badReference("USA-0817"))
        XCTAssertEqual(PotaSpot.validate(fields(kHz: 999)), .frequencyNotKHz)
        XCTAssertEqual(PotaSpot.Problem.badReference("X").errorDescription,
                       "X isn't a reference pota.app accepts — they look like US-0817.")
    }

    // MARK: Wire

    /// Byte for byte: sorted keys, kHz as text, our own name as the source.
    func testTheJSONBodyIsTheFormsShape() throws {
        let data = try PotaSpot.jsonBody(fields(kHz: 14045.25, mode: "SSB", comments: "QSO party"))
        XCTAssertEqual(String(decoding: data, as: UTF8.self),
            #"{"activator":"KE5CW","comments":"QSO party","frequency":"14045.25","mode":"SSB","reference":"US-0817","source":"QSOPartyLogger","spotter":"KE5CW"}"#)
    }
    func testTheBodyNormalizesCallsAndTheReference() throws {
        let data = try PotaSpot.jsonBody(fields(activator: " ke5cw", spotter: "ke5cw ", reference: "k-4562@us-ca"))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(#""activator":"KE5CW""#), text)
        XCTAssertTrue(text.contains(#""spotter":"KE5CW""#), text)
        XCTAssertTrue(text.contains(#""reference":"K-4562""#), text)
    }

    // MARK: The board's answer

    private func board() throws -> [PotaSpot.BoardSpot] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "pota_spots_sample", withExtension: "json"))
        return try XCTUnwrap(PotaSpot.board(from: try Data(contentsOf: url)))
    }
    func testTheBoardParsesFromTheLivePayloadShape() throws {
        let rows = try board()
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows.first?.activator, "W8EKM")
        XCTAssertEqual(rows.first?.reference, "US-6653")
        XCTAssertEqual(rows.first?.source, "Web")
    }
    func testOurSpotIsFoundByActivatorAndReference() throws {
        let rows = try board()
        XCTAssertTrue(PotaSpot.contains(fields(activator: "n4gbn", reference: "us-13340"), in: rows))
        XCTAssertFalse(PotaSpot.contains(fields(activator: "N4GBN", reference: "US-0001"), in: rows))
    }
    func testANonArrayBodyIsNotABoard() {
        XCTAssertNil(PotaSpot.board(from: Data("Invalid spot".utf8)))
        XCTAssertNil(PotaSpot.board(from: Data("{\"a\":1}".utf8)))
    }
    func testFailureTextIsTheServersOwnLineOrTheStatus() {
        XCTAssertEqual(PotaSpot.failureText(status: 400, body: Data("Invalid callsign\n".utf8)),
                       "pota.app refused the spot: Invalid callsign")
        XCTAssertEqual(PotaSpot.failureText(status: 502, body: Data("<html><body>Bad gateway".utf8)),
                       "pota.app refused the spot (HTTP 502).")
        XCTAssertEqual(PotaSpot.failureText(status: 500, body: Data()), "pota.app refused the spot (HTTP 500).")
    }
}
```

`Tests/Fixtures/pota_spots_sample.json` — five entries copied verbatim from `GET https://api.pota.app/spot/activator` on 2026-08-15 16:05Z (W8EKM/US-6653, K1SN/US-0016, KQ4TAX/US-1044, N4GBN/US-13340 with `"source": "HAMRS Pro/2.52.0"`, and one RBN row).

- [ ] **Step 2: Run — build failure.**
- [ ] **Step 3: Implement**

`ClusterSpot.swift`:

```swift
import Foundation

/// A spot for a DX cluster node — the `DX` command as both node families
/// take it. DXSpider User Manual v1.51: `dx (frequency) (callsign)
/// (remarks)`, "frequency is in kilohertz"; AR-Cluster: `DX frequency
/// callsign misc-info`, "misc-info should be kept brief". Frequency first is
/// the order both accept. Sources: docs/research/dxcluster-dx-command.md.
///
/// Pure. It builds and checks the command and sends nothing; `SpotClient`
/// writes it, and the node's echo — "The callout will also be sent to you as
/// proof of receipt" — is the confirmation.
enum ClusterSpot {

    struct Fields: Equatable, Sendable {
        var call: String
        var frequencyKHz: Double
        var remarks: String
    }

    enum Problem: Equatable, LocalizedError {
        case missingCall
        case missingFrequency

        var errorDescription: String? {
            switch self {
            case .missingCall: "Enter the call you're spotting."
            case .missingFrequency: "Enter the frequency — the node needs one in kilohertz."
            }
        }
    }

    static func validate(_ fields: Fields) -> Problem? {
        guard !fields.call.trimmingCharacters(in: .whitespaces).isEmpty else { return .missingCall }
        guard fields.frequencyKHz > 0 else { return .missingFrequency }
        return nil
    }

    /// `DX <kHz> <CALL> <remarks>` — one line, exactly what goes down the wire
    /// (the transport adds the CRLF).
    static func command(_ fields: Fields) -> String {
        var parts = [
            "DX",
            SpotFrequency.text(kHz: fields.frequencyKHz),
            fields.call.trimmingCharacters(in: .whitespaces).uppercased(),
        ]
        let remarks = sanitize(fields.remarks)
        if !remarks.isEmpty { parts.append(remarks) }
        return parts.joined(separator: " ")
    }

    /// The remarks for a spot from this log: the party's Cabrillo contest
    /// name first — the sponsor's own identifier, and the one party-neutral
    /// tag there is, so a reader outside the party knows what the spot is —
    /// then the county, because a cluster has no county field of its own,
    /// then whatever the operator typed. Each part optional.
    static func remarks(contest: String?, county: String?, comment: String) -> String {
        sanitize([contest, county, comment].compactMap { $0 }.joined(separator: " "))
    }

    /// One line, single-spaced, printable. A CR or LF would end the command
    /// early and send the rest as a second one; control characters have no
    /// place on the air. Tabs and runs of spaces collapse to one.
    static func sanitize(_ text: String) -> String {
        text.split(whereSeparator: { character in
            character.isWhitespace || character.isNewline
                || (character.asciiValue.map { $0 < 32 || $0 == 127 } ?? false)
        })
        .joined(separator: " ")
    }

    /// Whether an incoming spot is the node handing this one back — ours by
    /// spotter and call, at the frequency we gave within half a kilohertz
    /// (nodes print to 100 Hz).
    static func isEcho(_ spot: Spot, of fields: Fields, poster: String) -> Bool {
        spot.spotter.uppercased() == poster.trimmingCharacters(in: .whitespaces).uppercased()
            && spot.call.uppercased() == fields.call.trimmingCharacters(in: .whitespaces).uppercased()
            && abs(spot.freqKHz - fields.frequencyKHz) < 0.5
    }
}
```

`PotaSpot.swift`:

```swift
import Foundation

/// A spot for pota.app, built the way the site's own "Add Spot" form builds
/// one. The contract is the form's code (`SpotForm` in pota.app's bundle,
/// fetched 2026-08-15 — docs/research/pota/SOURCES.md): a JSON POST of
/// `activator, spotter, frequency, reference, mode, source, comments` to
/// `https://api.pota.app/spot`, no authentication, the response being the
/// board's current spot list. Every rule below is quoted from that form.
///
/// Pure: it builds and checks the payload and posts nothing.
enum PotaSpot {

    struct Fields: Equatable, Sendable {
        var activator: String
        var spotter: String
        var frequencyKHz: Double
        var reference: String
        var mode: String
        var comments: String
    }

    enum Problem: Equatable, LocalizedError {
        case missingActivator
        case missingSpotter
        case badCallsign(String)
        case missingReference
        case badReference(String)
        case frequencyNotKHz

        var errorDescription: String? {
            switch self {
            case .missingActivator: "Enter the call you're spotting."
            case .missingSpotter: "Enter your own call — pota.app records who spotted."
            case .badCallsign(let call): "\(call) isn't a callsign pota.app accepts."
            case .missingReference: "Enter the park reference."
            case .badReference(let reference):
                "\(reference) isn't a reference pota.app accepts — they look like US-0817."
            case .frequencyNotKHz: "pota.app takes the frequency in kilohertz, above 1000."
            }
        }
    }

    /// What the board records as the origin — other loggers post under their
    /// own names (`Ham2K Portable Logger`, `HAMRS Pro/2.52.0` on the live
    /// board), and so does this one.
    static let source = "QSOPartyLogger"
    static let postURL = URL(string: "https://api.pota.app/spot")!
    /// The board, for confirming a send the response did not confirm.
    static let boardURL = URL(string: "https://api.pota.app/spot/activator")!

    /// The form's `validCallsignRegex`, verbatim.
    private static let callsignPattern = try! NSRegularExpression(
        pattern: #"^(?:[A-Z\d]{1,4}/)?[A-Z\d]{1,3}\d[A-Z\d]*(?:/[A-Z\d]{1,4})?$"#,
        options: [.caseInsensitive])
    /// The form's `validReferenceRegex`, verbatim.
    private static let referencePattern = try! NSRegularExpression(
        pattern: #"^[A-Z0-9]{1,2}-[0-9]{4,5}$"#)

    static func isValidCallsign(_ call: String) -> Bool {
        matches(callsignPattern, call)
    }

    /// The reference as the form accepts it: through the ADIF grammar first
    /// (`PotaRef.normalize` — trim, uppercase, shape), with any `@subdivision`
    /// dropped because the spot page's regex has no room for one, then the
    /// page's own rule — or its literal `K-TEST`. `nil` when nothing usable.
    static func reference(from raw: String) -> String? {
        let token = raw.trimmingCharacters(in: .whitespaces).uppercased()
        if token == "K-TEST" { return token }
        guard let normalized = PotaRef.normalize(token),
              let park = normalized.split(separator: "@").first.map(String.init),
              matches(referencePattern, park) else { return nil }
        return park
    }

    static func validate(_ fields: Fields) -> Problem? {
        let activator = fields.activator.trimmingCharacters(in: .whitespaces)
        let spotter = fields.spotter.trimmingCharacters(in: .whitespaces)
        guard !activator.isEmpty else { return .missingActivator }
        guard !spotter.isEmpty else { return .missingSpotter }
        guard isValidCallsign(activator) else { return .badCallsign(activator.uppercased()) }
        guard isValidCallsign(spotter) else { return .badCallsign(spotter.uppercased()) }
        let rawReference = fields.reference.trimmingCharacters(in: .whitespaces)
        guard !rawReference.isEmpty else { return .missingReference }
        guard reference(from: rawReference) != nil else { return .badReference(rawReference.uppercased()) }
        // "Frequency in kHz (> 1000)" — the form's third frequency rule.
        guard fields.frequencyKHz > 1000 else { return .frequencyNotKHz }
        return nil
    }

    // MARK: Wire

    private struct Body: Encodable {
        let activator, spotter, frequency, reference, mode, source, comments: String
    }

    /// The JSON the form posts, keys sorted so the bytes are stable.
    static func jsonBody(_ fields: Fields) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Body(
            activator: fields.activator.trimmingCharacters(in: .whitespaces).uppercased(),
            spotter: fields.spotter.trimmingCharacters(in: .whitespaces).uppercased(),
            frequency: SpotFrequency.text(kHz: fields.frequencyKHz),
            reference: reference(from: fields.reference) ?? fields.reference.trimmingCharacters(in: .whitespaces).uppercased(),
            mode: fields.mode.trimmingCharacters(in: .whitespaces).uppercased(),
            source: source,
            comments: fields.comments.trimmingCharacters(in: .whitespaces)
        ))
    }

    // MARK: The board

    /// One row of the board, read leniently — only what confirmation needs.
    struct BoardSpot: Decodable, Equatable, Sendable {
        var activator: String
        var reference: String
        var spotter: String?
        var frequency: String?
        var mode: String?
        var spotTime: String?
        var source: String?
    }

    /// The board as the API returns it (and as the POST answers). `nil` when
    /// the body is not that list — an error text, an HTML page.
    static func board(from data: Data) -> [BoardSpot]? {
        try? JSONDecoder().decode([BoardSpot].self, from: data)
    }

    /// Whether the board shows this spot: same activator, same reference.
    static func contains(_ fields: Fields, in board: [BoardSpot]) -> Bool {
        let activator = fields.activator.trimmingCharacters(in: .whitespaces).uppercased()
        guard let reference = reference(from: fields.reference) else { return false }
        return board.contains { $0.activator.uppercased() == activator && $0.reference.uppercased() == reference }
    }

    /// The failure the operator reads: the server's own first line when it
    /// sent a readable one (the form shows `e.response.data` as-is), else the
    /// status. HTML is not readable.
    static func failureText(status: Int, body: Data) -> String {
        let text = String(decoding: body, as: UTF8.self)
        let line = text.split(whereSeparator: \.isNewline).first.map {
            $0.trimmingCharacters(in: .whitespaces)
        } ?? ""
        if line.isEmpty || line.hasPrefix("<") || line.count > 120 {
            return "pota.app refused the spot (HTTP \(status))."
        }
        return "pota.app refused the spot: \(line)"
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}
```

- [ ] **Step 4: Run `ClusterSpotTests`, `PotaSpotTests`, `SpotNetworkTests`, `SpotNetworkAvailabilityTests` — PASS.**
- [ ] **Step 5: Bank the sources** — `docs/research/dxcluster-dx-command.md` (DXSpider manual quotes, wiki command reference, AR-Cluster quotes, fetch dates, what the app bakes in) and append a "POTA spot API" section to `docs/research/pota/SOURCES.md` (the SpotForm code quotes, regexes, live-board observations, what the app bakes in). Add both to `docs/PROVENANCE.md`.
- [ ] **Step 6: Commit** — `spotting: SpotNetwork, availability, ClusterSpot, PotaSpot — the pure core, sources banked`.

---

### Task 4: `SpotDraft` and `SpotReceipt`

**Files:** create `Sources/Core/Spotting/SpotDraft.swift`, `Sources/Core/Spotting/SpotReceipt.swift`; tests `Tests/Core/SpotDraftTests.swift`, `Tests/Core/SpotReceiptTests.swift`.

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

/// The sheet's one model, and what each network gets from it.
final class SpotDraftTests: XCTestCase {
    private var alqp: PartyDefinition { PartyCatalog.party(id: "alqp")! }
    private func draft(networks: Set<SpotNetwork> = [.cluster, .hub, .pota]) -> SpotDraft {
        SpotDraft(station: "KE5CW", frequencyKHz: 7047, county: "MDSN", comment: "mobile",
                  poster: "KE5CW", park: "US-0817", mode: "CW", networks: networks)
    }

    func testEachNetworkGetsItsOwnPayload() {
        let d = draft()
        XCTAssertEqual(d.hubFields, HubSelfSpot.Fields(station: "KE5CW", frequencyKHz: 7047, county: "MDSN", comment: "mobile", poster: "KE5CW"))
        XCTAssertEqual(d.clusterFields(party: alqp), ClusterSpot.Fields(call: "KE5CW", frequencyKHz: 7047, remarks: "AL-QSO-PARTY MDSN mobile"))
        XCTAssertEqual(d.potaFields, PotaSpot.Fields(activator: "KE5CW", spotter: "KE5CW", frequencyKHz: 7047, reference: "US-0817", mode: "CW", comments: "mobile"))
    }
    func testProblemsAreKeyedToTheNetworkTheyBelongTo() {
        var d = draft()
        d.county = "ZZZZ"      // hub: not a county of this party; cluster and POTA don't care
        d.park = "USA-0817"    // POTA: not a reference the form takes
        let problems = d.problems(party: alqp)
        XCTAssertEqual(Set(problems.keys), [.hub, .pota])
        XCTAssertEqual(problems[.hub], "ZZZZ isn't a county in this party.")
        XCTAssertNil(d.problem(for: .cluster, party: alqp))
    }
    func testOnlyTickedNetworksAreJudged() {
        var d = draft(networks: [.cluster])
        d.park = "bad"
        XCTAssertTrue(d.problems(party: alqp).isEmpty)
        XCTAssertTrue(d.canPost(party: alqp))
    }
    func testPostNeedsSomethingTickedAndNothingTickedBroken() {
        XCTAssertFalse(draft(networks: []).canPost(party: alqp))
        var d = draft(networks: [.pota]); d.park = ""
        XCTAssertFalse(d.canPost(party: alqp))
        XCTAssertTrue(draft().canPost(party: alqp))
    }
    func testPreviewsShowExactlyWhatGoesOut() {
        let d = draft()
        XCTAssertEqual(d.preview(for: .cluster, party: alqp), "DX 7047 KE5CW AL-QSO-PARTY MDSN mobile")
        XCTAssertEqual(d.preview(for: .hub, party: alqp), "KE5CW 7047 MDSN mobile")
        XCTAssertEqual(d.preview(for: .pota, party: alqp), "US-0817 · CW · mobile")
    }
    func testSendingKeepsOnlyOfferedNetworks() {
        XCTAssertEqual(draft().sending(available: [.hub]).networks, [.hub])
    }
}
```

```swift
import XCTest
@testable import QSOPartyLogger

/// What the operator is told after Post, and for how long.
final class SpotReceiptTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func receipt(_ states: [SpotNetwork: SpotSendState]) -> SpotReceipt {
        SpotReceipt(station: "KE5CW", frequencyKHz: 7047, states: states, changedAt: t0)
    }

    func testLinesNameTheNetworkAndItsState() {
        let r = receipt([.cluster: .confirmed, .hub: .sent(t0), .pota: .failed("pota.app refused the spot (HTTP 500).")])
        XCTAssertEqual(r.line(for: .cluster), "Cluster — echoed by the node")
        XCTAssertEqual(r.line(for: .hub), "Hub — sent, watching the board")
        XCTAssertEqual(r.line(for: .pota), "POTA — pota.app refused the spot (HTTP 500).")
        XCTAssertEqual(receipt([.hub: .confirmed]).line(for: .hub), "Hub — on the board")
        XCTAssertEqual(receipt([.pota: .confirmed]).line(for: .pota), "POTA — on pota.app")
        XCTAssertEqual(receipt([.pota: .sent(t0)]).line(for: .pota), "POTA — sent, watching pota.app")
        XCTAssertEqual(receipt([.cluster: .sent(t0)]).line(for: .cluster), "Cluster — sent to the node")
        XCTAssertEqual(receipt([.cluster: .sending]).line(for: .cluster), "Cluster — sending…")
    }
    func testTheSummaryListsNetworksInOrder() {
        XCTAssertEqual(receipt([.pota: .confirmed, .cluster: .confirmed]).summary,
                       "Cluster — echoed by the node · POTA — on pota.app")
        XCTAssertEqual(receipt([:]).title, "KE5CW 7047")
    }
    func testTintIsBadOnAnyFailureGoodWhenAllConfirmedElsePending() {
        XCTAssertEqual(receipt([.hub: .confirmed, .pota: .failed("x")]).tint, .bad)
        XCTAssertEqual(receipt([.hub: .confirmed, .pota: .confirmed]).tint, .good)
        XCTAssertEqual(receipt([.hub: .confirmed, .pota: .sent(t0)]).tint, .pending)
        XCTAssertEqual(receipt([.hub: .sending]).tint, .pending)
    }
    func testVisibleForTwelveSecondsAfterAChangeWhenNothingFailed() {
        let r = receipt([.hub: .confirmed])
        XCTAssertTrue(r.isVisible(now: t0.addingTimeInterval(11.9)))
        XCTAssertFalse(r.isVisible(now: t0.addingTimeInterval(12)))
    }
    func testVisibleForAMinuteWhenSomethingFailed() {
        let r = receipt([.hub: .failed("x")])
        XCTAssertTrue(r.isVisible(now: t0.addingTimeInterval(59)))
        XCTAssertFalse(r.isVisible(now: t0.addingTimeInterval(60)))
    }
    func testALateChangeReShowsIt() {
        var r = receipt([.hub: .sent(t0)])
        XCTAssertFalse(r.isVisible(now: t0.addingTimeInterval(100)))
        r.set(.confirmed, for: .hub, at: t0.addingTimeInterval(100))
        XCTAssertTrue(r.isVisible(now: t0.addingTimeInterval(101)))
    }
    func testDismissHidesUntilTheNextChange() {
        var r = receipt([.hub: .sent(t0)])
        r.dismiss(at: t0.addingTimeInterval(1))
        XCTAssertFalse(r.isVisible(now: t0.addingTimeInterval(2)))
        r.set(.failed("gone"), for: .hub, at: t0.addingTimeInterval(3))
        XCTAssertTrue(r.isVisible(now: t0.addingTimeInterval(4)))
    }
    func testOnlyNetworksInTheReceiptTakeUpdatesAndUnchangedStatesDoNotRearm() {
        var r = receipt([.hub: .sent(t0)])
        r.set(.confirmed, for: .pota, at: t0.addingTimeInterval(5))
        XCTAssertNil(r.states[.pota]); XCTAssertEqual(r.changedAt, t0)
        r.set(.sent(t0), for: .hub, at: t0.addingTimeInterval(5))
        XCTAssertEqual(r.changedAt, t0)
    }
    func testFailedNetworksAndSettlement() {
        let r = receipt([.cluster: .sent(t0), .hub: .failed("x"), .pota: .sending])
        XCTAssertEqual(r.failedNetworks, [.hub])
        XCTAssertFalse(r.isSettled)
        XCTAssertTrue(receipt([.cluster: .sent(t0)]).isSettled)
    }
}
```

- [ ] **Step 2: Run — build failure.**
- [ ] **Step 3: Implement**

`SpotDraft.swift`:

```swift
import Foundation

/// What the spot sheet edits: one station, one frequency, and the pieces
/// each network wants — the party's county for the hub (and the cluster's
/// remarks), the park and mode for POTA — plus which networks are ticked.
/// Each network's own composer turns it into that network's payload, and
/// each network's own validator judges it, so a problem is shown under the
/// row it belongs to and never blocks another network.
struct SpotDraft: Equatable, Sendable {
    var station: String
    var frequencyKHz: Double
    /// The party's own county abbreviation(s), slash-joined for a line.
    var county: String?
    var comment: String
    var poster: String
    /// One POTA reference — the board takes one per spot.
    var park: String
    /// The ADIF mode POTA is told (`SSB`, `CW`, …).
    var mode: String
    var networks: Set<SpotNetwork>

    static let empty = SpotDraft(station: "", frequencyKHz: 0, county: nil, comment: "",
                                 poster: "", park: "", mode: "", networks: [])

    var hubFields: HubSelfSpot.Fields {
        HubSelfSpot.Fields(station: station, frequencyKHz: frequencyKHz, county: county,
                           comment: comment, poster: poster)
    }

    func clusterFields(party: PartyDefinition) -> ClusterSpot.Fields {
        ClusterSpot.Fields(
            call: station, frequencyKHz: frequencyKHz,
            remarks: ClusterSpot.remarks(contest: party.cabrilloContest, county: county, comment: comment))
    }

    var potaFields: PotaSpot.Fields {
        PotaSpot.Fields(activator: station, spotter: poster, frequencyKHz: frequencyKHz,
                        reference: park, mode: mode, comments: comment)
    }

    /// This network's objection to the draft, in its own words. Independent
    /// of whether the network is ticked.
    func problem(for network: SpotNetwork, party: PartyDefinition) -> String? {
        switch network {
        case .cluster: ClusterSpot.validate(clusterFields(party: party))?.errorDescription
        case .hub: HubSelfSpot.validate(hubFields, party: party)?.errorDescription
        case .pota: PotaSpot.validate(potaFields)?.errorDescription
        }
    }

    /// What stands between the draft and Post: the ticked networks' problems,
    /// each keyed to its network.
    func problems(party: PartyDefinition) -> [SpotNetwork: String] {
        var problems: [SpotNetwork: String] = [:]
        for network in networks {
            if let problem = problem(for: network, party: party) { problems[network] = problem }
        }
        return problems
    }

    /// Post is enabled only when something is ticked and nothing ticked has
    /// a problem — the operator fixes it or unticks it; nothing is skipped
    /// silently.
    func canPost(party: PartyDefinition) -> Bool {
        !networks.isEmpty && problems(party: party).isEmpty
    }

    /// Exactly what the network will carry, before it goes.
    func preview(for network: SpotNetwork, party: PartyDefinition) -> String {
        switch network {
        case .cluster:
            return ClusterSpot.command(clusterFields(party: party))
        case .hub:
            return [station.trimmingCharacters(in: .whitespaces).uppercased(),
                    SpotFrequency.text(kHz: frequencyKHz), county ?? "", comment]
                .filter { !$0.isEmpty }.joined(separator: " ")
        case .pota:
            return [PotaSpot.reference(from: park) ?? park.uppercased(), mode.uppercased(), comment]
                .filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    /// The draft as it goes to the dispatcher: a network that stopped being
    /// on offer while the sheet was open (the node dropped) is not sent to.
    func sending(available: Set<SpotNetwork>) -> SpotDraft {
        var copy = self
        copy.networks = networks.intersection(available)
        return copy
    }
}
```

`SpotReceipt.swift`:

```swift
import Foundation

/// What one Post became: a state per network, and how it reads. Pure —
/// the dispatcher writes it, the capsule in the station strip shows it.
struct SpotReceipt: Equatable, Sendable {
    var station: String
    var frequencyKHz: Double
    var states: [SpotNetwork: SpotSendState]
    /// When the latest state landed. Visibility runs from here.
    var changedAt: Date
    var dismissedAt: Date?

    enum Tint: Equatable, Sendable {
        /// Something still in flight, or sent and not yet shown back.
        case pending
        /// Every network showed the spot back.
        case good
        /// A network failed.
        case bad
    }

    /// Long enough to read; the consoles keep the record.
    static let quietWindow: TimeInterval = 12
    /// Long enough to read and act on.
    static let failureWindow: TimeInterval = 60

    init(station: String, frequencyKHz: Double, states: [SpotNetwork: SpotSendState],
         changedAt: Date, dismissedAt: Date? = nil) {
        self.station = station
        self.frequencyKHz = frequencyKHz
        self.states = states
        self.changedAt = changedAt
        self.dismissedAt = dismissedAt
    }

    /// The networks this send went to, in list order.
    var networks: [SpotNetwork] { SpotNetwork.allCases.filter { states[$0] != nil } }
    var failedNetworks: [SpotNetwork] { networks.filter { states[$0]?.failure != nil } }
    var isSettled: Bool { !states.values.contains(.sending) }

    var tint: Tint {
        if !failedNetworks.isEmpty { return .bad }
        if !states.isEmpty, states.values.allSatisfy({ $0 == .confirmed }) { return .good }
        return .pending
    }

    var title: String { "\(station) \(SpotFrequency.text(kHz: frequencyKHz))" }

    func line(for network: SpotNetwork) -> String {
        let name = network.shortName
        switch states[network] ?? .idle {
        case .idle: return "\(name) — waiting"
        case .sending: return "\(name) — sending…"
        case .sent:
            switch network {
            case .cluster: return "\(name) — sent to the node"
            case .hub: return "\(name) — sent, watching the board"
            case .pota: return "\(name) — sent, watching pota.app"
            }
        case .confirmed:
            switch network {
            case .cluster: return "\(name) — echoed by the node"
            case .hub: return "\(name) — on the board"
            case .pota: return "\(name) — on pota.app"
            }
        case .failed(let why): return "\(name) — \(why)"
        }
    }

    var summary: String { networks.map(line(for:)).joined(separator: " · ") }

    /// Shown from the last change for a quiet window, or a longer one when
    /// something failed; hidden by a dismissal until the next change.
    func isVisible(now: Date) -> Bool {
        if let dismissedAt, changedAt <= dismissedAt { return false }
        let window = failedNetworks.isEmpty ? Self.quietWindow : Self.failureWindow
        return now.timeIntervalSince(changedAt) < window
    }

    /// Only networks this send went to take updates, and an unchanged state
    /// does not re-arm the window.
    mutating func set(_ state: SpotSendState, for network: SpotNetwork, at now: Date) {
        guard let current = states[network], current != state else { return }
        states[network] = state
        changedAt = now
    }

    mutating func dismiss(at now: Date) { dismissedAt = now }
}
```

- [ ] **Step 4: Run both suites — PASS.**
- [ ] **Step 5: Commit** — `spotting: SpotDraft and SpotReceipt — one model for the sheet, one for the receipt`.

---

### Task 5: `PotaSpotClient`

**Files:** create `Sources/App/PotaSpotClient.swift`; test `Tests/App/PotaSpotClientTests.swift`.

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

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
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
    }

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func fields(reference: String = "US-0817") -> PotaSpot.Fields {
        .init(activator: "KE5CW", spotter: "KE5CW", frequencyKHz: 7047, reference: reference, mode: "CW", comments: "")
    }
    private func boardData(withOurs: Bool) -> Data {
        let ours = #"{"spotId":1,"activator":"KE5CW","frequency":"7047","mode":"CW","reference":"US-0817","spotter":"KE5CW","source":"QSOPartyLogger","spotTime":"2026-08-15T16:04:15"}"#
        let other = #"{"spotId":2,"activator":"W8EKM","frequency":"21320","mode":"SSB","reference":"US-6653","spotter":"W8EKM","source":"Web","spotTime":"2026-08-15T16:04:15"}"#
        return Data("[\(withOurs ? ours + "," : "")\(other)]".utf8)
    }
    private func client(_ poster: ScriptedPoster) -> PotaSpotClient {
        PotaSpotClient(poster: poster, confirmationDelays: [0.01, 0.02])
    }
    private func settle() async { try? await Task.sleep(nanoseconds: 100_000_000) }

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
    func testABoardThatShowsTheSpotConfirmsAtOnce() async {
        let poster = ScriptedPoster()
        poster.answers = [.success((boardData(withOurs: true), 200))]
        let c = client(poster)
        await c.post(fields(), now: t0)
        XCTAssertEqual(c.sendState, .confirmed)
        XCTAssertEqual(poster.requests.count, 1)
    }
    func testASendTheBoardDoesNotShowIsConfirmedByAFollowUp() async {
        let poster = ScriptedPoster()
        poster.answers = [.success((boardData(withOurs: false), 200)),
                          .success((boardData(withOurs: true), 200))]
        let c = client(poster)
        await c.post(fields(), now: t0)
        XCTAssertEqual(c.sendState, .sent(t0))
        await settle()
        XCTAssertEqual(c.sendState, .confirmed)
        XCTAssertEqual(poster.requests.last?.url, PotaSpot.boardURL)
        XCTAssertEqual(poster.requests.last?.httpMethod, "GET")
    }
    func testTwoMissedFollowUpsFail() async {
        let poster = ScriptedPoster()
        poster.answers = [.success((boardData(withOurs: false), 200)),
                          .success((boardData(withOurs: false), 200)),
                          .success((boardData(withOurs: false), 200))]
        let c = client(poster)
        await c.post(fields(), now: t0)
        await settle()
        XCTAssertEqual(c.sendState, .failed("The spot was sent but hasn't appeared on pota.app. It may not have been accepted — check the page before relying on it."))
    }
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
    func testStateChangesAreReported() async {
        let poster = ScriptedPoster()
        poster.answers = [.success((boardData(withOurs: true), 200))]
        let c = client(poster)
        var seen: [SpotSendState] = []
        c.onSendStateChange = { seen.append($0) }
        await c.post(fields(), now: t0)
        XCTAssertEqual(seen, [.sending, .confirmed])
    }
}
```

- [ ] **Step 2: Run — build failure.**
- [ ] **Step 3: Implement** `Sources/App/PotaSpotClient.swift`:

```swift
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
        config.httpAdditionalHeaders = ["User-Agent": "QSOPartyLogger/1.0 (+https://github.com/KE5CW) macOS"]
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

    init(poster: PotaSpotPosting = LivePotaSpotPoster(),
         confirmationDelays: [TimeInterval] = PotaSpotClient.confirmationDelays) {
        self.poster = poster
        self.confirmationDelays = confirmationDelays
    }

    private enum Refusal: Error { case server(status: Int, body: Data) }

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
        log("> spot \(fields.activator) \(SpotFrequency.text(kHz: fields.frequencyKHz)) \(fields.reference) \(fields.mode)")
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
            self.sendState = .failed("The spot was sent but hasn't appeared on pota.app. "
                + "It may not have been accepted — check the page before relying on it.")
            self.log("*** spot not seen on pota.app")
        }
    }

    private func boardShows(_ fields: PotaSpot.Fields) async -> Bool {
        var request = URLRequest(url: PotaSpot.boardURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, http) = try? await poster.send(request),
              (200..<300).contains(http.statusCode),
              let board = PotaSpot.board(from: data) else { return false }
        return PotaSpot.contains(fields, in: board)
    }

    private func log(_ line: String) {
        console.append(line)
        if console.count > Self.maxConsoleLines {
            console.removeFirst(console.count - Self.maxConsoleLines)
        }
    }
}
```

- [ ] **Step 4: Run `PotaSpotClientTests` — PASS.**
- [ ] **Step 5: Commit** — `spotting: PotaSpotClient — pota.app's own POST, confirmed by the board's list`.

---

### Task 6: `SpotDispatcher` and the `spotNetworks` setting

**Files:** create `Sources/App/SpotDispatcher.swift`; modify `Sources/App/AppSettings.swift`; tests `Tests/App/SpotDispatcherTests.swift`, append to `Tests/App/PreferenceIsolationTests.swift`-style suite a `SpotNetworkPreferenceTests` (in the dispatcher test file for brevity).

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

@MainActor
final class SpotDispatcherTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private var alqp: PartyDefinition { PartyCatalog.party(id: "alqp")! }

    final class Recorder {
        var clusterCommands: [String] = []
        var clusterConnected = true
        var hubPosts: [HubSelfSpot.Fields] = []
        var potaPosts: [PotaSpot.Fields] = []
    }
    private func dispatcher(_ r: Recorder) -> SpotDispatcher {
        SpotDispatcher(transports: .init(
            sendClusterCommand: { r.clusterCommands.append($0); return r.clusterConnected },
            postToHub: { fields, _ in r.hubPosts.append(fields) },
            postToPota: { r.potaPosts.append($0) }))
    }
    private func draft(_ networks: Set<SpotNetwork>) -> SpotDraft {
        SpotDraft(station: "KE5CW", frequencyKHz: 7047, county: "MDSN", comment: "", poster: "KE5CW",
                  park: "US-0817", mode: "CW", networks: networks)
    }

    func testOnlyTickedNetworksAreSentTo() {
        let r = Recorder(); let d = dispatcher(r)
        d.send(draft([.cluster, .pota]), party: alqp, now: t0)
        XCTAssertEqual(r.clusterCommands, ["DX 7047 KE5CW AL-QSO-PARTY MDSN"])
        XCTAssertTrue(r.hubPosts.isEmpty)
        XCTAssertEqual(r.potaPosts.count, 1)
        XCTAssertEqual(d.receipt?.networks, [.cluster, .pota])
        XCTAssertEqual(d.receipt?.states[.cluster], .sent(t0))
        XCTAssertEqual(d.receipt?.states[.pota], .sending)
    }
    func testAClusterWithNoSessionFails() {
        let r = Recorder(); r.clusterConnected = false
        let d = dispatcher(r)
        d.send(draft([.cluster]), party: alqp, now: t0)
        XCTAssertEqual(d.receipt?.states[.cluster], .failed("Cluster not connected."))
    }
    func testTheNodesEchoConfirmsTheClusterSpot() {
        let r = Recorder(); let d = dispatcher(r)
        d.send(draft([.cluster]), party: alqp, now: t0)
        d.noteIncomingSpot(Spot(call: "N4RT", freqKHz: 7047, spotter: "KE5CW", comment: "", receivedAt: t0), now: t0)
        XCTAssertEqual(d.receipt?.states[.cluster], .sent(t0))
        d.noteIncomingSpot(Spot(call: "KE5CW", freqKHz: 7047.0, spotter: "KE5CW", comment: "", receivedAt: t0), now: t0.addingTimeInterval(2))
        XCTAssertEqual(d.receipt?.states[.cluster], .confirmed)
        XCTAssertEqual(d.receipt?.changedAt, t0.addingTimeInterval(2))
    }
    func testClientStatesFlowIntoTheReceipt() {
        let r = Recorder(); let d = dispatcher(r)
        d.send(draft([.hub, .pota]), party: alqp, now: t0)
        d.update(.hub, state: .sent(t0), now: t0)
        d.update(.pota, state: .confirmed, now: t0)
        XCTAssertEqual(d.receipt?.states[.hub], .sent(t0))
        XCTAssertEqual(d.receipt?.states[.pota], .confirmed)
        // A network this send did not go to is ignored.
        d.update(.cluster, state: .confirmed, now: t0)
        XCTAssertNil(d.receipt?.states[.cluster])
    }
    func testAnIdenticalClusterSpotInsideFiveMinutesIsRefused() {
        let r = Recorder(); let d = dispatcher(r)
        d.send(draft([.cluster]), party: alqp, now: t0)
        d.send(draft([.cluster]), party: alqp, now: t0.addingTimeInterval(30))
        XCTAssertEqual(r.clusterCommands.count, 1)
        XCTAssertEqual(d.receipt?.states[.cluster], .failed("That spot just went out to the node — nothing has changed since."))
    }
    func testDismissHidesTheReceipt() {
        let r = Recorder(); let d = dispatcher(r)
        d.send(draft([.hub]), party: alqp, now: t0)
        d.dismiss(now: t0.addingTimeInterval(1))
        XCTAssertEqual(d.receipt?.isVisible(now: t0.addingTimeInterval(2)), false)
    }
    func testANewSendReplacesTheReceipt() {
        let r = Recorder(); let d = dispatcher(r)
        d.send(draft([.hub]), party: alqp, now: t0)
        d.send(draft([.pota]), party: alqp, now: t0.addingTimeInterval(400))
        XCTAssertEqual(d.receipt?.networks, [.pota])
    }
}

/// The remembered choice of networks.
final class SpotNetworkPreferenceTests: XCTestCase {
    func testDefaultsToEveryNetworkAndRoundTrips() {
        let suite = UserDefaults(suiteName: "SpotNetworkPreferenceTests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: suite)
        XCTAssertEqual(settings.spotNetworks, Set(SpotNetwork.allCases))
        settings.spotNetworks = [.hub]
        XCTAssertEqual(AppSettings(defaults: suite).spotNetworks, [.hub])
    }
}
```

- [ ] **Step 2: Run — build failure.**
- [ ] **Step 3: Implement**

`Sources/App/SpotDispatcher.swift`:

```swift
import Foundation
import Observation

/// The one place a `SpotDraft` becomes sends. Fans it out to every ticked
/// network through the transports it is given, and keeps the receipt — a
/// state per network — current as the clients report back and the node
/// echoes. Tests script the transports; nothing here touches TCP or HTTP.
@MainActor
@Observable
final class SpotDispatcher {

    struct Transports {
        /// Writes one command to the node. `false` when there is no session
        /// to write to.
        var sendClusterCommand: (String) -> Bool
        /// Fire-and-forget; the hub client reports through `update`.
        var postToHub: (HubSelfSpot.Fields, PartyDefinition) -> Void
        /// Fire-and-forget; the POTA client reports through `update`.
        var postToPota: (PotaSpot.Fields) -> Void
    }

    var transports: Transports
    private(set) var receipt: SpotReceipt?

    /// The cluster spot awaiting the node's echo, if any.
    private var pendingEcho: (fields: ClusterSpot.Fields, poster: String)?
    private var lastClusterSent: ClusterSpot.Fields?
    private var lastClusterSentAt: Date?

    init(transports: Transports) {
        self.transports = transports
    }

    /// The caller has confirmed the draft with the operator.
    func send(_ draft: SpotDraft, party: PartyDefinition, now: Date = Date()) {
        var states: [SpotNetwork: SpotSendState] = [:]
        for network in draft.networks { states[network] = .sending }
        receipt = SpotReceipt(
            station: draft.station.trimmingCharacters(in: .whitespaces).uppercased(),
            frequencyKHz: draft.frequencyKHz, states: states, changedAt: now)
        pendingEcho = nil

        if draft.networks.contains(.cluster) {
            let fields = draft.clusterFields(party: party)
            if SpotRepeat.isRepeat(fields, of: lastClusterSent, lastSentAt: lastClusterSentAt, now: now) {
                update(.cluster, state: .failed("That spot just went out to the node — nothing has changed since."), now: now)
            } else if transports.sendClusterCommand(ClusterSpot.command(fields)) {
                lastClusterSent = fields
                lastClusterSentAt = now
                pendingEcho = (fields, draft.poster)
                update(.cluster, state: .sent(now), now: now)
            } else {
                update(.cluster, state: .failed("Cluster not connected."), now: now)
            }
        }
        if draft.networks.contains(.hub) { transports.postToHub(draft.hubFields, party) }
        if draft.networks.contains(.pota) { transports.postToPota(draft.potaFields) }
    }

    /// A client's state for the network it serves.
    func update(_ network: SpotNetwork, state: SpotSendState, now: Date = Date()) {
        receipt?.set(state, for: network, at: now)
    }

    /// Every incoming cluster spot passes here: the one that is ours coming
    /// back is the node's proof of receipt.
    func noteIncomingSpot(_ spot: Spot, now: Date = Date()) {
        guard let pending = pendingEcho, case .sent = receipt?.states[.cluster] ?? .idle,
              ClusterSpot.isEcho(spot, of: pending.fields, poster: pending.poster) else { return }
        pendingEcho = nil
        update(.cluster, state: .confirmed, now: now)
    }

    func dismiss(now: Date = Date()) {
        receipt?.dismiss(at: now)
    }
}
```

`AppSettings.swift` — after `prefillExchangeFromSpots`:

```swift
    /// The networks the spot sheet opens ticked — remembered from the last
    /// post, per network, so a park weekend and a home weekend each keep
    /// their own habit. Every network by default.
    var spotNetworks: Set<SpotNetwork> {
        didSet { defaults.set(spotNetworks.map(\.rawValue).sorted(), forKey: "spotNetworks") }
    }
```
and in `init`:
```swift
        spotNetworks = defaults.stringArray(forKey: "spotNetworks")
            .map { Set($0.compactMap(SpotNetwork.init(rawValue:))) } ?? Set(SpotNetwork.allCases)
```

- [ ] **Step 4: Run both suites — PASS.**
- [ ] **Step 5: Commit** — `spotting: SpotDispatcher and the remembered network choice`.

---

### Task 7: The sheet, the receipt view, and the wiring

**Files:** rename `Sources/UI/SelfSpotSheet.swift` → `Sources/UI/SpotSheet.swift` (rewrite); create `Sources/UI/SpotReceiptView.swift`; modify `Sources/UI/MainView.swift`, `Sources/UI/BandMap.swift`, `Sources/UI/LogTable.swift`.

- [ ] **Step 1: `SpotSheet.swift`**

```swift
import SwiftUI

/// Confirms a spot before it goes out — to every network ticked, at once.
///
/// Every send is confirmed, not just the first: the hub's form has no
/// authentication and reaches a public board immediately, a cluster spot
/// goes to every node on the network, and pota.app posts land on the spot
/// page — and fanning one press out to all three makes that rule more
/// important, not less. Everything is pre-filled from the radio and the log,
/// because retyping a frequency mid-run is why operators stop spotting.
/// Return posts, Escape cancels, ⌘1/⌘2/⌘3 tick and untick the networks.
struct SpotSheet: View {

    let target: SpotNetworkAvailability.Target
    let party: PartyDefinition
    /// Everything but the draft's park — that half is read live from the
    /// draft, so typing a park enables the POTA row as you type.
    let baseContext: SpotNetworkAvailability.Context
    @Binding var draft: SpotDraft
    let onSend: (SpotDraft) -> Void
    let onCancel: () -> Void

    @FocusState private var focused: Field?

    private enum Field: Hashable { case station, frequency, county, comment, park, mode }

    private var context: SpotNetworkAvailability.Context {
        var context = baseContext
        context.draftPark = draft.park
        context.target = target
        return context
    }

    private var available: Set<SpotNetwork> { SpotNetworkAvailability.available(in: context) }

    private var canPost: Bool { draft.sending(available: available).canPost(party: party) }

    private var title: String {
        switch target {
        case .myself: "Spot Myself"
        case .station:
            let call = draft.station.trimmingCharacters(in: .whitespaces).uppercased()
            return call.isEmpty ? "Spot a Station" : "Spot \(call)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            Text("Return posts to every network ticked below — publicly, at once. Esc cancels.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Call spotted").gridColumnAlignment(.trailing)
                    TextField("", text: $draft.station)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused, equals: .station)
                        .frame(width: 130)
                }
                GridRow {
                    Text("Frequency").gridColumnAlignment(.trailing)
                    HStack(spacing: 4) {
                        TextField("", value: $draft.frequencyKHz, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .focused($focused, equals: .frequency)
                            .frame(width: 100)
                        Text("kHz").foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Text(party.countyTerm.sentenceCased).gridColumnAlignment(.trailing)
                    TextField("optional — MDSN, or MDSN/LIME on a line", text: countyBinding)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused, equals: .county)
                        .frame(width: 300)
                }
                GridRow {
                    Text("Comment").gridColumnAlignment(.trailing)
                    TextField("optional", text: $draft.comment)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused, equals: .comment)
                        .frame(width: 300)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Send to").font(.caption).foregroundStyle(.secondary)
                ForEach(SpotNetwork.allCases) { network in
                    networkRow(network)
                }
            }

            HStack {
                Text("Posted by \(draft.poster.isEmpty ? "—" : draft.poster)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Post Spot") { onSend(draft.sending(available: available)) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canPost)
            }
        }
        .padding(20)
        .frame(width: 520)
        // Land on whatever still needs an answer: a blank station, then a
        // blank frequency (a contact logged without a radio arrives with
        // none), else the station.
        .onAppear {
            if draft.station.isEmpty {
                focused = .station
            } else {
                focused = draft.frequencyKHz > 0 ? .station : .frequency
            }
        }
    }

    // MARK: Network rows

    @ViewBuilder
    private func networkRow(_ network: SpotNetwork) -> some View {
        let availability = SpotNetworkAvailability.availability(of: network, in: context)
        let ticked = draft.networks.contains(network) && availability.isAvailable
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Toggle(isOn: tick(network)) {
                    HStack(spacing: 6) {
                        Text(network.displayName).fontWeight(.medium)
                        Text("·").foregroundStyle(.tertiary)
                        Text(availability.text)
                            .foregroundStyle(availability.isAvailable ? .secondary : .orange)
                            .lineLimit(1)
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(!availability.isAvailable)
                .keyboardShortcut(KeyEquivalent(network.shortcutDigit), modifiers: .command)
                Spacer()
                Text("⌘\(String(network.shortcutDigit))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            if network == .pota, availability.isAvailable || target == .station {
                HStack(spacing: 6) {
                    Text("Park").foregroundStyle(.secondary)
                    TextField("US-0817", text: $draft.park)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .focused($focused, equals: .park)
                        .frame(width: 110)
                    Text("Mode").foregroundStyle(.secondary)
                    TextField("CW", text: $draft.mode)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .focused($focused, equals: .mode)
                        .frame(width: 60)
                }
                .padding(.leading, 20)
            }
            if ticked {
                if let problem = draft.problem(for: network, party: party) {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 20)
                } else {
                    Text(draft.preview(for: network, party: party))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.leading, 20)
                        .help("Exactly what this network receives")
                }
            }
        }
    }

    private func tick(_ network: SpotNetwork) -> Binding<Bool> {
        Binding(
            get: { draft.networks.contains(network) },
            set: { on in
                if on { draft.networks.insert(network) } else { draft.networks.remove(network) }
            }
        )
    }

    /// Free text, not a picker: a county-line operator gives two to four.
    /// The raw string is stored — splitting here would eat the separator as
    /// it is typed.
    private var countyBinding: Binding<String> {
        Binding(
            get: { draft.county ?? "" },
            set: { draft.county = $0.isEmpty ? nil : $0 }
        )
    }
}
```

- [ ] **Step 2: `SpotReceiptView.swift`**

```swift
import SwiftUI

/// What became of the last spot, in the station strip: a state per network,
/// live, tinted by the worst of them. Reads the clock once a second so the
/// capsule leaves by itself and comes back for a late change.
struct SpotReceiptView: View {
    let receipt: SpotReceipt
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            if receipt.isVisible(now: timeline.date) {
                HStack(spacing: 6) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                    Text(receipt.title)
                        .font(.caption.weight(.bold).monospaced())
                    Text(receipt.summary)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !receipt.failedNetworks.isEmpty {
                        Button("Retry…", action: onRetry)
                            .controlSize(.mini)
                            .help("Open the spot again with only the failed network(s) ticked")
                    }
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss spot receipt")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(color.opacity(0.18), in: Capsule())
                .foregroundStyle(color)
                .help(receipt.networks.map(receipt.line(for:)).joined(separator: "\n"))
            }
        }
    }

    private var color: Color {
        switch receipt.tint {
        case .pending: .secondary
        case .good: .green
        case .bad: .orange
        }
    }
}
```

- [ ] **Step 3: `MainView.swift` wiring** — replace `showSelfSpot`/`selfSpotFields` with `showSpotSheet`/`spotDraft`/`spotTarget`; add `potaSpotClient`, `spotDispatcher`; replace `canSpotToHub` with `canSpot`; `beginSpot(station:frequencyKHz:location:target:park:)`; the sheet presentation; the transports and callbacks in `onAppear`; `spotReceiptCapsule` in the station strip; help texts. `BandMap.swift`: `canSpotToHub`→`canSpot`, `onSpotToHub`→`onSpotStation`, label `"Spot \(call)…"`. `LogTable.swift`: same rename, label `"Spot \(qso.call)…"`, park from `qso.theirPotaRefs?.first`.

- [ ] **Step 4: Build; run the full suite (log to a file); fix.**
- [ ] **Step 5: README** — keyboard rows, "Spotting to the networks (⇧⌘S)" section, POTA bullet, test count; `docs/PROVENANCE.md`.
- [ ] **Step 6: Commit** — `spotting: one sheet, every network — cluster, hub and POTA at once, with a receipt`.

---

## Self-review

- **Spec coverage:** §2 availability → Task 2; §3 types → Tasks 1–4; §4 clients → Tasks 1, 5, 6; §5 sheet → Task 7; §6 receipt → Tasks 4, 7; §7 wiring → Task 7; §8 setting → Task 6; §9 tests/docs → each task + Task 7 step 5.
- **Type consistency:** `SpotDispatcher.Transports.postToHub` takes `(HubSelfSpot.Fields, PartyDefinition)` in both Task 6's tests and implementation; `SpotReceipt.set(_:for:at:)` and `dismiss(at:)` match Task 4 tests and Task 6 use; `PotaSpot.reference(from:)` is used by Task 2 and defined in Task 3 (run those tests together).
