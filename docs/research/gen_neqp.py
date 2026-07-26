#!/usr/bin/env python3
"""Generate Resources/Parties/neqp.json — the NEBRASKA QSO Party.

THIS FILE WAS LOST AND REBUILT. The New England QSO Party is also called NEQP,
and when it was built on 2026-07-26 its generator and research were written over
Nebraska's under the same `neqp_*` prefix. New England now lives under
`newenglandqp_*` (see gen_newenglandqp.py) and this prefix is Nebraska's alone.

Nebraska keeps the id `neqp` because it follows the state abbreviation, as every
single-state party's does. The two are told apart in Cabrillo anyway:
NE-QSO-PARTY here, NEQP for New England.

Sources, both re-fetched or re-read 2026-07-26:
  neqp_rules_2026.txt      the sponsor's 2026 rules, rendered from
                           nebraskaqsoparty.com (the page needs JavaScript)
  neqp_counties_2022.txt   the sponsor's own County Abbreviation List PDF,
                           which the rules call current: "It is the same list
                           used in 2016."
  neqp_cabrillo_name.txt   WA7BNM, under Article 1's exception, for the
                           CONTEST: header only -- the rules demand Cabrillo
                           and never name the token.

Every number below is asserted against a quoted sentence, so a silent edit to
the sponsor's page fails this script rather than shipping.

RUN gen_caveats.py AFTERWARDS. This writes the JSON whole and drops the party's
caveats; CaveatRosterTests fails until they are put back.

Run:  python3 docs/research/gen_neqp.py
"""

import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "neqp.json")


