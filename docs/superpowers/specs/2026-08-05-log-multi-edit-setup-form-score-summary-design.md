# Log multi-edit, Setup form repair, score summary copy — design

**Date:** 2026-08-05 · **Status:** approved for implementation

Three independent operator-facing changes, requested together. One commit each,
so a regression bisects to one of them.

## Sources

- N1MM Logger+ manual, *The Log Window*
  (`https://n1mmwp.hamdocs.com/manual-windows/log-window/`, fetched 2026-08-05)
  — multi-row selection and the five bulk change types.
- N1MM Logger+ manual, *The Score Window*
  (`https://n1mmwp.hamdocs.com/manual-windows/score-window/`, fetched
  2026-08-05) — the right-click menu, verbatim: "Copy all", "Print to file",
  "Help", "Display Contest Name". "Copy all" is described as "Copy all info to
  the Windows Clipboard"; "Print to file" writes `call-sign.SUM`.

**Known gap, stated rather than papered over:** the manual does not transcribe
the Score window's own screenshot, and no byte-exact sample of what "Copy all"
puts on the clipboard was reachable. The column layout in §3 is therefore a
**reconstruction of the window's shape**, not a transcription of N1MM's bytes.
It is a convenience format for pasting into a summary email or 3830, not a
scoring rule — nothing depends on it being byte-identical, and matching a real
sample later is a change to one formatter.

---

## 1. Multi-select and bulk edit in the log

### Selection

`LogTable.selection` becomes `Set<QSO.ID>`. `Table` then provides shift-click
ranges, ⌘-click for non-consecutive rows, shift-arrow extension and ⌘A — the
same selection model the N1MM Log window documents ("clicking the first entry,
then holding Shift and clicking the final item… Ctrl+Click enables
non-consecutive selections"), and a complete keyboard path without inventing
one.

### Context menu, branching on count

- **One row selected** — unchanged from today: `Edit…`, `Spot <call> to QSO
  Party Hub…`, `Delete Row`, and `Delete Contact Group (×N)` where the row
  belongs to a county-line group.
- **Two or more** — `Edit N Contacts…` opens the bulk sheet, `Delete N Rows`
  deletes the selection in one undoable step. Hub spotting stays single-row:
  it posts one station.

`primaryAction` (double-click / Return) keeps opening the single-row editor,
and only when exactly one row is selected.

### The bulk sheet

One field, one value, applied to every selected row. Fields offered:

| Field | Control | Shown when |
| --- | --- | --- |
| Band | picker over `party.validBands` | always |
| Mode | picker over `RadioBar.rawModes(for:)`; also sets `modeClass` | always |
| My exchange | text, validated through `ExchangeParser` at the log's role | always |
| Name sent | text | `party.exchangeIncludesName` |
| *member term* sent | text, validated with `MemberExchange.parse` | `party.memberExchange != nil` |

Their-side fields — `theirLoc`, `nameRcvd`, `serialRcvd`, `rstRcvd` — are
deliberately absent. They are per-station facts; there is no single correct
value across fifteen different stations. N1MM's five bulk types (operator,
mode, frequency, station name, X-QSO status) are all station-side or
administrative for the same reason.

Validation runs **before anything is written**, exactly as `EditQSOSheet.save()`
does: a My-exchange value must parse for this party and role and resolve to
exactly one location. A rejected value leaves the log untouched and states why
inline.

### County-line guard

`CountyLineExpander` expands one on-air contact into the cartesian product of
my location(s) × their location(s). A group logged while straddling a line
therefore holds rows that differ **only** in `myLoc`. Bulk-setting My exchange
across them would mint literally duplicate rows, which the dupe checker then
flags — the app creating the defect it exists to catch.

So for a **My exchange** change, a row is written only when its group is a
single row, or when the whole group is selected *and* already carries one
location — in which case the rows stay distinct by what the other station sent.
Two cases are therefore excluded:

- a group holding two of my counties (collapsing it mints duplicates);
- a **partly selected** group, which is the case the first rule alone misses —
  changing half of one contact's rows leaves that contact claiming two of my
  locations. This is why the partition reads the whole log rather than the
  selection: a group's other rows are exactly what the selection may be missing.

