# POTA Hunting Implementation Plan (phase 3 of the 2026-08-25 spec)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status (2026-08-25):** executed through Task 4 on branch `pota-hunting`,
inline. Suite: 3199 tests, 2 skipped, 0 failures. Deviations: (1) no
per-source checkbox was added to the filters popover — the house design is
deliberately a one-way "hub only" toggle, and the default all-sources view
already shows `.pota`; the party opt-in toggle landed beside it instead;
(2) the on-map park badge was not built — the park rides the spot tooltip
and the pounce, and a label badge would rework the layout metrics for
little gain (the tooltip names the park; the P2P field receives it);
(3) `enforceSpottingPolicy`'s claim sweep gained a POTA-board carve-out the
plan had not spelled out: the sweep's `removeNetworkSpots` would otherwise
flap the board feed a POTA log is entitled to keep — the sync re-decides
and the rows come straight back; (4) the store's `.pota` lifetime joined
the cluster/local case rather than a new knob, since `replace` is what
keeps the board truthful while polling. All recorded in their commits.

**Goal:** POTA's live activator board in the band map — spots with their park
riding along, click/⌘↑⌘↓-to-pounce prefilling call and their-park — polled
while a POTA log is front, and available to a party log that opts in.

**Architecture:** `SpotSource.pota` + `Spot.park`; a pure
`PotaSpot.mapToSpots` turning board rows (the already-shipped `BoardSpot`
decoder) into band-map spots; `SpotStore.replace(source:with:)` because the
board is authoritative per poll (a row gone from the feed is QRT or
expired); a `PotaBoardClient` on the house `…Fetching` seam polling
`GET https://api.pota.app/spot/activator` every 60 s (shape banked in
`docs/research/pota/SOURCES.md`; `HEAD` is not available); the tune path
gains one line — a spot's park lands in the empty their-park field. Polling
gates: a POTA log (`contest.potaProgram`) always polls; a party log polls
only when the operator turns it on AND the assisted-category rules that
govern the hub allow it; `usedSpots` stamping applies exactly as for
cluster spots (spec 2026-08-25 decision 3).

**Verification command:** the standard pipefail xcodebuild line. Base:
master `91db072` (phases 1–2 merged). Worktree
`.claude/worktrees/pota-hunting`, branch `pota-hunting`.

---

### Task 1: `SpotSource.pota`, `Spot.park`, the row mapper, and the store primitive

**Files:**
- Modify: `Sources/Core/Spotting/Spot.swift` (source case + park field)
- Modify: `Sources/Core/Spotting/SpotStore.swift:20-28` (lifetime switch) and append `replace`
- Modify: `Sources/Core/Spotting/PotaSpot.swift` (BoardSpot gains the fields the map needs + `mapToSpots`)
- Create: `Tests/Core/PotaBoardSpotTests.swift`

- [ ] **Step 1: Failing tests** — decode the shipped fixture
`Tests/Fixtures/pota_spots_sample.json` (five verbatim board rows, one RBN)
and map it:

