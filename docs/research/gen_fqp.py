#!/usr/bin/env python3
"""Generate Resources/Parties/fqp.json — the Florida QSO Party.

Per CONSTITUTION.md Article 2: the county list is parsed, never typed, and here
it is parsed TWICE - from the live HTML table and from the sponsor's own
printable PDF - with the two required to agree on all 67.

THE SPONSOR PRINTS ITS OWN CABRILLO HEADER, and it is not the one anybody would
guess: CONTEST: FCG-FQP, not FL-QSO-PARTY. It comes from the sponsor's own
Cabrillo specification, so no Article 1 exception is needed - the first party in
six to manage that.

Sources (all banked):

  fqp_rules_2026.txt         https://floridaqsoparty.org/rules/
  fqp_counties_2026.tsv      https://floridaqsoparty.org/counties/counties-list/
  fqp_counties_pdf.txt       https://www.floridaqsoparty.org/files/countabb.pdf
  fqp_cabrillo_spec.txt      .../uploads/Cabrillo-Specification-V3-FQP.pdf
  fqp_spelling_bee_2026.txt  https://floridaqsoparty.org/fqp-2026-special-calls/

  All fetched 2026-07-26. See fqp_rules.md.

FOUR BANDS - the narrowest list in the app - and the sponsor's own arithmetic
proves it: "Stations may be worked once per mode per band for a total of 8
maximum QSOs." Four bands times two modes is eight.

Run:  python3 docs/research/gen_fqp.py
"""

import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "fqp.json")


