# The Logs Are the History — Design

**Date:** 2026-08-17 · **For:** KE5CW · **Status:** approved (Tom, in
conversation: "I like #2 the logs being the history. If delete just means
deleting a log file, then don't add that to the UI. User can just delete the
file themselves.")

## What Tom asked for

> rethink the contest history log file. today it's in json format, but after
> dozens of contests get accumulated it will get bloated. Design a better way
> of tracking these with scale and simplicity in mind. Also consider that
> multiple instances of the app will be accessing over shared icloud folder.
> Also let me delete entries — some are still stuck in there from testing and
> tainting my history.

and, on the first proposal (a `History/` folder of per-contest files):

> Won't this mean there will be a bunch of files in the working directory?
> How could we make the working directory file structure simpler and easier
> to understand?

## What was there, measured

`Contest History.qphistory`: one JSON file in the iCloud logs folder holding
every archived contest *with every QSO row* plus a score snapshot — **156 KB
for 5 contests / 279 QSOs** on 2026-08-17, rewritten and re-uploaded whole
on every 2-second save pause. Two Macs writing one file forced a QSO-level
union merge, which is why 12 QSOs Tom deleted from his Skeeter Hunt log
still counted in its archived score (log 83, archive 95), and why nothing
could ever be deleted: any stale copy merged it back. The `tqp 2026` test
entry was stuck because its `.qplog` was long gone but the archive was not.

The `.qplog` files are already the source of truth for everything else:
Return/⌘E/⇧⌘E open and export the saved log, never the archive's copy. The
archive's QSO rows had one consumer, `StationMemory.Index` (exchange
pre-fill, "worked before", band-map colours).

## Approaches considered

- **A. `History/` folder of per-contest files** (built first this session,
  then set aside): fixed the growth, kept a shadow copy of every log beside
  the logs, and needed last-save-wins resolution, tombstones and a migration.
  Tom's objection — "a bunch of files in the working directory" — is
  correct: every contest existed twice.
- **B. The logs are the history — chosen.** No second store at all. The
  dashboard reads the `.qplog` files in the logs folder. Each log carries
  its own score snapshot, written at save time, so a past season's score
  stays frozen when next year's rules land. Deleting a log deletes the
  entry; there is no in-app delete.
- **C. SQLite** — a database inside a file-sync folder: rejected as before.
- **D. One summary file** — still one shared file with merge semantics.

## The design

### The folder

```
QSOPartyLogger/                       ← the iCloud logs folder Tom chose
├── 2026-08-01 NAQPCW KE5CW.qplog     ← the history *is* these files
├── 2026-08-15 NAQPSSB KE5CW.qplog
├── 2026-08-16 SKEETER KE5CW.qplog
├── Messages/                          (per-party F-key sets — unchanged)
└── Voice/                             (per-party recordings — unchanged)
```

Nothing new is written. `Contest History.qphistory` is no longer read or
written by the app; it is left where it is for Tom to delete when he likes
(the app never deletes user files). `Messages/` and `Voice/` stay where they
are — Tom did not ask to move them.

### What a log carries

`ContestLog.scoreSnapshot: ScoreSnapshot?` — additive, `decodeIfPresent`,
omitted when nil, ~1 KB. **Written by the save path** (`LogDocument.
fileWrapper`, the same encode that feeds the iCloud mirror), computed from
the log with the rules installed then: the engine's figures when the party
is installed, counts-only otherwise; nil for a log that is not set up or has
no QSOs. The running document never reads it — it is for the file. Older
builds ignore the key and drop it on their next save, which is fine: their
save is the newer state and the dashboard falls back below.

### Reading the folder

`LogFolder(url:).history()` → `LogFolder.History`:

- lists the folder **one level deep** (a log dragged into any subfolder is
  kept without counting), every `*.qplog`, read under `NSFileCoordinator`;
- skips logs that are not set up, have no QSOs or no callsign (drafts);
- each remaining log becomes a `ContestRecord`: identity `(partyID, UTC year
  of the earliest QSO, callsign)`, `updatedAt` = the file's modification
  date, `sourceFileName` = its name, and a snapshot chosen by one rule —
  **the log's own snapshot when it carries figures, else one computed now**
  (`ScoreSnapshot.best(for:)`: engine if the party is installed here,
  counts-only otherwise) — with `scoreOrigin` saying which, so the score cell
  can say "as saved with the log" or "computed now with the installed rules";
