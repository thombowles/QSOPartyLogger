#!/usr/bin/env python3
"""Generate hqp.json from the transcribed official multiplier map.

Source (committed alongside this script, so the run is reproducible):
  hqp_districts.tsv — transcribed from the sponsor's official multiplier map,
  https://www.hawaiiqsoparty.org/mult-map/ (committed as multmap_all.png).

The abbreviations are published only on that map; the rules page links to it
rather than printing a list. See hqp_rules.md for the full rules research,
including the sponsor's self-contradictory operating window (§2).

Usage:  python3 gen_hqp.py        (run from docs/research/)
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "hqp.json")
SRC = os.path.join(HERE, "hqp_districts.tsv")

districts = []
seen = set()
by_county = {}
for line in open(SRC, encoding="utf-8"):
    line = line.rstrip("\n")
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    parts = line.split("\t")
    if len(parts) != 3:
        sys.exit(f"malformed TSV row (want abbr/district/county): {line!r}")
    abbr, name, county = (p.strip() for p in parts)
    if abbr in seen:
        sys.exit(f"HQP duplicate abbreviation: {abbr}")
    seen.add(abbr)
    districts.append({"abbr": abbr, "name": name})
    by_county.setdefault(county, []).append(abbr)

# Rules: "14 Hawai'i districts ... Maximum of 84 (6 bands x 14 districts)".
assert len(districts) == 14, f"expected 14 HQP districts, got {len(districts)}"
assert len({d["name"] for d in districts}) == 14, "HQP district names not unique"
assert all(len(d["abbr"]) == 3 for d in districts), "all HQP abbreviations are 3 letters"
BANDS = ["160m", "80m", "40m", "20m", "15m", "10m"]
assert len(BANDS) * len(districts) == 84, "band x district ceiling must be the rules' 84"

# Districts are subdivisions of 5 counties, not counties — Honolulu has 4.
EXPECTED_GROUPS = {
    "Kaua'i County": 2,
    "Kalawao County": 1,
    "Maui County": 3,
    "Honolulu County (O'ahu)": 4,
    "Hawai'i County": 4,
}
actual = {c: len(a) for c, a in by_county.items()}
assert actual == EXPECTED_GROUPS, f"county grouping changed: {actual}"

hqp = {
    "schemaVersion": 1,
    "id": "hqp",
    "name": "Hawaii QSO Party",
    "cabrilloContest": "HI-QSO-PARTY",
    "homeState": "HI",
    "countyAbbrLength": 3,
    "validBands": BANDS,
    # "SSB: 2 points  CW: 3 points  digital: 3 points"
    "points": {"phone": 2, "cw": 3, "digital": 3},
    # Rule 3: "worked only once per band-mode (CW, SSB, digital)".
    "dupeScope": "bandMode",
    "multipliers": {
        # "Hawai'i stations: 14 Hawai'i districts plus US states (including DC),
        # plus Canadian provinces, plus DXCC entities. ONCE ONLY - NOT PER BAND"
        "inState": {
            "classes": ["county", "state", "province", "dx"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
        },
        # "Non-Hawaiian stations: 14 Hawai'i districts per band. Maximum of 84"
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "perBand",
        },
    },
    # No bonus station, no bonus points, no final-score multipliers.
    "bonuses": [],
    # "Contacts: Hawai'i stations work anyone - non-Hawai'i stations work only
    # Hawai'i."
    "outStateWorksHomeStationsOnly": True,
    # No district-line provision exists, and there is no mobile/rover category.
    "maxSimultaneousCounties": 1,
    # The sponsor's own multiplier text, quoted in hqp_rules.md: "Non-Hawaiian
    # stations: 14 Hawai'i districts per band." These 14 codes are districts,
    # and Hawaii's five actual counties are not what this party counts.
    "countyTerm": "district",
    # NOTE: this dict does NOT carry `hubSpots` or `caveats`, which are written
    # by later passes -- so running this script alone drops both from the file.
    # After any run: python3 gen_hub_map.py && python3 gen_caveats.py.
    # (gen_caveats.py says the same; the hub block is the one it cannot
    # restore, and HubSpotSourceTests is what catches its loss.)
    # See hqp_rules.md §2: the sponsor's rule 1 contradicts itself. 1600Z ->
    # 0400Z is the only reading matching its stated 36 hours AND both of its
    # Hawaii-time anchors (6am Sat / 6pm Sun, HST = UTC-10).
    "schedule": [{"start": "2026-08-22T16:00:00Z", "end": "2026-08-24T04:00:00Z"}],
    "counties": districts,
    "notes": (
        "verified: partial — rules read verbatim from the sponsor's rules page "
        "(hawaiiqsoparty.org/rules-page/, 2026-07-24; the page carries 2026 dates but "
        "prints no revision number). Multiplier entities are the 14 Hawai'i DISTRICTS, "
        "not counties: they subdivide the 5 counties, with Honolulu County alone "
        "contributing HON/LHN/PRL/WHN and Hawai'i County contributing HIL/KOH/KON/VOL. "
        "Abbreviations exist only on the sponsor's multiplier map "
        "(hawaiiqsoparty.org/mult-map/, committed as multmap_all.png), transcribed to "
        "hqp_districts.tsv and generated from there — never hand-typed into this file. "
        "Mult scope is asymmetric: out-of-state count districts PER BAND (ceiling 84 = "
        "6 bands x 14), Hawai'i stations count districts + states incl. DC + provinces + "
        "DXCC ONCE for the contest. Non-Hawai'i stations may only work Hawai'i. All three "
        "modes are legal; digital is worth 3 points, equal to CW. No bonuses, no "
        "final-score multipliers, no district lines. "
        "OPEN QUESTION (why this is partial): rule 1 reads 'Operating period is 36 hours "
        "from 1800 UTC Aug 22 through 0359 UTC Aug 24, 2026. Note: That's 6am Saturday "
        "Aug 22 to start and end at 6pm Sunday in Hawaii.' Those claims disagree — the "
        "literal UTC pair spans 33h59m, not 36 hours, and 1800Z is 8am HST, not 6am. "
        "1600Z->0400Z is the only span matching both the stated 36 hours and both Hawaii "
        "times, so that is what ships; the State QSO Party Challenge calendar instead "
        "says 1600Z->0200Z (34h). Confirm with info@hawaiiqsoparty.org before submitting "
        "a log. Not modeled: grid squares as a substitute QTH for modes that cannot send "
        "a name (rules allow it, sponsor's log checker resolves them)."
    ),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(hqp, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"hqp.json: {len(districts)} districts across {len(by_county)} counties")
for county, abbrs in by_county.items():
    print(f"  {county}: {' '.join(abbrs)}")
