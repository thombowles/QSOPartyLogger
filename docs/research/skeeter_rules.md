# NJQRP Skeeter Hunt — 2026 Rules Research

Researched 2026-08-04 for Mac contest logger implementation. Not a State QSO
Party — a four-hour QRP sprint, added at KE5CW's request (he is Skeeter #20
this year, and took High Score TX in 2025). The Article 15 template is applied
with the county sections answered honestly: this contest has no counties.

## 1. Sponsor / sources

- Sponsor: **NJQRP Club** (New Jersey QRP Club, njqrp.club). Contest manager:
  Larry Makoski, **W2LJ**, who runs the event on his own pages and inbox.
- **Current rules (2026): W2LJ's blog page**, "NJQRP Skeeter Hunt",
  http://w2lj.blogspot.com/p/njqrp-skeeter-hunt.html — names the **15th
  Annual** event and prints the 2026 date. Fetched 2026-08-04, banked as
  [`skeeter_rules_2026.txt`](skeeter_rules_2026.txt).
- **Official webpage (stale as of fetch): https://www.qsl.net/w2lj/** — titled
  "Official NJQRP Skeeter Hunt Webpage" but still carrying the **2025** (14th
  Annual, "Sunday August 17th, 2025") edition and the 2025 results on
  2026-08-04. Banked as [`skeeter_qslnet_page_2025.txt`](skeeter_qslnet_page_2025.txt).
  Every rule below is identical between the two pages except the date and the
  roster link; quotes are from the blog (current) edition.
- **2026 Skeeter number roster** (live Google Sheet, linked from the blog page:
  "The entire 2026 Skeeter Hunt roster can be seen"):
  https://docs.google.com/spreadsheets/d/17QjNLUKwkfC2T8_NQEG1Ny7Y4a-BBqtv/
  — CSV export banked 2026-08-04 as [`skeeter_roster_2026.csv`](skeeter_roster_2026.csv).
  **The sheet's document id changes every year** (numbers are reissued each
  season); the *blog page* is the stable discovery point.
- **2025 final scoreboard** (sponsor's own scoring arithmetic, used to verify
  the score formula in §8):
  https://docs.google.com/spreadsheets/d/1_aNsVnye-9wEzbMRU8jkRZScMIaYZoD9M-7lCpTwveE/
  — banked as [`skeeter_scoreboard_2025.csv`](skeeter_scoreboard_2025.csv).
- Skeeter number requests and **log submission**: `w2ljqrp@gmail.com`
  (plain-text in the blog page; the qsl.net copy Cloudflare-obfuscates it).
- WA7BNM Cabrillo name registry (contestcalendar.com/cabnames.php, fetched
  2026-08-04): **no entry** for Skeeter Hunt or NJQRP — see §12.

## 2. Dates and times for 2026, in UTC

> "The event is to be held on Sunday August 16th, 2026. It will be a four hour
> sprint - from 17:00 UTC to 21:00 UTC (1:00 TO 5:00 PM EDT)."

- Concretely: **2026-08-16 17:00:00Z → 2026-08-16 21:00:00Z**, one window.
- The sponsor states no recurrence formula; the printed date is the rule.
  (2025 ran Sunday Aug 17; both dates happen to be third Sundays of August,
  but that pattern is observation, not sponsor text.)
- Sponsor-internal wrinkle, no scoring effect: number issuance is stated both
  as "no sooner than 12:01 AM EDT on June 21st" and "from June 20th (the First
  Day of Summer) through the day before the event".

## 3. Exchange

> "Exchange -
> Skeeter Stations - RST, S/P/C , Skeeter number
> Non-Skeeter Stations - RST, S/P/C , Output power (For example - 559 NY 5W)"
>
> "Note: For those of you new to contesting, \"S/P/C\" refers to your
> \"State\" (US), \"Province\" (Canada), or \"Country\" (DX)."

- **No home region.** Every entrant — New Jersey included — sends the same
  shape. NJ is not special in any rule.
- The third element is **member number or power**: a bare number for Skeeters
  ("NR 13" in the sample QSO), an output power for everyone else ("5W").
  Sample QSO text: "BK TU UR 559 NJ NR 5960 BK - if he had a Skeeter number.
  If he's not a Skeeter, he would send: BK TU UR 559 NJ 5W BK".
- DX form: the country is the C in S/P/C — a DX station sends its country.

## 4. QSO points

Points are **by what the worked station is, not by mode**:

> "Scoring -
> Working a Skeeter Station - 3 points
> Working a non-Skeeter, but QRP station - 2 points
> Working any other QRO station - 1 point"

- The received third element decides: a Skeeter number → 3; a QRP power → 2;
  otherwise → 1.