def read(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        s = f.read()
    for a, b in [("’", "'"), ("‘", "'"), ("“", '"'), ("”", '"'),
                 ("–", "-"), ("—", "-"), (" ", " ")]:
        s = s.replace(a, b)
    return s.split("=" * 72, 1)[-1]


rules = read("neqp_rules_2026.txt")
flat = re.sub(r"\s+", " ", rules)

# ------------------------------------------------------------------ counties
# The PDF is two columns of "Name    ABBR", one county per line.
counties = []
for line in read("neqp_counties_2022.txt").splitlines():
    m = re.match(r"^\s*([A-Za-z][A-Za-z .']+?)\s{2,}([A-Z]{4})\s*$", line)
    if not m:
        continue
    name, abbr = m.group(1).strip(), m.group(2)
    counties.append({"abbr": abbr, "name": name})

# The sponsor's PDF is ordered by county NAME; the shipped file is ordered by
# ABBREVIATION, and sorting here is what makes this generator reproduce it
# byte for byte. The two orders hold the same 93 pairs either way.
counties.sort(key=lambda c: c["abbr"])

# The sponsor states the total itself, so the county list is self-checking.
assert "The multiplier for out-of-state stations has a maximum of 93 counties." in flat, \
    "the sponsor's own 93-county sentence moved"
assert len(counties) == 93, f"the sponsor says 93; parsed {len(counties)}"
assert len({c["abbr"] for c in counties}) == 93, "abbreviations must be unique"
assert all(len(c["abbr"]) == 4 for c in counties), "all abbreviations are 4 letters"

# The sponsor misspells Cuming as "Cumming"; shipped as printed (Article 1).
assert {"abbr": "CUMI", "name": "Cumming"} in counties, \
    "CUMI/Cumming -- the sponsor's misspelling -- is no longer in the list"

# ------------------------------------------------------------------- scoring
assert ("Each unique digital contact is 1 points, Phone is worth 2 points, "
        "CW is worth 3 points and Satellite is worth 4 points.") in flat, \
    "the points sentence moved"
POINTS = {"phone": 2, "cw": 3, "digital": 1}

assert ("If all QSOs are made QRP (5 watts or less) the power multiplier is 5; "
        "if less than 100 watts, the multiplier is 2; otherwise the power "
        "multiplier is 1 for over 100 watts.") in flat, \
    "the power-multiplier sentence moved"
POWER = {"QRP": 5, "LOW": 2, "HIGH": 1}

# Nebraska is INSIDE the fifty, so an NE station's own county yields the state
# multiplier: "The maximum number of states worked is 50" -- fifty, not 49.
assert "The maximum number of states worked is 50" in flat, \
    "the 50-states sentence moved; homeStateCountsViaCounty depends on it"

# "Count each Nebraska county, and each S/P/C, only once per contest."
assert "only once per contest" in flat, "the once-per-contest scope moved"

# --------------------------------------------------------------------- bands
# "All VHF/UHF bands are allowed. WARC band contacts do not count."
assert "All VHF/UHF bands are allowed. WARC band contacts do not count." in flat, \
    "the band sentence moved"
BANDS = ["160m", "80m", "40m", "20m", "15m", "10m", "6m", "2m", "1.25m", "70cm"]

# ------------------------------------------------------------------- bonuses
# Seven ARRL section appointees, parsed from the sponsor's own list rather than
# typed. The Section Manager pays 100 and the other six pay 50.
BONUS_RE = re.compile(r"-\s*([A-Z]{1,2}[0-9ØO][A-Z]{1,3})\s+Nebraska\s+[^\n]*?(\d+)\s+points")
bonuses = []
for call, pts in BONUS_RE.findall(rules):
    # The sponsor writes zero as the slashed Scandinavian O in every callsign.
    bonuses.append({"type": "workStation",
                    "call": call.replace("Ø", "0").replace("O", "0", 0),
                    "points": int(pts),
                    "scope": "once"})

assert len(bonuses) == 7, f"the sponsor lists seven appointees; parsed {len(bonuses)}"
assert bonuses[0]["call"] == "KA0BOJ" and bonuses[0]["points"] == 100, \
    f"the Section Manager should be KA0BOJ at 100; got {bonuses[0]}"
assert all(b["points"] == 50 for b in bonuses[1:]), "the other six pay 50 each"
assert "There will be 100 bonus points for any QSO with Nebraska SM" in flat, \
    "the bonus sentence moved -- and 'any QSO with' is why scope is 'once' " \
    "rather than perQSO (OPEN QUESTION 2)"

# ------------------------------------------------------------------ schedule
# "start Saturday, April 25th, 1400 UTC ... and end Sunday April 27th at 0200
# UTC". The weekday label is wrong -- the 27th is a Monday -- but the UTC date
# is right, because Sunday evening in Nebraska is Monday in UTC.
assert "1400 UTC" in flat and "0200 UTC" in flat, "the UTC figures moved"
assert "(8:00 AM CDT" in flat and "(08:00 PM CDT)" in flat, \
    "the local-time glosses moved; both are an hour off (OPEN QUESTION 1)"
SCHEDULE = [{"start": "2026-04-25T14:00:00Z", "end": "2026-04-27T02:00:00Z"}]

# --------------------------------------------------------------- county line
assert ("Nebraska Mobile/Portable stations may operate from county lines, but "
        "only two counties at a time.") in flat, "the county-line rule moved"
MAX_COUNTIES = 2

# ------------------------------------------------------------------ Cabrillo
cab = read("neqp_cabrillo_name.txt")
assert re.search(r"Nebraska QSO Party\s+NE-QSO-PARTY", cab), \
    "WA7BNM no longer lists NE-QSO-PARTY for Nebraska"
assert "Only Cabrillo format will be accepted for electronic logs" in flat, \
    "the Cabrillo requirement moved"

# ---------------------------------------------------------------------- write
# notes and caveats are preserved from the existing file: the prose is the
# maintainer's provenance record and the caveats are gen_caveats.py's, neither
# of which is derived from the sources above.
with open(OUT, encoding="utf-8") as f:
    existing = json.load(f)

party = {
    "schemaVersion": 1,
    "id": "neqp",
    "name": "Nebraska QSO Party",
    "cabrilloContest": "NE-QSO-PARTY",
    "homeState": "NE",
    "countyAbbrLength": 4,
    "validBands": BANDS,
    "points": POINTS,
    "dupeScope": "bandMode",
    "multipliers": {
        "inState": {"classes": ["county", "state", "province", "dx"],
                    "homeStateCountsViaCounty": True, "countScope": "once"},
        "outState": {"classes": ["county"],
                     "homeStateCountsViaCounty": False, "countScope": "once"},
    },
    "bonuses": bonuses,
    "dxStyle": "prefix",
    "allowedModes": ["phone", "cw", "digital"],
    "maxSimultaneousCounties": MAX_COUNTIES,
    "exchangeIncludesRST": True,
    "outStateWorksHomeStationsOnly": True,
    "scoreMultipliers": {"power": POWER},
    "schedule": SCHEDULE,
    "counties": counties,
    "hubSpots": existing["hubSpots"],
    "notes": existing["notes"],
}
if "caveats" in existing:
    party["caveats"] = existing["caveats"]

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(party, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"neqp.json: {len(counties)} counties, {len(bonuses)} bonus stations")
print(f"  points {POINTS}, power {POWER}")
print(f"  {len(BANDS)} bands, 36 h in one window, county lines max {MAX_COUNTIES}")
print(f"  wrote {os.path.normpath(OUT)}")
