# 7th Call Area QSO Party — rules research

Per [Article 15](../CONSTITUTION.md#article-15--research-before-code). All
quotations are the sponsor's own words, from the documents in §1.

**The first multi-state party in the app**, and it is **eight states, not the
seven the worklist's sketch listed** — §2 is about that.

## 1. Sponsor / sources

| | |
| --- | --- |
| Sponsor | a consortium coordinated by the **Central Oregon DX Club** (CODXC), with per-state coordinators |
| **Rules** | <http://7qp.org/new/Page.asp?content=rules> — headed "7th Call Area QSO Party -- 2026 Rules", dated 02/09/2026 |
| **State/County list** | <http://7qp.org/new/Page.asp?content=geo> |
| Cabrillo name | WA7BNM Contest Calendar, Cabrillo Names table (Article 1 exception — §10) |
| Fetched | **2026-07-26** |

Banked verbatim: [`sevenqp_rules_2026.txt`](sevenqp_rules_2026.txt),
[`sevenqp_counties_2026.tsv`](sevenqp_counties_2026.tsv),
[`sevenqp_cabrillo_name.txt`](sevenqp_cabrillo_name.txt).

`7qp.org` serves a meta-refresh to `/new/page.asp?content=start`; the rules and
county list are tabs off that. The site footer reads *"Site last updated on:
June 7, 2026"* and it carries the 2026 results, so this is current rather than a
rollover.

## 2. Eight states, not seven

The worklist's sketch listed **AZ ID MT NV OR UT WY** — seven — presumably
because Washington runs its own Salmon Run. It does, **and it is also in the 7th
call area**, which is what W7 means. The sponsor's own States & Counties page
carries eight state headers, and the generator counts them rather than trusting
the sketch:

| | | | |
| --- | --- | --- | --- |
| AZ Arizona 15 | ID Idaho 44 | MT Montana 56 | NV Nevada 17 |
| OR Oregon 36 | UT Utah 29 | **WA Washington 39** | WY Wyoming 23 |

**259 counties**, which is the sponsor's own stated total in its scoring rule —
so the count verifies itself.

Washington therefore appears in two bundled parties, on different weekends,
which the tests pin.

## 3. The exchange code already carries the state

> "Exchange state and county, e.g. **AZYVP for Yavapai AZ**."
>
> "7th-area stations send signal report plus **5-letter state/county code**
> (e.g., ORDES; see list). County-line stations send multiple codes, e.g.,
> **UTRIC/IDBEA** (state code needed only once, e.g., ORDES/JEF). Non-7th-area
> stations send signal report plus state/province/"DX" two-letter codes."

So a code is a 2-letter state followed by a 3-letter county, and **`County.state`
is a decomposition of what the sponsor already prints** rather than an invention
of this app.

That is also why **county names repeat freely** — Lincoln exists in six of the
eight states — while the 5-letter codes stay unique. The usual "names must be
unique" assertion does not apply to this party and the generator says so.

**A county line here can cross a state line**: `UTRIC/IDBEA` is Rich, Utah
against Bear Lake, Idaho. No single-state party can express that.

## 4. Dates and times for 2026, in UTC

> "**1300 UTC Saturday to 0700 UTC Sunday** (6 AM to midnight PDT the **first
> Saturday in May**)."

| Start | End | Length |
| --- | --- | --- |
| `2026-05-02T13:00:00Z` | `2026-05-03T07:00:00Z` | **18 h**, one window |

Both local glosses convert correctly (PDT is UTC−7), and the generator asserts
the arithmetic rather than the text.

## 5. Bands, modes and points

> "Bands: **160, 80, 40, 20, 15 and 10m.**"
>
> "**2 points per SSB QSO, 3 points per CW QSO, 4 points per Digital QSO.**"

**Digital pays most here**, which few parties do.

> "Work stations once per band/mode… The same station may be worked on each band
> on CW, Phone, and Digital."

→ `dupeScope: "bandMode"`.

> "Any computer-to-computer mode is considered digital. **WSJT modes do not
> support the 7QP exchange, so are not allowed.**"

That exclusion cannot be enforced — see §9.

## 6. Multipliers

> "**7th-area stations** multiply total QSO points by the total of **states (50),
> provinces (13) and other DXCC entities (maximum of 10)** worked.
> **Non-7th-area stations** multiply total QSO points by **7th-area counties
> (259)** worked."

| | In-area | Out-of-area |
| --- | --- | --- |
| Classes | states + provinces + **DX, capped at 10** | **259 counties** |
| Scope | once overall | once overall |

- **`homeStateCountsViaCounty: true`**, and this is where the schema change
  earns its keep: a station inside the call area receives county codes, and each
  one credits **its own** state. One log earns Arizona, Oregon, Washington and
  Wyoming separately.
- **No member state is a loggable token** — `excludedStateTokens` defaults to
  all eight, so a bare `WA` is refused; its stations send `WAxxx`.
- **`dxMultCap: 10`**, which the rules state and which can never bind (§9).

## 7. Out-of-area credit

> "7th call area stations work everyone, **others work 7th-area stations only**."

## 8. County lines

> "County-line operations must be **within 500 feet** of the county line."
>
> "County-line contacts may be logged with **one entry showing all counties or
> with separate entries for each county**."

**No maximum is stated** — the schema default of 4 ships. **OPEN QUESTION 1**.

## 9. Engine shapes to watch

1. **The DXCC cap can never bind.** §6. Non-7th-area stations send the literal
   `DX`, so every entity collapses to one multiplier and the count never
   approaches ten. Same shape as New Hampshire's, and the **fourth** party
   wanting a DXCC prefix table.
2. **"WSJT modes … are not allowed" cannot be enforced.** §5. `ModeClass.digital`
   covers RTTY and PSK, which this party *does* allow, alongside FT8, which it
   does not. **Fourth user** of that gap, after Illinois, North Dakota and
   Nebraska.
3. **The county-line shorthand is not accepted.** The sponsor allows `ORDES/JEF`,
   where the second county reuses the first's state; this app wants
   `ORDES/ORJEF`. A keystroke difference, not a scoring one.

## 10. Cabrillo `CONTEST:` header

**Not named**, though the rules require Cabrillo. `7QP` comes from WA7BNM's
Cabrillo Names table under [Article 1](../CONSTITUTION.md)'s exception.

## 11. Spot hub

**None.** `7qp-table.php` 302-redirects to `imlogin.php?loginstatus=-3`, a login
page — the same trap California's `qp-table.php` sets, where a guessed prefix
yields a poller that runs forever, never errors and shows nothing. `hubSpots` is
`nil`.

## 12. Open questions

1. **No maximum for simultaneous counties.** §8. The rules require operation
   within 500 feet of the line and print a two-county example, but cap nothing.
   The default 4 ships, which never refuses a legal exchange.
