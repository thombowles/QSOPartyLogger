#!/usr/bin/env python3
"""Generate Resources/Parties/sevenqp.json — the 7th Call Area QSO Party.

THE FIRST MULTI-STATE PARTY, built on the schema added in its own commit
immediately before this one: County.state, PartyDefinition.homeStates and
inStateLabel. One log covers every member state, which is what KE5CW asked for.

IT IS EIGHT STATES, NOT SEVEN. The worklist's sketch said seven (AZ ID MT NV OR
UT WY) and left Washington out - presumably because Washington has its own
Salmon Run. It does, and it is ALSO in the 7th call area, which is what W7
means. The sponsor's own States & Counties page is the authority and this
script counts the state headers rather than trusting the sketch.

THE EXCHANGE CODE ALREADY CARRIES THE STATE. "Exchange state and county, e.g.
AZYVP for Yavapai AZ" - so codes are five letters, a 2-letter state followed by
a 3-letter county, and County.state is not an invention here but a decomposition
of what the sponsor already prints.

Sources (both banked):

  sevenqp_rules_2026.txt      http://7qp.org/new/Page.asp?content=rules
  sevenqp_counties_2026.tsv   http://7qp.org/new/Page.asp?content=geo
  sevenqp_cabrillo_name.txt   WA7BNM Cabrillo Names (Article 1 exception - header only)

  All fetched 2026-07-26. See sevenqp_rules.md.

Run:  python3 docs/research/gen_sevenqp.py
"""

import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "sevenqp.json")


