# 222 MHz (1.25 m) band support

Design, 2026-07-24. Closes the "No 222 MHz band" deferred engine gap in
[`docs/parties/WORKLIST-2026.md`](../../parties/WORKLIST-2026.md).

## Problem

`Band` has no 1.25 m case. Two bundled parties permit the band and tabulate
suggested frequencies on it, so both ship an open question saying the app cannot
log those QSOs:

- **TnQP** — "All amateur bands are valid, with the exception of 60, 30, 17 and
  12 meters." Suggested VHF/UHF frequencies include 223.50.
- **IAQP** — "Contacts may be made on any amateur band EXCEPT the 60m, 30m, 17m,
  and 12m bands." Suggested frequencies are tabulated for 1.25 m at 222.150 and
  223.450.

Neither sponsor has changed a rule. The rules already permitted 1.25 m when both
parties were built; the app is catching up. This is therefore **not** an
Article 20 rule revision, and no diff note is owed — a point the notes state
explicitly so a later reader does not mistake it for one.

## Provenance

Article 1 applies to band edges as much as to county lists. All three values
below come from primary sources fetched 2026-07-24:

| Value | Source |
| --- | --- |
| ADIF band string `1.25m` | ADIF 3.1.4 Band Enumeration, `adif.org/314/ADIF_314.htm` |
| Edges 222.000–225.000 MHz | Same ADIF row (222 / 225), cross-checked against 47 CFR §97.301(a), which authorizes 222.00–225.00 MHz for Technician and above |
| Default frequency 222.100 MHz | ARRL band plan, `arrl.org/band-plan` — "222.1 SSB & CW calling frequency" |

The ADIF enumeration is also authority for the *existing* rows: its `2m 144 148`
and `70cm 420 450` match `Band.edges` exactly. The table has never cited a
source; this change adds that citation.

US amateurs also hold 219–220 MHz, but ADIF excludes it from `1.25m` and it is
restricted to point-to-point digital links. It is deliberately out of scope, and
the code comment says so, so nobody "fixes" the lower bound later.

## Decisions

**Raw value is `1.25m`.** `Band`'s raw value is simultaneously the ADIF band
string, the value persisted into saved logs, and the string rendered in every
band picker. ADIF conformance is not negotiable, so it fixes the other two.

**Case name is `cm125`.** 1.25 m is 125 cm, so it is dimensionally correct and
sits naturally beside `cm70`. `m125` would read as 125 meters.

**Enum position is between `.m2` and `.cm70`** — ascending frequency. The
declaration order is load-bearing: `Band.allCases` drives band-picker order
([`RadioBar.swift:136`](../../../Sources/UI/RadioBar.swift), [`EditQSOSheet.swift:35`](../../../Sources/UI/EditQSOSheet.swift))
and the column order of the score sidebar's QSOs-by-band matrix.

**Display stays `1.25m`; typing `222` also works.** The picker and score
sidebar show the standard designator used by ADIF, LoTW, and other loggers, but
`222` is what an operator's fingers reach for mid-run, so `EntryCommand` accepts
it. `1.25M` already matches for free via the existing raw-value comparison.

This is a targeted alias, not a general scheme. Bare band numbers work for no
band today — `160` parses as 160 kHz and is rejected as out-of-band — and
extending that to every band is out of scope.

**Default frequency is the weak-signal calling frequency, not the sponsors'
FM suggestions.** `m2 = 144200` and `cm70 = 432100` are both SSB/CW calling
frequencies; 222100 continues that pattern. The value only ever applies to
Cabrillo rows logged without CAT data, and a connected radio overrides it.

## Blast radius

Adding the case is sufficient. Everything band-aware derives from the enum:
per-band multiplier scoring, dupe scoping, the band map, ADIF export, Cabrillo
export, all three band pickers, and the score sidebar. No radio driver
references `Band` at all — only `RadioState.band`, via `Band.from(freqKHz:)`.

