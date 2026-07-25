# Party worklist — 2026 season

Per [Article 22](../CONSTITUTION.md#article-22--date-order-and-a-definition-of-done).
Ordered by contest date, so the next contest to run is always the next one built.

## Resuming this work in a new session

**This file is the state.** Read it plus [`../CONSTITUTION.md`](../CONSTITUTION.md)
and you have everything; nothing important lives only in a chat log.

- **Next party:** the top unstruck row of the table below — **Illinois**, the
  last party of the 2026 season, which starts from its sponsor's site with
  nothing captured.
- **Process per party:** the Article 22 definition of done at the bottom of this
  file. One party per commit (Article 9). Research doc *before* JSON (Article 15).
- **To restart the build loop**, self-paced, one party per iteration:

  ```
  /loop Add QSO party support for every US state/regional QSO party running through 2026-12-31, in contest-date order, following docs/CONSTITUTION.md exactly. One party per iteration, one commit each.
  ```

  The earlier run paced itself at roughly 5-minute ticks and landed one party per
  iteration; a party built from scratch takes noticeably longer than one with
  research already banked, and none is banked any more.

- **Recurring judgement calls** worth knowing before starting, all learned the
  hard way and recorded below: sponsors' dates beat every calendar (open question
  1), sponsors' Canada lists differ in both directions (6), banked research has
  twice mislabelled `homeStateCountsViaCounty` (5), and a sponsor's own stated
  multiplier total or hour count is the cheapest verification available — look for
  one in every rule set.

- **Time-sensitive, independent of building new parties:** the `verified: partial`
  parties each want a re-check shortly before they run — see *Late re-verification
  pass* under Deferred engine gaps. Nearest are Hawaii (Aug 22, and its window
  question needs an email) and Tennessee (Sep 6, rules still the 2025 edition).

**The 2026 state QSO party season ends Sunday 18 October 2026.** Two independent
calendars agree there is no state or provincial QSO party in November or
December, so "through the end of the calendar year" closes with the Illinois QSO
Party. Nothing after 2026-10-18 is pending.

## Calendar sources

