# California QSO Party (CQP) — 2026 Rules Research

Researched 2026-07-24 for Mac contest logger implementation.
Written to the [Article 15](../CONSTITUTION.md#article-15--research-before-code) template.

## 1. Sponsor / sources

- Sponsor: **Northern California Contest Club (NCCC)**, sponsoring CQP since 1974.
  2026 is the **61st running**. Contact `info@cqp.org`.
- Rules page (fetched 2026-07-24): https://www.cqp.org/Rules.html — header
  **"Rules: 2026 California QSO Party (CQP) / Last Update: 19-July-2026 at
  1500 UTC"**, five days before this research.
- Official rules PDF, same revision stamp:
  https://www.cqp.org/pdf/CQP_2026_Rules.pdf — extracted to
  [`cqp_rules_2026.txt`](cqp_rules_2026.txt). Page and PDF agree word for word.
- **Superseded revision**, still published:
  https://www.cqp.org/pdf/CQP_2025_Rules.pdf — "Rules: 2025 California QSO Party
  (CQP) / Last Update: 05-July-2025 at 1800 UTC" — extracted to
  [`cqp_rules_2025.txt`](cqp_rules_2025.txt) for the Article 20 diff in §4.
- **Multipliers page**, which carries the county table and the abbreviation
  formula: https://www.cqp.org/cqp_multipliers.html — extracted to
  [`cqp_multipliers.txt`](cqp_multipliers.txt).
- County-line logging guide:
  https://www.cqp.org/files/cqp_how_to_log_a_county_line_qso.pdf — extracted to
  [`cqp_countyline_logging.txt`](cqp_countyline_logging.txt).
- Log submission: robot at http://robot.cqp.org/cqp/logsubmit-form.html, or
  email. **"Logs must be submitted electronically in Cabrillo format – paper,
  Excel, and ADIF logs are NOT acceptable."** Deadline 2359 UTC Monday
  2026-10-19.
- Cabrillo name registry (WA7BNM): https://www.contestcalendar.com/cabnames.php

The rules page and the multipliers page are **not** redundant: the county
abbreviations, the abbreviation formula, the DC→MD fold, the Canadian list, and
the "1st CA county counts as CA" line appear only on the multipliers page.

*(Note for future fetches: `cqp.org` returns 403 for `/Counties.html`,
`/cqp_multipliers.html` and `/pdf/*` unless a `Referer:` header from a cqp.org
page is sent. `/Rules.html` fetches without one.)*

## 2. Dates and times for 2026, in UTC

> "DATES + TIMES: Begins: **1600 UTC - 03 October 2026** Ends: **2200 UTC - 04
> October 2026**"

Printed identically in the PDF, in the rules-page body, and in the site-wide
banner ("1600 UTC October 3, 2026 to 2200 UTC October 4, 2026").

CQP is "held every year on the first weekend of October"; 3–4 October 2026 is
Sat/Sun and is that weekend. **One continuous 30-hour window** —
`2026-10-03T16:00:00Z → 2026-10-04T22:00:00Z`. The 30 hours is corroborated by
the class table, which caps Multi-Single/Multi-Two/Multi-Multi at "30" maximum
operating hours (single-op classes at 24).

No calendar conflict: the State QSO Party Challenge PDF and WA7BNM both give
Oct 3–4, matching the sponsor.

## 3. Exchange

> "1. California stations send **QSO number and 4-letter county abbreviation**.
> 2. Stations outside of California send **QSO number and 2-letter State,
> Canadian province/territory, or "DX"**.
> QSO number = contact serial number starting with 1 for the first contact,
> progressing to 2 for the next contact, and so on. It is unnecessary to send
> leading zeros in the QSO number."

- **There is no RST in the CQP exchange at all** → `exchangeIncludesRST: false`,
  the second party after MDC to leave it out.
- The exchange instead carries a **serial number**, which this repo does not yet
  model. See §14 item 1 — this is the party's one real gap and it is recorded as
  a `KNOWN LIMITATION` in `notes` under
  [Article 17](../CONSTITUTION.md#article-17--mapping-rules-to-the-schema)
  ("a note in `notes` if you ship before the field exists"), not as a rule
  uncertainty.
- DX form: the literal token `DX` → `dxStyle: "token"`. The multipliers page adds
  that a DXCC prefix is *permitted* as an alternative: "The preferred QTH
  abbreviation for any DX station is 'DX'. You may instead log the ARRL DXCC
  country abbreviation (e.g. G for England, DL for Germany, etc), but simply
  'DX' is easier for you." The schema's `dxStyle` is one-or-the-other, so entry
  accepts the sponsor's *preferred* form. **No scoring consequence** — DX is
  never a multiplier in CQP (§6), so the two forms differ only in what the
  operator types.

## 4. QSO points by mode — and the one 2026 rule change

> "Each complete non-duplicate Phone contact is worth **3 points**. `**NEW in
> 2026**`
> Each complete non-duplicate CW contact is worth 3 points."
> "QSO Points = (CW Qs x 3 pts) + (Phone Qs x 3 pts)"

### Article 20 diff — phone 2 → 3 points

The superseded 2025 revision (Last Update 05-July-2025) reads:

> "Each complete non-duplicate Phone contact is worth **2 points**.
> Each complete non-duplicate CW contact is worth 3 points."
> "QSO Points = (CW Qs x 3 pts) + (Phone Qs x **2** pts)"

**The code follows the 2026 form: phone 3, CW 3.** The sponsor flags the change
itself with `**NEW in 2026**`, so this is not a transcription doubt.

A full text diff of the 2025 and 2026 PDFs shows this is the **only** substantive
rule change between the two revisions — dates aside, everything else differs only
in line wrapping. Recorded so next year's session can tell a real change from a
re-flow.

No digital mode exists → `allowedModes: ["phone", "cw"]`.

## 5. Dupe rule

> "Stations may be worked **once on CW and once on Phone on each of the 6 bands**
> (maximum of 12 QSOs with any one station)."

→ `dupeScope: "bandMode"`. The sponsor's own "maximum of 12" = 6 bands × 2 modes
confirms both the band count and the mode count.

> "Although there is no credit for duplicate contacts, there's no penalty either,
> so please do not remove them from your log as they help with log checking."

Dupes stay in the exported log and score zero — which is already this app's
behaviour (they are counted in `dupeCount`, not dropped).

## 6. Multipliers — in-state and out-of-state

### A. California stations

> "**Maximum of 58 Scored Multipliers out of 63 Total Multipliers** (U.S. states
> = 50 and Canadian provinces/territories = 13)."
>
> - "Although there are **63 possible multipliers** that can accrue toward the CA
>   station's multiplier tally, the **maximum number of counted multipliers
>   toward the CA station's final score is 58**."
> - "**DX** … does not count as an additional multiplier toward the CA station's
>   multiplier tally. DX QSOs count as QSO credit."
> - "**The first valid CA QSO logged with 4-letter county abbreviation will count
>   as the multiplier for California.** California stations must log all CA
>   contacts with their 4-letter county abbreviation."

Three distinct shapes in one paragraph:

1. Classes are **states + provinces only** — not counties. A CA station works
   another CA station for points, and the county yields the *state* multiplier
   `CA`, not a county multiplier.
2. **`homeStateCountsViaCounty: true`**, stated outright — the multipliers table
   even lists the CA row as "**CA — 1st CA county counts as CA**". This is the
   opposite of the NHQP/MEQP situation, and it is the sponsor's own sentence
   rather than an inference, so worklist lesson 5 does not bite here.
3. A **cap on the scored multiplier total: 58 of a possible 63.** No bundled
   party has had this; see §14 item 2. Note the sponsor's careful wording — 63
   may *accrue to the tally*, only 58 *count toward the final score* — so the cap
   belongs on the score, not on which multipliers are recognised.

Counting scope: **once for the contest.** The rules give no per-band or per-mode
language for multipliers anywhere, and the stated ceilings (58/63) are the
counts of distinct entities, which only works under `once`.

### B. Non-California stations

> "Count all **58 California Counties** for a maximum of 58 multipliers."

Classes: **county only**. Scope `once`. The stated maximum of 58 equals the
county count exactly — the cheapest possible arithmetic check, and the generator
asserts it.

> "**DX QSO's do not count for non-California participants.**"
> "United States commonwealths, territories and possessions do not count as
> multipliers."

### Who may work whom

> "Stations outside of California work as many California stations in as many CA
> Counties as possible. Stations inside California work everyone. **Non-CA to
> non-CA contacts do not count for QSO credit.**"

→ `outStateWorksHomeStationsOnly: true`, stated outright — no inference, unlike
NJQP/IAQP/NHQP. MEQP (the previous party) was the mirror image of this.

### DC and Canada

The multipliers table prints "**MD — Maryland & DC**" → `stateAliases: {"DC":
"MD"}`. The Canadian list is the **standard 13** (AB, BC, MB, NB, **NL**, NT, NS,
NU, ON, PE, QC, SK, YT) — a relief after OhQP's 11, NJQP's `NF`-for-`NL`, and
MEQP's 14 with `NF`/`LB` split. Read anyway, per worklist lesson 6; here the
default is correct.

## 7. Bonus stations and bonus points

**NONE.** No bonus station, no bonus points, in either revision. The special
award categories (Expedition, County-Line, One-Day, Mobile, YL, Youth, New
Contester) are **award classes claimed via `SOAPBOX:` lines**, not score
adjustments — "Stations are allowed to claim as many special award categories as
apply to their log."

## 8. Final-score multipliers

**NONE.**

> "The final score is the total number of QSO Points multiplied by the total
> number of scored multipliers (58 maximum)."

Power classes (HP/LP/QRP) affect which award you compete for, not the score.

## 9. County-line / multi-county rules

> "A California County-line station is an expedition or mobile operating with all
> radios and antennas within 150 meters (492 feet) of **more than one county and
> sending all such counties in a single exchange**." … "**State-line operations
> are not allowed.**"

So county lines *are* claimed in a single exchange, unlike MEQP's two-QSO rule.
The rules state no numeric limit, but the sponsor's own county-line logging
guide settles it:

> "N1MM+ • Enter counties separated by the **/** character. • Example:
> **DELN/SISK/HUMB**"
> "Writelog • For participants outside CA: Enter counties in **CNTY, CTY2, CTY3
> and CTY4** fields."

Three in the worked example, four fields in the sponsor's own instructions →
**`maxSimultaneousCounties: 4`**, and the sponsor's separator is `/`, which is
exactly this app's county-line syntax already.

> "California Mobile stations which **change counties or states are considered to
> be new stations** and may be contacted again for point and multiplier credit."

Mid-contest county changes are new QSOs, not dupes — already the engine's
behaviour.

## 10. Valid bands

> "BANDS: **160, 80, 40, 20, 15, and 10 meters**"

Six bands, cross-checked by "each of the 6 bands" and "maximum of 12 QSOs with
any one station". No WARC, no 60 m, no VHF/UHF.

> "MODES: CW, Phone" — no digital category.

Suggested frequencies: "CW: 40 kHz up from the bottom band edge on 10m-80m; 160m
at 1815 kHz. SSB: 1845 kHz, 3750-3820 kHz (avoiding 3790-3800 kHz DX window),
7230 kHz, 14250 kHz, 21300 kHz, 28450 kHz."

## 11. Categories (for Cabrillo `CATEGORY-*` headers)

Codes as the sponsor prints them: `SO-HP`, `SO-LP`, `SO-QRP`, `SOA-HP`,
`SOA-LP`, `SOA-QRP`, `MS-HP`, `MS-LP`, `MS-QRP`, `M2-HP`, `M2-LP`, `M2-QRP`,
`MM-HP`, `MM-LP`, `MM-QRP`. Power: HP >100 W, LP ≤100 W, QRP ≤5 W.

Single-op is capped at **24 operating hours** (off-times ≥15 minutes) inside the
30-hour window; multi-op classes may use all 30. Unassisted single-op forbids all
spotting assistance; the Assisted classes allow it but forbid self-spotting.

## 12. Cabrillo `CONTEST:` header

The sponsor requires Cabrillo but prints no `CONTEST:` token. Under the
[Article 1](../CONSTITUTION.md#article-1--provenance-or-it-does-not-exist)
codified exception, WA7BNM's registry is authority: **`CA-QSO-PARTY`**, no
aliases (fetched 2026-07-24).

## 13. County list

**58 counties, 4-letter abbreviations.** The sponsor publishes not just the table
but the **rule that generates it**, which is unusual and very useful:

> "Use the first 4 characters of the county name to make them unique.
> This rule is broken for **Contra Costa (CCOS)** and **Los Angeles (LANG)**.
> **Marin (MARN)** and **Mariposa (MARP)** counties are not unique in 4
> characters.
> If the county name is one of the **10 counties that start with "San" or
> "Santa"** abbreviate that part to a single "**S**"."

[`gen_cqp.py`](gen_cqp.py) parses the table out of the committed
`cqp_multipliers.txt` and then **re-derives every abbreviation from that stated
formula and asserts they match**, with the four named exceptions listed
explicitly. A hand-typo cannot survive both checks.

The San/Santa family (10, exactly as the sponsor counts them): `SBEN` San Benito,
`SBER` San Bernardino, `SDIE` San Diego, `SFRA` San Francisco, `SJOA` San
Joaquin, `SLUI` San Luis Obispo, `SMAT` San Mateo, `SBAR` Santa Barbara, `SCLA`
Santa Clara, `SCRU` Santa Cruz.

The sponsor also publishes the traps, which make excellent test cases:

> "`MON` – This is an ambiguous abbreviation for: `MONT` Monterey, `MONO` Mono"
> "`MAR` – … `MARN` Marin, `MARP` Mariposa"
> "`SB` – … `SBEN` San Benito, `SBER` San Bernardino, `SBAR` Santa Barbara"
> "`AL`: AL Alabama state, not `ALAM` Alameda county or `ALPI` Alpine county"
> "`LA`: LA Louisiana state, not `LANG` Los Angeles county or `LASS` Lassen"
> "`NV`: NV Nevada state, not `NEVA` Nevada county"
> "`OR`: OR Oregon state, not `ORAN` Orange county"

Four state tokens (`AL`, `LA`, `NV`, `OR`) collide with the *prefixes* of county
abbreviations. Because CQP abbreviations are a fixed 4 characters and state
tokens are 2, the parser distinguishes them by exact match and no aliasing is
needed — but each is worth a test.

## 14. Engine shapes to watch

1. **The exchange carries a serial number, and this repo has no serial field.**
   `QSO` has `rstSent`/`rstRcvd` and no `serial`. Scoring is unaffected —
   points and multipliers do not depend on the serial — but **Cabrillo export
   is**: the QSO-number element is what the log checker reads, and the app
   currently has nothing to put there. Ships with a `KNOWN LIMITATION` note per
   Article 17. **This is now the top deferred engine gap**, and the design
   question it must answer first is what serial a *county-line* contact carries,
   since CQP's own guide logs `DELN/SISK/HUMB` as one exchange while this app
   expands it into one row per county.
2. **A cap on the scored multiplier total** (58 of 63 possible) — new optional
   `maxScoredMultipliers` on `MultRule`. The sponsor's wording puts the cap on
   the *score*, not on recognition, so the implementation caps the count while
   leaving the full multiplier key set intact for the sidebar.
3. **`homeStateCountsViaCounty: true`, stated by the sponsor** — "1st CA county
   counts as CA". The flag's first *explicit* user; every earlier party either
   derived it by arithmetic or shipped it false.
4. **In-state counts no counties at all** — CA stations' classes are
   `["state", "province"]`. A CA county is only ever the route to the `CA` state
   multiplier.
5. **DX scores points but is never a multiplier**, for either side — the same
   shape IAQP introduced.
6. **No RST in the exchange** — second party after MDC.
7. **Six bands including 160 m; CW and phone only.**
