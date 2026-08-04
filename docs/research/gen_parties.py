#!/usr/bin/env python3
"""Generate ksqp.json and tqp.json from the official source files.

Sources (downloaded from official sites 2026-07-23):
  KSQP-Mults.txt      — pdftotext of https://www.ksqsoparty.org/info/KSQP-Mults-P.pdf
  TX_county_abbrevs.txt — from https://www.txqp.net/tqp_resource/planning/txcounty.zip
"""
import json
import re
import sys

OUT_DIR = "/Users/tom/AppDev/Apple/QSOPartyLogger/Resources/Parties"

# --- Kansas: parse "ABB - Name" pairs anywhere in the text; dict dedupes the
# "watch out for similar abbreviations" sidebar repeats. En-dash tolerated (WYA).
ks_text = open("KSQP-Mults.txt").read()
ks = {}
for m in re.finditer(r"\b([A-Z]{3})\s*[-–]\s*([A-Z][a-zA-Z]+)", ks_text):
    abbr, name = m.group(1), m.group(2)
    if abbr in ks and ks[abbr] != name:
        sys.exit(f"KSQP conflict: {abbr} -> {ks[abbr]} vs {name}")
    ks[abbr] = name
assert len(ks) == 105, f"expected 105 KS counties, got {len(ks)}"
assert len(set(ks.values())) == 105, "KS county names not unique"

# --- Texas: "Name          ABBR" lines; names may contain spaces (Deaf Smith).
tx = {}
for line in open("TX_county_abbrevs.txt"):
    line = line.rstrip()
    m = re.match(r"^([A-Za-z][A-Za-z .']*?)\s+([A-Z]{2,4})$", line)
    if m:
        name, abbr = m.group(1).strip(), m.group(2)
        if abbr in tx and tx[abbr] != name:
            sys.exit(f"TQP conflict: {abbr} -> {tx[abbr]} vs {name}")
        tx[abbr] = name
assert len(tx) == 254, f"expected 254 TX counties, got {len(tx)}"
assert len(set(tx.values())) == 254, "TX county names not unique"

def counties(d):
    return [{"abbr": a, "name": n} for a, n in sorted(d.items(), key=lambda kv: kv[1])]

ksqp = {
    "schemaVersion": 1,
    "id": "ksqp",
    "name": "Kansas QSO Party",
    "cabrilloContest": "KS-QSO-PARTY",
    "homeState": "KS",
    "countyAbbrLength": 3,
    "validBands": ["80m", "40m", "20m", "15m", "10m", "6m"],
    "points": {"phone": 2, "cw": 3, "digital": 3},
    "dupeScope": "bandMode",
    "multipliers": {
        "inState": {
            "classes": ["state", "province", "dx"],
            "homeStateCountsViaCounty": True,
            "countScope": "once",
        },
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
        },
    },
    "bonuses": [
        {"type": "workStation", "call": "KS0KS", "points": 100}
    ],
    "oneByOne": {
        "words": ["KANSAS", "QSOPARTY", "SUNFLOWER", "YELLOWBRICKROAD"],
        "wildcard": "KS0KS",
    },
    "schedule": [
        {"start": "2026-08-29T14:00:00Z", "end": "2026-08-30T02:00:00Z"},
        {"start": "2026-08-30T14:00:00Z", "end": "2026-08-30T20:00:00Z"},
    ],
    "counties": counties(ks),
    "notes": "Verified against official 2026 rules (ksqsoparty.org, fetched 2026-07-23). Counties from official KSQP-Mults PDF.",
}

tqp = {
    "schemaVersion": 1,
    "id": "tqp",
    "name": "Texas QSO Party",
    "cabrilloContest": "TX-QSO-PARTY",
    "homeState": "TX",
    "countyAbbrLength": 4,
    "validBands": ["160m", "80m", "40m", "20m", "15m", "10m", "6m", "2m"],
    "points": {"phone": 2, "cw": 3, "digital": 3},
    "dupeScope": "bandMode",
    "multipliers": {
        "inState": {
            "classes": ["state", "county", "province", "dx"],
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
        {"type": "mobileCountyCount", "per": 5, "points": 500}
    ],
    "schedule": [
        {"start": "2026-09-19T14:00:00Z", "end": "2026-09-20T02:00:00Z"},
        {"start": "2026-09-20T14:00:00Z", "end": "2026-09-20T20:00:00Z"},
    ],
    "counties": counties(tx),
    "notes": "verified: partial — points/mults/bonus from txqp.net rules; counties from official txcounty.zip (2014 file, fetched 2026-07-23). Confirm band list and current-year rules before submitting.",
}

for obj, fname in [(ksqp, "ksqp.json"), (tqp, "tqp.json")]:
    with open(f"{OUT_DIR}/{fname}", "w") as f:
        json.dump(obj, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"{fname}: {len(obj['counties'])} counties")

# --- Alabama: official page renders "Name / ABBR / Name" triplets.
al_lines = [l.strip() for l in open("research/alqp_counties_text.txt") if l.strip()]
al = {}
for i in range(len(al_lines) - 2):
    name, abbr, name2 = al_lines[i], al_lines[i + 1], al_lines[i + 2]
    if name == name2 and abbr.isupper() and 3 <= len(abbr) <= 4 and abbr.isalpha() and name[0].isupper() and not name.isupper():
        if abbr in al and al[abbr] != name:
            sys.exit(f"ALQP conflict: {abbr} -> {al[abbr]} vs {name}")
        al[abbr] = name
assert len(al) == 67, f"expected 67 AL counties, got {len(al)}: {sorted(al)}"
assert len(set(al.values())) == 67, "AL county names not unique"

alqp = {
    "schemaVersion": 1,
    "id": "alqp",
    "name": "Alabama QSO Party",
    "cabrilloContest": "AL-QSO-PARTY",
    "homeState": "AL",
    "countyAbbrLength": 4,
    "validBands": ["80m", "40m", "20m", "15m", "10m"],
    "points": {"phone": 2, "cw": 2, "digital": 0},
    "dupeScope": "bandMode",
    "multipliers": {
        "inState": {
            "classes": ["county", "state", "province", "dx"],
            # The sponsor counts DXCC entities individually -- see the
            # multiplier quote in the notes. Resolved against the ARRL
            # DXCC List (Resources/DXCC, generated by gen_dxcc.py).
            "dxCountsEntities": True,
            "homeStateCountsViaCounty": True,
            "countScope": "perMode",
        },
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "perMode",
        },
    },
    "bonuses": [],
    "dxStyle": "prefix",
    "allowedModes": ["phone", "cw"],
    "maxSimultaneousCounties": 1,
    "stateAliases": {"DC": "MD"},
    "schedule": [
        {"start": "2026-07-25T15:00:00Z", "end": "2026-07-26T03:00:00Z"}
    ],
    "counties": counties(al),
    "notes": "Verified against official 2026 AQP rules (alabamacontestgroup.org, fetched 2026-07-23). Counties from official County Map and Counties page. County-line sitting is NOT permitted (rules Misc a). Mults count once per mode; DC counts as Maryland; DX mults are country prefixes.",
}

with open(f"{OUT_DIR}/alqp.json", "w") as f:
    json.dump(alqp, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(f"alqp.json: {len(alqp['counties'])} counties")
