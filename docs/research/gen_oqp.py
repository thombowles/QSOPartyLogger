#!/usr/bin/env python3
"""Generate Resources/Parties/oqp.json — the Ontario QSO Party.

Per CONSTITUTION.md Article 2: the multiplier list is parsed, never typed.

THE SITE ROLLED FORWARD TO 2027 BUT THE RULES DID NOT. The OQP landing page
advertises "The 30th Annual Ontario QSO Party 2027" while rules.htm is still
headed "2026 Ontario QSO Party Rules (revised 01 March 2026)". This script
proves that split rather than assuming it, and it also diffs the 2025 edition
against the 2026 one to confirm every item on the sponsor's own change list -
including the two-hour shift from Saturday to Sunday, which makes ANY pre-2026
source wrong about the contest times.

Sources (all banked):

  oqp_rules_2026.txt      https://www.va3cco.com/oqp/rules.htm        (live = 2026)
  oqp_rules_2025.txt      web.archive.org/web/20260124025618/.../rules.htm
  oqp_index_2027.txt      https://www.va3cco.com/oqp/index.htm        (change log)
  oqp_mults_page.txt      https://www.va3cco.com/oqp/mults.htm
  oqp_multlist_2023.txt   https://www.va3cco.com/oqp/OQPMultList.pdf
  oqp_cabrillo_name.txt   WA7BNM Cabrillo Names (Article 1 exception - header only)

  All fetched 2026-07-26. See oqp_rules.md.

TWO THINGS ARE DELIBERATELY NOT SHIPPED, and both are argued in oqp_rules.md 12:
the five 10-point club stations (they are QSO points, inside the multiplication,
and the nearest schema shape would apply them after it), and the literal "DX"
token (dxStyle prefix is required to count DXCC entities individually, and
isPlausibleDXPrefix rejects "DX" by design).

Run:  python3 docs/research/gen_oqp.py
"""

import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "oqp.json")

APP_PROVINCES = ["AB", "BC", "MB", "NB", "NL", "NT", "NS", "NU", "ON", "PE",
                 "QC", "SK", "YT"]


