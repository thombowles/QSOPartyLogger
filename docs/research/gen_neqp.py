#!/usr/bin/env python3
"""Generate Resources/Parties/neqp.json — the Nebraska QSO Party.

Per CONSTITUTION.md Article 2: the county list is parsed, never typed.

TWO RETRIEVAL TRAPS, both asserted here so a later session meets them as facts
rather than rediscovering them:

1. nebraskaqsoparty.ORG IS NOT THE SPONSOR. It is a GoDaddy content-farm page
   with no rules, no dates and no county list, linking out to a law firm and
   Nielsen radio ratings. The sponsor is nebraskaqsoparty.COM. The .org is
   banked as a counter-example.

2. THE CURRENT RULES LIVE AT A URL THAT SAYS 2022. The sponsor edits one post
   in place, so "rules-for-2022-nebraska-qso-party" serves the 2026 rules.

AND THE SPONSOR CONTRADICTS ITSELF ABOUT THE START TIME. April is CDT, UTC-5,
so 1400 UTC is 9:00 AM CDT - but the rules gloss it "(8:00 AM CDT)", and gloss
0200 UTC as "(08:00 PM CDT)" where it is 9:00 PM. Both parentheticals are one
hour off, consistently, as if computed with the CST offset. WA7BNM trusted the
local times and publishes 1300Z-0100Z; the SQP Challenge calendar trusted the
UTC. THE SPONSOR'S OWN UTC FIGURES SHIP, per Article 19, and it is recorded as
OPEN QUESTION 1.

Sources (all banked):

  neqp_rules_2026.txt      nebraskaqsoparty.com/qso-party-rules/f/rules-for-2022-...
                           (rendered - the body is absent from the HTML and from
                            the site's own RSS/JSON feeds, which carry the title only)
  neqp_counties_2022.txt   .../downloads/Nebraska QSO Party County Abbreviation List.pdf
  neqp_cabrillo_name.txt   WA7BNM Cabrillo Names (Article 1 exception - header only)
  neqp_dot_org_is_not_the_sponsor.txt   the counter-example

  All fetched 2026-07-26. See neqp_rules.md.

THREE THINGS ARE DELIBERATELY NOT SHIPPED, all argued in neqp_rules.md 12: the
FT8/FT4 competition (a whole second contest, with grid-square multipliers and
its own formula), satellite QSOs (a fourth mode the schema has no case for), and
the rare-grid bonus (which pays on the operator's own grid square).

Run:  python3 docs/research/gen_neqp.py
"""

import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "neqp.json")


