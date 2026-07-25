#!/usr/bin/env python3
"""Generate coqp.json from the sponsor's official county abbreviation page.

Sources (committed alongside this script, so the run is reproducible):
  coqp_src_counties.txt — https://www.coloradoqsoparty.org/ "Colorado County
                          Abbreviations and Map", fetched 2026-07-23
  coqp_src_rules.txt    — https://www.coloradoqsoparty.org/rules/, same fetch;
                          re-verified verbatim against the live site 2026-07-24

See coqp_rules.md for the full rules research. Note in particular that the
rules' in-state ceiling of 128 multipliers per mode is what proves
homeStateCountsViaCounty is true — 64 + 50 + 13 + 1 = 128, so Colorado itself is
among the counted states, and a CO station can only earn it via a CO county.

Usage:  python3 gen_coqp.py        (run from docs/research/)
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "coqp.json")
SRC = os.path.join(HERE, "coqp_src_counties.txt")

text = open(SRC, encoding="utf-8").read()

# The abbreviation list sits between the intro line and the PDF download link.
# Everything after that is an "Amateurs per County" table whose rows carry a
# trailing licence count, so bounding the region keeps those out.
start = text.index("See the counties planned for activation.")
end = text.index("Download PDF")
region = text[start:end]

counties = {}
for line in region.splitlines():
    # " Clear Creek CLC" — name may contain spaces; abbr is 3 caps at line end.
    m = re.match(r"^\s*([A-Z][A-Za-z]*(?: [A-Z][A-Za-z]*)*)\s+([A-Z]{3})\s*$", line)
    if not m:
        continue
    name, abbr = m.group(1).strip(), m.group(2)
    if abbr in counties and counties[abbr] != name:
        sys.exit(f"COQP conflict: {abbr} -> {counties[abbr]} vs {name}")
    counties[abbr] = name

# Rules: "Stations Outside Colorado ... Maximum multipliers per mode: 64."
assert len(counties) == 64, f"expected 64 CO counties, got {len(counties)}"
assert len(set(counties.values())) == 64, "CO county names not unique"
assert all(len(a) == 3 for a in counties), "all COQP abbreviations are 3 letters"

# Colorado's abbreviations collide constantly; pin the groups that a human
# transcribing by hand would get wrong. MON is Montezuma, NOT Montrose.
EXPECTED = {
    "MON": "Montezuma", "MOT": "Montrose", "MOF": "Moffat", "MOR": "Morgan",
    "LAK": "Lake", "LAP": "La Plata", "LAR": "Larimer", "LAA": "Las Animas",
    "ELP": "El Paso", "ELB": "Elbert",
    "SAG": "Saguache", "SAJ": "San Juan", "SAM": "San Miguel",
    "KIO": "Kiowa", "KIC": "Kit Carson",
    "RIB": "Rio Blanco", "RIG": "Rio Grande",
    "DEL": "Delta", "DEN": "Denver", "DOL": "Dolores", "DOU": "Douglas",
    "CHA": "Chaffee", "CHE": "Cheyenne", "CLC": "Clear Creek",
    "BOU": "Boulder", "BRO": "Broomfield",
}
for abbr, name in EXPECTED.items():
    assert counties.get(abbr) == name, \
        f"{abbr} should be {name!r}, source says {counties.get(abbr)!r}"

# Rules: "Colorado Stations ... Maximum multipliers per mode: 128." Only reached
# if Colorado counts among the 50 states, which it can only do via a county.
STATES_INCLUDING_CO = 50   # DC counts as Maryland, so it adds nothing
PROVINCES = 13
DX = 1
ceiling = len(counties) + STATES_INCLUDING_CO + PROVINCES + DX
assert ceiling == 128, f"rules say 128 in-state mults per mode, computed {ceiling}"

coqp = {
    "schemaVersion": 1,
    "id": "coqp",
    "name": "Colorado QSO Party",
    "cabrilloContest": "COQP",
    "homeState": "CO",
    "countyAbbrLength": 3,
    # "80, 40, 20, 15, 10, 6, and 2 meters." No 160 m, no WARC, no 70 cm.
    "validBands": ["80m", "40m", "20m", "15m", "10m", "6m", "2m"],
    # "Two points are awarded for each valid QSO" — flat, both modes.
    "points": {"phone": 2, "cw": 2, "digital": 0},
    # "same call, band, mode, and Colorado county" — the sponsor spells out our
    # dupe key, so a mobile changing county is workable again.
    "dupeScope": "bandMode",
    "multipliers": {
        # "each Colorado county, U.S. state, Canadian province or territory, and
        # one DX multiplier ... Maximum multipliers per mode: 128."
        "inState": {
            "classes": ["county", "state", "province", "dx"],
            # Proven by the 128 ceiling: Colorado is one of the 50 counted
            # states and is only reachable through a Colorado county.
            "homeStateCountsViaCounty": True,
            "countScope": "perMode",
        },
        # "One multiplier per mode for each Colorado county worked. Maximum
        # multipliers per mode: 64."
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "perMode",
        },
    },
    "bonuses": [
        # "500-point bonus for each Colorado county activated, with at least 15
        # QSOs per county" — note 15, where TnQP uses 10.
        {"type": "activatedCountyCount", "minQSOs": 15, "points": 500},
    ],
    # "or 'DX' 2-character abbreviation"; also "Neither the USA nor Canada
    # counts as DX" and "Alaska and Hawaii shall count only as state multipliers".
    "dxStyle": "token",
    # "CW and Phone (SSB, AM, FM). Digital modes are not permitted."
    "allowedModes": ["phone", "cw"],
    # "The District of Columbia counts as Maryland."
    "stateAliases": {"DC": "MD"},
    # "QSOs on county lines must be logged as two entries."
    "maxSimultaneousCounties": 2,
    # "QSOs must include at least one Colorado station."
    "outStateWorksHomeStationsOnly": True,
    # Second Saturday in September from 2026 onward; "14:00 UTC Saturday through
    # 03:59 UTC Sunday", i.e. the window closes at 0400Z. 2026-09-12 is a Saturday.
    "schedule": [{"start": "2026-09-12T14:00:00Z", "end": "2026-09-13T04:00:00Z"}],
    "counties": [{"abbr": a, "name": n} for a, n in sorted(counties.items(), key=lambda kv: kv[1])],
    "notes": (
        "Verified against the sponsor's official 2026 rules "
        "(coloradoqsoparty.org/rules/, captured 2026-07-23 and re-fetched verbatim "
        "2026-07-24). The page is titled 'Colorado QSO Party 2026 Rules' and carries its "
        "own revision note — 'revised as of July 15, 2026: Rule 7 (Entry Categories); Rule "
        "12 (scoring mixed entries), and Rule 15 (Awards)' — so it is an explicitly dated "
        "current-year revision. Host changed for 2026 to the Grand Mesa Contesters of "
        "Colorado, and 2026 is the FIRST year on the new second-Saturday-in-September date, "
        "so older calendars and logger presets may disagree. Counties generated from the "
        "sponsor's official abbreviation page — never hand-typed; Colorado's codes collide "
        "heavily and MON is Montezuma, NOT Montrose (also MOT Montrose, MOF Moffat, MOR "
        "Morgan; LAK/LAP/LAR/LAA; ELP/ELB; SAG/SAJ/SAM; KIO/KIC; RIB/RIG). Flat 2 points "
        "per QSO; no digital modes. Multipliers count PER MODE, so a county worked on CW "
        "and again on phone is two multipliers. The rules' in-state ceiling of 128 per mode "
        "(64 counties + 50 states + 13 provinces + 1 DX) is asserted by the generator and "
        "is what establishes that Colorado itself counts as a state multiplier, earned via "
        "a Colorado county. DC counts as Maryland; AK/HI count only as states; neither USA "
        "nor Canada counts as DX. No 160 m. County lines are logged as two rows. Mobile and "
        "portable Colorado stations earn 500 bonus points per county with at least 15 QSOs "
        "(note: 15, where TnQP requires 10). No power or category multiplier. Cabrillo "
        "CONTEST value COQP per WA7BNM; the sponsor requires Cabrillo but prints no header "
        "token. Not modeled: cross-mode/cross-band/repeater/satellite QSOs not counting, "
        "and the one-transmitter-at-a-time rule."
    ),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(coqp, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"coqp.json: {len(counties)} counties")
print(f"  in-state mult ceiling: {len(counties)} + {STATES_INCLUDING_CO} + {PROVINCES} + {DX} "
      f"= {ceiling} per mode (rules say 128)")
print(f"  MON={counties['MON']}  MOT={counties['MOT']}  (the trap)")
