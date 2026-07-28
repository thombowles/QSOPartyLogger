# N1MM call history files — provenance and mechanics

Research bank for the call history feature
(design: `docs/superpowers/specs/2026-07-28-call-history-design.md`).
All fetches 2026-07-28 unless noted.

Constitution note: these files are operating **hints**, not rules. Article 1's
ban on N1MM files as rule authority stands untouched — nothing here feeds
`ScoreEngine`, and every offered value must survive the party's own
`ExchangeParser` first.

## Sources

| What | Where | Fetched |
| --- | --- | --- |
| File format | `n1mmwp.hamdocs.com/setup/call-history/` | 2026-07-28 |
| File listing (504 files, 11 pages) | `n1mmwp.hamdocs.com/mmfiles/categories/callhistory/` | 2026-07-28 |
| Banked inventory | [`n1mm_callhistory_inventory.json`](n1mm_callhistory_inventory.json) | 2026-07-28 |
| Per-party verification | [`n1mm_callhistory_verify.json`](n1mm_callhistory_verify.json) | 2026-07-28 |
| Generator | [`gen_callhistory.py`](gen_callhistory.py) | — |

## File format (from the N1MM documentation)

- Comma- **or semicolon**-delimited text; `#` begins a comment line.
- Default field order: `Call, Name, Loc1, Loc2, Sect, State, CK, BirthDate,
  Exch1, Misc, Power, CqZone, ItuZone, UserText`.
- An `!!Order!!` line re-declares the order, e.g. `!!Order!!,Call,Name,CK,Sect`;
  "field name case is not important".
- Other `!!…!!` import directives exist (`!!MapStateToSect!!`,
  `!!Validate50State!!`, …) and are ignored by this app.
- N1MM pre-fills exchange fields from the matched record when they are empty —
  the same posture this app takes (operator text always outranks it).

## Observed variations (downloaded files, headers banked in verify JSON)

| File | `!!Order!!` | Notes |
| --- | --- | --- |
| QSOP_AL-2026-002 | `Call,Name,Exch1,UserText,` | trailing comma; `# QSOPARTY AL` |
| QSOP_TX-2025-004 | `Call,Exch1,UserText` | no Name; `!!Order!!` after a `#` line |
| QSOP_WA-2025-002 | `, Call, Name, Exch1, UserText` | **spaces around names** |
| QSOP_NE-2026-002 | `Call,Exch1,UserText,` | leading blank line before the directive |
| QSOP_PA-2025-003 | `Call,Exch1,UserText` | directive after 5 comment lines; Exch1 carries counties *and* sections |
| QSOP_OH-2025-003 | `Call,Name,Exch1,UserText,` | writes `# QSO PARTY OH` (space) — the reason token matching is whitespace-blind |
| NAQPCW-004 | `Call,Name,State,UserText,` | location in **State**, not Exch1; one file declares NAQPCW/NAQPSSB/NAQPRTTY/Sprints |
| QSOP_IN7QPNE_DE-2026-006 | `Call,Name,Exch1,UserText,` | one file for five parties: "There will be only one file for all, in 2026"; declares `QSOPARTY 7QP / DE / IN / IN7QPNE / NEWE` |
| QSOP_QC-2026-011 | `, Call, Name, Exch1, UserText` | UTF-8 French comments |
| QSOP_KS-2025-002 | `Call,Name,Exch1,UserText,` | 1×1 bonus calls listed first; duplicate calls possible → last wins |

Record shapes worth remembering: empty Exch1 with `MOBILE`/`Multiple` in
UserText (rovers with no fixed county); county-line values as slash pairs
(`NSHRM/NSCOL`, `MTJEF/SIL`); DX prefixes in the NAQP State column (`8P`);
portable suffixes in calls (`AA2IL/6`, `AD4EB/M`).

## Download mechanics (observed; CM Download Manager)

1. Listing search: `GET /mmfiles/categories/callhistory/?view=list&sort=newest&CMDsearch=<prefix>`
   → `<li>` entries with `cmdm-list-item-title` (filename),
   the file page URL, and `cmdm-list-item-desc` (updated date, `YYYY-MM-DD`).
2. File page: `GET /mmfiles/<slug>/` → form
   `<form method="post" class="CMDM-downloadForm" action="…/mmfile/get/file/<FILENAME>">`
   with hidden `cmdm_nonce` and `id` inputs. Cookies from this GET must
   accompany the POST, plus a `Referer` of the page URL — without them the
   site answers `/cmdm-access-denied/`.
3. `POST action` with `cmdm_nonce=<nonce>&id=<id>` → raw file bytes
   (`application/octet-stream`).

Every uploaded revision gets its **own** page slug
(`qsop_al-2026-002-txt`, `…-001-txt` are separate pages), which is why no URL
is bundled: discovery runs the search at use time and takes the newest
filename matching the party's prefix + separator (`-`, `_` or `.`).

## Mapping (generated, never hand-typed — `gen_callhistory.py`)

- Single-state parties: prefix `QSOP_<homeState>`, token `QSOPARTY <homeState>`.
- May weekend (inqp, sevenqp, newenglandqp, deqp, in7qpne): shared
  `QSOP_IN7QPNE_DE` file, per-party tokens as the file itself declares them.
- naqpcw/naqpssb: `NAQPCW` / `NAQPSSB` module files.
- **No file exists** for azqp, mdc, vtqp (checked against all 504 inventory
  titles). The generator asserts this set exactly, so a file appearing
  upstream — or a new party arriving — fails loudly and gets a decision.
- njqp's newest file is `QSOP_NJ-2024-002.txt` (2024): stale upstream, still
  offered — hints age gracefully because every value is re-parsed per party.

## Regeneration

```bash
python3 docs/research/gen_callhistory.py --fetch   # scrape + verify (network)
python3 docs/research/gen_callhistory.py           # offline re-patch
```

Re-run `--fetch` at the start of each season. The patch phase asserts: 45
mapped / 3 file-less of 48 bundled, every prefix resolves in the inventory,
and every token was seen in its file's comments (whitespace-blind).
