# Nebraska QSO Party — rules research

Per [Article 15](../CONSTITUTION.md#article-15--research-before-code). All
quotations are the sponsor's own words, from the documents in §1.

**Two retrieval traps and a self-contradicting date**, so §1 and §2 matter more
than usual here. The party itself is the most feature-rich of the season: a
power multiplier, seven bonus stations, a satellite category, and a **second
contest inside the first** for FT8/FT4.

## 1. Sponsor / sources — and what is *not* a source

| | |
| --- | --- |
| Sponsor | **Nebraska QSO Party Committee**; entries to **Matt Anderson KA0BOJ**, ARRL Nebraska Section Manager |
| **Rules** | <https://nebraskaqsoparty.com/qso-party-rules/f/rules-for-2022-nebraska-qso-party> — titled "Rules for **2026** Nebraska QSO Party" |
| **County list** | `…/downloads/Nebraska QSO Party County Abbreviation List.pdf`, `Last-Modified: 2022-03-18` |
| Cabrillo name | WA7BNM Contest Calendar, Cabrillo Names table (Article 1 exception — §11) |
| Fetched | **2026-07-26** |

Banked verbatim: [`neqp_rules_2026.txt`](neqp_rules_2026.txt),
[`neqp_counties_2022.txt`](neqp_counties_2022.txt),
[`neqp_cabrillo_name.txt`](neqp_cabrillo_name.txt),
[`neqp_dot_org_is_not_the_sponsor.txt`](neqp_dot_org_is_not_the_sponsor.txt).

### Trap 1: `nebraskaqsoparty.org` is not the sponsor

The obvious domain serves a **GoDaddy content-farm page** — generic prose
("What Is a QSO Party?", "Why Participate?"), **no rules, no dates, no county
list, no exchange**, and outbound links to a law firm, Nielsen radio ratings,
two universities and NPR. It was last modified the same day this was fetched.

The sponsor is **`nebraskaqsoparty.com`**. The `.org` is banked as a
counter-example so a later session recognises it rather than re-deciding. A
session that trusted it would have found nothing checkable and might have
filled the gaps from recall — the exact failure
[Article 1](../CONSTITUTION.md) exists to prevent.

### Trap 2: the current rules live at a URL that says 2022

The sponsor edits **one post in place** rather than publishing a new one each
year, so the 2026 rules are served from
`…/f/rules-for-2022-nebraska-qso-party`. The post's date reads *January 5,
2025*; its title and body are 2026, and its "Highlights for this Year" names the
2026 changes. WA7BNM links that same URL — correct, but only by the accident of
in-place editing.

### And the body is not in the HTML

The rules render client-side. The static HTML carries only the page shell, and
the site's own RSS and JSON feeds carry **only the title line**
(`<content:encoded><![CDATA[<p>2026 NEBRASKA QSO PARTY RULES </p>]]>`). The
banked text was taken from the rendered page.

## 2. Dates and times — the sponsor contradicts itself

> "Dates/Times. The QSO Party (QP) will be held **over two days**. The QP will be
> **April 25-26**.
> The first day of the QP will start **Saturday, April 25th, 1400 UTC (8:00 AM
> CDT Sat, )** and end **Sunday April 27th at 0200 UTC (08:00 PM CDT)**, Their
> are **no scheduled breaks and you can operate the ENTIRE time scheduled**."

Three things to untangle.

**The span is 36 continuous hours, and that part is solid.** "Two days",
"April 25-26", "end … April 27th at 0200 UTC" and "no scheduled breaks" all
agree: one unbroken window from 1400Z Saturday to 0200Z on the 27th, which is
Sunday evening local. Note that "Sunday April 27th" mislabels the weekday —
27 April 2026 is a **Monday** — but the *UTC date* is right, because Sunday
evening in Nebraska is Monday in UTC.

**The hour does not agree with itself.** April is CDT, which is UTC−5:

| Sponsor's UTC | Sponsor's local | Actual conversion |
| --- | --- | --- |
| 1400 UTC | "8:00 AM CDT" | 1400 UTC = **9:00 AM CDT** |
| 0200 UTC | "08:00 PM CDT" | 0200 UTC = **9:00 PM CDT** |

Both parentheticals are one hour off, consistently — they were computed with
the CST offset (UTC−6) while labelled CDT. So either the UTC figures are right
and the local ones are stale, or vice versa.

**The aggregators split on it**, which is the clearest sign this is a real
ambiguity and not a misreading:

| Source | Window |
| --- | --- |
| **Sponsor (UTC as printed)** | Apr 25 1400Z → Apr 27 0200Z |
| WA7BNM | Apr 25 **1300Z** → Apr 27 **0100Z** — it trusted the local times |
| SQP Challenge calendar | Apr 25 1400Z → Apr **26** 0200Z — right hour, **truncated span** |

**What ships:** `2026-04-25T14:00:00Z` → `2026-04-27T02:00:00Z`. The rules state
UTC first and the local times parenthetically, [Article 19](../CONSTITUTION.md)
puts the sponsor's own rules above any aggregator, and the Challenge calendar
independently agrees on both clock values. **This is OPEN QUESTION 1** (§13) —
an operator who starts at 1400Z loses the first hour if the sponsor meant
1300Z.

**Thirty-six hours in one window** — joint-longest with Hawaii, and behind only
Vermont's 48.

## 3. Exchange

> "For all modes except FT8/FT4 grid-square, stations outside of Nebraska send
> **State, Canadian Province or DXCC Country (S/P/C)**. Stations in Nebraska send
> **NE county**."
>
> "For all modes, **exchange of signal report is optional**."

→ `exchangeIncludesSerial: false`. **RST is optional here**, which no other
bundled party says — MDC drops it entirely, and everyone else requires it.
`exchangeIncludesRST: true` ships, because the field being available costs an
operator nothing and almost everyone sends 59/599; hiding it would lose
information the sponsor is happy to receive.

**`dxStyle: "prefix"`** — DXCC countries are counted individually (§6) and no
literal `DX` token is mentioned anywhere in the rules.

## 4. Modes, and the contest inside the contest

> "Modes. For the regularly scored contest, modes are **CW, Phone (SSB, AM, FM)
> and Digital (RTTY, PSK, and other digital modes, but not FT8/FT4)**. We
> encourage FT8/FT4 participation exchanging grid square, but it will be **scored
> separately**."

> "**Satellite.** Plus a new category for satellite QSO's of 4 points each"

> "Cross mode contacts and repeater contacts are prohibited."

→ `allowedModes: ["phone", "cw", "digital"]`. The FT8/FT4 exclusion is the same
gap Illinois and North Dakota have (§12), and **satellite is a fourth mode the
schema has no case for** — its 4 points cannot be scored.

## 5. QSO points

> "Each unique digital contact is **1** points, Phone is worth **2** points, CW is
> worth **3** points and Satellite is worth **4** points."

Three distinct values, which four bundled parties now have — but Nebraska is
**the only one where digital pays *less* than phone**. North Carolina, New York
and Vermont all rank digital above it; here it is the cheapest contact on the
band.

> "Contacts with the same station on different bands are considered unique, and
> contacts with the same station on the same band but with different modes are
> also considered unique. QSOs with the same mobile/portable station from
> different counties are also considered unique."

→ `dupeScope: "bandMode"`, with the mobile clause the engine already honours.

## 6. Multipliers, and a power multiplier that fits

> "**Geo Multiplier.** For stations outside of Nebraska, this multiplier is the
> total number of Nebraska counties worked. **Count each Nebraska county only
> once per contest.** The multiplier for out-of-state stations has a **maximum of
> 93 counties**."
>
> "For stations in Nebraska … the multiplier is the total number of Nebraska
> counties worked **plus** the total number of States/Provinces/Countries (S/P/C)
> worked. **The maximum number of states worked is 50**, and the maximum number of
> Canadian provinces worked is **13**."

| | In-state (NE) | Out-of-state |
| --- | --- | --- |
| Classes | 93 counties + states + provinces + **DXCC countries** | **93 counties** |
| Scope | **once overall** | **once overall** |

→ `countScope: "once"`, stated twice as "only once per contest".

- **`homeStateCountsViaCounty: true`** — *"The maximum number of states worked
  is **50**"*. Fifty, not forty-nine, so Nebraska is inside it; and NE stations
  send counties, so the token `NE` is never received. Same arithmetic as New
  Mexico.
- **93 counties** is Nebraska's exact count, and the sponsor states it.

> "**Power Multiplier.** … If all QSOs are made QRP (5 watts or less) the power
> multiplier is **5**; if less than 100 watts, the multiplier is **2**; otherwise
> the power multiplier is **1** for over 100 watts."

**Whole numbers, so it ships** — the second party in the app to manage that,
after New Mexico, and with the identical 5/2/1 shape. (Vermont and Wisconsin
still cannot, their low-power factor being ×1.5.)

> "**Final Score equals (QSO Points x Power Multiplier x Geo Multiplier) plus
> Bonus points.**"

That is `qsoPoints * multiplierCount * categoryFactor + bonusPoints`, exactly.

## 7. Out-of-Nebraska credit

> "Objective. Stations outside of Nebraska to work as many Nebraska
> stations/counties as possible. **Stations in Nebraska to work everyone.**"
>
> "…each out-of-state station must copy the NE county."

→ `outStateWorksHomeStationsOnly: true`.

## 8. County lines

> "Nebraska Mobile/Portable stations may operate from county lines, but **only
> two counties at a time**. A single exchange on the air is ok, but **enter it
> twice in the log**, once for each county."

→ `maxSimultaneousCounties: 2`, and the second sentence is `CountyLineExpander`
described from the sponsor's side — one keystroke, two logged rows.

## 9. Bonus points — seven stations

> "There will be **100 bonus points** for any QSO with Nebraska SM **KAØBOJ** and
> **50 bonus points** for all other appointees in the section."

| Call | Role | Points |
| --- | --- | --- |
| `KA0BOJ` | Section Manager | **100** |
| `K0SMM` | ASM/ADEC/AEC | 50 |
| `K0RPT` | SEC/ASM | 50 |
| `K0NEB` | ASM | 50 |
| `NF0N` | STM/ASM | 50 |
| `N0FER` | Technical Coordinator/ASM | 50 |
| `KE0XQ` | ASM | 50 |

→ seven `workStation` bonuses. **The scope is not stated** — "for any QSO with"
reads either as *once, if you worked them at all* or as *for each such QSO*.
`.once` ships as the conservative reading; **OPEN QUESTION 2** (§13).

The sponsor prints these calls with the **slashed zero `Ø`**, which is a
typographic convention, not part of the callsign; they ship as `0`.

> "**RARE GRID BONUS** For the following grid squares (DN91CE, DN91DE, DN91EE) if
> you activate in them you will receive a bonus of 5 points per QSO…"

**Not modelled** — see §12.

## 10. Bands

> "All **VHF/UHF** bands are allowed. **WARC band contacts do not count**."

with recommended frequencies on 1.805/1.915, 3.865, 7.265, 14.265, 21.365,
28.465 and 50.175 — so 160 through 10 plus 6 m, and "all VHF/UHF" adds 2 m,
1.25 m and 70 cm. **Ten bands**, behind Vermont's 13 and New York's 11.

## 11. Cabrillo `CONTEST:` header

**Not named**, though the rules require Cabrillo: *"Only Cabrillo format will be
accepted for electronic logs."* So `NE-QSO-PARTY` comes from WA7BNM's Cabrillo
Names table under [Article 1](../CONSTITUTION.md)'s exception — the fifth in a
row, after North Dakota, Michigan, Ontario and Quebec.

## 12. Engine shapes to watch

**Three things are deliberately not shipped.**

1. **The FT8/FT4 competition is a whole second contest and is not modelled.**
   §4. It has its own point value (2 per QSO), its own multiplier class (**grid
   squares**, capped at 13 for out-of-state entrants), its own power multiplier
   (fixed at 1), its own log, and its own final-score formula. The schema
   describes **one** contest per party; a party with two parallel scoring
   systems has no representation at all. Nebraska's FT8 entrants are out of
   scope for this app, and the rules make that a supported way to enter rather
   than a limitation of the logger.
   *The "not FT8/FT4" exclusion inside the main contest is separately the same
   gap Illinois and North Dakota have — this is its **third** user.*
2. **Satellite QSOs cannot be scored.** §4, §5. `ModeClass` has phone, CW and
   digital; satellite is a fourth thing here, worth 4 points, and a satellite
   QSO logged under any existing mode scores that mode's value instead. First
   user of that gap.
3. **The rare-grid bonus is not modelled.** §9. It pays on *activating* one of
   three named grid squares, and the app has no notion of the operator's grid —
   `activatedCountyCount` keys on counties. The rule's own worked example is
   also internally muddled (it multiplies a 5-point QSO total by a "rare grid
   multiplier of 5" to reach 25). Nothing is invented for it.

Everything else fits, including the two that usually do not:

| Rule | Field |
| --- | --- |
| digital 1, phone 2, CW 3 | `points` |
| satellite 4 | **no mode class — limitation 2** |
| "not FT8/FT4" | **cannot be expressed — limitation 1** |
| "only once per contest" | `countScope: "once"`, both sides |
| "maximum number of states worked is 50" | `homeStateCountsViaCounty: true` |
| **QRP ×5, <100 W ×2, >100 W ×1** | **`scoreMultipliers.power`** |
| seven section appointees | `workStation` ×7 |
| rare-grid bonus | **not modelled — limitation 3** |
| "only two counties at a time" | `maxSimultaneousCounties: 2` |
| 160–10, 6, and all VHF/UHF, no WARC | `validBands` — ten |
| 1400Z Sat → 0200Z Mon | `schedule` — 36 h, one window |

## 13. Open questions

1. **Is the start 1400Z or 1300Z?** §2. The sponsor's UTC figures and its own
   local-time glosses differ by an hour, and WA7BNM reads it the other way from
   the SQP Challenge calendar. **1400Z ships**, per the rules' own UTC and
   Article 19. An operator who starts then loses the first hour if 1300Z was
   meant. Worth an email before the 2027 running.
2. **Are the section-appointee bonuses once or per QSO?** §9. "100 bonus points
   for **any** QSO with…" is ambiguous. `.once` ships as the conservative
   reading; per-QSO across eleven bands and three modes would dominate the
   score, which argues the same way.

## 14. County list

**93 counties**, uniform 4-letter codes, from the sponsor's own PDF — which the
rules describe with unusual candour:

> "NOTE. A list of Nebraska County abbreviations is provided on the website. **It
> is the same list used in 2016.**"

So the file's 2022 date is not staleness; the sponsor intends it to be
unchanged and says which year it dates from.

**The sponsor misspells one county**: `CUMI` is printed as **"Cumming"**, where
Nebraska's is **Cuming**, one *m*. Shipped as printed, per the repo's practice
with NHQP's "Merrimac", NCQP's "Chowen", MOQP's "St. Genevieve", NMQP's "Dona
Ana" and NDQP's "La Moure".

Codes worth checking, all four letters and several sharing three:

| | |
| --- | --- |
| `DGLS` Douglas | *not* `DOUG` — the only code that drops its vowels |
| `CHAS` Chase · `CHER` Cherry · `CHEY` Cheyenne | |
| `DAKO` Dakota · `DAWE` Dawes · `DAWS` Dawson | |
| `FRNK` Franklin · `FRON` Frontier · `FURN` Furnas | |
