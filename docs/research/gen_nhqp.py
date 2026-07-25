#!/usr/bin/env python3
"""Generate nhqp.json from the official NH county abbreviation list.

Sources (committed alongside this script, so the run is reproducible):
  nhqp_counties.tsv — the 10 NH counties and their 3-letter abbreviations, from
                      the sponsor's rules page and PDF (page 3, "NH County
                      (Abbreviation)")
  nhqp_rules.md     — full rules research; the rules page was re-read live and
                      quoted back verbatim on 2026-07-24

Sponsor: Port City Amateur Radio Club (W1WQM), https://w1wqm.org/nh-qso-party/
Rules revision "Revised August 19, 2025", which lists the 2026 dates.

Usage:  python3 gen_nhqp.py        (run from docs/research/)
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "nhqp.json")
SRC = os.path.join(HERE, "nhqp_counties.tsv")

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
        sys.exit(f"NHQP duplicate abbreviation: {abbr}")
    counties[abbr] = name

assert len(counties) == 10, f"expected 10 NH counties, got {len(counties)}"
assert len(set(counties.values())) == 10, "NH county names not unique"
assert all(len(a) == 3 for a in counties), "all NHQP abbreviations are 3 letters"
# The sponsor's rules print "Merrimac (MER)"; the county is Merrimack. The
# abbreviation is unaffected, and the correct spelling is used for display.
assert counties["MER"] == "Merrimack", \
    f"MER should display as Merrimack, got {counties['MER']!r}"
assert counties["COO"] == "Coos" and counties["HIL"] == "Hillsborough"

# Rules, non-NH stations: "Maximum multiplier count: 50 (10 counties per band,
# 5 bands)". That arithmetic confirms both the county count and the band list.
BANDS = ["80m", "40m", "20m", "15m", "10m"]
assert len(counties) * len(BANDS) == 50, "the rules' stated 50-multiplier maximum"

nhqp = {
    "schemaVersion": 1,
    "id": "nhqp",
    "name": "New Hampshire QSO Party",
    "cabrilloContest": "NH-QSO-PARTY",
    "homeState": "NH",
    "countyAbbrLength": 3,
    # "80 through 10 M, except WARC bands (12, 17, 30 M)" — 5 bands, no 160 m.
    "validBands": BANDS,
    # "1 Point per phone QSO. 2 points by CW/Digital QSO."
    "points": {"phone": 1, "cw": 2, "digital": 2},
    # "Once per band per mode."
    "dupeScope": "bandMode",
    "multipliers": {
        # "NH Stations - one multiplier only: Each NH county, each state, each
        # Canadian province and up to 10 DXCC country once."
        "inState": {
            "classes": ["county", "state", "province", "dx"],
            # The rules never say NH itself counts as a state, and NH stations
            # send a county so the token NH is never received. See
            # nhqp_rules.md multipliers section for why this ships false.
            "homeStateCountsViaCounty": False,
            "countScope": "once",
            # "up to 10 DXCC country" — see notes: unreachable in practice
            # because the exchange carries the literal token "DX".
            "dxMultCap": 10,
        },
        # "Non-NH Stations: Each NH county once per band. Maximum multiplier
        # count: 50 (10 counties per band, 5 bands)"
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "perBand",
        },
    },
    # No bonus station and no bonus points in either the current page or the
    # superseded June 2025 PDF.
    "bonuses": [],
    # Exchange: 'DX: RS(T) + "DX"' — the literal token, not a prefix.
    "dxStyle": "token",
    # No county-line provision exists; mobiles/portables move between counties
    # sequentially, one county per QSO.
    "maxSimultaneousCounties": 1,
    # See nhqp_rules.md — the Objective says "Stations outside of NH contact as
    # many NH stations as possible", which is an aim rather than a limit.
    "outStateWorksHomeStationsOnly": True,
    # "1600 Z to 0400 Z Saturday; 1200 Z to 2200 Z Sunday. Total operating time
    # 22 hours." Third weekend of September; the rules list "2026: September
    # 19 - 20". 12 h + 10 h = the stated 22.
    "schedule": [
        {"start": "2026-09-19T16:00:00Z", "end": "2026-09-20T04:00:00Z"},
        {"start": "2026-09-20T12:00:00Z", "end": "2026-09-20T22:00:00Z"},
    ],
    "counties": [{"abbr": a, "name": n} for a, n in sorted(counties.items(), key=lambda kv: kv[1])],
    "notes": (
        "verified: partial — rules from the Port City Amateur Radio Club's official page "
        "(w1wqm.org/nh-qso-party/, 'Revised August 19, 2025', which lists the 2026 dates), "
        "read verbatim 2026-07-24. KNOWN SCORING LIMITATION: the rules give NH stations "
        "'up to 10 DXCC country' as multipliers, but the exchange is 'DX: RS(T) + \"DX\"' — "
        "every DX station sends the same literal token, so this app cannot tell one DXCC "
        "entity from another and credits DX as a SINGLE multiplier. An NH station working "
        "several DX countries will therefore see a multiplier count up to 9 low. dxMultCap "
        "is set to 10 to record the rule, but it can never bind without a DXCC prefix "
        "table. Out-of-state entrants are unaffected: DX is not one of their multiplier "
        "classes. Multiplier scope is ASYMMETRIC — NH stations count a single combined list "
        "ONCE for the contest, while non-NH stations count NH counties ONCE PER BAND to a "
        "stated maximum of 50 (10 counties x 5 bands), which the generator asserts and "
        "which confirms both the county count and the band list. Neither scope matches the "
        "dupe scope (band + mode). This per-band rule is NEW: the superseded June 2025 PDF "
        "counted NH counties once for a maximum of ten, and the August 2025 revision that "
        "carries the 2026 dates changed it. Phone 1 pt, CW and digital 2 pts. No 160 m, no "
        "WARC, no VHF. No bonus stations, no bonus points, no final-score multiplier, and no "
        "county-line provision. The sponsor prints 'Merrimac (MER)'; the county is "
        "Merrimack and the correct spelling is used for display, the abbreviation being "
        "unaffected. Note also that two clauses present in the superseded June 2025 PDF are "
        "GONE from the current revision and are deliberately not modeled: 'Washington DC "
        "QSOs count as Maryland' (so there is no DC alias here, unlike ALQP/TnQP/COQP/IAQP) "
        "and the maritime-mobile note. Cabrillo CONTEST value NH-QSO-PARTY per WA7BNM; the "
        "sponsor requires Cabrillo but prints no header token. "
        "OPEN QUESTIONS (why this is partial): (1) No rule states whether stations outside "
        "NH may work only NH stations. The Objective reads 'Stations outside of NH contact "
        "as many NH stations as possible' — an aim, not a limit — and the rules are "
        "otherwise silent. Shipped with the restriction ON for consistency with every other "
        "bundled party, and because a stray non-NH contact is then visibly flagged NO CREDIT "
        "rather than silently adding points. (2) Whether NH itself counts as a state "
        "multiplier for NH stations is not stated, and unlike KSQP/COQP/IAQP there is no "
        "in-state maximum to settle it by arithmetic; shipped as NOT counting, so as not to "
        "credit a multiplier the sponsor never described. Confirm both with the sponsor "
        "before submitting a log."
    ),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(nhqp, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"nhqp.json: {len(counties)} counties")
print(f"  out-of-state ceiling: {len(counties)} counties x {len(BANDS)} bands = "
      f"{len(counties) * len(BANDS)} (rules say 50)")
print(f"  schedule: 12 h + 10 h = 22 h (rules say 22)")
