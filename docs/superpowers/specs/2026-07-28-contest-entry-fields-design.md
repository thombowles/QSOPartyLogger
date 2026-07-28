# Contest entry fields — assisted category, transmitters, operators, grid

**Date:** 2026-07-28 · **Trigger:** KE5CW: "Make sure the NAQP contest setup
screen collects all the appropriate details to support all the operating
modes" (rules: <https://www.ncjweb.com/NAQP-Rules.pdf>), with his January
2026 NAQP CW Cabrillo log as reference. He added: "These fields may also
apply to the other qso parties and may be universal." Designed and executed
in one autonomous session; the approval gates of the brainstorming flow are
collapsed into this document plus the commit record.

## Problem

NAQP rule 5 defines three entry classifications — Single Operator (SO),
Single Operator **Assisted** (SOA), and Multioperator Two-Transmitter (M2) —
and rule 6 two competitive power classes (QRP ≤5 W, Low 5–100 W; over 100 W
is received as a check log). The app cannot declare most of them:

- **`CATEGORY-ASSISTED` does not exist anywhere** — not in `StationProfile`,
  not in the setup sheet, not in `CabrilloExporter`. The reference log
  (KE5CW, NAQP CW, January 2026, written by N1MM) is `CATEGORY-OPERATOR:
  SINGLE-OP` + `CATEGORY-ASSISTED: ASSISTED` — the operator's own real
  category is unrepresentable, and SO vs SOA is the distinction NAQP's rule
  5A/5B (and its plaque table) turns on.
- **`categoryTransmitter` and `operators` exist on `StationProfile` but have
  no UI**, so `CATEGORY-TRANSMITTER:` is forever `ONE` and `OPERATORS:` is
  forever the bare callsign — M2 (rule 5C: two transmitters, a crew of
  operators) cannot be declared either.
- **`GRID-LOCATOR` is absent** (model, UI, export). The reference log
  carries `GRID-LOCATOR: EM13LE`; it is a standard Cabrillo V3 header.
- **`country` is exported but not editable** — `ADDRESS-COUNTRY:` always
  says `USA` with no field anywhere to change it.

All four are universal Cabrillo V3 headers (wwrof.org spec, banked
2026-07-28 in `docs/research/cabrillo_v3_headers.md`), not NAQP quirks —
exactly the "may be universal" the request anticipated. No `Sources/UI/`
party branching is needed or permitted.

## Design

### 1. `StationProfile` — two new fields, and a tolerant decoder

```swift
var categoryAssisted: CategoryAssisted = .nonAssisted
var gridLocator: String = ""            // Maidenhead, e.g. EM13LE; optional

enum CategoryAssisted: String, Codable, CaseIterable, Sendable {
    case nonAssisted = "NON-ASSISTED"   // default: the claim is opt-in
    case assisted = "ASSISTED"
}
```

`StationProfile` today has **no hand-written `init(from:)`** — synthesized
decoding requires every key, and `ContestLog.init(from:)` hard-decodes
`station`, so adding a field naively would fail to open every existing
`.qplog`, drop every saved `lastStationProfile` in Preferences, and break
every `ContestRecord` in the iCloud archive. The change therefore ships a
hand-written `init(from:)` using `decodeIfPresent` + the property default
for **every** field (the `ContestLog` pattern, Article 4's spirit applied to
persistence). Encoding stays synthesized — new files always carry the keys.

Default `NON-ASSISTED` because absent-means-unassisted is how sponsors read
logs that predate the field, and an assistance claim should be deliberate.

### 2. `CabrilloExporter` — two new header lines

- `CATEGORY-ASSISTED: <raw>` — always written, immediately after
  `CATEGORY-OPERATOR:` (the reference log's ordering).
- `GRID-LOCATOR: <uppercased>` — written only when non-empty, between
  `ADDRESS-COUNTRY:` and `EMAIL:` (the reference log's ordering).

Nothing else moves; existing headers and QSO lines are byte-identical for a
profile that never touches the new controls, except the added
`CATEGORY-ASSISTED: NON-ASSISTED` line (a truthful statement of the default
that was previously implicit).

### 3. `SetupSheet` — complete the Category section, finish the address block

- **Category** section: `Picker("Assisted")` after Operator;
  `Picker("Transmitters")` after Station; then `TextField("Operators")`
  (monospaced, uppercase) with the caption "Multi-op: space-separated calls;
  @ marks the host station. Blank = your callsign." — surfacing the two
  model fields that had no UI.
- **Station** section: one new row after City/State/ZIP —
  `TextField("Country")` beside `TextField("Grid square")` (monospaced,
  uppercase, optional).

All controls are stock grouped-`Form` rows: fully keyboard-reachable in the
existing Tab order (Article 7), no `@FocusState` changes (programmatic focus
still lands on callsign/location/name — the save-gating fields). `canSave`
is unchanged: every new field has a valid default, and an M2 entry with a
blank operators list is the *sponsor's* reclassification case (rule
5C(viii)), not a reason to block saving.

### 4. Tests (red first, per the TDD skill)

- `CabrilloExporterTests`: default header carries `CATEGORY-ASSISTED:
  NON-ASSISTED` and no `GRID-LOCATOR:`; an assisted/gridded/multi-op profile
  carries `ASSISTED`, the uppercased grid in the reference-log position,
  `CATEGORY-TRANSMITTER: TWO`, and a multi-call `OPERATORS:` list with the
  `@host` convention preserved.
- `ModelTests`: new fields round-trip; a legacy payload built by encoding
  and **deleting the new keys** (the `testLogWithoutAStoredModeDerivesItFromLocation`
  fixture pattern) decodes to the defaults with neighbouring values intact.
- `NorthAmericanQSOPartyCWTests`: rule-anchored — an SOA entry exports
  `SINGLE-OP` + `ASSISTED` (rule 5B), an M2 entry exports `MULTI-OP` +
  `TWO` + the operator list (rule 5C), and QRP exports `CATEGORY-POWER:
  QRP` (rule 6A) — over a real NAQP log with name exchanges.

## Explicit non-goals, with the rule that excuses each

- **Team fields** — rule 14: "Inclusion of team information in submitted
  Cabrillo logs is not required, as teams are determined ahead of time
  through the team registration system." Registration is a web form, not a
  header.
- **Blocking HIGH power for NAQP** — rule 6: entries over 100 W "will be
  classified as check logs" *by the sponsor*. The export stays honest;
  constraining per-party category sets would add schema for no behavior.
- **`CATEGORY-OVERLAY` / `CATEGORY-TIME`** — NAQP defines neither; no
  bundled party models either; additive later under Article 4 if a party
  ever needs one.
- **Off-time accounting and M2's 10-minute band timer** — already recorded
  as deliberately unmodeled in `naqpcw_rules.md` §14.
- **`LOCATION:` derivation unchanged** (state/province token, `TX`) — N1MM
  writes the ARRL section (`NTX`) instead; NAQP's sponsor specifies nothing
  and collects station location on its upload form independently. Noted in
  the research doc; changing it needs sponsor-side authority that does not
  exist.
- **A "cluster connected while NON-ASSISTED" warning** — worthwhile but a
  behavior feature, not a setup field; left for its own session.

## Compatibility

No party JSON changes; no `ScoreEngine` changes; `scoreMultipliers` keys
(power, station) untouched, so every bundled party scores identically —
the existing per-party suites are the proof. The only export diff for an
untouched profile is the always-written `CATEGORY-ASSISTED: NON-ASSISTED`.
