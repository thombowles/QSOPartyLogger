# Nebraska QSO Party — rules research

Per [Article 15](../CONSTITUTION.md#article-15--research-before-code). All
quotations are the sponsor's own words, from the documents in §1.

**This file was rebuilt on 2026-07-26 after being overwritten.** The New England
QSO Party is also called NEQP, and when it was built the same afternoon its
research took the `neqp_*` prefix and wrote over Nebraska's — leaving a shipped,
scoring party with no generator and no rules research, which is the hole
[Article 2](../CONSTITUTION.md) exists to prevent. New England now lives under
`newenglandqp_*`; this prefix is Nebraska's alone. Nebraska keeps the id `neqp`
because it follows the state abbreviation, as every single-state party's does,
and the two are unambiguous in Cabrillo regardless: **`NE-QSO-PARTY` here,
`NEQP` for New England.**

## 1. Sponsor / sources

| | |
| --- | --- |
| Sponsor | the Nebraska QSO Party Committee; entries to Matt Anderson KA0BOJ, Raymond NE |
| Rules | [`neqp_rules_2026.txt`](neqp_rules_2026.txt) — re-fetched 2026-07-26 |
| Counties | [`neqp_counties_2022.txt`](neqp_counties_2022.txt) — the sponsor's own County Abbreviation List PDF |
| Cabrillo | [`neqp_cabrillo_name.txt`](neqp_cabrillo_name.txt) — WA7BNM, Article 1 exception |
| Counter-example | [`neqp_dot_org_is_not_the_sponsor.txt`](neqp_dot_org_is_not_the_sponsor.txt) |

**The rules page needs JavaScript.** `nebraskaqsoparty.com` is a GoDaddy builder
site: a plain HTTP fetch of either `/qso-party-rules` or the rules post itself
returns the navigation chrome and no rules at all. The text in
`neqp_rules_2026.txt` was recovered by rendering the page.

**The URL still says 2022 and the dateline says 2025.** The post lives at
`/qso-party-rules/f/rules-for-2022-nebraska-qso-party` and is datelined
"January 5, 2025", while its title and body both say 2026. The body is the 2026
edition — it names the 2026 dates, the 2026 deadline ("May 7th, 2026") and the
new-for-2026 categories. Neither the slug nor the dateline is evidence against
it.

**`nebraskaqsoparty.ORG` is not the sponsor.** It has the obvious domain and is
a content farm; the `.com` is the real site. Banked as a counter-example so the
next reader does not repeat the mistake.

## 2. What the rules say

| | Sponsor's words |
| --- | --- |
| Dates | "start Saturday, April 25th, 1400 UTC (8:00 AM CDT Sat, ) and end Sunday April 27th at 0200 UTC (08:00 PM CDT)" |
| Length | "Their are no scheduled breaks and you can operate the ENTIRE time scheduled" — **36 h in one unbroken window** |
| Bands | "All VHF/UHF bands are allowed. WARC band contacts do not count." |
| Modes | CW, phone, digital — "but not FT8/FT4", which is a separate competition |
| Exchange | "stations outside of Nebraska send State, Canadian Province or DXCC Country (S/P/C). Stations in Nebraska send NE county." |
| RST | "For all modes, exchange of signal report is optional." |
| Points | "Each unique digital contact is 1 points, Phone is worth 2 points, CW is worth 3 points and Satellite is worth 4 points." |
| Power | "QRP (5 watts or less) the power multiplier is 5; if less than 100 watts, the multiplier is 2; otherwise … 1 for over 100 watts" |
| Mults | "Count each Nebraska county, and each S/P/C, only once per contest." |
| County total | "The multiplier for out-of-state stations has a maximum of 93 counties." |
| States | "The maximum number of states worked is 50" |
| County lines | "may operate from county lines, but only two counties at a time … enter it twice in the log" |
| Bonus | "100 bonus points for any QSO with Nebraska SM KAØBOJ and 50 bonus points for all other appointees" |
| Logs | "Only Cabrillo format will be accepted for electronic logs"; deadline "May 7th, 2026" |

**Nebraska is inside the fifty.** "The maximum number of states worked is 50" —
fifty, not forty-nine — and Nebraska stations always send a county, so
`homeStateCountsViaCounty` is `true`. That is the same arithmetic that settles
KSQP, COQP, IAQP and AZQP, and here the sponsor's own total makes it explicit
rather than inferred.

**The county list is deliberately old.** "A list of Nebraska County
abbreviations is provided on the website. It is the same list used in 2016." So
the PDF's 2022 file date is the sponsor's intent, not staleness.

**The sponsor's typos ship as printed** (Article 1): "Their are no scheduled
breaks", "CATAGORIES", "Each unique digital contact is 1 points", and the county
`CUMI` printed as **"Cumming"** where Nebraska's county is Cuming, one `m`. The
generator asserts that last one by name so a silent correction is noticed.

## 3. Open questions

**1. Is the start 1400Z or 1300Z?** April is CDT, UTC−5, so 1400 UTC is 9:00 AM
CDT — but the rules gloss it "(8:00 AM CDT)" and gloss the 0200 UTC finish
"(08:00 PM CDT)" where it is 9:00 PM. Both parentheticals are one hour off,
consistently, as if computed with the CST offset. WA7BNM trusted the local times
and publishes 1300Z–0100Z; the SQP Challenge calendar trusted the UTC. **The
sponsor's own UTC figures ship** per Article 19. Worth an email before 2027.

The finish is labelled "Sunday April 27th", which mislabels the weekday — the
27th is a Monday — but **the UTC date is right**, since Sunday evening in
Nebraska is Monday in UTC.

**2. Are the bonuses once or per QSO?** "100 bonus points for ANY QSO with…" is
ambiguous. Scope `once` ships as the conservative reading, and per-QSO across
eleven bands and three modes would dominate the score, which argues the same way.

## 4. Not modelled

Recorded as caveats on the party, so an operator sees them in the setup sheet:

- **The FT8/FT4 competition is a whole second contest** — its own 2 points per
  QSO, its own multiplier class (grid squares, capped at 13 for out-of-state
  entrants), its own power multiplier fixed at 1, its own log and its own
  final-score formula. The schema describes one contest per party.
- **Satellite QSOs cannot be scored.** `ModeClass` has phone, CW and digital;
  satellite is a fourth thing here worth 4 points, so a satellite QSO scores as
  whichever mode it is logged under.
- **The rare-grid bonus is not modelled.** It pays on activating one of
  DN91CE / DN91DE / DN91EE, and the app has no notion of the operator's grid.
  The rule's own worked example is internally muddled too.

## 5. Regenerating

```bash
python3 docs/research/gen_neqp.py
python3 docs/research/gen_caveats.py   # the generator drops caveats; put them back
```

`gen_neqp.py` reproduces the shipped `neqp.json` **byte for byte**, which is
what establishes that the rebuilt generator derives the party from the sponsor's
sources rather than from the file it was meant to check. Every number it emits
is asserted against a quoted sentence, and the assertions were confirmed live:
removing one county from the list fails with *"the sponsor says 93; parsed 92"*.

The sponsor's PDF is ordered by county **name**; the shipped file is ordered by
**abbreviation**, so the generator sorts. Same 93 pairs either way.