def read(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        s = f.read()
    for a, b in [("’", "'"), ("‘", "'"), ("“", '"'), ("”", '"'),
                 ("–", "-"), ("—", "-"), (" ", " "),
                 ("Ø", "0")]:   # the sponsor's slashed zero is typography, not callsign
        s = s.replace(a, b)
    return s.split("=" * 72, 1)[-1]


rules = read("neqp_rules_2026.txt")
flat = re.sub(r"\s+", " ", rules)

# ---------------------------------------------------------------- the counties
# Two columns, and the PDF's spacing changes partway down, so rows are matched
# by shape rather than by column position.
ROW = re.compile(r"^([A-Z][A-Za-z]*(?: [A-Za-z]+)*)\s{2,}([A-Z]{4})\s*$")

counties = []
for line in read("neqp_counties_2022.txt").splitlines():
    line = line.rstrip()
    if not line.strip() or "County Abbreviations" in line:
        continue
    m = ROW.match(line.strip().rjust(len(line)) if False else line)
    if not m:
        m = ROW.match("  " + line.strip())
    assert m, f"unparsed county row: {line!r}"
    counties.append({"abbr": m.group(2), "name": m.group(1).strip()})

counties.sort(key=lambda c: c["abbr"])
assert len(counties) == 93, f"Nebraska has 93 counties, parsed {len(counties)}"
assert len({c["abbr"] for c in counties}) == 93, "codes must be unique"
assert len({c["name"] for c in counties}) == 93, "names must be unique"
assert {len(c["abbr"]) for c in counties} == {4}, "uniformly 4 letters"

by_abbr = {c["abbr"]: c["name"] for c in counties}

# THE SPONSOR'S MISSPELLING, shipped as printed so a correction is noticed.
assert by_abbr["CUMI"] == "Cumming", by_abbr.get("CUMI")

# The one code that drops its vowels rather than truncating.
assert by_abbr["DGLS"] == "Douglas"
assert "DOUG" not in by_abbr

# Three-way groups separated by a single fourth letter.
for group in [("CHAS", "Chase"), ("CHER", "Cherry"), ("CHEY", "Cheyenne"),
              ("DAKO", "Dakota"), ("DAWE", "Dawes"), ("DAWS", "Dawson"),
              ("FRNK", "Franklin"), ("FRON", "Frontier"), ("FURN", "Furnas")]:
    assert by_abbr[group[0]] == group[1], group

# The sponsor says outright how old the list is, which is why the 2022 file date
# is not staleness.
assert ("A list of Nebraska County abbreviations is provided on the website. It is the "
        "same list used in 2016.") in flat

# ------------------------------------------------------ the traps, as assertions
org = read("neqp_dot_org_is_not_the_sponsor.txt")
assert "What Is a QSO Party?" in org, "the .org's generic prose"
for absent in ["1400 UTC", "county abbreviation", "Cabrillo"]:
    assert absent.lower() not in org.lower(), \
        f"the .org should carry no {absent} - if it now does, re-check which is the sponsor"
assert "There is a new website, www.nebraskaqsoparty.com" in flat, \
    "the sponsor names its own domain, which is the .com"

# ------------------------------------------------------------- dates and times
assert "The QSO Party (QP) will be held over two days." in flat
assert "The QP will be April 25-26." in flat
assert ("The first day of the QP will start Saturday, April 25th, 1400 UTC (8:00 AM CDT "
        "Sat, ) and end Sunday April 27th at 0200 UTC (08:00 PM CDT)") in flat
assert "no scheduled breaks and you can operate the ENTIRE time scheduled" in flat

# OPEN QUESTION 1, as arithmetic. April is CDT = UTC-5.
CDT_OFFSET = -5
assert (14 + CDT_OFFSET) % 24 == 9, "1400 UTC is 9 AM CDT, not the 8 AM the rules gloss"
assert (2 + CDT_OFFSET) % 24 == 21, "0200 UTC is 9 PM CDT, not the 8 PM the rules gloss"
assert "8:00 AM CDT" in flat and "08:00 PM CDT" in flat, \
    "both glosses are one hour off, consistently - see OPEN QUESTION 1"

# ------------------------------------------------------------- modes and points
assert ("modes are CW, Phone (SSB, AM, FM) and Digital (RTTY, PSK, and other digital "
        "modes, but not FT8/FT4)") in flat
assert "it will be scored separately" in flat, "the FT8/FT4 contest-within-a-contest"
assert "a new category for satellite QSO's of 4 points each" in flat
assert "Cross mode contacts and repeater contacts are prohibited." in flat

assert ("Each unique digital contact is 1 points, Phone is worth 2 points, CW is worth 3 "
        "points and Satellite is worth 4 points.") in flat
assert ("Contacts with the same station on different bands are considered unique, and "
        "contacts with the same station on the same band but with different modes are "
        "also considered unique.") in flat

# ------------------------------------------------------------- the multipliers
assert ("For stations outside of Nebraska, this multiplier is the total number of "
        "Nebraska counties worked. Count each Nebraska county only once per contest. The "
        "multiplier for out-of-state stations has a maximum of 93 counties.") in flat
assert ("The maximum number of states worked is 50, and the maximum number of Canadian "
        "provinces worked is 13.") in flat
assert len(counties) == 93, "the sponsor's own stated ceiling"

assert ("If all QSOs are made QRP (5 watts or less) the power multiplier is 5; if less "
        "than 100 watts, the multiplier is 2; otherwise the power multiplier is 1 for "
        "over 100 watts.") in flat
assert ("Final Score equals (QSO Points x Power Multiplier x Geo Multiplier) plus Bonus "
        "points.") in flat

# ------------------------------------------------------------------ the bonuses
# Parsed from the sponsor's own table so the roster cannot be typed wrong.
# Anchored to the "Bonus Points" table. Without the anchor the Highlights
# paragraph ("A 100 point BONUS is given for a QSO with KA0BOJ Nebraska SM...")
# matches too, and the roster comes out one long.
BONUS = re.compile(r"([A-Z]{1,2}[0-9][A-Z]{1,3}) Nebraska [^0-9]*?(\d+) points")
table = rules.split("Bonus Points", 1)[1].split("FT8/FT4 grid-square Competition", 1)[0]
bonus_calls = BONUS.findall(table)
assert len(bonus_calls) == 7, f"seven section appointees, parsed {len(bonus_calls)}"
assert bonus_calls[0] == ("KA0BOJ", "100"), bonus_calls[0]
assert [c for c, _ in bonus_calls] == [
    "KA0BOJ", "K0SMM", "K0RPT", "K0NEB", "NF0N", "N0FER", "KE0XQ"], bonus_calls
assert all(p == "50" for _, p in bonus_calls[1:]), "all but the SM are 50"
assert ("There will be 100 bonus points for any QSO with Nebraska SM KA0BOJ and 50 bonus "
        "points for all other appointees in the section.") in flat

# The rare-grid bonus, which is NOT modelled - see neqp_rules.md 12.
assert "RARE GRID BONUS" in flat
assert "DN91CE, DN91DE, DN91EE" in flat

# --------------------------------------------------------------- bands, credit
assert "All VHF/UHF bands are allowed. WARC band contacts do not count." in flat
assert ("Stations outside of Nebraska to work as many Nebraska stations/counties as "
        "possible. Stations in Nebraska to work everyone.") in flat
assert "each out-of-state station must copy the NE county" in flat

assert ("Nebraska Mobile/Portable stations may operate from county lines, but only two "
        "counties at a time. A single exchange on the air is ok, but enter it twice in "
        "the log, once for each county.") in flat
assert ("Nebraska Mobile/Portable stations that change counties are considered to be a "
        "new station in each county") in flat

assert "exchange of signal report is optional" in flat, \
    "no other bundled party makes RST optional"

# Cabrillo: required, never named.
assert "Only Cabrillo format will be accepted for electronic logs." in flat
assert "CONTEST:" not in rules
name = read("neqp_cabrillo_name.txt")
assert "Nebraska QSO Party" in name and "NE-QSO-PARTY" in name

NOTES = (
    "verified: partial - rules from the Nebraska QSO Party Committee's own site, read "
    "verbatim 2026-07-26; entries go to Matt Anderson KA0BOJ, the ARRL Nebraska Section "
    "Manager. TWO RETRIEVAL TRAPS. FIRST, nebraskaqsoparty.ORG IS NOT THE SPONSOR: it is "
    "a GoDaddy content-farm page with no rules, no dates and no county list, linking out "
    "to a law firm and Nielsen radio ratings. The sponsor is nebraskaqsoparty.COM, and "
    "the .org is banked as a counter-example. SECOND, THE CURRENT RULES LIVE AT A URL "
    "THAT SAYS 2022 - the sponsor edits one post in place, so "
    "'rules-for-2022-nebraska-qso-party' serves the 2026 rules; the body is rendered "
    "client-side and absent from both the HTML and the site's own feeds. OPEN QUESTION 1: "
    "IS THE START 1400Z OR 1300Z? April is CDT, UTC-5, so 1400 UTC is 9:00 AM CDT - but "
    "the rules gloss it '(8:00 AM CDT)' and gloss the 0200 UTC finish '(08:00 PM CDT)' "
    "where it is 9:00 PM. Both parentheticals are one hour off, consistently, as if "
    "computed with the CST offset. WA7BNM trusted the local times and publishes "
    "1300Z-0100Z; the SQP Challenge calendar trusted the UTC. THE SPONSOR'S OWN UTC "
    "FIGURES SHIP per Article 19, so an operator starting at 1400Z loses the first hour "
    "if 1300Z was meant - worth an email before 2027. THIRTY-SIX HOURS IN ONE UNBROKEN "
    "WINDOW, joint-longest with Hawaii and behind only Vermont's 48: 'no scheduled breaks "
    "and you can "
    "operate the ENTIRE time scheduled'. The rules say the finish is 'Sunday April 27th', "
    "which mislabels the weekday - the 27th is a Monday - but the UTC DATE IS RIGHT, "
    "since Sunday evening in Nebraska is Monday in UTC. TEN BANDS - 160 through 10, 6 m, "
    "and 'all VHF/UHF bands are allowed', less WARC; Vermont and New York carry more. Points "
    "run 1 for digital, 2 for phone, 3 for CW. THE POWER MULTIPLIER FITS - QRP x5, under "
    "100 W x2, over 100 W x1, all whole numbers - making this the second party after New "
    "Mexico to ship one, with the identical 5/2/1 shape. Multipliers count ONCE OVERALL. "
    "Nebraska is inside 'the maximum number of states worked is 50' - fifty, not "
    "forty-nine - and NE stations send counties, so homeStateCountsViaCounty is true. "
    "SEVEN BONUS STATIONS, the ARRL section appointees: KA0BOJ the Section Manager at 100 "
    "points and six others at 50, parsed from the sponsor's own table rather than typed. "
    "OPEN QUESTION 2: ARE THEY ONCE OR PER QSO? '100 bonus points for ANY QSO with...' is "
    "ambiguous; scope 'once' ships as the conservative reading, and per-QSO across eleven "
    "bands and three modes would dominate the score, which argues the same way. County "
    "lines allow two counties, logged as two rows from one exchange - CountyLineExpander "
    "described from the sponsor's side. RST IS OPTIONAL HERE, which no other bundled "
    "party says; the field still ships, because having it costs nothing and hiding it "
    "would lose information the sponsor accepts. THREE THINGS ARE DELIBERATELY NOT "
    "MODELLED. KNOWN LIMITATION 1 - THE FT8/FT4 COMPETITION IS A WHOLE SECOND CONTEST: "
    "its own 2 points per QSO, its own multiplier class (GRID SQUARES, capped at 13 for "
    "out-of-state entrants), its own power multiplier fixed at 1, its own log and its own "
    "final-score formula. The schema describes one contest per party, so a party with two "
    "parallel scoring systems has no representation; FT8 entrants are out of scope, which "
    "the rules make a supported way to enter rather than a defect. The 'not FT8/FT4' "
    "exclusion inside the MAIN contest is separately the same gap Illinois and North "
    "Dakota have - third user. KNOWN LIMITATION 2 - SATELLITE QSOs CANNOT BE SCORED: "
    "ModeClass has phone, CW and digital, and satellite is a fourth thing here worth 4 "
    "points, so a satellite QSO scores whichever mode it is logged under. First user of "
    "that gap. KNOWN LIMITATION 3 - THE RARE GRID BONUS IS NOT MODELLED: it pays on "
    "activating one of three named grid squares (DN91CE, DN91DE, DN91EE) and the app has "
    "no notion of the operator's grid; the rule's own worked example is internally "
    "muddled too. The Cabrillo CONTEST header is the one thing not from the sponsor - the "
    "rules demand Cabrillo without naming it - so NE-QSO-PARTY comes from WA7BNM under "
    "Article 1's exception. SPONSOR MISSPELLING SHIPPED AS PRINTED: CUMI is 'Cumming' "
    "where Nebraska's county is Cuming, one m. The county list is the sponsor's own PDF, "
    "which the rules describe candidly - 'It is the same list used in 2016' - so its 2022 "
    "file date is intent, not staleness."
)

party = {
    "schemaVersion": 1,
    "id": "neqp",
    "name": "Nebraska QSO Party",
    "cabrilloContest": "NE-QSO-PARTY",
    "homeState": "NE",
    "countyAbbrLength": 4,
    "validBands": ["160m", "80m", "40m", "20m", "15m", "10m",
                   "6m", "2m", "1.25m", "70cm"],
    "points": {"phone": 2, "cw": 3, "digital": 1},
    "dupeScope": "bandMode",
    "multipliers": {
        # "Count each Nebraska county, and each S/P/C, only once per contest."
        "inState": {
            "classes": ["county", "state", "province", "dx"],
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
        {"type": "workStation", "call": call, "points": int(pts), "scope": "once"}
        for call, pts in bonus_calls
    ],
    "dxStyle": "prefix",
    "allowedModes": ["phone", "cw", "digital"],
    "maxSimultaneousCounties": 2,
    "exchangeIncludesRST": True,
    "outStateWorksHomeStationsOnly": True,
    "scoreMultipliers": {"power": {"QRP": 5, "LOW": 2, "HIGH": 1}},
    "schedule": [
        {"start": "2026-04-25T14:00:00Z", "end": "2026-04-27T02:00:00Z"},
    ],
    "counties": counties,
    "hubSpots": {
        "tableURL": "http://qsopartyhub.com/neqp-table.php",
        "postURL": "http://qsopartyhub.com/neqp-spots.php",
    },
    "notes": NOTES,
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(party, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"neqp.json: {len(counties)} counties, uniform 4-letter codes")
print("  TRAP 1: nebraskaqsoparty.ORG is a content farm; the sponsor is the .COM")
print("  TRAP 2: the 2026 rules live at a URL reading 'rules-for-2022-...'")
print("  OPEN QUESTION 1: the sponsor's UTC and local times differ by an hour")
print("    1400 UTC is 9 AM CDT, not the '8:00 AM CDT' printed; WA7BNM reads 1300Z")
print("    the sponsor's own UTC ships, per Article 19")
print("  schedule: ONE window of 36 h - joint-longest with Hawaii, behind Vermont's 48")
print(f"  {len(party['validBands'])} bands (all VHF/UHF, no WARC) - Vermont carries 13")
print("  points: digital 1, phone 2, CW 3; multipliers ONCE overall")
print("  POWER MULTIPLIER SHIPS: QRP x5, LOW x2, HIGH x1 - as New Mexico's")
print(f"  bonuses: {len(bonus_calls)} section appointees, "
      f"{bonus_calls[0][0]} at {bonus_calls[0][1]} and six at 50 (scope: OPEN QUESTION 2)")
print("  NOT shipped: the FT8/FT4 competition, satellite QSOs, the rare-grid bonus")
print("  CUMI is 'Cumming' as the sponsor prints it; Nebraska's county is Cuming")
print(f"  wrote {os.path.normpath(OUT)}")
