#!/usr/bin/env python3
"""Generate Resources/Parties/gaqp.json — the Georgia QSO Party.

Per CONSTITUTION.md Article 2: the county list is parsed, never typed. Georgia
has 159 counties, more than any state but Texas, and the second-largest list in
this app after TQP's 254 — which is exactly the list nobody should be
hand-keying.

Sources (both banked, both first-party, both parsed here):

  gaqp_rules_2026.txt              https://gaqsoparty.com/georgia-qso-party-rules/
  gaqp_home_2026.txt               https://gaqsoparty.com/
  gaqp_counties_2026.tsv           https://gaqsoparty.com/county-list/   (live table)
  gaqp_counties_printable_2017.txt .../images/GQP/GQPCounties.pdf        (2017 PDF)

  All fetched 2026-07-26. See gaqp_rules.md.

THE TWO COUNTY SOURCES ARE PARSED INDEPENDENTLY AND REQUIRED TO AGREE. The PDF
is the county page's own "printer-friendly copy" but is nine years older, so it
is a second opinion and never the authority: if they diverge, this script stops
and a human decides, and the live table is what wins.

THE SPONSOR DOES THE ARITHMETIC FOR US. It states "128 possible multipliers"
for Georgia stations and "318 possible multipliers" for everyone else. Those
are (51 states+DC + 13 provinces) x 2 modes and 159 counties x 2 modes. Both
are asserted below, which verifies the county count and both class lists at
once and is the cheapest check available.

Run:  python3 docs/research/gen_gaqp.py
"""

import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "gaqp.json")


