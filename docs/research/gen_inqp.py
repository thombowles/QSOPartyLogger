#!/usr/bin/env python3
"""Generate Resources/Parties/inqp.json — the Indiana QSO Party.

Per CONSTITUTION.md Article 2: the county list is parsed, never typed.

TWO THINGS TO GET RIGHT, and both are traps a stale source falls into:

1. QSO POINTS CHANGED FOR 2026. The rules now read "Count two points for each
   complete two-way QSO (both CW and Phone) - Rule change for 2026." The OLD
   wording, "one point ... phone / two points ... CW", is STILL IN THE PAGE as
   an HTML comment. The banked text keeps comments but MARKS them, so this
   script can assert both that the new rule is live and that the old one is
   commented out.

2. THE COUNTY ABBREVIATIONS CHANGED IN 2017, which the rules say outright, and
   counties-rev2017.html meta-refreshes to counties.html. A pre-2017 list is
   wrong.

Like 7QP, the exchange is a 5-character state+county code - Marion is INMRN -
but Indiana is a single state, so no County.state is needed and the multi-state
schema stays untouched here.

Sources (all banked):

  inqp_rules_2026.txt      http://www.hdxcc.org/inqp/rules.html  (Last-Modified 2026-03-14)
  inqp_counties_2026.tsv   http://www.hdxcc.org/inqp/counties.html
  inqp_cabrillo_name.txt   WA7BNM Cabrillo Names (Article 1 exception - header only)

  All fetched 2026-07-26. See inqp_rules.md.

Run:  python3 docs/research/gen_inqp.py
"""

import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "inqp.json")


