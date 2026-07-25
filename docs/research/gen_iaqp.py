#!/usr/bin/env python3
"""Generate iaqp.json from the official Iowa county abbreviation list.

Sources (committed alongside this script, so the run is reproducible):
  iaqp_county_list.txt — the sponsor's "IOWA QSO Party County List"
                         (Updated: 08 JUNE 2018), 99 counties in 3 columns
  iaqp_state_prov.txt  — the sponsor's "State and Province List"
                         (Updated: 12 AUG 2018)
  iaqp_page.txt        — https://www.w0yl.com/IAQP rules page, fetched
                         2026-07-23; re-checked live 2026-07-24

See iaqp_rules.md for the full rules research, including why this ships
`verified: partial`.

Usage:  python3 gen_iaqp.py        (run from docs/research/)
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "iaqp.json")
SRC = os.path.join(HERE, "iaqp_county_list.txt")
STATES = os.path.join(HERE, "iaqp_state_prov.txt")

text = open(SRC, encoding="utf-8").read()

# Three (num, abbr, name) triplets per line. Names carry spaces (Black Hawk,
# Palo Alto, Des Moines) and an apostrophe (O'Brien), and end at a run of two or
# more spaces or at end of line.
counties, numbers = {}, {}
for m in re.finditer(r"(\d{1,3})\s+([A-Z]{3})\s+([A-Za-z'][A-Za-z' ]*?)(?=\s{2,}|\s*$)",
                     text, re.MULTILINE):
    num, abbr, name = int(m.group(1)), m.group(2), m.group(3).strip()
    if abbr in counties and counties[abbr] != name:
        sys.exit(f"IAQP conflict: {abbr} -> {counties[abbr]} vs {name}")
    counties[abbr] = name
    numbers[abbr] = num

assert len(counties) == 99, f"expected 99 Iowa counties, got {len(counties)}"
assert len(set(counties.values())) == 99, "IA county names not unique"
assert all(len(a) == 3 for a in counties), "all IAQP abbreviations are 3 letters"
assert sorted(numbers.values()) == list(range(1, 100)), "numbering must be exactly 1..99"

# Abbreviations a human would get wrong. Iowa has four CL* counties and six PO*/
# W* clusters; O'Brien carries an apostrophe.
EXPECTED = {
    "BTL": "Butler", "HDN": "Hardin", "HRS": "Harrison",
    "CLR": "Clarke", "CLA": "Clay", "CLT": "Clayton", "CLN": "Clinton",
    "MNA": "Monona", "MOE": "Monroe", "MTG": "Montgomery",
    "MRN": "Marion", "MSL": "Marshall", "MAH": "Mahaska", "MAD": "Madison",
    "OBR": "O'Brien", "DSM": "Des Moines", "BKH": "Black Hawk",
    "BNV": "Buena Vista", "CEG": "Cerro Gordo", "PLA": "Palo Alto",
    "PLY": "Plymouth", "POC": "Pocahontas", "POL": "Polk",
    "POT": "Pottawattamie", "POW": "Poweshiek",
    "WNB": "Winnebago", "WNS": "Winneshiek", "WOO": "Woodbury", "WOR": "Worth",
    "VAN": "Van Buren", "LYN": "Lyon", "CRF": "Crawford",
}
for abbr, name in EXPECTED.items():
    assert counties.get(abbr) == name, \
        f"{abbr} should be {name!r}, source says {counties.get(abbr)!r}"
assert "BUT" not in counties, "Butler is BTL, not BUT"

# The sponsor's state list folds DC into Maryland and carries all 50 states
# (Iowa included) plus the standard 13 provinces with the modern NL spelling.
state_text = open(STATES, encoding="utf-8").read()
assert "Maryland and DC" in state_text, "sponsor's list must still fold DC into MD"
assert re.search(r"\bNL\s+Newfoundland", state_text), "sponsor uses NL, not NJQP's NF"
assert re.search(r"\bIA\s+Iowa\b", state_text), "Iowa is itself a listed multiplier"

iaqp = {
    "schemaVersion": 1,
    "id": "iaqp",
    "name": "Iowa QSO Party",
    "cabrilloContest": "IAQP",
    "homeState": "IA",
    "countyAbbrLength": 3,
    # "any amateur band EXCEPT the 60m, 30m, 17m, and 12m bands." 1.25 m is
    # legal and the rules suggest 222.150/223.450, but this app has no 222 MHz
    # band (see notes).
    "validBands": ["160m", "80m", "40m", "20m", "15m", "10m", "6m", "2m", "70cm"],
    # phone 1, CW 2, digital 2
    "points": {"phone": 1, "cw": 2, "digital": 2},
    # "Non-Iowa stations may be worked ONCE per MODE per BAND. Iowa stations may
    # be worked ONCE per MODE per BAND per COUNTY." The received county is part
    # of the engine's dupe key, so one scope covers both.
    "dupeScope": "bandMode",
    "multipliers": {
        # "One multiplier for each Iowa county worked, and one multiplier for
        # each state (including Iowa) or Canadian province worked." Iowa itself
        # is earned through an Iowa county, since Iowa stations send counties.
        # NOTE: no dx class — "No multiplier for working DX stations."
        "inState": {
            "classes": ["county", "state", "province"],
            "homeStateCountsViaCounty": True,
            "countScope": "once",
        },
        # "Stations Outside Iowa: One multiplier for each Iowa county worked."
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
        },
    },
    # "No bonus points this year" / "No Bonus Stations this year".
    "bonuses": [],
    # DX stations send the literal token. They score QSO points but never a
    # multiplier, which falls out of omitting dx from the class lists above.
    "dxStyle": "token",
    # Sponsor's official state list prints "MD  Maryland and DC".
    "stateAliases": {"DC": "MD"},
    # "may park/setup on a county line/junction and represent all counties at
    # the intersection simultaneously" — Iowa junctions reach four.
    "maxSimultaneousCounties": 4,
    # See iaqp_rules.md §14 — not stated by the sponsor either way.
    "outStateWorksHomeStationsOnly": True,
    # Third weekend of September, 9AM-9PM US Central. 2026: Sat Sep 19,
    # 1400Z Sep 19 - 0200Z Sep 20 (CDT = UTC-5).
    "schedule": [{"start": "2026-09-19T14:00:00Z", "end": "2026-09-20T02:00:00Z"}],
    "counties": [{"abbr": a, "name": n} for a, n in sorted(counties.items(), key=lambda kv: kv[1])],
    "notes": (
        "verified: partial — rules from the Story County Amateur Radio Club's page "
        "(w0yl.com/IAQP, captured 2026-07-23, re-checked live 2026-07-24). Counties "
        "generated from the sponsor's official county list (iaqp_county_list.txt, updated 08 "
        "JUNE 2018) — never hand-typed; Iowa's codes cluster badly and the generator pins 32 "
        "of them, including BTL Butler (not BUT), HDN Hardin, CLR/CLA/CLT/CLN "
        "Clarke/Clay/Clayton/Clinton, MNA/MOE/MTG Monona/Monroe/Montgomery, MRN/MSL "
        "Marion/Marshall, DSM Des Moines, BKH Black Hawk, BNV Buena Vista, PLA Palo Alto, "
        "WNB/WNS Winnebago/Winneshiek, and OBR O'Brien with its apostrophe. Phone 1 pt, CW "
        "and digital 2 pts. Multipliers are applied ONCE ONLY, explicitly 'NOT per Band, and "
        "NOT per Mode'. Iowa stations count Iowa counties plus each state INCLUDING IOWA "
        "plus Canadian provinces — Iowa itself is earned via an Iowa county, since Iowa "
        "stations send a county and never the token IA. Iowa stations get NO multiplier for "
        "DX, though DX contacts still score QSO points ('definitely DO work them'), which is "
        "why dx is absent from the multiplier classes. The sponsor's official state list "
        "prints 'MD Maryland and DC', so DC is credited as Maryland; the province list uses "
        "the standard 13 with the modern NL spelling, unlike NJQP's NF. Iowa mobiles, rovers "
        "and portables may sit on a county line or junction and claim ALL intersecting "
        "counties in a single exchange, up to four. No bonus points and no bonus stations. "
        "No power or category multiplier. Cabrillo CONTEST value IAQP per WA7BNM. "
        "OPEN QUESTIONS (why this is partial): (1) The published rules page is still titled "
        "for 2025 and its rules PDF is dated 12 AUG 2018; only the 2026 DATE (September 19, "
        "third weekend, 1400Z-0200Z) is announced, so re-check w0yl.com/IAQP in early "
        "September for a 2026 revision. (2) No rule states whether stations outside Iowa may "
        "work only Iowa stations. The Objective says 'Stations outside Iowa work as many "
        "Iowa stations as possible' — an aim, not a limit — and the dupe list's 'Non-Iowa "
        "stations may be worked ONCE per MODE per BAND' is not scoped to Iowa entrants, "
        "which arguably cuts the other way. Shipped with the restriction ON for consistency "
        "with every other bundled party and because a stray non-Iowa contact is then visibly "
        "flagged NO CREDIT rather than silently adding points; if the sponsor scores those "
        "QSOs, this under-counts and the flag makes that obvious. Confirm with "
        "iowaqsoparty@hotmail.com. (3) IAQP permits 1.25 m and suggests 222.150/223.450; "
        "this app has no 222 MHz band, so those QSOs cannot be logged on that band. "
        "Not modeled: satellite QSOs being allowed, and the club competition."
    ),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(iaqp, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"iaqp.json: {len(counties)} counties")
print(f"  BTL={counties['BTL']}  OBR={counties['OBR']}  DSM={counties['DSM']}")
print(f"  CL* -> {', '.join(f'{a}={counties[a]}' for a in ['CLR','CLA','CLT','CLN'])}")