```swift
import XCTest
@testable import QSOPartyLogger

/// Board rows → band-map spots (spec 2026-08-25 decision 3). The fixture is
/// five rows copied verbatim from the live board (SOURCES.md).
final class PotaBoardSpotTests: XCTestCase {

    private func fixtureRows() throws -> [PotaSpot.BoardSpot] {
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: "pota_spots_sample", withExtension: "json"))
        return try XCTUnwrap(PotaSpot.board(from: try Data(contentsOf: url)))
    }

    func testFixtureDecodesWithFrequenciesAndParks() throws {
        let rows = try fixtureRows()
        XCTAssertEqual(rows.count, 5)
        XCTAssertTrue(rows.allSatisfy { !$0.reference.isEmpty })
    }

    func testMapToSpots() throws {
        let spots = PotaSpot.mapToSpots(try fixtureRows(), now: Date(timeIntervalSince1970: 0))
        XCTAssertFalse(spots.isEmpty)
        for spot in spots {
            XCTAssertEqual(spot.source, .pota)
            XCTAssertNotNil(spot.park, "the park is the point")
            XCTAssertGreaterThan(spot.freqKHz, 1000, "kHz, per the board's own rule")
            XCTAssertNil(spot.county, "a park is not a county")
        }
        // The mode rides the comment so the map's mode inference and colour
        // rules see it without a new field.
        XCTAssertTrue(spots.contains { !$0.comment.isEmpty })
    }

    func testUnparseableFrequencyRowsAreDropped() {
        let rows = [PotaSpot.BoardSpot(activator: "W1AW", reference: "US-0001",
                                       spotter: "W1AW", frequency: "QRG?",
                                       mode: "CW", spotTime: nil, source: nil)]
        XCTAssertTrue(PotaSpot.mapToSpots(rows, now: Date(timeIntervalSince1970: 0)).isEmpty)
    }

    func testStoreReplaceIsWholesalePerSource() {
        let store = SpotStore()
        store.add(Spot(call: "K1AA", freqKHz: 14040, spotter: "N1XX",
                       comment: "", receivedAt: Date(), county: nil, source: .cluster))
        let first = Spot(call: "W1AW", freqKHz: 14285, spotter: "W1AW",
                         comment: "SSB", receivedAt: Date(), county: nil,
                         source: .pota, park: "US-0001")
        store.replace(source: .pota, with: [first])
        XCTAssertEqual(store.all.filter { $0.source == .pota }.count, 1)
        // Next poll: the board no longer lists W1AW (QRT). He is gone; the
        // cluster spot is untouched.
        store.replace(source: .pota, with: [])
        XCTAssertTrue(store.all.filter { $0.source == .pota }.isEmpty)
        XCTAssertEqual(store.all.filter { $0.source == .cluster }.count, 1)
    }
}
```

(Adjust `Spot`/`BoardSpot` constructions to the real memberwise shapes —
`Spot.park` is being added in this task; keep argument order as declared.)

- [ ] **Step 2: Red, then implement**

`Spot.swift`: add `case pota` to `SpotSource` with a doc line ("POTA's
activator board — the spot carries the activator's park"); add
`var park: String? = nil` after `county` with a doc comment; the memberwise
init is synthesized-by-default-values, so call sites are untouched.

`SpotStore.swift`: the lifetime switch gains `.pota` beside `.cluster,
.local` (while polling, `replace` keeps the board truthful; when polling
stops, board spots fade on the operator's one age-out setting like
everything else). Append:

```swift
    /// The POTA board is authoritative per poll: a row gone from the feed
    /// is QRT or expired, so its spots are replaced wholesale rather than
    /// aged individually. Other sources are untouched.
    func replace(source: SpotSource, with spots: [Spot]) {
        all.removeAll { $0.source == source }
        for spot in spots { add(spot) }
    }
```

`PotaSpot.swift`: extend `BoardSpot` with the map's fields (all optional,
lenient — `comments: String?`, `invalid: String?`… check the banked row
shape in SOURCES.md § the spot API; add only what `mapToSpots` reads) and:

```swift
    /// Board rows as band-map spots. Frequencies arrive as kHz strings
    /// ("14039.5", "18101" — both observed live); a row whose frequency
    /// does not parse above the board's own 1000 kHz floor is dropped, and
    /// the mode rides the comment so the map's existing mode inference
    /// reads it. Spotter and activator both come along for the filters.
    static func mapToSpots(_ rows: [BoardSpot], now: Date) -> [Spot] {
        rows.compactMap { row in
            guard let kHz = Double(row.frequency ?? ""), kHz > 1000 else { return nil }
            return Spot(
                call: row.activator.uppercased(),
                freqKHz: kHz,
                spotter: (row.spotter ?? row.activator).uppercased(),
                comment: row.mode ?? "",
                receivedAt: now,
                county: nil,
                source: .pota,
                park: row.reference.uppercased()
            )
        }
    }
```

Build; give every exhaustive `SpotSource` switch the compiler flags a
`.pota` arm in its neighbours' voice (expect at least the store's lifetime
switch; possibly a legend/colour table in the band map — follow each site's
own idiom and note them in the commit body).

- [ ] **Step 3: Green; full suite; commit** — `spots: SpotSource.pota — board rows as band-map spots, replaced wholesale per poll`

---

### Task 2: `PotaBoardClient`

**Files:**
- Create: `Sources/App/PotaBoardClient.swift`
- Create: `Tests/App/PotaBoardClientTests.swift`

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

