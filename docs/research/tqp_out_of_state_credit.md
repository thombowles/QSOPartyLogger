# TQP — who a non-Texas entrant may work for credit

Researched 2026-07-25. Narrow follow-up to the original TQP verification, which
banked points, multipliers and bonuses but left `outStateWorksHomeStationsOnly`
unset — so the definition defaulted to `false` and credited a non-Texas entrant
for working another non-Texas station.

## Source

- **Operating Rules** (fetched 2026-07-25):
  https://www.txqp.net/index.php/rules/operating-rules — the live rules page.
  Extracted to [`tqp_operating_rules.txt`](tqp_operating_rules.txt).
- Note that `https://txqp.net/rules/` and `https://txqp.net/rules.html` both
  **404**. The rules live under the Joomla `index.php` path above. Recorded so
  the next session does not conclude the rules are gone.

## The rule

Unlike most state parties, TQP does not leave this to an objective statement.
It is written into the QSO points rule itself:

> "Non - Texas Stations
> Count two (2) points per phone QSO **with any Texas station**
> Count three (3) points per CW and other digital mode QSOs **with any Texas
> Station**."

A non-Texas station is awarded points only for contacts with Texas stations.
There is no clause anywhere awarding a non-Texas station points for working
another non-Texas station, so such a contact is worth zero.

The multiplier rule agrees, and is equally explicit about the asymmetry:

> "Non - Texas stations— Your multiplier is the number of Texas counties
> worked. The maximum possible multiplier is 254."
>
> "Texas Stations— Your multipliers are the number of states worked (not
> including Texas) plus the number of Texas counties worked plus each Canadian
> province worked (13 total) plus each DXCC country worked excluding USA,
> Canada, Alaska and Hawaii."

The exchange confirms which side sends what:

> "Stations outside Texas use RS/T and State, Country, Canadian Province, or
> maritime region. DX stations should send the primary prefix assigned to their
> country."
>
> "Texas stations use RS/T and Texas County using the TQP standard
> abbreviations."

## Decision

Ship `outStateWorksHomeStationsOnly: true`.

This is **not** the "aim, not a prohibition" case resolved by precedent for
NJQP, IAQP, NHQP, PAQP, SDQP, NYQP and ILQP. TQP states the restriction
directly in the points rule, which makes it the best-evidenced instance of this
flag in the catalogue after MDC rule 10b.

## Scoring effect

A non-Texas entrant's log containing a non-Texas contact previously scored that
row at 2 or 3 points and counted it for dupe purposes. It now scores zero and is
excluded, which is what the sponsor's rules say. Texas entrants are unaffected —
the flag only applies when the operator is out of state.

## Still open, unchanged by this

TQP remains `verified: partial` on its original grounds: the county list comes
from the sponsor's 2014 `txcounty.zip`, and the band list and current-year rules
should be re-confirmed before submitting a log. This research does not touch
either question.
