# ARS Flight of the Bumblebees — 2026 Rules Research

Researched 2026-08-10 for Mac contest logger implementation. Not a State QSO
Party — a four-hour QRP CW sprint run **twice a year** by the Adventure Radio
Society, the direct ancestor of the NJQRP Skeeter Hunt already bundled
([`skeeter_rules.md`](skeeter_rules.md)). The Article 15 template is applied
with the county sections answered honestly: this contest has no counties. The
next running is the **Fall** event, Sunday 2026-09-20.

## 1. Sponsor / sources

- Sponsor: **Adventure Radio Society** (ARS). The rules page signs off
  "73, Jody – K3JZD on behalf of Russ Carpenter - AA7QU and Richard Fisher -
  KI6SN / The Adventure Radio Society Pioneers".
- **Current rules: the sponsor's own page**
  https://ars-qrp.com/FOBB/FOBB.html — one page carries the whole rule set
  for both annual runnings; at fetch it is headed for the Fall event
  ("Fall Flight of the Bumblebees / Sunday, September 20, 2026"). The page is
  edited **in place** at a stable URL; its only revision marker is a
  "Last Updated : 27JUL26" footer. Fetched 2026-08-10, banked as
  [`fobb_rules_2026.txt`](fobb_rules_2026.txt).
  - The page's HTML `<title>` still reads "Adventure Radio Society 2024
    Flight of the Bumblebees, Sunday, July 28" — stale boilerplate. Never
    read dates from the title; the body is what the sponsor maintains.
- **July (Legacy) edition of the same page**, as the sponsor printed it
  before the July running: Internet Archive snapshot **20260723202047**
  (2026-07-23, three days pre-event) of the same URL, headed "Legacy Flight
  of the Bumblebees / Sunday, July 26, 2026 / 1700 to 2100 UTC". Fetched
  2026-08-10, banked as
  [`fobb_rules_2026_july_wayback.txt`](fobb_rules_2026_july_wayback.txt).
  Every rule below is identical between the two captures except the event
  title/date block; quotes are from the live (Fall) page.