/// The board poller: 60 s cadence while started, wholesale-published rows,
/// failures keep the last board and land in the console — never a modal,
/// never a block. Tests drive the fetch directly; no timers fire here.
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
          "reference": "US-6653", "spotter": "W8EKM", "comments": "CQ",
          "source": "Web"}]
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
```

- [ ] **Step 2: Red; implement**

```swift
import Foundation
import Observation

protocol PotaBoardFetching: Sendable {
    func get(_ url: URL) async throws -> Data
}

struct URLSessionPotaBoardFetcher: PotaBoardFetching {
    private let session: URLSession
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = [
            "User-Agent": "QSOPartyLogger/1.5 (+https://github.com/KE5CW) macOS"
        ]
        session = URLSession(configuration: config)
    }
    func get(_ url: URL) async throws -> Data {
        try await session.data(from: url).0
    }
}

/// The POTA activator board, polled while a log wants it (spec 2026-08-25
/// decision 3). `api.pota.app` refuses HEAD, so each poll is a plain GET of
/// the same list the site reads (`PotaSpot.boardURL`, banked in
/// docs/research/pota/SOURCES.md); 60 s keeps well under the site's own
/// refresh habits. A failed poll keeps the last board and says so in the
/// console — the map fades stale spots on its own age-out.
@MainActor
@Observable
final class PotaBoardClient {
    private(set) var spots: [Spot] = []
    private(set) var console: [String] = []
    private(set) var isPolling = false

    static let interval: TimeInterval = 60

    private let fetcher: PotaBoardFetching
    private var pollTask: Task<Void, Never>?

    init(fetcher: PotaBoardFetching = URLSessionPotaBoardFetcher()) {
        self.fetcher = fetcher
    }

    func start() {
        guard !isPolling else { return }
        isPolling = true
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                try? await Task.sleep(nanoseconds: UInt64(Self.interval * 1_000_000_000))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        isPolling = false
    }

    /// One fetch — the poll loop's body, and the tests' direct entry.
    func pollOnce() async {
        do {
            let data = try await fetcher.get(PotaSpot.boardURL)
            guard let rows = PotaSpot.board(from: data) else {
                log("board: unreadable reply — keeping the last list")
                return
            }
            spots = PotaSpot.mapToSpots(rows, now: Date())
        } catch {
            log("board: \(error.localizedDescription) — keeping the last list")
        }
    }

    private func log(_ line: String) {
        console.append(line)
        if console.count > 100 { console.removeFirst(console.count - 100) }
    }
}
```

- [ ] **Step 3: Green; full suite; commit** — `spots: PotaBoardClient — the activator board on a minute poll`

---

### Task 3: Wiring — polling gates, the map, the pounce, the toggle

**Files:**
- Modify: `Sources/UI/MainView.swift` (client, sync, ingestion, tune)
- Modify: `Sources/UI/SpottingPolicy.swift` (or wherever `hubShouldPoll` lives — one sibling predicate)
- Modify: `Sources/App/AppSettings.swift` (`potaSpotsInParties`, default false)
- Modify: `Sources/UI/BandMap.swift` filters popover (source row + party-log toggle)
- Modify: `Tests/UI/SpottingPolicyTests.swift` (the new predicate)

- [ ] **Step 1: The polling predicate, test-first**

Find `hubShouldPoll` (`grep -n "hubShouldPoll" Sources/UI/SpottingPolicy.swift`)
and read its shape and its tests. Add a sibling in the same voice:

```swift
    /// Whether the POTA board should be polled. A POTA log always hunts —
    /// there is no assisted category at POTA, so nothing to protect. A
    /// party log polls only when the operator opted in AND the same
    /// assisted-category rule that governs the hub allows it: the board is
    /// spotting assistance like any other.
    static func potaShouldPoll(
        isPotaProgramLog: Bool,
        partyOptIn: Bool,
        claim: StationProfile.CategoryAssisted
    ) -> Bool {
        if isPotaProgramLog { return true }
        guard partyOptIn else { return false }
        return claimAllowsSpots(claim)
    }