def read(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        s = f.read()
    for a, b in [("’", "'"), ("‘", "'"), ("“", '"'), ("”", '"'),
                 ("–", "-"), ("—", "-"), (" ", " "), ("×", "x")]:
        s = s.replace(a, b)
    return s.split("=" * 72, 1)[-1]


# ------------------------------------------------------------ counties (A) HTML
rows = []
for line in read("fqp_counties_2026.tsv").splitlines():
    if line.startswith("#") or not line.strip():
        continue
    rows.append([c.strip() for c in line.split("\t")])

live = {}
for cells in rows:
    # Three county/abbreviation pairs per row, with an EMPTY SEPARATOR CELL
    # between them - so the stride is 3, not 2. Reading it as 2 silently drops
    # the second and third columns of every row.
    for i in range(0, len(cells) - 1, 3):
        name, abbr = cells[i], cells[i + 1]
        if not name and not abbr:
            continue
        if name.upper() == "COUNTY" or not re.fullmatch(r"[A-Z]{3}", abbr):
            continue
        assert abbr not in live, f"duplicate code {abbr}"
        live[abbr] = name

# ------------------------------------------------------------- counties (B) PDF
# Two columns of "ABC  COUNTY NAME", so a code is followed by its name here -
# the opposite order from the HTML table, which is why this is a real check.
PAIR = re.compile(r"([A-Z]{3})\s{2,}([A-Z][A-Z.\- ]+?)(?=\s{2,}[A-Z]{3}\s|$)")
pdf = {}
for line in read("fqp_counties_pdf.txt").splitlines():
    if "Abbreviations" in line or not line.strip():
        continue
    for abbr, name in PAIR.findall(line.rstrip()):
        pdf[abbr] = name.strip()

# The two copies differ typographically on exactly one county: the live table
# prints "MIAMI-DADE" and the PDF "MIAMI - DADE". Compared with spacing around
# hyphens normalised, so a real disagreement is not masked by a real one.
def key(n):
    return re.sub(r"\s*-\s*", "-", n.strip())


if {a: key(n) for a, n in live.items()} != {a: key(n) for a, n in pdf.items()}:
    live, pdf = {a: key(n) for a, n in live.items()}, {a: key(n) for a, n in pdf.items()}
    raise SystemExit(
        "COUNTY SOURCES DISAGREE - stop and decide by hand.\n"
        f"  only in the live table: { {k: v for k, v in live.items() if pdf.get(k) != v} }\n"
        f"  only in the PDF:        { {k: v for k, v in pdf.items() if live.get(k) != v} }")

# The live page's spelling ships - it is the one that says "Please do not
# deviate from these names and abbreviations in your logs."
counties = [{"abbr": a, "name": n.title()} for a, n in sorted(live.items())]
by_abbr = {c["abbr"]: c["name"] for c in counties}

assert len(counties) == 67, f"Florida has 67 counties, parsed {len(counties)}"
assert len({c["name"] for c in counties}) == 67, "names must be unique"
assert {len(c["abbr"]) for c in counties} == {3}, "uniformly 3 letters"

# THE TRAP THE SPONSOR FLAGS ITSELF: "Pay attention to 'MIAMI-DADE' COUNTY as
# the abbreviation is DAD."
assert by_abbr["DAD"] == "Miami-Dade", by_abbr.get("DAD")
assert "MIA" not in by_abbr and "DADE" not in by_abbr

# Two counties whose names are already three letters, so the code IS the name -
# a flattener that drops repeated lines loses exactly these two.
assert by_abbr["BAY"] == "Bay"
assert by_abbr["LEE"] == "Lee"

# The four codes that are not simple truncations.
assert by_abbr["CAH"] == "Calhoun"      # not CAL
assert by_abbr["CLR"] == "Collier"      # not COL
assert by_abbr["CLM"] == "Columbia"     # ...which CLR and CLM would collide with
assert by_abbr["IDR"] == "Indian River"
assert by_abbr["MTE"] == "Manatee" and by_abbr["MAO"] == "Marion"
assert by_abbr["STJ"] == "St. Johns" and by_abbr["STL"] == "St. Lucie"

# ------------------------------------------------------------------- the rules
rules = read("fqp_rules_2026.txt")
flat = re.sub(r"\s+", " ", rules)

assert "Sponsored by the Florida Contest Group" in flat
assert ("For radio amateurs outside of the state of Florida to make contacts with as many "
        "Florida stations in as many of the 67 Florida counties as possible. Florida "
        "operators can work anyone outside and within Florida.") in flat

# Dates: the formula, the 2026 dates, and both windows in UTC and local.
assert "CONTEST PERIOD: Starts the last Saturday of April." in flat
assert "For 2026, the Florida QSO Party dates will be April 25th- 26th." in flat
assert ("There are two 10-hour operating periods separated by a 10-hour break period. All "
        "operators may operate the full 20 hours.") in flat
assert "Saturday 16:00:00Z (Noon EDT) - Sunday 01:59:59Z (9:59:59 PM EDT)" in flat
assert "Sunday 12:00:00Z (8 AM EDT) - 21:59:59Z (5:59:59 PM EDT)" in flat

# ALL FOUR local glosses convert correctly - worth checking after Nebraska,
# where none of them did. EDT is UTC-4.
EDT = -4
for utc_hour, local_hour in [(16, 12), (2, 22), (12, 8), (22, 18)]:
    assert (utc_hour + EDT) % 24 == local_hour % 24, (utc_hour, local_hour)

# Modes: no digital at all.
assert "Phone, CW, Mixed (Phone and CW)" in flat
assert "No digital QSOs are allowed in the FQP" in flat
assert "No cross-mode contacts." in flat

# Bands, and the sponsor's own arithmetic that fixes the count at four.
assert "No 160 or 80 meters, WARC or VHF bands." in flat
assert ("Stations may be worked once per mode per band for a total of 8 maximum QSOs."
        in flat)
BANDS = ["40m", "20m", "15m", "10m"]
MODES = 2
assert len(BANDS) * MODES == 8, "the sponsor's stated maximum"
for mhz in ["7.025-7.055", "14.025-14.055", "21.025-21.055", "28.025-28.055"]:
    assert mhz in flat, f"a suggested CW range on every one of the four bands: {mhz}"

# Exchange - and the DXCC prefix, stated outright.
assert "Florida operators send county." in flat
assert "US (including KH6/KL7) operators send State. Canadian operators send province." in flat
assert "DX (including KP4, etc.) operators send DXCC prefix." in flat
assert "Maritime mobile operators send ITU Region (1, 2 or 3)." in flat, \
    "three multiplier tokens with no class - see KNOWN LIMITATION 1"
assert ("Contacts with Florida stations must include their county as part of the received "
        "exchange. Don't log the exchange as FL.") in flat

# Points and scope.
assert "Each complete non-duplicate Phone contact is worth 1 point per band." in flat
assert "Each complete non-duplicate CW contact is worth 2 points per band." in flat
assert ("A multiplier is counted once per mode, regardless of the number of bands on "
        "which it is worked.") in flat
assert "50 States (including Florida)" in flat, \
    "fifty, not forty-nine - so Florida is reached through a county"
assert "There is no in-state County multiplier." in flat, \
    "Florida entrants get NO county multipliers, which is unusual"
assert "For non-Florida entrants: 67 Florida Counties." in flat

# The power multiplier, whole numbers again.
assert "If all QSOs were made using 5 watts output or less, use a Power Multiplier of 3."\
    in flat
assert ("If all QSOs were made using greater 5 watts and less than 100 watts output, use "
        "a Power Multiplier of 2.") in flat
assert ("If all QSOs were made using more than 100 watts output, there is no Power "
        "Multiplier.") in flat
assert "FINAL SCORE QSO Points times Multipliers then times Power Multiplier" in flat

# County lines, capped at two by the sponsor.
assert ("Florida stations on a county line (maximum of two counties) may be claimed as a "
        "separate QSO and multiplier from each county.") in flat
assert ("Florida Mobiles and Expeditions that move to a new county are considered to be a "
        "new station and may be contacted again for QSO Point credit.") in flat

assert "bonus" not in flat.lower(), "no bonus rule to model"

# Cabrillo: FIRST-PARTY, and not the obvious value.
spec = read("fqp_cabrillo_spec.txt")
assert "CONTEST: FCG-FQP" in spec, "the sponsor's own Cabrillo specification"
assert "FL-QSO-PARTY" not in spec, "the guess a session would otherwise have made"
assert "QSO: 14045 CW 2019-04-27 1600 K4KG          599 POL" in spec
assert by_abbr["POL"] == "Polk", "the county in the sponsor's own worked example"

# The Spelling Bee, which is what oneByOne carries. 2026-ONLY.
bee = re.sub(r"\s+", " ", read("fqp_spelling_bee_2026.txt"))
assert "2026 FQP Spelling Bee Celebrating the USA's 250th Birthday" in bee
assert ("We had a total of 20 special 1x1 stations whose suffixes spell US BIRTHDAY."
        in bee)
BEE_WORD = "USBIRTHDAY"
assert len(BEE_WORD) == 10, "ten suffix letters, two stations each, twenty in all"

NOTES = (
    "verified: partial - rules, both county lists and the Cabrillo specification all from "
    "the Florida Contest Group's own site, read verbatim 2026-07-26. THE SPONSOR PRINTS "
    "ITS OWN CABRILLO HEADER AND IT IS NOT THE OBVIOUS ONE: 'CONTEST: FCG-FQP', not "
    "FL-QSO-PARTY, taken from its own Cabrillo specification - so no Article 1 exception "
    "is needed, the first party in six to manage that. FOUR BANDS - 40, 20, 15 and 10 - "
    "THE NARROWEST LIST IN THIS APP: 'No 160 or 80 meters, WARC or VHF bands', and the "
    "sponsor's own arithmetic proves the count, since 'stations may be worked once per "
    "mode per band for a total of 8 maximum QSOs' is four bands times two modes. NO "
    "DIGITAL AT ALL. Twenty hours in two 10-hour legs separated by a 10-hour break, and "
    "ALL FOUR of the sponsor's local-time glosses convert correctly against its UTC "
    "instants - worth saying after Nebraska, where none of them did. Multipliers count PER "
    "MODE. FLORIDA ENTRANTS GET NO COUNTY MULTIPLIERS AT ALL - 'There is no in-state "
    "County multiplier' - which is unusual; they count states, provinces, DXCC countries "
    "and maritime-mobile ITU regions instead. Florida itself is inside '50 States "
    "(including Florida)' and reaches an in-state log only through a county, so "
    "homeStateCountsViaCounty is true. THE POWER MULTIPLIER FITS - QRP x3, low x2, high x1 "
    "- the third party to ship one after New Mexico and Nebraska. County lines take two "
    "counties, per the sponsor's explicit cap and the County Hunter guidelines. The 1x1 "
    "Spelling Bee ships in oneByOne: twenty stations, two per suffix letter, spelling US "
    "BIRTHDAY. THAT WORD IS 2026-ONLY - it marks the USA's 250th - so a 2027 session must "
    "replace it. KNOWN LIMITATION 1 - MARITIME MOBILE ITU REGIONS CANNOT BE COUNTED. The "
    "rules give maritime-mobile stations their own exchange ('send ITU Region (1, 2 or 3)') "
    "and make R1, R2 and R3 multipliers for Florida entrants, and the schema has no class "
    "for them: MultClass covers county, state, province and dx. AND THEY DO NOT MERELY "
    "FAIL TO COUNT - because dxStyle is 'prefix', R1, R2 and R3 are accepted as PLAUSIBLE "
    "DXCC PREFIXES and silently credited as country multipliers instead, which is the same "
    "shape as the Mississippi grid-square finding. The exchange logs and the QSO scores; "
    "only the multiplier class is wrong, and since both classes count once per mode the "
    "total usually lands right by accident. First user of that gap. OPEN QUESTION 1: IS THE OUT-OF-STATE RESTRICTION STATED OR ONLY "
    "IMPLIED? The Object is asymmetric - non-Florida amateurs are directed at Florida "
    "stations while 'Florida operators can work anyone outside and within Florida' - and "
    "non-Florida entrants' only multipliers are Florida counties, but no sentence forbids "
    "a non-Florida station from claiming points for another non-Florida contact. "
    "outStateWorksHomeStationsOnly ships true as the reading every FQP summary takes; "
    "worth confirming with the sponsor before 2027."
)

party = {
    "schemaVersion": 1,
    "id": "fqp",
    "name": "Florida QSO Party",
    "cabrilloContest": "FCG-FQP",
    "homeState": "FL",
    "countyAbbrLength": 3,
    "validBands": BANDS,
    "points": {"phone": 1, "cw": 2, "digital": 0},
    "dupeScope": "bandMode",
    "multipliers": {
        # "There is no in-state County multiplier." Florida entrants count
        # states, provinces and DXCC countries only.
        "inState": {
            "classes": ["state", "province", "dx"],
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
    "oneByOne": {"words": [BEE_WORD]},
    "dxStyle": "prefix",
    "allowedModes": ["phone", "cw"],
    "maxSimultaneousCounties": 2,
    "exchangeIncludesRST": True,
    "outStateWorksHomeStationsOnly": True,
    "scoreMultipliers": {"power": {"QRP": 3, "LOW": 2, "HIGH": 1}},
    "schedule": [
        {"start": "2026-04-25T16:00:00Z", "end": "2026-04-26T02:00:00Z"},
        {"start": "2026-04-26T12:00:00Z", "end": "2026-04-26T22:00:00Z"},
    ],
    "counties": counties,
    # THE HUB CALLS IT FLQP, NOT FQP. fqp-table.php 404s. The party id follows
    # the sponsor, whose own Cabrillo header and site both say FQP; the URL
    # follows the hub. Third party where the two differ, after California and
    # Ontario.
    "hubSpots": {
        "tableURL": "http://qsopartyhub.com/flqp-table.php",
        "postURL": "http://qsopartyhub.com/flqp-spots.php",
    },
    "notes": NOTES,
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(party, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"fqp.json: {len(counties)} counties, parsed twice and required to agree")
print("  DAD is Miami-Dade - the sponsor flags that trap itself")
print("  BAY and LEE are their own codes; a line-deduping parser loses exactly those two")
print(f"  CABRILLO IS FIRST-PARTY AND NOT THE GUESS: {party['cabrilloContest']}")
print(f"  {len(BANDS)} bands - the narrowest here; 4 x 2 modes = the sponsor's 8 max QSOs")
print("  points: phone 1, CW 2; multipliers PER MODE; NO in-state county multiplier")
print("  POWER MULTIPLIER SHIPS: QRP x3, LOW x2, HIGH x1")
print(f"  oneByOne: {BEE_WORD} - 2026 ONLY, the USA's 250th")
print("  NOT shipped: maritime-mobile ITU regions R1/R2/R3 (no mult class)")
print("  schedule: 2 windows, 10 h each, 20 h total; all four local glosses check out")
print(f"  wrote {os.path.normpath(OUT)}")
