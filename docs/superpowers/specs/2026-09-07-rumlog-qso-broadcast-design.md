# Sending QSOs to RUMlogNG as they are logged — design

**Date:** 2026-09-07 · **Status:** approved for implementation (autonomous
session — the open calls in §9 default as stated; Tom evaluates the build)

KE5CW keeps his station logbook in RUMlogNG. Every QSO party ends the same
way: export the contest's ADIF, open RUMlogNG, import it, dedupe. The
request: **broadcast each QSO to RUMlogNG as it is logged**, so the contest
files never need importing by hand.

RUMlogNG's Preferences › UDP pane (screenshot, 2026-09-07) offers two ways
in: *QSOs received from N1MM* (port 12060) and *QSOs received from Flex /
ADIF* (port 2237), each with a *Save QSO* popup. This design uses the first.

## Sources

Every byte on the wire traces to the protocol owner's own page, fetched
2026-09-07 and banked in
[`docs/research/n1mm-udp-contactinfo.md`](../../research/n1mm-udp-contactinfo.md)
in the same commit as the behaviour (constitution rule 1).

- **N1MM Logger+ documentation, "External UDP Messages"**
  (`n1mmwp.hamdocs.com/appendices/external-udp-broadcasts/`). Defines the
  `contactinfo`, `contactreplace` and `contactdelete` packets field by field:
  one UTF-8 XML document per datagram, default port **12060**; `rxfreq` /
  `txfreq` *"in units of 10 Hz"*; `band` *"composed of 2 or 3 characters"*
  with *"80 meters may be "3.5" or "3,5"; 160 meters as "1.8" or "1,8""*;
  `timestamp` `2020-01-17 16:43:38`; `ID` *"a 32 byte unique GUID identifier
  for each contact in the log … sent as 2 hex characters per byte"*;
  *"When a user edits an existing contact record, the program will send a
  pair of UDP packets: A <contactdelete> packet, followed by a
  <contactreplace> packet."*; `oldtimestamp` / `oldcall` *"indicate the time
  and callsign that were originally logged before editing"*; `IsOriginal`
  *"indicates that this is the station on which this contact was initially
  logged"*; `SentExchange` *"is the contents of the Sent Exchange box"*;
  *"the Section field … means whatever the rules for the particular contest
  define it to mean"*. Destination addressing: *"To send them to a program
  running on this PC, use the address 127.0.0.1 … To send them to all PCs
  on this subnet, enter 255 as the last number (octet)"*.
  The page prints `<exchangel>` and `<ismultiplierl>` with a letter *l*;
  its siblings are `ismultiplier2` / `ismultiplier3`, and the N1MM–DXKeeper
  gateway's help names *"N1MM's Exchange1 field"*, so the app emits the
  digit: `exchange1`, `ismultiplier1`.
- **RUMlogNG documentation, "Functions in the local network"**
  (`dl2rum.de/RUMlogNG/docs/en/pages/Networking.html`): *"RUMlog can
  communicate with third party applications or other RUMlog instances in the
  local network … Zwo different, not compatible protocols are supported:
  Fldigi compatible; N1MM and TR4W compatible. For the data exchange between
  multiple RUMlog applications, the N1MM protocol will be used."*
- **RUMlogNG version history** (`…/pages/OlderHistory.html`): **5.0,
  20-September-2020** — *"Real time import from from other loggers in N1MM
  format. (I.e. Flex Radio logbook)"* and *"Real time import from from
  N1MM"*; **5.15.3, 6-February-2024** — *"Function in the QSO contextual
  menu to resend QSOs via UDP or tcp/ip to connected clients"*. The 6.5.1
  release (2026-09-05, machamradio.com) adds `my_gridsquare` to RUMlogNG's
  own N1MM contact broadcast.
- **DL2RUM on his forum, 23 May 2021** (`dl2rum.de/forum/viewtopic.php?t=1425`):
  *"RUMlog can broadcast all logged QSOs over the network."* with a tcpdump
  of the packet RUMlogNG itself sends — a `contactinfo` with **no `app`
  element**, `IsOriginal` `YES`, `band` `24` for 12 m, `txfreq` `2489800`,
  `continent` `Eu`, and a trailing `<dxcc>230</dxcc>`. It is the only
  first-hand example of what RUMlogNG considers "N1MM format", and it is
  looser than N1MM's own: absent elements and extra ones are both in play.

