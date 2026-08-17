# Contest-day fixes (Skeeter Hunt 2026) — design

Date: 2026-08-16. Six items Tom logged while operating the NJQRP Skeeter Hunt,
in his words:

1. "Make shortcuts allowed during calling CQ without canceling"
2. "Make repeat CQ enable setting persistent when leaving RUN and coming back.
   Also, don't start calling CQ when I click the repeat CQ button"
3. "Make sure CW memories are remembered per contest"
4. "Skeeter Hunt points are wrong on the log list" — should be 3 (Skeeter) /
   2 (non-Skeeter QRP) / 1 (QRO)
5. "Make the history calls be included in the callsign lookup helper, not just
   SCP. And highlight the calls that are in the history"
6. "Cmd + shift +/- to change cw speed by 2 wpm, Cmd +/- to change by 1 wpm"

Written without Tom in the room; every choice below is reversible in one place
and named as a choice. Ordered by risk: the scoring display bug first.

## 4. Skeeter Hunt points in the log list

**Cause.** The score sidebar was right (70 points = 22×3 + 2×2): `ScoreEngine`
pays a member-exchange party by what the worked station *is*
(`MemberExchange.workedClass`). The log table's `Pts` column never asked the
engine — `LogTable.pointsText` recomputed each row from
`party.pointsTable(forTheirLoc:)`, which knows modes and locations but not the
member element, so every Skeeter row read 1. That is party-specific scoring
logic living in a view, which the layout table forbids.

**Fix.** The engine records what it paid each row —
`ScoreBreakdown.pointsByRowID: [UUID: Int]` — set in the same loop that adds
to `qsoPoints`, for every first-occurrence, in-scope, allowed-mode row. Dupes,
invalid-mode and out-of-scope rows are simply absent (they earned nothing).
`LogTable` reads that dictionary and nothing else; the party-table
recomputation is deleted. Additive (Article 4): no total changes for any party.

The row helper becomes `nonisolated static LogTable.points(for:score:party:)`
so a test can assert "3 / 2 / 1" against a Skeeter log; the regression test is
proven red against the old recomputation before the fix lands.

## 1. Shortcuts during a repeating CQ

Today `KeyMonitorGate.response` says *every* key down while the loop is
running pauses it and aborts the CQ on the air. That was written for "the
moment you start typing his call you are not talking over him" (N1MM: "stop
repeat CQing by beginning to enter a call-sign, or by hitting Escape"). It
also fires for ⌘= (WPM), ⌘B (band map), ⌘↑/⌘↓ (spots), ⌘/ (hints), ⇧⌘←/→
(VFO), ⌘E, ⌘R, ⇧⌘S — none of which are answering anyone.

**Rule.** A keystroke pauses the loop and aborts the CQ **unless it is a
shortcut**: a ⌘ chord, or F12. Two exceptions inside that:

- ⌘Esc still aborts and pauses (Esc means stop, modifier or not).
- ⌘F1–⌘F8 fall through to the message table today (⌘F2 sends F2); a message
  key must still take the CQ off the air first, so it is not a shortcut.

Everything else — letters, digits, Return, Space, Tab, arrows, Backspace,
Esc, F1–F8 — behaves exactly as before. This is `KeyMonitorGate.isShortcut`,
consulted by `response`; `MainView` is untouched. Sheets keep their rule
(typing in a sheet still pauses; a ⌘ chord in a sheet no longer does).

Choice named: F12 is treated as a shortcut (wipe does not stop the CQ — the
field is empty while the loop runs, so there is nothing to wipe; N1MM lists
only a callsign and Esc as stoppers). Plain arrows and Tab stay conservative
(they pause), since a keystroke inside the entry row means the operator is
working the row.

## 2. Repeat CQ is a mode: arm without keying, survive Run ⇄ S&P

Two changes to `MainView`, both pinned in `RepeatCQPolicy`:

- **The toggle arms; it never keys.** N1MM: "When you first press F1 after
  selecting repeat CQs, an icon will appear … As long as the icon is visible,
  the CQ will repeat" — Alt+R selects the mode, F1 starts it. So clicking
  Repeat CQ on sets `repeatCQ` and nothing else (Article 11: nothing keys the
  radio until an F-key asks). F1, the CQ button, or ESM's Return in Run start
  the loop (`RepeatCQPolicy.onSend` → `.restartLoop`, unchanged). Clicking it
  off cancels the loop; a CQ already on the air finishes, as today. The button
  reads `Repeat CQ ⏸` (orange) while armed and not running — which is now
  also its state right after arming — and its tooltip says so.
- **Only the toggle disarms.** Leaving Run (⌘R, or the knob), a CW ⇄ phone
  mode change, and a disconnect all *pause* the loop and leave the mode
  armed; the old `stopRepeat()` (pause + disarm) is gone. Back in Run, the
  toggle is where the operator left it and F1 resumes. The Repeat CQ button
  is disabled outside Run as before, so an armed-and-paused mode in S&P shows
  greyed `Repeat CQ ⏸`. When F1 is pressed armed but the loop cannot run
  (disconnected, or a phone path not ready), the CQ is sent once and the mode
  stays armed — never a silent disarm.

Choice named: the mode is session state (`@State`), not a preference. Tom
asked for it to survive leaving Run and coming back, not app relaunches; a
preference that made every F1 after launch a loop would be a surprise.

