# ALQP — who a non-Alabama entrant may work for credit

Researched 2026-07-25, **during the running 2026 party**, after an operating
report: a Texas entrant typed `SAF` into the county field and it validated. That
turned out to be the DX-prefix guess rather than this flag, but reading the
rules to answer it showed `outStateWorksHomeStationsOnly` was also unset here.

## Source

- **2026 AQP Rules** (fetched 2026-07-25):
  https://alabamacontestgroup.org/aqp/rules/ — extracted to
  [`alqp_rules_2026.txt`](alqp_rules_2026.txt). Note the rules live at
  `/aqp/rules/`; the shorter `/aqp-rules/` **404s**.
- Contest period on that page reads "1500Z July 25th to 0300Z July 26th, 2026",
  matching the bundled schedule exactly.

## The rule

Stated as the party's Object, in the same shape as SDQP's and KSQP's:

> "Object:
> For Alabama amateurs to make contact with amateur radio stations throughout
> the world. **Stations outside of Alabama make contact with Alabama amateur
> radio stations and as many Alabama counties as possible.**"

The multiplier sections draw the same asymmetry:

> "Multipliers: All other stations
> (1) Maximum of 67 Alabama counties … (4) Total possible multipliers are 67 per
> CW or PH mode 134 for mixed mode."

against the Alabama station's "Maximum of 50 states (includes Alabama)" plus
provinces and DXCC entities.

The exchange confirms which side sends what:

> "a) Alabama stations send signal report and county abbreviations. … c) W/VE
> stations (including KH6/KL7) send signal report and state or VE province. d)
> DX stations (including KP2/KP4) send signal report and prefix of country."

## Decision

Ship `outStateWorksHomeStationsOnly: true`.

The "aim, not a prohibition" case again. The QSO points rule — "Both CW and
phone QSOs count 2 points per QSO" — is not scoped by location, and no rule
elsewhere says a non-Alabama pair may not work each other. But out-of-state
multipliers are Alabama counties only, so such a contact could add points while
adding nothing else.

Resolved as for NJQP, IAQP, NHQP, PAQP, SDQP, NYQP, ILQP and now KSQP: ship the
flag, so a stray contact is visibly flagged as no-credit rather than silently
scoring.

## Scoring effect, and the timing

A non-Alabama entrant's log containing a non-Alabama contact previously scored
that row at 2 points and counted it for dupe purposes. It now scores zero and is
excluded. Alabama entrants are unaffected.

**This landed while the 2026 party was running.** For a log holding only Alabama
counties — the normal case for an out-of-state entrant — the score does not move
at all. A log holding non-Alabama rows will drop, which is the sponsor's rules
being applied rather than a regression, but it is a live score changing under
the operator, so it is called out here and in the commit message rather than
left to be discovered.

Combined with the role-aware exchange validation in the preceding commit, an
out-of-state ALQP entrant can now enter Alabama counties only: state, province
and DX-prefix tokens are all rejected at the entry bar.