Not consulted for any wire byte: other loggers' source code, forum guesses,
model recall.

---

## 1. Approaches considered

1. **N1MM `contactinfo` over UDP to RUMlogNG's N1MM listener** *(chosen)*.
   Every mutation of the log has a packet: `contactinfo` on logging,
   `contactdelete` on delete, `contactdelete` + `contactreplace` on edit —
   N1MM's own sequence, so RUMlogNG's log follows the contest log through
   corrections, not just additions. The format is documented by its owner
   field by field, RUMlogNG names it as its import format, and every other
   N1MM-compatible listener on the LAN (Log4OM, DXKeeper's gateway,
   qsorder, MacLoggerDX) gets the same feed for free.
2. **ADIF records to RUMlogNG's Flex / ADIF listener on 2237.** Reuses
   `AdifExporter` byte for byte. Rejected: the format on that port is
   documented nowhere citable (RUMlogNG's history names it only as "Flex
   Radio logbook"), and a plain ADIF record has no delete or replace, so an
   edit or a ⌘Z in the contest log would leave a wrong QSO in the station
   log with nothing to say so.
3. **Automatic ADIF file drop** into a folder RUMlogNG watches. Rejected:
   RUMlogNG has no watched-folder import; it would still be an import.

## 2. What the operator sees

A **RUMlog** toolbar button (paper plane; filled while sending is on) opens
a popover:

- **Send QSOs as they are logged** — the toggle. Off by default: a logger
  must never start talking to another program unasked.
- **Host** and **Port** — `127.0.0.1` and `12060` by default, RUMlogNG on
  this Mac. Another Mac's address or a subnet broadcast (`192.168.1.255`)
  works too; macOS asks for Local Network permission the first time.
- A **status line**, inline, in the popover — never a modal (feedback
  memory: inline status over alerts): *Off*, *Ready — 127.0.0.1:12060*,
  *Sent W0BH 14:32:05 · 12 this session*, *Sending 143 of 2,012…*, or
  orange *Could not resolve rumlog.local* / *Send failed: No route to host*.
  UDP has no acknowledgement, so the line says what left the Mac, never
  that RUMlogNG took it; the popover says so.
- **Send Whole Log Now** (⇧⌘L) — every row of this log, oldest first, as
  fresh `contactinfo` packets, paced. The catch-up for a log made before the
  toggle was on, a RUMlogNG that was not running, or a doubt. While it runs
  the button reads **Stop** and the status counts.
- A caption with RUMlogNG's side of it: *Preferences › UDP › QSOs received
  from N1MM: Save QSO, port 12060.*

Nothing else in the window changes. Logging, editing and deleting look
exactly as before; the packets leave in the background.

## 3. Architecture

Three units, each testable alone, wired by the window:

```
LogDocument ──QSOChange──▶ QSOBroadcaster ──packets──▶ UDPSending (socket)
   (funnel)                 (App: queue,       ▲
                             pacing, status)   │ builds
                                     N1MMContactBroadcast (Core: pure XML)
```

### 3.1 `QSOChange` — the document's mutation seam (Core/Models)

```swift
enum QSOChange: Equatable, Sendable {
    case added([QSO])
    case removed([QSO])
    case replaced([Replacement])          // struct Replacement { old, new }
}
```

`LogDocument` gains `@ObservationIgnored var qsoObserver: ((QSOChange) -> Void)?`
and calls it at the end of its four row mutations — `append`, `remove`,
`update(qso:)`, `update(qsos:actionName:)` — with the rows the mutation
actually touched. Undo and redo re-enter those same functions, so a ⌘Z of
a logged contact is a `.removed` and a ⌘Z of a delete is an `.added`, with
no extra code. Loading a document sets `log` directly and fires nothing:
opening a file must not re-send 2,000 contacts.

### 3.2 `N1MMContactBroadcast` — the packets (Core/Export)

Pure functions on `(QSO, ContestLog, ContestDefinition)` → XML `String`,
next to `AdifExporter` and reading the contest the same way (rule 10: the
engine is the model; a party reaches here lowered). No socket, no clock, no
host name of its own — the caller passes `StationContext` (station name,
`now` is never needed: every packet carries the row's own time).

| Element | Value | Why |
| --- | --- | --- |
| `app` | `N1MM` | RUMlogNG 6.5.1 saves a contact only when the element is exactly `N1MM` — verified 2026-09-07 against the running app (see the research bank); the first build's `QSOPartyLogger` was dropped silently |
| `contestname` | `contest.cabrillo.contest` (`KS-QSO-PARTY`) | the sponsor's own token, what ADIF `contest_id` already carries |
| `contestnr` | `1` | opaque per-database counter in N1MM; one contest per log here |
| `timestamp` | `yyyy-MM-dd HH:mm:ss` UTC | N1MM's example, and N1MM logs in UTC |
| `mycall` | the log's callsign, upper case | |
| `band` | `1.8` `3.5` `5.3` `7` `10` `14` `18` `21` `24` `28` `50` `144` `222` `420` | the band's lower edge in MHz, one decimal below 7 MHz — N1MM's "3.5"/"1.8", RUMlogNG's own "24" for 12 m; always a period, since the delimiter is N1MM's Windows locale, not a rule |
| `rxfreq` `txfreq` | kHz × 100 — 14042 kHz → `1404200` | "units of 10 Hz"; a row logged without CAT sends the band's `defaultFreqKHz`, the rule Cabrillo already uses |
| `operator` | `mycall` | what ADIF `operator` carries |
| `mode` | `CW`, `USB`/`LSB`, `RTTY`, … | N1MM's vocabulary has no `SSB`: a row logged as `SSB` resolves to the band's conventional sideband at its frequency (`BandPlan.sidebandRawMode`, the same rule the radio path uses); every other raw mode upper-cased verbatim |
| `call` | upper case | |
| `countryprefix` `continent` `dxcc` | from `CTYTable` for the worked call; empty / absent when cty has no match | `dxcc` is RUMlogNG's own trailing element |
| `wpxprefix` | `WPXPrefix.of(call)` | |
| `stationprefix` | `mycall` | N1MM's example shows the station's own call |
| `snt` `rcv` | the row's RSTs | |
| `sntnr` `rcvnr` | serials, `0` when the exchange has none | N1MM's example: `<rcvnr>0</rcvnr>` |
| `gridsquare` | received `grid` element, else the callbook stamp's grid, else empty | |
| `exchange1` | the received `location` token (county / state / DX) for a party; for a general contest the received values of its token elements in exchange order, space-joined | N1MM's Exchange1 is "the exchange" beyond RST, serial, name and section |
| `section` | received `section` element or empty | "whatever the rules define" — SS/FD sections |
| `comment` | the QSO's UTC date and the contest's name, the exchange each way as the log table shows it, then the row's note: `2026-09-07 Kansas QSO Party · Sent 599 TX · Rcvd 599 DEC · long path` | RUMlogNG's Note is filled from `comment` and from nothing else, and it has no contest field (marker probe, 2026-09-07 — research bank) |
| `qth` | the callbook stamp's QTH or empty | |
| `name` | received `name`, else the callbook stamp's name | the same precedence ADIF uses |
| `power` | received `power` element; else the member-or-power element when it is a power (`5W`) | "received power exchange from the other station" |
| `misctext` | empty | |
| `zone` | received `cqZone`, else `ituZone`, else `0` | "often means the same as CQZ … in some contests ITUZ" |
| `prec` `ck` | received precedence / check, empty / `0` | |
| `ismultiplier1` | `1` when the engine credited a new multiplier to this row, else `0` | `ScoreBreakdown.newMultRowIDs`, supplied by the window's `LiveScore` |
| `ismultiplier2` `ismultiplier3` | `0` | |
| `points` | the engine's points for the row, `0` for a dupe or an unscored row | `ScoreBreakdown.pointsByRowID` |
| `radionr` `run1run2` | `1` | single radio |
| `RoverLocation` | empty | |
| `RadioInterfaced` | `1` when the row has a CAT frequency | |
| `NetworkedCompNr` | `0` | |
| `IsOriginal` | `True` | this Mac logged it |
| `NetBiosName` | empty | |
| `IsRunQSO` | `1` when the row's posture is Run | |
| `StationName` | this Mac's name (`Host.current().localizedName`) | "the netbios name of the station that sent this packet" |
| `ID` | the row's UUID as 32 lower-case hex characters | "32 byte unique GUID … 2 hex characters per byte" — stable across delete/replace, so the receiver can match |
| `IsClaimedQso` | `1` | |
| `oldtimestamp` `oldcall` | the replaced row's time and call in a `contactreplace`; the row's own in a `contactinfo` | N1MM's rule verbatim |
| `SentExchange` | my sent exchange as the row carries it, non-RST non-serial elements in exchange order (`BOU`, `TOM TX`, `TX 13`) | "the contents of the Sent Exchange box" |
| `my_gridsquare` | the station's grid locator, empty when unset | RUMlogNG 6.5.1's own extension |

`contactreplace` is the same body under `<contactreplace>`. `contactdelete`
carries exactly N1MM's eight elements: `app`, `timestamp`, `mycall`,
`band`, `call`, `contestnr`, `StationName`, `ID` — built from the row being
removed, or the *old* row of an edit, as N1MM's note requires.

Text is XML-escaped (`&`, `<`, `>`, `"`, `'`); elements are emitted in
N1MM's order, one per line, tab-indented, under
`<?xml version="1.0" encoding="utf-8"?>`. A packet for the log's row is
byte-pinned in the tests, the way the exporters are.

`packets(for: QSOChange)` turns a change into the ordered packet list:
`.added` → one `contactinfo` per row; `.removed` → one `contactdelete` per
row; `.replaced` → per pair, `contactdelete(old)` then
`contactreplace(new, old:)`.

### 3.3 `QSOBroadcaster` — the sender (App)

`@MainActor @Observable final class QSOBroadcaster`, one per log window
like the spot clients:

- `configure(enabled:host:port:)` — the window pushes the preference on
  appear and on change. Turning off closes the socket and clears the queue;
  a changed host or port closes it, and the next packet reopens.
- `handle(_ change: QSOChange, log:, contest:, scoring:)` — builds the
  packets and enqueues them. Nothing happens while off: the closure that
  reads the engine's fold is never called, so a disabled broadcaster costs
  a disabled feature's nothing.
- `sendWholeLog(log:contest:scoring:)` — enqueues a `contactinfo` for every
  row, chronological. A second call while one runs **stops** it (the
  button's *Stop*).
- **One paced queue** for both: a drain task sends one datagram, then
  sleeps `pacing` (5 ms; 0 in tests), so a 2,000-row resend or a 300-row
  bulk edit cannot overrun a receiver's socket buffer, and a live contact
  still leaves within milliseconds.
- **Socket**: `UDPSending`, the protocol the Flex DAX path already sends
  through, opened lazily by an injectable `makeSender(host, port)`
  (`UDPSender` in production; a recorder in tests). `UDPSender` gains
  `SO_BROADCAST`, so `x.x.x.255` — the addressing N1MM documents — is
  sendable; the connected-socket design is otherwise unchanged and the
  Flex path is untouched.
- **Status** (`Status`, `Equatable`): `.off`, `.ready(destination)`,
  `.sent(count:, lastCall:, at:)`, `.sending(done:, total:)`,
  `.failed(String)`. A failed `open` clears the queue and reports the
  error's own words; a refused `send` (the kernel's errno from
  `sendFailures`) is reported and the queue keeps going, since one refused
  datagram says nothing about the next.

### 3.4 Wiring in `MainView`

- `onAppear`: `broadcaster.configure(…)` from `AppSettings`; `document.qsoObserver`
  → `broadcaster.handle(change, log: document.log, contest:
  ContestCatalog.contest(id:), scoring: liveScore's fold)`. The scoring
  closure reads `liveScore.breakdown` — the fold the window is about to do
  for the table anyway, keyed on the same generation, so it costs no
  second fold (the 2026-08-30 discipline holds).
- `.onChange` of the three preferences → `configure`.
- Toolbar button + `QSOBroadcastPane` popover (`Sources/UI/`, no
  party- or radio-specific branching).
- `KeyMonitorGate.Action.sendLogToRUMlog` on ⇧⌘L; `perform` calls
  `sendWholeLog`; `KeyDiagnostics` names it; `ShortcutLegend` lists it.

### 3.5 Preferences (`AppSettings`)

`qsoBroadcastEnabled` (false), `qsoBroadcastHost` ("127.0.0.1"),
`qsoBroadcastPort` (12060) — machine-level like the cluster host, under
their own keys; an out-of-range stored port falls back to 12060 rather
than to nothing.

## 4. Data flow, end to end

1. Return logs `W0BH` on a county line → `EntryFlow` → `document.append(rows)`.
2. `append` mutates `log` (generation bumps), registers undo, calls
   `qsoObserver(.added(rows))`.
3. The window's observer resolves the contest and hands the broadcaster
   the change with a scoring closure.
4. The broadcaster (on) builds two `contactinfo` packets, enqueues them,
   and the drain task sends them 5 ms apart through the socket.
5. RUMlogNG's N1MM listener saves two QSOs. Edit one in the log table →
   `update(qso:)` → `.replaced` → `contactdelete` then `contactreplace`.
   Press ⌘Z → `update(qso: old)` → the same pair the other way round.

## 5. Error handling

- Off: nothing opens, nothing is built.
- Bad host: `open` throws → `.failed("Could not resolve …")`, queue
  dropped, next change tries again (cheap, and the operator has had a
  chance to fix the field).
- Send refused (no route, Local Network denied): `.failed("Send failed:
  …")` with `strerror`, sending continues.
- RUMlogNG not running: UDP cannot tell; the status honestly says *sent*.
  The popover's caption says that a *sent* is what left this Mac, and
  **Send Whole Log Now** is the remedy.
- Never a modal, never a claim of delivery.

## 6. Testing

All without a network: the socket is a recorder.

- `N1MMContactBroadcastTests` (Core): a KSQP county row pinned byte for
  byte; serial rows (CQP); name (NAQP); member/power (Skeeter); section,
  precedence, check, zone (a general contest); every band's token; the
  10 Hz units and the no-CAT fallback; `SSB` → sideband by frequency; XML
  escaping; ID format; `IsRunQSO`; points and `ismultiplier1` from the
  scoring; the callbook fallbacks; `contactreplace` with `oldcall` /
  `oldtimestamp`; `contactdelete`'s eight elements; `packets(for:)` order.
- `LogDocumentTests`: the observer fires with exactly the rows touched by
  `append`, `remove`, `removeGroup`, `update(qso:)`, `update(qsos:)`; undo
  fires the inverse; loading fires nothing.
- `QSOBroadcasterTests` (App): off sends nothing and opens nothing; on
  opens lazily with the host and port; one datagram per packet in order;
  an edit is delete-then-replace; the whole-log send is chronological,
  counts in the status, and stops on the second call; host change
  reopens; open failure reports and drops; send failure reports and keeps
  going; turning off closes.
- `KeyMonitorGateTests`: ⇧⌘L maps, ⌘L and plain L do not.
- `QSOBroadcastPreferenceTests`: defaults, keys, the port fallback.
- `ShortcutHintsTests`: the legend lists ⇧⌘L.

Unverified by test, by design: `SO_BROADCAST` to a real `x.x.x.255`, and
RUMlogNG's acceptance — Tom tries the build against his RUMlogNG.

## 7. Documentation (same commit)

README: a *Sending QSOs to RUMlogNG* section under *Files and export*, the
⇧⌘L row in the keyboard table, the test count. `docs/PROVENANCE.md`: the
N1MM page and RUMlogNG's own words. `docs/research/n1mm-udp-contactinfo.md`:
the banked text. `project.yml` / `Resources/Info.plist`: the Local Network
usage string names RUMlogNG.

## 8. Out of scope (deliberately)

- The Flex / ADIF listener (2237), RUMlogNG's Fldigi protocol, radio and
  spot broadcasts (`RadioInfo`, `spot`), and `AppInfo` — none moves a QSO.
- Sending an *archived* log from the dashboard: open it and press ⇧⌘L.
- Listening for anything back: UDP has no reply, and RUMlogNG documents none.

## 9. Open calls, defaulted

1. ~~**`app` says `QSOPartyLogger`, not `N1MM`.**~~ **Overturned by
   experiment, 2026-09-07:** RUMlogNG 6.5.1 dropped the packet silently and
   saved the identical packet with `N1MM`; N1MM's `contactdelete` removed
   it again. The element says `N1MM`.
2. **`contestname` is the Cabrillo name.** N1MM's own tokens (`KSQP`) are
   not published as a list; the sponsor's token is at least citable.
3. **⇧⌘L** for *Send Whole Log Now* — free in the gate, no AppKit meaning
   in a log window.
4. **5 ms pacing.** 2,000 rows in ten seconds; a receiver's default socket
   buffer holds far fewer 1.2 KB datagrams than that burst would produce
   unpaced.
5. **Rows are sent whether or not they score** — a dupe is still a contact
   made, and RUMlogNG's dedupe is its own.