- "QRP" is not further defined in the scoring text. The event's own power rule
  is "Power - 5W max CW, 10 Watts max SSB", so this implementation reads a
  received power as QRP at **≤ 5 W on CW and ≤ 10 W on phone** (inference,
  recorded in the party's notes).

## 5. Dupe rule

> "NOTE: Stations can be worked on different bands for QSO points, but
> S/P/C's only count once for multiplier credit. For example. if you work
> W2LJ on 40, 20 and 15 Meters, that would count as three different Skeeter
> QSOs, but you can only count NJ once for S/P/C muliplier credit." [sic]

- Re-working on a **new band** is explicitly a new QSO.
- Same band, other **mode** (a Mixed entrant working W2LJ on 40 CW and 40
  SSB): the rules do not say. OPEN QUESTION — this app ships its only dupe
  scope, band × mode, which counts such a contact; a stricter per-band-only
  reading would not. Categories are mode-split (§11) so the case arises only
  for Mixed entries.

## 6. Multipliers

- One class family: **S/P/Cs — states, provinces, and DX countries as peers —
  counted once for the contest**, per the §5 quote. No per-band, no per-mode,
  no cap, and no in-state/out-of-state asymmetry (there is no in-state).
- Each DX **country** is its own multiplier (that is what the C in S/P/C is);
  countries are counted individually like states, so `dxCountsEntities` and
  the prefix exchange form apply.
- The sponsor publishes no state/province token list. Defaults apply: the
  standard state table (DC included, as its own multiplier — unstated by the
  sponsor either way) and the standard 13 provinces. The 2026 roster's own
  S/P/C column stays inside those tables (44 distinct values incl. BC, ON,
  QC), which is consistency evidence, not authority.
- The 2025 scoreboard's S/P/C column ranges 0–34 with no value near a per-band
  product, confirming the once-per-contest scope arithmetically.

## 7. Bonus stations and bonus points

No bonus stations. One bonus rule, **"Skeeter Hunt Blackjack"** (returning
from 2025 — the bonus gimmick historically changes some years; re-check each
season):

> "This year we are going to again play \"Skeeter Hunt Blackjack\". Work
> enough call sign numbers to add up to exactly 21 and you can earn a one
> time 1,000 Bonus Points!"
>
> "Each call area number is worth that many points with the \"0\" area call
> signs being worth 10 points. So for example - if you work N0SS, W2LJ,
> WD8RIF and W1PID that equals 10 +2 + 8 + 1, which adds up to 21 ... You
> just have to come up with a combination of callsigns that add up to exactly
> 21."
>
> "You can use any call sign worked ONCE. And to claim the bonus points, you
> MUST include the call signs worked when submitting your Log Summary."

- Once, +1,000, when some subset of distinct worked callsigns' call-area
  digits (0 counts as 10) sums to exactly 21. Each callsign usable once in
  the sum; how many QSOs you had with it is irrelevant.
- The digit for non-US call shapes is not defined by the sponsor (inference:
  this implementation reads the first decimal digit in the callsign).

## 8. Final-score multipliers — station class, and the verified formula

> "Station Classes and Multipliers
> X1 Home stations - commercial transceiver or separates
> X2 Home stations - home brewed or kit built transceiver or separates
> X3 Portable station - commercial transceiver or separates
> X4 Portable station - home brewed or kit built transceiver or separates"

- Mobile counts as portable: "Mobile stations (which are considered to be
  portable stations for this event)". Kit-built counts as home-brew per the
  page's own Q&A ("The operator's hands were involved in more than 50% of the
  building of the kit").
- **The class factors are not a product of two axes** (home/portable ×
  commercial/homebrew would give 1/2/3/6, the sponsor prints 1/2/3/4) — the
  class is an irreducible four-way choice the entrant declares.
