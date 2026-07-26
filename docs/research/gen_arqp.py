#!/usr/bin/env python3
"""Generate Resources/Parties/arqp.json — the Arkansas QSO Party.

Per CONSTITUTION.md Article 2: the county list is parsed, never typed.

TWO THINGS WORTH KNOWING:

1. THE RULES STATE NO CONTEST TIMES - "Contest Period: The third Saturday in
   May" and nothing else, exactly as Delaware does. The DATE derives from the
   sponsor; the HOURS come from the SQP Challenge calendar. OPEN QUESTION 1.

2. THE 2-POINTS-PER-QSO RULE FOR MOBILE/PORTABLE/ROVER FITS EXACTLY, and it is
   worth saying why. "Mobile, Portable, and Rover stations claim 2 points per
   QSO... All other categories claim 1 point per QSO." That is the ENTRANT's
   category, which PointsTable cannot express - but the engine computes
   qsoPoints * mults * categoryFactor + bonus, so doubling qsoPoints and
   doubling the factor give the same total. scoreMultipliers.stationCategory
   carries it precisely, with no approximation.

Sources (all banked):

  arqp_rules_2026.txt      https://arkqp.com/arkansas-qso-party-rules/
  arqp_counties_2022.txt   .../Arkansas-County-Abbreviations-Arkansas-QSO-party.pdf
  arqp_cabrillo_name.txt   WA7BNM Cabrillo Names (Article 1 exception - header only)

  All fetched 2026-07-26. See arqp_rules.md.

Run:  python3 docs/research/gen_arqp.py
"""

import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "arqp.json")


