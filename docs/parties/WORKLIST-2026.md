# Party worklist — 2026 season

Per [Article 22](../CONSTITUTION.md#article-22--date-order-and-a-definition-of-done).
Ordered by contest date, so the next contest to run is always the next one built.

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

**8 remaining** of the 16 in scope (8 built so far: MDC, HQP, OhQP, TnQP, COQP,
NJQP, IAQP, NHQP); 11 parties bundled in total, those 8 plus the pre-existing
ALQP, KSQP and TQP. Rows are in contest-date order — the top unstruck row is what's
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
| **Washington Salmon Run** | Sep 19 1600Z → Sep 20 0700Z; Sep 20 1600–2400Z | [`warun_rules.md`](../research/warun_rules.md) + [`warun_counties.tsv`](../research/warun_counties.tsv) | research banked |
| ~~Texas~~ | Sep 19 1400Z → Sep 20 0200Z; Sep 20 1400–2000Z | [`tqp_verify.md`](../research/tqp_verify.md) | **done** (`verified: partial`) |
| **Maine** | Sep 26 1200Z → Sep 27 1200Z ⚠️ **not on the Challenge calendar** | — | not started |
| **California** | Oct 3 1600Z → Oct 4 2200Z | — | not started |
| **Arizona** | Oct 10 1500Z → Oct 11 0500Z | — | not started |
| **Pennsylvania** | Oct 10 1600Z → Oct 11 0400Z; Oct 11 1300–2200Z | — | not started |
| **South Dakota** | Oct 10 1800Z → Oct 11 1800Z | — | not started |
| **New York** | Oct 17 1400Z → Oct 18 0200Z | — | not started |
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
2. **Maine is absent from the Challenge calendar** but listed by WA7BNM for
   Sep 26–27. Confirm the party runs in 2026 from the sponsor before building it;
   if it does not, strike it from this list rather than shipping a guess.
3. **Hawaii's operating window — unresolved with the sponsor.** HQP shipped
   `verified: partial` because rules rule 1 contradicts itself: "36 hours from
   1800 UTC Aug 22 through 0359 UTC Aug 24" *and* "6am Saturday … to 6pm Sunday
   in Hawaii". The literal UTC pair spans 33h59m, and 1800Z is 8am HST, not 6am.
   Shipped 1600Z→0400Z, the only span matching the stated 36 hours and both
   Hawaii-time anchors; the Challenge calendar instead says 1600Z→0200Z (34h).
   **Email `info@hawaiiqsoparty.org` to settle it.** See
   [`hqp_rules.md` §2](../research/hqp_rules.md).
4. **Only one banked research doc is left.** Of the 8 remaining, only Washington
   Salmon Run has research banked. The other seven (Maine, California, Arizona,
   Pennsylvania, South Dakota, New York, Illinois) start from their sponsors'
   sites with nothing captured, so expect those iterations to be research-heavy,
   as Hawaii was.
5. **Banked research has mislabelled `homeStateCountsViaCounty` twice.** Both
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
   `NL` — so `NL` is invalid there. Two parties, two different deviations from the
   default. Never assume the standard 13, and never assume the standard spellings.

## Deferred engine gaps

Recorded when a party needed something the schema does not model. None blocks a
party; each would be its own commit (Article 4).

- **Self-activation multipliers.** TnQP: "Tennessee mobiles and rovers may claim
  one multiplier for any Tennessee county from which they complete at least 10
  QSOs if they do not earn a multiplier for that county otherwise." The matching
  500-point *bonus* is modeled (`activatedCountyCount`); the extra *multiplier*
  is not, so a TN mobile/rover sees a slightly low multiplier count. COQP turned
  out **not** to need it — its activation rule is a bonus only — so TnQP is the
  sole user so far, and the field is not yet worth building. Revisit if a second
  party wants it.
- **No 222 MHz band.** `Band` has no 1.25 m case, but **TnQP and IAQP both
  permit it** and both tabulate suggested 222/223 MHz frequencies. Two users now,
  so this is worth building: it touches `Band`, the band map and ADIF, and belongs
  in its own commit.
- **No DXCC prefix table.** NHQP gives NH stations "up to 10 DXCC country" as
  multipliers, but its exchange is the literal token "DX", so distinguishing DXCC
  entities requires deriving country from the callsign. `dxMultCap` records the
  rule and can never bind. Fixing it means a prefix→DXCC table plus wiring
  `multContributions` to use the `call` parameter it currently ignores. Affects
  in-state NHQP entrants only; WA may want the same when it lands.
- **Late re-verification pass.** TnQP ships against a rules document titled for
  2025 (no 2026 revision posted). Sponsors commonly post revisions weeks before
  the event, so every `verified: partial` party wants one re-check in the fortnight
  before it runs — TnQP in late August, and HQP's window question settled by email.

## Also outstanding

- **Review `outStateWorksHomeStationsOnly` for the parties that predate it.**
  MDC introduced this field (rules 10b), and **every party built since has needed
  it** — HQP, OhQP, TnQP and COQP all state the restriction outright
  ("QSOs must include at least one Colorado station"). Five for five: this is the
  norm, not the exception, and ALQP/KSQP/TQP are very likely wrong to have it off.
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
