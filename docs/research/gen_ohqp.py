#!/usr/bin/env python3
"""Generate ohqp.json from the sponsor's official multiplier list.

Source (committed alongside this script, so the run is reproducible):
  ohqp_mults_ohio.html — https://www.ohqp.org/index.php/official-list-of-mults-for-ohio-stations/
  fetched 2026-07-23. That page states: "To assure credit is received for a
  multiplier, these abbreviations must be used. ... If conflicts exist, this
  list trumps all other lists."

See ohqp_rules.md for the full rules research. The rules' own "Total of 150
multipliers for Ohio Stations" is asserted below and independently confirms the
county count, the province count, and Ohio's exclusion from the state list.

Usage:  python3 gen_ohqp.py        (run from docs/research/)
"""
import html
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "ohqp.json")
SRC = os.path.join(HERE, "ohqp_mults_ohio.html")

raw = open(SRC, encoding="utf-8", errors="replace").read()
raw = re.sub(r"<script.*?</script>", "", raw, flags=re.S | re.I)
raw = re.sub(r"<style.*?</style>", "", raw, flags=re.S | re.I)
text = html.unescape(re.sub(r"<[^>]+>", "\n", raw))

# The list is a run of "ABBR = Name," entries: counties (4 letters), then state
# and province tokens (2 letters), then "DX = DX".
pairs = re.findall(r"\b([A-Z]{2,4})\s*=\s*([^,\n|]+)", text)

counties, states, provinces, dx = {}, {}, {}, {}
# S1: "11 Canadian Provinces (NL, PE, NS, NB, VE2-7, NT)" — VE2-7 being
# QC/ON/MB/SK/AB/BC. NT is the COMBINED Yukon-NWT-Nunavut entity, so YT and NU
# are deliberately not valid OhQP tokens.
PROVINCE_TOKENS = ["NL", "PE", "NS", "NB", "QC", "ON", "MB", "SK", "AB", "BC", "NT"]

for abbr, name in pairs:
    name = name.strip().rstrip(",").strip()
    if not name:
        continue
    if abbr == "DX":
        dx[abbr] = name
    elif len(abbr) == 4:
        if abbr in counties and counties[abbr] != name:
            sys.exit(f"OhQP county conflict: {abbr} -> {counties[abbr]} vs {name}")
        counties[abbr] = name
    elif abbr in PROVINCE_TOKENS:
        provinces[abbr] = name
    elif len(abbr) == 2:
        states[abbr] = name

# The sponsor's list misspells two county names. Correct the display names while
# keeping their abbreviations verbatim — and refuse to run if the source text
# ever changes, so this never silently rewrites correct data.
NAME_FIXES = {"AUGL": ("Auglaze", "Auglaize"), "VANW": ("VanWert", "Van Wert")}
for abbr, (expected_typo, fixed) in NAME_FIXES.items():
    if counties.get(abbr) != expected_typo:
        sys.exit(
            f"{abbr} no longer reads {expected_typo!r} (now {counties.get(abbr)!r}) — "
            "re-check the sponsor's list and update NAME_FIXES"
        )
    counties[abbr] = fixed

assert len(counties) == 88, f"expected 88 Ohio counties, got {len(counties)}"
assert len(set(counties.values())) == 88, "Ohio county names not unique"
assert all(len(a) == 4 for a in counties), "all OhQP county abbreviations are 4 letters"
assert "OH" not in states, "Ohio must be excluded from the state multiplier list"
assert "DC" in states, "Washington DC is its own multiplier"
assert len(states) == 50, f"expected 49 states + DC = 50, got {len(states)}"
assert sorted(provinces) == sorted(PROVINCE_TOKENS), f"province mismatch: {sorted(provinces)}"
assert provinces["NT"] == "Yukon-NWT-Nu", f"NT should be the combined entity, got {provinces['NT']!r}"
assert len(dx) == 1, "exactly one DX multiplier"

# Rules: "Total of 150 multipliers for Ohio Stations."
total = len(counties) + len(states) + len(provinces) + len(dx)
assert total == 150, f"rules say 150 multipliers for Ohio stations, computed {total}"