The sheet names the excluded count before Apply is enabled ("3 county-line rows
are left unchanged — edit those individually"). Band, mode and the sent elements
are shared by every row of a group, so they carry no such exclusion.

### Undo

New `LogDocument.update(qsos:actionName:undoManager:)`: one mutation, one undo
registration, action name "Change N Contacts". One ⌘Z reverts the whole bulk
change. Reusing the existing single-row `update(qso:)` N times would demand N
presses, which is the wrong shape for an operation whose whole purpose is to
touch N rows at once.

### Tests

- Band, mode and My-exchange bulk changes apply to every selected row.
- A My-exchange value the party rejects writes nothing.
- A multi-row group with differing `myLoc` is excluded from a My-exchange
  change, and its rows keep their values.
- One undo restores every row of a bulk change.

---

## 2. Contest Setup: field layout and case

### Diagnosis

Two separate causes, both already understood in this file's own comment at
`SetupSheet.swift:226` and never applied to the station rows:

1. In a grouped `Form`, a **titled** `TextField` has its title hoisted into the
   leading label column, so `.frame(width: 70)` sizes *label and field
   together*. That is why "State" wraps to `Stat`/`e` and leaves a borderless
   sliver, and why "Grid square" at width 110 wraps to two lines.
2. `.textCase(.uppercase)` on a Form row styles **the label as well as the
   field**, which is why `CALLSIGN` and `GRID SQUARE` shout while `Name` and
   `Email` do not.

### Layout

City/State/ZIP becomes one `LabeledContent("City / State / ZIP")` holding three
`.roundedBorder` fields, with widths on the controls alone; Country/Grid the
same. The label leaves the Form's label column, so nothing wraps and every
field has a visible target.

### Case

Every field switches from display-only `.textCase(.uppercase)` to the real
`.uppercasing` binding — callsign, name, address, city, state, ZIP, country,
grid locator, club, operators, and the **My Location** token (`$stateToken`,
today display-only at line 238, so what is stored keeps whatever case was
typed). `exchangeName` and `exchangeMember` already fold correctly.

**Email is excluded.** It is the one header a sponsor may machine-read back to
the entrant, and the local part of an address is case-sensitive by RFC 5321
even though most hosts ignore that.

### Testable guarantee

A binding is a typing affordance; the constitution's rule 7 wants a test, and
a `View` is not one. So `save()` routes through a new
`StationProfile.normalized()` in Core — trims every field, uppercases all but
email — and that function carries the test. This also normalises profiles
loaded from logs written before this change.

### Tests

- `normalized()` uppercases every field it should and leaves email verbatim.
- Whitespace is trimmed on every field.
- An already-normalised profile is unchanged (idempotent).

---

## 3. Score summary copy

### Where the logic lives

`Sources/Core/Export/ScoreSummaryText.swift`, a pure function:

```swift
static func make(
    log: ContestLog, party: PartyDefinition?,
    score: ScoreEngine.ScoreBreakdown, members: [PartyDefinition]
) -> String
```

Formatting in Core, beside Cabrillo and ADIF, means golden-string tests. The
sidebar only puts the result on the pasteboard.

### Shape

Band rows × mode columns, then the score components — the Score window's shape:

```
KE5CW — Kansas QSO Party

 Band    CW    PH   Dig   QSOs
   80    12     4     0     16
   40    31    18     0     49
   20     8    22     0     30
Total    51    44     0     95

QSO points     190
Multipliers     45
Bonus          +50
Score        8,600
```

Mode columns come from `party.allowedModeClasses`; rows from
`ScoreEngine.bandModeCounts`, which already excludes dupes, wrong-mode and
out-of-scope rows. Columns are right-aligned and fixed-width.

Conditional lines append exactly as the sidebar shows them, and for the same
reasons:

- the member / QRP / QRO split where `party.memberExchange` exists (the
  Skeeter Hunt's summary email asks for those three counts);
- `Category ×` where `categoryFactor` is not one;
- `Dupes` where any exist.

An empty log still produces the header and a zero score, rather than an empty
clipboard that reads as a failed copy.

### Surfaces

- Right-click the totals card → `Copy Score Summary`, written with
  `NSPasteboard.general` (`clearContents()` then `setString(_:forType: .string)`).
- **⇧⌘C**, via the same hidden-button pattern ⇧⌘M already uses at
  `ScoreSidebar.swift:307` — constitution rule 9, every feature has a keyboard
  path.
- README keyboard table gains the row in the same commit.

### Tests

Golden strings for: a single-mode party, a two-mode party, a member party with
the three-way split, and an empty log.

---

## Out of scope

- X-QSO / checklog marking of individual rows. N1MM offers it as a bulk change;
  this app has no such flag, and inventing scoring state is not a UI commit.
- Bulk editing received exchange elements (see §1).
- Matching N1MM's clipboard bytes exactly (see *Sources*).