- two files with one identity (a copy, an iCloud duplicate): the later-
  modified one is shown and the others are named as `duplicates`;
- a file that doesn't decode is named in `unreadable` and skipped, never
  written; `.<name>.qplog.icloud` placeholders are counted in `downloading`
  and their download requested;
- returns `archive: ContestArchive` (the plain in-memory value the dashboard,
  `SeasonStats`, `ChallengeStanding`, `UpcomingContests` and `StationMemory`
  read), plus `duplicates`, `unreadable`, `downloading`.

No logs folder chosen → nothing to read; the dashboard's empty state offers
the folder chooser, as it does today.

### Consequences, in Tom's terms

- **Scale:** the save already writes the log; nothing else is ever written.
- **Multiple instances:** nothing shared beyond the documents themselves.
  Different contests never meet; the same log open on two Macs is the
  document-conflict case that exists today regardless — the dashboard shows
  the file iCloud has and names a duplicate if one appears.
- **Delete = delete the log.** No UI. An entry exists exactly while its log
  is in the folder; the `tqp` test entry could never have been stuck.
- **One source of truth:** dashboard, prefill, worked-before, Open, exports
  all read the log. The inflated Skeeter score corrects itself (the log has
  83; without a saved snapshot it is scored now, and stamped on next save).
- **Less code:** the historian (debounced writes, import, migration,
  conflict folding), the archive store, the union merge, unknown-key
  preservation and the Import Logs button all go away.

### What changes in code

`Sources/Core/`
- `Models/ContestLog.swift`: `scoreSnapshot`; `stampingScoreSnapshot(rules:)`
  returns the copy the save path writes.
- `History/ScoreSnapshot.swift`: `best(for:)` (engine if installed else
  counts-only).
- `History/LogFolder.swift` (new): the reader above.
- `History/ContestRecord.swift`: plain value (no Codable, no extras, no
  merge) + `scoreOrigin`. `History/ContestArchive.swift`: plain value
  (`records`, `years`, `records(year:)`, `canonicalOrder`).
- Deleted: `History/ArchiveStore.swift`, `History/JSONValue.swift`.

`Sources/App/`
- `LogDocument.fileWrapper`: encode `log.stampingScoreSnapshot(...)` once,
  for the wrapper and the mirror; no historian call.
- Deleted: `ContestHistorian.swift`.

`Sources/UI/`
- `DashboardModel(logsFolder:)` — a closure, `CloudMirror.activeFolder` in
  the app, a temp folder in tests; `refresh()` reads through `LogFolder`;
  `duplicates`/`unreadable`/`downloading` for the footer; no import, no
  auto-import; `revealLogsFolder()`.
- `DashboardView`: toolbar *Reveal Logs Folder* + *Refresh*; footer;
  empty-state copy ("logs saved into your logs folder appear here").
- `DashboardContestsSection`: score cell tooltip names the score's origin.
- `MainView.loadArchiveIndex`: `LogFolder(url:).history().archive`.

Docs: README (features, keyboard row wording, tests paragraph, count),
CLAUDE.md layout row.

### Testing (offline, temp folders)

- `ContestLog`: `scoreSnapshot` round-trips; absent decodes nil; nil is not
  written; `stampingScoreSnapshot` sets the engine's figures for an
  installed party, counts-only for an unknown one, nil for a draft.
- `LogFolder`: identity/stamp/name from files; drafts skipped; non-`.qplog`
  and subfolders ignored; a saved snapshot with figures is used verbatim
  (frozen) and marked as saved; a log without one is scored now and marked
  so; a saved counts-only snapshot on a Mac with the party is rescored;
  duplicates fold to the later-modified and are named; a corrupt file is
  named, not fatal; a missing folder is empty; a placeholder is counted.
- `LogDocument`: what `fileWrapper` writes decodes with the snapshot set.
- `DashboardModel`: refresh over a temp folder; duplicates/unreadable
  surfaced; no folder → empty, no error.
- `StationMemory` / stats / challenge / upcoming / exports: unchanged.

### Commit plan

1. spec (this file).
2. Core: snapshot in the log, `LogFolder`, slimmed record/archive, deletions.
3. App + UI: save path, historian gone, dashboard on the folder, index.
4. Docs + count.