No bundled party gains the band implicitly, because every party lists
`validBands` explicitly. Article 4 therefore holds with no compatibility
accessor and no default-preserving shim: every existing party scores
identically because none of them can produce a QSO on the new band.

## Commit 1 — the band

Article 9 keeps parties one-per-commit, so the engine change lands alone.

**`Sources/Core/Models/Band.swift`**
- `case cm125 = "1.25m"`, declared between `.m2` and `.cm70`
- `(.cm125, 222000...225000)` in `edges`, positioned to match
- `case .cm125: 222100` in `defaultFreqKHz`
- A provenance comment above `edges` naming ADIF 3.1.4, §97.301(a), and the
  fetch date, plus the 219–220 MHz exclusion note

**`Sources/Core/Engine/EntryCommand.swift`**
- A `bandAliases` map containing exactly `"222": .cm125`, consulted after the
  raw-value match and **before** the numeric branch. Order matters: `222` is
  numeric, so a later check would never be reached.

**Tests**
- `ModelTests`: `Band.from(freqKHz:)` at both edges (222000, 225000) and
  rejection just outside (221999, 225001); the ADIF string is `1.25m`. The
  existing `allCases` round-trip loop covers the new default frequency
  automatically.
- `EntryCommandTests`: `222` and `1.25M` both parse to `.band(.cm125)`;
  `223500` resolves to the band through the frequency path.

**Docs, same commit (Article 6)**
- README test count, from 381 to its new value
- README keyboard table — the QSY/band row gains `222`
- README Data provenance — a band-data entry with the three sources above
- `WORKLIST-2026.md` — strike the "No 222 MHz band" deferred gap; record in its
  place that `CabrilloExporter` writes raw kHz for VHF where Cabrillo V3 wants
  bare band designators (`50`, `144`, `222`, `432`), a pre-existing defect
  affecting 2 m and 70 cm today

## Commits 2 and 3 — TnQP, then IAQP

One party per commit, same shape both times. Article 2 forbids hand-editing the
JSON: the change goes into the generator and the JSON is regenerated.

| | TnQP | IAQP |
| --- | --- | --- |
| Generator | `docs/research/gen_tnqp.py:55` | `docs/research/gen_iaqp.py:82` |
| Stale comment | line 54 | lines 79–81 |
| Research doc | `tnqp_rules.md:25` | `iaqp_rules.md:129`, `:171` |
| Open question to drop | (3) | (3) |
| Test file | `TennesseeQSOPartyTests` | `IowaQSOPartyTests` |

For each: add `"1.25m"` to `validBands`, delete the "this app has no 222 MHz
band" clause from both the generator comment and the party's `notes`,
regenerate the JSON, correct the research doc, and extend the party's test to
assert the band is present.

Both parties remain `verified: partial` — their remaining open questions concern
2025-titled rules documents and are untouched here. Renumber the surviving open
questions so the list stays contiguous.

Neither party's score can change: `validBands` gates which bands are offered,
and no existing QSO sits on 1.25 m. Each party's existing tests are the proof,
and must pass unmodified apart from the added assertion.

## Verification

Article 8 — by test and build, with the command and its output recorded:

```bash
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS'
```

Full suite green at each of the three commits, not only at the end.

## Explicitly out of scope

- **Cabrillo VHF frequency format.** `CabrilloExporter` emits raw kHz
  (`144200`) where Cabrillo V3 specifies bare band designators above 50 MHz.
  Real, pre-existing, and it changes every existing party's export, so it is its
  own commit under Article 9. Recorded in the worklist instead.
- **Band-map gridline density.** The tick step caps at 100 kHz, so 1.25 m draws
  ~30 gridlines. 70 cm already draws ~300; this is pre-existing and 1.25 m does
  not worsen it in kind.
- **Bare band-number aliases for other bands.** `160`, `80`, and the rest stay
  unparsed, exactly as today.
- **219–220 MHz.** Excluded from the band definition, per ADIF.
