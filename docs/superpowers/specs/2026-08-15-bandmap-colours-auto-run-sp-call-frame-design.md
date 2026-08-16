# Band map colours, automatic Run ⇄ S&P, and the call frame — design

Date: 2026-08-15. Three requests from Tom, in his words:

1. "color the potential mults in the bandplan as red, unworked but not mults
   as blue, and worked as greyed out like they are today"
2. "when i'm running on a frequency, but then move off of that frequency,
   automatically change me to S&P after a reasonable amount of vfo change
   (incase i need to qsy because of qrm)" — and, on review, "when I return to
   CQ Frequency, put it back in Run mode"
3. "when I'm in S&P and scrolling the vfo across the band, as I get close to
   current spots, automatically fill the qso field(s) as I come across spots"

Tom chose the N1MM call-frame form for (3) — a ghost call in the empty call
field, taken by Return or Space — over filling the field directly, because a
direct fill collides with typing a call heard on the same frequency (§3).

## Reference

All three behaviours imitate N1MM Logger+, so the manual is the authority
(constitution Article 1 applies to imitated behaviour as much as to rules).
Fetched 2026-08-15 from n1mmwp.hamdocs.com:

**Bandmap window** (`/manual-windows/bandmap-window/`), *Colors of the
Incoming Spots*:

> Blue: Will be a good QSO, not a multiplier
> Red: Single Multiplier …
> Green: Double or better Multiplier …
> Gray: Dupe

and, on tuning: *"In Search & Pounce (S&P) the call-frame will show you each
spotted station as you come within 'tuning tolerance' (user settable) of that
station. … With worked stations in the bandmap, the program will tell you that
they are not workable again. You can tune by them more quickly."*; *"If you
tune the VFO outside that range, any call-sign captured into the Entry window's
call-frame or brought into the Entry window's call-sign textbox will be
erased."*; *"Remember: if a call is in the callframe, space will load it into
the call textbox."*

**Entry window** (`/manual-windows/entry-window/`), *Run mode and S+P mode*:

> When you call CQ on a frequency, the marker CQ-Frequency is placed at that
> frequency on the Bandmap. Thereafter, if you are in S&P mode and you tune
> within the tuning tolerance of the marker, the program will switch
> automatically to Run mode.

> Normally when you are on your CQ-frequency you will be in Run mode and
> QSYing will switch to S&P mode. Press Alt+F11 to disable this automatic mode
> change, and again to re-enable it.

Config menu: *"Do not automatically switch to Run on CQ-frequency — When
selected and you QSY back to an old Run frequency, the mode stays in S&P. …
This is most useful in Sprint-like contests"*. Repeat CQ: *"The function is
automatically turned off when no longer on the CQ-frequency and the mode
changed to S&P."* Call frame: *"When tuning the band, if a station on the
Bandmap is within the tuning tolerance, its call will be placed in the Entry
window's call-frame. When the call-sign textbox is empty, pressing the space
bar will copy the call-sign from the call-frame to the call-sign textbox."*
and (SO2V section) *"Hitting the space bar (or Enter, in ESM) will pull the
call-sign from the call-frame into the Call-sign textbox."* Colours there:
*"Gray: Dupe contact or an unworkable station"*.

**Configurer** (`/setup/the-configurer/`): *"CW Tuning Tolerance (Hz) … the
maximum frequency distance to the call on the bandmap when it will be put on
the callsign frame. … The default value is 300"* — one each for SSB, CW and
RTTY, all defaulting to 300 Hz.

## Where this differs from N1MM, and why

- **Green (double multiplier) is not drawn.** A QSO party contact carries one
  location; a county-line contact is the only double, and it is one spot with
  one county on the hub. Red, blue, grey — the three Tom named.
- **Leaving Run has its own distance**, larger than the tuning tolerance. In
  N1MM, S&P F1 is a CQ that puts you back in Run, so a QRM dodge costs one
  key; here S&P F1 is "my call", so an early flip to S&P costs ⌘R. Tom asked
  for "a reasonable amount of vfo change" for exactly that reason.
- **The phone tuning tolerance defaults to 1 kHz**, not 300 Hz. RBN does not
  skim SSB; human SSB spots are posted to the kHz or half-kHz, so 300 Hz
  misses a station you can plainly hear. CW and digital keep N1MM's 300 Hz.
- **The frame is drawn inside the empty call field** as ghost text rather
  than in a strip above it. Same lifetime rules, one fewer row on screen.

