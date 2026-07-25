#!/usr/bin/env python3
"""Generate njqp.json from the sponsor's official multiplier tables.

Source (committed alongside this script, so the run is reproducible):
  njqp_counties.tsv — transcribed from the sponsor's multiplier tables, which
  are published ONLY as images at
  https://sites.google.com/view/k2td-bcrc/nj-qp/nj-mults
  (committed as njqp_mults_counties_provinces.png and njqp_mults_states.png).

See njqp_rules.md for the full rules research — in particular that the sponsor's
date (Sep 12) contradicts the State QSO Party Challenge calendar (Sep 19), and
that Newfoundland is abbreviated NF here rather than the standard NL.

Usage:  python3 gen_njqp.py        (run from docs/research/)
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "njqp.json")
SRC = os.path.join(HERE, "njqp_counties.tsv")

counties = {}
for line in open(SRC, encoding="utf-8"):
    line = line.rstrip("\n")
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    parts = line.split("\t")
    if len(parts) != 2:
        sys.exit(f"malformed TSV row (want abbr/county): {line!r}")
    abbr, name = (p.strip() for p in parts)
    if abbr in counties:
        sys.exit(f"NJQP duplicate abbreviation: {abbr}")
    counties[abbr] = name

# Rules: "NJ Counties (21) ... maximum of 21x multiplier" for non-NJ stations.
assert len(counties) == 21, f"expected 21 NJ counties, got {len(counties)}"
assert len(set(counties.values())) == 21, "NJ county names not unique"
assert all(len(a) == 4 for a in counties), "all NJQP abbreviations are 4 characters"
# Not first-four-letter truncations — the two that bite.
assert counties["CMDN"] == "Camden", f"CMDN should be Camden, got {counties.get('CMDN')!r}"
assert counties["WRRN"] == "Warren", f"WRRN should be Warren, got {counties.get('WRRN')!r}"
assert "CAMD" not in counties and "WARR" not in counties, \
    "the naive truncations must not appear"

# Official province table uses the LEGACY 'NF' for Newfoundland & Labrador,
# not the modern 'NL' this repo defaults to. All 13 count, and unlike OhQP,
# YT and NU stay separate from NT.
PROVINCES = ["AB", "BC", "MB", "NB", "NF", "NS", "NT", "NU", "ON", "PE", "QC", "SK", "YT"]
assert len(PROVINCES) == 13, "rules count 13 Canadian provinces"
assert "NF" in PROVINCES and "NL" not in PROVINCES, "NJQP spells Newfoundland NF"

# Rules: "NJ Counties (21) + States (49 not NJ) + Canadian Provinces (13) +
# DX (1) for a maximum of 84x". 49 = 50 US states less NJ, with NO DC row in the
# sponsor's states table.
STATES_LESS_NJ_NO_DC = 49
ceiling = len(counties) + STATES_LESS_NJ_NO_DC + len(PROVINCES) + 1
assert ceiling == 84, f"rules say 84 in-state contact mults, computed {ceiling}"

njqp = {
    "schemaVersion": 1,
    "id": "njqp",
    "name": "New Jersey QSO Party",
    "cabrilloContest": "NJQP",
    "homeState": "NJ",
    "countyAbbrLength": 4,
    # "80, 40, 20, 15 and 10 meters ONLY."
    "validBands": ["80m", "40m", "20m", "15m", "10m"],
    # "two points ... CW / Digital ... one point if a valid phone contact"
    "points": {"phone": 1, "cw": 2, "digital": 2},
    # "The same station may be contacted on CW, Digital and Phone on each band."
    "dupeScope": "bandMode",
    "multipliers": {
        # "NJ Counties (21) + States (49 not NJ) + Canadian Provinces (13) +
        # DX (1) for a maximum of 84x" — maxima equal entity counts, so once.
        "inState": {
            "classes": ["county", "state", "province", "dx"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
        },
        # "Non-NJ Stations: count up contacted NJ Counties (21) ... Add total
        # unique counties for contact multiplier."
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
        },
    },
    "bonuses": [],
    "dxStyle": "token",
    # NJ struck from the state list ("NJ : use counties"); DC has no row at all
    # in the sponsor's states table and is not among the counted 49.
    "excludedStateTokens": ["NJ", "DC"],
    "provinces": PROVINCES,
    # "No station may claim simultaneous operation in more than one county,
    # state, or province."
    "maxSimultaneousCounties": 1,
    # See njqp_rules.md §14.4 — implied by the Objectives, not stated outright.
    "outStateWorksHomeStationsOnly": True,
    # "High power = 1x, Low power = 2x, QRP = 4x"; no station-category factor.
    "scoreMultipliers": {"power": {"HIGH": 1, "LOW": 2, "QRP": 4}},
    # "Saturday September 12, 2026 ... Sat 10:00 AM EDT (1400 UTC) ... Sat
    # 10:00 PM EDT (0200 UTC)" — 22:00 EDT Sat is 0200Z Sunday.
    "schedule": [{"start": "2026-09-12T14:00:00Z", "end": "2026-09-13T02:00:00Z"}],
    "counties": [{"abbr": a, "name": n} for a, n in sorted(counties.items(), key=lambda kv: kv[1])],
    "notes": (
        "verified: partial — rules from the Burlington County Radio Club's official 2026 "
        "page (sites.google.com/view/k2td-bcrc/nj-qp/2026-rules, footer version 2026rev0.5, "
        "captured 2026-07-23 and re-read live 2026-07-24). DATE NOTE: the sponsor says "
        "Saturday September 12, 2026 (1400Z-0200Z), which CONTRADICTS the State QSO Party "
        "Challenge calendar's Sep 19-20; WA7BNM agrees with the sponsor. Article 19 gives "
        "the sponsor authority, so Sep 12 ships. Counties generated from njqp_counties.tsv, "
        "transcribed from the sponsor's multiplier tables — which exist only as images "
        "(committed as njqp_mults_*.png) — never hand-typed; note CMDN is Camden and WRRN "
        "is Warren, neither being a first-four-letters truncation. Multipliers count ONCE "
        "for the contest, not per band or per mode: the rules' maxima (84 in-state, 21 "
        "out-of-state) equal the entity counts, and both of the sponsor's worked examples "
        "confirm it. The 84 total (21 counties + 49 states + 13 provinces + 1 DX) is "
        "asserted by the generator. PROVINCES: all 13 count, but the official table spells "
        "Newfoundland & Labrador NF, the legacy abbreviation, not the standard NL - the "
        "provinces override carries NF so VO1/VO2 contacts can be logged. Power is a "
        "final-score multiplier (High 1x, Low 2x, QRP 4x) with no station-category factor; "
        "both of the sponsor's example scores reproduce exactly. Phone 1 pt, CW and digital "
        "2 pts each; digital is a first-class mode. No bonuses. Simultaneous multi-county "
        "operation is forbidden. "
        "OPEN QUESTIONS (why this is partial): (1) The sponsor's states table has NO "
        "District of Columbia row and counts only 49 states, so DC ships as an excluded "
        "token and cannot be logged at all. NJQP's tables simply have no answer for DC, and "
        "inventing a DC-counts-as-Maryland alias would be a rule this sponsor never wrote "
        "(ALQP/TnQP/COQP each state that alias explicitly; NJQP does not). (2) No rule says "
        "outright that non-NJ stations may work only NJ stations - the Objectives imply it "
        "and the live page contains no 'only NJ' phrasing. Shipped with the restriction ON, "
        "matching the objectives, the multiplier structure and universal convention; with it "
        "on, a stray non-NJ contact is visibly flagged NO CREDIT rather than silently "
        "scoring. Confirm both with NewJerseyQSOParty@gmail.com before submitting a log. "
        "Not modeled: the 1000-foot circle, the Rookie overlay, the call-suffix convention "
        "for NJ stations changing county, and club aggregate scoring."
    ),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(njqp, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"njqp.json: {len(counties)} counties")
print(f"  contact mult ceiling: {len(counties)} + {STATES_LESS_NJ_NO_DC} + {len(PROVINCES)} + 1 "
      f"= {ceiling} (rules say 84)")
print(f"  provinces: {' '.join(PROVINCES)}  [NF, not NL]")