## 3. CW messages remembered per contest

Messages are stored per document (`ContestLog.messages`), so a new log for a
party the operator has already customised starts from the party defaults, and
the work is redone every year. Voice recordings already solved this per party
on disk (`VoiceLibrary`), in the iCloud logs folder when one is chosen. The
message sets go the same way — Tom, same day: "save those in the icloud
folder, same as the voice macros, so I can use them across computers". (A
first cut kept them in `Preferences.store`; it never shipped.)

- `MessageMemory` (App layer): files, one per party — `Messages/<party>.json`,
  pretty-printed and sorted so iCloud syncs and resolves each party on its
  own and a person can read it — in the iCloud folder's `Messages` subfolder
  beside `Voice` when a folder is chosen (`CloudMirror.activeFolder()`,
  re-evaluated at every use), else `~/Library/Application Support/
  QSOPartyLogger/Messages`. `messages(for:)`, `remember(_:for:)` (throws),
  `forget(_:)`, and `adoptSets(from:)` — the recordings' rule: sets saved on
  this Mac before a folder was chosen move into it once, whole, never
  overwriting a set the folder has. Adoption is an explicit step
  (`adoptThisMacsSetsIfNeeded`, called by `MainView` on appear and right after
  the folder is chosen), never a side effect of reading the folder, so no
  test can move real files. `init(folder:)` for tests; a not-yet-downloaded
  iCloud placeholder is asked for on read.
- `LogDocument.messageMemory: MessageMemory?` — `@ObservationIgnored`, nil by
  default so a document built in a test remembers nothing and no test can
  pollute another; `MainView` wires `.standard` on appear, before Contest
  Setup can run. A write failure is logged, never blocking the Save (the set
  is in the log file regardless).
- **Write:** `LogDocument.updateMessages` (the editor's Save, and its undo)
  remembers the set under the log's party. Restore Defaults + Save therefore
  remembers the defaults, which is the same as forgetting.
- **Read:** `LogDocument.updateStation` already replaces an *untouched* set
  with the new party's defaults. Now "untouched" means equal to the old
  party's defaults **or** to the old party's remembered set (this log's own
  edits, already banked under the old party), and the replacement is the new
  party's remembered set, falling back to its defaults. A set that matches
  neither is the operator's and is left alone, exactly as before. Undo is
  already an exact restore of the old set.
- Whole `MessageSets` is remembered (CW text and the phone memory mapping and
  names) — the phone mapping is as much a per-party habit as the text, and
  the recordings it names are already per party.

Opening an existing log never consults the memory: that log's set is that
log's intent. The Messages editor's caption gains "and remembered for this
party — a new log for it starts from the set you saved last".

## 5. Call history in the super check strip

N1MM's Check window draws from four sources — the log, master.scp, telnet
spots and the call history file — in separate panes. This app has one strip;
the call history file (for the Skeeter Hunt, the roster of Skeeter numbers)
joins the SCP database in it, marked.

- `SuperCheck.matches(fragment:scpCalls:historyCalls:limit:)` (Core) is the
  one ranking implementation: exact call, then calls starting with the
  fragment, then the rest containing it; **within a tier, history calls
  first**, alphabetical after that. Each `Match` carries `inHistory`, and the
  result carries `scpTotal`, `historyTotal` and the union `total` for the
  "+N more" arithmetic. `SCPDatabase.matches` delegates to it, so its tests
  keep passing.
- `EntryFlow` keeps a sorted list of the active party's history calls,
  recomputed when `callHistoryIndex` is set (once per download, never per
  keystroke), and merges it into `scpMatches`. The strip is live when SCP is
  on and either source is loaded, so a cached roster shows before MASTER.SCP
  lands.
- `SuperCheckRow`: **bold = exact match; teal = in the call history**; SCP-only
  calls stay secondary; the exact SCP-only call stays green. Label reads
  `SCP n` and, when any, `HIST m` in teal. Weight carries "exact" so the cue
  never rests on colour alone.

Choice named: "history" is read as the N1MM call history file (the app's own
term, and the roster is exactly what a Skeeter Hunt operator wants to see),
not the contest archive. The archive is a candidate third source later.

## 6. CW speed keys

`KeyMonitorGate.commandAction`: `=` / keypad `+` and `-` / keypad `-` with ⌘
give ±1 WPM; with ⇧ as well, ±2. (⇧⌘= is how `+` arrives on the keyboard.)
Legend, WPM tooltip and README follow: `⌘= ⌘-` WPM ±1, `⇧⌘= ⇧⌘-` ±2.

## Testing

Every rule is a pure function with a test: `KeyMonitorGate.isShortcut` and
the response table (a ⌘ chord during a loop neither pauses nor aborts; ⌘Esc
and ⌘F2 still do; letters still do), `RepeatCQPolicy` (arming keys nothing;
interruptions pause and keep the mode), `ScoreBreakdown.pointsByRowID` on a
Skeeter log (3/2/1) and the `LogTable` row helper (red first), `MessageMemory`
round trip and `LogDocument` party-change reads/writes with a scratch memory,
`SuperCheck` ranking and totals, `EntryFlow` merge on a late history, and the
WPM chords. Docs (README features, keyboard table, test count) ship in the
same commits.
