# Canadian Prairies QSO Party — BLOCKED, and why

**No party was built.** The rules were read in full and are banked; the district
list cannot be obtained without hand-typing it from an image, which
[Article 2](../CONSTITUTION.md) forbids. This file records everything gathered so
the next session starts here rather than repeating the search.

Banked: [`cpqp_rules_2026.txt`](cpqp_rules_2026.txt),
[`cpqp_multipliers_page.txt`](cpqp_multipliers_page.txt),
[`cpqp_counties_page.txt`](cpqp_counties_page.txt).

## What blocks it

**The 62 federal electoral districts exist only as JPEGs.** The sponsor's
Multipliers and Counties pages render every chart as an image
(`…/uploads/2025/04/FEDS_2023_2.jpg`, `AB2023.jpg`, `Calgary2023.jpg`, …), with
**no alt text**, no PDF, no CSV, and no support file on the Software page. The
only machine-readable thing offered is a link to Elections Canada's district
finder, which is a lookup tool rather than a list.

**And the sponsor's own pages disagree about how many there are:**

| Source | Says |
| --- | --- |
| Rules | "**62 districts**" (MB 14, SK 14, AB 34), and "a maximum of **63** multipliers" for in-province stations |
| Multipliers page | "Total **65** Canadian Prairies District Multipliers" |
| Multipliers page | "Total **60** Outside Canadian Prairies Districts Multipliers" |
| Multipliers footnote | "a total of **63** multipliers", and elsewhere "a total of **66**" |

So even a hand-typed list could not be self-checked: there is no agreed count to
assert against. Typing 62 names and codes off a JPEG, against four
contradictory totals, is exactly the failure
[Article 1](../CONSTITUTION.md) and Article 2 exist to prevent.

## Re-attempted 2026-07-26 — still blocked, and nothing has moved

Every path below that could be tried without contacting the sponsor was tried,
by rendering the pages rather than fetching them. **Both blockers are intact.**

| Checked | Result |
| --- | --- |
| `/counties/` | **Unchanged.** 10 JPEGs, **0 tables, 0 alt text** — `FEDS_2023_2.jpg`, `AB2023.jpg`, `Calgary2023.jpg`, `Edmonton2023.jpg`, `REDDEER2023.jpg`, `SK2023.jpg`, `Regina2023.jpg`, `Saskatoon2023.jpg`, `MB2023.jpg`, `Winnipeg2023.jpg`. Still just a link to Elections Canada's lookup tool. |
| `/multipliers/` | **Unchanged, and the contradiction is still in one paragraph:** "a total of **63** multipliers", "Total **65** Canadian Prairies District Multipliers", "a total of **66** multipliers", "Total **60** Outside Canadian Prairies Districts Multipliers". |
| `/software/` | **No data file of any kind.** Confirms N1MM+ support "v1.0.9491 or newer" and DXLog "2.5.33", and offers a call-history file only by emailing VE2FK. No district table. |
| `cpqp.contesting.com/cpqpsubmitlog.php` | **Not the districts.** Its only dropdown is the entrant's *own* location — DX, 13 provinces, 50 states. The robot does not publish what it validates against. |

So the count is still unresolvable from the sponsor's own site, which is the
deeper of the two blockers: even a perfectly OCR'd list of 62 could not be
checked against a page that says 63, 65, 66 and 60.

## What is left to try

Both remaining paths need a decision that is not this repo's to make:

1. **Ask the sponsor for a text list** — `CPQPinfo@ve6hams.ca`, or VE2FK for the
   N1MM call-history file. This is outward-facing correspondence and needs the
   maintainer's say-so, not an agent's. It is also the path most likely to
   work, because N1MM and DXLog both ship a district table, so a machine-readable
   list demonstrably exists somewhere.
2. **Read N1MM+ or DXLog's own data files.** First-party-adjacent and machine
   readable, but they ship inside a Windows installer rather than as a published
   file, so getting one means downloading and unpacking a binary.

**OCR is not a path on its own.** With the totals unresolved it would produce a
list that cannot be asserted, which is precisely what
[Article 1](../CONSTITUTION.md) and Article 2 forbid. Ask the sponsor first;
OCR only becomes viable once someone states the real total.

## What the rules do say, and it is otherwise a clean fit

Everything except the district list was recovered, so the JSON is mostly
decided already:

| | |
| --- | --- |
| Dates | 1700Z 9 May → 0300Z 10 May 2026 — **10 hours**, one window |
| Bands | **10, 15, 20, 40** — four, tying Florida for the narrowest |
| Modes | CW and phone; "once on CW and once on Phone on each of the 4 bands (maximum 8 QSOs with any one station)" |
| Points | **flat 1 point** per QSO |
| Multipliers | **per band**. In-province: 50 states + 13 Canadian areas = 63. Out: the districts |
| DX | "count for QSO credit (1 point each) **but not as a multiplier**" — the fourth party with that shape |
| Credit | "Contacts between non VE/VA 4, 5 and 6 stations do not count for QSO credit" |
| District lines | "a separate QSO and complete exchange must be made and logged for each FED worked" — so 1 |

**It would be the third multi-state party, and the first where `County.state`
does work the code cannot.** 7QP and NEQP both encode the state in the exchange
(`AZYVP`, `MAMID`); CPQP's districts are **bare 3-letter codes** that carry no
province. Yet an in-province station "will receive a **provincial multiplier**
for the first VA/VE 4, 5 or 6 station worked on each band, including their own
province" — which is `homeStateCountsViaCounty` resolving through
`state(forCounty:)` to the district's own province. That is precisely the case
the multi-state schema was built for, and it cannot be derived from the code.

Two further notes for whoever builds it:

- **`provinces` must omit AB, SK and MB**, per the lesson BCQP recorded:
  `validOutStateTokens` unions `provinces` in *after* subtracting
  `excludedStateTokens`, so the home provinces stay loggable otherwise. The
  sponsor's own list of 13 Canadian areas *includes* all three, but they are
  earned through a district, never sent as a bare token.
- **The rules document is muddled about its own year.** Its title says "2025",
  its footer says "Last Update: March 8, 2026", its start date says
  "May 9, 2026" and its **end** date says "May 10, **2025**". The home page's
  "THE 2026 CPQP IS IN THE BOOKS!" settles that the party ran in 2026.
