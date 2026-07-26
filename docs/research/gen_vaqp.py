#!/usr/bin/env python3
"""Generate vaqp.json from the Sterling Park Amateur Radio Club's own documents.

Sources (committed alongside this script, so the run is reproducible):
  vaqp_rules_2026.txt — pdftotext -layout of the sponsor's "2026 Virginia QSO
                        Party Rules". THE AUTHORITY.
  vaqp_counties.txt   — the sponsor's entity list, "95 Counties and 38
                        Independent Cities with 3 Character Abbreviations -
                        Cities marked with an '*'"
  vaqp_rules.md       — full rules research; all fetched 2026-07-26

THIS IS THE FIRST PARTY WHOSE ENTITY LIST IS NOT JUST COUNTIES, and the first
where NAMES ARE NOT UNIQUE: Fairfax, Franklin, Richmond and Roanoke each exist
twice, once as a county and once as an independent city. Only the abbreviations
are unique, which is what PartyDefinition.validate() actually requires.

Cities are rendered "Name (City)". That is this repo's only transformation of a
sponsor's printed name and it is deliberate: it renders the sponsor's own
asterisk as readable text, makes all 133 display names unique, and stops an
operator picking FRA when they meant FRX. Note that MOST city codes end in X but
that is NOT a reliable test - FFX is Fairfax COUNTY. The asterisk is the
authority, and the asterisk is what this script reads.

WHAT DELIBERATELY DOES NOT SHIP - see vaqp_rules.md section 13:
  * 3 points per contact with a Virginia Mobile, Expedition or Rover. The worked
    station's category is not in the exchange, only in its callsign suffix by
    convention, and PointsTable is keyed by mode.
  * the 50-point bonus stations, which the rules do not name - they are published
    on the web site near the event, as with PAQP's 2026 station.

Usage:  python3 gen_vaqp.py        (run from docs/research/)
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "vaqp.json")
RULES = os.path.join(HERE, "vaqp_rules_2026.txt")
ENTITIES = os.path.join(HERE, "vaqp_counties.txt")


def read(path):
    s = open(path, encoding="utf-8", errors="replace").read()
    for a, b in [("’", "'"), ("‘", "'"), ("“", '"'), ("”", '"'),
                 ("–", "-"), ("—", "-"), (" ", " ")]:
        s = s.replace(a, b)
    return s


rules = re.sub(r"\s+", " ", read(RULES))
entities_txt = read(ENTITIES)

# --- Entities. The HTML table flattens to a stream of name fragments, "*"
# markers and 3-letter codes; a code terminates the entity that precedes it. ---
body = entities_txt.split('Cities marked with an "*"')[1]
tokens = [line.strip() for line in body.splitlines() if line.strip()]

entities = {}          # abbr -> (printed name, is_city)
order = []
name_parts, is_city = [], False
for token in tokens:
    if token == "*":
        is_city = True
        continue
    if token.startswith("* "):
        is_city = True
        token = token[2:].strip()
    if re.fullmatch(r"[A-Z]{3}", token) and name_parts:
        abbr = token
        name = " ".join(" ".join(name_parts).split())
        if abbr in entities:
            if entities[abbr] != (name, is_city):
                sys.exit(f"VAQP conflicting entries for {abbr}: "
                         f"{entities[abbr]!r} vs {(name, is_city)!r}")
        else:
            entities[abbr] = (name, is_city)
            order.append(abbr)
        name_parts, is_city = [], False
    else:
        name_parts.append(token)

cities = [a for a in entities if entities[a][1]]
counties = [a for a in entities if not entities[a][1]]

assert len(entities) == 133, f"expected 133 VA entities, got {len(entities)}"
assert len(counties) == 95, f"expected 95 counties, got {len(counties)}"
assert len(cities) == 38, f"expected 38 independent cities, got {len(cities)}"
assert {len(a) for a in entities} == {3}, "VA codes are uniformly 3 characters"
assert "95 Counties and 38 Independent Cities" in re.sub(r"\s+", " ", entities_txt)
assert "95 Virginia Counties and 38 Virginia Independent Cities" in rules, \
    "the 2026 rules' own counts no longer match the entity list"

# THE FOUR SHARED NAMES. This is the party's defining feature: names are NOT
# unique, only codes are. Assert both members of each pair.
SHARED = {"Fairfax": ("FFX", "FXX"), "Franklin": ("FRA", "FRX"),
          "Richmond": ("RIC", "RIX"), "Roanoke": ("ROA", "ROX")}
for name, (county_code, city_code) in SHARED.items():
    assert entities.get(county_code) == (name, False), \
        f"{county_code} should be {name} COUNTY, got {entities.get(county_code)!r}"
    assert entities.get(city_code) == (name, True), \
        f"{city_code} should be {name} CITY, got {entities.get(city_code)!r}"
printed = [n for n, _ in entities.values()]
assert len(set(printed)) == 133 - len(SHARED), \
    f"expected exactly {len(SHARED)} duplicated printed names, got {133 - len(set(printed))}"

# "Ends in X" is the sponsor's convention for cities but is NOT a reliable test -
# FFX is Fairfax COUNTY. Pinned so nobody replaces the asterisk parse with it.
assert entities["FFX"] == ("Fairfax", False), "FFX is Fairfax COUNTY, despite the X"
assert sum(1 for a in counties if a.endswith("X")) >= 1, \
    "at least one COUNTY code ends in X - do not use the letter as a city test"

for abbr, name in [
    ("CCY", "Charles City"), ("KQN", "King Queen"), ("KGE", "King George"),
    ("KWM", "King William"), ("IOW", "Isle of Wight"), ("ACC", "Accomack"),
    ("MPX", "Manassas Park"), ("COX", "Colonial Heights"), ("BVX", "Buena Vista"),
    ("VBX", "Virginia Beach"), ("NNX", "Newport News"), ("CHX", "Charlottesville"),
]:
    assert entities.get(abbr, (None, None))[0] == name, \
        f"{abbr} should be {name!r}, got {entities.get(abbr)!r}"


def display(abbr):
    name, city = entities[abbr]
    return f"{name} (City)" if city else name


rendered = {a: display(a) for a in entities}
assert len(set(rendered.values())) == 133, "rendered display names must be unique"
assert sum(1 for v in rendered.values() if v.endswith(" (City)")) == 38
assert rendered["FRA"] == "Franklin" and rendered["FRX"] == "Franklin (City)"

# --- Bands: "160 meters and up, except no WARC", with the suggested-frequency
# list fixing the top end at 70 cm. Same ten as WIQP. ---
BANDS = ["160m", "80m", "40m", "20m", "15m", "10m", "6m", "2m", "1.25m", "70cm"]
assert "160 meters and up, except no WARC band QSO's permitted" in rules, \
    "the band sentence changed - re-derive from the suggested frequencies"
# NOTE the rules PDF is TWO-COLUMN, so pdftotext interleaves the columns and a
# quotation may be split by unrelated text from the other column. Assert the
# fragments that do not cross a column break.
assert "VHF - 50.130, 144.200 (CW & SSB), 146.580 and" in rules
assert "223.50 MHz." in rules
assert "UHF - 446.00 MHz" in rules
for excluded in ["60m", "30m", "17m", "12m"]:
    assert excluded not in BANDS, f"{excluded} is a WARC band or unlisted"

# --- The rule sentences this file encodes. ---
#
# NOTE THE RULES PDF IS TWO-COLUMN, and pdftotext -layout interleaves the columns
# once whitespace is normalised - "Saturday, 21 March 2026 ... 1200 UTC - Band
# Categories 2400 UTC." So every quotation below is a fragment short enough to
# sit inside a single column line. Longer quotations belong in vaqp_rules.md,
# which cites them from the laid-out text.
for quote in [
    # Dates - each half separately, because a column break falls between them
    "Saturday, 21 March 2026, 1400 UTC - Sunday, 22 March, 0400 UTC and Sunday, 22 March,",
    "Saturday 10 AM - 12 Midnight and",
    "Sunday 8 AM - 8 PM Virginia local time",
    # Exchange: a QSO NUMBER and no report
    "Exchange QSO number and QTH",
    "sequential QSO",
    # Points, including the 3-point rule that does NOT ship
    "QSO's count 1 point per Phone, 2 points per CW, 2 points per digital mode",
    "points per contact made with a Virginia Mobile,",
    # Multipliers
    "Multipliers are only counted once",
    "U. S. States (except",
    "extra DX multiplier for U.S. (including Alaska and Hawaii), Virginia, and Canada",
    "Outside of Virginia station multipliers are the total number of Virginia Counties (95)",
    "may claim it as a multiplier,",
    # Bonuses
    "bonus of 100 additional points for each Virginia",
    "one-time bonus of 50 points. Bonus",
    "stations are listed on the VaQP Web Site",
    # County lines: ONE multiplier, not two
    "Stations on County or Independent City",
    "lines count as one QSO and one County/Independent",
    # Dupes and credit
    "stations once per band/mode",
    "Virginia stations work all stations. Out-of-State",
    "stations work Virginia stations only",
    "No cross-mode or repeater QSO's",
    # Scoring
    "Final score is the number of QSO Points multiplied by",
]:
    assert quote in rules, f"the 2026 rules no longer contain: {quote!r}"

assert "2026 Virginia QSO Party Rules" in rules, \
    "this is not the 2026 edition - re-verify every rule before shipping it"

# The two rules that deliberately do not ship.
assert "points per contact made with a Virginia Mobile," in rules and "Expedition, or Rover." in rules, \
    "the 3-point mobile rule changed - revisit KNOWN LIMITATION 1"
assert "must use appropriate suffix in call sign" in rules, \
    "the callsign-suffix convention is gone - it is the only hint a fix could use"
assert "Satellite contacts allowed" in rules

vaqp = {
    "schemaVersion": 1,
    "id": "vaqp",
    "name": "Virginia QSO Party",
    # The rules print no CONTEST: value and give no Cabrillo example;
    # WA7BNM registry (Article 1's codified exception).
    "cabrilloContest": "VA-QSO-PARTY",
    "homeState": "VA",
    "countyAbbrLength": 3,
    # "160 meters and up, except no WARC band QSO's permitted", with the
    # suggested-frequency list fixing the top at 70 cm. Same ten as WIQP.
    "validBands": BANDS,
    # "1 point per Phone, 2 points per CW, 2 points per digital mode". The
    # 3-point rule for VA mobiles/expeditions/rovers cannot be expressed; see
    # notes, KNOWN LIMITATION 1.
    "points": {"phone": 1, "cw": 2, "digital": 2},
    # "Work fixed stations once per band/mode."
    "dupeScope": "bandMode",
    "multipliers": {
        # "the total number of Virginia counties, Virginia independent cities,
        # U.S. States (except Virginia), Canadian Provinces, and DX entities."
        "inState": {
            "classes": ["county", "state", "province", "dx"],
            # "U. S. States (EXCEPT VIRGINIA)", and again "No extra DX
            # multiplier for ... Virginia". Stated outright, twice.
            "homeStateCountsViaCounty": False,
            # "Multipliers are only counted once, i.e., contacting the same ...
            # using a different band or mode counts only as a new QSO."
            "countScope": "once",
        },
        # "the total number of Virginia Counties (95) and Independent Cities
        # (38) worked" - 133.
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
        },
    },
    # "Virginia Mobile, Rover, and Expedition stations receive a bonus of 100
    # additional points for each Virginia County/Independent City from which they
    # log a valid QSO" - "a valid QSO" is a threshold of one.
    # The 50-point bonus stations are NOT named in the rules; none ships.
    "bonuses": [
        {"type": "activatedCountyCount", "minQSOs": 1, "points": 100},
    ],
    # 'State, Province or "DX" for others' - the literal token.
    "dxStyle": "token",
    "allowedModes": ["phone", "cw", "digital"],
    # "Stations on County or Independent City lines count as ONE QSO and ONE
    # County/Independent City multiplier" - line operation is permitted but pays
    # for one, so the operator picks which.
    "maxSimultaneousCounties": 1,
    # DC is never mentioned; it stays its own state-class token.
    # "Exchange QSO number and QTH" - a serial, and no signal report anywhere.
    "exchangeIncludesRST": False,
    "exchangeIncludesSerial": True,
    # "Out-of-State stations work Virginia stations only."
    "outStateWorksHomeStationsOnly": True,
    # Two windows, 14 h + 12 h = 26 h. Round instants; all four local anchors
    # land under EDT (US daylight time began 8 March 2026).
    "schedule": [
        {"start": "2026-03-21T14:00:00Z", "end": "2026-03-22T04:00:00Z"},
        {"start": "2026-03-22T12:00:00Z", "end": "2026-03-23T00:00:00Z"},
    ],
    "counties": [{"abbr": a, "name": rendered[a]}
                 for a in sorted(entities, key=lambda a: rendered[a])],
    "hubSpots": {
        "tableURL": "http://qsopartyhub.com/vaqp-table.php",
        "postURL": "http://qsopartyhub.com/vaqp-spots.php",
    },
    "notes": (
        "verified: partial - rules from the Sterling Park Amateur Radio Club's official '2026 "
        "Virginia QSO Party Rules' PDF and the sponsor's own entity list, both read verbatim "
        "2026-07-26. Contact vqp@verizon.net; logs by 15 April. "
        "THIS IS THE FIRST BUNDLED PARTY WHOSE ENTITIES ARE NOT ALL COUNTIES: 95 counties AND 38 "
        "INDEPENDENT CITIES, 133 in all, which is Virginia's unique arrangement. FOUR NAMES APPEAR "
        "TWICE, once as a county and once as a city - Fairfax (FFX county, FXX city), Franklin "
        "(FRA/FRX), Richmond (RIC/RIX) and Roanoke (ROA/ROX) - so the NAMES ARE NOT UNIQUE here "
        "and only the codes are. Cities are shown as 'Name (City)', which renders the sponsor's "
        "own asterisk as readable text and stops you picking FRA when you meant FRX. Most city "
        "codes end in X, but that is the sponsor's convention rather than a rule and it is NOT "
        "safe to rely on: FFX is Fairfax COUNTY. "
        "Twenty-six hours in two windows: 1400Z Saturday 21 March to 0400Z Sunday, then 1200Z to "
        "2400Z Sunday 22 March 2026 - the longest total of any bundled party except Vermont's 48. "
        "Round instants, and all four local anchors land exactly under EDT. "
        "THE EXCHANGE IS A QSO NUMBER AND A LOCATION, WITH NO SIGNAL REPORT - the third party to "
        "send a serial after CQP and PAQP, and no report appears anywhere in the rules. Virginia "
        "stations send a county or independent city; everyone else sends a state, a province, or "
        "the literal DX. Phone 1 point, CW 2, digital 2. Multipliers count ONCE overall - not per "
        "band, not per mode. Virginia stations count the 133 counties and cities plus the states "
        "EXCEPT VIRGINIA plus provinces plus DX entities; everyone else counts the 133. Virginia "
        "itself is explicitly excluded, stated twice. Alaska and Hawaii are states, not DX. DC is "
        "never mentioned and stays its own multiplier. Ten bands, 160 m and up excluding WARC, "
        "derived from the suggested-frequency list, which reaches 223.50 MHz and 446.00 MHz - note "
        "those are the very frequencies Wisconsin's rules tell operators to avoid, so the two "
        "sponsors' conventions genuinely differ. "
        "COUNTY-LINE OPERATION IS PERMITTED BUT PAYS FOR ONE: 'Stations on County or Independent "
        "City lines count as one QSO and one County/Independent City multiplier.' That is neither "
        "of the usual shapes - it is not forbidden as in Alabama and Wisconsin, and it does not "
        "pay per county as in Iowa and Oklahoma - so a two-entity entry is rejected here and the "
        "operator picks which one to claim. Virginia mobiles, rovers and expeditions earn 100 "
        "points for each county or city they log a valid QSO from, which is modelled. "
        "KNOWN LIMITATION 1 - CONTACTS WITH VIRGINIA MOBILES, EXPEDITIONS AND ROVERS ARE WORTH 3 "
        "POINTS AND THIS APP PAYS 1 OR 2. The rule is 'QSO's count 1 point per Phone, 2 points per "
        "CW, 2 points per digital mode, and 3 POINTS PER CONTACT MADE WITH A VIRGINIA MOBILE, "
        "EXPEDITION, OR ROVER' - and the worked station's category is NOT part of the exchange. "
        "The only hint available while logging is the sponsor's convention that 'Mobile, Rover, "
        "and Expedition stations must use appropriate suffix in call sign', which is a convention "
        "and not a rule. In a party with 133 entities most of the multipliers come from mobiles, "
        "so THIS UNDER-CREDITS ALMOST EVERY SERIOUS ENTRANT. TO CORRECT BY HAND: add 2 points for "
        "each phone QSO and 1 for each CW or digital QSO made with a /M, /R or expedition station. "
        "KNOWN LIMITATION 2 - THE BONUS STATIONS ARE NOT SHIPPED. 'A QSO with each different VA "
        "QSO Party Bonus Station gives a one-time bonus of 50 points. Bonus stations are listed on "
        "the VaQP Web Site' - and the rules do not name them, so none can be encoded. Check the "
        "VaQP site before the contest and add 50 points per distinct bonus station worked. This is "
        "the same call PAQP's unannounced 2026 station got. KNOWN LIMITATION 3 - Virginia mobiles, "
        "rovers and expeditions may also claim a county or city as a MULTIPLIER when they work ten "
        "or more different stations from it 'if not otherwise worked'; this app has no "
        "self-activation multiplier, so an in-state roving entrant is short by that count. "
        "Out-of-state entrants are unaffected. Satellite contacts are allowed and this app has no "
        "concept of them, though a satellite QSO still lands on a band it knows. "
        "Cabrillo CONTEST value VA-QSO-PARTY per the WA7BNM registry - the rules print no header "
        "token and give no Cabrillo example. "
        "OPEN QUESTIONS (why this is partial): (1) and (2) above change the score for ordinary "
        "entrants - the 3-point mobile rule especially - and (3) affects in-state rovers. All "
        "three are missing app features rather than rules in doubt. Confirm the bonus-station list "
        "at the VaQP web site before submitting."
    ),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(vaqp, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"vaqp.json: {len(entities)} entities = {len(counties)} counties + {len(cities)} cities")
print(f"  FOUR names appear twice: Fairfax, Franklin, Richmond, Roanoke (county + city)")
print(f"  cities rendered 'Name (City)'; FFX is Fairfax COUNTY despite the X")
print(f"  exchange: QSO NUMBER + location, NO signal report")
print(f"  multipliers once overall; Virginia itself explicitly excluded")
print(f"  county lines pay ONE multiplier - neither forbidden nor per-county")
print(f"  bands: {len(BANDS)}; schedule: 2 windows, 14 h + 12 h = 26 h")
print(f"  NOT shipped: 3-point mobile contacts, the unnamed 50-point bonus stations")
