# Mode-driven hub spotting, and county lines on the wire

Date: 2026-07-25
Status: implemented

## Problem

Three shortcomings, reported from a live ALQP session.

1. **Two spot shortcuts sit one modifier apart.** `⇧⌘S` spots yourself, `⌥⌘S`
   spots the station in the call field. Mid-QSO with N4RT, `⇧⌘S` is the one
   that gets pressed, and the sheet opens with the operator's own call in it.
   Both commands work exactly as coded; the design is the defect.

2. **The county is a single-selection `Picker`.** A county-line operator sends
   two to four counties (`MyLocation` allows four), and none of the spot paths
   can express that. `HubSpotPrefill.county(in:party:)` returns `.first` of the
   counties it finds, so a copied `599 MDSN DANE` prefills half an answer and a
   band-map spot carrying a county line round-trips lossily.

3. **Self-spot prefill is unreliable.** `beginSelfSpot` fills the county from
   `myLocation.sentExchanges.first` with no in-state check, and falls back to
   `currentBand.defaultFreqKHz` when no radio is connected.

## Decisions

| Question | Decision |
| --- | --- |
| One shortcut or two | One — `⇧⌘S`, dispatched on operating mode. `⌥⌘S` retired. |
| S&P with an empty call field | Sheet opens, call field blank and focused. |
| County line on the wire | Post every county, slash-joined: `MDSN/DANE`. |
| No radio connected | Frequency blank, send held, cursor in the field. |

## Provenance

`docs/research/qsopartyhub.md` §5 records the hub's `county` input as a
`<select>` carrying that party's single-county token list, and §6 open question
1 states that the row format is **not** confirmed against a county-line spot.

Posting `MDSN/DANE` into that field is therefore **off the documented
contract**. It is chosen anyway because the alternative is worse: a spot naming
only `MDSN` tells a chaser hunting `DANE` to skip a station that would have
given them the multiplier. Correct information off-contract beats misleading
information on it.

This adds a new open question to §6, and the first real county-line send is
verified against the following poll rather than assumed from an HTTP 200 —
the discipline §6 open question 2 already imposes on every send.

Nothing else here touches a rule, a county list, a band list or a CAT byte, so
no other provenance obligation attaches.

## Design

### 1. `SpotCommand` — a pure dispatcher

New file `Sources/Core/Spotting/SpotCommand.swift`. Keeps the branch out of
SwiftUI and makes it testable without a view.

```swift
enum SpotCommand: Equatable {
    case myself
    case station(String)
    case blankStation

    static func target(mode: OperatingMode, entryCall: String) -> SpotCommand
}
```

| Mode | Call field | Target |
| --- | --- | --- |
| `.run` | anything | `.myself` |
| `.searchPounce` | `N4RT` | `.station("N4RT")` |
| `.searchPounce` | empty or whitespace | `.blankStation` |

Run mode ignores the call field entirely. An operator calling CQ with a
half-typed call in the field still means to spot their own run; guessing
otherwise reintroduces exactly the ambiguity this replaces.

### 2. `MainView` — one button, one shortcut

`beginSpotForMode()` switches on `SpotCommand.target(...)` and calls the
existing `beginSelfSpot()` / `beginSpot(station:frequencyKHz:location:)`.
`.blankStation` opens the sheet with an empty station, the VFO frequency and
no county.

The `Spot Station` toolbar button and its `⌥⌘S` shortcut are removed, along
with `canSpotEntryStation`. The remaining button:

- keeps `⇧⌘S`
- takes its label from the mode — `Spot Myself` in Run, `Spot Station` in S&P
- names the actual call in its tooltip when S&P has one
- is disabled only on `!canSpotToHub`

Right-click to spot from the band map or a log row is unchanged; those paths
already call `beginSpot` directly and remain the way to spot an arbitrary
station.

### 3. County as free text

`HubSelfSpot.Fields.county` stays a plain `String` — not `[String]`. The sheet
binds a `TextField` straight to it. An array in the model would require the
binding to split and rejoin on every keystroke, which eats a trailing separator
the moment it is typed and fights the cursor.

Structure lives in pure functions instead:

```swift
extension HubSelfSpot {
    /// Split on `/`, `,` or whitespace; uppercased; empties dropped;
    /// duplicates dropped, first occurrence wins. Every token, county or not —
    /// judging them is `validate`'s job.
    static func counties(in text: String) -> [String]
}
```

- **Validation** — every parsed token must be a county of this party. The
  existing `.unknownCounty(String)` names the first that is not. An empty
  county field stays valid; the field is optional on the form.