- **Bumblebee number roster** — the sponsor runs a self-serve number system
  on the same site, with public report pages linked from the rules page. The
  full roster ("Click Here to See ALL of the Bumblebees - Sorted by BB
  Number") is a plain HTML table at the **stable URL**
  https://ars-qrp.com/FOBB/Process_Get_All_By_Number.php — columns
  `BB | Callsign | Name | SPC | Expected Location`. Fetched 2026-08-10 (234
  numbers — the July event's roster still being served), banked raw as
  [`fobb_roster_page_2026-07.html`](fobb_roster_page_2026-07.html) and
  extracted to [`fobb_roster_2026-07.csv`](fobb_roster_2026-07.csv).
  Sibling reports exist by SPC (`Process_Get_All_By_SPC.php`,
  `Process_SPC_Count.php`, `Form_Get_One_SPC.php`) and for number recovery
  (`Form_Get_One_Entry.php`); number problems go to
  `fobb-number@ars-qrp.com`.
- **Results venue: 3830scores.com** — the rules designate it outright
  ("If you choose to report your results, go to 3830scores.com, and select
  the 'ARS FOBB'"). The July 2026 edition's claimed scores
  (https://www.3830scores.com/editionscores.php?arg=RvJxJizV77DLxU, header
  "ARS Flight of the Bumblebees — 2026 Jul 26 Claimed Scores", 99 scores)
  were fetched 2026-08-10 and extracted to
  [`fobb_3830_claimed_2026-07.csv`](fobb_3830_claimed_2026-07.csv) — used in
  §8 to corroborate the score formula on the sponsor-designated calculator's
  own arithmetic.
- **Log submission: there is none.** No Cabrillo, no ADIF, no email log —
  reporting is the 3830 form plus optional soapbox; photos go to
  `fobb-pictures@ars-qrp.com`. See §12.
- WA7BNM Cabrillo name registry (contestcalendar.com/cabnames.php, fetched
  2026-08-10): **no entry** for Flight of the Bumblebees, FOBB, or the
  Adventure Radio Society — see §12.
- N1MM community call-history listing: **no FOBB file** —
  [`n1mm_callhistory_inventory.json`](n1mm_callhistory_inventory.json) has
  zero FOBB/Bumblebee matches (grep 2026-08-10), so the N1MM path cannot
  serve this party (the Skeeter situation exactly).
- The ARS blog (arsqrp.blogspot.com), which carried FOBB announcements
  through 2023, is **dormant** — newest post January 2024 (checked
  2026-08-10). It is superseded by ars-qrp.com and was not relied on.

## 2. Dates and times for 2026, in UTC

> "The Flight of the Bumblebees is a four-hour event held twice each Year
> - Annually on the last Sunday of July.
> - Annually on the 3rd Sunday in September."

Both 2026 dates are **printed by the sponsor**, one per page capture, and
both agree with the stated formula:

- **Legacy (July): 2026-07-26 17:00:00Z → 2026-07-26 21:00:00Z** — "Legacy
  Flight of the Bumblebees / Sunday, July 26, 2026 / 1700 to 2100 UTC"
  (Wayback capture of the sponsor's page, §1). Last Sunday of July 2026 ✓.
  Already run; 3830 carries its results.
- **Fall (September): 2026-09-20 17:00:00Z → 2026-09-20 21:00:00Z** — "Fall
  Flight of the Bumblebees / Sunday, September 20, 2026 / 1700 to 2100 UTC"
  (live page). Third Sunday of September 2026 ✓. This is the next running.

Both windows ship in `schedule` (Article 19, target year only — the NAQP CW
precedent for a twice-a-year contest, two windows in one party). The page's
time table pins the zone conversions: "ZULU 1700 to 2100 EDST / EASTERN 1300
to 1700 EDST / CENTRAL 1200 to 1600 CDST …" — note the ZULU line's "EDST"
is the sponsor's typo (Zulu is Zulu); 1700Z = 1:00 PM EDT ✓. Recorded so
nobody "fixes" the banked text later (the NHQP "Merrimac" habit).

## 3. Exchange

> "EXCHANGE
> If you are a Bumblebee:
> - RST
> - Your State, Province, or Country
> - Your BB Number
> If you are a Home Station:
> - RST
> - Your State, Province, or Country
> - Your Power Output"

- **No home region.** Every entrant sends the same shape; there is no
  in-state/out-of-state anywhere in the rules.
- The third element is **member number or power** — exactly the
  `memberExchange` shape the Skeeter Hunt introduced. Bumblebees are the
  portable stations: "(The 'Bumblebees' are the stations that are operating
  out in the field)."
- **The number is what makes a Bumblebee contact, not the callsign suffix.**
  "Bumblebees will add /BB to their calls." and "(NOTE: Home-based stations
  do not ever add /BB to their callsign.)" — but the identification rule is
  "Bumblebees will put a /BB after their Call, **and/or** will give you a BB
  Number", and the POTA/SOTA note settles it: "As long as a Bumblebee Number
  is sent in the Outgoing Exchange, that will be a valid FOBB Bumblebee
  Contact."
- DX form: the country is the C in S/P/C — a DX station sends its country.
  No token list is published; the standard state/province tables and DXCC
  prefixes apply (defaults, as in the Skeeter Hunt).

## 4. QSO points

**The rules print no per-QSO points at all** — scoring is the §8 product,
in which every valid contact counts one [Total Contact]:

> "([Total Contacts] includes both Bumblebees and non-Bumblebees)"

Mode cannot differentiate points: the event is CW-only (§11). In this app
the ×3 constant of the §8 formula is folded into the per-QSO points (3
points per valid contact), so the sponsor's product falls out of the
engine's `points × multipliers` shape exactly — see §14.

## 5. Dupe rule

> "You can work each Bumblebee or Home Station once on each Band."

- Re-working the same station on a new band is explicitly a new contact:
  "Working the same station on a different band counts as another contact."
- The app's one dupe scope, band × mode, **coincides exactly** with the
  sponsor's per-band rule because only one mode is legal (CW) — the
  Skeeter Hunt's Mixed-entry open question does not arise here.

## 6. Multipliers

**The S/P/C is exchanged but is NOT a multiplier.** The only thing that
multiplies is the count of Bumblebees worked:

> "Keep track of how many Bumblebee you work - that total will be needed."
> [sic]

> "Working the same Bumblebee on a different band counts as an additional
> Contact **and as an additional Bumblebee Worked**. So, try looking for
> Bumblebees on all of the bands that are open during this event."

- [Number of Bumblebees] therefore counts **per band**: one Bumblebee
  worked on three bands is three contacts and three Bumblebees toward the
  multiplier. Same band twice is a dupe (§5), so the count equals the number
  of valid contacts whose received element is a BB number.
- No cap, no in/out asymmetry (there are no sides), and no other multiplier
  class of any kind. The sponsor's per-SPC roster reports (§1) are number
  bookkeeping, not scoring — no counting phrase attaches to S/P/C anywhere
  (the NCQP lesson: a qualifying clause is not a counting clause; here there
  is not even a qualifying clause).
- **The multiplier defaults to 1, printed in the scoring block:** "(Defaults
  to [Total Contacts] = 1 and [Number of Bumblebees] = 1)" — a home station
  that works no Bumblebee still scores contacts × 1 × 3. See §8 and OPEN
  QUESTION 1 for the one zero-case wrinkle.

## 7. Bonus stations and bonus points

**NONE.** No bonus stations, no bonus points, no Blackjack-style gimmick
anywhere on the page (contrast the Skeeter Hunt). Looked for explicitly.

## 8. Final-score multipliers — the printed formula, and its verification

> "SCORING
> Total Scores will be Automatically Calculated using this Formula:
> [Total Score] = [Total Contacts] x [Number of Bumblebees] x 3
> Working the same station on a different band counts as another contact.
> (Defaults to [Total Contacts] = 1 and [Number of Bumblebees] = 1)
> Separate Reports will be available for the 'Home' and the 'Bumblebee'
> entrants."

No station classes, no power factors, no self-declared entry classes
(contrast Skeeter's X1–X4) — the ×3 is a constant for everyone.

**Verified against the sponsor-designated calculator's own arithmetic**: all
**90 of 90** parsed rows of the July 2026 claimed-scores table
([`fobb_3830_claimed_2026-07.csv`](fobb_3830_claimed_2026-07.csv)) satisfy
`score = QSOs × Bumblebees × 3` exactly, including:

- N5GW (top Bumblebee LP): 79 × 52 × 3 = 12,324 ✓
- N8EU: 80 × 38 × 3 = 9,120 ✓
- W4KAC (BB #7 in the banked roster): 34 × 32 × 3 = 3,264 ✓
- KO4BHX/BB (call reported with the /BB suffix): 25 × 24 × 3 = 1,800 ✓
- N9JL (Home section): 10 × 10 × 3 = 300 ✓
- G4CIB/P (DX entrant): 1 × 1 × 3 = 3 ✓
- K4UPG: 0 QSOs, 0 Bumblebees → **0**, not the 1 × 1 × 3 = 3 a literal
  both-defaults reading would give. See OPEN QUESTION 1.

`gen_fobb.py` re-runs this verification over the banked CSV as its Article 2
assertion (the no-county analogue, exactly as `gen_skeeter.py` does).

**OPEN QUESTION 1 — the zero-Bumblebee log.** The printed line says both
factors default to 1; the calculator's one observed zero row (K4UPG, 0/0)
computed 0. The two agree on every real case but diverge on edges: this app
scores `points × max(1, bumblebees)`, which gives an empty log 0 (matching
K4UPG) and a bee-less log with contacts `contacts × 3` (matching the printed
default). A log with contacts but zero Bumblebees has never been observed on
3830, so that reading is unconfirmed by data. Cost if wrong: a bee-less
log's score reads N×3 here and might be 0 at the sponsor — no real entrant
class is likely to hit it.

## 9. County-line / multi-county rules

None — no counties, no mobile-county concept, no location-change rule of any
kind. The roster's "Expected Location" column is free-text bookkeeping.

## 10. Valid bands

The rules list "TARGET SCENTS (FREQUENCIES)" on **80, 40, 20, 15 and 10
meters** — 3.566, 7.036, 14.036, 21.036, 28.036, each "+/-" — and no
others: no 160 m, no WARC, no VHF. "(You can be anywhere – These are just
suggested gathering spots)" loosens the *frequencies within a band*, not the
band set; the five listed bands are the only bands the sponsor names
(inference, recorded in the party's notes — the identical inference the
Skeeter Hunt ships).

Note the July 2023-era rules (old ARS blog) listed only 40/20/15/10; the
current page adds 80 m. The current page is the authority.

## 11. Categories

> "WHO CAN PLAY?
> Home Based Stations and Portable QRP Stations"

- Two reporting populations, **Home** and **Bumblebee**: "Select 'Home' or
  'Bumblebee' so that you end up in the proper Results List". Same formula,
  separate lists — a reporting split, not a scoring class.
- Power is an entry condition, not a category: "Open to all QRP CW
  operators", "Participating FOBB Home Stations are expected to be running
  5W QRP Maximum", and non-QRP stations are workable but cannot enter —
  "You run QRP CW – You can work Non-QRP Stations", "(POTA Hunters and SOTA
  Chasers running more than 5W QRP cannot Submit FOBB Results)". A
  Bumblebee unable to get a hunter's power should "not dwell on it - it is
  a FOBB Contact - move on."
- 3830's results table further splits each list into QRP/LP power sections
  (July 2026: `Bumblebee QRP`, `Bumblebee LP`, `Home QRP`, `Home LP`) —
  that is 3830's own machinery, not the sponsor's rules; not modelled.
- Mode: CW only (the event is defined as "QRP CW Contacts"; no phone or
  digital appears anywhere).

## 12. Cabrillo `CONTEST:` header

**None exists, anywhere.** The sponsor accepts no log files at all —
results are self-reported totals on the 3830 form ("You will enter your
[Total Contacts] that you made and the [Number of Bumblebees] that you
worked"). The WA7BNM registry (the Article 1 fallback authority) has no
FOBB/Bumblebees/ARS entry (fetched 2026-08-10). The schema requires a
value, so the app ships the invented **`ARS-FOBB`** (matching 3830's "ARS
FOBB" listing name and the registry's sponsor-prefix idiom), declared as a
cosmetic caveat: no recipient of this header exists. The export exists for
the operator's own records; the score sidebar keeps [Total Contacts] and
[Number of Bumblebees] on screen, which is the whole 3830 submission.

## 13. County list

**There is none, deliberately** — the exchange's S/P/C is validated against
the app's standard state/province tables plus DXCC prefixes (§3) and earns
nothing (§6), so there is nothing to enumerate. `counties` is empty under
the `hasHomeRegion: false` gate the Skeeter Hunt already opened.

The **Bumblebee number roster** is the party's prefill data instead
(call → number, SPC, name), served at a stable URL (§1) rather than
Skeeter's per-season Google Sheet. Shape of the banked July 2026 capture:
header row `BB | Callsign | Name | SPC | Expected Location`; **234 assigned
numbers**, all numbers unique; K2SQS is #1, W4KAC #7, K4KBL #234. Quirks
the parser must survive, observed in the banked file: **one call under two
numbers** (NN5DE — the Skeeter K3UT case), mixed-case free-text locations,
and names ranging from a first name to full names. Numbers are **per-event
and reissued**: "Bumblebee Numbers are only valid for One FOBB Event. You
must request a new sequentially issued BB Number for each ARS FOBB Event",
with self-serve opening "One Month Before the Event Date" — so the table
resets for September (~2026-08-20) and grows until the event; between
events it serves the *previous* event's numbers. Roster data is a hint,
never a rule (Article 1): every offered value passes the party's own
parsers first, and nothing from it reaches scoring — Bumblebee credit comes
from the received exchange, not roster membership.

## 14. Engine shapes to watch

1. **`memberExchange` — reused as-is, no schema change.** Term "Bumblebee
   number" / "BB #" / plural "Bumblebees"; `memberPoints = qrpPoints =
   otherPoints = 3` (every valid contact pays the same; the element decides
   *Bumblebee-ness*, never the rate — the ×3 fold of §4);
   `qrpMaxWatts` 5/5/5 from the event's own "5W QRP Maximum" (drives only
   the sidebar's QRP/QRO split, cosmetic here). A blank element is simply
   not a Bumblebee — the sponsor's number-decides rule (§3), not a caveat.
2. **Points by worked-station membership as a MULTIPLIER (new).** The §8
   product needs the multiplier side to be "valid contacts whose received
   element is a member number, counted per band, floored at 1". Sketch: a
   new `MultClass.member` whose contribution fires when the row's
   `memberRcvd` parses as a number — key value the raw logged callsign,
   scope from the ordinary `countScope: perBand` — so the NEW MULT badge,
   sidebar count and roster machinery all work unchanged; plus a
   `MultRule.multiplierFloor` (default 0 = today's behavior; FOBB sets 1)
   applied as `max(floor, min(count, cap))`. An empty log still scores 0
   because `qsoPoints` is 0 (the K4UPG row).
3. **Roster download (new `CallHistorySource.Kind`).** Stable report URL,
   no discovery hop (simpler than Skeeter): GET the PHP page → parse the
   HTML table (explicit failure on shape drift, never a silent empty) →
   convert to the N1MM call-history text shape (S/P/C in State, BB number
   in Exch1) → existing token/store/parser/prefill pipeline untouched.
   **Emit each Bumblebee under both `CALL` and `CALL/BB`** — bees sign /BB
   on the air (§3) and `CallHistoryFile.entry(for:)` is an exact-match
   lookup, so the double row is what makes prefill fire however the
   operator types the call. Live data on the daily staleness clock, no
   revision short-circuit (numbers issue until the event; the table resets
   per event).
4. **Two windows, one party** — the NAQP CW twice-a-year precedent (§2).
5. **No home region** — `hasHomeRegion: false`, `homeState: "NA"`,
   `counties: []`, exactly the Skeeter/NAQP shape.
6. **DX prefix with no DX multiplier class** — `dxStyle: "prefix"` +
   `acceptsDXToken: true` and no `dx` in `classes`: loggable, validated,
   never multiplies. NDQP proved the prefix-without-counting form, NAQP the
   token-with-no-class form; FOBB combines them (a DX station sends its
   country, §3, and nothing multiplies, §6).
7. **/BB suffixes ride the call field as typed.** Dupe identity and the
   member-mult key both read the raw call, the app-wide convention — a bee
   logged `K3JZD/BB` on 40 m and `K3JZD` on 20 m is two contacts and two
   Bumblebees (correct: different bands); the pathological same-band retype
   under two spellings is ordinary call-typo variance, shared with every
   logger, and not modelled. 3830 shows both forms in the wild (KO4BHX/BB,
   AC6J/BB).
8. **No entry classes, no bonuses, no score multipliers, no serials, no
   names** — all absent, all explicit in §§7–8.