ohqp = {
    "schemaVersion": 1,
    "id": "ohqp",
    "name": "Ohio QSO Party",
    "cabrilloContest": "MRRC-OHQP",
    "homeState": "OH",
    "countyAbbrLength": 4,
    "validBands": ["160m", "80m", "40m", "20m", "15m", "10m"],
    # "SSB contact is worth one point ... CW contact is worth two points."
    "points": {"phone": 1, "cw": 2, "digital": 0},
    # "worked once per mode on each band"
    "dupeScope": "bandMode",
    "multipliers": {
        # "49 American States (excluding Ohio), 1 Washington DC, 11 Canadian
        # Provinces, 88 Ohio Counties and 1 DX. Total of 150."
        "inState": {
            "classes": ["county", "state", "province", "dx"],
            "homeStateCountsViaCounty": False,
            "countScope": "perMode",
        },
        # "FOR ALL OTHER STATIONS - multipliers are the 88 Ohio counties."
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "perMode",
        },
    },
    "bonuses": [],
    # "CW and SSB on 160, 80, 40, 20, 15, and 10 meters" — no digital.
    "allowedModes": ["phone", "cw"],
    # Objective: "Non-Ohio stations may work only Ohio stations, while Ohio
    # stations may contact anyone."
    "outStateWorksHomeStationsOnly": True,
    # Misc: "No station may claim simultaneous operation in more than one
    # county, state, or province."
    "maxSimultaneousCounties": 1,
    # 11 provinces only, and NT is the combined Yukon/NWT/Nunavut entity — so
    # YT and NU are not valid OhQP tokens.
    "provinces": PROVINCE_TOKENS,
    # "The Ohio QSO Party occurs on the fourth Saturday of August ... 1200 EDT
    # [noon] to 2400 EDT [midnight] (1600Z Saturday until 0400Z Sunday)."
    # Fourth Saturday of Aug 2026 = Aug 22.
    "schedule": [{"start": "2026-08-22T16:00:00Z", "end": "2026-08-23T04:00:00Z"}],
    "counties": [{"abbr": a, "name": n} for a, n in sorted(counties.items(), key=lambda kv: kv[1])],
    "notes": (
        "Verified against the sponsor's official rules (ohqp.org/index.php/rules/, "
        "captured 2026-07-23, page re-checked 2026-07-24 — header reads 'Next OhQP Sat 22 "
        "Aug 2026' and the self-spotting rule is tagged '[New 2026]', so this is the "
        "current-year revision). Counties generated from the sponsor's official multiplier "
        "list (ohqp_mults_ohio.html), which states 'these abbreviations must be used ... "
        "this list trumps all other lists' — never hand-typed. The rules' stated 'Total of "
        "150 multipliers for Ohio Stations' is asserted by the generator (88 counties + 49 "
        "states + DC + 11 provinces + 1 DX) and independently confirms the county count and "
        "Ohio's exclusion from the state list. Mults count ONCE PER MODE, so one county on "
        "CW and again on SSB is two multipliers. Phone 1 pt / CW 2 pts; no digital modes. "
        "Non-Ohio stations may work only Ohio stations. Simultaneous multi-county operation "
        "is expressly forbidden. PROVINCES: only 11 count, and NT is a COMBINED "
        "Yukon-NWT-Nunavut multiplier per the official list — YT and NU are therefore not "
        "valid OhQP tokens and are rejected on entry; a Yukon station sends NT. The "
        "sponsor's list misspells two counties ('Auglaze' for Auglaize, 'VanWert' for Van "
        "Wert); abbreviations are kept verbatim and the display names corrected, with the "
        "generator asserting it touches only those two. Cabrillo CONTEST value MRRC-OHQP "
        "per WA7BNM; the sponsor prints none and states it ignores Cabrillo headers "
        "entirely, collecting call/location/category at upload instead. Not modeled: the "
        "500-foot rule for mobiles claiming a new county, and the no-cross-mode-contacts "
        "rule."
    ),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(ohqp, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"ohqp.json: {len(counties)} counties")
print(f"  mult total for Ohio stations: {len(counties)} + {len(states)} + "
      f"{len(provinces)} + {len(dx)} = {total} (rules say 150)")
print(f"  provinces ({len(provinces)}): {' '.join(PROVINCE_TOKENS)}  [NT = {provinces['NT']}]")
