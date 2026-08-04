#!/usr/bin/env python3
"""Generate Resources/Parties/ndqp.json — the North Dakota QSO Party.

Per CONSTITUTION.md Article 2: the county list is parsed, never typed - and so
is the Canadian list, because THIS SPONSOR'S THIRTEEN ARE NOT THE APP'S
THIRTEEN. It prints "LB Labrador" and "NF Newfoundland" as two separate tokens
and has no Nunavut at all, which is the pre-2001 RAC nomenclature. That needs a
provinces override, and an override typed from memory is exactly the kind of
thing Article 2 exists to prevent.

Sources (banked):

  ndqp_rules_2026.txt      http://ndarrlsection.com/2026/2026_nd_qsp_party_rules.pdf
                           "2026 ND QSO Party Rules", Last-Modified 2026-03-06
  ndqp_cabrillo_name.txt   https://www.contestcalendar.com/cabnames.php
                           (Article 1 WA7BNM exception - the CONTEST: header only)

  Both fetched 2026-07-26. See ndqp_rules.md.

THE COUNTY BLOCK IS THE AWKWARD PART. pdftotext reflows it so the separator
between a name and its code is inconsistent: a hyphen (Adams County-ADM), a
space (Cavalier County CAV), or nothing at all (Barnes CountyBRN). The block is
joined into one line and split on commas, then every entry is matched with the
same "<name> County[-\\s]*<CODE>" pattern, so all three shapes fall out
together.

THE SPONSOR DOES ITS OWN ARITHMETIC and it is asserted here: 53 counties + 63
W/VE (49 states excluding ND + DC + 10 provinces + 3 territories) = 116 for an
ND station, and 53 for everyone else.

Run:  python3 docs/research/gen_ndqp.py
"""

import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "ndqp.json")


