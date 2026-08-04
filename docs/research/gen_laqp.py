#!/usr/bin/env python3
"""Generate laqp.json from the Louisiana Contest Club's own pages.

Sources (committed alongside this script, so the run is reproducible):
  laqp_rules_2026.txt  — text of laqp.louisianacontestclub.org/laqso-rules-htm/
  laqp_parishes.txt    — the sponsor's official parish abbreviation list
  laqp_rules.md        — full rules research; all fetched 2026-07-26

Sponsor: Louisiana Contest Club (N5LCC). Chairman Bobby WM5H, questions@laqp.org.

FIRST BUNDLED PARTY WHOSE HOME ENTITIES ARE PARISHES, not counties.

THE 2026 DATE IS DERIVED, NOT PUBLISHED. Rule 2 still carries the 2025 running -
"14:00 UTC April 5, 2025 to 02:00 UTC April 6, 2025" - the sponsor's "LAQP Dates"
page 404s, and its Recent Posts stop at the 2021 results. The window below rests
on the stable 1400Z-0200Z shape, on "first Saturday in April" (which fits both
the printed 2025 date and the sponsor's archived "2020 LAQP is April 4th"), and
on the Challenge calendar agreeing. THE SPONSOR STATES NO FORMULA, so this is
weaker than ILQP's derivation and is the party's principal open question.

WHAT DOES NOT SHIP CLEANLY: the sponsor's mode split is TWO-WAY - Phone, and
CW/Digital together - while this app keys on three mode classes. Unlike ILQP,
where the same gap touched only dupes, LAQP counts multipliers PER BAND/MODE, so
the over-count reaches the score. See laqp_rules.md section 13.

Usage:  python3 gen_laqp.py        (run from docs/research/)
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "laqp.json")
RULES = os.path.join(HERE, "laqp_rules_2026.txt")
PARISHES = os.path.join(HERE, "laqp_parishes.txt")


def read(path):
    s = open(path, encoding="utf-8", errors="replace").read()
    for a, b in [("’", "'"), ("‘", "'"), ("“", '"'), ("”", '"'),
                 ("–", "-"), ("—", "-"), (" ", " ")]:
        s = s.replace(a, b)
    return s


rules = re.sub(r"\s+", " ", read(RULES))
parishes_txt = read(PARISHES)

# --- Parishes: the data lines are two columns of "Name CODE", e.g.
# "Acadia ACAD Madison MADI". The page's nav menu repeats the heading "Parish
# Abbreviations" several times, so bounding by the heading is unreliable -
# instead take only lines that MATCH THE DATA SHAPE: exactly two codes, each
# preceded by a capitalised name. Codes are 3 OR 4 characters. ---
DATA_LINE = re.compile(
    r"^([A-Z][A-Za-z.' ]*?) ([A-Z]{3,4}) ([A-Z][A-Za-z.' ]*?) ([A-Z]{3,4})$"
)
parishes = {}
for line in parishes_txt.splitlines():
    m = DATA_LINE.match(line.strip())
    if not m:
        continue
    for name, abbr in [(m.group(1), m.group(2)), (m.group(3), m.group(4))]:
        name = " ".join(name.split())
        if abbr in parishes and parishes[abbr] != name:
            sys.exit(f"LAQP conflicting names for {abbr}: {parishes[abbr]!r} vs {name!r}")
        parishes[abbr] = name

assert len(parishes) == 64, f"expected 64 LA parishes, got {len(parishes)}: {sorted(parishes)}"
assert len(set(parishes.values())) == 64, "LA parish names not unique"
lengths = sorted({len(a) for a in parishes})
assert lengths == [3, 4], f"expected mixed 3/4-character codes, got {lengths}"
assert "64 possible per band/mode" in rules, "the sponsor's own parish count changed"

# The five three-character codes are all contractions of long names; pin the set
# so a silent change to any of them fails here.
THREE = {a for a in parishes if len(a) == 3}
assert THREE == {"EBR", "WBR", "PCP", "SJB", "SMT"}, \
    f"the three-character codes moved: {sorted(THREE)}"

for abbr, name in [
    ("EBR", "East Baton Rouge"), ("WBR", "West Baton Rouge"),
    ("PCP", "Pointe Coupee"), ("SJB", "St. John Baptist"),  # sponsor drops the "the"
    ("SMT", "St. Martin"), ("SMAR", "St. Mary"),            # 3 chars vs 4, adjacent names
    ("SBND", "St. Bernard"), ("SCHL", "St. Charles"), ("SHEL", "St. Helena"),
    ("SJAM", "St. James"), ("SLAN", "St. Landry"), ("STAM", "St. Tammany"),
    ("ECAR", "East Carroll"), ("WCAR", "West Carroll"),
    ("EFEL", "East Feliciana"), ("WFEL", "West Feliciana"),
    ("JEFF", "Jefferson"), ("JFDV", "Jefferson Davis"),
    ("LASA", "La Salle"), ("DESO", "De Soto"), ("REDR", "Red River"),
    ("ORLE", "Orleans"), ("ACAD", "Acadia"), ("CADD", "Caddo"),
]:
    assert parishes.get(abbr) == name, f"{abbr} should be {name!r}, got {parishes.get(abbr)!r}"
# Nine St. parishes, and no two follow the same pattern.
assert sum(1 for n in parishes.values() if n.startswith("St. ")) == 9

# --- Bands: stated in the OBJECT, with a separate WARC exclusion. ---
BANDS = ["160m", "80m", "40m", "20m", "15m", "10m", "6m", "2m"]
assert "160, 80, 40, 20, 15, 10, 6 and 2 meter bands" in rules, "the band list changed"
assert "No WARC band contacts" in rules
for excluded in ["60m", "30m", "17m", "12m", "1.25m", "70cm"]:
    assert excluded not in BANDS

# --- The rule sentences this file encodes. ---
for quote in [
    # Scope of credit
    "Louisiana stations work everyone",
    "Non-Louisiana stations work Louisiana stations only",
    # Exchange
    "Non-Louisiana stations send call, signal report and state/province/country",
    "Louisiana stations send call, signal report and parish abbreviation",
    # Points
    "Count two (2) points for each complete PHONE QSO",
    "Count four (4) points for each complete CW/Digital QSO",
    # Multipliers
    "For Non-Louisiana stations, multipliers are Louisiana Parishes (64 possible per band/mode)",
    "For Louisiana stations, multipliers are: Louisiana Parishes, States (other than Louisiana), "
    "Provinces, and DXCC, per band/mode",
    "the following 13 Canadian provinces shall be recognized: AB, BC, MB, NB, NL, NS, NT, NU, "
    "ON, PE, QC, SK, and YT",
    "Maritime regions will not be recognized as multipliers",
    # Dupes - the TWO-WAY mode split
    "All fixed stations may be worked once on CW/Digital and once on Phone PER BAND",
    "CW/Digital and Phone contacts count as separate multipliers",
    "Rovers may be worked once on CW/Digital and once on Phone per band, in EACH parish activated",
    # Parish lines
    "Rovers who are PRECISELY on a parish line may give contacts for both parishes",
    "a separate and complete QSO and log entry must be made for each contact",
    # Bonuses
    "Any station working N5LCC, the Louisiana Contest Club station, may claim a one-time "
    "100 POINT BONUS",
    "PLUS 50 points per Parish activated",
    # Cabrillo required, no CONTEST token printed
    "in ARRL (Cabrillo) format",
]:
    assert quote in rules, f"the rules no longer contain: {quote!r}"

# THE DATE. Rule 2 still prints the 2025 running; assert that, so a sponsor
# update is noticed and the derivation re-checked rather than silently kept.
assert "will run from 14:00 UTC April 5, 2025 to 02:00 UTC April 6, 2025" in rules, (
    "rule 2 no longer prints the 2025 dates - THE SPONSOR MAY HAVE PUBLISHED 2026. "
    "Re-read it and re-derive the schedule; see laqp_rules.md section 2"
)
# 4 April 2026 is the first Saturday of April; 5 April 2025 was too. Both follow
# the same rule, which is the whole basis for the shipped date.
import datetime
for year, day in [(2025, 5), (2026, 4)]:
    d = datetime.date(year, 4, day)
    assert d.weekday() == 5, f"{d} is not a Saturday"
    assert d.day <= 7, f"{d} is not in the first week of April"

laqp = {
    "schemaVersion": 1,
    "id": "laqp",
    "name": "Louisiana QSO Party",
    # Cabrillo is required but the rules print no CONTEST: token;
    # WA7BNM registry (Article 1's codified exception).
    "cabrilloContest": "LA-QSO-PARTY",
    "homeState": "LA",
    # Mixed 3/4 - countyAbbrLengths reports both; this is the entry hint.
    "countyAbbrLength": 4,
    # "on the 160, 80, 40, 20, 15, 10, 6 and 2 meter bands" + "No WARC band contacts".
    "validBands": BANDS,
    # "two (2) points for each complete PHONE QSO ... four (4) points for each
    # complete CW/Digital QSO." CW at 4 ties BCQP for the highest here.
    "points": {"phone": 2, "cw": 4, "digital": 4},
    # "once on CW/Digital and once on Phone PER BAND". NOTE the sponsor's split is
    # TWO-WAY where this app keys on three mode classes; see notes.
    "dupeScope": "bandMode",
    "multipliers": {
        # "Louisiana Parishes, States (other than Louisiana), Provinces, and
        # DXCC, per band/mode."
        "inState": {
            "classes": ["county", "state", "province", "dx"],
            # "States (OTHER THAN LOUISIANA)" - stated outright, in the negative.
            "homeStateCountsViaCounty": False,
            # "64 possible per band/mode" is what fixes the scope.
            "countScope": "perBandMode",
            # The sponsor counts DXCC entities individually -- see the
            # multiplier quote in the notes. Resolved against the ARRL
            # DXCC List (Resources/DXCC, generated by gen_dxcc.py).
            "dxCountsEntities": True,
        },
        # "For Non-Louisiana stations, multipliers are Louisiana Parishes."
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "perBandMode",
        },
    },
    "bonuses": [
        # "Any station working N5LCC ... may claim a ONE-TIME 100 POINT BONUS."
        {"type": "workStation", "call": "N5LCC", "points": 100, "scope": "once"},
        # "PLUS 50 points per Parish activated." No QSO threshold is stated.
        {"type": "activatedCountyCount", "minQSOs": 1, "points": 50},
    ],
    # "state/province/COUNTRY", and LA stations count DXCC entities individually.
    "dxStyle": "prefix",
    "allowedModes": ["phone", "cw", "digital"],
    # "Rovers who are PRECISELY on a parish line may give contacts for both
    # parishes ... a separate and complete QSO and log entry must be made for each."
    "maxSimultaneousCounties": 2,
    # "call, signal report and parish abbreviation"
    "exchangeIncludesRST": True,
    # Rule 1.2.
    "outStateWorksHomeStationsOnly": True,
    # DERIVED - rule 2 still prints the 2025 running. First Saturday in April
    # 2026 is the 4th, and the 1400Z-0200Z shape is unchanged for years.
    # See notes and laqp_rules.md section 2; this is the open question.
    "schedule": [{"start": "2026-04-04T14:00:00Z", "end": "2026-04-05T02:00:00Z"}],
    "counties": [{"abbr": a, "name": n} for a, n in sorted(parishes.items(), key=lambda kv: kv[1])],
    "hubSpots": {
        "tableURL": "http://qsopartyhub.com/laqp-table.php",
        "postURL": "http://qsopartyhub.com/laqp-spots.php",
    },
    "notes": (
        "verified: partial - rules from the Louisiana Contest Club's own pages, "
        "https://laqp.louisianacontestclub.org/laqso-rules-htm/ and its official parish "
        "abbreviation list, both read verbatim 2026-07-26. Chairman Bobby WM5H, "
        "questions@laqp.org; Cabrillo logs within 10 days. THE FIRST BUNDLED PARTY WHOSE HOME "
        "ENTITIES ARE PARISHES rather than counties - Louisiana has 64 of them. "
        "THE 2026 DATE IS DERIVED, NOT PUBLISHED, AND IT IS THIS PARTY'S MAIN OPEN QUESTION. "
        "Rule 2 still reads 'The Louisiana QSO Party will run from 14:00 UTC April 5, 2025 to "
        "02:00 UTC April 6, 2025' - the 2025 running - the sponsor's own 'LAQP Dates' page 404s, "
        "and its Recent Posts stop at the 2021 results. Shipped as 1400Z Saturday 4 April to "
        "0200Z Sunday 5 April 2026 on three grounds: the 1400Z-to-0200Z twelve-hour shape has "
        "been stable for years; 'first Saturday in April' fits both the printed 2025 date and the "
        "sponsor's own archived post '2020 LAQP is April 4th'; and the State QSO Party Challenge "
        "calendar prints exactly those instants. BUT THE SPONSOR STATES NO FORMULA, so unlike "
        "ILQP - whose page prints 'Sunday the third full weekend of October' - this rests on "
        "inference from two past dates. Confirm before operating. "
        "Phone 2 points, CW and digital 4 - the joint highest CW value in this app, tied with "
        "British Columbia. Multipliers count PER BAND AND MODE on both sides, which the sponsor's "
        "'64 possible per band/mode' settles. Louisiana stations count the 64 parishes plus states "
        "OTHER THAN LOUISIANA plus the 13 provinces plus DXCC entities; everyone else counts the "
        "64 parishes. Louisiana itself is excluded in so many words. The province list is the "
        "standard 13, and the sponsor explains why it dropped the Maritime sub-regions it once "
        "counted - 'to be more in line with other state QSO parties'. DC is never mentioned and "
        "stays its own multiplier. Eight bands, 160 m through 2 m, no WARC. Parish lines pay both "
        "parishes with a separate log entry for each, which is what this app writes. N5LCC, the "
        "club station, pays a ONE-TIME 100-point bonus; Louisiana rovers earn 50 points per "
        "parish activated. No power multiplier - power selects the award only. "
        "KNOWN LIMITATION - CW AND DIGITAL ARE ONE MODE FOR THE SPONSOR AND TWO FOR THIS APP, AND "
        "HERE THAT MOVES THE SCORE. The rules say fixed stations 'may be worked once on CW/Digital "
        "and once on Phone PER BAND' and that 'CW/Digital and Phone contacts count as separate "
        "multipliers' - a TWO-WAY split, where this app keys on three mode classes. So working one "
        "station on CW and again on RTTY on the same band shows here as two valid QSOs and TWO "
        "MULTIPLIERS, while the sponsor counts one of each. Illinois has the identical rule, but "
        "there it touched only dupe accounting because ILQP counts multipliers once overall; "
        "LOUISIANA COUNTS THEM PER BAND AND MODE, so the over-count reaches the final score. If "
        "you work any station on both CW and a digital mode on the same band, delete the second "
        "contact before submitting. "
        "Cabrillo CONTEST value LA-QSO-PARTY per the WA7BNM registry - the rules require Cabrillo "
        "but print no header token. Parishes are 64 with MIXED 3- AND 4-CHARACTER codes: five are "
        "three characters, all contractions of long names - EBR East Baton Rouge, WBR West Baton "
        "Rouge, PCP Pointe Coupee, SJB St. John Baptist and SMT St. Martin. THERE ARE NINE 'St.' "
        "PARISHES AND NO TWO FOLLOW THE SAME PATTERN; watch SMT St. Martin against SMAR St. Mary "
        "in particular, three characters against four for two parishes three letters apart. Note "
        "also the East/West triples - EBR/WBR, ECAR/WCAR, EFEL/WFEL - of which only the Baton "
        "Rouges contract, and JEFF Jefferson against JFDV Jefferson Davis. The sponsor prints 'St. "
        "John Baptist', dropping the 'the' of the official St. John the Baptist Parish; it ships "
        "as printed. "
        "OPEN QUESTIONS (why this is partial): (1) THE 2026 DATE, derived as above from a rules "
        "page that still carries 2025 and a sponsor site whose dates page is missing. This is the "
        "principal one. (2) The CW/digital mode grouping above, which is a missing app feature "
        "rather than a rule in doubt, and which over-counts multipliers. Confirm both with the "
        "contest committee at questions@laqp.org before submitting a log."
    ),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(laqp, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"laqp.json: {len(parishes)} PARISHES, lengths {lengths} (5 are three characters)")
print(f"  nine St. parishes, no two alike; SMT St. Martin vs SMAR St. Mary")
print(f"  points: phone 2, CW/digital 4; multipliers PER BAND/MODE both sides")
print(f"  bands: {len(BANDS)} - 160 m through 2 m, no WARC")
print(f"  bonuses: N5LCC 100 once, 50 per parish activated")
print(f"  schedule: DERIVED - 1 window, 12 h (1400Z 4 Apr -> 0200Z 5 Apr 2026)")
print(f"    rule 2 still prints the 2025 running; see the open question")
print(f"  KNOWN LIMITATION: CW/digital are one mode for the sponsor - and here")
print(f"    that OVER-COUNTS MULTIPLIERS, unlike ILQP where only dupes were hit")
