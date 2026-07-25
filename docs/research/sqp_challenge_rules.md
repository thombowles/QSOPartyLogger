# State QSO Party Challenge — official rules research

Research for the dashboard's challenge tracker. This is not a QSO party —
no `PartyDefinition` ships from this document — but the same provenance
discipline applies (Constitution Articles 1–3): every number the tracker
computes traces to the sponsor's own words, quoted here.

## 1. Sponsor / sources

- **Program:** State QSO Party Challenge, administered by the **State QSO
  Party Group**, sponsored by Icom America. Administrator: Stan Zawrotny,
  K4SBZ (challenge@stateqsoparty.com).
- **Site:** stateqsoparty.com (the `.info` domain does not resolve).
  Homepage read 2026-07-25.
- **Rules PDF:** `stateqsoparty.com/wp-content/uploads/2026/01/2026SQPCHALLENGERULES.pdf`,
  fetched **2026-07-25**, committed verbatim as
  [`2026SQPCHALLENGERULES.pdf`](2026SQPCHALLENGERULES.pdf). The PDF carries
  no revision marker of its own; its upload path dates it 2026-01.
- **Calendar:** the challenge's own 2026 calendar PDF, already banked as
  [`2026_state_qso_party_calendar.txt`](2026_state_qso_party_calendar.txt)
  (fetched 2026-07-24, `pdftotext -layout`).
- **Live scores:** `3830scores.com/sqpsummary.php` (linked from the rules).

## 2. Time period

> "February 1st – November 30th. November 30th is the last day to make a
> 3830scores.com form submissions."

The PDF's Entry Deadline section says "**the 2025 SQP Challenge program**"
in one sentence — a leftover year in the 2026 document (same class of
sponsor typo as MEQP's contest-period line; the 2026-01 upload path and
title govern).

## 3. Scoring — the sponsor's exact words

> "The participant's Score is based on the total number of QSOs made in
> each approved state QSO party contests as reported on 3830Scores.com
> multiplied by the number of State QSO Parties entered in the current year
> before the November 30th submission deadline."
>
> "Total Points = (Sum of Individual state QSO party contest QSOs) x
> (Number of state QSO party contest 3830scores.com form submission)"

The homepage adds the multiplier floor:

> "Entrants must make at least two contacts in a QSO party for it to count
> as a multiplier."

### Interpretation shipped (recorded so a later reader can audit it)

- **QSO sum:** valid (non-dupe, in-scope) QSOs per contest — the number an
  operator reports to 3830. The app uses its own `ScoreBreakdown.validQSOs`
  as the estimate and labels the whole panel an **estimate**: the official
  score is computed by the sponsor from what is actually posted to
  3830scores.com, which this app does not submit to.
- **Multiplier:** number of distinct approved parties entered in the year
  **with ≥ 2 valid QSOs** (homepage rule above). A 1-QSO entry still adds
  its QSO to the sum (the PDF's formula counts submissions and QSOs
  separately) but does not count as a party.
- **Window:** the Feb 1 – Nov 30 window is not separately enforced by the
  tracker — every approved 2026 contest's windows already fall inside it
  (calendar: Feb 7 Vermont through Oct 18 Illinois).

## 4. Award levels — the sponsor's exact words

> "There are five recognition levels based on minimum Challenge points:
> Diamond 100,000 | Platinum 25,000 | Gold 10,000 | Silver 5,000 | Bronze 500"
>
> "To qualify for an award level, the participant must have participated in
> at least two state QSO party contest. Each state QSO party contest entry
> must include at least TWO valid QSOs."

So: no award level at all until **two** parties each carry **≥ 2 valid
QSOs**, regardless of points.

## 5. Approved contests, 2026

> "An 'Approved Contest' is one in which out of state/province stations may
> only make contacts with stations in the target state/province/region."

The homepage lists **47 approved contests** (header: "47 Approved
Contests"), read 2026-07-25, and the banked calendar carries windows for
exactly those 47. Of this app's 19 bundled parties, **18 are approved**.

- **Maine QSO Party is NOT on the 2026 approved list.** Verified twice
  against the homepage (absent between "Louisiana" and "Maryland/DC") and
  absent from the calendar PDF. MEQP logs therefore count in the app's
  overall statistics but **not** toward the challenge, and the dashboard
  says so rather than silently dropping them.
- The other 29 approved contests are not bundled parties (nothing to score
  with), but their calendar windows drive the dashboard's upcoming list,
  labeled with this calendar as the source.

## 6. Known calendar error (Article 19 case, already on record)

The challenge calendar puts **NJQP on Sep 19**; the sponsor's own 2026
rules say **Sep 12**, and Article 19 already records that WA7BNM agrees
with the sponsor. For every bundled party the app's `schedule` (sponsor
authority) supersedes the calendar row; calendar windows are used only for
contests this app has no definition for, and are labeled as calendar-derived
wherever shown.

## 7. Multi-op stations (out of scope, recorded)

The rules divide a multi-op station's contact total equally among its
operators ("1,200 divided by 4 operators resulting in each of the four
operators getting credit for 300 contacts"), with each operator's share
required to be ≥ 2. The tracker scores the log's callsign as a single
entry and does not model per-operator division; a multi-op share is a
3830-side computation on data this app never sees. Recorded as a
limitation in the dashboard's estimate note.

## 8. Data generation

`Resources/Challenge/sqp_challenge_2026.json` is **generated, never
hand-typed**, by [`gen_sqp_challenge.py`](gen_sqp_challenge.py) from the
committed calendar text, with hard assertions:

- exactly 47 distinct contests parsed;
- the parsed names map 1:1 onto the homepage's 47 names (alias table for
  the two spelling differences: calendar "Washington St Salmon Run" =
  site "Washington State Salmon Run"; calendar "Maryland-DC QSO Party" =
  site "Maryland/DC QSO Party");
- exactly 18 contests map onto bundled party ids, and `meqp` maps to none;
- every window parses to a UTC instant pair with `end > start`.
