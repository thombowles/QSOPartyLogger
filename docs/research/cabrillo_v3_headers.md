# Cabrillo V3 header tags — official value sets

Banked 2026-07-28 for the contest-entry-fields work (assisted category,
transmitters, operators, grid locator in Contest Setup). These are
**format-level** facts, not any sponsor's rules: the authority is the
Cabrillo specification maintained by the World Wide Radio Operators
Foundation, which NAQP rule 15 designates by name ("The file format for
electronic logs for NCJ-sponsored contests is Cabrillo; see wwrof.org/cabrillo/
for details").

## Sources

- **Spec:** "Cabrillo Specification – Header",
  <https://wwrof.org/cabrillo/cabrillo-v3-header/>, fetched **2026-07-28**,
  banked as [`cabrillo_v3_header_spec.txt`](cabrillo_v3_header_spec.txt)
  (textutil extraction of the page).
- **Reference log:** KE5CW's NAQP CW January 2026 Cabrillo submission,
  written by N1MM Logger+ 1.0.11067.0 (supplied by the operator,
  2026-07-28) — evidence of the header set and ordering a real accepted
  logger produces for NAQP.
- **Sponsor upload form:** <https://www.ncjweb.com/naqplogsubmit>, read
  2026-07-28 — collects submitter email, station location (dropdown), power
  category ("5W or less / 100W or less / More than 100W"), whether spotting
  assistance was used, operator count (single/multiple), and age ("if
  applicable for youth category") **on the form itself**, independent of the
  log's headers. The robot therefore does not depend on the `CATEGORY-*`
  lines, but correct headers keep the log self-describing.

## Enumerated values (quoted from the spec)

| Tag | Legal values |
| --- | --- |
| `CATEGORY-ASSISTED` | `ASSISTED`, `NON-ASSISTED` |
| `CATEGORY-BAND` | `ALL`, `160M`, `80M`, `40M`, `20M`, `15M`, `10M`, `6M`, … (VHF/UHF/SHF values follow) |
| `CATEGORY-MODE` | `CW`, `DIGI`, `FM`, `RTTY`, `SSB`, `MIXED` |
| `CATEGORY-OPERATOR` | `SINGLE-OP`, `MULTI-OP`, `CHECKLOG` |
| `CATEGORY-POWER` | `HIGH`, `LOW`, `QRP` |
| `CATEGORY-STATION` | `DISTRIBUTED`, `FIXED`, `MOBILE`, `PORTABLE`, `ROVER`, `ROVER-LIMITED`, `ROVER-UNLIMITED`, `EXPEDITION`, `HQ`, `SCHOOL`, `EXPLORER` |
| `CATEGORY-TIME` | `6-HOURS`, `8-HOURS`, `12-HOURS`, `24-HOURS` |
| `CATEGORY-TRANSMITTER` | `ONE`, `TWO`, `LIMITED`, `UNLIMITED`, `SWL` — "required for multi-operator entries" |
| `CATEGORY-OVERLAY` | `CLASSIC`, `ROOKIE`, `TB-WIRES`, `YOUTH`, `NOVICE-TECH`, `YL` |

Free-text tags used by this app: `CLUB` ("Name of the radio club to which
the score should be applied"), `NAME` (max 75 chars), `ADDRESS` /
`ADDRESS-CITY` / `ADDRESS-STATE-PROVINCE` / `ADDRESS-POSTALCODE` /
`ADDRESS-COUNTRY`, `EMAIL`, `SOAPBOX`, `CLAIMED-SCORE` (integer, no
commas), and:

- **`OPERATORS`** — "A space or comma-delimited list of operator
  callsign(s). You may also list the callsign of the host station by placing
  an '@' character in front of the callsign within the operator list, such
  as OPERATORS: K1ABC N5XYZ @N6IJ". Max 75 chars per line.
- **`GRID-LOCATOR`** — "Used to indicate the Maidenhead Grid Square where
  the station was operating from. E.g., FN42, JO44EB". The reference log
  carries `GRID-LOCATOR: EM13LE`.
- **`LOCATION`** — per the spec, the ARRL section for US/Canada stations
  ("required for IARU-HF and for all ARRL and CQ contests"; NCJ is neither).
  N1MM accordingly wrote `LOCATION: NTX` (ARRL North Texas section) in the
  reference log, while this app writes the party-derived location token
  (`TX`); NAQP's rules say nothing about the header, and the sponsor's
  upload form collects station location in its own dropdown, so the
  state-token behavior stands unchanged. Recorded so the difference from
  N1MM is a known reading, not an accident.

## What this app models (as of the entry-fields change)

`StationProfile` carries `CategoryOperator` (`SINGLE-OP`/`MULTI-OP`/
`CHECKLOG`), `CategoryAssisted` (`NON-ASSISTED` default/`ASSISTED`),
`CategoryPower` (`HIGH`/`LOW`/`QRP`), `CategoryStation` (`FIXED`/`MOBILE`/
`PORTABLE`/`ROVER`/`EXPEDITION`/`SCHOOL` — the subset a bundled party has
ever needed; the spec's remaining values are additive later under Article
4), `CategoryTransmitter` (`ONE`/`TWO`/`LIMITED`/`UNLIMITED` — `SWL` not
modeled), `operators`, and `gridLocator`. `CATEGORY-OVERLAY` and
`CATEGORY-TIME` are deliberately unmodeled: no bundled party defines an
overlay or time category, and NAQP defines neither.