def read(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        s = f.read()
    # The site's WordPress theme uses curly quotes and en dashes throughout;
    # normalise so rule assertions can be written in plain ASCII.
    for a, b in [("’", "'"), ("‘", "'"), ("“", '"'),
                 ("”", '"'), ("–", "-"), ("—", "-"),
                 (" ", " ")]:
        s = s.replace(a, b)
    return s


# ---------------------------------------------------------------- counties (A)
# The live HTML table, banked as TSV. Four columns per row: the sponsor prints
# the list in two side-by-side column pairs, so a row carries two counties.
# 159 is odd, so the final row has one pair and one blank.

rows = []
for line in read("gaqp_counties_2026.tsv").splitlines():
    if line.startswith("#") or not line.strip():
        continue
    rows.append([c.strip() for c in line.split("\t")])

header, data = rows[0], rows[1:]
assert header == ["County", "Abbreviation", "County", "Abbreviation"], header
assert len(data) == 80, f"expected 80 data rows, got {len(data)}"

live = {}
for cells in data:
    assert len(cells) == 4, cells
    for name, abbr in ((cells[0], cells[1]), (cells[2], cells[3])):
        if not name and not abbr:
            continue                      # the odd count's one empty cell pair
        assert name and abbr, cells
        assert abbr not in live, f"duplicate code {abbr}"
        live[abbr] = name

# ---------------------------------------------------------------- counties (B)
# The 2017 printable PDF, via `pdftotext -layout`. Same two-pair layout, but as
# whitespace-aligned text, so pairs are matched by shape rather than position:
# a county name is words, a code is 3-4 capitals.

PAIR = re.compile(r"([A-Z][A-Za-z]*(?: [A-Za-z]+)*?)\s+([A-Z]{3,4})(?=\s|$)")

# Everything before the "====" rule is the provenance header this repo wrote,
# not the sponsor's. Parsing it once produced a phantom county ("ONLY: Used"),
# which is precisely what the cross-check below exists to catch.
body = read("gaqp_counties_printable_2017.txt").split("=" * 72, 1)[1]

printable = {}
for line in body.splitlines():
    if "Abbreviation" in line or "file:///" in line:
        continue                          # the header row and Word's own path
    for name, abbr in PAIR.findall(line.strip()):
        printable[abbr] = name

# ---------------------------------------------------------------- cross-check
# Nine years apart, from the same sponsor, parsed by two different methods.
if live != printable:
    only_live = {k: v for k, v in live.items() if printable.get(k) != v}
    only_pdf = {k: v for k, v in printable.items() if live.get(k) != v}
    raise SystemExit(
        "COUNTY SOURCES DISAGREE - stop and decide by hand.\n"
        f"  live table (2026, authoritative): {only_live}\n"
        f"  printable PDF (2017, advisory):   {only_pdf}"
    )

counties = [{"abbr": a, "name": n} for a, n in sorted(live.items())]

# --------------------------------------------------------------- county facts
assert len(counties) == 159, f"Georgia has 159 counties, parsed {len(counties)}"
assert len({c["name"] for c in counties}) == 159, "county names must be unique"

lengths = sorted({len(c["abbr"]) for c in counties})
assert lengths == [3, 4], lengths
threes = sorted(c["abbr"] for c in counties if len(c["abbr"]) == 3)
assert threes == ["LEE"], f"LEE should be the only 3-letter code, got {threes}"

# THE TRAP: four counties begin "Cha", and the obvious code belongs to the one
# nobody would guess. CHAT is Chattahoochee; Chatham - Savannah, and far better
# known - is CHTM.
assert live["CHAT"] == "Chattahoochee"
assert live["CHTM"] == "Chatham"
assert live["CHGA"] == "Chattooga"
assert live["CHAR"] == "Charlton"

# Two counties named for a Jefferson, which a fuzzy matcher would merge.
assert live["JEFF"] == "Jefferson"
assert live["JFDA"] == "Jeff Davis"

# The only three-way group, separated by a single fourth letter.
assert live["HARA"] == "Haralson"
assert live["HARR"] == "Harris"
assert live["HART"] == "Hart"

# ------------------------------------------------------------------ the rules
rules = read("gaqp_rules_2026.txt")
home = read("gaqp_home_2026.txt")

# Sponsorship and the county count, stated twice.
assert "co-sponsored by the South East Contest Club and Southeastern DX Club" in home
assert "as many of the 159 Georgia counties as possible" in rules

# No digital, said in one sentence.
assert "Digital contacts aren't allowed in the Georgia QSO Party" in rules
assert "No cross mode contacts allowed" in rules

# Points.
assert "Each completed SSB contact counts one point" in rules
assert "Each completed CW contact counts two points" in rules

# The scope asymmetry, which is the rule most likely to be got wrong.
assert "Stations may be worked once per band and mode for QSO Points" in rules
assert "Each multiplier may be counted once per mode. (Not per band)" in rules

# The sponsor's own multiplier arithmetic - the cheapest verification here.
assert "Each USA State and DC, including Georgia (51)" in rules
assert "Each Canadian Province (13)" in rules
assert "DX counts for QSO points only, there are no country multipliers." in rules
assert "128 possible multipliers." in rules
assert "Each Georgia county (159)" in rules
assert "318 possible multipliers." in rules

US_STATES_AND_DC = 51            # 50 states, Georgia among them, plus DC
PROVINCES = 13
MODES = 2                        # "once on CW and once on SSB"
assert (US_STATES_AND_DC + PROVINCES) * MODES == 128, "in-state ceiling"
assert len(counties) * MODES == 318, "out-of-state ceiling"

# Out-of-state credit, stated in both directions.
assert "Amateurs INSIDE the state of Georgia can make contacts with everyone" in rules
assert "Stations outside Georgia may not count contacts with non-Georgia or DX stations." in rules

# The exchange, including the literal DX token.
assert "GEORGIA stations- Send signal report and GA county abbreviation" in rules
assert "NON-GEORGIA US stations- Send signal report and STATE" in rules
assert 'DX- Send signal report and "DX"' in rules

# Cabrillo, printed by the sponsor for logging-program authors.
assert "CONTEST: GA-QSO-PARTY" in rules
assert "QSO: 14000 CW 2016-04-09 1805 KU8E 599 HARR AA3B 599 PA" in rules

# Scoring is a bare product - no power or station factor anywhere.
assert "Final Score -Multiply total QSO points by total multipliers." in rules
assert "bonus" not in rules.lower(), "a bonus rule would need modelling"

# County lines: deferred to MARAC, with a two-county worked example and no cap.
assert "See the County Hunter rules for guidance" in rules
assert "KU8E/HARR/MUSC if operating from the Harris/Muscogee county line" in rules
assert live["HARR"] == "Harris" and live["MUSC"] == "Muscogee"
assert not re.search(r"only (two|three|2|3) count(y|ies)", rules, re.I), \
    "if the sponsor ever states a maximum, maxSimultaneousCounties must follow it"

# Dates: the formula in the rules, the actual dates on the home page.
assert "held annually the 2nd full weekend of April" in rules
assert "1800Z (2:00 pm EDST) Saturday until 0359Z" in rules
assert "1400Z (10:00 am EDST) to 2359Z" in rules
assert "The 2026 Dates were April 11th - April 12th" in home
assert "two 10 hour periods" in home

# Bands are inferred from the suggested-frequency list and nothing else.
assert "Here are the suggested frequencies" in rules
assert "SSB: 1.865, 3.810, 7.190, 14.250, 21.300, 28.450, 50.135." in rules
assert "CW: 1.815, 3.545, 7.045, 14.045, 21.045, 28.045, 50.095." in rules
assert not re.search(r"\b(WARC|60 meters|30 meters|17 meters|12 meters)\b", rules), \
    "the sponsor names no excluded bands - see OPEN QUESTION 1"

NOTES = (
    "verified: partial - rules, dates and county list all from the sponsor's own site "
    "(gaqsoparty.com), read verbatim 2026-07-26. Co-sponsored by the South East Contest "
    "Club and the Southeastern DX Club. 159 counties - more than any state but Texas, and "
    "the second-largest list here after TQP's 254. Two sources for it were parsed "
    "independently and required "
    "to agree - the live HTML county table and the page's own printer-friendly PDF, which "
    "is nine years older and advisory only. THE SPONSOR DOES ITS OWN MULTIPLIER "
    "ARITHMETIC and both totals check out: '128 possible multipliers' is (51 states+DC + "
    "13 provinces) x 2 modes for a Georgia station, and '318 possible multipliers' is 159 "
    "counties x 2 modes for everyone else. WATCH THE SCOPE ASYMMETRY: stations may be "
    "worked once per band AND mode for QSO points, but 'each multiplier may be counted "
    "once per mode. (Not per band)' - so countScope is perMode while dupeScope is "
    "bandMode. DIGITAL IS NOT A LEGAL MODE HERE - 'Digital contacts aren't allowed in the "
    "Georgia QSO Party' - and cross-mode contacts are refused. DX IS WORTH POINTS AND NO "
    "MULTIPLIER for a Georgia entrant: 'DX counts for QSO points only, there are no "
    "country multipliers', which is why dx is absent from the in-state classes while DX "
    "rows still score. Georgia itself is inside the 51 and reaches an in-state log through "
    "a county, so homeStateCountsViaCounty is true; DC is a multiplier in its own right "
    "here, NOT aliased to Maryland - 51 is 50 states plus DC. No bonus points and no power "
    "or station score multiplier: 'Final Score - Multiply total QSO points by total "
    "multipliers.' Twenty hours in two 10-hour legs on the second full weekend of April, "
    "and the sponsor states the 2026 dates outright rather than leaving the formula to be "
    "applied. OPEN QUESTION 1: THE BAND LIST IS INFERRED. The rules give suggested "
    "frequencies (160/80/40/20/15/10/6 m) and never state which bands are legal; WARC and "
    "2 m are neither listed nor forbidden. The cost is bounded - multipliers are counted "
    "per mode, not per band, so no band list can change a score, only which rows the app "
    "accepts. OPEN QUESTION 2: NO STATED MAXIMUM FOR SIMULTANEOUS COUNTIES. The sponsor "
    "defers to MARAC's county-hunter rules and its worked example shows two "
    "(KU8E/HARR/MUSC), so the schema default of 4 ships - the choice that never refuses a "
    "legal exchange mid-contest. Both are re-checked in the late re-verification pass."
)

party = {
    "schemaVersion": 1,
    "id": "gaqp",
    "name": "Georgia QSO Party",
    "cabrilloContest": "GA-QSO-PARTY",
    "homeState": "GA",
    "countyAbbrLength": 4,
    "validBands": ["160m", "80m", "40m", "20m", "15m", "10m", "6m"],
    "points": {"phone": 1, "cw": 2, "digital": 0},
    "dupeScope": "bandMode",
    "multipliers": {
        # "Each USA State and DC, including Georgia (51) / Each Canadian
        # Province (13)" - and pointedly no dx: DX pays points only.
        "inState": {
            "classes": ["state", "province"],
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
    "dxStyle": "token",
    "allowedModes": ["phone", "cw"],
    "maxSimultaneousCounties": 4,
    "exchangeIncludesRST": True,
    "outStateWorksHomeStationsOnly": True,
    "schedule": [
        {"start": "2026-04-11T18:00:00Z", "end": "2026-04-12T04:00:00Z"},
        {"start": "2026-04-12T14:00:00Z", "end": "2026-04-13T00:00:00Z"},
    ],
    "counties": counties,
    "hubSpots": {
        "tableURL": "http://qsopartyhub.com/gaqp-table.php",
        "postURL": "http://qsopartyhub.com/gaqp-spots.php",
    },
    "notes": NOTES,
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(party, f, indent=2, ensure_ascii=False)
    f.write("\n")

collisions = {}
for c in counties:
    collisions.setdefault(c["abbr"][:3], []).append(c["abbr"])
near = sorted(v for v in collisions.values() if len(v) > 1)

print(f"gaqp.json: {len(counties)} counties, second only to TQP's 254")
print(f"  {len(near)} groups of codes that share their first three letters "
      f"(a 4th letter is the only thing separating them):")
for group in near:
    print("    " + ", ".join(f"{a} {live[a]}" for a in group))
print("  LEE is the only 3-letter code; every other is 4")
print("  sponsor's own arithmetic checks: in-state (51+13)x2 = 128, "
      "out-of-state 159x2 = 318")
print("  points: SSB 1, CW 2; DIGITAL IS NOT A LEGAL MODE")
print("  multipliers PER MODE (not per band); DX pays points but no multiplier")
print("  no bonuses, no power multiplier - score is a bare product")
print("  schedule: 2 windows, 10 h each, 20 h total")
print(f"  wrote {os.path.normpath(OUT)}")