def read(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        s = f.read()
    for a, b in [("’", "'"), ("‘", "'"), ("“", '"'),
                 ("”", '"'), ("–", "-"), ("—", "-"), (" ", " ")]:
        s = s.replace(a, b)
    return s


rules = read("ndqp_rules_2026.txt")
body = rules.split("=" * 72, 1)[1]          # drop this repo's provenance header

# Every rule quote below is asserted against a whitespace-flattened copy. The
# PDF wraps mid-sentence in a dozen places, and a quote that has to be broken at
# the sponsor's line breaks is a quote that stops matching the moment the PDF is
# re-laid-out - which says nothing about whether the rule changed.
flat_body = re.sub(r"\s+", " ", body)

# ---------------------------------------------------------------- the counties
# One block, from its own heading to the Canadian one. Joining the lines first
# is what makes the three separator shapes collapse into one pattern.
block = re.search(
    r"North Dakota County Abbreviations \(53\)(.*?)Canadian Abbreviations \(13\)",
    body, re.S)
assert block, "the county block moved - re-read the PDF before touching this"
flat = re.sub(r"\s+", " ", block.group(1)).strip()

ENTRY = re.compile(r"^(.+?)\s*County[-\s]*([A-Z]{3})$")

counties = []
for piece in flat.split(","):
    piece = piece.strip()
    if not piece:
        continue
    m = ENTRY.match(piece)
    assert m, f"unparsed county entry: {piece!r}"
    counties.append({"abbr": m.group(2), "name": m.group(1).strip()})

counties.sort(key=lambda c: c["abbr"])

assert len(counties) == 53, f"North Dakota has 53 counties, parsed {len(counties)}"
assert len({c["abbr"] for c in counties}) == 53, "codes must be unique"
assert len({c["name"] for c in counties}) == 53, "names must be unique"
assert {len(c["abbr"]) for c in counties} == {3}, "uniformly 3 letters"

by_abbr = {c["abbr"]: c["name"] for c in counties}

# The four Mc counties: four codes separated by a single third letter, and all
# four are real. A parser that dropped one would still produce a plausible list.
assert by_abbr["MCH"] == "McHenry"
assert by_abbr["MCI"] == "McIntosh"
assert by_abbr["MCK"] == "McKenzie"
assert by_abbr["MCL"] == "McLean"

# Two-word names survive the join intact - the separator ambiguity is worst here.
assert by_abbr["GNV"] == "Golden Valley"      # printed "Golden Valley CountyGNV"
assert by_abbr["GFK"] == "Grand Forks"
assert by_abbr["LMR"] == "La Moure", "the sponsor's spelling; the county's own is LaMoure"

# One of each separator shape, so a future pdftotext change is caught here.
assert "Adams County-ADM" in flat          # hyphen
assert "Cavalier County CAV" in flat       # space
assert "Barnes CountyBRN" in flat          # nothing at all

# --------------------------------------------------------------- the Canadians
# NOT the app's default thirteen. Parsed rather than typed, for that reason.
can_block = re.search(r"Canadian Abbreviations \(13\)(.*?)Use Standard Two Letter",
                      body, re.S)
assert can_block, "the Canadian block moved"
can_flat = re.sub(r"\s+", " ", can_block.group(1)).strip()

provinces = []
for piece in can_flat.split(","):
    piece = piece.strip()
    if not piece:
        continue
    m = re.match(r"^([A-Z]{2})\s+(.+)$", piece)
    assert m, f"unparsed province entry: {piece!r}"
    provinces.append(m.group(1))

assert len(provinces) == 13, f"the sponsor says 13, parsed {len(provinces)}"
assert len(set(provinces)) == 13

# The two swaps against the standard list, asserted by name so the override can
# never silently drift back to the app default.
STANDARD = {"AB", "BC", "MB", "NB", "NL", "NT", "NS", "NU", "ON", "PE", "QC", "SK", "YT"}
assert set(provinces) - STANDARD == {"NF", "LB"}, "expected the NL -> NF + LB split"
assert STANDARD - set(provinces) == {"NL", "NU"}, "expected no NL and no Nunavut"
assert "LB Labrador" in can_flat
assert "NF Newfoundland" in can_flat
assert "NU" not in provinces, "the sponsor's list predates Nunavut"

# ------------------------------------------------------------------ the rules
assert "North Dakota QSO Party Sponsored by: ARRL ND Section Manager N0RDF" in flat_body

# Dates: both instants, both years, UTC and local, and no formula to misapply.
assert ("Starts at 1800Z (1:00 PM CDST) April 11th, 2026 until 1800Z "
        "(1:00 PM CDST) April 12th, 2026") in flat_body

# Bands, with the exclusion stated outright.
assert "Bands: 160 through 10 meters, 6 & 2 meters, (Excluding the WARC Bands)" in flat_body

# Modes - and the FT8 exclusion this app cannot express (see ndqp_rules.md 12).
assert "Digital = (RTTY/PSK), NO FT8" in flat_body
assert ("You are allowed to make a Phone, CW and a Digital contact with the same "
        "station on the same band in each mode.") in flat_body

# Points: flat one, said twice.
assert "All contacts count as 1 point per non-duplicated phone, CW or Digital contact" in flat_body
assert "CW, Digital or Phone contacts will all count one point." in flat_body

# The multiplier arithmetic, and the scope stated with both alternatives refused.
assert ("ND stations multiply points by the sum of ND Counties (53), states/provinces "
        "(49 states excluding North Dakota + DC, + 10 Canadian provinces + 3 Canadian "
        "Territories = 63 W/VE multipliers total): 116 Total Multipliers") in flat_body
assert "Multipliers count once overall, not once per band or mode." in flat_body
assert ("North Dakota stations may work DXCC countries for points only - no multipliers."
        in flat_body)

STATES_LESS_ND_PLUS_DC = 49 + 1
CANADA = 13
assert STATES_LESS_ND_PLUS_DC + CANADA == 63, "the sponsor's W/VE total"
assert len(counties) + 63 == 116, "the sponsor's in-state total"

# The summary sheet restates both ceilings independently.
assert "Multipliers max 63 plus # North Dakota Counties" in flat_body
assert "Multipliers max 53" in flat_body
assert "Contacts with only ND Stations count." in flat_body

# County lines: park there, but work each county separately.
assert ("Mobile stations may park on a county line but each county must be worked in a "
        "separate contact.") in flat_body
assert ("Mobile ND stations that change counties are considered to be a new station in "
        "each new county.") in flat_body

# No power categories, no multi-op, a bare product.
assert "There are no power limitations in this contest, within legal limit." in flat_body
assert "There are no multi-op categories" in flat_body
assert "Final Total = Contact Total X Multiplier Total" in flat_body
assert "bonus" not in flat_body.lower(), "a bonus rule would need modelling"

# The exchange, including the DX shape that limitation 1 is about.
assert "ND stations give RST and County." in flat_body
assert "DX Stations give RST and DX country." in flat_body

# THE SPONSOR'S OWN ERRORS, asserted so that a correction is noticed.
assert "postmarked by May 15th, 2025." in flat_body, \
    "a 2025 deadline in the 2026 rules, two lines above a 2026 one"
assert "by the May 15th, 2026 deadline" in flat_body
assert "January 2025" in flat_body and "Revised January 2026" in flat_body
assert "CW: 1.850, 3.550, 3705, 7.050" in flat_body, "3705 is missing its decimal point"
assert "NT Northwest Territory" in can_flat, "singular; officially Territories"
assert "PE Prince Edward Is." in can_flat

# Cabrillo: the sponsor never states one. Article 1's WA7BNM exception.
assert "CONTEST:" not in flat_body, \
    "if the sponsor ever prints a CONTEST: header, drop the WA7BNM exception"
assert "Cabrillo file via" in flat_body, "it does ask for Cabrillo - it just never names it"
cab = read("ndqp_cabrillo_name.txt")
assert "North Dakota QSO Party" in cab and "ND-QSO-PARTY" in cab

NOTES = (
    "verified: partial - rules and both abbreviation lists from the ARRL North Dakota "
    "Section's own '2026 ND QSO Party Rules' (Last-Modified 2026-03-06, footer 'Revised "
    "January 2026'), read verbatim 2026-07-26. The sponsor is a SECTION, not a club: ND "
    "Section Manager N0RDF with ASM K0YL. TWENTY-FOUR HOURS IN ONE UNBROKEN WINDOW - a "
    "shape shared with exactly two other bundled parties, Maine and South Dakota - with "
    "both instants printed in UTC "
    "and local and both years stated, so nothing is derived. THE CANADIAN LIST IS NOT THE "
    "STANDARD THIRTEEN: this sponsor prints 'LB Labrador' and 'NF Newfoundland' as two "
    "separate tokens and has NO NUNAVUT, which is pre-2001 RAC nomenclature, so the "
    "provinces override ships and is parsed from the sponsor's own list rather than typed. "
    "NORTH DAKOTA IS NOT A STATE MULTIPLIER - '49 states excluding North Dakota' - and ND "
    "stations instead count all 53 of their own counties, which is why the in-state "
    "ceiling is 116 (53 + 63) rather than 63. Multipliers count ONCE OVERALL, with both "
    "alternatives named and refused in the same sentence. Flat ONE POINT for every mode, "
    "stated twice. No power categories, no multi-op, no bonuses: 'Final Total = Contact "
    "Total X Multiplier Total'. A mobile may park on a county line but each county must be "
    "worked in a SEPARATE CONTACT, so maxSimultaneousCounties is 1 - the opposite of "
    "Georgia, where the rover sends both at once. AN ND STATION CAN NOW LOG THE DX COUNTRY "
    "THE RULES ASK FOR, which it could not before 2026-08-01. The rules want the country "
    "in the log, and ExchangeParser used to guess at DXCC prefixes by shape - loose enough "
    "to turn every mistyped county into a valid exchange - so the guess was gated to "
    "operators for whom DX was a multiplier class. North Dakota grants DX no multipliers, "
    "which left dxStyle 'prefix' inert AND stripped the literal DX token, so 'token' "
    "shipped and the operator typed DX where the sponsor wanted DL. The DXCC entity table "
    "(Resources/DXCC, ARRL DXCC List January 2026 edition) checks tokens against the real "
    "list instead of guessing, so the gate is gone: dxStyle 'prefix' now accepts DL, and "
    "acceptsDXToken keeps the literal DX for a country the operator did not catch. THE "
    "SCORE IS UNAFFECTED EITHER WAY - DX is never a multiplier here and every mode pays "
    "the same one point; only the log's fidelity to the rules changes. KNOWN "
    "LIMITATION 1 - 'NO FT8' CANNOT BE ENFORCED. ModeClass.digital is one class and this "
    "party admits RTTY and PSK under it, so a logged FT8 row will score. SECOND USER of "
    "that gap after Illinois ('FT4 and FT8 contacts will receive no contact credit'), which "
    "meets the repo's two-user bar and makes it buildable: QSO.rawMode already carries the "
    "concrete mode, so the fix is a party-level list of excluded raw modes. The Cabrillo CONTEST header "
    "is the one thing not from the sponsor - its five pages never state one, though they "
    "do ask for Cabrillo logs - so ND-QSO-PARTY comes from WA7BNM's Cabrillo Names table "
    "under Article 1's exception. SPONSOR ERRORS SHIPPED AS PRINTED: a 'May 15th, 2025' "
    "deadline two lines above the 2026 one, 'January 2025' immediately before 'Revised "
    "January 2026', a CW frequency printed '3705' without its decimal point, 'Northwest "
    "Territory' singular, and 'La Moure' for the county that spells itself LaMoure."
)

party = {
    "schemaVersion": 1,
    "id": "ndqp",
    "name": "North Dakota QSO Party",
    "cabrilloContest": "ND-QSO-PARTY",
    "homeState": "ND",
    "countyAbbrLength": 3,
    "validBands": ["160m", "80m", "40m", "20m", "15m", "10m", "6m", "2m"],
    "points": {"phone": 1, "cw": 1, "digital": 1},
    "dupeScope": "bandMode",
    "multipliers": {
        # 53 counties + 63 W/VE = 116. North Dakota itself is NOT among the
        # states, and no DX: "for points only - no multipliers".
        "inState": {
            "classes": ["county", "state", "province"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
        },
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
        },
    },
    "bonuses": [],
    # The rules want the DX country in the log, and with the ARRL entity table
    # checking tokens against the real list, prefix mode can finally deliver
    # it. DX earns no multiplier here either way.
    "dxStyle": "prefix",
    # ...and the literal DX stays loggable, for a country not caught.
    "acceptsDXToken": True,
    "allowedModes": ["phone", "cw", "digital"],
    "maxSimultaneousCounties": 1,
    "provinces": sorted(provinces),
    "exchangeIncludesRST": True,
    "outStateWorksHomeStationsOnly": True,
    "schedule": [
        {"start": "2026-04-11T18:00:00Z", "end": "2026-04-12T18:00:00Z"},
    ],
    "counties": counties,
    "hubSpots": {
        "tableURL": "http://qsopartyhub.com/ndqp-table.php",
        "postURL": "http://qsopartyhub.com/ndqp-spots.php",
    },
    "notes": NOTES,
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(party, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"ndqp.json: {len(counties)} counties, uniform 3-letter codes")
print("  the four Mc counties differ by one letter: "
      + ", ".join(f"{a} {by_abbr[a]}" for a in ("MCH", "MCI", "MCK", "MCL")))
print(f"  PROVINCES OVERRIDE SHIPS: {' '.join(sorted(provinces))}")
print("    NL is split into NF + LB, and there is no NU - pre-2001 RAC spelling")
print("  points: flat 1 for phone, CW and digital alike")
print(f"  multipliers ONCE OVERALL: in-state {len(counties)} + 63 = 116, "
      f"out-of-state {len(counties)}")
print("    North Dakota is NOT a state multiplier; ND stations count their own counties")
print("  county lines: each county must be a separate contact, so max is 1")
print("  schedule: 1 window, 24 h unbroken - as Maine and South Dakota also are")
print("  NOT shipped: the 'NO FT8' exclusion, and DX country prefixes (see notes)")
print(f"  wrote {os.path.normpath(OUT)}")