- **Wire** — `hubCountyToken` maps **per token** through
  `reverseCountyAliases`, then joins with `/`. Illinois' `PULA`→`PULS`
  translation therefore still holds inside a pair.
- **Separator** — `/`, matching `MyLocation.displayText`, which already joins
  county lines that way everywhere else in the app.
- **No count cap.** `MyLocation` caps an in-state operator at four, but a
  third-party spot of somebody else's rover has no such knowledge. Requiring
  every token to be a real party county is the bound.

### 4. Prefill

`HubSpotPrefill.county(in:party:)` becomes
`counties(in:party:) -> String?` — every party county named in the text, in
order of appearance, deduped, joined with `/`, and `nil` when the text names
none. Same token scan as today, so a half-copied exchange still offers what it
has.

Note the two similarly named functions differ by job and by return type.
`HubSelfSpot.counties(in:)` splits operator-typed text into tokens for
validation and the wire, keeping every token including bad ones.
`HubSpotPrefill.counties(in:party:)` scans found text — a copied exchange, a
band-map spot's county — and keeps only real counties of this party, because
anything else must never be offered as a county token for a public board.

`beginSelfSpot` changes on two points:

- County: `myLocation.isInState ? sentExchanges.joined(separator: "/") : nil`.
  Today an out-of-state operator who toggles to Run and presses `⇧⌘S` gets
  `TX` in the county field, which fails `unknownCounty` and blocks the sheet
  that was just opened.
- Frequency: `vfoKHzForSpotting ?? 0`, dropping the `currentBand.defaultFreqKHz`
  fallback. Zero opens the sheet on the frequency field with the send held, the
  behaviour every other spot path already has and the one
  `HubSpotPrefill`'s own comment argues for.

`offerReSpotOnCountyChange` compares `lastSelfSpotCounty` against
`sentExchanges.first`, so a line moving from `MDSN/DANE` to `MDSN/IOWA` never
prompts. It compares the joined string instead.

### 5. Sheet

The county `Picker` becomes a `TextField` with a `MDSN or MDSN/DANE`
placeholder, bound directly to `fields.county`. `Field.county` already exists in
the focus enum and is finally used.

Focus on appear, in order: empty station → `.station`; else zero frequency →
`.frequency`; else `.station`.

## Testing

Every case below is a test, and the regression tests in §3 of this list are
proven red against the current code before the fix lands.

**`Tests/Core/SpotCommandTests.swift`** (new)
- Run + call present → `.myself`; Run + empty → `.myself`
- S&P + `n4rt` → `.station("N4RT")`; S&P + empty and S&P + `"   "` →
  `.blankStation`

**`Tests/Core/HubSpotPrefillTests.swift`**
- `599 MDSN DANE` → `MDSN/DANE`; order of appearance preserved
- `MDSN MDSN` → `MDSN` (deduped)
- `599 TX` → `nil`; `DX` → `nil`
- `MDSN 599 XXXX DANE` → `MDSN/DANE` (non-counties ignored, not fatal)

**`Tests/Core/HubSelfSpotTests.swift`**
- `validate` accepts `MDSN/DANE`, `MDSN, DANE`, `MDSN DANE`
- `validate` rejects `MDSN/XXXX` with `.unknownCounty("XXXX")`
- `validate` accepts an empty county
- `multipartBody` posts `county=MDSN/DANE`
- ILQP `PULA/JACK` posts as `PULS/JACK` — aliasing survives inside a pair

**Regression**
- out-of-state self-spot prefills no county rather than `TX`
- no radio → frequency `0`, not the band default
- rover prompt fires when a county line changes in a position other than first

## Documentation

Same commit, per Article 8.

- **README keyboard table** — the `⌥⌘S` row is deleted; the `⇧⌘S` row reads as
  the mode-driven command.
- **README** — `Spotting yourself (⇧⌘S)` and `Spotting somebody else (⌥⌘S, or
  right-click)` merge into one section describing the mode switch, county-line
  counties, and the blank-frequency hold.
- **README line 623** — unit test count updated from 945.
- **`docs/research/qsopartyhub.md` §6** — new open question recording that the
  county field is a single-token `<select>`, that a slash-joined county-line
  value is off-contract and unverified, and that the first send is checked
  against the following poll.

## Out of scope

- Reading a slash-joined county *back* off the board. `HubSpotParser` reads the
  county column by position and will surface whatever string is there; no
  inbound parsing changes here. If the board round-trips our own county line,
  that is observed and recorded, not designed for in advance.
- Any change to right-click spotting from the band map or log.
- Any change to the five-minute duplicate window or the confirm-on-next-poll
  behaviour.
