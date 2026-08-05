#!/usr/bin/env python3
"""Generate msqp.json from the Vicksburg ARC's own 2026 documents.

Sources (committed alongside this script, so the run is reproducible):
  msqp_rules_2026.txt — pdftotext -layout of 2026-MS-QSO-PARTY-RULES-FINAL.pdf,
                        header "2026 MS QSO PARTY RULES". THE AUTHORITY.
  msqp_counties.txt   — the sponsor's "County Check List", 82 counties in three
                        columns of "Abbrv  County Name"
  msqp_page.txt       — msqp.eqth.net, which confirms the date independently
  msqp_rules.md       — full rules research; all fetched 2026-07-26

Sponsor: Vicksburg Amateur Radio Club; manager Malcolm W5XX, published via the
ARRL Mississippi Section.

RETRIEVAL NOTE: arrlmiss.org 404s a plain fetch of its own PDFs. They need a
browser User-Agent AND a Referer of https://arrlmiss.org/mississippi-qso-party/ .

THE FIRST PARTY HERE THAT BUILDS FT4/FT8 IN ON PURPOSE - "Incorporate FT4/8
digital modes into the event" is one of three stated objectives, where ILQP,
NCQP, OKQP and IDQP all bar it. That is also where the gaps come from, all
recorded in the notes and in msqp_rules.md section 12:
  * GRID SQUARE MULTIPLIERS - up to 9 for an out-of-state entrant on a base of
    82, and grids/4 rounded up for an MS entrant. No MultClass case exists.
  * the FT4/8 exchange is a GRID SQUARE, not a location token, and this app has
    one exchange shape per party.
  * RTTY and FT4/8 are separate modes to the sponsor and one ModeClass here - the
    sponsor's own example works one station on 20m RTTY AND 20m FT4/8.

Usage:  python3 gen_msqp.py        (run from docs/research/)
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "msqp.json")
RULES = os.path.join(HERE, "msqp_rules_2026.txt")
COUNTIES = os.path.join(HERE, "msqp_counties.txt")
PAGE = os.path.join(HERE, "msqp_page.txt")


def read(path):
    s = open(path, encoding="utf-8", errors="replace").read()
    for a, b in [("’", "'"), ("‘", "'"), ("“", '"'), ("”", '"'),
                 ("–", "-"), ("—", "-"), (" ", " ")]:
        s = s.replace(a, b)
    return s


rules = re.sub(r"\s+", " ", read(RULES))
page = re.sub(r"\s+", " ", read(PAGE))
counties_txt = read(COUNTIES)

# --- Counties: three columns of "ABC  County Name". The check-list artwork
# ("Mississippi / QSO Party / County Check List") is interleaved into column 3,
# so require a 3-letter code followed by two spaces and a capitalised name. ---
# re.M matters: without it the "end of line" alternative only matches the end
# of the whole file, and the third column plus most of the second is dropped.
PAIR = re.compile(
    r"\b([A-Z]{3})\s{2,}([A-Z][A-Za-z]*(?: [A-Z][A-Za-z]*)?)(?=\s{2,}|\s*$)", re.M
)
counties = {}
for abbr, name in PAIR.findall(counties_txt):
    name = " ".join(name.split())
    if abbr in counties and counties[abbr] != name:
        sys.exit(f"MSQP conflicting names for {abbr}: {counties[abbr]!r} vs {name!r}")
    counties[abbr] = name
counties.pop("Abb", None)   # the table header, "Abbrv   County Name"

assert len(counties) == 82, f"expected 82 MS counties, got {len(counties)}: {sorted(counties)}"
assert len(set(counties.values())) == 82, "MS county names not unique"
assert {len(a) for a in counties} == {3}, "MS codes are uniformly 3 letters"
assert "82 possible" in rules, "the sponsor's own county count changed"

# Mississippi's clusters are among the densest in the repo, and several codes are
# NOT the naive first three letters. See msqp_rules.md section 11.
for abbr, name in [
    ("CAL", "Calhoun"), ("CLA", "Clay"), ("CLB", "Claiborne"), ("CLK", "Clarke"),
    ("LAF", "Lafayette"), ("LAM", "Lamar"), ("LAU", "Lauderdale"), ("LAW", "Lawrence"),
    ("WAL", "Walthall"), ("WAR", "Warren"), ("WAS", "Washington"), ("WAY", "Wayne"),
    ("MAR", "Marshall"), ("MRN", "Marion"), ("MAD", "Madison"),
    ("GRN", "Greene"), ("GRE", "Grenada"),
    ("JEF", "Jefferson"), ("JDV", "Jefferson Davis"),
    ("PER", "Perry"), ("PEA", "Pearl River"),
    ("MGY", "Montgomery"), ("NOX", "Noxubee"), ("OKT", "Oktibbeha"), ("ISS", "Issaquena"),
    ("DES", "DeSoto"),      # one word here; Louisiana prints "De Soto"
    ("HIN", "Hinds"), ("LEE", "Lee"), ("YAZ", "Yazoo"),
]:
    assert counties.get(abbr) == name, f"{abbr} should be {name!r}, got {counties.get(abbr)!r}"
for absent in ["CLAI", "MARI", "GREE", "PEAR"]:
    assert absent not in counties, f"{absent} is not an MSQP abbreviation"

# --- Bands: listed outright, no exclusion clause needed. ---
BANDS = ["160m", "80m", "40m", "20m", "15m", "10m", "6m", "2m"]
assert "Bands: 160m, 80m, 40m, 20m, 15m, 10m, 6m, 2m" in rules, "the band list changed"
for excluded in ["60m", "30m", "17m", "12m", "1.25m", "70cm"]:
    assert excluded not in BANDS

# --- The rule sentences this file encodes. ---
for quote in [
    # Dates - printed twice over, plus the duration
    "Starts: 1400z / 4 April 2026",
    "Ends: 0200z / 5 April 2026",
    "Duration: 12 Hours",
    # Exchange
    "W/VE stations send signal report and State or Province",
    "DX stations send signal report and Country",
    "MS stations send signal report and County",
    "ALL FT4/8 stations send signal report and Grid Square",
    # Points and dupes
    "QSO Points: SSB = 1; CW = 2; RTTY = 2; FT4/8 = 2",
    "Same station can be worked on each separate band/mode",
    # Multipliers
    "Multipliers: (Earned ONCE regardless of band/mode worked.)",
    "1 for each of the remaining States worked (49 possible)",
    "1 for each Canadian Province/Territory worked (13 possible)",
    # Scoring
    "Fixed: Final score equals the sum of QSO points multiplied by the total multipliers",
    "Portable/Mobile: Final score will be the sum of the scores from each County operated",
    "Entry Categories: (No separate mode or power categories)",
]:
    assert quote in rules, f"the 2026 rules no longer contain: {quote!r}"

assert "2026 MS QSO PARTY RULES" in rules, \
    "this is not the 2026 edition - re-verify every rule before shipping it"
# The sponsor's activity page confirms the date independently, in local time.
assert "April 4, 2026" in page and "9:00 am - 9:00 pm CDT" in page, \
    "the activity page no longer corroborates the date - re-check both sources"

# The FT4/8 rules that deliberately do not ship. Assert they are still there so a
# future edition dropping FT4/8 leaves no stale limitation in the notes.
assert "Incorporate FT4/8 digital modes into the event" in rules
assert "1 for each MS Grid Square worked in FT8/4 (9 possible...EM41-44 and EM50-54)" in rules, \
    "the grid-square multiplier rule changed - revisit KNOWN LIMITATION 1"
assert "dividing by 4" in rules and "Round up to nearest whole number" in rules
assert "20m RTTY, 20m FT4/8" in rules, \
    "the sponsor's own four-mode example is gone - revisit KNOWN LIMITATION 3"

# The rules say NOTHING about county lines. Assert that silence, so a future
# edition adding a provision is noticed rather than passing unread.
assert "county line" not in rules.lower(), \
    "the rules now mention county lines - re-read them and revisit maxSimultaneousCounties"

msqp = {
    "schemaVersion": 1,
    "id": "msqp",
    "name": "Mississippi QSO Party",
    # The rules print no CONTEST: token and do not even require Cabrillo
    # ("Hand-written legible logs will be accepted"); WA7BNM registry.
    "cabrilloContest": "MS-QSO-PARTY",
    "homeState": "MS",
    "countyAbbrLength": 3,
    # "Bands: 160m, 80m, 40m, 20m, 15m, 10m, 6m, 2m" - listed outright.
    "validBands": BANDS,
    # "SSB = 1; CW = 2; RTTY = 2; FT4/8 = 2." RTTY and FT4/8 pay alike, so four
    # sponsor modes collapse into three mode classes with no loss of POINTS
    # accuracy - the difference matters for multipliers and dupes. See notes.
    "points": {"phone": 1, "cw": 2, "digital": 2},
    # "Same station can be worked on each separate band/mode."
    "dupeScope": "bandMode",
    "multipliers": {
        # "1 for each MS County worked (82 possible), 1 for each of the remaining
        # States worked (49 possible), 1 for each Canadian Province/Territory
        # worked (13 possible), 1 for each remaining DX Country/Entity worked."
        # The grid-square component has no MultClass; see notes.
        "inState": {
            "classes": ["county", "state", "province", "dx"],
            # "the REMAINING States worked (49 possible)" - 49, not 50, so
            # Mississippi is excluded.
            "homeStateCountsViaCounty": False,
            # "Earned ONCE regardless of band/mode worked."
            "countScope": "once",
            # The sponsor counts DXCC entities individually -- see the
            # multiplier quote in the notes. Resolved against the ARRL
            # DXCC List (Resources/DXCC, generated by gen_dxcc.py).
            "dxCountsEntities": True,
        },
        # "W/VE stations earn 1 for each MS County worked ... (82 possible)".
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
        },
    },
    # No bonus station, no activation bonus, no power multiplier - and the rules
    # say "No separate mode or power categories" outright.
    "bonuses": [],
    # "DX stations send signal report and Country", and MS stations count DX
    # entities individually (336 possible).
    "dxStyle": "prefix",
    "allowedModes": ["phone", "cw", "digital"],
    # The rules say NOTHING about county lines - neither permitting nor
    # forbidding. Shipped at 1 on the reading that silence is not permission;
    # open question. Contrast SCQP, which permits them without a cap.
    "maxSimultaneousCounties": 1,
    # "MS stations send signal report and County"
    "exchangeIncludesRST": True,
    # Inferred, not stated - see notes and msqp_rules.md section 12.
    "outStateWorksHomeStationsOnly": True,
    # "Starts: 1400z / 4 April 2026 - Ends: 0200z / 5 April 2026 - Duration: 12
    # Hours", corroborated by the activity page's "9:00 am - 9:00 pm CDT".
    "schedule": [{"start": "2026-04-04T14:00:00Z", "end": "2026-04-05T02:00:00Z"}],
    "counties": [{"abbr": a, "name": n} for a, n in sorted(counties.items(), key=lambda kv: kv[1])],
    "hubSpots": {
        "tableURL": "http://qsopartyhub.com/msqp-table.php",
        "postURL": "http://qsopartyhub.com/msqp-spots.php",
    },
    "notes": (
        "verified: partial - rules from the Vicksburg Amateur Radio Club's official '2026 MS QSO "
        "PARTY RULES' PDF and the sponsor's County Check List, both read verbatim 2026-07-26, "
        "with msqp.eqth.net confirming the date. Contest manager Malcolm W5XX; logs by e-mail by "
        "30 April. Note arrlmiss.org 404s a plain fetch of its own PDFs - they need a browser "
        "User-Agent and a Referer of the MSQP page. "
        "THE DATES ARE THE CLEANEST OF THIS RUN: the rules print both instants AND the duration - "
        "'Starts: 1400z / 4 April 2026, Ends: 0200z / 5 April 2026, Duration: 12 Hours' - all "
        "three agree, and the sponsor's activity page independently says 'April 4, 2026, 9:00 am "
        "to 9:00 pm CDT', which is exactly that window. Nothing here is derived. (A web search "
        "confidently placed this party on Sunday 5 April ending 0159Z; it is wrong on the day, "
        "the date and the end instant.) "
        "SSB 1 point, CW 2, RTTY 2, FT4/8 2. Multipliers are earned ONCE regardless of band or "
        "mode, stated in the heading. Mississippi stations count the 82 counties, the REMAINING 49 "
        "states - Mississippi itself is excluded - the 13 provinces and DX entities individually; "
        "everyone else counts the 82 counties. Eight bands, listed outright. No bonus stations, no "
        "activation bonus and no power multiplier: the sponsor says 'No separate mode or power "
        "categories'. Self-spotting is allowed for Mississippi mobile and portable stations only. "
        "THIS IS THE FIRST PARTY IN THIS APP THAT BUILDS FT4/FT8 IN ON PURPOSE - 'Incorporate "
        "FT4/8 digital modes into the event' is one of its three objectives, where Illinois, North "
        "Carolina, Oklahoma and Idaho all bar it - and that is where every limitation below comes "
        "from. "
        "KNOWN LIMITATION 1 - GRID SQUARE MULTIPLIERS ARE NOT COUNTED, AND THIS IS THE BIGGEST "
        "GAP. On FT4/8 the sponsor counts MS GRID SQUARES as multipliers: an out-of-state entrant "
        "earns one for each of up to NINE (EM41-44 and EM50-54) on top of the 82 counties, better "
        "than a tenth of the achievable total; a Mississippi entrant takes the total number of "
        "grid squares worked and divides by four, rounding up, with no cap. This app has no grid "
        "square multiplier class and no grid field on a QSO, so none of that is counted. ADD THEM "
        "BY HAND on the sponsor's scoring spreadsheet. KNOWN LIMITATION 2 - THE FT4/8 EXCHANGE IS "
        "A GRID SQUARE, NOT A LOCATION. 'ALL FT4/8 stations send signal report and Grid Square', "
        "while every other mode sends a county, state, province or country. This app has ONE "
        "exchange shape per party, so an FT4/8 contact cannot carry the token the sponsor asks "
        "for. A GRID SQUARE IS AT LEAST REFUSED NOW rather than silently credited: because DX "
        "stations here send a country prefix, a token like EM42 used to look like a valid prefix "
        "to this app's shape guess, and a Mississippi entrant who logged one was credited a DXCC "
        "entity that does not exist. Tokens are checked against the ARRL DXCC List (January 2026 "
        "edition, Resources/DXCC) as of 2026-08-01, so EM42 is an error - note that EM alone IS "
        "Ukraine's, which is why shape was never a safe test. TAKEN WITH LIMITATION 1, FT4/8 "
        "CONTACTS ARE BEST KEPT OUT OF THIS LOG and scored by "
        "hand - which is the reverse of the advice four other parties need, where FT8 is barred "
        "outright. KNOWN LIMITATION 3 - RTTY AND FT4/8 ARE SEPARATE MODES TO THE SPONSOR AND ONE "
        "MODE HERE. The sponsor's own example works one station on '20m CW, 20m SSB, 20m RTTY, 20m "
        "FT4/8' - four QSOs where this app sees three and flags the fourth as a duplicate. "
        "KNOWN LIMITATION 4 - PORTABLE AND MOBILE STATIONS SCORE DIFFERENTLY. 'Portable/Mobile: "
        "Final score will be the sum of the scores from each County operated' is a different "
        "scoring model rather than a bonus, and this app computes one score for the whole log. "
        "MISSISSIPPI MOBILES AND PORTABLES ONLY; every fixed and out-of-state entrant is exact. "
        "Cabrillo CONTEST value MS-QSO-PARTY per the WA7BNM registry - the rules print no header "
        "token and do not even require Cabrillo, since 'hand-written legible logs will be "
        "accepted'. Counties are 82 with uniform 3-letter codes and some of the densest clusters "
        "in this app: FOUR Ca-/Cl- counties where CAL is Calhoun, CLA is CLAY, CLB is Claiborne "
        "and CLK is Clarke; FOUR La- counties (Lafayette LAF, Lamar LAM, Lauderdale LAU, Lawrence "
        "LAW); FOUR Wa- counties (Walthall WAL, Warren WAR, Washington WAS, Wayne WAY); MAR "
        "Marshall against MRN Marion; and GRN Greene against GRE Grenada, one letter apart with "
        "the shorter-looking code on the longer name. JEF Jefferson and JDV Jefferson Davis are "
        "the same pair Louisiana has, with different codes. DES is DeSoto as one word, where "
        "Louisiana prints De Soto as two. "
        "OPEN QUESTIONS (why this is partial): (1) The four KNOWN LIMITATIONS above, all "
        "consequences of FT4/8 being a first-class mode here; limitation 1 changes the score for "
        "every entrant who works any FT4/8. (2) COUNTY LINES ARE NOT MENTIONED ANYWHERE in the "
        "rules - neither permitted nor forbidden - so a two-county entry is rejected here on the "
        "reading that silence is not permission, and because the Portable/Mobile scoring model "
        "reads as one county at a time. (3) No rule states whether stations outside Mississippi "
        "may work only Mississippi stations; the objectives and the multiplier list both point "
        "that way, and the restriction ships ON as for six other parties, so a stray non-MS "
        "contact is visibly flagged NO CREDIT. Confirm all three with W5XX at ARRL.NET."
    ),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(msqp, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"msqp.json: {len(counties)} counties, uniform 3-letter codes")
print(f"  clusters asserted: CAL/CLA/CLB/CLK, four La-, four Wa-, MAR/MRN, GRN/GRE")
print(f"  points: SSB 1, CW/RTTY/FT4-8 2; multipliers ONCE overall")
print(f"  bands: {len(BANDS)}, listed outright; no bonuses, no power categories")
print(f"  schedule: 1 window, 12 h - printed twice AND corroborated by the activity page")
print(f"  county lines: NOT MENTIONED - shipped at 1, open question")
print(f"  NOT shipped: grid-square multipliers, the FT4/8 grid exchange,")
print(f"    the RTTY-vs-FT4/8 mode split, and per-county mobile scoring")
