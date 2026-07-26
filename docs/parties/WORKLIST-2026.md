# Party worklist — 2026 season

Per [Article 22](../CONSTITUTION.md#article-22--date-order-and-a-definition-of-done).
Ordered by contest date, so the next contest to run is always the next one built.

## Resuming this work in a new session

**This file is the state.** Read it plus [`../CONSTITUTION.md`](../CONSTITUTION.md)
and you have everything; nothing important lives only in a chat log.

- **21 parties remain.** **The scope widened on 2026-07-26** — see *Scope* below.
  February is clear (Vermont, Minnesota, British Columbia, South Carolina); North
  Carolina, Oklahoma, Idaho and Wisconsin are done in March.
  The original loop built every party running **from 2026-07-24 through
  2026-12-31**, which it finished; the season, however, starts in February, and
  the 24 US and 5 Canadian parties that ran **2026-02-07 → 2026-06-21** were
  never in that window and are not bundled. They are the remaining work.
- Maintenance runs alongside it: the late re-verification pass on the
  `verified: partial` parties (below), the standing debts under *Also
  outstanding*, and the remaining engine gaps.
- **Process per party:** the Article 22 definition of done at the bottom of this
  file. One party per commit (Article 9). Research doc *before* JSON (Article 15).
- **To restart the build loop**, self-paced, one party per iteration:

  ```
  /loop until all QSO parties from the 2026 season are added to qsopartylogger.
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
  **Five parties now ship against a stale-year rules document** — TnQP, IAQP, AZQP,
  PAQP, SDQP's sub-site hazard, NYQP and ILQP — and two carry a bonus-station
  question: PAQP's 2026 station is unannounced (worth 200 points per QSO), and
  ILQP's two club calls are marked "NEW FOR 2025" and have run only once.

**The 2026 season runs Saturday 7 February → Sunday 18 October 2026.** Two
independent calendars agree there is no state or provincial QSO party in
January, November or December, so the season opens with Vermont/Minnesota/BC and
closes with the Illinois QSO Party. Nothing outside that span is pending.

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

## Scope

**Widened 2026-07-26, and this is the only thing about this file that changed
meaning.** The original loop's brief was "every US state/regional QSO party
running **through** 2026-12-31", started on 2026-07-24 — so in practice it meant
*the rest of 2026*, and it finished. The 2026 **season** is the calendar year,
and it opens on 7 February. Everything between 2026-02-07 and 2026-06-21 was
outside the original window and is unbuilt.

Two consequences worth naming before the first one is built:

1. **These parties have already run.** Article 19 still binds — `schedule`
   carries the sponsor's own printed dates for the target year, and the target
   year is **2026**. A past window is correct data, not a defect: the party
   scores and exports properly, and `UpcomingContests` simply does not surface
   it. Where a sponsor has already announced 2027 dates, record them in `notes`;
   never derive a 2027 window from a formula and ship it as if printed.
2. **Five of the 29 are not US-state parties and two more are multi-state.**
   The Canadian five (BC, Ontario, Quebec, Canadian Prairies, Atlantic Canada)
   and the two multi-state regionals (7th Call Area, New England) do not fit
   `homeState: String` + one county list as cleanly as a single state does.

   **BCQP settled the first half of this on 2026-07-26: a single-province party
   needs NO schema change.** Nothing requires `homeState` to be a *US* state or
   the county class to be a *county* — `validate()` only wants two characters,
   and `homeState` drives the UI labels, the ADIF `state` field, the Cabrillo
   in-state location and `homeStateCountsViaCounty`, all of which `"BC"` is
   correct for. British Columbia's 43 federal electoral districts sit in the
   county list unchanged. **Two things to carry forward:** `provinces` **must**
   be overridden to drop the home province, because `validOutStateTokens` unions
   `provinces` in *after* subtracting `excludedStateTokens`, so the home
   province stays loggable otherwise; and ADIF's `cnty` field comes out as
   `<province>,<district>`, which is well formed but meaningless — Cabrillo,
   which is what sponsors require, is unaffected. Ontario, Quebec and the two
   multi-province parties should each be checked against this, not assumed.

   **The two multi-state regionals — REQUIREMENT SET BY KE5CW, 2026-07-26:**

   > "I should be able to log all states on the 7qp in a single log. Same for
   > NEQP."

   That is the design, and it is not negotiable by convenience. **One log covers
   every member state** — 7QP's seven (AZ ID MT NV OR UT WY) and NEQP's six (CT
   ME MA NH RI VT). No "pick your state at setup", no one-log-per-state, no
   seven separate party definitions.

   So `homeState: String` genuinely does not survive here, and this is the one
   Article 4 change the remaining parties actually force. Sketch, to be confirmed
   against each sponsor's rules when built:

   - **Counties carry their own state.** `County` gains an optional `state`;
     `nil` keeps every existing party identical (Article 4). The party's county
     list becomes the union across member states, ~350 entries for 7QP.
   - **`homeState` becomes a set.** An optional `homeStates: [String]` whose
     default is `[homeState]`, so nothing else moves. `excludedStateTokens`
     defaults to all of them — a 7-land station sends a county, never a bare
     state, so none of the seven tokens is loggable.
   - **Per-QSO location comes from the county, not the party.** `AdifExporter`
     writes `party.homeState` into `state`/`my_state` and `cnty` today; for these
     two it must read the county's own state instead. Cabrillo is unaffected —
     it carries the raw exchange token.
   - **`homeStateCountsViaCounty` becomes per-state** if any sponsor wants it.
   - **The UI's "Inside/Outside \(homeState)"** needs a party-supplied phrase
     ("Inside the 7th call area"), which is data, not a UI special case.

   **Five of the thirteen member-state county lists are already bundled**, which
   materially de-risks this: AZ and ID for 7QP, and ME, NH and VT for NEQP. The
   other eight (MT NV OR UT WY, CT MA RI) have no 2026 party of their own and
   must be generated from the regional sponsors' own lists.

   Its own commit, adding no party (Article 4), before 7QP is built. Both sit on
   2 May, so the March and April parties still buy time — but the shape is now
   decided, and it should not be re-litigated.

## Remaining, in contest-date order

**21 remaining**, ordered by 2026 contest date (Article 22) — which is also the
order they recur in 2027, so the rule still reads "the next contest to run is the
next one built". 17 US + 4 Canadian. Research is banked for none of them.

| # | Party | 2026 dates (UTC, provisional) | Notes |
| --- | --- | --- | --- |
| ~~1~~ | ~~Vermont~~ | ~~Feb 7 0000Z → Feb 8 2400Z~~ | **done** 2026-07-26 — [`vtqp_rules.md`](../research/vtqp_rules.md), `verified: partial` |
| ~~2~~ | ~~Minnesota~~ | ~~Feb 7 1400Z → Feb 7 2400Z~~ | **done** 2026-07-26 — [`mnqp_rules.md`](../research/mnqp_rules.md), `verified: partial` |
| ~~3~~ | ~~British Columbia~~ | ~~Feb 7 1600Z → Feb 8 0359Z; Feb 8 1600–2359Z~~ | **done** 2026-07-26 — [`bcqp_rules.md`](../research/bcqp_rules.md), `verified: partial` |
| ~~4~~ | ~~South Carolina~~ | ~~Feb 28 1500Z → Mar 1 0159Z~~ | **done** 2026-07-26 — [`scqp_rules.md`](../research/scqp_rules.md), `verified: partial` |
| ~~5~~ | ~~North Carolina~~ | ~~Mar 1 1500Z → Mar 2 0100Z~~ | **done** 2026-07-26 — [`ncqp_rules.md`](../research/ncqp_rules.md), `verified: partial` |
| ~~6~~ | ~~Oklahoma~~ | ~~Mar 14 1400Z → Mar 15 0200Z; Mar 15 1400–2200Z~~ | **done** 2026-07-26 — [`okqp_rules.md`](../research/okqp_rules.md), `verified: partial` |
| ~~7~~ | ~~Idaho~~ | ~~Mar 14 1600Z → Mar 15 0400Z; Mar 15 1400Z → Mar 16 0200Z~~ | **done** 2026-07-26 — [`idqp_rules.md`](../research/idqp_rules.md); **its county list is 7QP-reusable** |
| ~~8~~ | ~~Wisconsin~~ | ~~Mar 15 1800Z → Mar 16 0100Z~~ | **done** 2026-07-26 — [`wiqp_rules.md`](../research/wiqp_rules.md), `verified: partial` |
| 9 | Virginia | Mar 21 1400Z → Mar 22 0400Z; Mar 22 1200–2400Z | counties **and** independent cities |
| 10 | Louisiana | Apr 4 1400Z → Apr 5 0200Z | parishes, not counties |
| 11 | Mississippi | Apr 4 1400Z → Apr 5 0200Z | |
| 12 | Missouri | Apr 11 1400Z → Apr 12 0400Z; Apr 12 1400–2000Z | |
| 13 | New Mexico | Apr 11 1400Z → Apr 12 0200Z | |
| 14 | Georgia | Apr 11 1800Z → Apr 12 0359Z; Apr 12 1400–2359Z | 159 counties, the largest |
| 15 | North Dakota | Apr 11 1800Z → Apr 12 1800Z | 24 h continuous |
| 16 | Michigan | Apr 18 1600Z → Apr 19 0400Z | |
| 17 | Ontario | Apr 18 1800Z → Apr 19 0300Z; Apr 19 1200–2000Z | 🇨🇦 |
| 18 | Quebec | Apr 19 1300Z → Apr 19 2400Z | 🇨🇦 |
| 19 | Nebraska | Apr 25 1400Z → Apr 26 0200Z | |
| 20 | Florida | Apr 25 1600Z → Apr 26 0159Z; Apr 26 1200–2159Z | |
| 21 | 7th Call Area | May 2 1300Z → May 3 0700Z | **7 states** (AZ ID MT NV OR UT WY) — **one log covers all seven**, see *Scope* |
| 22 | Indiana | May 2 1500Z → May 3 0259Z | |
| 23 | Delaware | May 2 1700Z → May 3 2359Z | 3 counties |
| 24 | New England | May 2 2000Z → May 3 0500Z; May 3 1300–2400Z | **6 states** (CT ME MA NH RI VT) — **one log covers all six**, see *Scope* |
| 25 | Canadian Prairies | May 9 1700Z → May 10 0300Z | 🇨🇦 MB/SK/AB |
| 26 | Arkansas | May 16 1400Z → May 17 0200Z | |
| 27 | Kentucky | Jun 6 1300Z → Jun 7 0100Z | |
| 28 | Atlantic Canada | Jun 7 1400Z → Jun 8 0100Z | 🇨🇦 NB/NS/PE/NL |
| 29 | West Virginia | Jun 20 1600Z → Jun 21 0400Z | |

County counts above are recollection, not provenance — they are a sanity hint
for the generator's assertion, never its source (Article 2).

## Built

**27 bundled.** The 16 built by the first loop (MDC, HQP, OhQP, TnQP, COQP,
NJQP, IAQP, NHQP, Salmon Run, MEQP, CQP, AZQP, PAQP, SDQP, NYQP, ILQP), the
pre-existing ALQP, KSQP and TQP, and **VTQP**, **MNQP**, **BCQP**, **SCQP**,
**NCQP**, **OKQP**, **IDQP** and **WIQP** from the reopened first-half season,
all built 2026-07-26. Every row below is struck.

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
| ~~Illinois~~ | Oct 18 1700Z → Oct 19 0100Z | [`ilqp_rules.md`](../research/ilqp_rules.md) + [`ilqp_rules_2025.txt`](../research/ilqp_rules_2025.txt) + [`ilqp_counties.txt`](../research/ilqp_counties.txt) | **done** (`verified: partial`) |

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
4. ~~**All banked research is used up.**~~ **Moot — nothing is left to research.**
   *(SDQP, NYQP and ILQP are the evidence that the schema settled: after four
   consecutive parties that each needed an engine change, the last three were data
   only.)*
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

- **NO POINTS-BY-COUNTY, and no named-subset sweep — NCQP needs both, and
  together they are now the largest scoring gap in the repo.** Added 2026-07-26.

  *(a) Points by county.* NCQP designates ten "Rarest of NC" counties and pays
  **10× QSO points** for working them — phone 20, CW 30, digital 50 — and the
  sponsor stresses the placement: *"These points are added to the rest of the
  regular QSO Points **prior to MULT multiplication** so they have a significant
  positive effect on the final score."* `PointsTable` is keyed by mode alone.
  Sketch: an optional `bonusCountyPoints: {counties: [...], factor: Int}` (or an
  explicit per-mode table) consulted by
  `PartyDefinition.pointsTable(forTheirLoc:countyAbbrs:)` — **the hook already
  exists**, since that method already takes the received location and already
  chooses between two tables for `homeStationPoints`. This is the cheapest of the
  outstanding gaps and the highest-value; build it first.

  *(b) Named-subset sweep.* *"If at least one QSO is made with a station in five
  of the 'Rarest of NC' counties, 500 additional bonus points are added to the
  score after multiplication."* `BonusRule.sweepTiers` lands in the right place
  but counts `workedValues(.county).count` — *any* counties — so reusing it would
  pay nearly every log. Sketch: a `sweepOf(counties: [String], need: Int, points:
  Int)` case; only the predicate is new.

  **Both affect every entrant, in state and out** — unlike SCQP's activation
  multiplier or VTQP's power factor, which each hit one class of operator. Until
  they are built an NCQP score is a floor; `ncqp.json` gives the operator the
  correcting arithmetic, and
  `NorthCarolinaQSOPartyTests.testKnownGapRarestCountiesDoNotPayTenTimes` and
  `…testKnownGapTheFiveRareCountySweepIsNotPaid` pin the current behaviour.
- **FRACTIONAL SCORE MULTIPLIERS — SECOND USER FOUND 2026-07-26, so the repo's
  two-user bar is met and this is now buildable.** WIQP's power factors are QRP
  ×2, LOW ×1.5, high ×1 — **identical to VTQP's, down to the same three
  numbers**. Two sponsors, one gap; when it lands, both parties gain the field. `ScoreMultipliers` is
  `[String: Int]`, and VTQP's power multiplier is **QRP ×2, LOW POWER ×1.5, high
  ×1** (rule 7(D)(1)). ×1.5 cannot be represented, and shipping ×1 for low power
  would understate the most common power category by a third *while looking
  right* — the exact failure the constitution's preamble names. So VTQP ships
  with **no `scoreMultipliers` at all** and an operator-facing instruction to do
  the arithmetic by hand (`vtqp.json` KNOWN LIMITATION 1, pinned by
  `VermontQSOPartyTests.testKnownGapPowerMultiplierIsNotAppliedBecauseItIsFractional`).
  **This is bigger than a schema change.** The `Int` runs all the way through:
  `MultRule.factor(power:station:) -> Int`, `ScoreBreakdown.categoryFactor: Int`,
  `ScoreEngine.total = qsoPoints * multiplierCount * categoryFactor + bonusPoints`,
  `ScoreSidebar`'s `Text("\(score.categoryFactor)")` — and
  **`ScoreSnapshot.categoryFactor: Int` is persisted to the iCloud contest
  archive**, so widening it is a stored-history migration as well. Sketch: keep
  the JSON key, accept either an integer or a decimal, carry the factor as a
  rational (numerator/denominator) rather than a `Double` so the final score
  stays exact and the sidebar can render "×1.5" without float formatting, and
  decide the rounding rule explicitly — VTQP's sponsor does not state one, and
  ×1.5 on an odd points×mults product lands on a half exactly half the time.
  Its own commit, adding no party (Article 4), with every existing party's score
  proved unchanged; then VTQP gains the field in a second commit.
- **THE EXCHANGE CANNOT CARRY A NAME — and it is the only gap so far that blocks
  log submission.** MNQP's exchange is a **first name** plus a location, with no
  signal report at all: *"MN Stations: First name & county (three letter
  designator). W/VE Stations: First name and state / province. DX Stations: First
  name only."* `QSO` has `call`, `rstSent/Rcvd`, `serialSent/Rcvd`, `myLoc`,
  `theirLoc` — and no name. `CabrilloExporter.qsoLine` writes
  `exchangeNumber(serial:rst:)` into the `ex1` column the sponsor reserves for
  the name, which for a party with neither resolves to the **empty string**, so
  the exported log has the right columns with the names missing. The sponsor's
  own template shows the cost:

  ```
  QSO: 14042 CW 2010-02-06 1200 AC0W  BILL  MOW N2CU  TOM  NY
                                      ^ex1=Name           ^ex1=Name
  ```

  **Scoring is entirely unaffected** — names are not multipliers, not points, and
  not part of the dupe key — so live operating, dupe checking and the score are
  all correct. Cabrillo is *required* for submission, though, so an MNQP log
  needs its name column filled in by hand. Sketch: `QSO.nameSent/nameRcvd:
  String?` plus `PartyDefinition.exchangeIncludesName: Bool` defaulting false,
  with `ex1` preferring name → serial → RST; the entry bar and edit sheet each
  gain a field, and `ExchangeParser` learns a `NAME LOC` form. That touches
  `Sources/UI/`, so it is its own commit under Article 4 and cannot ride along
  with a party under Article 9. Pinned by
  `MinnesotaQSOPartyTests.testKnownGapTheNameHalfOfTheExchangeIsNotLogged`.
  **Watch for a second user** — a name exchange is common in the parties still
  to be built, and the count matters for the schema's shape.
- **Bonuses cannot be restricted to one side of the party.** VTQP rule 1A(F):
  *"Stations OUTSIDE of Vermont will get an additional 2 point bonus for each
  W1AW/1 station they work"*, ending *"Vermont stations will not get this
  bonus."* `ScoreEngine.bonusPoints` applies `workStation` regardless of
  `log.myLocation`, so a Vermont entrant is over-credited 2 points per W1AW/1
  QSO. Sketch: an optional `appliesTo: "inState" | "outState"` on `BonusRule`,
  defaulting to both. **One user so far** — the repo's bar is a second. Pinned by
  `testKnownGapVermontEntrantsAlsoReceiveTheBonusTheyShouldNot`. Note the rule
  itself is 2026-only (America250/YOTC), so it may simply disappear.
- **Mode-class grouping — now TWO users, wanting OPPOSITE things.** ILQP's mode
  split is **two-way** — "Stations
  may be worked once per band and mode (**phone and CW/digital**)" — while
  `DupeChecker` keys on all three `ModeClass` cases. So a station worked on CW and
  again on RTTY on one band is not flagged, and the sponsor counts the second as a
  duplicate. Scoring is otherwise unaffected: ILQP multipliers count once
  regardless, and the sponsor's stated penalty is loss of the QSO with no further
  deduction. Sketch: a party-level `dupeModeGroups: [["cw", "digital"]]` consulted
  by `DupeChecker` (and by nothing else, since no party groups modes for
  multiplier purposes). Recorded in `ilqp.json`'s notes as KNOWN LIMITATION 1 so
  an operator sees it.

  **VTQP is the second user, and it wants the opposite grouping** — a *finer*
  split, not a coarser one. Its page: *"RTTY is considered a legacy mode and is
  not part of this digital group."* RTTY and WSJT-X are two sponsor modes sharing
  one `ModeClass`, and since VTQP multipliers count **once per mode**, a Vermont
  entrant working one state on both RTTY and FT8 earns two multipliers from the
  sponsor and one here. The two parties together settle the shape: not a
  dupe-only `dupeModeGroups`, but **a party-supplied partition of modes** that
  both `DupeChecker` and the multiplier scope consult, with `ModeClass.allCases`
  as the default. ILQP supplies `[["phone"], ["cw", "digital"]]`; VTQP needs
  RTTY split out of `.digital`, which `QSO.rawMode` already carries. Pinned by
  `VermontQSOPartyTests.testKnownGapRTTYAndFT8ShareOneModeClass`.
- **FT4/FT8 cannot be excluded while other digital modes are allowed.** ILQP:
  "FT4 and FT8 contacts will receive no contact credit. Other digital modes are
  encouraged." That is below the granularity of `ModeClass`, which has one
  `.digital` case. `QSO.rawMode` carries the concrete mode, so a fix is possible —
  a party-level list of excluded raw modes — but one party wants it and the harm
  is small (an FT8 QSO scores locally and earns nothing from the sponsor).
  Recorded in `ilqp.json` as KNOWN LIMITATION 2.
- **Self-activation multipliers — SECOND USER FOUND 2026-07-26, so the repo's own
  bar is met and this is now buildable.** TnQP: "Tennessee mobiles and rovers may
  claim one multiplier for any Tennessee county from which they complete at least
  10 QSOs if they do not earn a multiplier for that county otherwise." The
  matching 500-point *bonus* is modeled (`activatedCountyCount`); the extra
  *multiplier* is not, so a TN mobile/rover sees a slightly low multiplier count.
  COQP turned out **not** to need it — its activation rule is a bonus only.

  **NCQP is the third user, added 2026-07-26**, and in its broadest form yet: *"NC stations may include the county from which operation takes place in the Multiplier count **regardless of whether any QSOs are logged from that same county**"* — so a fixed NC station counts its own county unconditionally. Three sponsors, three scopes (TnQP once, SCQP per band per mode, NCQP once and unconditional), which settles that the field must carry its scope rather than assume one.

  **SCQP rule 9.2.2 is the second user**, and states it as a multiplier outright:
  SC Mobile and Expedition stations count "Each SC county activated. At least one
  (1) QSO must be made from a county in order for it to count as activated", and
  "Expedition stations that operate from more than one county will receive a
  multiplier (ONCE PER MODE PER BAND) for each county activated". Note SCQP scopes
  it **per band per mode** while TnQP's is once — so the field must carry the
  scope, not assume one. Sketch: an optional `activatedCountyMultiplier: {minQSOs:
  Int}` on `MultRule`, credited from `log.myLoc` values rather than `theirLoc`,
  honouring the side's existing `countScope`, and gated on
  `isRovingCategory(log.station.categoryStation)` exactly as the bonus already is.
  Its own commit under Article 4, adding no party.

  **Who is affected:** only in-state mobile/rover/expedition entrants. A fixed
  in-state station and *every* out-of-state entrant score identically today,
  which is why both parties shipped without it. Recorded in `scqp.json`'s notes
  as a KNOWN LIMITATION so an SC mobile operator sees it.
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
