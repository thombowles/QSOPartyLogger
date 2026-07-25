#!/usr/bin/env python3
"""Generate nyqp.json from the sponsor's own rules PDF and county CSV.

The 62 counties are taken from TWO sponsor sources and checked against each
other: the NAMES come from the rules PDF's Name/Abbreviation table, and the
ABBREVIATION SET is cross-checked against the official CSV. A mis-parse of
either shows up as a set difference rather than as a wrong county.

Sources (committed alongside this script, so the run is reproducible):
  nyqp_rules_2025.txt  — pdftotext -layout of the official rules PDF,
                         footer "v1.2 FINAL 2025-10-01", from
                         nyqp.org/wordpress/nyqp-rules/
  nyqp_counties.csv    — nyqp.org/.../2025/04/NYQP-Counties-Sheet1.csv
  nyqp_rules.md        — full rules research; both fetched 2026-07-24

PARSING NOTE: "New York County List" and "SCORING" both appear in the PDF's table
of contents before they appear as headings, so anchoring on those strings alone
captures the TOC. This anchors on the table's own "Name  Abbreviation" header row.

NOTE the rules are the 2025 edition; the 2026 dates come from the formula printed
in the document's own title block ("Third Saturday in October"). See
nyqp_rules.md §2. The party ships verified: partial for that.

Sponsor: Rochester (NY) DX Association, https://nyqp.org

Usage:  python3 gen_nyqp.py        (run from docs/research/)
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "nyqp.json")
RULES = os.path.join(HERE, "nyqp_rules_2025.txt")
CSV = os.path.join(HERE, "nyqp_counties.csv")

rules_raw = open(RULES, encoding="utf-8").read().replace("’", "'").replace("“", '"').replace("”", '"')
rules = re.sub(r"\s+", " ", rules_raw)

# --- Counties: the PDF's own table, anchored on its header row. ---
m = re.search(r"Name\s+Abbreviation(.*?)^SCORING", rules_raw, re.S | re.M)
if not m:
    sys.exit("county table not found in nyqp_rules_2025.txt")
counties = {}
for name, abbr in re.findall(r"^\s*([A-Z][A-Za-z.'\- ]*?)\s{2,}([A-Z]{3})\s*$", m.group(1), re.M):
    name = name.strip()
    if abbr in counties:
        sys.exit(f"NYQP duplicate county abbreviation: {abbr}")
    counties[abbr] = name

# --- Cross-check the abbreviation set against the sponsor's official CSV. ---
csv_codes = [
    line.strip()
    for line in open(CSV, encoding="utf-8-sig")
    if re.fullmatch(r"[A-Z]{3}", line.strip())
]

assert len(counties) == 62, f"expected 62 NY counties, got {len(counties)}: {sorted(counties)}"
assert len(csv_codes) == 62, f"expected 62 codes in the CSV, got {len(csv_codes)}"
assert set(counties) == set(csv_codes), (
    "the rules PDF and the official CSV disagree on the county codes: "
    f"pdf-only {sorted(set(counties) - set(csv_codes))}, "
    f"csv-only {sorted(set(csv_codes) - set(counties))}"
)
assert len(set(counties.values())) == 62, "NY county names not unique"
assert all(len(a) == 3 for a in counties), "all NYQP abbreviations are 3 letters"
# The rules state the count themselves, twice.
assert "New York Counties (62)" in rules and "maximum of 62 multipliers" in rules, \
    "the rules' own county count is gone — re-read the source"

# Spot checks: the near-collision clusters and the five NYC boroughs (Article 18).
for abbr, name in [
    ("CHA", "Chautauqua"), ("CHE", "Chemung"), ("CGO", "Chenango"),  # CGO breaks the pattern
    ("COL", "Columbia"), ("COR", "Cortland"),
    ("ONE", "Oneida"), ("ONO", "Onondaga"), ("ONT", "Ontario"),
    ("ORA", "Orange"), ("ORL", "Orleans"),
    ("SCH", "Schenectady"), ("SCO", "Schoharie"), ("SCU", "Schuyler"),
    ("STE", "Steuben"), ("STL", "St. Lawrence"),
    ("BRX", "Bronx"), ("BRM", "Broome"),
    ("KIN", "Kings"), ("NEW", "New York"), ("QUE", "Queens"), ("RIC", "Richmond"),
    ("MTG", "Montgomery"),
]:
    assert counties.get(abbr) == name, f"{abbr} should be {name}, got {counties.get(abbr)!r}"

# --- Multipliers: the sponsor's arithmetic must close exactly. ---
US_STATES, PROVINCES = 50, 13
IN_STATE_MAX = US_STATES + len(counties) + PROVINCES
assert IN_STATE_MAX == 125, f"50 + 62 + 13 should be 125, got {IN_STATE_MAX}"
assert "Maximum of 125 multipliers" in rules, \
    "the rules' own in-state maximum changed — re-check nyqp_rules.md §6"
assert "Count US states (50), New York Counties (62) and Canadian provinces (13)" in rules
assert "The first valid New York county logged will count as the multiplier for New York" in rules, \
    "the rule that makes homeStateCountsViaCounty true is gone"
assert "DX counts as QSO points but not multipliers" in rules

# --- Bands: "All FCC allocated amateur frequencies (excluding the 30, 17, and 12
# meter bands)". Only three exclusions, all WARC — so 60 m is included on a
# literal reading, and microwave above 70 cm has nowhere to go in Band. ---
BANDS = ["160m", "80m", "60m", "40m", "20m", "15m", "10m", "6m", "2m", "1.25m", "70cm"]
assert "All FCC allocated amateur frequencies (excluding the 30, 17, and 12 meter bands)" in rules, \
    "the band sentence changed — re-read the source and revisit 60 m"
for warc in ["30m", "17m", "12m"]:
    assert warc not in BANDS
assert "60m" in BANDS, "60 m is included by the literal reading; see nyqp_rules.md §10"
# The sponsor's sample log proves microwave is really in use.
assert "10G" in rules_raw, "the sample Cabrillo no longer shows microwave QSOs"

# --- The rule sentences this file encodes. ---
for quote in [
    "Third Saturday in October",
    "14:00:00 UTC through 01:59:59 UTC",
    "New York stations send signal report and three-letter county abbreviation",
    "Stations outside of New York send signal report plus state or Canadian province",
    "Each complete, non-duplicate Phone contact is worth 1 point per band",
    "Each complete, non-duplicate CW contact is worth 2 points per band",
    "worth 3 points per",
    "You may contact each station once on each band and mode",
    "only two counties at a time may be counted for the same contact",
    "County line exchanges should be logged as two separate QSOs",
    "The total score is the total number of QSO points multiplied by the total number of multipliers",
    "CONTEST: NY-QSO-PARTY",
]:
    assert quote in rules, f"rules text no longer contains: {quote!r}"

# The rules are still the 2025 edition; the 2026 dates come from the formula.
assert "2025 New York QSO Party" in rules and "v1.2 FINAL 2025-10-01" in rules, \
    "the rules PDF is no longer the 2025 v1.2 revision — re-verify and revisit the partial marker"

nyqp = {
    "schemaVersion": 1,
    "id": "nyqp",
    "name": "New York QSO Party",
    # The sponsor publishes this itself, in its own sample Cabrillo header — the
    # first party where Article 1's WA7BNM exception is not needed.
    "cabrilloContest": "NY-QSO-PARTY",
    "homeState": "NY",
    "countyAbbrLength": 3,
    # "All FCC allocated amateur frequencies (excluding the 30, 17, and 12 meter
    # bands)". 60 m is included on that literal reading; microwave above 70 cm
    # cannot be expressed by Band. See notes and nyqp_rules.md §10.
    "validBands": BANDS,
    # Phone 1, CW 2, RTTY/digital 3 — the first party where digital outscores CW.
    "points": {"phone": 1, "cw": 2, "digital": 3},
    # "You may contact each station once on each band and mode, for a maximum of
    # three contacts per station"
    "dupeScope": "bandMode",
    "multipliers": {
        # "Count US states (50), New York Counties (62) and Canadian provinces
        # (13) ... Maximum of 125 multipliers. (DX counts as QSO points but not
        # multipliers.)" 50 + 62 + 13 = 125 exactly.
        "inState": {
            "classes": ["county", "state", "province"],
            # "The first valid New York county logged will count as the
            # multiplier for New York." Stated outright, and required for the
            # sponsor's own 125 to close.
            "homeStateCountsViaCounty": True,
            "countScope": "once",
        },
        # "Count New York counties for a maximum of 62 multipliers."
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
        },
    },
    # No bonus station and no bonus points anywhere in the 17 pages.
    "bonuses": [],
    # 'send signal report and "DX."' — the literal token.
    "dxStyle": "token",
    # Phone, CW and digital are all legal; digital is Mixed-category only, which
    # is an entry-class rule rather than a scoring one.
    "allowedModes": ["phone", "cw", "digital"],
    # "If the portable or mobile station is operating from the intersection of
    # three or more NY counties, only two counties at a time may be counted for
    # the same contact." A stated numeric maximum, which is rare.
    "maxSimultaneousCounties": 2,
    # DC is not mentioned; no alias is invented, and the default token stands.
    # "signal report and three-letter county abbreviation"
    "exchangeIncludesRST": True,
    # An aim rather than a stated limit; shipped on with an open question.
    "outStateWorksHomeStationsOnly": True,
    # "Third Saturday in October", 14:00:00 UTC through 01:59:59 UTC, 12 hours.
    # 17 October 2026 is the third Saturday, and 1400Z = 10 AM EDT holds since
    # DST ends 1 November. Stored with the exclusive 02:00 end instant.
    "schedule": [{"start": "2026-10-17T14:00:00Z", "end": "2026-10-18T02:00:00Z"}],
    "counties": [{"abbr": a, "name": n} for a, n in sorted(counties.items(), key=lambda kv: kv[1])],
    "notes": (
        "verified: partial — rules from the Rochester (NY) DX Association's official PDF "
        "('2025 New York QSO Party', footer 'v1.2 FINAL 2025-10-01'), with the county codes "
        "cross-checked against the sponsor's official CSV, both read verbatim 2026-07-24. This "
        "is the best-documented party in the repo: the PDF carries a county table, a Canadian "
        "multiplier list, and a full Cabrillo specification with sample header and QSO lines - "
        "so the Cabrillo CONTEST value NY-QSO-PARTY comes from THE SPONSOR rather than from "
        "WA7BNM, the first party where that fallback is not needed. "
        "The sponsor's multiplier arithmetic closes exactly and is asserted by the generator: "
        "'Count US states (50), New York Counties (62) and Canadian provinces (13) ... Maximum "
        "of 125 multipliers', and 50 + 62 + 13 = 125. Out-of-state entrants count the 62 "
        "counties. Everything counts ONCE, not per band. DX scores QSO points but is NEVER a "
        "multiplier for either side ('DX counts as QSO points but not multipliers'). NEW YORK "
        "ITSELF IS EARNED VIA A COUNTY, stated outright - 'The first valid New York county "
        "logged will count as the multiplier for New York' - and the 125 total only closes if "
        "it is, since NY stations send counties and the token NY is never received. Canada is "
        "the standard 13, listed twice. "
        "DIGITAL IS LEGAL AND PAYS MOST: phone 1 point, CW 2, RTTY/digital 3 - the first "
        "bundled party where digital outscores CW. All RTTY and digital modes count as one "
        "mode, and digital is permitted in the Mixed entry category only, which is an "
        "entry-class rule rather than a scoring one. "
        "County lines have a STATED numeric maximum of two: 'If the portable or mobile station "
        "is operating from the intersection of three or more NY counties, only two counties at "
        "a time may be counted for the same contact.' The separator is '/' and the sponsor "
        "expects 'County line exchanges should be logged as two separate QSOs', which is "
        "exactly what this app does with a DUT/PUT entry. Only Portable and stationary Mobile "
        "stations may operate a county line; a moving mobile changes county instead, and a New "
        "York station that changes county is a new station for points and multiplier credit. "
        "No bonus station, no bonus points, no final-score multiplier. "
        "ELEVEN VALID BANDS, the widest list of any bundled party: 'All FCC allocated amateur "
        "frequencies (excluding the 30, 17, and 12 meter bands)'. Note two consequences. First, "
        "60 M IS INCLUDED on that literal reading - the rules exclude only the three WARC bands "
        "and 60 m is an FCC amateur allocation - which no other bundled party permits, so treat "
        "it as the sponsor's words rather than as settled convention. Second, KNOWN LIMITATION: "
        "the sponsor's own sample log contains QSOs on 902 MHz, 1.2 GHz and 10 GHz, and this "
        "app's band list stops at 70 cm, so microwave contacts cannot be logged. Recorded "
        "rather than built, as PAQP's 630 m and 2200 m are. "
        "OPEN QUESTIONS (why this is partial): (1) The published rules are the 2025 edition and "
        "no 2026 revision has been posted. The DATE is not in doubt: the formula is printed in "
        "the document's own title block ('Third Saturday in October'), 17 October 2026 is the "
        "third Saturday, and the rules' own parentheticals pin the offset - 1400 UTC = 10 AM "
        "Eastern and 01:59:59 UTC = 9:59:59 PM Eastern, both still true in 2026 since DST ends "
        "1 November. What is unverified is whether any RULE changed for 2026. Re-check nyqp.org "
        "before 17 October 2026 and re-run gen_nyqp.py, whose quoted-sentence assertions fail "
        "loudly if the text moved. (2) No rule states whether stations outside New York may work "
        "only New York stations. The Objective reads 'Work as many New York stations and as many "
        "New York counties as possible', which is an aim rather than a limit, and out-of-state "
        "multipliers are NY counties only. Shipped with the restriction ON, as for NJQP, IAQP, "
        "NHQP, PAQP and SDQP, so a stray non-NY contact is visibly flagged NO CREDIT rather "
        "than silently adding points. Confirm both, and the 60 m reading, with the sponsor "
        "before submitting a log."
    ),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(nyqp, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"nyqp.json: {len(counties)} counties, names from the rules PDF and codes "
      f"cross-checked against the official CSV")
print(f"  in-state ceiling: {US_STATES} states + {len(counties)} counties + "
      f"{PROVINCES} provinces = {IN_STATE_MAX} (rules say 125)")
print(f"  out-of-state ceiling: {len(counties)} counties (rules say 62)")
print(f"  points: phone 1, CW 2, digital 3 — digital outscores CW here")
print(f"  bands: {len(BANDS)} — all but WARC, including 60 m; microwave unloggable")
print(f"  schedule: 1 window, 12 h (1400Z Sat 17 Oct -> 0200Z Sun 18 Oct 2026)")