## 1. Band map colours

Three colours, decided in this order:

| Colour | Meaning | Test |
| --- | --- | --- |
| grey (`.secondary`, struck through — as today) | worked on this band and mode, or superseded | `SpotFilter.isWorked` on call+county; `spot.isSuperseded` |
| red | unworked, and the location the app knows for the station would still add a multiplier | `ScoreEngine.wouldAddMultiplier` for that location on the spot's band and mode |
| blue | everything else unworked — not a multiplier, or location unknown | — |

**Where the location comes from.** A hub or local spot carries a county and
uses it, exactly as `isNeededMultiplier` does today. A cluster spot carries
none, so the app resolves the call the same way the exchange pre-fill does,
in the same order — this log, then the archive under the same sponsor (or a
non-county location under any sponsor), then the call history file. So a red
cluster spot is one whose county will land in the exchange field the moment
you tune to it, and never a guess the entry row would not also make.

That chain is factored out of `EntryFlow.refreshPrefill` into a pure
`StationMemory.knownLocation(call:log:index:callHistory:party:role:)`
returning a `Candidate` whose `Source` gains `.callHistory`; `refreshPrefill`
calls it and maps `.callHistory` onto the existing `ExchangeOrigin.callHistory`.
Behaviour of the entry row is unchanged; the existing prefill tests pin it.

