#!/usr/bin/env python3
"""Generate tnqp.json from the official Tennessee county abbreviation list.

Source (committed alongside this script, so the run is reproducible):
  tnqp_counties.tsv — extracted from the sponsor's official abbreviation PDF,
  https://tnqp.org/wp-content/uploads/2025/01/tnqp_county_abbreviations.pdf
  ("TNQP Counties List"); the same list is printed in the rules document.

See tnqp_rules.md for the full rules research, including why this ships
`verified: partial` (the posted rules document is still the 2025 edition).

Usage:  python3 gen_tnqp.py        (run from docs/research/)
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "tnqp.json")
SRC = os.path.join(HERE, "tnqp_counties.tsv")

counties = {}
for line in open(SRC, encoding="utf-8"):
    line = line.rstrip("\n")
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    parts = line.split("\t")
    if len(parts) != 2:
        sys.exit(f"malformed TSV row (want abbr/name): {line!r}")
    abbr, name = (p.strip() for p in parts)
    if abbr in counties:
        sys.exit(f"TnQP duplicate abbreviation: {abbr}")
    counties[abbr] = name

# Rules: "Multipliers are Tennessee counties (95 max/band)".
assert len(counties) == 95, f"expected 95 TN counties, got {len(counties)}"
assert len(set(counties.values())) == 95, "TN county names not unique"
assert all(len(a) == 4 for a in counties), "all TnQP abbreviations are 4 letters"
# The classic TnQP trap: Hardeman and Hardin both start HARD.
assert counties["HARD"] == "Hardeman", f"HARD should be Hardeman, got {counties['HARD']!r}"
assert counties["HARN"] == "Hardin", f"HARN should be Hardin, got {counties['HARN']!r}"
# Sponsor's own spellings, preserved deliberately (see tnqp_rules.md §13).
assert counties["DEKA"] == "Dekalb", "official list prints 'Dekalb', not 'DeKalb'"
assert counties["VANB"] == "Van Buren"

tnqp = {
    "schemaVersion": 1,
    "id": "tnqp",
    "name": "Tennessee QSO Party",
    "cabrilloContest": "TN-QSO-PARTY",
    "homeState": "TN",
    "countyAbbrLength": 4,
    # "All amateur bands are valid, with the exception of 60, 30, 17 and 12
    # meters." That includes 1.25 m, which the suggested-frequency list gives as
    # 223.50; the app gained the band on 2026-07-24.
    "validBands": [
        "160m", "80m", "40m", "20m", "15m", "10m", "6m", "2m", "1.25m", "70cm",
    ],
    # "3 points per QSO regardless of mode."
    "points": {"phone": 3, "cw": 3, "digital": 3},
    # "Fixed Stations may be worked once per band/mode"; mobiles/rovers again on
    # a county change, which the dupe key already covers via the received QTH.
    "dupeScope": "bandMode",
    "multipliers": {
        # In-state, per band: TN counties + 49 states (not TN) + 13 provinces +
        # DXCC less USA/Canada/AK/HI.
        "inState": {
            "classes": ["county", "state", "province", "dx"],
            # TN is never counted as a state at all ("do not count Tennessee as
            # a state"), so no home-state-via-county credit.
            "homeStateCountsViaCounty": False,
            "countScope": "perBand",
        },
        # "Multipliers accumulate on a per band basis. Multipliers are Tennessee
        # counties (95 max/band) ... all 95 on 40M and again on 20M = 190."
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "perBand",
        },
    },
    "bonuses": [
        # "All entrants may claim 100 bonus points for EACH QSO with TCG
        # headquarters station K4TCG."
        {"type": "workStation", "call": "K4TCG", "points": 100, "scope": "perQSO"},
        # "Tennessee mobile & rover operators may claim 500 bonus points for
        # each Tennessee county from which they complete at least 10 QSOs."
        {"type": "activatedCountyCount", "minQSOs": 10, "points": 500},
    ],
    # Exchange sends a DXCC entity, not a literal "DX" token.
    "dxStyle": "prefix",
    # "District of Columbia counts as Maryland."
    "stateAliases": {"DC": "MD"},
    # County lines allowed per MARAC rules, but "Three and four county lines may
    # not be run simultaneously" — so at most 2 at once.
    "maxSimultaneousCounties": 2,
    # "Outside Tennessee stations work only Tennessee stations."
    "outStateWorksHomeStationsOnly": True,
    # First Sunday of September; 1700Z Sunday to 0300Z Monday. 2026-09-06 is a
    # Sunday, confirmed by date(1) and the sponsor's home page.
    "schedule": [{"start": "2026-09-06T17:00:00Z", "end": "2026-09-07T03:00:00Z"}],
    "counties": [{"abbr": a, "name": n} for a, n in sorted(counties.items(), key=lambda kv: kv[1])],
    "notes": (
        "verified: partial — rules from the Tennessee Contest Group's posted document "
        "(tnqp.org/rules/, embedded DOCX 'Tennessee-QSO-Party-2024-Rule-Revisions-.docx', "
        "uploaded 2025/09), read 2026-07-23 and re-checked 2026-07-24: the page still "
        "embeds that same document and announces no 2026 revision. The 2026 date "
        "(September 6) is confirmed by the tnqp.org home page and is the first Sunday of "
        "September. Counties generated from the sponsor's official abbreviation PDF via "
        "tnqp_counties.tsv — never hand-typed; note HARD=Hardeman vs HARN=Hardin, and the "
        "official list's own spellings 'Dekalb' and 'Van Buren' are preserved. 3 points per "
        "QSO in every mode. Multipliers accumulate PER BAND for both in-state and "
        "out-of-state entrants (95 counties per band out-of-state); Tennessee is never a "
        "state multiplier, DC counts as Maryland, and AK/HI count as states only, never "
        "DXCC. Out-of-state stations work only Tennessee stations. County lines allowed up "
        "to 2 counties at once (three- and four-county lines are forbidden). K4TCG pays 100 "
        "bonus points PER QSO, and TN mobiles/rovers 500 per county with 10+ QSOs; bonuses "
        "are added after the multiplier. No power or category multiplier. All amateur "
        "bands are valid except 60, 30, 17 and 12 m — 1.25 m included, shipped since "
        "2026-07-24 when the app gained the band; the sponsor's rule itself never "
        "changed. "
        "OPEN QUESTIONS (why this is partial): (1) the posted rules document is titled for "
        "2025 and no 2026-specific revision exists yet — re-check tnqp.org/rules/ in late "
        "August 2026. (2) Not modeled: 'Tennessee mobiles and rovers may claim one "
        "MULTIPLIER for any Tennessee county from which they complete at least 10 QSOs if "
        "they do not earn a multiplier for that county otherwise' — the matching 500-point "
        "BONUS is modeled, but this extra self-activation multiplier is not, so a TN "
        "mobile/rover may see a slightly low multiplier count."
    ),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(tnqp, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"tnqp.json: {len(counties)} counties")
print(f"  HARD={counties['HARD']}  HARN={counties['HARN']}  (the lookalike pair)")
