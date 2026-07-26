#!/usr/bin/env python3
"""Generate Resources/Parties/kyqp.json — the Kentucky QSO Party.

Per CONSTITUTION.md Article 2: the county list is parsed, never typed.

THE SITE HAS ROLLED FORWARD TO 2027 and it does not matter, which is worth
saying after Michigan and Ontario, where it did. The rules give a FORMULA and
year-independent times - "always 1st Saturday in June", "13Z - 01Z" - so the
2026 window derives from the sponsor rather than from the page's headline date.

THE BONUS STATION SCOPE IS THE ONE ADDED FOR SOUTH CAROLINA. "K4KCG may be
worked once per BAND and MODE for 100 bonus points per QSO" is exactly
BonusRule.WorkStationScope.perBandMode, which this run introduced back in
February's parties. Second user.

Sources (all banked):

  kyqp_rules_2026.txt      https://kyqsoparty.org/rules/
  kyqp_counties.txt        .../uploads/2018/02/Kentucky_Counties.pdf
  kyqp_cabrillo_name.txt   WA7BNM Cabrillo Names (Article 1 exception)

  All fetched 2026-07-26. See kyqp_rules.md.

Run:  python3 docs/research/gen_kyqp.py
"""

import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "kyqp.json")


def read(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        s = f.read()
    for a, b in [("’", "'"), ("‘", "'"), ("“", '"'), ("”", '"'),
                 ("–", "-"), ("—", "-"), (" ", " ")]:
        s = s.replace(a, b)
    return s.split("=" * 72, 1)[-1]


# ---------------------------------------------------------------- the counties
PAIR = re.compile(r"([A-Z][A-Za-z]*(?: [A-Za-z]+)*)\s{2,}([A-Z]{3})(?=\s|$)")
counties = []
for line in read("kyqp_counties.txt").splitlines():
    if "Abbreviation" in line or not line.strip():
        continue
    for name, code in PAIR.findall(line.rstrip()):
        counties.append({"abbr": code, "name": name.strip()})

counties.sort(key=lambda c: c["abbr"])
by_abbr = {c["abbr"]: c["name"] for c in counties}

assert len(counties) == 120, f"Kentucky has 120 counties, parsed {len(counties)}"
assert len(by_abbr) == 120, "codes must be unique"
assert len({c["name"] for c in counties}) == 120, "names must be unique"
assert {len(c["abbr"]) for c in counties} == {3}

# Codes that are not truncations, because the obvious three letters were taken.
assert by_abbr["HAR"] == "Hardin" and by_abbr["HRL"] == "Harlan"
assert by_abbr["MON"] == "Monroe" and by_abbr["MOT"] == "Montgomery"
assert by_abbr["GRE"] == "Green" and by_abbr["GRP"] == "Greenup"
assert by_abbr["GRT"] == "Grant" and by_abbr["GRV"] == "Graves" and by_abbr["GRY"] == "Grayson"

# ------------------------------------------------------------------- the rules
rules = read("kyqp_rules_2026.txt")
flat = re.sub(r"\s+", " ", rules)

# The formula and the times, both year-independent.
assert "UTC: 13Z - 01Z" in flat
assert "EDT: 9AM - 9PM" in flat
EDT = -4
assert (13 + EDT) % 24 == 9 and (1 + EDT) % 24 == 21, "13Z-01Z is 9am-9pm EDT"

assert "All simplex QSOs, no repeaters, NO digital QSOs." in flat
assert "80, 40, 20, 15, 10, 6, 2" in flat
assert "KY stations: RS(T) + County Abbreviation" in flat
assert 'DX: RS(T) + "DX"' in flat

assert "High Power: More than 100 watts, Power Multiplier = 1." in flat
assert "Low Power: 100 watts or less, Power Multiplier = 2." in flat
assert "QRP: 5 watts or less, Power Multiplier = 3." in flat
assert "1 point per completed Phone QSO" in flat
assert "2 points per completed CW QSO" in flat

assert "Each Kentucky station is a multiplier when worked in each of the 120 counties." in flat
assert ("KY stations log USA state (not ARRL section), including DC, and Canadian "
        "Provinces.") in flat
assert ('KY stations log DX contacts for QSO points only, and enter "DX" for the exchange.'
        in flat), "DX pays points and no multiplier - the fourth party with that shape"
assert "Each Kentucky station is a multiplier based on their county." in flat
assert ("Total score = QSO Points x QSO Multipliers x Power Multiplier + Bonus Station "
        "points.") in flat

# The bonus station, and the submission bonus that cannot be modelled.
assert "K4KCG may be worked once per BAND and MODE for 100 bonus points per QSO" in flat
assert ("An additional 100 points is added to your final score as a bonus for submitting "
        "your Cabrillo log file online.") in flat
assert "Bonus stations may change each year" in flat, \
    "so a 2027 session must re-read this call"

# County lines: forbidden to fixed stations, allowed to mobiles with no cap.
assert ("KY Fixed stations on a county line must choose a KY county, and exchange that "
        "county during the QSO Party. No multiple county exchanges.") in flat
assert "KY Mobile and Expedition stations may setup on a county line" in flat

assert "CONTEST:" not in rules
name = read("kyqp_cabrillo_name.txt")
assert "Kentucky QSO Party" in name and "KYQP" in name

NOTES = (
    "verified: partial - rules and county list from the Kentucky Contest Group's own site, "
    "read verbatim 2026-07-26. THE SITE HAS ROLLED FORWARD TO 2027 AND IT DOES NOT MATTER, "
    "which is worth saying after Michigan and Ontario where it did: the rules give a "
    "formula and year-independent times - 'always 1st Saturday in June', 'UTC: 13Z - 01Z' - "
    "so the 2026 window derives from the sponsor rather than from the page's headline date. "
    "The first Saturday in June 2026 is the 6th, and all four of the sponsor's local zones "
    "(EDT, CDT, MDT, PDT) are printed and consistent. 120 counties, the third-largest single "
    "-state list here. WATCH THE CODES: they are not truncations where the obvious three "
    "letters were already taken - HAR is Hardin and HRL is Harlan; MON is Monroe and MOT is "
    "Montgomery; GRE Green, GRP Greenup, GRT Grant, GRV Graves and GRY Grayson are five "
    "counties sharing two letters. SEVEN BANDS, 80 through 2 - no 160 m. NO DIGITAL AT ALL, "
    "and no repeaters. Points are phone 1 and CW 2. THE POWER MULTIPLIER FITS - high x1, low "
    "x2, QRP x3 - the fifth party to ship one. Kentucky is not a state multiplier; KY "
    "entrants count the 120 counties directly, plus states including DC and Canadian "
    "provinces. DX PAYS POINTS AND NO MULTIPLIER for a Kentucky entrant - 'KY stations log "
    "DX contacts for QSO points only' - the fourth party with that shape after Georgia, "
    "North Dakota and Indiana. THE BONUS STATION USES THE perBandMode SCOPE ADDED FOR SOUTH "
    "CAROLINA EARLIER IN THIS RUN: 'K4KCG may be worked once per BAND and MODE for 100 bonus "
    "points per QSO' - second user of that scope, and it fits exactly. NOTE THE SPONSOR'S "
    "OWN WARNING: 'Bonus stations may change each year', so a 2027 session must re-read the "
    "call rather than assume K4KCG. KNOWN LIMITATION 1 - THE 100-POINT LOG-SUBMISSION BONUS "
    "IS NOT MODELLED: it pays for uploading a Cabrillo file, not for anything on the air, "
    "and no BonusRule shape describes that; Delaware has the same gap with its 50-point "
    "version. KNOWN LIMITATION 2 - COUNTY-LINE PERMISSION IS PER CATEGORY AND THE SCHEMA IS "
    "PER PARTY. 'KY Fixed stations on a county line must choose a KY county... No multiple "
    "county exchanges', while KY Mobile and Expedition stations may send several. "
    "maxSimultaneousCounties is one number for the whole party, so the schema default of 4 "
    "ships - permissive for mobiles, which is right, and permissive for fixed stations, "
    "which the sponsor forbids. Refusing a legal mobile exchange would be the worse failure."
)

party = {
    "schemaVersion": 1,
    "id": "kyqp",
    "name": "Kentucky QSO Party",
    "cabrilloContest": "KYQP",
    "homeState": "KY",
    "countyAbbrLength": 3,
    "validBands": ["80m", "40m", "20m", "15m", "10m", "6m", "2m"],
    "points": {"phone": 1, "cw": 2, "digital": 0},
    "dupeScope": "bandMode",
    "multipliers": {
        "inState": {
            "classes": ["county", "state", "province"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
        },
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
        },
    },
    "bonuses": [
        {"type": "workStation", "call": "K4KCG", "points": 100, "scope": "perBandMode"},
    ],
    "dxStyle": "token",
    "allowedModes": ["phone", "cw"],
    "exchangeIncludesRST": True,
    "outStateWorksHomeStationsOnly": True,
    "scoreMultipliers": {"power": {"QRP": 3, "LOW": 2, "HIGH": 1}},
    "schedule": [
        {"start": "2026-06-06T13:00:00Z", "end": "2026-06-07T01:00:00Z"},
    ],
    "counties": counties,
    "hubSpots": {
        "tableURL": "http://qsopartyhub.com/kyqp-table.php",
        "postURL": "http://qsopartyhub.com/kyqp-spots.php",
    },
    "notes": NOTES,
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(party, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"kyqp.json: {len(counties)} counties, 3-letter codes")
print("  the site says 2027 and it DOES NOT MATTER - the rules give a formula")
print("    and year-independent times, so 2026 derives from the sponsor")
print("  codes are not truncations where taken: HAR/HRL, MON/MOT, GRE/GRP/GRT/GRV/GRY")
print("  7 bands, no 160; NO DIGITAL; points phone 1, CW 2")
print("  POWER MULTIPLIER SHIPS: QRP x3, LOW x2, HIGH x1")
print("  bonus K4KCG 100/QSO at perBandMode - the scope added for South Carolina")
print("  NOT shipped: the 100-pt log-submission bonus; per-category county lines")
print(f"  wrote {os.path.normpath(OUT)}")