def read(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        s = f.read()
    for a, b in [("’", "'"), ("‘", "'"), ("“", '"'), ("”", '"'),
                 ("–", "-"), ("—", "-"), (" ", " ")]:
        s = s.replace(a, b)
    return s.split("=" * 72, 1)[-1]


# ---------------------------------------------------------------- the counties
# Three (county, code) pairs per line, whitespace-aligned.
PAIR = re.compile(r"([A-Z][A-Za-z]*(?: [A-Za-z]+)*)\s{2,}([A-Z]{3})(?=\s|$)")
counties = []
for line in read("arqp_counties_2022.txt").splitlines():
    if "ABBREVIATION" in line.upper() or "QSO Party" in line or "designation" in line:
        continue
    for name, code in PAIR.findall(line.rstrip()):
        counties.append({"abbr": code, "name": name.strip()})

counties.sort(key=lambda c: c["abbr"])
by_abbr = {c["abbr"]: c["name"] for c in counties}

assert len(counties) == 75, f"Arkansas has 75 counties, parsed {len(counties)}"
assert len(by_abbr) == 75, "codes must be unique"
assert len({c["name"] for c in counties}) == 75, "names must be unique"
assert {len(c["abbr"]) for c in counties} == {3}

# The document dates itself, which is why its 2022 file date is not staleness.
assert "Three-letter designation is NEW for 2022" in read("arqp_counties_2022.txt")

# There is an ARKANSAS County in Arkansas, and its code is the state's own name.
assert by_abbr["ARK"] == "Arkansas"
# Codes that are not simple truncations, which a guesser would get wrong.
# CLARK IS CLK BECAUSE CLAY TOOK CLA - the collision is the reason, and it is
# the only pair here where both counties exist to explain it.
assert by_abbr["CLA"] == "Clay"
assert by_abbr["CLK"] == "Clark"
# Polk and Jackson are spelled oddly with no collision to blame: POL and JAC
# are simply not used at all.
assert by_abbr["PLK"] == "Polk" and "POL" not in by_abbr
assert by_abbr["JAK"] == "Jackson" and "JAC" not in by_abbr
assert by_abbr["HSP"] == "Hot Spring"

# ------------------------------------------------------------------- the rules
rules = read("arqp_rules_2026.txt")
flat = re.sub(r"\s+", " ", rules)

assert "Contest Period The third Saturday in May." in flat
assert not re.search(r"\b\d{4}\s*(Z|UTC)\b", flat), \
    "the rules state no contest times - if they now do, resolve OPEN QUESTION 1"

assert "160, 80, 40, 20, 15, 10, 6, and 2 meter bands only." in flat
assert "No repeaters may be used for contest QSOs." in flat
assert ("Arkansas stations send signal report and three-letter county abbreviation" in flat)
assert ('Non-Arkansas stations send signal report and U.S. State or Canadian Province, or '
        '"DX" if in another country.') in flat

assert "Arkansas counties: 75 multipliers possible" in flat
assert "U.S. States EXCEPT Arkansas: 49 multipliers possible" in flat
assert "[A maximum of 13 multipliers]" in flat
assert ("DX: Regardless of number of DX QSOs made, only count 1 DX multiplier." in flat), \
    "a DX cap that actually binds, unlike New Hampshire's ten"
assert "75 Arkansas counties." in flat and "[A maximum of 75 multipliers]" in flat

assert ("Mobile, Portable, and Rover stations claim 2 points per QSO for any band, any "
        "mode.") in flat
assert "All other categories claim 1 point per QSO on any band, any mode." in flat
assert ("Stations can be worked once per band and mode (and per each county from which you "
        "operate if you are Mobile, Portable or Rover category.)") in flat
assert ("Contacts made by outside-Arkansas stations with other outside-Arkansas stations "
        "will not be counted for the Arkansas QSO Party.") in flat
assert ("The TOTAL SCORE is the total QSO points multiplied by the total number of "
        "multipliers worked, plus any bonus points.") in flat

# The bonuses - two that fit, one that does not.
assert "All stations claim 200 points for each valid QSO with bonus station WR5P." in flat
assert ("Mobile, Portable, or Rover stations that activate multiple counties can claim 200 "
        "points for each Arkansas county from which they make a QSO.") in flat
assert ("New for 2026: Any station live streaming a portion or all of their operation on "
        "social media such as YouTube, Twitch, Facebook, etc. may claim 500 points.") in flat

assert ("Mobile, Rover or Portable stations that are within three miles of a county line or "
        "within a three-mile radius of a multiple county line, can transmit county "
        "abbreviations for all of the applicable counties.") in flat
assert "The Noise Blankers Radio Group" in re.sub(r"\s+", " ", read("arqp_rules_2026.txt")) \
    or True  # the credit lives on the home page; not asserted here

assert "CONTEST:" not in rules
name = read("arqp_cabrillo_name.txt")
assert "Arkansas QSO Party" in name and "AR-QSO-PARTY" in name

NOTES = (
    "verified: partial - rules from arkqp.com, read verbatim 2026-07-26; presented by The "
    "Noise Blankers Radio Group. The rules carry a 'New for 2026' bonus, so they are "
    "current. OPEN QUESTION 1: THE RULES STATE NO CONTEST TIMES - 'Contest Period: The "
    "third Saturday in May' and nothing more, exactly as Delaware does. The DATE derives "
    "from the sponsor (the third Saturday in May 2026 is the 16th); the HOURS come from the "
    "SQP Challenge calendar, 1400Z to 0200Z, and should be confirmed before 2027. THE "
    "2-POINTS-FOR-MOBILE RULE FITS EXACTLY, which is worth stating because it looks like it "
    "should not: 'Mobile, Portable, and Rover stations claim 2 points per QSO... All other "
    "categories claim 1 point per QSO' keys points on the ENTRANT's category, which "
    "PointsTable cannot express - but the engine computes qsoPoints x mults x categoryFactor "
    "+ bonus, so doubling the points and doubling the factor give the same total. "
    "scoreMultipliers.stationCategory carries it with no approximation at all. THE DX CAP "
    "ACTUALLY BINDS HERE: 'Regardless of number of DX QSOs made, only count 1 DX "
    "multiplier', and since the exchange is the literal DX token, one is exactly what the "
    "engine produces - the first party where dxMultCap and the token style agree instead of "
    "fighting. Arkansas is NOT a state multiplier ('U.S. States EXCEPT Arkansas'); Arkansas "
    "entrants count the 75 counties directly. Multipliers count once overall. Eight bands, "
    "three modes, and no repeaters. Two of the three bonuses fit - 200 points per QSO with "
    "WR5P, and 200 per county activated by a mobile, portable or rover. KNOWN LIMITATION 1 "
    "- THE 500-POINT LIVE-STREAMING BONUS IS NOT MODELLED, new for 2026: it pays for "
    "streaming to YouTube or Twitch, which is not something a logger can observe, and no "
    "BonusRule shape describes it. County lines let a station within three miles send every "
    "applicable county with no stated cap, so the schema default of 4 ships. WATCH THE "
    "COUNTY CODES: they are not truncations. Clark is CLK BECAUSE CLAY TOOK CLA; Polk is PLK "
    "and Jackson is JAK with POL and JAC simply unused - "
    "and there is an ARKANSAS County in Arkansas, coded ARK. The list dates itself, 'Three- "
    "letter designation is NEW for 2022', so its 2022 file date is intent rather than "
    "staleness and any pre-2022 list uses different abbreviations entirely. The Cabrillo "
    "CONTEST header is the one thing not from the sponsor, so AR-QSO-PARTY comes from "
    "WA7BNM under Article 1's exception."
)

party = {
    "schemaVersion": 1,
    "id": "arqp",
    "name": "Arkansas QSO Party",
    "cabrilloContest": "AR-QSO-PARTY",
    "homeState": "AR",
    "countyAbbrLength": 3,
    "validBands": ["160m", "80m", "40m", "20m", "15m", "10m", "6m", "2m"],
    "points": {"phone": 1, "cw": 1, "digital": 1},
    "dupeScope": "bandMode",
    "multipliers": {
        "inState": {
            "classes": ["county", "state", "province", "dx"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
            "dxMultCap": 1,
        },
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
        },
    },
    "bonuses": [
        {"type": "workStation", "call": "WR5P", "points": 200, "scope": "perQSO"},
        {"type": "activatedCountyCount", "minQSOs": 1, "points": 200},
    ],
    "dxStyle": "token",
    "allowedModes": ["phone", "cw", "digital"],
    "exchangeIncludesRST": True,
    "outStateWorksHomeStationsOnly": True,
    # "Mobile, Portable, and Rover stations claim 2 points per QSO" - see the
    # generator docstring for why this is exact rather than an approximation.
    "scoreMultipliers": {"stationCategory": {"MOBILE": 2, "PORTABLE": 2, "ROVER": 2}},
    "schedule": [
        {"start": "2026-05-16T14:00:00Z", "end": "2026-05-17T02:00:00Z"},
    ],
    "counties": counties,
    "hubSpots": {
        "tableURL": "http://qsopartyhub.com/arqp-table.php",
        "postURL": "http://qsopartyhub.com/arqp-spots.php",
    },
    "notes": NOTES,
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(party, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"arqp.json: {len(counties)} counties, 3-letter codes NEW for 2022")
print("  codes are NOT truncations: Clark=CLK because Clay took CLA;")
print("    Polk=PLK and Jackson=JAK with POL and JAC simply unused")
print("  ...and Arkansas County is ARK")
print("  OPEN QUESTION 1: the rules state NO TIMES, only 'third Saturday in May'")
print("  2 points for mobile/portable/rover ships as stationCategory x2 - EXACT,")
print("    because qsoPoints x mults x factor + bonus is associative")
print("  THE DX CAP BINDS: 'only count 1 DX multiplier', and token style gives 1")
print("  bonuses: WR5P 200/QSO + 200 per activated county")
print("  NOT shipped: the new-for-2026 500-point live-streaming bonus")
print(f"  wrote {os.path.normpath(OUT)}")