```

…where `claimAllowsSpots` is whatever the hub predicate already uses for
the claim half (read it; reuse the exact same check so the two networks can
never disagree — extract a shared helper if it is inline). Tests mirror the
hub predicate's: POTA log polls regardless of claim; party log needs both
the opt-in and a permitting claim.

- [ ] **Step 2: MainView wiring**

1. `@State private var potaBoardClient = PotaBoardClient()`.
2. A sync sibling to `syncHubSpotClient` (called from the same `.task`/
   `.onChange` sites — grep the three `syncHubSpotClient()` call sites and
   add `syncPotaBoardClient()` beside each, plus
   `.onChange(of: settings.potaSpotsInParties)`):

```swift
    private func syncPotaBoardClient() {
        if SpottingPolicy.potaShouldPoll(
            isPotaProgramLog: flow.standaloneContest?.potaProgram == true,
            partyOptIn: settings.potaSpotsInParties,
            claim: document.log.station.categoryAssisted
        ) {
            potaBoardClient.start()
        } else {
            potaBoardClient.stop()
        }
    }
```

3. Ingestion: where hub spots land in the band map model (grep
   `hubSpotClient.spots` consumers), add the analogous
   `.onChange(of: potaBoardClient.spots) { bandMapModel?.store.replace(source: .pota, with: potaBoardClient.spots) }`
   — matching however the model exposes its store (read `BandMapModel` at
   `BandMap.swift:8-90`; if spots flow through a method rather than the
   store, add a `replacePotaSpots(_:)` pass-through in the model's idiom).
   Also stamp usage the way hub/cluster ingestion does: find where
   `noteSpotsUsed()`/`usedSpots` is set for arriving spots and apply the
   same rule (spots *received into the session* is the trigger per the
   NAQP wording — copy the hub's exact trigger point).
4. The pounce: in `tune(to:)` (line ~1645), after the `flow.stationChanged`
   call:

```swift
        // A POTA spot names the activator's park; it lands in an empty
        // their-park field the way a previously-given park does — typed
        // text is never overwritten (spec 2026-08-25 decision 3).
        if let park = spot.park, entry.theirParkTyped.isEmpty {
            entry.theirParkTyped = park
        }
```

- [ ] **Step 3: The band map surface**

Read the filters popover (`BandMap.swift:305-460`) and:
1. Add the `.pota` source to the source-filter row exactly as `.hub` is
   rendered (checkbox/toggle bound into `SpotFilter.Options.sources`).
2. Add a "POTA spots in contests" toggle bound to
   `$settings.potaSpotsInParties`, visible only when the front log is a
   party (the POTA log needs no switch — it always hunts), with a caption
   in the popover's own voice ("The POTA activator board as a spot source.
   Receiving spots is assistance — the assisted category rules apply.").
3. If the map draws per-source colours/legend (grep `SpotSource` in
   `BandMapScale.swift`/`SpotLabelSize.swift`/legend code), give `.pota`
   a colour in the palette's idiom — the compiler's exhaustive-switch
   errors from Task 1 will already have named every such site.
4. Spot label: where the hub's county badge renders on a spot row, show
   `spot.park` the same way (it is the datum a hunter pounces for).

`AppSettings`: `potaSpotsInParties: Bool` default false, stored in the
established pattern.

- [ ] **Step 4: Full suite; commit** — `pota: the activator board in the band map — poll gates, pounce with the park, party opt-in`

---

### Task 4: Docs and the final gate

- README: extend the POTA-mode section's hunting story (the board in the
  band map, minute poll, pounce fills call + park, the party-log opt-in and
  its assisted-category consequence) and the keyboard note (⌘↑/⌘↓ step
  POTA spots like any other); test count from the final run.
- PROVENANCE.md: the board-read endpoint is already banked (spot API row) —
  extend that row's sentence with "and read back as the hunting feed" if it
  names only confirmation.
- Status block on this plan; final full suite; commit —
  `docs: POTA hunting — README, provenance, test count`.

Then finishing-a-development-branch (ExitWorktree first, merge from the
main checkout, `git worktree remove` last).

## Coverage map

| Spec item | Task |
| --- | --- |
| Decision 3 (feed the band map, no new pane; pounce) | 1, 2, 3 |
| §Hunting (source case, park field, 60 s poll, expire-by-board, worked-dimming/`usedSpots` via existing machinery) | 1, 2, 3 |
| Party opt-in + assisted gating | 3 |
| Docs | 4 |
