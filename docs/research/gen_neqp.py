#!/usr/bin/env python3
"""Generate Resources/Parties/newenglandqp.json — the New England QSO Party.

THE ID IS NOT "neqp". Nebraska took that first, and it has the better claim:
its id follows the state abbreviation, as every single-state party's does. New
England is not a state, so - like 7QP, which is "sevenqp" - it gets a
spelled-out id. Both parties are genuinely called NEQP in the wild, and their
Cabrillo headers disambiguate them: NE-QSO-PARTY for Nebraska, NEQP for New
England.

THE SECOND MULTI-STATE PARTY, on the schema 7QP proved: County.state,
homeStates and inStateLabel. One log covers all six member states, as KE5CW
asked for.

The sponsor gives the SAME rationale for its 5-letter codes that 7QP does, and
says it outright: "some county names are the same in each state (Middlesex is
in MA and CT, for example). We prefer that logs use the full 5-letter
abbreviations - state then county."

CONNECTICUT NO LONGER USES COUNTIES. "Note that CT switched from counties to
Regional Councils of Government (2024)", so CT's nine multipliers are COGs -
Capital Region, Naugatuck Valley and so on - not counties at all. They live in
the county list because that is the field the exchange occupies, and the
generator asserts a couple of them by name so a silent reversion is caught.

Sources (both banked):

  neqp_rules_2026.txt      https://neqp.org/rules/  ("Last updated 4/27/2026")
  neqp_counties_2026.tsv        https://neqp.org/neqp-county-abbreviations/ (table)
  neqp_counties_page_prose.txt  ...the same page's prose, banked apart
  sevenqp_cabrillo_name.txt   WA7BNM Cabrillo Names, which lists NEQP too

  All fetched 2026-07-26. See neqp_rules.md.

Run:  python3 docs/research/gen_neqp.py
"""

import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "newenglandqp.json")

STATE_CODE = {"Connecticut": "CT", "Maine": "ME", "Massachusetts": "MA",
              "New Hampshire": "NH", "Rhode Island": "RI", "Vermont": "VT"}


