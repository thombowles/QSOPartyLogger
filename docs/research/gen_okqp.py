#!/usr/bin/env python3
"""Generate okqp.json from the Oklahoma QSO Party's own 2026 documents.

Sources (committed alongside this script, so the run is reproducible):
  okqp_rules_2026.txt   — pdftotext -layout of http://k5cm.com/okqp2026rules.pdf,
                          "The 2026 Oklahoma QSO Party". THE AUTHORITY.
  okqp_counties.txt     — k5cm.com/counties_files/counties-x.htm, the sponsor's
                          "Oklahoma County Locator Map": 77 counties as
                          ABBR / Name (map number)
  okqp_summary_page.txt — the content frame of k5cm.com/okqp.htm, the sponsor's
                          own 2026 summary; carries the mobile activation bonus,
                          the FT8 ban, and the sponsor's OWN list of the county
                          abbreviations that "cause considerable confusion"
  okqp_rules.md         — full rules research; all fetched 2026-07-26

PROVENANCE WARNING, AND IT IS THE SHARPEST OF THIS RUN:
https://www.qsl.net/okdxa/OKQP.htm is THE 2003 RULES - headline "2003 Oklahoma
QSO Party" - and it is still live and still the top search result. It is wrong in
four scoring dimensions: it says the exchange carries a QSO NUMBER (2026: a
signal report), that NINE Canadian provinces count (2026: 13), that 160 m is a
contest band (2026: 80 m and up, plus 2 m), and it has no mobile activation bonus
at all. The assertions below pin the 2026 values so that a future run against the
wrong document fails loudly.

Reaching the real rules took three hops: the qsl.net mirror -> okqp.contesting.com
(the log robot, which is current) -> its "OKQP Home" link to k5cm.com/okqp.htm ->
that page's frameset content.

Usage:  python3 gen_okqp.py        (run from docs/research/)
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "okqp.json")
RULES = os.path.join(HERE, "okqp_rules_2026.txt")
COUNTIES = os.path.join(HERE, "okqp_counties.txt")
SUMMARY = os.path.join(HERE, "okqp_summary_page.txt")


def read(path):
    s = open(path, encoding="utf-8", errors="replace").read()
    for a, b in [("’", "'"), ("‘", "'"), ("“", '"'), ("”", '"'),
                 ("–", "-"), ("—", "-"), (" ", " ")]:
        s = s.replace(a, b)
    return s


rules = re.sub(r"\s+", " ", read(RULES))
summary = re.sub(r"\s+", " ", read(SUMMARY))
counties_txt = read(COUNTIES)

# --- Counties: "ABBR\nName (n)" pairs, numbered 1-77 on the sponsor's map. ---
counties = {}
numbers = {}
for abbr, name, num in re.findall(r"^([A-Z]{3})\n([A-Z][A-Za-z' ]+?) \((\d{1,2})\)\s*$",
                                  counties_txt, re.M):
    name = " ".join(name.split())
    if abbr in counties and counties[abbr] != name:
        sys.exit(f"OKQP conflicting names for {abbr}: {counties[abbr]!r} vs {name!r}")
    counties[abbr] = name
    numbers[abbr] = int(num)

assert len(counties) == 77, f"expected 77 OK counties, got {len(counties)}: {sorted(counties)}"
assert len(set(counties.values())) == 77, "OK county names not unique"
assert {len(a) for a in counties} == {3}, "OK codes are uniformly 3 letters"
# The sponsor numbers its map 1-77 with no gaps; a missed row would show up here.
assert sorted(numbers.values()) == list(range(1, 78)), \
    f"map numbers are not 1-77: missing {sorted(set(range(1, 78)) - set(numbers.values()))}"
assert "The 77 Oklahoma counties" in rules, "the sponsor's own county count changed"

# THE SPONSOR NAMES ITS OWN TRAPS. Every one of these pairs is a case where the
# naive first-three-letters picks the OTHER county. Assert the sponsor still
# names them, and that each resolves the way the sponsor says.
assert ('"GAR-Garfield / GRV-Garvin", "GRA-Grady / GNT-Grant", "HAR-Harmon / HRP-Harper", '
        '"MCL-McClain / MCU-McCurtain", "ROG-Rogers / RGM-Roger Mills", "WAS-Washington / '
        'WAT / Washita", "WOO-Woods / WDW-Woodward" cause considerable confusion') in summary, \
    "the sponsor's own confusion list changed - re-read it and update the spot checks"
for abbr, name in [
    ("GAR", "Garfield"), ("GRV", "Garvin"),
    ("GRA", "Grady"), ("GNT", "Grant"),
    ("HAR", "Harmon"), ("HRP", "Harper"),
    ("MCL", "McClain"), ("MCU", "McCurtain"), ("MCI", "McIntosh"),
    ("ROG", "Rogers"), ("RGM", "Roger Mills"),
    ("WAS", "Washington"), ("WAT", "Washita"),
    ("WOO", "Woods"), ("WDW", "Woodward"),
    ("LEF", "Le Flore"),        # two words
    ("OKL", "Oklahoma"),        # the county, distinct from the never-sent OK token
    ("PIT", "Pittsburg"), ("LAT", "Latimer"), ("HAS", "Haskell"),  # the sponsor's junction
    ("CIM", "Cimarron"), ("TEX", "Texas"), ("BEA", "Beaver"),
]:
    assert counties.get(abbr) == name, f"{abbr} should be {name!r}, got {counties.get(abbr)!r}"
for absent in ["GARF", "HARP", "WOOD", "ROGE", "MCCL"]:
    assert absent not in counties, f"{absent} is not an OKQP abbreviation"

# --- Bands: stated with "only". NO 160 m - which the 2003 page wrongly includes. ---
BANDS = ["80m", "40m", "20m", "15m", "10m", "6m", "2m"]
assert "Operate only the 3.5, 7, 14, 21, 28, 50, and 144 MHz bands" in rules, \
    "the band sentence changed - re-read it"
assert "160m" not in BANDS, "the 2026 rules drop 160 m; only the 2003 page has it"
for excluded in ["160m", "60m", "30m", "17m", "12m", "1.25m", "70cm"]:
    assert excluded not in BANDS

# --- The 2026 rule sentences this file encodes. ---
for quote in [
    # Dates, and the local anchors that only work under CDT
    "Saturday March 14 1400 to 0200 UTC",
    "Sunday March 15 1400 to 2200 UTC",
    "9 to 9 on Saturday, 9 to 5 on Sunday, local Oklahoma time",
    # Exchange - a SIGNAL REPORT, not the 2003 page's QSO number
    "Oklahoma stations send signal report and county",
    "W/VE stations (including KH6/KL7) send signal report and state or province",
    "DX stations (including KH2/KP4) send signal report and DXCC prefix",
    # Points
    "Count two points per phone QSO with any station",
    "Count three points per CW QSO",
    "Count three points per Digital QSO (No FT8/FT4)",
    "Stations may be worked again on each band and mode",
    # Multipliers
    "The 50 states (DC counts as Maryland)",
    "The 13 Canadian Provinces/Territories - NS, NB, NL, PE, QC, ON, MB, SK, AB, BC, NT, NU, YT",
    "A Multiplier counts once, regardless of the number bands or modes it is worked on",
    "Non Oklahoma stations The 77 Oklahoma counties",
    "unlimited dxcc mult rule",
    # County lines
    "operating on a 2, 3, or 4 county line may be counted as 2, 3, or 4 QSO and multipliers",
    "Separate log entries must be entered for each county/QSO",
    "Do not put PIT/LAT/HAS on the same line in your log",
    # Bonus
    "Oklahoma Mobile stations can earn 500 points per county by making at least 10 QSO in the county",
    # Scoring, scope of credit, Cabrillo
    "Multiply total QSO Points by total Multipliers",
    "Non Oklahoma stations work only Oklahoma stations",
    "CONTEST: OK-QSO-PARTY",
]:
    assert quote in rules, f"the 2026 rules no longer contain: {quote!r}"

assert "The 2026 Oklahoma QSO Party" in rules, \
    "this is not the 2026 edition - re-verify every rule before shipping it"

# FT8/FT4 are barred outright and the sponsor says so repeatedly. Below the
# granularity of ModeClass.digital; asserted so the note stays true.
assert "No FT8/FT4" in rules
assert "Only PSK, RTTY and JS8Call are allowed as digital contacts" in summary, \
    "the allowed-digital list changed - update the notes"
assert "Just to be clear, no FT8 or FT4" in summary
# ...and CW and digital are DELIBERATELY separate modes here, unlike ILQP.
assert "CW and Digital contacts will be scored separately" in summary

# The rules' own "19 hour" line disagrees with its four printed instants and all
# three local anchors, which total 20. Pinned so the discrepancy stays visible.
assert "Everyone may operate the entire 19 hour period" in rules, \
    "the '19 hour' line changed - re-check the schedule arithmetic in okqp_rules.md 2"
assert (12 + 8) == 20, "the two windows total 20 hours, not the stated 19"

okqp = {
    "schemaVersion": 1,
    "id": "okqp",
    "name": "Oklahoma QSO Party",
    # Printed by the sponsor in its own Cabrillo example.
    "cabrilloContest": "OK-QSO-PARTY",
    "homeState": "OK",
    "countyAbbrLength": 3,
    # "Operate only the 3.5, 7, 14, 21, 28, 50, and 144 MHz bands." No 160 m.
    "validBands": BANDS,
    # Phone 2, CW 3, digital 3 - stated identically for both sides, so one table.
    "points": {"phone": 2, "cw": 3, "digital": 3},
    # "Stations may be worked again on each band and mode."
    "dupeScope": "bandMode",
    "multipliers": {
        # "The 50 states (DC counts as Maryland); The 13 Canadian
        # Provinces/Territories; The 77 Oklahoma counties; DXCC countries
        # (excluding US, Canada, KH6 and KL7)."
        "inState": {
            "classes": ["county", "state", "province", "dx"],
            # The sponsor counts DXCC entities individually -- see the
            # multiplier quote in the notes. Resolved against the ARRL
            # DXCC List (Resources/DXCC, generated by gen_dxcc.py).
            "dxCountsEntities": True,
            # "The 50 states" is unqualified and Oklahoma is one of them, while
            # OK stations always send a county so the token OK is never received.
            # Note MNQP and NCQP both EXCLUDE their home state in so many words
            # and this one does not. Open question; see okqp_rules.md section 6.
            "homeStateCountsViaCounty": True,
            # "A Multiplier counts once, regardless of the number bands or modes."
            "countScope": "once",
            # No cap: the sponsor calls it "the unlimited dxcc mult rule".
        },
        # "Non Oklahoma stations - The 77 Oklahoma counties."
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
        },
    },
    # "Oklahoma Mobile stations can earn 500 points per county by making at least
    # 10 QSO in the county." The identical rule TnQP has, both numbers included.
    "bonuses": [
        {"type": "activatedCountyCount", "minQSOs": 10, "points": 500},
    ],
    # "DX stations send signal report and DXCC PREFIX", and OK stations count
    # DXCC countries individually - so the prefix is what tells them apart.
    "dxStyle": "prefix",
    # Phone, CW and non-FT8/FT4 digital, scored as three separate modes.
    "allowedModes": ["phone", "cw", "digital"],
    # "operating on a 2, 3, or 4 county line may be counted as 2, 3, or 4 QSO and
    # multipliers" - with each county on its own log line, which is what
    # CountyLineExpander produces.
    "maxSimultaneousCounties": 4,
    # "DC counts as Maryland."
    "stateAliases": {"DC": "MD"},
    # "Oklahoma stations send SIGNAL REPORT and county" - NOT the QSO number the
    # 2003 page still advertises.
    "exchangeIncludesRST": True,
    # "Non Oklahoma stations work only Oklahoma stations."
    "outStateWorksHomeStationsOnly": True,
    # Sat 1400Z->0200Z and Sun 1400Z->2200Z. The local anchors (9 to 9, 9 to 5)
    # land exactly under CDT - US DST began 8 March 2026, the weekend BEFORE, so
    # the summary page's "DST does NOT start on this weekend" means Oklahoma is
    # already on daylight time, not that it is on standard time.
    "schedule": [
        {"start": "2026-03-14T14:00:00Z", "end": "2026-03-15T02:00:00Z"},
        {"start": "2026-03-15T14:00:00Z", "end": "2026-03-15T22:00:00Z"},
    ],
    "counties": [{"abbr": a, "name": n} for a, n in sorted(counties.items(), key=lambda kv: kv[1])],
    "hubSpots": {
        "tableURL": "http://qsopartyhub.com/okqp-table.php",
        "postURL": "http://qsopartyhub.com/okqp-spots.php",
    },
    "notes": (
        "verified: partial - rules from the sponsor's OFFICIAL 2026 PDF ('The 2026 Oklahoma QSO "
        "Party', http://k5cm.com/okqp2026rules.pdf), with the sponsor's county locator page and "
        "its own 2026 summary page, all read verbatim 2026-07-26. Contact K5CM; logs to "
        "https://okqp.contesting.com/ by 5 April. "
        "PROVENANCE WARNING WORTH KEEPING: https://www.qsl.net/okdxa/OKQP.htm IS THE 2003 RULES - "
        "headline '2003 Oklahoma QSO Party', dated 22-23 March 2003 - and it is still live and "
        "still the first search result for this party. IT IS WRONG IN FOUR SCORING DIMENSIONS: it "
        "says the exchange carries a QSO NUMBER (the 2026 rules say a signal report), that only "
        "NINE Canadian provinces count (13 now), that 160 m is a contest band (80 m and up now, "
        "plus 2 m), and it has no mobile activation bonus at all. Reaching the real rules took "
        "three hops - the qsl.net mirror, then okqp.contesting.com which is current, then its "
        "'OKQP Home' link to k5cm.com/okqp.htm, which is a frameset. "
        "Twenty hours in TWO windows: 1400Z to 0200Z Saturday 14 March and 1400Z to 2200Z Sunday "
        "15 March 2026. The sponsor's local anchors - '9 to 9 on Saturday, 9 to 5 on Sunday' - "
        "land exactly under CDT, and the summary page's 'DST does NOT start on this weekend' "
        "means daylight time BEGAN THE WEEKEND BEFORE (8 March 2026), not that Oklahoma is on "
        "standard time; under CST every anchor would be an hour out. Note the rules also say "
        "'Everyone may operate the entire 19 hour period' where the two windows total 20; the "
        "four printed instants and all three local anchors agree with each other and with the "
        "Challenge calendar, so 20 ships and the lone 19 reads as a leftover from the 2003 "
        "edition's 18-of-24-hours off-time limit. "
        "Phone 2 points, CW 3, digital 3, stated identically for both sides. Multipliers count "
        "ONCE overall - not per band, not per mode. Oklahoma stations count the 77 counties, the "
        "50 states, the 13 provinces and territories and DXCC countries with NO CAP, which the "
        "sponsor calls 'the unlimited dxcc mult rule'; everyone else counts the 77 counties. "
        "'DC counts as Maryland', as in VTQP, BCQP and MDC - and the opposite of MNQP, NCQP and "
        "SCQP, which count DC in its own right. ALASKA AND HAWAII ARE W/VE HERE and send a state, "
        "while GUAM AND PUERTO RICO ARE DX and send a prefix; the sponsor states both in the same "
        "breath. Seven bands, 80 m through 2 m - NO 160 m, which only the stale 2003 page claims. "
        "County lines pay TWO, THREE OR FOUR counties, each on its own log line: enter PIT/LAT/HAS "
        "here and the app writes the three separate lines the sponsor demands - its instruction "
        "'Do not put PIT/LAT/HAS on the same line' is aimed at loggers that emit one Cabrillo line "
        "carrying three counties. Oklahoma mobiles earn 500 points per county in which they make "
        "at least 10 QSOs, which is modelled - the identical rule TnQP has, both numbers included. "
        "No final-score multiplier: power selects the entry class only. "
        "KNOWN LIMITATION 1 - FT8 AND FT4 ARE BARRED AND THIS APP CANNOT ENFORCE IT. The sponsor "
        "says so four times over, and names what is allowed: 'Only PSK, RTTY and JS8Call are "
        "allowed as digital contacts. Just to be clear, no FT8 or FT4.' That distinction is below "
        "the granularity of this app's mode classes, so an FT8 QSO logs and scores here and earns "
        "nothing from the sponsor. KEEP FT8/FT4 OUT OF THE LOG. Note by contrast that CW and "
        "digital ARE separate modes here - 'you can work the same station on both CW and PSK and "
        "get credit for both' - which is exactly how this app behaves, and the opposite of ILQP. "
        "KNOWN LIMITATION 2 - the sponsor uses a SINGLE FREE-TEXT Cabrillo CATEGORY: line, such "
        "as 'CATEGORY: OKLAHOMA MOBILE ASSISTED LOW MIXED', where this app writes the standard "
        "split CATEGORY-OPERATOR / CATEGORY-POWER / CATEGORY-MODE headers. The robot accepts "
        "standard Cabrillo so this is cosmetic, but an entrant chasing a specific category award "
        "should paste the sponsor's exact string into the file. "
        "Counties are 77 with uniform 3-letter codes, and THE SPONSOR NAMES ITS OWN TRAPS - seven "
        "pairs it says 'cause considerable confusion', every one of which the naive first three "
        "letters gets backwards: GAR Garfield vs GRV Garvin, GRA Grady vs GNT Grant, HAR Harmon "
        "vs HRP Harper, MCL McClain vs MCU McCurtain (and MCI McIntosh), ROG Rogers vs RGM Roger "
        "Mills, WAS Washington vs WAT Washita, and WOO Woods vs WDW Woodward. All fifteen are "
        "asserted by the generator, along with the sponsor's map numbering 1 to 77. "
        "OPEN QUESTION (why this is partial): whether Oklahoma itself counts as a state "
        "multiplier for Oklahoma entrants. The rules say 'The 50 states' without qualification "
        "and Oklahoma is one of them, while OK stations always send a county so the token OK is "
        "never received - and, unlike MNQP ('49 states, does not include Minnesota') and NCQP "
        "('49 US States (not NC)'), this sponsor does not exclude its own state. Shipped as "
        "COUNTING, via the county. The 2003 edition said so outright - 'Oklahoma stations working "
        "other Oklahoma stations must log the complete exchange, including county even though "
        "they all count as the OK multiplier' - which is not authority for a 2026 rule but does "
        "show the plain reading is long-standing sponsor practice. Confirm with K5CW/K5CM before "
        "submitting a log."
    ),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(okqp, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"okqp.json: {len(counties)} counties, uniform 3-letter codes, map numbered 1-77")
print(f"  all 7 sponsor-named confusion pairs asserted (GAR/GRV, GRA/GNT, HAR/HRP,")
print(f"    MCL/MCU, ROG/RGM, WAS/WAT, WOO/WDW)")
print(f"  points: phone 2, CW 3, digital 3; multipliers ONCE overall")
print(f"  DX: prefix style, UNCAPPED DXCC for OK stations; DC counts as MD")
print(f"  bands: {len(BANDS)} - 80 m through 2 m, NO 160 m (the 2003 page is wrong)")
print(f"  county lines: up to FOUR, each on its own log line")
print(f"  bonus: 500 points per county activated with 10+ QSOs (TnQP's rule exactly)")
print(f"  schedule: 2 windows, 12 h + 8 h = 20 h (the rules' '19 hour' line is stale)")
