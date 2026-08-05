# Party worklist — 2026 season

Per [Article 22](../CONSTITUTION.md#article-22--date-order-and-a-definition-of-done).
Ordered by contest date, so the next contest to run is always the next one built.

## Resuming this work in a new session

**This file is the state.** Read it plus [`../CONSTITUTION.md`](../CONSTITUTION.md)
and you have everything; nothing important lives only in a chat log.

- **3 parties remain**, plus the blocked Canadian Prairies. **The scope widened on 2026-07-26** — see *Scope* below.
  February and March are clear; April is under way (Louisiana, Mississippi,
  Missouri, New Mexico, Georgia, North Dakota, Michigan, Ontario, Quebec,
  Nebraska, Florida, 7QP, Indiana, Delaware, NEQP, Arkansas). **Both
  multi-state parties are done** and the schema needed no further change for
  the second. **The Canadian Prairies is BLOCKED** — its 62 districts are
  published only as JPEGs and the sponsor's own pages give four different
  totals; see [`cpqp_blocked.md`](../research/cpqp_blocked.md) for the research
  and the unblock path. **Atlantic Canada is next** (7 June).
  **7QP turned out to be EIGHT states, not seven** — the sketch below left
  Washington out, and the sponsor's own page is the authority.
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
   every member state** — 7QP's **eight** (AZ ID MT NV OR UT **WA** WY) and
   NEQP's six (CT ME MA NH RI VT). *Corrected when 7QP was built: this sketch
   said seven and left Washington out. Running its own Salmon Run does not take
   Washington out of the 7th call area.* No "pick your state at setup", no one-log-per-state, no
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

   **DONE 2026-07-26, in its own party-free commit** — the sketch above shipped
   almost unchanged. Three optional fields carry it, all defaulted so every
   existing party is byte-identical:

   | Field | Default | What it does |
   | --- | --- | --- |
   | `County.state` | `nil` | the state that county lies in |
   | `PartyDefinition.homeStates` | `[homeState]` | every member state |
   | `PartyDefinition.inStateLabel` | `homeState` | the setup sheet's phrase |

   `PartyDefinition.state(forCounty:)` is the single accessor that resolves a
   county to its state, and every call site that used to read `party.homeState`
   for a county now goes through it — the state credited by
   `homeStateCountsViaCounty`, and ADIF's `cnty`/`state`/`my_cnty`/`my_state`.
   `excludedStateTokens` now defaults to **all** member states, so no member
   state is a loggable token. `validate()` rejects a county naming a state the
   party does not cover, and a `homeState` absent from `homeStates`.

   `Tests/Core/MultiStatePartyTests.swift` is the Article 4 proof: every bundled
   party still has one home state, no county naming one, and the same
   excluded-token list. **Two things the sketch got wrong and the build
   corrected**: Cabrillo needed no change at all (its `LOCATION:` header is the
   entrant's own state, and `homeState` remains right for that), and
   `homeStateCountsViaCounty` did *not* need to become per-state — resolving the
   county's own state gives each member state its multiplier from one flag.

## Remaining, in contest-date order

**3 remaining** plus one blocked, ordered by 2026 contest date (Article 22) — which is also the
order they recur in 2027, so the rule still reads "the next contest to run is the
next one built". 3 US + 2 Canadian. Research is banked for none of them.

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
| ~~9~~ | ~~Virginia~~ | ~~Mar 21 1400Z → Mar 22 0400Z; Mar 22 1200–2400Z~~ | **done** 2026-07-26 — [`vaqp_rules.md`](../research/vaqp_rules.md); 95 counties + 38 cities |
| ~~10~~ | ~~Louisiana~~ | ~~Apr 4 1400Z → Apr 5 0200Z~~ | **done** 2026-07-26 — [`laqp_rules.md`](../research/laqp_rules.md); 64 parishes, date **derived** |
| ~~11~~ | ~~Mississippi~~ | ~~Apr 4 1400Z → Apr 5 0200Z~~ | **done** 2026-07-26 — [`msqp_rules.md`](../research/msqp_rules.md); FT4/8 is a first-class mode |
| ~~12~~ | ~~Missouri~~ | ~~Apr 11 1400Z → Apr 12 0400Z; Apr 12 1400–2000Z~~ | **done** 2026-07-26 — [`moqp_rules.md`](../research/moqp_rules.md); date **moved for Easter** |
| ~~13~~ | ~~New Mexico~~ | ~~Apr 11 1400Z → Apr 12 0200Z~~ | **done** 2026-07-26 — [`nmqp_rules.md`](../research/nmqp_rules.md); **first power multiplier that fits** |
| ~~14~~ | ~~Georgia~~ | ~~Apr 11 1800Z → Apr 12 0359Z; Apr 12 1400–2359Z~~ | **done** 2026-07-26 — [`gaqp_rules.md`](../research/gaqp_rules.md); 159 counties, **entirely first-party** |
| ~~15~~ | ~~North Dakota~~ | ~~Apr 11 1800Z → Apr 12 1800Z~~ | **done** 2026-07-26 — [`ndqp_rules.md`](../research/ndqp_rules.md); 24 h continuous, **non-standard province list** |
| ~~16~~ | ~~Michigan~~ | ~~Apr 18 1600Z → Apr 19 0400Z~~ | **done** 2026-07-26 — [`miqp_rules.md`](../research/miqp_rules.md); **site had rolled to 2027**, editions diffed |
| ~~17~~ | ~~Ontario~~ | ~~Apr 18 1800Z → Apr 19 0300Z; Apr 19 1200–2000Z~~ | **done** 2026-07-26 — [`oqp_rules.md`](../research/oqp_rules.md); 🇨🇦 **rules still 2026 while the site says 2027** |
| ~~18~~ | ~~Quebec~~ | ~~Apr 19 1300Z → Apr 19 2400Z~~ | **done** 2026-07-26 — [`qcqp_rules.md`](../research/qcqp_rules.md); 🇨🇦 **bilingual rules, parsed both** |
| ~~19~~ | ~~Nebraska~~ | ~~Apr 25 1400Z → Apr 26 0200Z~~ | **done** 2026-07-26 — [`neqp_rules.md`](../research/neqp_rules.md); **36 h, not 12** — and the .org is a content farm |
| ~~20~~ | ~~Florida~~ | ~~Apr 25 1600Z → Apr 26 0159Z; Apr 26 1200–2159Z~~ | **done** 2026-07-26 — [`fqp_rules.md`](../research/fqp_rules.md); **first-party Cabrillo header**, `FCG-FQP` |
| ~~21~~ | ~~7th Call Area~~ | ~~May 2 1300Z → May 3 0700Z~~ | **done** 2026-07-26 — [`sevenqp_rules.md`](../research/sevenqp_rules.md); **EIGHT states, not seven** — WA is in it too |
| ~~22~~ | ~~Indiana~~ | ~~May 2 1500Z → May 3 0259Z~~ | **done** 2026-07-26 — [`inqp_rules.md`](../research/inqp_rules.md); **points changed for 2026**, old rule still in an HTML comment |
| ~~23~~ | ~~Delaware~~ | ~~May 2 1700Z → May 3 2359Z~~ | **done** 2026-07-26 — [`deqp_rules.md`](../research/deqp_rules.md); 3 counties, **rules titled 2024** and they state no times |
| ~~24~~ | ~~New England~~ | ~~May 2 2000Z → May 3 0500Z; May 3 1300–2400Z~~ | **done** 2026-07-26 — [`newenglandqp_rules.md`](../research/newenglandqp_rules.md); 6 states, id **`newenglandqp`** (Nebraska holds `neqp`) |
| **25** | **Canadian Prairies** | May 9 1700Z → May 10 0300Z | 🇨🇦 MB/SK/AB — **BLOCKED 2026-07-26**: districts are images only, sponsor totals contradict. Research banked in [`cpqp_blocked.md`](../research/cpqp_blocked.md) |
| ~~26~~ | ~~Arkansas~~ | ~~May 16 1400Z → May 17 0200Z~~ | **done** 2026-07-26 — [`arqp_rules.md`](../research/arqp_rules.md); the rules state **no times** |
| ~~27~~ | ~~Kentucky~~ | ~~Jun 6 1300Z → Jun 7 0100Z~~ | **done** 2026-07-26 — [`kyqp_rules.md`](../research/kyqp_rules.md); site says 2027 but the rules are a formula |
| 28 | Atlantic Canada | Jun 7 1400Z → Jun 8 0100Z | 🇨🇦 NB/NS/PE/NL |
| 29 | West Virginia | Jun 20 1600Z → Jun 21 0400Z | |

County counts above are recollection, not provenance — they are a sanity hint
for the generator's assertion, never its source (Article 2).

## Built

**45 bundled.** The 16 built by the first loop (MDC, HQP, OhQP, TnQP, COQP,
NJQP, IAQP, NHQP, Salmon Run, MEQP, CQP, AZQP, PAQP, SDQP, NYQP, ILQP), the
pre-existing ALQP, KSQP and TQP, and **VTQP**, **MNQP**, **BCQP**, **SCQP**,
**NCQP**, **OKQP**, **IDQP**, **WIQP**, **VAQP**, **LAQP**, **MSQP**, **MOQP**,
**NMQP**, **GAQP**, **NDQP**, **MIQP**, **OQP**, **QCQP**, **NEQP**, **FQP**
**7QP**, **INQP**, **DEQP**, **NEQP**, **ARQP** and **KYQP** from the reopened first-half season, all built 2026-07-26.
Every row below is struck.

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

- ~~**NO POINTS-BY-COUNTY, and no named-subset sweep — NCQP needs both, and
  together they are now the largest scoring gap in the repo.**~~ Added
  2026-07-26, **BUILT 2026-07-28.** Both ship, and the repo's largest scoring
  gap is closed.

  *(a) Points by county* → **`countyPointFactor: {counties: [...], factor: Int}`**,
  consulted by `PartyDefinition.pointsTable(forTheirLoc:countyAbbrs:)` as
  sketched — the hook was already there, so `ScoreEngine` needed no change for
  the 10× at all: a scaled table flows through the existing `qsoPoints +=` and
  lands inside the multiplication by construction. It scales whichever table
  applied rather than replacing it, so it composes with `homeStationPoints`. The
  factor ships, not the sponsor's worked-out 20/30/50 table, and `gen_ncqp.py`
  asserts the one reproduces the other.

  *(b) Named-subset sweep* → **`BonusRule.designatedCountySweep(counties:need:points:)`**.
  A new case rather than a flag on `sweepTiers`, because the two read different
  things: tiers count `workedValues(.county)`, the multiplier tally, while the
  sponsor's predicate is *"at least one QSO is made with a station in five of
  the … counties"* — rows, not mults. Pays once at the threshold or past it.

  Design:
  [`2026-07-28-designated-county-scoring-design.md`](../superpowers/specs/2026-07-28-designated-county-scoring-design.md).
  Engine first, party-free, then NCQP alone (Article 9). *That left NCQP
  `verified: partial` on the self-activation multiplier below — which shipped
  in turn on 2026-08-04, closing the last scoring gap of that party. NCQP stays
  partial now only on a provenance item: the Cabrillo `CONTEST:` value is the
  WA7BNM registry's, since the sponsor's rules state none.*

  **The shape does not cover the other two points-table users.** Ontario wants
  points by *callsign* and at a flat rate, Delaware by *band* and by the
  entrant's own role — neither is county-keyed, so both still wait. What this
  settles is that a points rule keyed on the received location has a home, and
  the next one adds a sibling field rather than reopening the argument.
- ~~**FRACTIONAL SCORE MULTIPLIERS.**~~ **Done 2026-07-28**, in three commits:
  the engine, then VTQP, then WIQP. WIQP's power factors are QRP ×2, LOW ×1.5,
  high ×1 —
  **identical to VTQP's, down to the same three numbers** (VTQP rule 7(D)(1)) —
  and `ScoreMultipliers` held `[String: Int]`, so ×1.5 could not be represented
  and shipping ×1 for low power would have understated the most common power
  category by a third *while looking right*, the exact failure the
  constitution's preamble names. Both parties therefore shipped with **no
  `scoreMultipliers` at all** and an operator-facing instruction to do the
  arithmetic by hand.
  **The `Int` ran all the way through**, which is why this was bigger than a
  schema change: `factor(power:station:)`, `ScoreBreakdown.categoryFactor`,
  `ScoreEngine.total`, `ScoreSidebar`'s `Text("\(score.categoryFactor)")` — and
  `ScoreSnapshot.Figures.categoryFactor`, persisted to the iCloud contest
  archive, so it was a stored-history migration too. Shipped as sketched:
  [`ScoreFactor`](../../Sources/Core/Parties/ScoreFactor.swift) is an exact
  rational (numerator/denominator, never a `Double`), a party file writes the
  number the sponsor prints (`1.5`), the archive keeps its whole-number key and
  adds `categoryFactorExact` beside it, and the sidebar renders "×1.5" without
  float formatting. **The rounding rule: down, once, on the whole
  `points × multipliers` product, before bonuses.** Neither sponsor states one
  — VTQP's only rounding instruction anywhere is rule 7(B)(f)'s grid-square
  count, *"dividing by 3, and rounding down"*, and WIQP's rules, multiplier list
  and Cabrillo guide contain no rounding language at all — so down is the
  sponsors' own idiom where either states one, and elsewhere the direction that
  cannot overstate a claimed score. Party-free commit (Article 4), every
  existing party's score proved unchanged by the full suite;
  `ScoreFactorTests.testOnlyTheRosteredPartiesShipAFractionalFactor` is the
  roster that makes a party gaining a fraction deliberate. **VTQP and WIQP each
  gained the field in their own commit** (Article 9), and both parties' "score is
  a floor" caveat is gone — the score is the sponsor's.
- ~~**THE EXCHANGE CANNOT CARRY A NAME.**~~ **Done 2026-07-27.** The second and
  third users arrived at once — the **North American QSO Parties, CW and SSB**
  (NCJ; not State QSO Parties, deliberately absent from the Challenge's
  approved list, requested by KE5CW) — which met the two-user bar and the
  sketch shipped nearly unchanged: `QSO.nameSent/nameRcvd`,
  `PartyDefinition.exchangeIncludesName`, `ContestLog.exchangeName` (the
  contest-long sent name, set in Contest Setup and stamped per row), Cabrillo's
  ex1 element preferring name → serial → report, ADIF `name`/`my_name`, a
  `{NAME}` macro in the party-default message shapes, and a received-name
  field on the entry row's Space chain that **gates logging** — rule 12 counts
  only a complete copied exchange. One sketch item died on contact:
  `ExchangeParser` learned no `NAME LOC` form, because Space is a field
  separator, not a token separator — the name is its own field, like the
  serial. MNQP's flag flipped in its own commit and its `exportBlocking`
  caveat closed: **no bundled party's export is blocked any more**, pinned by
  `CaveatRosterTests.testNoPartyIsExportBlocked`. NAQP itself needed **no
  other schema change**: its 46-of-47 country checklist rides in the county
  slot (the BCQP precedent), and its no-mult `DX` token is the NDQP shape.
  Design: [`2026-07-27-name-exchanges-design.md`](../superpowers/specs/2026-07-27-name-exchanges-design.md).
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

  **LAQP is the second user of ILQP's direction, added 2026-07-26 — and the first
  where the grouping moves the SCORE.** Its rules are ILQP's: "once on CW/Digital
  and once on Phone PER BAND", and "CW/Digital and Phone contacts count as
  separate multipliers". But ILQP counts multipliers **once overall**, so only its
  dupe accounting was wrong; **LAQP counts them per band and mode**, so the
  over-count propagates into the final score. That makes this gap score-affecting
  for the first time.

  **VTQP is the third user, and it wants the opposite grouping** — a *finer*
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
- **FT4/FT8 cannot be excluded while other digital modes are allowed — SECOND
  USER FOUND 2026-07-26, so the two-user bar is met and this is now buildable.**
  ILQP: "FT4 and FT8 contacts will receive no contact credit. Other digital modes
  are encouraged." **NDQP: "Digital = (RTTY/PSK), NO FT8"** — the same rule from
  a different sponsor, and both admit RTTY and PSK alongside the exclusion. That
  is below the granularity of `ModeClass`, which has one `.digital` case.
  `QSO.rawMode` already carries the concrete mode, so the fix is a party-level
  list of excluded raw modes consulted where `allowedModeClasses` already is, in
  `ScoreEngine.score`'s invalid-mode filter. The harm stays small per party (an
  FT8 QSO scores locally and earns nothing from the sponsor), but it is now two
  sponsors' stated rules going unmodelled. Recorded in `ilqp.json` and
  `ndqp.json` as KNOWN LIMITATION 2 in both.

- **The DX-prefix gate costs a party where DX pays points but no multiplier.**
  Added 2026-07-26 by NDQP. `ExchangeParser.acceptsDXPrefix` only guesses at
  DXCC prefixes where `dx` is a multiplier class for that operator — deliberately,
  because the guess is loose enough to validate every mistyped county, and the
  comment there says so. North Dakota is the first party where that gate has a
  cost: its rules ask DX stations for a **country** ("DX Stations give RST and DX
  country") while granting ND entrants no DX multipliers, so the gate is shut and
  a bare `DL` cannot be logged. `dxStyle: "prefix"` would not help — it is inert
  under the same gate, *and* it would drop the literal `DX` token, leaving no way
  to log the contact at all. `token` therefore ships and the operator enters `DX`.
  **The score is unaffected** (DX is never a multiplier there, and every mode pays
  one point), so this is a fidelity gap in the recorded exchange, not a scoring
  one. Georgia has the same points-but-no-multiplier shape and is unaffected,
  because its DX stations send the literal token by rule. A fix would separate
  "may I guess a prefix" from "is DX a multiplier" — perhaps gating on
  `dxStyle == .prefix` instead, which is what the setting was named for.
  Recorded in `ndqp.json` as KNOWN LIMITATION 1.
- ~~**Self-activation multipliers.**~~ **Done 2026-08-04**, all five sponsors,
  one commit each after a party-free engine commit (Articles 4 and 9).
  `MultRule.activatedCountyMultiplier`, and **every field is required** because
  no two of the five agree on any of them:

  | | `minCount` | `countUnit` | `countScope` | `categories` | `notOtherwiseWorked` |
  | --- | --- | --- | --- | --- | --- |
  | SCQP | 1 | qsos | `perBandMode` | mobile, portable, expedition | **false** |
  | NCQP | 1 | qsos | `once` | **all six** | true |
  | VAQP | 10 | **stations** | `once` | mobile, rover, expedition | true |
  | MOQP | 50 | qsos | `once` | mobile, portable, expedition | true |
  | TnQP | 10 | qsos | `once` | mobile, rover | true |

  **The sketch this entry carried was wrong on four of the five axes**, and is
  recorded here rather than deleted because the way it was wrong is the lesson.
  It proposed `{minQSOs: Int}`, inheriting the side's `countScope` and gated on
  `isRovingCategory` — written when TnQP and SCQP were the only known users.

  - **The unit is not always QSOs.** VAQP counts "10 (ten) or more different
    **stations**"; TnQP's near-identical sentence counts QSOs. One chaser worked
    on ten bands satisfies one and not the other.
  - **The scope is never inherited.** TnQP grants "**one** multiplier" while
    counting worked multipliers per band, so the side's scope is the wrong
    answer for the one party the sketch was written from.
  - **It is not a roving-category rule.** NCQP says "**NC stations**", naming
    Mobile and Portable only as the multi-county case, so a fixed NC station
    counts the county it sits in.
  - **Whether working the county forfeits it is per sponsor.** TnQP and VAQP
    say so outright; NCQP's printed "164 total possible" and MOQP's "115
    maximum" are exactly their entity lists and so say it by arithmetic; SCQP,
    alone in printing no ceiling, lists worked and activated counties as
    separate numbered multipliers and is additive.

  `MultKey` gained an `activated` component for that last one, and
  `wouldAddMultiplier` a net-gain check so the NEW MULT badge does not promise a
  multiplier the forfeit takes away. COQP was checked and does **not** need any
  of this — its activation rule is a bonus only.

  Design:
  [`2026-07-28-activated-county-multipliers-design.md`](../superpowers/specs/2026-07-28-activated-county-multipliers-design.md).
  SCQP left the badge roster: this was its only `scoreAffecting` caveat.
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
- ~~**DXCC prefixes shadowed by state/province codes.**~~ **Done 2026-08-01.**
  Fixed exactly as this entry predicted — with the callsign, not the exchange
  token. Where a received token is both a state or province code and a real
  DXCC prefix, the worked callsign decides, and only when it resolves to the
  very same entity the token names: `PA0AAA` sending `PA` is the Netherlands,
  `W3XYZ` sending it is Pennsylvania, and a `VE5` sending `SK` stays
  Saskatchewan even though `SK` is Sweden's. A US or Canadian call never flips
  the reading, which keeps Alberta's `AB` a province despite falling inside the
  ARRL list's US block `AA-AK`. `SalmonRunTests` now pins the new behaviour
  from both sides. Note the old entry mislabelled `OK` as Slovakia; it is the
  Czech Republic.
- ~~**No DXCC prefix table.**~~ **Done 2026-08-01.** `Resources/DXCC` carries
  the ARRL DXCC List (Current Entities, January 2026 edition), generated by
  [`gen_dxcc.py`](../research/gen_dxcc.py) with the document's own stated total
  of 340 as the count assertion. `multContributions` uses the `call` parameter
  it used to ignore, and the new `dxCountsEntities` rule flag is what turns
  entity counting on — additively, so the 29 DX-counting parties whose sponsors
  have not been re-read score exactly as before.
  **Six parties opted in:** NHQP (its 10-entity cap binds at last), MEQP (the
  largest single scoring gap in the repo — every entrant, uncapped, per band
  *and* per mode), NMQP, OQP and WARUN. NDQP took the prefix form without
  entity counting, since DX earns it no multiplier.
  **Three more closed on the way:** MSQP's grid squares and FQP's ITU-region
  tokens no longer become phantom DXCC entities, and the in-state loose guess
  is gone from all sixteen prefix parties.
- ~~**The other DX-counting parties are unsurveyed.**~~ **Surveyed 2026-08-01.**
  All 35 parties carrying `dx` in a multiplier class were re-read against their
  banked sponsor rules. **22 count DXCC entities individually** and now set
  `dxCountsEntities`; **13 grant exactly one DX multiplier** and are correctly
  left alone, which is what makes the flag opt-in rather than global:

  | Sponsor counts entities (22) | Sponsor grants one DX mult (13) |
  | --- | --- |
  | alqp azqp deqp fqp idqp ilqp laqp mdc meqp msqp neqp newenglandqp nhqp nmqp okqp oqp sdqp sevenqp tnqp tqp vtqp warun | arqp coqp hqp ksqp miqp mnqp moqp ncqp njqp ohqp paqp qcqp vaqp |

  The "one DX" side is quoted, not inferred — OhQP's multipliers end "and 1 DX",
  MnQP gives "1 multiplier for working a DX station", MoQP "an additional
  multiplier of the value of one", CoQP "one DX multiplier if any DX station is
  worked", MiQP lists "'DX' (a non-W/VE station)", and NJQP's own sample log
  counts `DX` as one of nine unique multipliers.

  **NCQP was flipped and reverted the same day.** Its research write-up says
  "This includes US Territories, Mexican provinces, and DXCC countries", which
  reads like plural counting but describes what *qualifies* as DX; the rules
  themselves say "only one 'DX' multiplier is applied … representing all DX
  worked", and the sponsor's stated in-state maximum of 164 is what caught it —
  `NorthCarolinaQSOPartyTests` failed on the flip. Worth remembering: a
  qualifying clause is not a counting clause.

  **Three parties were decided on thin evidence and want a fresh sponsor read**
  before 2027: `hqp`, `ksqp` and `vaqp` have no DX-multiplier sentence in their
  banked rules at all. All three are left at one DX multiplier, which is the
  conservative reading, but none of them is *quoted*.
- **`gen_parties.py` cannot be run.** It opens `KSQP-Mults.txt` and
  `TX_county_abbrevs.txt`, neither of which was ever committed — checked with
  `git log --all --diff-filter=A`, and it has been this way since the generator
  landed in `1c4c7be`. That is a standing Article 2 violation: `alqp`, `ksqp`
  and `tqp` have a generator whose raw sources are not banked, so their JSON
  cannot be reproduced. `alqp` and `tqp` needed `dxCountsEntities` from this
  survey and had to be edited in the JSON directly, with the generator patched
  to match for whenever its sources are restored.
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
- [ ] docs: README table row + test count, `PARTIES.md` entry, `PROVENANCE.md` sources
- [ ] committed alone