def read(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        s = f.read()
    for a, b in [("’", "'"), ("‘", "'"), ("“", '"'), ("”", '"'),
                 ("–", "-"), ("—", "-"), (" ", " ")]:
        s = s.replace(a, b)
    return s.split("=" * 72, 1)[-1]


# ---------------------------------------------------------------- the counties
counties, current = [], None
for line in read("neqp_counties_2026.tsv").splitlines():
    if line.startswith("#") or not line.strip():
        continue
    cells = [c.strip() for c in line.split("\t")]
    if cells[:2] == ["State", "County"]:
        continue
    if len(cells) < 3:
        continue
    state_name, name, code = cells[0], cells[1], cells[2]
    if state_name:
        assert state_name in STATE_CODE, f"unknown state {state_name!r}"
        current = STATE_CODE[state_name]
    assert current, f"county row before any state: {cells}"
    assert re.fullmatch(r"[A-Z]{5}", code), f"bad code {code!r} for {name!r}"
    assert code.startswith(current), f"{code} should begin with {current}"
    counties.append({"abbr": code, "name": name, "state": current})

counties.sort(key=lambda c: c["abbr"])
by_abbr = {c["abbr"]: c for c in counties}
states = sorted({c["state"] for c in counties})

assert states == ["CT", "MA", "ME", "NH", "RI", "VT"], states
assert len(counties) == 68, f"the sponsor says 68; parsed {len(counties)}"
assert len(by_abbr) == 68, "codes must be unique"
assert {len(c["abbr"]) for c in counties} == {5}

# THE SPONSOR'S OWN PER-STATE BREAKDOWN, which is the arithmetic check.
rules = read("neqp_rules_2026.txt")
flat = re.sub(r"\s+", " ", rules)
assert "for a total of 68 (CT/9 MA/14 ME/16 NH/10 RI/5 VT/14)" in flat
EXPECTED = {"CT": 9, "MA": 14, "ME": 16, "NH": 10, "RI": 5, "VT": 14}
actual = {s: sum(1 for c in counties if c["state"] == s) for s in states}
assert actual == EXPECTED, (actual, EXPECTED)
assert sum(EXPECTED.values()) == 68

# CONNECTICUT'S NINE ARE COUNCILS OF GOVERNMENT, NOT COUNTIES.
assert "Note that CT switched from counties to Regional Councils of Government (2024)." in flat
assert "in CT, stations will use Regional Councils of Government" in flat
for code, name in [("CTCAP", "Capital Region"), ("CTNAU", "Naugatuck Valley"),
                   ("CTLCR", "Lower CT River"), ("CTNOW", "Northwest Hills")]:
    assert by_abbr[code]["name"] == name, (code, by_abbr.get(code))
assert not any(c["name"] in ("Hartford", "New Haven", "Fairfield", "Litchfield")
               for c in counties if c["state"] == "CT"), \
    "the pre-2024 Connecticut COUNTIES must not reappear"

# WHY THE CODES CARRY THE STATE - and the sponsor's own example has gone stale.
# It says "Middlesex is in MA and CT", which WAS true; Connecticut's Middlesex
# County stopped being a multiplier when CT moved to Councils of Government in
# 2024, so only MAMID survives. The convention is still fully justified, just
# not by that example: four names still repeat across ten multipliers.
assert ("some county names are the same in each state (Middlesex is in MA and CT, for "
        "example). We prefer that logs use the full 5-letter abbreviations - state then "
        "county.") in re.sub(r"\s+", " ", read("neqp_counties_page_prose.txt")), \
    "asserted against the sponsor's prose, banked apart from the table so this is "\
    "not a check on a comment this repo wrote"
assert sorted(c["abbr"] for c in counties if c["name"] == "Middlesex") == ["MAMID"], \
    "if a CT Middlesex returns, the sponsor's example is live again - re-read the COG list"

by_name = {}
for c in counties:
    by_name.setdefault(c["name"], []).append(c["abbr"])
duplicates = {n: sorted(v) for n, v in by_name.items() if len(v) > 1}
assert duplicates == {
    "Franklin": ["MAFRA", "MEFRA", "VTFRA"],
    "Washington": ["MEWAS", "RIWAS", "VTWAS"],
    "Bristol": ["MABRI", "RIBRI"],
    "Essex": ["MAESS", "VTESS"],
}, duplicates

# ------------------------------------------------------------------- the rules
assert ("To contact as many New England stations (Connecticut, Maine, Massachusetts, New "
        "Hampshire, Rhode Island, Vermont) in as many New England counties (68) as possible "
        "on 80-40-20-15-10m. (New England stations work anyone)") in flat
assert "Date: First full weekend of May (May 2-3, 2026)" in flat
assert ("Contest Period: 2000Z Saturday until 0500Z Sunday (4pm EDT Saturday until 1am EDT "
        "Sunday) and 1300Z Sunday until 2400Z Sunday (9am EDT Sunday until 8pm EDT "
        "Sunday).") in flat
EDT = -4
for utc, local in [(20, 16), (5, 1), (13, 9), (24, 20)]:
    assert (utc + EDT) % 24 == local % 24, (utc, local)

assert "Work New England stations once per band/mode." in flat
assert "County line QSOs should be logged as two separate QSOs." in flat
assert "Cross mode, cross-band, and repeater QSOs are not permitted." in flat
assert ("Mobiles that change counties are considered to be new stations, and can be worked "
        "for both multiplier and QSO Point credit.") in flat

assert ("QSO Points: Count one point per phone QSO, two points per CW (includes digital "
        "modes)QSO.") in flat, "digital scores as CW here"

assert ("New England stations use states(50)(Count DC as MD), Canadian provinces(14 - "
        "VO1/VO2 are separate) and DXCC countries (not USA) as multipliers.") in flat
assert "Total score is QSO points times the multiplier." in flat
assert "Send signal report and state/province (DX stations send signal report and \"DX\")." in flat

assert "bonus" not in flat.lower(), "no bonus rule to model"
assert "CONTEST:" not in rules
cab = read("sevenqp_cabrillo_name.txt")
assert "New England QSO Party" in cab and "NEQP" in cab

# The 14 Canadians: the standard 13 with Newfoundland and Labrador split, since
# "VO1/VO2 are separate". The sponsor states the COUNT but not the TOKENS -
# OPEN QUESTION 1 - so the split follows North Dakota's and Quebec's NF/LB.
PROVINCES = ["AB", "BC", "LB", "MB", "NB", "NF", "NS", "NT", "NU", "ON",
             "PE", "QC", "SK", "YT"]
assert len(PROVINCES) == 14
assert "NL" not in PROVINCES and {"NF", "LB"} <= set(PROVINCES)

NOTES = (
    "verified: partial - rules and the 68-multiplier list from neqp.org, read verbatim "
    "2026-07-26; the rules page's own footer reads 'Last updated 4/27/2026'. THE SECOND "
    "MULTI-STATE PARTY, on the schema 7QP proved: ONE LOG COVERS ALL SIX MEMBER STATES (CT "
    "ME MA NH RI VT). The sponsor gives the SAME rationale for 5-letter codes that 7QP "
    "does, and says it outright: 'some county names are the same in each state (Middlesex "
    "is in MA and CT, for example). We prefer that logs use the full 5-letter abbreviations "
    "- state then county.' Middlesex is exactly that case here - CTMID and MAMID - which is "
    "why County.state earns its keep. CONNECTICUT NO LONGER USES COUNTIES: 'Note that CT "
    "switched from counties to Regional Councils of Government (2024)', so its nine "
    "multipliers are COGs - Capital Region, Naugatuck Valley, Northwest Hills and the rest "
    "- and Hartford, New Haven, Fairfield and Litchfield are NOT multipliers any more. The "
    "generator asserts both halves, so a source that predates 2024 fails loudly rather than "
    "shipping nine dead multipliers. THE SPONSOR'S OWN PER-STATE BREAKDOWN IS THE "
    "ARITHMETIC CHECK and it holds: CT/9 MA/14 ME/16 NH/10 RI/5 VT/14 = 68. Twenty hours in "
    "two legs on the first full weekend of May, and all four local glosses convert "
    "correctly. FIVE BANDS, 80 through 10 - no 160 m and no VHF. Points are phone 1 and CW "
    "2, with DIGITAL EXPLICITLY SCORING AS CW ('two points per CW (includes digital "
    "modes)'). Multipliers count ONCE overall. New England entrants count states, provinces "
    "and DXCC countries, NOT counties - so a New England station working another earns "
    "points only. DC counts as Maryland. OPEN QUESTION 1: THE CANADIAN LIST HAS FOURTEEN "
    "ENTRIES AND THE SPONSOR NAMES NONE OF THEM. 'Canadian provinces(14 - VO1/VO2 are "
    "separate)' gives the count and the reason - Newfoundland and Labrador split - but no "
    "abbreviations. NF and LB ship, following North Dakota's and Quebec's lists, which are "
    "the only other sponsors in this app to split it; an operator should confirm the tokens "
    "before 2027. County lines are logged as two separate QSOs, so maxSimultaneousCounties "
    "is 1. No bonus points and no power multiplier: 'Total score is QSO points times the "
    "multiplier.' The Cabrillo CONTEST header is the one thing not from the sponsor - the "
    "rules ask for Cabrillo without naming it - so NEQP comes from WA7BNM under Article 1's "
    "exception."
)

party = {
    "schemaVersion": 1,
    "id": "newenglandqp",
    "name": "New England QSO Party",
    "cabrilloContest": "NEQP",
    "homeState": "CT",
    "homeStates": states,
    "inStateLabel": "New England",
    "countyAbbrLength": 5,
    "validBands": ["80m", "40m", "20m", "15m", "10m"],
    "points": {"phone": 1, "cw": 2, "digital": 2},
    "dupeScope": "bandMode",
    "multipliers": {
        # "New England stations use states(50)(Count DC as MD), Canadian
        # provinces(14) and DXCC countries (not USA)" - and pointedly no
        # counties, so a New England pair earns points only.
        "inState": {
            "classes": ["state", "province", "dx"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
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
    "maxSimultaneousCounties": 1,
    "provinces": PROVINCES,
    "stateAliases": {"DC": "MD"},
    "exchangeIncludesRST": True,
    "outStateWorksHomeStationsOnly": True,
    "schedule": [
        {"start": "2026-05-02T20:00:00Z", "end": "2026-05-03T05:00:00Z"},
        {"start": "2026-05-03T13:00:00Z", "end": "2026-05-04T00:00:00Z"},
    ],
    "counties": counties,
    "hubSpots": None,
    "notes": NOTES,
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(party, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"newenglandqp.json: {len(counties)} multipliers across {len(states)} states")
for s in states:
    print(f"    {s} {actual[s]:>3}")
print("  CONNECTICUT'S NINE ARE COUNCILS OF GOVERNMENT, NOT COUNTIES (2024 change)")
print("  the sponsor cites Middlesex as its duplicate example - and that example is STALE:")
print("    CT's Middlesex went with the 2024 COG switch, so only MAMID survives")
print(f"  four names DO still repeat: {', '.join(sorted(duplicates))}")
print("  5 bands, 80-10; no 160 m, no VHF")
print("  points: phone 1, CW 2, and DIGITAL SCORES AS CW by the sponsor's own words")
print("  multipliers ONCE overall; NE entrants count no counties at all")
print(f"  provinces: {len(PROVINCES)} with NL split into NF+LB (OPEN QUESTION 1)")
print("  schedule: 2 windows, 9 h + 11 h = 20 h")
print(f"  wrote {os.path.normpath(OUT)}")