def read(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        s = f.read()
    for a, b in [("’", "'"), ("‘", "'"), ("“", '"'), ("”", '"'),
                 ("–", "-"), ("—", "-"), (" ", " ")]:
        s = s.replace(a, b)
    return s.split("=" * 72, 1)[-1]


# ---------------------------------------------------------------- the counties
counties = []
for line in read("inqp_counties_2026.tsv").splitlines():
    if line.startswith("#") or line.startswith("### TABLE") or not line.strip():
        continue
    cells = [c.strip() for c in line.split("\t")]
    # Shape-driven rather than table-indexed: the page's first table is its
    # banner, so anything whose second cell is not an INxxx code is not a
    # county row. The count assertion below is what proves nothing was skipped.
    if len(cells) < 2 or not re.fullmatch(r"IN[A-Z]{3}", cells[1]):
        continue
    name, code = cells[0], cells[1]
    assert name and not name.startswith("IN"), f"bad county name {name!r} for {code}"
    counties.append({"abbr": code, "name": name})

counties.sort(key=lambda c: c["abbr"])
by_abbr = {c["abbr"]: c["name"] for c in counties}

assert len(counties) == 92, f"Indiana has 92 counties, parsed {len(counties)}"
assert len(by_abbr) == 92, "codes must be unique"
assert len({c["name"] for c in counties}) == 92, "names must be unique"
assert {len(c["abbr"]) for c in counties} == {5}, "uniformly 5: IN + three letters"
assert all(c["abbr"].startswith("IN") for c in counties)

# The sponsor's own worked example, from the exchange rule.
assert by_abbr["INMRN"] == "Marion", by_abbr.get("INMRN")

# Codes that are NOT simple truncations - Marion is MRN, not MAR.
assert "INMAR" not in by_abbr, "Marion is INMRN; INMAR would be the naive guess"
for code, name in [("INADA", "Adams"), ("INALL", "Allen"), ("INBAR", "Bartholomew"),
                   ("INHAN", "Hancock"), ("INHAR", "Harrison")]:
    assert by_abbr[code] == name, (code, by_abbr.get(code))

# ------------------------------------------------------------------- the rules
rules = read("inqp_rules_2026.txt")
flat = re.sub(r"\s+", " ", rules)

assert "2026 Indiana QSO Party Rules" in flat
assert "Sponsored by HDXCCthe Hoosier DX and Contest Club" in flat

# THE 2026 RULE CHANGE, and the old wording it replaced.
assert "Count two points for each complete two-way QSO (both CW and Phone)" in flat
assert "Rule change for 2026." in flat
comments = " ".join(re.findall(r"\[\[COMMENTED OUT IN THE SOURCE\]\](.*?)\[\[END COMMENT\]\]",
                               flat))
assert "Count one point for each complete two-way phone QSO." in comments, \
    "the pre-2026 wording should still be present, but only inside a comment"
assert "Count one point for each complete two-way phone QSO." not in \
    re.sub(r"\[\[COMMENTED OUT IN THE SOURCE\]\].*?\[\[END COMMENT\]\]", " ", flat), \
    "...and must NOT appear in the live text"

# The abbreviations changed in 2017, which is why a pre-2017 list is wrong.
assert "County name abbreviations changed in 2017." in flat

# Dates: formula, the 2026 dates, and both local zones.
assert ("Contest starts at 1500 UTC Saturday and ends at 0259 UTC Sunday the first full "
        "weekend of May.") in flat
assert "(Saturday 11am to 11pm EDT or 10am to 10pm CDT.)" in flat
assert "For 2026, this is May 2-3." in flat
assert "All stations may operate the full 12-hour period." in flat
EDT = -4
assert (15 + EDT) % 24 == 11, "1500Z is 11 AM EDT, as the rules say"
assert (3 + EDT) % 24 == 23, "0300Z is 11 PM EDT, as the rules say"

# Bands, and the sponsor's own dupe arithmetic.
assert ("contact as many stations in Indiana as possible on the 160, 80, 40, 20, 15 and 10 "
        "meter Amateur bands.") in flat
assert ("Stations may be worked once in each mode (CW/phone) on each band (160, 80, 40, 20, "
        "15, 10).") in flat
assert "The same fixed station could theoretically be worked twelve times." in flat
BANDS = ["160m", "80m", "40m", "20m", "15m", "10m"]
assert len(BANDS) * 2 == 12, "six bands times two modes is the sponsor's twelve"

# The exchange, including the 5-character shape and its worked example.
assert ("Indiana stations send RS(T) plus their INQP exchange from this list. For example, "
        "an Indiana station in Marion county would send \"59 INMRN\".") in flat
assert ("Non-Indiana stations in the USA and Canada send RS(T) and state, province or "
        "territory. All others send RS(T) and \"DX\".") in flat

# Multipliers.
assert "Multipliers count once per mode (i.e. once on CW and once on phone)." in flat
assert "The 92 Indiana counties" in flat
assert "The other 49 U.S. states (District of Columbia counts as Maryland)." in flat
assert ("Indiana stations may work DX stations for QSO point credit, but there are no DX "
        "multipliers.") in flat
assert "Non-Indiana stations may work only Indiana stations." in flat
assert "Multiply QSO points by total multipliers." in flat

# The sponsor's own worked example is the arithmetic check.
assert "Total score = ((354) * 2) * (39 + 27)" in flat
assert "Total score = 708 x 66" in flat
assert 354 * 2 == 708 and 39 + 27 == 66 and 708 * 66 == 46728
assert "Total score = 46,728" in flat

# County lines, capped explicitly and with the refusal spelled out.
assert ("A county line mobile, portable, or rover may operate from only one or two counties "
        "at a time. In other words, three and four county operations are not allowed.") in flat

assert "no digital" not in flat.lower()
assert "RTTY" not in flat and "FT8" not in flat, "CW and phone only; digital is never named"
assert "Repeater, cross-band and cross-mode contacts are not allowed." in flat
assert "CONTEST:" not in rules
name = read("inqp_cabrillo_name.txt")
assert "Indiana QSO Party" in name and "IN-QSO-PARTY" in name

NOTES = (
    "verified: partial - rules and county list from the Hoosier DX and Contest Club's own "
    "site, read verbatim 2026-07-26 (rules Last-Modified 2026-03-14). QSO POINTS CHANGED "
    "FOR 2026: 'Count two points for each complete two-way QSO (both CW and Phone) - Rule "
    "change for 2026.' Phone used to be worth one and CW two, AND THE OLD WORDING IS STILL "
    "IN THE PAGE AS AN HTML COMMENT - so a scraper that strips the comment markers but "
    "keeps the text reads both rules at once. The generator asserts the new rule is live "
    "AND that the old one appears only inside a comment. THE COUNTY ABBREVIATIONS CHANGED "
    "IN 2017, which the rules say outright, so any pre-2017 list is wrong; "
    "counties-rev2017.html meta-refreshes to counties.html, which is the current one. THE "
    "EXCHANGE IS A 5-CHARACTER STATE+COUNTY CODE - Marion is INMRN, which the rules print "
    "as their example - the same shape as 7QP's, but Indiana is a single state so no "
    "County.state is needed and the multi-state schema is untouched here. WATCH INMRN: "
    "Marion is MRN, not MAR, so the naive truncation is wrong. Twelve hours in one window, "
    "1500Z to 0259Z on the first full weekend of May, with both local zones given (11am-11pm "
    "EDT or 10am-10pm CDT - Indiana straddles two) and both converting correctly. Six bands, "
    "and the sponsor works the dupe arithmetic out loud: six bands times two modes means "
    "'the same fixed station could theoretically be worked twelve times'. CW AND PHONE "
    "ONLY - digital is never named anywhere in the rules. Multipliers count PER MODE. "
    "INDIANA IS NOT A STATE MULTIPLIER ('the other 49 U.S. states'), and Indiana entrants "
    "count the 92 counties themselves, so homeStateCountsViaCounty is false. DC COUNTS AS "
    "MARYLAND. DX PAYS POINTS AND NO MULTIPLIER for an Indiana entrant - 'Indiana stations "
    "may work DX stations for QSO point credit, but there are no DX multipliers' - the "
    "third party with that shape, after Georgia and North Dakota. County lines take one or "
    "two counties, with the sponsor spelling out the refusal: 'three and four county "
    "operations are not allowed'. No bonus points and no power multiplier: 'Multiply QSO "
    "points by total multipliers', which the sponsor's own worked example confirms "
    "(354 QSOs x 2 points x 66 multipliers = 46,728). The Cabrillo CONTEST header is the "
    "one thing not from the sponsor - the rules discuss the Cabrillo CLUB: line at length "
    "without ever naming CONTEST: - so IN-QSO-PARTY comes from WA7BNM under Article 1's "
    "exception. THE SPOT HUB DOES NOT SERVE THIS PARTY: inqp-table.php "
    "302-redirects to a login page, exactly as 7QP's does, so hubSpots is null."
)

party = {
    "schemaVersion": 1,
    "id": "inqp",
    "name": "Indiana QSO Party",
    "cabrilloContest": "IN-QSO-PARTY",
    "homeState": "IN",
    "countyAbbrLength": 5,
    "validBands": BANDS,
    "points": {"phone": 2, "cw": 2, "digital": 0},
    "dupeScope": "bandMode",
    "multipliers": {
        # In-state counts its own counties plus the other 49 states and 13
        # provinces - and pointedly no DX.
        "inState": {
            "classes": ["county", "state", "province"],
            "homeStateCountsViaCounty": False,
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
    "maxSimultaneousCounties": 2,
    "stateAliases": {"DC": "MD"},
    "exchangeIncludesRST": True,
    "outStateWorksHomeStationsOnly": True,
    "schedule": [
        {"start": "2026-05-02T15:00:00Z", "end": "2026-05-03T03:00:00Z"},
    ],
    "counties": counties,
    # THE HUB DOES NOT SERVE INQP. inqp-table.php 302-redirects to a login
    # page, exactly as 7qp-table.php does - the trap California's qp-table.php
    # set, where a guessed prefix yields a poller that never errors and never
    # shows anything.
    "hubSpots": None,
    "notes": NOTES,
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(party, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"inqp.json: {len(counties)} counties, 5-character IN+county codes")
print("  POINTS CHANGED FOR 2026: flat 2 for both modes (phone used to be 1)")
print("    ...and the old wording is STILL IN THE PAGE, inside an HTML comment")
print("  the abbreviations changed in 2017 - a pre-2017 list is wrong")
print("  INMRN is Marion; INMAR would be the naive guess and does not exist")
print("  multipliers PER MODE; Indiana is NOT a state multiplier; DC counts as MD")
print("  DX pays points and no multiplier - third party with that shape")
print("  county lines: one or two, with three and four refused by name")
print("  NO HUB SOURCE: inqp-table.php 302s to a login page, as 7QP does")
print("  schedule: 1 window, 12 h, first full weekend of May")
print(f"  wrote {os.path.normpath(OUT)}")