def read(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        s = f.read()
    for a, b in [("’", "'"), ("‘", "'"), ("“", '"'), ("”", '"'),
                 ("–", "-"), ("—", "-"), (" ", " "), ("�", " ")]:
        s = s.replace(a, b)
    return s.split("=" * 72, 1)[-1]


# ------------------------------------------------------------- the county grid
rows = []
for line in read("sevenqp_counties_2026.tsv").splitlines():
    if line.startswith("#"):
        continue
    rows.append([c.strip() for c in line.split("\t")])

counties, state_names, current = [], {}, None
for cells in rows:
    if not any(cells):
        continue
    # A state header row: 2-letter code, state name, then the word "map".
    if len(cells) > 3 and cells[3] == "map" and re.fullmatch(r"[A-Z]{2}", cells[0]):
        current = cells[0]
        state_names[current] = cells[1]
        continue
    assert current, f"county row before any state header: {cells}"
    # Five (code, name) pairs at stride 3.
    for i in range(0, len(cells) - 1, 3):
        code, name = cells[i], cells[i + 1]
        if not code and not name:
            continue
        assert re.fullmatch(r"[A-Z]{3}", code), f"bad county code {code!r} in {current}"
        assert name, f"{current}/{code} has no name"
        counties.append({"abbr": current + code, "name": name, "state": current})

states = sorted(state_names)
by_abbr = {c["abbr"]: c for c in counties}

# EIGHT STATES. The sketch said seven; the sponsor says otherwise.
assert states == ["AZ", "ID", "MT", "NV", "OR", "UT", "WA", "WY"], states
assert len(states) == 8, "the 7th call area is W7: eight states, Washington included"
assert state_names["WA"] == "Washington"

# The sponsor states its own county total in the scoring rule.
rules = read("sevenqp_rules_2026.txt")
flat = re.sub(r"\s+", " ", rules)
assert "7th-area counties (259) worked" in flat
assert len(counties) == 259, (
    f"the sponsor says 259 counties; parsed {len(counties)}: "
    + ", ".join(f"{s}={sum(1 for c in counties if c['state'] == s)}" for s in states))

assert len(by_abbr) == 259, "codes must be unique across all eight states"
assert {len(c["abbr"]) for c in counties} == {5}, "uniformly 5 letters: state + county"

# The sponsor's own worked example, from the geo page and the rules.
assert by_abbr["AZYVP"]["name"] == "Yavapai" and by_abbr["AZYVP"]["state"] == "AZ"
assert "Exchange state and county, e.g. AZYVP for Yavapai AZ." in \
    re.sub(r"\s+", " ", read("sevenqp_counties_2026.tsv"))
assert "7th-area stations send signal report plus 5-letter state/county code (e.g., ORDES" in flat
assert by_abbr["ORDES"]["name"] == "Deschutes", by_abbr.get("ORDES")

# The county-line examples the rules print, both of which must resolve.
assert "UTRIC/IDBEA" in flat
assert by_abbr["UTRIC"]["name"] == "Rich" and by_abbr["IDBEA"]["name"] == "Bear Lake"
assert "ORDES/JEF" in flat, "the shorthand where the second county reuses the state"
assert by_abbr["ORJEF"]["name"] == "Jefferson"

# Three states that share a county name, which is exactly why the code carries
# the state: "Lincoln" exists in five of the eight.
lincolns = sorted(c["abbr"] for c in counties if c["name"] == "Lincoln")
assert len(lincolns) >= 4, lincolns
assert len({c["name"] for c in counties}) < len(counties), \
    "county NAMES repeat across states; only the 5-letter codes are unique"

# ------------------------------------------------------------------- the rules
assert "7th Call Area QSO Party -- 2026 Rules" in flat
assert ("1300 UTC Saturday to 0700 UTC Sunday (6 AM to midnight PDT the first Saturday "
        "in May)") in flat
PDT = -7
assert (13 + PDT) % 24 == 6, "1300Z is 6 AM PDT, as the rules say"
assert (7 + PDT) % 24 == 0, "0700Z is midnight PDT, as the rules say"

assert "7th call area stations work everyone, others work 7th-area stations only." in flat
assert "Work stations once per band/mode." in flat
assert "The same station may be worked on each band on CW, Phone, and Digital." in flat

assert "Bands: 160, 80, 40, 20, 15 and 10m." in flat
assert "2 points per SSB QSO, 3 points per CW QSO, 4 points per Digital QSO." in flat
assert ("7th-area stations multiply total QSO points by the total of states (50), "
        "provinces (13) and other DXCC entities (maximum of 10) worked.") in flat
assert "Non-7th-area stations multiply total QSO points by 7th-area counties (259) worked." in flat
assert 'Non-7th-area stations send signal report plus state/province/"DX" two-letter codes.' in flat

# WSJT is excluded by name - the same gap Illinois, North Dakota and Nebraska have.
assert "WSJT modes do not support the 7QP exchange, so are not allowed." in flat
assert "Any computer-to-computer mode is considered digital." in flat

assert "County-line operations must be within 500 feet of the county line." in flat
assert ("County-line contacts may be logged with one entry showing all counties or with "
        "separate entries for each county.") in flat
assert "bonus" not in flat.lower(), "no bonus rule to model"
assert "CONTEST:" not in rules
name = read("sevenqp_cabrillo_name.txt")
assert "7th Call Area QSO Party" in name and "7QP" in name

NOTES = (
    "verified: partial - rules and the State/County list from the 7QP consortium's own "
    "site (7qp.org, coordinated by the Central Oregon DX Club), read verbatim 2026-07-26. "
    "The rules are headed '2026 Rules', dated 02/09/2026, on a site whose footer reads "
    "'Site last updated on: June 7, 2026' and which carries the 2026 results, so this is "
    "current rather than a rollover. THE FIRST MULTI-STATE PARTY IN THIS APP, built on the "
    "County.state / homeStates / inStateLabel schema added in its own commit immediately "
    "before this one: ONE LOG COVERS ALL EIGHT MEMBER STATES. IT IS EIGHT, NOT SEVEN - the "
    "worklist's sketch listed AZ ID MT NV OR UT WY and left Washington out, presumably "
    "because Washington runs its own Salmon Run. It does, and it is ALSO in the 7th call "
    "area, which is what W7 means; the sponsor's own page is the authority and the "
    "generator counts its state headers rather than trusting the sketch. THE EXCHANGE CODE "
    "ALREADY CARRIES THE STATE: 'Exchange state and county, e.g. AZYVP for Yavapai AZ', so "
    "codes are five letters - a 2-letter state then a 3-letter county - and County.state is "
    "a decomposition of what the sponsor prints rather than an invention. That is why "
    "county NAMES repeat freely across the eight states (Lincoln appears in five of them) "
    "while the 5-letter codes stay unique. 259 counties, which is the sponsor's own stated "
    "total in its scoring rule. Eighteen hours in ONE window, 1300Z Saturday to 0700Z "
    "Sunday on the first Saturday in May, and both local glosses (6 AM and midnight PDT) "
    "convert correctly. Points run SSB 2, CW 3, DIGITAL 4 - digital is the highest-paying "
    "mode here, which only Maine and North Carolina also do. Multipliers count ONCE "
    "OVERALL: 7th-area stations count states, provinces and DXCC entities, and non-7th-area "
    "stations count the 259 counties. DXCC IS CAPPED AT TEN by the rules ('other DXCC "
    "entities (maximum of 10)'), which dxMultCap records. KNOWN LIMITATION 1 - THE DXCC CAP "
    "CAN NEVER BIND, because the exchange is the literal 'DX' token, so every entity "
    "collapses to one multiplier and the count never reaches ten. Same shape as New "
    "Hampshire's, and the fourth party wanting a DXCC prefix table. KNOWN LIMITATION 2 - "
    "'WSJT modes do not support the 7QP exchange, so are not allowed' cannot be enforced, "
    "since ModeClass.digital covers RTTY and PSK, which this party does allow, alongside "
    "FT8, which it does not. FOURTH USER of that gap after Illinois, North Dakota and "
    "Nebraska. OPEN QUESTION 1: NO MAXIMUM IS STATED FOR SIMULTANEOUS COUNTIES. The rules "
    "require county-line operation within 500 feet of the line and print a two-county "
    "example (UTRIC/IDBEA), but cap nothing; the schema default of 4 ships, which never "
    "refuses a legal exchange. NOTE ALSO the sponsor's county-line shorthand 'ORDES/JEF', "
    "where the second county reuses the first's state - this app requires both codes in "
    "full (ORDES/ORJEF), which is a keystroke difference and not a scoring one. The "
    "Cabrillo CONTEST header is the one thing not from the sponsor - the rules demand "
    "Cabrillo without naming it - so 7QP comes from WA7BNM under Article 1's exception. THE "
    "SPOT HUB DOES NOT SERVE THIS PARTY: 7qp-table.php 302-redirects to a login page, the "
    "same trap California's qp-table.php sets, so hubSpots is null."
)

party = {
    "schemaVersion": 1,
    "id": "sevenqp",
    "name": "7th Call Area QSO Party",
    "cabrilloContest": "7QP",
    "homeState": "AZ",
    "homeStates": states,
    "inStateLabel": "the 7th call area",
    "countyAbbrLength": 5,
    "validBands": ["160m", "80m", "40m", "20m", "15m", "10m"],
    "points": {"phone": 2, "cw": 3, "digital": 4},
    "dupeScope": "bandMode",
    "multipliers": {
        # "7th-area stations multiply ... by the total of states (50), provinces
        # (13) and other DXCC entities (maximum of 10) worked."
        "inState": {
            "classes": ["state", "province", "dx"],
            "homeStateCountsViaCounty": True,
            "countScope": "once",
            "dxMultCap": 10,
        },
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
        },
    },
    "bonuses": [],
    "dxStyle": "token",
    "allowedModes": ["phone", "cw", "digital"],
    "exchangeIncludesRST": True,
    "outStateWorksHomeStationsOnly": True,
    "schedule": [
        {"start": "2026-05-02T13:00:00Z", "end": "2026-05-03T07:00:00Z"},
    ],
    "counties": counties,
    # THE HUB DOES NOT SERVE 7QP. 7qp-table.php 302-redirects to
    # imlogin.php?loginstatus=-3, a login page - the same trap California's
    # qp-table.php sets, where a guessed prefix yields a poller that runs
    # forever, never errors and shows nothing.
    "hubSpots": None,
    "notes": NOTES,
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(party, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"sevenqp.json: {len(counties)} counties across {len(states)} states")
print("  IT IS EIGHT STATES, NOT SEVEN - the sketch left Washington out:")
for s in states:
    n = sum(1 for c in counties if c["state"] == s)
    print(f"    {s} {state_names[s]:<12} {n:>3}")
print("  codes are 5 letters, state + county: AZ + YVP = AZYVP")
print(f"  county NAMES repeat across states ({len(lincolns)} Lincolns); only codes are unique")
print("  points: SSB 2, CW 3, DIGITAL 4 - digital pays most here")
print("  multipliers ONCE overall; DXCC capped at 10 (a cap that can never bind)")
print("  schedule: 1 window, 18 h, first Saturday in May")
print("  NOT shipped: the WSJT exclusion; the ORDES/JEF county-line shorthand")
print("  NO HUB SOURCE: 7qp-table.php 302s to a login page")
print(f"  wrote {os.path.normpath(OUT)}")