| Source | Role |
| --- | --- |
| [2026 State QSO Party Challenge calendar (PDF)](https://stateqsoparty.com/wp-content/uploads/2026/03/2026-State-QSO-Party-Calendarc.pdf) — extracted to [`2026_state_qso_party_calendar.txt`](../research/2026_state_qso_party_calendar.txt) | Primary. Fetched 2026-07-24. |
| [WA7BNM state parties page](https://www.contestcalendar.com/stateparties.php) | Cross-check. Fetched 2026-07-24. |
| [N5NA state/province calendar](https://qsoparty.eqth.net/index.html) | Cross-check on the Nov/Dec question. Fetched 2026-07-24. |

**These dates are provisional.** Per
[Article 19](../CONSTITUTION.md#article-19--the-schedule-is-annual-and-dated),
the `schedule` written into a party's JSON comes from **the sponsor's own rules**,
verified against the sponsor's printed dates — not from a calendar aggregator. The
dates below decide *build order only*.

## Status legend

| | |
| --- | --- |
| **done** | Bundled, tested, README updated — meets the Article 22 definition of done |
| **research banked** | Full `docs/research/<id>_rules.md` written to the Article 15 template |
| **raw sources only** | Sponsor text captured in `docs/research/`, not yet written up |
| **not started** | No sources captured |

## Remaining, in contest-date order

**1 remaining** of the 16 in scope (15 built so far: MDC, HQP, OhQP, TnQP, COQP,
NJQP, IAQP, NHQP, Salmon Run, MEQP, CQP, AZQP, PAQP, SDQP, NYQP); 18 parties
bundled in total, those 15 plus the pre-existing ALQP, KSQP and TQP. Rows are in contest-date order — the top unstruck row is what's
next, and the count above must equal the number of unstruck rows below.

| Party | 2026 dates (UTC, provisional) | Research | Status |
| --- | --- | --- | --- |
| ~~Maryland-DC~~ | Aug 8 1400Z → Aug 9 0400Z | [`mdcqp_rules.md`](../research/mdcqp_rules.md) + [`mdc_rules_2024.txt`](../research/mdc_rules_2024.txt) | **done** |
| ~~Hawaii~~ | Aug 22 1600Z → Aug 24 0400Z ⚠️ see below | [`hqp_rules.md`](../research/hqp_rules.md) + [`hqp_districts.tsv`](../research/hqp_districts.tsv) | **done** (`verified: partial`) |
| ~~Ohio~~ | Aug 22 1600Z → Aug 23 0400Z | [`ohqp_rules.md`](../research/ohqp_rules.md) + [`ohqp_mults_ohio.html`](../research/ohqp_mults_ohio.html) | **done** |
| ~~Kansas~~ | Aug 29 1400Z → Aug 30 0200Z; Aug 30 1400–2000Z | official PDFs | **done** |
| ~~Tennessee~~ | Sep 6 1700Z → Sep 7 0300Z | [`tnqp_rules.md`](../research/tnqp_rules.md) + [`tnqp_counties.tsv`](../research/tnqp_counties.tsv) | **done** (`verified: partial`) |
| ~~New Jersey~~ | Sep 12 1400Z → Sep 13 0200Z ✅ date settled by sponsor | [`njqp_rules.md`](../research/njqp_rules.md) + [`njqp_counties.tsv`](../research/njqp_counties.tsv) | **done** (`verified: partial`) |
| ~~Colorado~~ | Sep 12 1400Z → Sep 13 0400Z | [`coqp_rules.md`](../research/coqp_rules.md) + [`coqp_src_counties.txt`](../research/coqp_src_counties.txt) | **done** |
| ~~Iowa~~ | Sep 19 1400Z → Sep 20 0200Z | [`iaqp_rules.md`](../research/iaqp_rules.md) + [`iaqp_county_list.txt`](../research/iaqp_county_list.txt) | **done** (`verified: partial`) |
| ~~New Hampshire~~ | Sep 19 1600Z → Sep 20 0400Z; Sep 20 1200–2200Z | [`nhqp_rules.md`](../research/nhqp_rules.md) + [`nhqp_counties.tsv`](../research/nhqp_counties.tsv) | **done** (`verified: partial`) |
| ~~Washington Salmon Run~~ | Sep 19 1600Z → Sep 20 0700Z; Sep 20 1600–2400Z | [`warun_rules.md`](../research/warun_rules.md) + [`warun_counties.tsv`](../research/warun_counties.tsv) | **done** |
| ~~Texas~~ | Sep 19 1400Z → Sep 20 0200Z; Sep 20 1400–2000Z | [`tqp_verify.md`](../research/tqp_verify.md) | **done** (`verified: partial`) |
| ~~Maine~~ | Sep 26 1200Z → Sep 27 1200Z ✅ sponsor confirms it runs | [`meqp_rules.md`](../research/meqp_rules.md) + [`meqp_rules_2026.txt`](../research/meqp_rules_2026.txt) + [`meqp_page.txt`](../research/meqp_page.txt) | **done** (`verified: partial`) |
| ~~California~~ | Oct 3 1600Z → Oct 4 2200Z | [`cqp_rules.md`](../research/cqp_rules.md) + [`cqp_rules_2026.txt`](../research/cqp_rules_2026.txt) + [`cqp_multipliers.txt`](../research/cqp_multipliers.txt) | **done** |
| ~~Arizona~~ | Oct 10 1500Z → Oct 11 0500Z | [`azqp_rules.md`](../research/azqp_rules.md) + [`azqp_rules_pdf.txt`](../research/azqp_rules_pdf.txt) + [`azqp_counties_page.txt`](../research/azqp_counties_page.txt) | **done** (`verified: partial`) |
| ~~Pennsylvania~~ | Oct 10 1600Z → Oct 11 0400Z; Oct 11 1300–2200Z | [`paqp_rules.md`](../research/paqp_rules.md) + [`paqp_counties.txt`](../research/paqp_counties.txt) + [`paqp_arrl_sections.txt`](../research/paqp_arrl_sections.txt) | **done** (`verified: partial`) |
| ~~South Dakota~~ | Oct 10 1800Z → Oct 11 1800Z | [`sdqp_rules.md`](../research/sdqp_rules.md) + [`sdqp_rules_page.txt`](../research/sdqp_rules_page.txt) + [`sdqp_counties.txt`](../research/sdqp_counties.txt) | **done** (`verified: partial`) |
| ~~New York~~ | Oct 17 1400Z → Oct 18 0200Z | [`nyqp_rules.md`](../research/nyqp_rules.md) + [`nyqp_rules_2025.txt`](../research/nyqp_rules_2025.txt) + [`nyqp_counties.csv`](../research/nyqp_counties.csv) | **done** (`verified: partial`) |
| **Illinois** | Oct 18 1700Z → Oct 19 0100Z | — | not started |

## Open questions carried by this worklist

1. ~~**New Jersey date conflict.**~~ **RESOLVED 2026-07-24 — and the primary
   calendar was wrong.** The sponsor's own 2026 rules (version `2026rev0.5`,
   read live) say **Saturday September 12, 1400Z–0200Z**. The Challenge calendar
   PDF said Sep 19–20 and an initial web search agreed; WA7BNM said Sep 12–13.
   **Two of three aggregators, including the one this worklist designates
   primary, were wrong.** Treat this as the standing warning against the dates in
   the table above: they order the work, they do not decide it. Every remaining
   party's `schedule` must come from the sponsor, and a disagreement between
   aggregators is not resolved by counting them.
2. ~~**Maine is absent from the Challenge calendar.**~~ **RESOLVED 2026-07-24 —
   the party runs, and the primary calendar was again the wrong one.** The
   sponsor's own rules PDF is titled "2026 Official Rules" and both it and the
   rules page print **1200 UTC Sat Sep 26 → 1200 UTC Sun Sep 27**, matching
   WA7BNM and the sponsor's stated formula ("the last full weekend in
   September"). The Challenge calendar simply omits the event. Companion lesson
   to open question 1: an aggregator's **silence** is no more evidence than an
   aggregator's date. *(The sponsor's PDF misprints the contest-period year as
   2025; its own title block, its Oct 12 2026 deadline, the formula, and the
   fact that 2025-09-26 was a Friday all settle it on 2026 —
   [`meqp_rules.md` §2](../research/meqp_rules.md).)*
3. **Hawaii's operating window — unresolved with the sponsor.** HQP shipped
   `verified: partial` because rules rule 1 contradicts itself: "36 hours from
   1800 UTC Aug 22 through 0359 UTC Aug 24" *and* "6am Saturday … to 6pm Sunday
   in Hawaii". The literal UTC pair spans 33h59m, and 1800Z is 8am HST, not 6am.
   Shipped 1600Z→0400Z, the only span matching the stated 36 hours and both
   Hawaii-time anchors; the Challenge calendar instead says 1600Z→0200Z (34h).
   **Email `info@hawaiiqsoparty.org` to settle it.** See
   [`hqp_rules.md` §2](../research/hqp_rules.md).
4. **All banked research is used up.** Illinois, the last one, starts from its
   sponsor's site with nothing captured. *(SDQP and NYQP are the evidence that the
   schema has settled: after four consecutive parties that each needed an engine
   change, both were data only.)*
5. **Banked research has mislabelled `homeStateCountsViaCounty` twice.**
   *(CQP is the counter-example worth knowing: its sponsor states the rule
   outright — "The first valid CA QSO logged with 4-letter county abbreviation
   will count as the multiplier for California", and the multiplier table's CA
   row reads "1st CA county counts as CA". When a sponsor says it, ship it true;
   the lesson below is about the cases where nobody said it.)* Both
   `tnqp_rules.md` and `nhqp_rules.md` claimed "home-state-via-county: YES" when
   the sponsor only meant that home-state counties are in the in-state class list.
   That flag means something narrower — a home county *also* yielding the home
   state's own state multiplier — and taking the note at face value would have
   credited a phantom multiplier in both parties. Both are corrected in place.
   `warun_rules.md` reasons it correctly ("WA itself is NOT a state mult"), but
   **verify it against the sponsor's text anyway** when Washington is built.
6. **Read every sponsor's own Canada list — they differ in both directions.**
   OhQP counts only 11 provinces and folds Yukon/NWT/Nunavut into one `NT`
   multiplier, so `YT`/`NU` are invalid there. NJQP counts all 13 but spells
   Newfoundland **`NF`**, the legacy abbreviation, where this repo's default is
   `NL` — so `NL` is invalid there. **MEQP counts 14**, splitting Newfoundland
   (`NF`) and Labrador (`LB`) into two multipliers — "Please note that
   Newfoundland (NF) and Labrador (LB) will count seperately" [sic] — so `NL` is
   invalid there too, for a different reason than NJQP. Three parties, three
   different deviations: 11, 13-with-`NF`, and 14. Never assume the standard 13,
   and never assume the standard spellings. **CQP is the control case** — its
   multipliers page lists the standard 13 including `NL`, so the default was
   right there; it was still read before being relied on, which is the point.

## Deferred engine gaps

Recorded when a party needed something the schema does not model. Each would be
its own commit (Article 4).

- ~~**SERIAL NUMBERS.**~~ **Done 2026-07-24.** `QSO.serialSent`/`serialRcvd`,
  `PartyDefinition.exchangeIncludesSerial`, a QSO-number pair in the entry bar
  and the edit sheet, the numbers in Cabrillo's exchange columns and ADIF's
  `STX`/`SRX`, and a `{SERIAL}` CW macro. CQP carries it now, in its own commit
  (Article 9). The county-line question the sketch said to answer first is
  settled and tested: CQP sends its counties "in a single exchange", so **one
  contact carries one number** and every row of a county-line contact shares it —
  which fell out of `CountyLineExpander`'s existing shared `groupID` rather than
  needing new machinery. The next number is `max(serialSent) + 1`, not the row
  count, and deleting a QSO never renumbers the rest.
  Design: [`2026-07-24-serial-number-exchanges-design.md`](../superpowers/specs/2026-07-24-serial-number-exchanges-design.md).
  *Still worth checking when Pennsylvania is built: if PAQP also exchanges a QSO
  number, it now just sets the flag.*

- **Self-activation multipliers.** TnQP: "Tennessee mobiles and rovers may claim
  one multiplier for any Tennessee county from which they complete at least 10
  QSOs if they do not earn a multiplier for that county otherwise." The matching
  500-point *bonus* is modeled (`activatedCountyCount`); the extra *multiplier*
  is not, so a TN mobile/rover sees a slightly low multiplier count. COQP turned
  out **not** to need it — its activation rule is a bonus only — so TnQP is the
  sole user so far, and the field is not yet worth building. Revisit if a second
  party wants it.
- ~~**No 222 MHz band.**~~ **Done 2026-07-24.** `Band.cm125` = `1.25m`,
  222000–225000 kHz, default 222100 — ADIF 3.1.4 for the band string and edges,
  47 CFR §97.301(a) as cross-check, ARRL band plan for the calling frequency.
  `222` typed in the call field QSYs there; `1.25M` works too. TnQP and IAQP
  both carry the band now, each in its own commit (Article 9), and the open
  question that said the band did not exist is gone from both.
  Design: [`2026-07-24-222mhz-band-design.md`](../superpowers/specs/2026-07-24-222mhz-band-design.md).
- **Cabrillo writes raw kHz for VHF and up.** `CabrilloExporter.qsoLine` emits
  `String(q.freqKHz ?? q.band.defaultFreqKHz)`, so a 2 m QSO exports as
  `144200`. Cabrillo V3 specifies bare band designators above 50 MHz — `50`,
  `144`, `222`, `432` — not kHz. Pre-existing and wrong for 2 m and 70 cm
  today; 1.25 m simply joins them. Found while adding the band and left alone
  deliberately: fixing it changes every existing party's exported log, so it
  needs its own commit and its own exporter-test updates (Article 9).
- **DXCC prefixes shadowed by state/province codes.** `isPlausibleDXPrefix`
  rejects any token matching a US state or Canadian province code, so real DXCC
  prefixes that collide are credited as the state/province: PA (Netherlands) as
  Pennsylvania, OK (Slovakia) as Oklahoma, LA (Norway) as Louisiana, ON (Belgium)
  as Ontario. Sponsors' log checkers resolve them the same way, so this is
  defensible — but it matters for the Salmon Run, the one party where DX prefixes
  carry multiplier weight, because it can leave the 10-DXCC allowance under-used.
  Fixing it properly needs the callsign, not the exchange token. A test in
  `SalmonRunTests` pins the current behaviour so it stays deliberate.
- **No DXCC prefix table.** NHQP gives NH stations "up to 10 DXCC country" as
  multipliers, but its exchange is the literal token "DX", so distinguishing DXCC
  entities requires deriving country from the callsign. `dxMultCap` records the
  rule and can never bind. Fixing it means a prefix→DXCC table plus wiring
  `multContributions` to use the `call` parameter it currently ignores.
  **MEQP raises the stakes:** it gives DXCC entities to *every* entrant with *no*
  cap, and counts them per band per mode, so the undercount is now the largest
  single scoring gap in the repo rather than an in-state edge case. This is the
  strongest case yet for building the table — the second party wanting it, and
  the first where it costs everyone.
- **Late re-verification pass.** TnQP ships against a rules document titled for
  2025 (no 2026 revision posted). Sponsors commonly post revisions weeks before
  the event, so every `verified: partial` party wants one re-check in the fortnight
  before it runs — TnQP in late August, and HQP's window question settled by email.
  **AZQP is the same case as TnQP and wants the same treatment** (early October):
  its published rules — page and PDF alike — are headed "2025 Arizona QSO Party"
  with footer "Rev: 2501 6/23/2025", while only the site banner carries the 2026
  date. The date itself is settled (the rules' own "2nd October Saturday" formula
  agrees with the banner); what is unverified is whether any *rule* moved.
  **MEQP needs one too** (mid-September): the sponsor edits its rules PDF in place
  at a stable URL with no revision marker, so the only way to detect a change is
  to re-fetch and re-run `gen_meqp.py`, whose quoted-sentence assertions fail
  loudly if the text moved. Its open question (is Maine itself a state multiplier
  for Maine entrants?) is one email to `maineqsoparty@gmail.com`.

## Also outstanding

- **Review `outStateWorksHomeStationsOnly` for the parties that predate it.**
  MDC introduced this field (rules 10b), and every party built since had needed
  it — until **MEQP, the first to answer no, and to say so outright**: "all QSOs
  made during the contest period that meet MEQP criteria are eligible for
  points—not just contacts with Maine stations." CQP then swung back the other
  way just as explicitly ("Non-CA to non-CA contacts do not count for QSO
  credit"), so the run is ten for eleven and the field is genuinely per-party
  rather than a near-universal default. Seven state the restriction outright
  (MDC, HQP, OhQP, TnQP, COQP, CQP, and the Salmon Run's "Stations outside
  Washington state work only Washington state stations"); three more (NJQP, IAQP,
  NHQP) only imply it and ship it on with an open question. ALQP/KSQP/TQP are very likely wrong to have it off.
  It defaults to `false` so those three keep scoring exactly as before per
  Article 4, but each should be re-read and switched on where the sponsor says so
  — ideally in one deliberate commit covering all three, with their own tests
  updated to prove the change.
- **Generator consolidation.** `gen_parties.py` is not runnable: it reads
  `KSQP-Mults.txt`, `TX_county_abbrevs.txt`, and
  `research/alqp_counties_text.txt`, none of which are committed. `gen_mdc.py`
  is self-contained and runs from committed data — the pattern to follow. Folding
  the older three into runnable per-party generators is a refactor and belongs in
  its own commit (Article 4).
- **TQP's notes have no `OPEN QUESTION` section.** It is marked
  `verified: partial`, so the setup sheet warns on it, but its caveat ("Confirm
  band list and current-year details before submitting") is written as prose
  inside the provenance paragraph rather than under the marker Article 3 now
  requires. The operator therefore sees a warning with nothing actionable beside
  it. Fix when resolving the Cabrillo question below, in the same commit.
- **TQP Cabrillo name** — `tqp.json` ships the `TX-QSO-PARTY` alias while
  `tqp_verify.md` concludes `TXQP` is the safe export value
  ([Appendix A.2](../CONSTITUTION.md#appendix-a--known-violations)). Resolve
  before anyone submits a TQP log.
- **ALQP runs this weekend** (Jul 25–26) and is already done — no action.

## Per-party definition of done

Copied from Article 22 so it can be ticked off in place:

- [ ] `docs/research/<id>_rules.md` complete, all 14 sections
- [ ] counties generated by script with count assertions
- [ ] `Resources/Parties/<id>.json` with provenance + any `verified: partial` questions
- [ ] per-party test file meeting the Article 18 floor
- [ ] full suite green, command and output recorded
- [ ] README: bundled-parties entry, test count, provenance
- [ ] committed alone