- The rules never print the total-score equation. **Verified from the
  sponsor's own 2025 final scoreboard** (columns: Skeeter QSOs, Non-Skeeter
  QRP QSOs, Non-QRP QSOs, S/P/C, Station Class, Bonus Points, Total):

  **total = (3·skeeterQSOs + 2·qrpQSOs + 1·qroQSOs) × S/P/Cs × class + bonus**

  Exact on every row checked, including:
  - AD0YM (1st): (3·42+2·4+60)·32·4 + 1000 = 25,832 ✓
  - NK9G (2nd): (3·58+2·16+8)·28·4 + 1000 = 24,968 ✓
  - W4MPS (3rd): (3·41+2·21+34)·30·4 + 1000 = 24,880 ✓
  - KE5CW (High Score TX): (3·48+2·7+29)·24·3 + 1000 = 14,464 ✓
  - W2LJ: (3·35+2·5+0)·21·4 + 1000 = 10,660 ✓

  `gen_skeeter.py` re-derives this from the banked scoreboard as its count
  assertion (Article 2's analogue for a party with no counties).

## 9. County-line / multi-county rules

None — the contest has no counties and no mobile-county concept. One location
per entrant; "Please let me know if you intend to operate from a state other
than your home state" is roster bookkeeping, not a mid-contest change rule.

## 10. Valid bands

The rules list operating frequencies ("The QRP \"Watering Holes\"") on
**80, 40, 20, 15 and 10 meters** for both CW and SSB, and no others — no
160 m, no WARC, no VHF. The frequencies are "suggested starting points"; the
band set is taken from them as the only bands the sponsor names (inference,
recorded in notes).

CW: 3.560, 7.040/7.030 (novice segment 7.114–7.122), 14.060, 21.060, 28.060.
SSB: 3.985, 7.285, 14.285, 21.385, 28.885 (novice 28.385).

## 11. Categories

> "Categories: CW Only and SSB Only, or Mixed Operating will be considered
> separate categories."

- Multi-op is acknowledged informally ("this will be considered a separate
  operating class") — submission is by summary email, so no Cabrillo
  category mapping matters.
- Modes: "Mode – CW, SSB" — **no digital**.
- Power limits (entry condition, not a category): "Power - 5W max CW,
  10 Watts max SSB".

## 12. Cabrillo `CONTEST:` header

**None exists, anywhere.** The sponsor accepts no log files at all — "Please
no ADIF, Cabrillo or N1MM files!" — submission is a plain-text summary email
within 14 days. The WA7BNM registry (the Article 1 fallback authority) has no
Skeeter Hunt or NJQRP entry (fetched 2026-08-04; nearest matches are other
clubs' AGCW-QRP / UFT-QRP). The schema requires a value, so the app ships the
invented `SKEETER-HUNT`, declared as a cosmetic caveat: no recipient of this
header exists.

Sample summary from the rules (what the operator actually submits):

> "Larry - W2LJ - NJ / Skeeter #13 - All CW / Single Op / Skeeter QSOs - 23 /
> Non-Skeeter QRP QSOs - 5 / Non-Skeeter QRO QSOs - (if any) / S/P/Cs - 18 /
> Station Class Multiplier X4 / Bonus - List of stations with call sign
> numbers adding up to exactly 21."

## 13. County list

**There is none, deliberately** — the multiplier classes are the default
state/province tables plus DXCC entities, all already bundled. `counties` is
empty, which needed a one-line loosening of `PartyDefinition.validate()` for
`hasHomeRegion == false` parties (its own party-free commit).

The **Skeeter number roster** is the party's prefill data instead (call →
name, S/P/C, number). Shape of the banked 2026 CSV (fetched 2026-08-04,
**live — it grows until the day before the event**, so the app re-fetches):
header `Skeeter #, Call, Name, S/P/C, Mode, …scoreboard columns…`; **187
assigned numbers** so far (43 further pre-numbered rows sit blank awaiting
assignment, and trailing scoreboard rows are blank); W2LJ is #13, KE5CW is
#20. Maintainer quirks the parser
must survive: whitespace around calls (" N2TO"), typo S/P/C values (",SC",
"IA+") which simply fail exchange validation and are never offered, trailing
blank/formula rows, and one call listed under two numbers (K3UT, #25 and
#183). Roster data is a hint, never a rule (Article 1): every offered value
passes the party's own parser first, and nothing from it reaches scoring —
points come from the received exchange, not from roster membership.

## 14. Engine shapes to watch

1. **Member-number-or-power exchange element** (new, `memberExchange`): a
   third exchange token beside RST and S/P/C — digits = member number, else a
   power (`5W`, `500MW`, `2.5W`, `1KW`). Sent value is contest-long (like the
   NAQP name); received value is per-QSO and gates logging.
2. **Points by worked-station class** (new): 3/2/1 from the received member
   element (§4), mode-independent — the first party whose points table is
   decided by the received exchange content.
3. **Entry classes** (new, `entryClasses`): a party-declared list of
   self-assessed classes with exact factors (X1–X4). Not expressible as
   `scoreMultipliers` (not a product, §8); the operator picks one in Contest
   Setup and the factor rides the existing `categoryFactor` path.
4. **Blackjack bonus** (new `BonusRule.callAreaSum`): subset-sum over
   distinct worked calls' area digits, 0→10, target 21, +1000 once.
5. **Empty county list** (`validate()` change gated on `hasHomeRegion ==
   false`).
6. **Roster download** (new `CallHistorySource` kind): discovery from the
   stable blog page URL → this year's Google Sheet link → CSV export →
   converted to the N1MM call-history text shape at install, so the store,
   parser, and prefill pipeline are untouched. The N1MM community listing has
   no Skeeter file (inventory grep 2026-08-04), so the N1MM path cannot serve
   this party.
7. **No home region** — NAQP's `hasHomeRegion: false` shape reused as-is.
8. Dupe-scope question (§5) ships as `bandMode` with a `ruleInference`
   caveat.
