# Indiana QSO Party — rules research

Per [Article 15](../CONSTITUTION.md#article-15--research-before-code). All
quotations are the sponsor's own words, from the documents in §1.

**Two things a stale source gets wrong**, and one of them is a trap the page
sets for scrapers rather than for readers — §5.

## 1. Sponsor / sources

| | |
| --- | --- |
| Sponsor | **Hoosier DX and Contest Club** (HDXCC) |
| **Rules** | <http://www.hdxcc.org/inqp/rules.html> — "2026 Indiana QSO Party Rules", `Last-Modified: 2026-03-14` |
| **County list** | <http://www.hdxcc.org/inqp/counties.html> |
| Cabrillo name | WA7BNM Contest Calendar, Cabrillo Names table (Article 1 exception — §10) |
| Fetched | **2026-07-26** |

Banked verbatim: [`inqp_rules_2026.txt`](inqp_rules_2026.txt),
[`inqp_counties_2026.tsv`](inqp_counties_2026.tsv),
[`inqp_cabrillo_name.txt`](inqp_cabrillo_name.txt).

## 2. Dates and times for 2026, in UTC

> "Contest starts at **1500 UTC** Saturday and ends at **0259 UTC** Sunday the
> **first full weekend of May**. (Saturday **11am to 11pm EDT or 10am to 10pm
> CDT**.) **For 2026, this is May 2-3.** All stations may operate the full
> **12-hour** period."

| Start | End | Length |
| --- | --- | --- |
| `2026-05-02T15:00:00Z` | `2026-05-03T03:00:00Z` | 12 h |

**Indiana straddles two time zones and the sponsor gives both** — Eastern and
Central — and both convert correctly. The tests check them against
`America/Indiana/Indianapolis` and `America/Chicago` rather than against the
prose.

It shares 2 May with the 7th Call Area and Delaware.

## 3. Exchange — a five-character state+county code

> "Indiana stations send RS(T) plus their **INQP exchange** from this list. For
> example, an Indiana station in Marion county would send "**59 INMRN**".
> Non-Indiana stations in the USA and Canada send RS(T) and state, province or
> territory. All others send RS(T) and "**DX**"."

**The same code shape as 7QP's** — `IN` + a three-letter county — but Indiana is
a single state, so no county carries a `state` and the multi-state schema added
one commit earlier stays untouched here. `countyAbbrLength: 5`,
`dxStyle: "token"`.

## 4. Bands and modes

> "…on the **160, 80, 40, 20, 15 and 10** meter Amateur bands."
>
> "Stations may be worked once in each mode (CW/phone) on each band… **The same
> fixed station could theoretically be worked twelve times.**"

Six bands × two modes = twelve, the sponsor's own arithmetic. **Digital is never
named anywhere in the rules** → `allowedModes: ["phone", "cw"]`.

> "Repeater, cross-band and cross-mode contacts are not allowed."

## 5. QSO points — changed for 2026, and the old rule is still on the page

> "**Count two points for each complete two-way QSO (both CW and Phone)** —
> **Rule change for 2026.**"

Phone used to be worth one point and CW two. **The old wording is still in the
page**, inside an HTML comment:

```html
<!-- Count one point for each complete two-way phone QSO.
     Count two points for each complete two-way CW QSO. -->
```

So there are two ways to get this wrong: read a 2025 source, or scrape the page
with a flattener that strips the comment *markers* and keeps the text — which
yields both rules at once. The banked text therefore **preserves comments and
marks them** `[[COMMENTED OUT IN THE SOURCE]]`, and the generator asserts both
halves: the new rule is in the live text, and the old rule appears **only**
inside a comment.

## 6. Multipliers

> "Multipliers count **once per mode** (i.e. once on CW and once on phone)."
>
> "**Non-Indiana stations:** The 92 Indiana counties.
> **Indiana stations:** The 92 Indiana counties. **The other 49 U.S. states**
> (District of Columbia counts as Maryland). The 13 Canadian
> Provinces/Territories…"
>
> "Indiana stations may work DX stations for **QSO point credit, but there are no
> DX multipliers**."

| | In-state (IN) | Out-of-state |
| --- | --- | --- |
| Classes | 92 counties + 49 states + DC + 13 provinces, **no DX** | **92 counties** |
| Scope | **per mode** | **per mode** |

- **`homeStateCountsViaCounty: false`** — *"the **other** 49 U.S. states"*.
  Indiana is not a state multiplier; its entrants count the 92 counties directly.
- **`stateAliases: {"DC": "MD"}`**, stated in parentheses.
- **DX pays points and no multiplier** — the third party with that shape, after
  Georgia and North Dakota.

**The sponsor's own worked example is the arithmetic check**, and it checks out:

> "KX9IO … has 354 valid QSOs with stations in 39 states/provinces and 27
> Indiana counties. Total score = ((354) * 2) * (39 + 27) = 708 x 66 = **46,728**"

## 7. Out-of-state credit

> "**Non-Indiana stations may work only Indiana stations.**"

## 8. County lines

> "A county line mobile, portable, or rover may operate from only **one or two
> counties at a time**. **In other words, three and four county operations are
> not allowed.**"

→ `maxSimultaneousCounties: 2`, with the refusal spelled out — which few sponsors
bother to do.

## 9. The county abbreviations changed in 2017

> "**County name abbreviations changed in 2017.** See the revised list here."

`counties-rev2017.html` meta-refreshes to `counties.html`, which is the current
list. **Any pre-2017 list is wrong**, which is worth recording because the older
page still resolves.

`INMRN` is Marion — **`INMAR`, the naive truncation, does not exist**.

## 10. Cabrillo `CONTEST:` header

**Not named**, though the rules discuss the Cabrillo `CLUB:` line at length. So
`IN-QSO-PARTY` comes from WA7BNM under [Article 1](../CONSTITUTION.md)'s
exception.

## 11. Spot hub

**None.** `inqp-table.php` 302-redirects to `imlogin.php?loginstatus=-3`,
exactly as 7QP's does. `hubSpots` is `nil`.

## 12. Engine shapes to watch

**Nothing new and nothing deferred** — Indiana fits the schema exactly, including
the 5-character county code, which 7QP had already exercised one commit earlier.

## 13. Open questions

**None.**
