# Implementation plan — Contest History, Dashboard, iCloud Sync

Spec: [`../specs/2026-07-25-contest-history-dashboard-design.md`](../specs/2026-07-25-contest-history-dashboard-design.md)

Each step is TDD (tests written first, watched fail, then made green) and
ends with the full suite green. Verification commands per Article 8:

```bash
xcodegen generate
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS'
```

## Steps

1. **Challenge research + data** *(done first — data dependency)*
   `docs/research/sqp_challenge_rules.md`, `gen_sqp_challenge.py`,
   committed rules PDF, generated `Resources/Challenge/sqp_challenge_2026.json`
   (47 contests / 61 windows / 18 bundled asserted).

2. **Core history models** — `Sources/Core/History/`
   `JSONValue` (unknown-key preservation), `ScoreSnapshot` (+`make(log:party:)`
   parity with `ScoreEngine`, `countsOnly(log:)`, operating-minutes rule),
   `ContestRecord` (identity, `merging(_:)` QSO-union), `ContestArchive`
   (envelope, `upserting`, `merging`, stale-snapshot rebuild hook).
   Tests: `Tests/Core/ContestArchiveTests.swift`, `ScoreSnapshotTests.swift`.

3. **Core store** — `ArchiveStore` (coordinated load/upsert against an
   injectable folder; missing→empty, corrupt→throws, upsert re-reads under
   write coordination; atomic writes). Tests: `ArchiveStoreTests.swift`.

4. **Core stats + challenge + upcoming** —
   `SeasonStats`, `ChallengeCalendar` (resource loader), `ChallengeStanding`
   (formula + levels + exclusions), `UpcomingContests` (merged schedule
   sources, fixed-`now` logic). Tests: `SeasonStatsTests.swift`,
   `ChallengeTests.swift`, `UpcomingContestsTests.swift`.

5. **App wiring** — `ContestHistorian` actor (folder resolution, debounce,
   conflict-version sweep, `.qplog` import), `LogDocument.fileWrapper` hook.
   Tests: `ContestHistorianTests.swift` (temp-dir; debounce flush hook).

6. **Dashboard UI + docs** — `Sources/UI/Dashboard/*`, `Window` scene +
   ⌘⇧D, project.yml Challenge resource, README (feature bullets, keyboard
   rows, test count, provenance), CLAUDE.md layout row. Build + full suite +
   run-log verification.

## Risks / watchpoints

- Swift 6 strict concurrency on the historian actor and the nonisolated
  save path — mirror the existing `CloudMirror` pattern.
- `NSFileCoordinator` in sandboxed unit tests: plain temp dirs, no iCloud —
  same environment the CloudMirror tests already prove out.
- Test-host UserDefaults bleed (CloudMirror bookmark key) — historian takes
  explicit folder URLs in tests; only the resolution helper touches
  CloudMirror, tested via the bookmark fixture CloudMirrorTests establishes.
- Dashboard must render with zero records / no folder / stale file — states
  are enumerated in the spec §7 and get explicit UI.