`BandMapModel` gains `archiveIndex: StationMemory.Index` and
`callHistory: CallHistoryFile.Parsed?` (already checked against the party by
`MainView`, which sets both wherever it sets the flow's), and

```swift
struct LocationVerdict: Equatable { let location: String; let source: LocationSource; let needed: Bool }
enum LocationSource { case spot, thisLog, archive, callHistory }
func verdict(for spot: Spot) -> LocationVerdict?     // nil: location unknown
func status(for spot: Spot) -> SpotStatus            // .worked / .neededMultiplier / .unworked
```

`isNeededMultiplier` becomes `verdict(for:)?.needed ?? false`. Two memo
caches, both `@ObservationIgnored` — call → verdict, and location|band|mode →
needed — dropped in the `didSet` of `party`, `log`, `archiveIndex` and
`callHistory`. The 2026-07-25 rule stands: nothing the band map body reads
may write observed state, and `BandMapObservationTests` grows a case for a
cluster spot whose verdict is computed on first read.

`log` is now also refreshed on every `document.log.qsos` change, not only
when the current band's worked set changes — a QSO deleted on another band
changes which multipliers are still needed.

**Drawing.** `spotColor` returns `.secondary` / `.red` / `.blue`; the county
chip on a hub spot tints with the label. The tooltip names the source:
`BALD (your log) — NEW MULTIPLIER`, `MDSN (call history) — already counted`,
`location unknown` for a cluster spot nobody has told us about. The band label
in the panel header carries the legend in its tooltip.

## 2. Automatic Run ⇄ S&P

Pure policy in `Sources/Core/Engine/TuningPolicy.swift`:

```swift
enum TuningPolicy {
    enum Zone { case onFrequency, near, away }
    /// |vfo − cq| ≤ tolerance → onFrequency; ≤ leave → near; else away.
    static func zone(vfoHz: Int, cqHz: Int, toleranceHz: Int, leaveHz: Int) -> Zone
    /// The mode to switch to on a zone change, or nil.
    static func modeChange(from previous: Zone?, to zone: Zone, mode: OperatingMode,
                           leaveEnabled: Bool, returnEnabled: Bool) -> OperatingMode?
}
```

- Entering **away** from anywhere else while in Run, with "leave" on →
  `.searchPounce`.
- Entering **onFrequency** from anywhere else while in S&P, with "return" on
  → `.run`.
- Anything else, including any change with `previous == nil`, → nil.

**Edge-triggered.** Only a zone *change* acts, so ⌘R is never fought: switch
to S&P by hand while sitting on the CQ frequency and you stay there; switch
to Run by hand five kHz away to start a fresh run and you stay there until F1
records the new CQ frequency. A QRM dodge that stays inside the leave-run
distance keeps you in Run; drift within tolerance after coming back keeps you
in Run.

**Wiring (`MainView`).** `@State cqZone: TuningPolicy.Zone?`, set to
`.onFrequency` whenever a CQ frequency is captured (F1 in Run, Repeat CQ
start) and to nil when there is none. One `.onChange(of:
radio.radioState?.frequencyHz)` calls `vfoMoved()`, which runs the zone check
first and the call frame second, so a knob turn that leaves Run can seed the
frame in the same pass. Distances come from the radio's current mode class.
No CQ frequency, no radio → nothing.

**Leaving Run stops Repeat CQ** — automatically or by ⌘R. Today the loop keeps
running through a manual switch and, on its next pass, keys the S&P F1
("my call") instead of the CQ. `RepeatCQPolicy.continues(in:)` says only Run
does; `.onChange(of: document.log.operatingMode)` enforces it. N1MM: "The
function is automatically turned off when no longer on the CQ-frequency and
the mode changed to S&P."

⌘J is unchanged: it tunes to the CQ frequency and sets Run itself.

## 3. The call frame

Only in S&P, only with a radio reporting a frequency, only while the option
is on. In Run the frame is always empty — a caller answering your CQ is on
your own frequency and nobody's spot should land in your row.

**What it holds.** `EntryState.callFrame: Spot?` — the visible spot on the
current band nearest the VFO within the tuning tolerance for the current mode
class, worked or not (N1MM shows dupes in grey so you tune past them faster).
`SpotStore.nearest(in:toKHz:withinHz:workedCalls:workedCallCounties:)` picks it:
superseded spots excluded, ties broken unworked-first then by call. Refreshed
by `vfoMoved()`; cleared when the mode goes to Run, the option goes off, or
the radio disconnects. The visible list is the one ⌘↑/⌘↓ step through, so a
hidden worked station never ghosts.

**How it is drawn.** Ghost text inside the call field while the field is
empty — the spot's call in the band map's colour for it (`bandMapModel.status`),
non-interactive, monospaced like the field. Nothing is drawn while the field
holds anything, typed or filled; N1MM's rule for taking the frame is the same
("When the call-sign textbox is empty").

**Taking it.**

- **Space** in an empty call field with a frame → the call goes into the
  field and the county (when "Offer the spotted county as the exchange" is
  on) into the exchange, through `EntryFlow.stationChanged` exactly as a spot
  click does; focus stays in the call field. With a call already in the field
  Space advances as it always has.
- **Return under ESM** with the cursor in the empty call field and a frame →
  take it, then continue: S&P with the cursor in the call field is
  `sendMessage(0)` — my call — the same message Return sends today on an
  empty row, so one Return both fills the row and calls him. Two things
  deliberately do **not** take the frame: Return from any other field (with
  the county pre-filled the row could be loggable, and the cursor in the
  exchange field is what ESM reads as "I have him"), and Return **without
  ESM** (outside ESM, Return logs). N1MM draws the same line ("or Enter, in
  ESM"); the call field never logs, so taking the frame there is always safe.
- Clicking is not needed; the field is where the keyboard already is.

**Erasing what was taken.** A call the app put in the field — from the frame,
a spot click, or ⌘↑/⌘↓ — is *app-filled*. `EntryState` gains
`callIsAutoFilled` with `callTyped` (the binding the field writes through,
which clears the flag on any change) and `autoFillCall(_:)`, on the pattern of
the exchange, name and member. `EntryFlow` remembers the frequency it filled
at. In S&P, when the VFO moves more than the tuning tolerance from that
frequency and the row holds **no operator text** (`EntryState.hasOperatorText`:
exchange, name or member not auto-filled, a received number, a park, a sent
number override, or a report changed from the default), `EntryFlow.stationLeft`
clears the row — the app's own text only — so the next spot's ghost can show.
Typed text is never touched by tuning; that rule does not change.

`stationChanged` marks the call app-filled; the ⌘↑/⌘↓ and click paths pick
that up with no other change. `stationLeft(_:)` is `stationChanged(to: "")`
under a name that says what happened.

## Settings

All in `AppSettings`, all in the band map's filter popover under a new
**TUNING** heading, after BAND PLAN, and reset by its Reset All:

| Key | Type | Default | Control |
| --- | --- | --- | --- |
| `callFrameEnabled` | Bool | on | "Show the spot under the VFO as a ghost call (S&P)" |
| `autoLeaveRun` | Bool | on | "Leave Run when the VFO moves off your CQ frequency" |
| `autoReturnToRun` | Bool | on | "Return to Run when it comes back" |
| `tuningToleranceHz` | `TuningDistances` | CW 300 · phone 1000 · digital 300 | "Spot within" pickers: 100 · 200 · 300 · 500 · 1000 · 2000 Hz |
| `leaveRunDistanceHz` | `TuningDistances` | CW 1000 · phone 3000 · digital 1000 | "Leave Run at" pickers: 500 Hz · 1 · 2 · 3 · 5 · 10 kHz |

`TuningDistances` (Core, `Codable`, `Equatable`, `Sendable`) holds one Hz
value per `ModeClass` with `hz(for:)`, persisted as JSON under its key. A
leave-run distance smaller than the tolerance is treated as equal to it —
`near` simply never occurs.

**Keyboard.** No chord for the toggles: N1MM's Alt+F11 exists, but these are
set-once preferences outside the operating loop, the case Tom drew the line
at on 2026-07-25 (spot label size). The waiver is recorded here. Space and
Return already carry the frame.

## Files

| Path | Change |
| --- | --- |
| `Sources/Core/Engine/TuningPolicy.swift` | new: `Zone`, `zone`, `modeChange`, `TuningDistances` |
| `Sources/Core/Engine/StationMemory.swift` | `Source.callHistory`; `knownLocation(...)` |
| `Sources/Core/Spotting/SpotStore.swift` | `nearest(in:toKHz:withinHz:...)` |
| `Sources/Core/Spotting/SpotStatus.swift` | new: `SpotStatus` (worked / neededMultiplier / unworked) |
| `Sources/App/RepeatCQPolicy.swift` | `continues(in:)` |
| `Sources/App/EntryState.swift` | `callIsAutoFilled`, `callTyped`, `autoFillCall`, `hasOperatorText`, `callFrame` |
| `Sources/App/EntryFlow.swift` | `refreshPrefill` via `knownLocation`; `stationChanged(to:_:spotCounty:atKHz:)` marks the call app-filled and records the frequency; `stationLeft(_:)`; `updateCallFrame(_:)`; `takeCallFrame(_:) -> Bool`; `tunedAway(toKHz:toleranceKHz:_:)` (the erase rule); Return under ESM takes the frame |
| `Sources/App/AppSettings.swift` | five settings above |
| `Sources/UI/BandMap.swift` | verdict/status + caches; colours; tooltips; legend; TUNING section |
| `Sources/UI/EntryBar.swift` | binds `callTyped`; ghost overlay; Space takes the frame |
| `Sources/UI/MainView.swift` | `radioBar` seam with the radio `onChange`s + `frequencyHz`; `cqZone`; `vfoMoved`; operating-mode change stops Repeat CQ; band map model fed the indexes and the whole log |
| `Sources/UI/MessagesRow.swift` | picker tooltip mentions the automatic switch |
| `README.md` | features (colours, auto Run⇄S&P, call frame), keyboard table (Space / Return), test count |

## Tests (all without hardware or network)

- `TuningPolicyTests` — zone boundaries at exactly the tolerance and the
  leave distance; leave < tolerance; leave from `near` and from
  `onFrequency`; return from `near` and from `away`; no action on
  `away → near`, `onFrequency → near`, same zone, `previous == nil`, wrong
  mode, either toggle off. `TuningDistances` defaults, `hz(for:)`, JSON round trip.
- `SpotStore.nearest` — nearest of several; none outside tolerance;
  boundary inclusive; superseded skipped; tie prefers unworked, then call.
- `StationMemoryTests` — `knownLocation` order: this log, archive, call
  history; `.callHistory` source; nothing known → nil.
- `EntryFlowTests` — Return under ESM with the cursor in the empty call
  field and a frame fills the call and the county and returns
  `.send(index: 0)`; Return from the exchange field, and Return without
  ESM, leave the frame alone; `takeCallFrame` with text in the field does
  nothing; `stationChanged` marks the call app-filled and typing clears the
  mark; `stationLeft` clears app text and never typed text;
  `hasOperatorText` for each field.
- `BandMapStatusTests` — a cluster spot is red via this log, via the archive,
  via the call history; blue when unknown or already counted; grey when
  worked wins over needed; hub county still used as today. `BandMapObservationTests`
  covers the new caches.
- `RepeatCQPolicyTests` — `continues(in:)`.
- `AppSettings` — the five keys round-trip through the redirected defaults.

`MainView`'s wiring — the frequency `onChange`, focus, the ghost overlay — is
verified by build and by Tom on the air, as every view change here is; the
decisions it carries out are all in tested code.
