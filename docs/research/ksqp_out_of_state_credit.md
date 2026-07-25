# KSQP — who a non-Kansas entrant may work for credit

Researched 2026-07-25. Narrow follow-up to the original KSQP verification, which
banked counties, points, multipliers and the 1×1 tracker but left
`outStateWorksHomeStationsOnly` unset — so the definition defaulted to `false`
and credited a non-Kansas entrant for working another non-Kansas station.

## Source

- **2026 Kansas QSO Party Rules** (fetched 2026-07-25):
  https://ksqsoparty.org/rules/KSQPRules2026.pdf — extracted with `pdftotext
  -layout` to [`ksqp_rules_2026.txt`](ksqp_rules_2026.txt). Headed "29 Aug 2026
  1400 – 0200 UTC / 30 Aug 2026 1400 – 2000 UTC", matching the bundled schedule.

## The rule

The restriction is the party's stated OBJECT, and it names both sides:

> "OBJECT
> Stations outside of Kansas work as many Kansas stations in as many Kansas
> counties as possible. **Stations in Kansas work everyone.**"

The multiplier table draws the same line, and caps the two sides differently:

> "Kansas Stations – maximum of 64 multipliers including: US states (50) …
> Canadian provinces/territories (13) … DX (1)"
>
> "**Non-Kansas Stations – maximum of 105 Kansas county multipliers**"

The exchange confirms which side sends what:

> "Kansas stations send signal report and county. Stations outside of Kansas
> send signal report and state, Canadian province, or DX."

## Decision

Ship `outStateWorksHomeStationsOnly: true`.

This is the "aim, not a prohibition" case. The QSO POINTS section — "Complete
non-duplicate Phone contacts are worth 2 points, complete non-duplicate CW or
RTTY contacts are worth 3 points" — is not itself scoped by location, so read in
isolation a non-Kansas pair could claim points while adding no multiplier.

Resolved exactly as for NJQP, IAQP, NHQP, PAQP, SDQP, NYQP and ILQP: ship the
flag, so a stray contact is visibly flagged as no-credit rather than silently
scoring. KSQP's wording is in fact the *strongest* of that group — it is
verbatim parallel to SDQP's OBJECT, and adds the explicit "Stations in Kansas
work everyone" counterpart that makes the asymmetry deliberate rather than
incidental.

## Scoring effect

A non-Kansas entrant's log containing a non-Kansas contact previously scored
that row at 2 or 3 points and counted it for dupe purposes. It now scores zero
and is excluded. Kansas entrants are unaffected — the flag only applies when the
operator is out of state.

## Noted in passing, not acted on

The 2026 rules carry an FT4/8 category with its own scoring ("See below for
special FT4/8 category rules"), and the bundled definition predates it. Out of
scope here; recorded so it is not mistaken for verified.
