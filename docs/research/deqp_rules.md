# Delaware QSO Party — rules research

Per [Article 15](../CONSTITUTION.md#article-15--research-before-code). All
quotations are the sponsor's own words, from the document in §1.

**Three counties — the smallest list in the app — and the one party where the
list is the only easy thing about it.** The newest rules are titled 2024, they
state no contest times at all, and QSO points depend on which side of the state
line you are on.

## 1. Sponsor / sources, and a redirect chain that lands short

| | |
| --- | --- |
| Sponsor | **First State Amateur Radio Club** (FSARC) |
| **Rules** | <https://www.fsarc.org/qsoparty/rules-2024.html> — the newest edition published |
| Cabrillo name | WA7BNM Contest Calendar, Cabrillo Names table (Article 1 exception — §9) |
| Fetched | **2026-07-26** |

Banked verbatim: [`deqp_rules_2024.txt`](deqp_rules_2024.txt),
[`deqp_cabrillo_name.txt`](deqp_cabrillo_name.txt).

**`rules-2025.html` and `rules-2026.html` both 404.** The 2024 edition is the
newest the sponsor has, which is why this party is `verified: partial`.

**And the site's own links land two editions short**, which is the part worth
recording:

| Entry point | Where it ends |
| --- | --- |
| `/qsoparty/rules.htm` — the obvious URL | → `rules-2022.htm` → **`rules-2023.html`**, and stops |
| `/qso-rules` — the home page's own link | → **`rules-2024.html`**, the current one |

So a session that guessed `rules.htm` would ship the 2023 rules believing them
current. Every `Last-Modified` on the site reads 2026-07-17 — a server-wide
touch — so header dates prove nothing here either.

The sponsor's `2026_results.htm` exists, so the party did run in 2026.

## 2. Dates — and the hours that come from nowhere

> "Date: **First full weekend in May**"

That is the whole of it. **The rules state no contest times anywhere**; the only
mention of UTC is *"Logs should indicate times in UTC"*, which is about log
format.

| Start | End |
| --- | --- |
| `2026-05-02T17:00:00Z` | `2026-05-04T00:00:00Z` |

- **The date is the sponsor's.** The first full weekend in May 2026 is the 2nd
  and 3rd.
- **The hours are not.** 1700Z–2359Z comes from the SQP Challenge calendar.
  [Article 19](../CONSTITUTION.md) wants the sponsor's own times and there are
  none to have, so the calendar's ship with this flagged. **OPEN QUESTION 1.**

## 3. Exchange

> "Delaware stations send signal report and **county**. Stations outside Delaware
> send signal report and **state, province or DX**."

→ `dxStyle: "token"`, `exchangeIncludesRST: true`.

## 4. Counties

> "The county designations are: New Castle County **NDE**, Kent County **KDE**,
> Sussex County **SDE**."

Three, printed twice — in the header and again in the multiplier rule — and the
generator requires both copies to agree. **The code is the county's initial plus
`DE`**, not a truncation, so New Castle is `NDE` and not `NEW`.

## 5. QSO points — which side of the line you are on

> "Stations **inside** DE earn **1** point per phone QSO, **2** points for digital
> QSO, and **2** points per CW QSO. Stations **outside** DE earn **10** points per
> phone QSO, **20** points per digital QSO and **20** points per CW QSO."

**Exactly ten times as much**, and keyed on the *entrant's* location — which the
schema cannot express, because `pointsTable(forTheirLoc:countyAbbrs:)` keys on
what you *receive*. See §8, limitation 1.

## 6. Multipliers

> "Multipliers are counted only once. **Multipliers are by Band.**"
>
> "Delaware stations use, **states, Canadian provinces, and DXCC countries**.
> Stations outside Delaware use Delaware counties, New Castle (NDE), Kent (KDE),
> and Sussex (SDE)."

| | In-state (DE) | Out-of-state |
| --- | --- | --- |
| Classes | states + provinces + DX — **no counties** | **3 counties** |
| Scope | **per band** | **per band** |

**Delaware entrants get no county multipliers**, which the rules confirm from
the other direction:

> "Delaware stations may contact other Delaware stations but **only count for QSO
> point credit**."

> "Power Multiplier … Greater than 100 watts, total score **×1**; 100 watts or
> less, **×2**; 5 watts or less, **×3**."
>
> "Final score = the total of QSO points × location multipliers × power
> multiplier, **+ 50 point electronic submission bonus** if applicable."

Whole numbers, so the power multiplier ships — the fourth party to manage that.
The submission bonus does not; see §8.

## 7. Bands, modes, county lines

> "Suggested frequencies: **All HF bands excluding WARC bands**."
>
> "DEQP also allows contacts on **any band and mode 6 meters and up** to include
> **repeater contacts within Delaware**. **1 point per voice contact, 2 points
> per digital contact to include CW.**"

VHF and up have their own point values — §8, limitation 2 — and are the only
place in the app where a sponsor permits repeater contacts.

> "Work stations **once per band per mode**. The three valid mode categories are
> **CW, Phone, and Digital**."
>
> "**County line QSOs should be logged as two separate QSOs.**"

→ `dupeScope: "bandMode"`, `maxSimultaneousCounties: 1`.

## 8. Engine shapes to watch

**Four limitations — the most of any bundled party.**

1. **QSO points depend on the entrant's side, and the schema keys them on the
   received location.** §5. `homeStationPoints` fires whenever the received
   location is a Delaware county, which is **right** for every out-of-state
   entrant (all their valid QSOs are with Delaware) and **right** for a Delaware
   station working outside — but **wrong for a Delaware station working another
   Delaware station**, which takes 10/20/20 where the sponsor pays 1/2/2.

   That is the smallest wrong case available: those contacts earn no multiplier
   either way, by the sponsor's own rule, and they are a minority of a Delaware
   log. Modelling it the other way round would be wrong for *every* out-of-state
   entrant, who are the majority. **The fix is to give `pointsTable` the
   entrant's role as well as the received location.**
2. **VHF and up score differently.** §7. Points are keyed by mode, never by
   band, so a 6 m contact scores the HF value. **Second user of the
   points-table gap** after North Carolina's points-by-county and Ontario's
   points-by-callsign — three parties now want that one method to consult more
   than the mode.
3. **The 50-point electronic-submission bonus is not modelled.** It pays for how
   the log is *sent*, not for anything done on the air, and no `BonusRule` shape
   describes that.
4. **FT8/FT4 use a Field Day exchange entirely** — `1A DE` for New Castle, `2A
   DE` for Kent — which is a different exchange *grammar*, not a different
   token. Not modelled.

## 9. Cabrillo `CONTEST:` header

**Not named**, though the sponsor has a whole Cabrillo Info page. `DE-QSO-PARTY`
comes from WA7BNM under [Article 1](../CONSTITUTION.md)'s exception.

## 10. Spot hub

**None** — the hub serves no Delaware table.

## 11. Open questions

1. **What are the contest hours?** §2. The rules give a date formula and no
   times at all. The SQP Challenge calendar's 1700Z–2359Z ships; an operator
   should confirm with FSARC before 2027.
2. **Are the 2024 rules still current for 2026?** §1. No later edition has been
   published, and the 2026 results page exists, so the party ran — but nothing
   states that the 2024 rules governed it.