def read(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        s = f.read()
    for a, b in [("’", "'"), ("‘", "'"), ("“", '"'),
                 ("”", '"'), ("–", "-"), ("—", "-"), (" ", " ")]:
        s = s.replace(a, b)
    return s.split("=" * 72, 1)[-1]


def lines(name):
    return [l.strip() for l in read(name).splitlines() if l.strip()]


# ------------------------------------------------ which edition is on the wire
rules = read("oqp_rules_2026.txt")
flat = re.sub(r"\s+", " ", rules)

assert "2026 Ontario QSO Party Rules (revised 01 March 2026)" in flat, \
    "the live rules page is no longer the 2026 edition - re-read it before building"

# The landing page HAS rolled forward. Asserting both halves is what makes the
# split a recorded fact rather than an assumption.
index = re.sub(r"\s+", " ", read("oqp_index_2027.txt"))
assert "The 30th Annual Ontario QSO Party 2027" in index
assert "1800Z April 17 to 0300Z April 18, 2027" in index

# ------------------------------------- the 2025 -> 2026 diff, item by item
old = lines("oqp_rules_2025.txt")
new = lines("oqp_rules_2026.txt")

assert "2025 Ontario QSO Party Rules (revised 27 Jan 2025)" in " ".join(old)

flat_old = re.sub(r"\s+", " ", " ".join(old))

# Each pair is (what the 2025 rules said, what the 2026 rules say). The sponsor
# lists five changes on its landing page; these are those five, found in the
# text rather than taken on trust.
for was, now in [
    # "Phone QSO's now count the same as CW QSO's (2 points)"
    ("Score 1 QSO point for each station worked on phone",
     "Score 2 QSO points for each station worked on phone"),
    # "addition of VE3RHQ as bonus station"
    ("station VA3RAC.", "stations VA3RAC and VE3RHQ."),
    # "2 hours moved from Saturday to Sunday"
    ("1800Z April 19 to 0500Z April 20", "1800Z April 18 to 0300Z April 19"),
    ("1200Z to 1800Z April 20", "1200Z to 2000Z April 19"),
]:
    assert was in flat_old, f"2025 rules should say: {was}"
    assert now in flat, f"2026 rules should say: {now}"
    assert was not in flat, f"2026 rules should no longer say: {was}"

# "County line proximity definition (250m)" and "Fixed County Line Category added"
assert "250m" not in flat_old and "(within 250m of a county line)" in flat
assert "Fixed Station County Line" not in flat_old
assert ("Fixed Station County Line - A station operating from a fixed location "
        "within 250m of a county line.") in flat

for change in ["Phone QSO's now count the same as CW QSO's (2 points)",
               "of VE3RHQ as bonus station",
               "County line proximity definition (250m)",
               "Fixed County Line Category added.",
               "Adjustment of contest times (2 hours moved from Saturday to Sunday)"]:
    assert change in index, f"the sponsor's own change list should carry: {change}"

# ------------------------------------------------------------- the multipliers
# Three columns: name, 3-letter mult, RAC section. The section is real data the
# schema has no field for, so it is parsed (to prove the row was understood)
# and then dropped.
ROW = re.compile(r"^(.+?)\s{2,}([A-Z]{3})\s{2,}(ONN|ONS|ONE|GH)\s*$")

mults, sections = [], {}
for line in read("oqp_multlist_2023.txt").splitlines():
    if not line.strip() or "Effective" in line:
        continue
    m = ROW.match(line.rstrip())
    assert m, f"unparsed multiplier row: {line!r}"
    name, abbr, section = m.group(1).strip(), m.group(2), m.group(3)
    assert abbr not in sections, f"duplicate code {abbr}"
    mults.append({"abbr": abbr, "name": name})
    sections[abbr] = section

assert "Effective 01Jan2023" in read("oqp_multlist_2023.txt")

mults.sort(key=lambda c: c["abbr"])
assert len(mults) == 50, f"Ontario has 50 multipliers, parsed {len(mults)}"
assert len({c["abbr"] for c in mults}) == 50
assert len({c["name"] for c in mults}) == 50
assert {len(c["abbr"]) for c in mults} == {3}, "uniformly 3 letters"
assert set(sections.values()) == {"ONN", "ONS", "ONE", "GH"}, sorted(set(sections.values()))

by_abbr = {c["abbr"]: c["name"] for c in mults}

# THE TRAP: two adjacent southern-Ontario entities, and the obvious abbreviation
# belongs to the smaller one.
assert by_abbr["HAL"] == "Town of Haldimand", by_abbr.get("HAL")
assert by_abbr["HTN"] == "Halton Regional Municipality", by_abbr.get("HTN")

# A county and the city inside it, both multipliers in their own right.
assert by_abbr["BRA"] == "Brant County"
assert by_abbr["BFD"] == "City of Brantford"

# Three PE? codes, three unrelated places.
assert by_abbr["PED"] == "City of Prince Edward"
assert by_abbr["PEL"] == "Peel Regional Municipality"
assert by_abbr["PER"] == "Perth County"

assert by_abbr["NOR"] == "Northumberland County"
assert by_abbr["NFK"] == "Town of Norfolk"
assert by_abbr["MAN"] == "Manitoulin District", "not Manitoba, which is MB"

# The list is deliberately not all counties, and the sponsor says why.
assert ("single tier municipalities" in re.sub(r"\s+", " ", read("oqp_mults_page.txt")))
assert by_abbr["SDG"] == "United Counties of Stormont, Dundas & Glengarry"
kinds = {"County": 0, "District": 0, "City of": 0, "Town of": 0,
         "Regional Municipality": 0, "United Counties": 0}
for name in by_abbr.values():
    for k in kinds:
        if k in name:
            kinds[k] += 1
assert all(v > 0 for v in kinds.values()), kinds

# ------------------------------------------------------------- the rules, read
assert ("For 2026, the contest periods are 1800Z April 18 to 0300Z April 19, and "
        "1200Z to 2000Z April 19.") in flat
assert "Held on the third full weekend of April each Year." in flat

assert "All Bands 160-2 meters with the exception of the WARC bands." in flat
# OPEN QUESTION 1: 60 m sits inside "160-2 meters" and is not strictly a WARC
# band, so the sentence above does not settle it. What settles the shipped list
# is that the sponsor's own suggested frequencies name every band it expects
# activity on, and 5 MHz is not among them.
assert not re.search(r"\b60\s*m(eters?)?\b", flat), \
    "the sponsor now mentions 60 m - resolve OPEN QUESTION 1 from its own words"
suggested = flat.split("Suggested Frequencies")[1].split("Suggested Manner")[0]
assert "5." not in suggested, "no 5 MHz frequency is suggested"
for mhz in ["1.870", "3.735", "7.070", "14.130", "21.260", "28.360",
            "50.130", "144.205"]:
    assert mhz in suggested, f"expected a suggested frequency at {mhz}"

assert "You may work a station TWICE per band: once on phone and once on CW." in flat
assert "Operators can not use repeaters" in flat
assert "digital" not in flat.lower() and "RTTY" not in flat, "phone and CW only"

assert "Score 2 QSO points for each station worked on phone per band." in flat
assert "Score 2 QSO points for each station worked on CW per band." in flat

# The five 10-point stations - parsed so the limitation names the right calls.
club = re.search(r"Score 10 QSO points for each contact made with (.+?)\.", flat)
assert club, "the 10-point club-station rule moved"
CLUB_CALLS = re.findall(r"\b(V[AE]3[A-Z]{3})\b", club.group(1))
assert CLUB_CALLS == ["VA3CCO", "VE3CCO", "VE3ODX", "VA3RAC", "VE3RHQ"], CLUB_CALLS

assert ("Stations claim 1 multiplier point for each Ontario county worked on each band."
        in flat)
assert ("Ontario stations also claim 1 multiplier point for each Canadian "
        "province/territory, U.S. state (plus District of Columbia) and DXCC country "
        "worked on each band.") in flat
assert "Total Score = Total QSO points x total multiplier points." in flat
assert ("Mobile/Rover Score = (total QSO points x total multiplier points) + bonus."
        in flat)

assert "Ontario stations work everyone. Non-Ontario stations work Ontario stations only."\
    in flat
assert ("Mobile/Rover stations add 300 bonus points for each Ontario multiplier "
        "activated.") in flat
assert ("a station must make at least three contacts with three different stations from "
        "the multiplier area.") in flat

assert ("a separate QSO and complete exchange must be made and logged for each county "
        "worked.") in flat

# The exchange, and the sentence that makes the dxStyle choice a trade-off.
assert "Ontario stations send signal report and their county abbreviation" in flat
assert ("Non-Ontario stations send signal report and province, state, or DXCC country "
        "or abbreviation.") in flat
assert 'the abbreviation "DX" is also acceptable' in flat, \
    "this is the form dxStyle 'prefix' cannot accept - see KNOWN LIMITATION 2"

# Power categorises but does not scale, and nothing else pays a bonus.
assert "Single Operator QRP Mixed mode (5 watts and under)" in flat

# THE SPONSOR'S OWN TYPOS, asserted so a correction is noticed.
assert "for 2025 that will be May 18, 2026." in flat, \
    "the log deadline says 2025 and means 2026"
assert "A seperate QSO and complete exchange must be logged for each county." in flat

# Cabrillo: never named, though a converter is linked.
assert "CONTEST:" not in flat
assert "b4h.net/cabforms/onqp_cab3.php" in flat
name = read("oqp_cabrillo_name.txt")
assert "Ontario QSO Party" in name and "ON-QSO-PARTY" in name

NOTES = (
    "verified: partial - rules from Contest Club Ontario's own site, read verbatim "
    "2026-07-26, and the multiplier list from its OQPMultList.pdf ('Effective "
    "01Jan2023'). THE SITE ROLLED FORWARD TO 2027 BUT THE RULES DID NOT: the OQP landing "
    "page advertises 'The 30th Annual Ontario QSO Party 2027' while rules.htm is still "
    "headed '2026 Ontario QSO Party Rules (revised 01 March 2026)' and is byte-identical "
    "to the Wayback snapshot of 2026-05-04. The generator asserts both halves of that "
    "split. IT ALSO DIFFS THE 2025 EDITION AGAINST THE 2026 ONE and confirms every item "
    "on the sponsor's own change list: phone went from 1 point to 2, VE3RHQ joined the "
    "bonus stations, a 250 m county-line proximity definition and a Fixed Station County "
    "Line category were added, and TWO HOURS MOVED FROM SATURDAY NIGHT TO SUNDAY - so ANY "
    "PRE-2026 SOURCE IS WRONG ABOUT BOTH THE TIMES AND THE PHONE POINTS. Seventeen hours "
    "in two legs, with the sponsor printing the 2026 instants outright. FLAT 2 POINTS for "
    "phone and CW alike. Multipliers count PER BAND, not per mode, even though a station "
    "is worked twice per band. Ontario stations claim the 50 Ontario multipliers directly, "
    "so homeStateCountsViaCounty is false and ON is absent from the provinces they count. "
    "THE 50 ARE NOT ALL COUNTIES - the sponsor explains that former counties have become "
    "single-tier municipalities, so the list mixes counties, districts, regional "
    "municipalities, cities, towns and united counties. WATCH HAL: it is the Town of "
    "HALDIMAND, not Halton, which is HTN - two adjacent southern-Ontario entities where "
    "the obvious abbreviation belongs to the smaller one. County lines need a separate QSO "
    "per county, so maxSimultaneousCounties is 1. KNOWN LIMITATION 1 - THE FIVE 10-POINT "
    "CLUB STATIONS ARE NOT MODELLED. The sponsor pays 10 QSO POINTS for working VA3CCO, "
    "VE3CCO, VE3ODX, VA3RAC and VE3RHQ, and QSO points sit INSIDE the multiplication. The "
    "nearest schema shape, a workStation bonus, is added AFTER multiplication - so an "
    "entrant with 60 multipliers would be credited 8 points where the sponsor credits 480. "
    "A wrong number that looks deliberate is harder to notice than a missing one, so "
    "nothing ships for these five and their QSOs score the ordinary 2 points. Second user "
    "of the points-table gap North Carolina opened: NCQP wants points by county, Ontario "
    "wants points by callsign, and both want pointsTable to consult more than the mode. "
    "KNOWN LIMITATION 2 - THE LITERAL 'DX' CANNOT BE LOGGED. The sponsor counts DXCC "
    "countries individually and asks for 'province, state, or DXCC country or "
    "abbreviation', but adds that when an Ontario station logs it 'the abbreviation \"DX\" "
    "is also acceptable'. dxStyle 'token' would accept DX while collapsing every entity "
    "into one multiplier per band AND leaving an Ontario station unable to log DL at all; "
    "'prefix' counts entities individually and accepts DL, but isPlausibleDXPrefix rejects "
    "the literal DX by design. PREFIX SHIPS, because it gets the scoring right and accepts "
    "the primary form; the rare secondary form is the casualty. This is the exact mirror "
    "of North Dakota, where the same two settings traded places and token won. KNOWN "
    "LIMITATION 3 - the activation bonus requires 'three contacts with three different "
    "stations' and activatedCountyCount counts three QSOs, which three bands' worth of one "
    "station would satisfy; the overpayment is bounded at 300 points per multiplier area. "
    "The Cabrillo CONTEST header is the one thing not from the sponsor - the rules ask for "
    "Cabrillo and link a converter without ever naming the header - so ON-QSO-PARTY comes "
    "from WA7BNM's Cabrillo Names table under Article 1's exception. SPONSOR TYPOS SHIPPED "
    "AS PRINTED: a log deadline reading 'for 2025 that will be May 18, 2026', and "
    "'seperate' in the Fixed Station County Line paragraph. OPEN QUESTION 1: IS 60 M "
    "LEGAL? 'All Bands 160-2 meters with the exception of the WARC bands' puts 60 m inside "
    "the range and 60 m is not strictly WARC, but it is channelised in Canada, absent from "
    "the sponsor's suggested frequencies and universally excluded from contests. Eight "
    "bands ship without it; North Dakota's wording has the identical ambiguity and was "
    "resolved the same way."
)

party = {
    "schemaVersion": 1,
    "id": "oqp",
    "name": "Ontario QSO Party",
    "cabrilloContest": "ON-QSO-PARTY",
    "homeState": "ON",
    "countyAbbrLength": 3,
    "validBands": ["160m", "80m", "40m", "20m", "15m", "10m", "6m", "2m"],
    "points": {"phone": 2, "cw": 2, "digital": 0},
    "dupeScope": "bandMode",
    "multipliers": {
        # "worked on each band" - the band is the axis, not the mode.
        "inState": {
            "classes": ["county", "state", "province", "dx"],
            "homeStateCountsViaCounty": False,
            "countScope": "perBand",
        },
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "perBand",
        },
    },
    "bonuses": [
        {"type": "activatedCountyCount", "minQSOs": 3, "points": 300},
    ],
    "dxStyle": "prefix",
    "allowedModes": ["phone", "cw"],
    "maxSimultaneousCounties": 1,
    "provinces": [p for p in APP_PROVINCES if p != "ON"],
    "exchangeIncludesRST": True,
    "outStateWorksHomeStationsOnly": True,
    "schedule": [
        {"start": "2026-04-18T18:00:00Z", "end": "2026-04-19T03:00:00Z"},
        {"start": "2026-04-19T12:00:00Z", "end": "2026-04-19T20:00:00Z"},
    ],
    "counties": mults,
    # THE HUB CALLS IT ONQP, NOT OQP. oqp-table.php 404s; onqp-table.php serves
    # a real table. The party id follows the sponsor, which calls itself OQP
    # throughout; the URL follows the hub. CQP already proved the prefix is not
    # derivable from the id.
    "hubSpots": {
        "tableURL": "http://qsopartyhub.com/onqp-table.php",
        "postURL": "http://qsopartyhub.com/onqp-spots.php",
    },
    "notes": NOTES,
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(party, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"oqp.json: {len(mults)} Ontario multipliers, uniform 3-letter codes")
print("  THE LIVE RULES ARE STILL THE 2026 EDITION; only the landing page is 2027")
print("  the 2025 -> 2026 diff confirms all five of the sponsor's stated changes,")
print("    including 2 hours moved from Saturday to Sunday and phone 1 -> 2 points")
print("  HAL is the Town of HALDIMAND - Halton is HTN")
print(f"  the list mixes {', '.join(f'{k} x{v}' for k, v in kinds.items())}")
print("  points: flat 2 for phone and CW; multipliers PER BAND, not per mode")
print(f"  NOT shipped: 10 QSO points for {', '.join(CLUB_CALLS)} (see notes),")
print("    and the literal 'DX' token, which dxStyle prefix cannot accept")
print("  bonuses: 300 per activated multiplier area with 3+ QSOs")
print("  hub URLs use ONQP, not OQP - oqp-table.php 404s")
print("  schedule: 2 windows, 9 h + 8 h = 17 h")
print(f"  wrote {os.path.normpath(OUT)}")
