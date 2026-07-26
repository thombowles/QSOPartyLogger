# Michigan QSO Party — rules research

Per [Article 15](../CONSTITUTION.md#article-15--research-before-code). All
quotations are the sponsor's own words, from the documents in §1.

**The live site had already rolled forward to 2027 when this was built**, so the
2026 edition came from the Wayback Machine and the two were diffed. Exactly one
sentence differs, and §6 is about what it means.

## 1. Sponsor / sources

| | |
| --- | --- |
| Sponsor | **Mad River Radio Club** (MRRC), <https://miqp.org> |
| **Rules (2026)** | [`web.archive.org/web/20260314141558/…/rules/`](http://web.archive.org/web/20260314141558/https://miqp.org/index.php/rules/) — archived **2026-03-14**, five weeks before the contest |
| Rules (live) | <https://miqp.org/index.php/rules/> — by 2026-07-26 the header read "Next MiQP Sat 17 Apr 2027" |
| **Multiplier list (2026)** | [`web.archive.org/web/20260414033926/…/official-list-of-mults/`](http://web.archive.org/web/20260414033926/https://miqp.org/index.php/official-list-of-mults/) — archived **2026-04-14**, four days before the contest |
| Cabrillo page | <https://miqp.org/index.php/cabrillo-information/> |
| Cabrillo name | WA7BNM Contest Calendar, Cabrillo Names table (Article 1 exception — §11) |
| Fetched | **2026-07-26** |

Banked verbatim: [`miqp_rules_2026.txt`](miqp_rules_2026.txt),
[`miqp_rules_live_2027.txt`](miqp_rules_live_2027.txt),
[`miqp_mults_2026.tsv`](miqp_mults_2026.tsv),
[`miqp_mults_live_2027.tsv`](miqp_mults_live_2027.tsv),
[`miqp_cabrillo_2026.txt`](miqp_cabrillo_2026.txt),
[`miqp_cabrillo_name.txt`](miqp_cabrillo_name.txt).

**Both editions are banked and the generator diffs them**, which is the whole
reason the one real change was found rather than absorbed silently.

## 2. Dates and times for 2026, in UTC

> "The Michigan QSO Party (MiQP) occurs annually on the **Saturday of the third
> full weekend in April**. The contest period runs from 1200 EDT (noon in
> Detroit, MI) to 2400 EDT (midnight in Detroit, MI) (**16Z Saturday until 04Z
> Sunday UTC**). All stations may operate the full **twelve hours**."

| Start | End | Length |
| --- | --- | --- |
| `2026-04-18T16:00:00Z` | `2026-04-19T04:00:00Z` | 12 h |

**The rules carry no year at all** — they are a formula, which is why the site
rolling over to 2027 did not corrupt them. April 2026 opens on a Wednesday, so
the full weekends (both days in April) are the 4th–5th, 11th–12th and
**18th–19th**; the Saturday of the third is **18 April**.

**The formula is verified against the sponsor's own arithmetic.** The live
site's header reads *"Next MiQP Sat 17 Apr 2027"*, and April 2027 opens on a
Thursday, so its full weekends are the 3rd–4th, 10th–11th and 17th–18th — the
third Saturday being the 17th. The formula reproduces the sponsor's stated date
exactly, one year out, which is a stronger check than any calendar aggregator.

## 3. Exchange

> "Michigan stations send a **RST, and their Michigan county**.
> Non-Michigan W/VE stations (**including KH6/KL7**) send a RST, and their state
> or province.
> Stations outside of the U.S.A. (**including KP2/KP4**) or Canada send a RST,
> and "**DX**"."

→ `exchangeIncludesRST: true`, `exchangeIncludesSerial: false`,
`dxStyle: "token"` — the sponsor names the token in the rule.

Note the two parenthetical rulings, which settle the awkward cases outright:
**Hawaii and Alaska are W/VE** and send `HI`/`AK`; **the Virgin Islands and
Puerto Rico are not** and send `DX`.

The rules also record a change made four years ago, and the app is on the right
side of it:

> "The Contest Logging Software community was made aware of the **change from
> QSO# to RST for 2022**…"

so a source predating 2022 would have this party exchanging a serial. It does
not.

## 4. Bands and modes

> "**CW and SSB on 80, 40, 20, 15 and 10 meters.** Stations may be worked once
> per band and mode."

**Five bands, two modes** — no 160 m, no 6 m, **no digital**, and the sponsor
works the arithmetic out loud:

> "Example: K8MQP is a station operating from OAKL county. K8MQP may be
> contacted on each of the (5) bands [80m-10m] on each of the (2) modes [CW,SSB]
> for a maximum of **(10) ten QSOs**."

→ `dupeScope: "bandMode"`, `allowedModes: ["phone", "cw"]`. The fourteenth
bundled party with no digital, and the narrowest band list in the app.

> "**No cross-mode contacts.** Both stations must be using the same mode…"

## 5. QSO points

> "Each complete non-duplicate **SSB** contact is worth **one** point. Each
> complete non-duplicate **CW** contact is worth **two** points. Duplicate
> contacts are worth zero points."

## 6. Multipliers — and the one sentence that changed

> "Multipliers are counted **once per mode**. Working the same multiplier on
> both CW and SSB counts as **two multipliers**."

→ `countScope: "perMode"` both sides. The second party this run with that
scope, after Georgia.

**The 2026 and 2027 editions differ in exactly one sentence**, and it is this
one. Diffed line by line by the generator:

| | |
| --- | --- |
| **2026-03-14** | "…the 83 Michigan counties, **49 American states (excluding Michigan)**, and 13 Canadian provinces (NL, NB, NS, PE, QC, ON, MB, SK, AB, BC, NT, YT, NU), and "DX" (a non-W/VE station)." |
| **live (2027)** | "…the 83 Michigan counties, **49 American states (excluding Michigan) + 1 District of Columbia**, 13 Canadian provinces (…), and "DX" (a non-W/VE station)." |

**The District of Columbia was added to the sentence after the 2026 contest.**
The question that matters is whether DC was a multiplier *in 2026*, and the
answer is yes — from a second source, which is why it was worth checking rather
than guessing:

- The rules defer to the multiplier list **twice**, in both editions: *"To
  guarantee multiplier credit in scoring these abbreviations must be used"* and
  *"Note that the official abbreviations must be used to assure scoring
  credit."*
- The **Official List of Mults archived four days before the 2026 contest
  carries `DC DISTRICT OF COLUMBIA`**, and is otherwise identical to the live
  one. The generator asserts both halves of that.

So the 2027 edit is a **clarification of wording, not a change of rule**: DC has
been a multiplier all along, and the sentence simply now says so. Shipping DC as
a multiplier is correct for both editions.

| | In-state (MI) | Out-of-state |
| --- | --- | --- |
| Classes | 83 counties + 49 states + DC + 13 provinces + **DX** | **83 MI counties** |
| Scope | **per mode** | **per mode** |
| Ceiling | **147** per mode, 294 across both | **83** per mode, 166 |

- **`homeStateCountsViaCounty: false`** — *"49 American states (**excluding
  Michigan**)"*. Michigan is not a state multiplier; MI stations count the 83
  counties instead. Same shape as North Dakota one row earlier.
- **DX is a real multiplier here**, worth exactly one per mode, because the
  exchange is the literal token. Michigan is therefore *not* another
  points-but-no-multiplier party — the contrast with Georgia and North Dakota is
  worth keeping straight.
- **The 13 provinces are the app's standard 13**, listed by the sponsor in full
  (`NL … NU`), so no override is needed — unlike North Dakota one row earlier.
  The generator asserts the sponsor's list equals `MultClass.canadianProvinces`.
- **Mobiles get no extra**: *"Multipliers for mobile entrants are the same as
  above and apply to the overall log regardless of the number of counties
  activated."*

**The sponsor's own multiplier table is the arithmetic check.** Its Michigan
table has exactly **147** rows and its non-Michigan table exactly **83**, which
is 49 + 1 + 13 + 1 + 83 and 83. Both are asserted.

## 7. Out-of-state credit

> "For amateurs outside the state of Michigan to make contact with as many
> Michigan stations as possible. **Non-Michigan stations may work only Michigan
> stations**, while Michigan stations may contact anyone."

→ `outStateWorksHomeStationsOnly: true`, in the Object, in the first paragraph.

## 8. County lines — forbidden outright

> "**No station may claim simultaneous operation in more than one county, state,
> or province.** A mobile or rover station must move a **minimum of 500 feet**
> before claiming to be in a new county, state or province."

→ `maxSimultaneousCounties: **1**`, and unlike North Dakota — which permits
parking on the line and merely requires separate contacts — Michigan forbids the
claim itself. It joins ALQP, AZQP, BCQP, HQP, MDC, MEQP, MNQP, MSQP, NHQP, NJQP,
OhQP, SDQP, VAQP and WIQP at 1.

> "Mobile or Rover stations that change the geographic entity they're operating
> from (**counties for Michigan stations, state or province for others**) are
> considered to be a new station and may be contacted again for QSO points and
> multiplier credit."

Note the symmetry: an *out-of-state* rover changing states is also a new
station. `DupeChecker` keys on `theirLoc`, so both halves already work.

## 9. Categories

Single Operator (QRP ≤5 W / low ≤100 W / high >100 W) · Multi-Op
Single-Transmitter · Multi-Op Multi-Transmitter · **Mobile** (≤100 W,
self-contained) · **Rover** (two or more counties, ≤100 W, mains power allowed) ·
**Emergency Operations Center**. All categories are mixed-mode and all-band —
*"There are no single mode categories… There are no single band categories."*

**Power categorises but does not scale.** → no `scoreMultipliers`.

> "Final Score – multiply total QSO points by the total number of multipliers."

## 10. Bonus points

**None.** There is a plaque programme and a certificate programme, but no rule
pays points.

## 11. Cabrillo `CONTEST:` header

**The sponsor has an entire page about Cabrillo and still never names one** —
deliberately:

> "MiQP does **NOT use Cabrillo header info** as it has been found over the years
> to be incorrect. That is why we collect Call, Location, Category and Club info
> when the log file is submitted to the web upload page."

Its worked example carries no header line either:

```
START-OF-LOG: 3.0
QSO: 7040 CW 2021-04-17 1648 K8MQP 599 WASH K8MAD 599 OH
END-OF-LOG:
```

So `MI-QSO-PARTY` comes from WA7BNM's Cabrillo Names table under
[Article 1](../CONSTITUTION.md)'s exception — the second party in a row to need
it, after North Dakota. The example does confirm the **field order and the
county-not-state rule**, which matters more:

> "SentQTH is one of the abbreviations from the official list. **Michigan
> stations must list county abbreviation and NOT MI or MICH or MICHIGAN!**"

## 12. Open questions

**None.** Every rule this app models is stated by the sponsor, the one changed
sentence is resolved by a second source, and the date formula is confirmed
against the sponsor's own future date. The party ships `verified: partial` only
because the 2026 rules came from an archive rather than a live page — the
standard caveat, not an unresolved question.

## 13. Engine shapes to watch

**Nothing new, nothing deferred.** Michigan fits the schema exactly:

| Rule | Field |
| --- | --- |
| SSB 1, CW 2 | `points` |
| CW and SSB only | `allowedModes: ["phone", "cw"]` |
| 80/40/20/15/10 | `validBands` — five, the narrowest in the app |
| "once per band and mode" | `dupeScope: "bandMode"` |
| "counted once per mode" | `countScope: "perMode"`, both sides |
| "49 American states (excluding Michigan)" | `homeStateCountsViaCounty: false` |
| DX is a multiplier, as a token | `dx` in in-state `classes`, `dxStyle: "token"` |
| "may work only Michigan stations" | `outStateWorksHomeStationsOnly: true` |
| "No station may claim simultaneous operation…" | `maxSimultaneousCounties: 1` |
| 16Z–04Z, twelve hours | `schedule` |

## 14. County list

**83 counties**, from the sponsor's Official List of Mults — which prints them
**twice**, once inside the 147-entry Michigan-station table and once alone in
the 83-entry non-Michigan table. The generator parses both and requires them to
agree, so the sponsor's page cross-checks itself.

Codes are four letters with **one exception**: `BAY` for Bay County, which has
only three letters to work with — the same shape as Georgia's `LEE` two parties
earlier.
