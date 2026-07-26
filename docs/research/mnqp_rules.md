# Minnesota QSO Party — rules research

Per [Article 15](../CONSTITUTION.md#article-15--research-before-code). All
quotations are the sponsor's own words, from the documents in §1.

The 28th running. **The first party in this repo whose published rules had
already moved past the year being built** — see §1, which is the most important
section here.

## 1. Sponsor / sources

| | |
| --- | --- |
| Sponsor | **Minnesota Wireless Association (MWA)**, club call `W0AA` |
| Rules Committee | `mnqp-committee@w0aa.org` |
| **2026 rules (THE AUTHORITY)** | `MNQP_Contest_Rules rev 31.pdf` — footer on all four pages: **`Rev 31 – December 31, 2025`** |
| 2027 rules (for the diff only) | `MNQP_2027_Contest_Rules_A.pdf` — footer **`June 8, 2026`** |
| County list | <https://www.w0aa.org/wp-content/docs/mnqp/MNQP-MN-Counties.pdf> |
| Main page | <https://www.w0aa.org/mn-qso-party/> |
| Log robot | <https://mnqp.contesting.com/mnqpsubmitlog.php> — Cabrillo **required** |
| Deadline | 7 days after the contest |
| Fetched | **2026-07-26** |

Banked verbatim next to this file:

- [`mnqp_rules_2026_rev31.txt`](mnqp_rules_2026_rev31.txt) — **the authority**
- [`mnqp_rules_2027.txt`](mnqp_rules_2027.txt) — kept only for §14's diff
- [`mnqp_counties.txt`](mnqp_counties.txt), [`mnqp_page.txt`](mnqp_page.txt)

### The retrieval problem, and why it mattered

**w0aa.org no longer publishes the 2026 rules.** The live rules page today reads
*"The MN QSO Party rules were last updated for the 2027 QSO Party"* and links
`MNQP_2027_Contest_Rules_A.pdf`. Taking that document as "the MNQP rules" would
have been wrong in three separate scoring dimensions, because it flags its own
changes:

> **NEW 2027** – Multipliers may be worked once on each mode. In state county
> multipliers no longer count for MN stations while QSO's still count.

> **New 2027** — Phone QSO's equal 2 points each. CW QSO's equal 3 QSO points each.

> **NEW 2027** — Rovers may operate simultaneously from up to 2 counties.

The 2026 edition was recovered from the Wayback Machine snapshot
`20260209103319` — two days after the 2026 contest — whose copy of the rules page
reads *"last updated for the **2026** QSO Party"* and links
`MNQP_Contest_Rules rev 31.pdf`. That is the document §2–§13 below describe.

**Two traps worth recording for the next session:**

1. **The rules page's changelog sentence is stale.** Both the 2026 and the 2027
   versions of the page carry the identical second sentence — *"Changed entry
   deadline to seven days after the contest."* That was the 2026 change; the
   sponsor updated the year and left the note. **The changelog understates the
   2027 revision badly**, and only the PDF's own `NEW 2027` markers reveal it. A
   sponsor's summary of its own changes is not authority for the changes.
2. **`w0aa.org` 404s its own PDFs without a `Referer`.** Every document under
   `/wp-content/docs/mnqp/` returns 404 to a plain fetch and 200 with
   `-e https://www.w0aa.org/mnqp-rules/`. A session that concluded "the rules PDF
   is gone" would be wrong.

Per [Article 20](../CONSTITUTION.md#article-20--updating-an-existing-party) the
diff between the two editions is recorded in full in §14.

## 2. Dates and times for 2026, in UTC

> "Contest runs on the first Saturday of February from 1400 through 2359 UTC
> (8 AM through 5:59 PM CST)." — rev 31, *Time*

The main page prints it one minute longer:

> "Saturday, February 7th, 2026 — Hours: 1400 UTC (8:00 AM CST) to 2400 UTC
> (6:00 PM CST)"

**One window ships:**

| Start | End | Length |
| --- | --- | --- |
| `2026-02-07T14:00:00Z` | `2026-02-08T00:00:00Z` | 10 h 00 m |

**The two documents agree in substance and the difference is notational.** "From
1400 **through** 2359 UTC" is inclusive of the 2359 minute, so the contest is over
at 2400:00 — which is exactly what the main page states outright, in both UTC and
local time. Both are internally consistent (CST is UTC−6: 1400Z = 8 AM ✓,
2359Z = 5:59 PM ✓, 2400Z = 6:00 PM ✓). Ten hours round is also what the State QSO
Party Challenge calendar prints. Nothing here is in doubt; the note exists so
nobody "corrects" the end instant later.

The formula — *"always the first Saturday in February"* (main page) and *"the
first Saturday of February"* (rules) — gives **Saturday 7 February 2026** ✓.

**The sponsor publishes future dates**, which is rare enough to record:

> "Future dates for the Minnesota QSO Party: February 6, 2027 · February 5, 2028
> · February 3, 2029"

Per [Article 19](../CONSTITUTION.md#article-19--the-schedule-is-annual-and-dated)
the JSON carries the **2026** window only; the 2027 date goes in `notes` as
published fact, not into `schedule`.

## 3. Exchange

> "MN Stations: First name & county (three letter designator).
> W/VE Stations: First name and state / province (two letter abbreviation).
> DX Stations: First name only. Section should be logged as DX." — rev 31, *Exchange*

| Role | Sends |
| --- | --- |
| **In-state (MN)** | **First name** + one of the 87 MN county designators |
| **Out-of-state W/VE** | **First name** + 2-letter state or province |
| **DX** | **First name only** — logged as the literal token `DX` |

Three consequences, and the first is the biggest thing about this party:

- **There is no signal report at all.** → `exchangeIncludesRST: false`. MNQP is
  the second party to do this after MDC, and for a different reason: MDC drops
  the report and sends call + location; MNQP drops it and sends **name** +
  location.
- **The exchange carries a NAME, and this repo has nowhere to put it.** `QSO` has
  `call`, `rstSent/Rcvd`, `serialSent/Rcvd`, `myLoc`, `theirLoc` — and no name
  field. The sponsor's own Cabrillo template makes the cost concrete:

  ```
  QSO: 14042 CW 2010-02-06 1200 AC0W       BILL       MOW N2CU       TOM        NY
                                            ^ex1=Name  ^ex2          ^ex1=Name  ^ex2
  ```

  `CabrilloExporter.qsoLine` puts `exchangeNumber(serial:rst:)` in the `ex1` slot,
  which for a party with neither serial nor RST resolves to the **empty string**.
  So an exported MNQP log has the right columns with the names missing, and
  Cabrillo is *required* for submission. This does not affect scoring at all —
  names are not multipliers — but it does block submission. See §14 and KNOWN
  LIMITATION 1.
- **DX sends no location token**, and the sponsor says to log the literal `DX` →
  `dxStyle: "token"`, which also matches the multiplier rule: DX is worth exactly
  **one** multiplier however many entities are worked (§6).

> "Use only one name throughout the contest. Multioperator stations shall use the
> same name on all transmitters during the contest."

MN mobiles/rovers additionally sign the county on their call — *"WØAA/DAK for
Dakota County"* — which is callsign decoration, not part of the logged exchange.

## 4. QSO points by mode

> "Score 2 QSO points for all QSO's, i.e. Phone and CW QSO's equal 2 QSO points
> each." — rev 31, *Scoring*

| Mode | Points |
| --- | --- |
| Phone | 2 |
| CW | 2 |
| Digital | n/a — not a legal mode (§10) |

**Flat, and the sponsor spells out that it is flat.** `points` is
`{phone: 2, cw: 2, digital: 2}`; the digital value is unreachable because
`allowedModes` excludes it, and is set equal so that a future edition adding
digital cannot silently inherit a different number.

> "The final score is QSO points total times multiplier total."

No power multiplier, no station-category multiplier → `scoreMultipliers` absent.
Power decides the entry class only.

## 5. Dupe rule

> "Work stations once per band & mode." — rev 31, *QSO Rules*
> "A station may be worked once on CW and once on Phone." — *Modes*

→ `dupeScope: "bandMode"`.

> "MN mobiles and rovers may be worked once per band & mode from each county, &
> MN mobiles and rovers may work stations once per band & mode from each county."

> "Mobile or rover stations that change geographic area (counties for Minnesota
> stations, state or province for others) are considered to be a new station and
> may be contacted again for QSO points and multiplier credit." — *County Line Operation*

A county change is a new station, not a dupe — already how `DupeChecker` behaves,
since `theirLoc` is part of the key.

## 6. Multipliers

Stated separately per side, and **the sponsor states its own totals**, which is
the cheapest verification available and is asserted by the generator.

> "Multipliers for Minnesota Stations: 87 Minnesota counties, 49 states (does not
> include Minnesota), 1 District of Columbia, 10 Canadian provinces, 3 Canadian
> Territories, and 1 DX; **151 maximum**."
>
> "Minnesota stations may work DXCC countries for points and receive **1
> multiplier** for working a DX station."
>
> "Multipliers for W/VE and DX (outside Minnesota): MN counties: **87 maximum**."
>
> "**Multipliers count once overall - not once per band or mode.**"

| | In-state (MN) | Out-of-state |
| --- | --- | --- |
| Classes | 87 counties + 49 states + DC + 13 provinces/territories + DX | **MN counties only** |
| Scope | **once overall** | **once overall** |
| Stated total | **151** | **87** |

→ `countScope: "once"` on both sides; `inState.classes = [county, state,
province, dx]`, `outState.classes = [county]`. No `dxMultCap` — the cap is
structural, not numeric: `dxStyle: "token"` means every DX contact yields the
single value `DX`, so "1 DX" falls out without a cap.

**The arithmetic reconciles exactly, and pins two schema choices:**

```
87 counties
+ 50 state-class tokens   (acceptedStateTokens = 50 states ∪ {DC}, less
                           excludedStateTokens = {MN}  →  49 states + DC)
+ 13 provinces
+  1 DX
= 151  ✓  the sponsor's stated maximum
```

- *"49 states (**does not include Minnesota**)"* → `homeStateCountsViaCounty:
  false`, stated outright rather than inferred. This is the first party in the
  repo where the sponsor settles that question in its own words in the negative,
  and it is worth contrasting with the 2027 edition, which reverses it (§14).
- *"1 District of Columbia"* counted **separately from the 50 states** → DC must
  stay a loggable token in its own right, and must **not** be aliased. Unlike
  VTQP (`DC → MD`) and MDC, MNQP counts DC as itself. No `stateAliases`.
- 10 provinces + 3 territories = the standard 13, and the county PDF prints them
  with the standard `NL` spelling ("Newfoundland & Labrador NL"). Read rather
  than assumed, per the worklist's recurring judgement call 6.

## 7. Bonus stations and bonus points

**NONE.** Rev 31 defines no bonus station, no bonus points, and no per-county
activation bonus. The Prizes and Awards section is entirely certificates,
plaques and wild rice — awards, not score. `bonuses: []`.

## 8. Final-score multipliers

**NONE.** *"The final score is QSO points total times multiplier total."* Power
level selects the operating class and nothing else. `scoreMultipliers` absent.

Worth noting because it is unusual: **Minnesota stations are capped at 100 W**
(*"Output power for all Minnesota operating classes is limited to a maximum of
100 watts except QRP (5 watts)"*) while W/VE classes go to 1500 W. That is an
eligibility rule, not a scoring one.

## 9. County-line / multi-county rules

> "**No station may claim simultaneous operation in more than one county, state,
> or province.** A mobile, rover or portable station must move to a location
> clearly within the new county before claiming a county change. Common sense and
> safety should be considered when making county changes." — rev 31,
> *County Line Operation*

→ `maxSimultaneousCounties: **1**` — county-line operation is **forbidden**, the
same as ALQP and the opposite of most parties. Entering `AIT/ANO` must fail.

**The 2027 edition reverses this for rovers** (§14) — recorded so a later session
does not read the current rules and quietly widen the 2026 party.

## 10. Valid bands

> "HF: 160m - 10m (excluding WARC bands)." — rev 31, *Bands*
>
> "All classes are restricted to 160 through 10 meters (exclusive of WARC Bands)."
> — repeated in both the MN and W/VE class sections

**Six bands:** `160m, 80m, 40m, 20m, 15m, 10m`.

The suggested-frequency table confirms the list has exactly six members, one
frequency per band per mode, which the generator asserts row for row:

> CW: 1.850, 3.550, 7.050, 14.050, 21.050, 28.050.
> SSB: 1.870, 3.850, 7.250, 14.270, 21.350, 28.450.

No 60 m (outside "160 through 10" as the sponsor uses it, and absent from the
suggested table), no 30/17/12 (WARC, excluded outright), **and no VHF/UHF** —
unlike VTQP, which allows them explicitly. MNQP is HF-only.

> "CW QSOs in the SSB Portion of the HF Bands is not allowed."

## 11. Categories

**MN** (all ≤ 100 W except QRP): Single Op Mixed · Single Op Mixed QRP · Single
Op Phone · Single Op CW · Multi-Op (1–2 transmitters) · **Mobile** (single
transmitter) · **Rover** (single transmitter).

**W/VE**: Single Op Mixed Low (≤100 W) · Single Op Mixed High (≤1500 W) · Single
Op Mixed QRP (≤5 W) · Single Op Phone · Single Op CW · Multi-Op.

**DX**: Unlimited.

> "Operating in two or more classes requires separate unique call sign to be used
> for each class."

Mobile vs Rover is a real distinction here: *"Mobile stations, including
antennas, must be self-contained in or on a vehicle and capable of operating
while moving"*, while *"Rover stations must operate stationery [sic] from at
least two counties using portable, temporary or permanent antennas… An antenna
used for mobile operation cannot be used for stationary operation."*

MN ARES groups enter using `ARES` as their name and compete for a certificate.

## 12. Cabrillo `CONTEST:` header

**`MN-QSO-PARTY`** — from the WA7BNM Cabrillo name registry
(<https://www.contestcalendar.com/cabnames.php>, entry 238, fetched 2026-07-26),
which Article 1 names as the one codified secondary authority, **because the
sponsor prints no `CONTEST:` token** despite requiring Cabrillo. No alias is
registered.

The sponsor does print the QSO-line template (§3), and it is the reason KNOWN
LIMITATION 1 exists.

## 13. County list

**87 counties, uniform 3-letter designators.**

The sponsor's county PDF prints the whole list **twice** — once *"Alphabetical by
County"* and once *"Alphabetical by Designator"* — so the two tables check each
other, and `gen_mnqp.py` requires them to be identical. That is the same
two-source pattern NYQP uses, except here both sources are inside one document.

Spelling anomalies flagged, so nobody "fixes" them later:

1. **`CRL` Carlton and `CRV` Carver and `CRO` Crow Wing** — three counties whose
   names begin `Car`/`Cro`, none of which takes the naive first three letters.
   `CAR` is not a valid designator in this party.
2. **`KNB` Kanabec and `KND` Kandiyohi** — one letter apart, and neither is `KAN`.
3. **`MRS` Marshall, `MRT` Martin, `MUR` Murray, `MOR` Morrison, `MOW` Mower** —
   a dense `M` cluster where only `MUR`/`MOR`/`MOW` are the naive form.
4. **`STL` is "St Louis"** — printed without a period, unlike ILQP's `SCLA`
   "St. Clair". Ship the sponsor's spelling.
5. **`Ottertail` (`OTT`) is one word** in the sponsor's list; the county is
   conventionally "Otter Tail". Ship as printed.
6. `LKW` Lake of the Woods and `LAK` Lake are distinct, as are `RDL` Red Lake and
   `CLE` Clearwater.

*(The same PDF's US-states table misspells Virginia as "Virgina". It is not used
— `MultClass.usStates` supplies the states — but it is noted so a future reader
does not treat that table as authoritative.)*

## 14. Engine shapes to watch

### The Article 20 diff: rev 31 (2026) → 2027 edition

Recorded in full because the live site now serves only the later document, and
because **three of the four changes are scoring changes**.

| Rule | **2026 — rev 31 (shipped)** | 2027 edition |
| --- | --- | --- |
| Multiplier scope | "Multipliers count **once overall** - not once per band or mode." | "**NEW 2027** – Multipliers may be worked **once on each mode**." |
| MN county mults for MN stations | Counted — "87 Minnesota counties, 49 states…; 151 maximum" | "**In state county multipliers no longer count for MN stations** while QSO's still count." |
| Minnesota as a state multiplier | "49 states (**does not** include Minnesota)" | "50 states (**includes** Minnesota)" |
| MN-station totals | 151 maximum | 65 per mode; 130 maximum |
| Out-of-state totals | 87 maximum | 87 per mode; 174 maximum |
| Points | "**2 QSO points for all QSO's**" | "**New 2027** Phone 2, **CW 3**" |
| Rover county lines | "**No station may claim simultaneous operation in more than one county**" | "**NEW 2027** Rovers may operate simultaneously from up to **2 counties**… within 500 feet of the county line" |
| Mobile county lines | forbidden | still forbidden — "Mobile stations may operate in only one county at a time, county line operation not permitted" |
| End time | "1400 through 2359 UTC" | unchanged |
| Log deadline | 7 days | 7 days |

**When MNQP is next re-verified, the 2027 edition is a `homeStateCountsViaCounty:
true` party with `countScope: "perMode"`, points `{phone: 2, cw: 3}`, and
`maxSimultaneousCounties: 2`.** Every one of those is a field this repo already
has, so the 2027 update is data-only — but it is four simultaneous changes, which
is why it must not be done by accident.

### Gaps

1. **THE EXCHANGE CARRIES A NAME AND THIS REPO CANNOT LOG IT.** §3 has the
   detail. `QSO` has no name field, `ExchangeParser` has nowhere to put one, and
   `CabrilloExporter.qsoLine` emits `exchangeNumber(serial:rst:)` — the empty
   string here — in the `ex1` column the sponsor reserves for the name. **Scoring
   is entirely unaffected**: names are not multipliers, not points, and not part
   of the dupe key. Submission is not: Cabrillo is required and the robot expects
   `ex1`. Sketch: `QSO.nameSent/nameRcvd: String?` plus
   `PartyDefinition.exchangeIncludesName: Bool` defaulting false, with `ex1`
   preferring name → serial → RST; the entry bar and edit sheet each gain a
   field, and `ExchangeParser` learns a `NAME LOC` form. That is a cross-cutting
   change touching `Sources/UI/`, so it is its own commit under Article 4 and
   cannot ride along with a party under Article 9. **This is the second party to
   want it in spirit** — MDC already ships a report-free exchange — but the first
   where a *missing* field, rather than an extra one, breaks the export.
2. **No `stateAliases`, deliberately.** DC is its own multiplier here. Recorded
   because two of the three most recent parties alias it and the pattern is easy
   to copy by reflex.

Everything else maps cleanly:

| Rule | Field |
| --- | --- |
| "2 QSO points for all QSO's" | `points {phone: 2, cw: 2, digital: 2}` |
| "once per band & mode" | `dupeScope: "bandMode"` |
| "Multipliers count once overall" | `countScope: "once"`, both sides |
| "49 states (does not include Minnesota)" | `homeStateCountsViaCounty: false` |
| "1 DX" for any number of entities | `dxStyle: "token"` |
| "Phone… CW - only" | `allowedModes: ["phone", "cw"]` |
| no simultaneous multi-county operation | `maxSimultaneousCounties: 1` |
| no signal report in the exchange | `exchangeIncludesRST: false` |
| "all other W/VE & DX work MN stations" | `outStateWorksHomeStationsOnly: true` |
| 1400Z–2400Z, 7 Feb 2026 | `schedule` |

**`outStateWorksHomeStationsOnly` is stated outright** in the first line of the
QSO Rules — *"MN stations work everyone; all other W/VE & DX work MN
stations"* — making MNQP the ninth party to state rather than imply it.
