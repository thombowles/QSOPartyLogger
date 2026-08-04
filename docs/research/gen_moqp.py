#!/usr/bin/env python3
"""Generate moqp.json from BEARS-St. Louis's own 2026 documents.

Sources (committed alongside this script, so the run is reproducible):
  moqp_rules_2026.txt — pdftotext -layout of moqp-2026-rules-final.pdf, header
                        "2026 Missouri QSO Party Rules". THE AUTHORITY.
  moqp_counties.txt   — the sponsor's "Missouri County Listing", 115 entities in
                        three columns of "NAME  CODE"
  moqp_page.txt       — the MOQP home page, which publishes FUTURE dates
  moqp_rules.md       — full rules research; all fetched 2026-07-26

Sponsor: Boeing Employees Amateur Radio Society - St. Louis (WØMA).

RETRIEVAL NOTE: the site's own "2026 MOQP Rules" link points at
./results/thisyear/moqp-2026-rules-final.pdf, which 403s. The identical file is
served from ./results/2026/reports/ . A session stopping at the advertised link
would conclude the rules were unavailable and fall back to the 2025 edition,
which is still the top search result.

THE 2026 DATE DOES NOT FOLLOW THE USUAL FORMULA, and the sponsor says why: "For
2026 due to the Easter weekend the contest is on 11-12th of April." MOQP normally
runs the first full weekend of April - which in 2026 would be the 4th-5th, the
same weekend as Louisiana and Mississippi. Deriving this one from the formula
would land a week early.

WHAT DELIBERATELY DOES NOT SHIP - see moqp_rules.md section 13:
  * the 40/80 m daytime bonus: +1 point per QSO on two named bands inside two
    six-hour windows, capped at 250. BonusRule has no band predicate, no time
    predicate and no cap, and this one adds to QSO POINTS rather than to the
    post-multiplication total, so it compounds.
  * the 100-point bonus for submitting a Cabrillo log electronically, which is
    not about QSOs at all.

Usage:  python3 gen_moqp.py        (run from docs/research/)
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "moqp.json")
RULES = os.path.join(HERE, "moqp_rules_2026.txt")
COUNTIES = os.path.join(HERE, "moqp_counties.txt")
PAGE = os.path.join(HERE, "moqp_page.txt")


def read(path):
    s = open(path, encoding="utf-8", errors="replace").read()
    for a, b in [("’", "'"), ("‘", "'"), ("“", '"'), ("”", '"'),
                 ("–", "-"), ("—", "-"), (" ", " "), ("​", ""),
                 ("Ø", "0")]:
        s = s.replace(a, b)
    return s


rules = re.sub(r"\s+", " ", read(RULES))
page = re.sub(r"\s+", " ", read(PAGE))
counties_txt = read(COUNTIES)

# --- Counties: three columns of "Name  CODE". Names may be several words
# ("Cape Girardeau", "St. Louis County"), so anchor on the CODE. ---
PAIR = re.compile(r"([A-Z][A-Za-z.' ]*?[A-Za-z.])\s{2,}([A-Z]{3})(?=\s|$)", re.M)
counties = {}
for name, abbr in PAIR.findall(counties_txt):
    name = " ".join(name.split())
    if name in ("NAME", "CODE") or abbr == "COD":
        continue
    if abbr in counties and counties[abbr] != name:
        sys.exit(f"MOQP conflicting names for {abbr}: {counties[abbr]!r} vs {name!r}")
    counties[abbr] = name

assert len(counties) == 115, f"expected 115 MO entities, got {len(counties)}: {sorted(counties)}"
assert len(set(counties.values())) == 115, "MO entity names not unique"
assert {len(a) for a in counties} == {3}, "MO codes are uniformly 3 letters"
assert "Missouri counties (115 maximum)" in rules, "the sponsor's own count changed"

# THE TRAP THIS PARTY TURNS ON: Missouri has 114 counties PLUS the independent
# City of St. Louis. STL and SLC share all three letters in a different order.
assert counties.get("STL") == "St. Louis City", \
    f"STL should be St. Louis City, got {counties.get('STL')!r}"
assert counties.get("SLC") == "St. Louis County", \
    f"SLC should be St. Louis County, got {counties.get('SLC')!r}"

for abbr, name in [
    # five C-l codes, none obvious
    ("CAL", "Callaway"), ("CLA", "Clay"), ("CLK", "Clark"), ("CLN", "Clinton"),
    ("CWL", "Caldwell"),
    # four B counties; the two that contract are not the guessable ones
    ("BAR", "Barry"), ("BTN", "Barton"), ("BAT", "Bates"), ("BTR", "Butler"),
    # four M counties
    ("MAC", "Macon"), ("MAD", "Madison"), ("MAR", "Marion"), ("MCD", "McDonald"),
    # the S block - eight codes, five of them SC*/ST*
    ("SAL", "Saline"), ("SCH", "Schuyler"), ("SCL", "St. Clair"), ("SCO", "Scott"),
    ("SCT", "Scotland"), ("STC", "St. Charles"), ("STF", "St. Francois"),
    ("STG", "St. Genevieve"),   # sponsor's spelling; the county is Ste. Genevieve
    # contractions
    ("CPG", "Cape Girardeau"), ("CHN", "Chariton"), ("LCN", "Lincoln"),
    ("HLT", "Holt"), ("HWL", "Howell"), ("IRN", "Iron"), ("KNX", "Knox"),
]:
    assert counties.get(abbr) == name, f"{abbr} should be {name!r}, got {counties.get(abbr)!r}"
for absent in ["SAI", "STE", "CALD", "BART"]:
    assert absent not in counties, f"{absent} is not an MOQP abbreviation"

# --- Bands: listed outright, ten of them. ---
BANDS = ["160m", "80m", "40m", "20m", "15m", "10m", "6m", "2m", "1.25m", "70cm"]
assert "160M, 80M, 40M, 20M, 15M, 10M, 6M, 2M, 1.25M, and 70cm" in rules, \
    "the band list changed"
for excluded in ["60m", "30m", "17m", "12m"]:
    assert excluded not in BANDS

# --- The rule sentences this file encodes. ---
for quote in [
    # Dates, and the sponsor's own reason for moving them
    "For 2026 due to the Easter weekend the contest is on 11-12th of April",
    "1400 UTC Saturday",
    "0400 UTC Sunday",
    "2000 UTC Sunday",
    # Exchange
    "Missouri stations will provide call sign, RST, and a three letter county code",
    "Non-Missouri stations will provide call sign, RST, and their US state",
    'DX stations will provide callsign, RST, and the exchange "DX"',
    # Points
    "Valid phone contacts equals one point each",
    "Valid CW contacts equals two points each",
    "Valid digital contacts equals two points each",
    # Multipliers
    "The multipliers for Missouri stations are Missouri counties (115 maximum), US states (49",
    "An additional multiplier of the value of one will be added if at least one DX station is worked",
    "The multipliers for Non-Missouri and DX stations are Missouri Counties (115 maximum)",
    "makes 50 or more valid contacts from a county or county lines",
    # Rule 3's qualifying classes. The shipped set adds EXPEDITION on the
    # county-lines reading (see the notes' OPEN QUESTION 1), so a revision
    # that names expeditions outright - or drops portables - must fail here.
    "Any mobile or portable category entry",
    # Dupes
    "once per mode on each band per Missouri county",
    # County lines
    "Expedition stations may be located at the intersection of two or more counties",
    "County line operations must log these contacts as separate QSOs",
    # Scoring
    "multiplying the total number of valid contact points by the total number of multipliers",
    # Logs
    "No paper logs will be accepted",
]:
    assert quote in rules, f"the 2026 rules no longer contain: {quote!r}"

assert "2026 Missouri QSO Party Rules" in rules, \
    "this is not the 2026 edition - re-verify every rule before shipping it"

# The two bonuses that DO ship, and the two that do not.
assert "valid contact with the W0MA special event station will count as a single" in rules
assert "valid contact with special event station K0GQ will count as a single" in rules
assert "A 100 point bonus will be awarded for successfully submitting a Cabrillo log" in rules, \
    "the log-submission bonus changed - revisit KNOWN LIMITATION 2"
assert "on the 40 and 80 meter bands will count as an additional point each" in rules, \
    "the 40/80 m daytime bonus changed - revisit KNOWN LIMITATION 1"
assert "Up to 250-point bonus can be added to the total score" in rules

# The sponsor's published future dates confirm the formula resumes after Easter.
for future in ["2027: Apr 3 and 4", "2028: Apr 1 and 2", "2029: Apr 7 and 8"]:
    assert future in page, f"the sponsor's future-date list changed: {future!r}"

moqp = {
    "schemaVersion": 1,
    "id": "moqp",
    "name": "Missouri QSO Party",
    # Cabrillo is required - and even paid for - but the rules print no CONTEST:
    # token; WA7BNM registry (Article 1's codified exception).
    "cabrilloContest": "MO-QSO-PARTY",
    "homeState": "MO",
    "countyAbbrLength": 3,
    # "160M, 80M, 40M, 20M, 15M, 10M, 6M, 2M, 1.25M, and 70cm" - ten, listed
    # outright, joint-largest in the repo with WIQP and VAQP.
    "validBands": BANDS,
    # phone 1, CW 2, digital 2.
    "points": {"phone": 1, "cw": 2, "digital": 2},
    # "once per mode on each band per Missouri county"
    "dupeScope": "bandMode",
    "multipliers": {
        # "Missouri counties (115 maximum), US states (49 maximum), and Canadian
        # provinces and territories (13 maximum) ... plus one for any DX."
        "inState": {
            "classes": ["county", "state", "province", "dx"],
            # "US states (49 MAXIMUM)" - 49, not 50, so Missouri is excluded.
            "homeStateCountsViaCounty": False,
            # The stated maxima settle the scope: a per-band count could not have
            # a maximum of 115.
            "countScope": "once",
            # Rule 3: "Any mobile or portable category entry that makes 50 or
            # more valid contacts from a county or county lines will be given
            # the multiplier for that county or counties."
            "activatedCountyMultiplier": {
                # THE HIGHEST THRESHOLD OF THE FIVE by a factor of five - SCQP
                # and NCQP 1, TnQP and VAQP 10, this 50.
                "minCount": 50,
                # "50 or more valid CONTACTS", not stations. VAQP's rule looks
                # similar and counts distinct callsigns; this one does not.
                "countUnit": "qsos",
                # The stated maximum of 115 is a whole-log count, so the
                # activation is scoped the same way everything else here is.
                "countScope": "once",
                # RULE 3 NAMES "mobile or portable" AND MOQP DEFINES A THIRD
                # ROVING CLASS, Missouri Expedition, which it does not name.
                # EXPEDITION SHIPS COVERED ANYWAY: rule 3 pays "from a county or
                # COUNTY LINES", and the expedition is the class MOQP permits at
                # "the intersection of two or more counties". Recorded as an
                # OPEN QUESTION, because the literal list is two classes and
                # this is three - the one place in these five parties where the
                # shipped set is wider than the sponsor's sentence.
                "categories": ["MOBILE", "PORTABLE", "EXPEDITION"],
                # BY ARITHMETIC, as with NCQP. "Missouri counties (115 MAXIMUM)"
                # is exactly the entity list - 114 counties plus St. Louis City
                # - so a county both operated from and worked cannot make 116.
                "notOtherwiseWorked": True,
            },
        },
        # "Missouri Counties (115 maximum) worked."
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
        },
    },
    # Two of the sponsor's five bonus rules fit; see notes for the other three.
    "bonuses": [
        {"type": "workStation", "call": "W0MA", "points": 100, "scope": "once"},
        {"type": "workStation", "call": "K0GQ", "points": 100, "scope": "once"},
    ],
    # 'the exchange "DX"', and one multiplier for any and all DX worked.
    "dxStyle": "token",
    "allowedModes": ["phone", "cw", "digital"],
    # "the intersection of two or more counties", with NO stated cap - so this is
    # this app's own maximum rather than a sponsor's number. Open question.
    "maxSimultaneousCounties": 4,
    # "call sign, RST, and a three letter county code"
    "exchangeIncludesRST": True,
    # Inferred, not stated - see notes.
    "outStateWorksHomeStationsOnly": True,
    # "For 2026 due to the Easter weekend the contest is on 11-12th of April."
    # NOT the usual first full weekend, which would have been 4-5 April.
    "schedule": [
        {"start": "2026-04-11T14:00:00Z", "end": "2026-04-12T04:00:00Z"},
        {"start": "2026-04-12T14:00:00Z", "end": "2026-04-12T20:00:00Z"},
    ],
    "counties": [{"abbr": a, "name": n} for a, n in sorted(counties.items(), key=lambda kv: kv[1])],
    "hubSpots": {
        "tableURL": "http://qsopartyhub.com/moqp-table.php",
        "postURL": "http://qsopartyhub.com/moqp-spots.php",
    },
    "notes": (
        "verified: partial - rules from the Boeing Employees Amateur Radio Society-St. Louis's "
        "official '2026 Missouri QSO Party Rules' PDF and the sponsor's Missouri County Listing, "
        "both read verbatim 2026-07-26. Electronic Cabrillo only; no paper logs. "
        "RETRIEVAL NOTE: the site's own '2026 MOQP Rules' link 403s - it points at "
        "./results/thisyear/ - while the identical file is served from ./results/2026/reports/ . "
        "A session stopping at the advertised link would have concluded the rules were "
        "unavailable and fallen back to the 2025 edition, which is still the top search result. "
        "THE 2026 DATE DOES NOT FOLLOW THE USUAL FORMULA AND THE SPONSOR SAYS WHY: 'For 2026 due "
        "to the Easter weekend the contest is on 11-12th of April.' Missouri normally runs the "
        "FIRST full weekend of April, which in 2026 would have been the 4th and 5th - the same "
        "weekend as Louisiana and Mississippi - so deriving this date from the formula would land "
        "a week early. Twenty hours in two windows: 1400Z Saturday 11 April to 0400Z Sunday, then "
        "1400Z to 2000Z Sunday 12 April. The sponsor publishes future dates and they confirm the "
        "formula resumes - 3-4 April 2027, 1-2 April 2028, 7-8 April 2029 - which are recorded "
        "here but deliberately NOT put in the schedule. "
        "Phone 1 point, CW 2, digital 2. Multipliers count ONCE overall, which the sponsor's own "
        "maxima settle - a per-band count could not have a maximum of 115. Missouri stations "
        "count the 115 counties, 49 states (Missouri itself is excluded), the 13 provinces and "
        "territories, and ONE multiplier for any and all DX worked; everyone else counts the 115. "
        "DC is never mentioned and stays its own multiplier. Ten bands, 160 m through 70 cm, "
        "listed outright - the joint-largest list here with Wisconsin and Virginia. County-line "
        "operation is allowed at 'the intersection of two or more counties' with each contact "
        "logged as a separate QSO, which is what this app writes. "
        "THE SPONSOR HAS FIVE BONUS RULES AND ONLY TWO OF THEM FIT. Modelled: WOMA and KOGQ each "
        "pay a single 100-point bonus for at least one valid contact. NOT modelled, and both "
        "affect your claimed score: "
        "KNOWN LIMITATION 1 - THE 40 AND 80 METRE DAYTIME BONUS IS NOT APPLIED. 'Any valid "
        "contacts made between the hours of 1400 UTC Saturday to 2000 UTC Saturday and 1400 UTC "
        "Sunday to 2000 UTC Sunday on the 40 and 80 meter bands will count as an additional point "
        "each. Up to 250-point bonus.' That is a per-QSO bonus conditioned on BAND and on a TIME "
        "WINDOW narrower than the contest, with a CAP - three things this app's bonus rules "
        "cannot express - and it adds to QSO POINTS rather than to the total, so it is multiplied "
        "by your multipliers as well. EVERY ENTRANT IS AFFECTED, since 40 and 80 m in daylight "
        "are where most of this contest happens. TO CORRECT BY HAND: count your 40 m and 80 m "
        "QSOs made in those two six-hour windows, cap the total at 250, and add it to your QSO "
        "points BEFORE multiplying. KNOWN LIMITATION 2 - the flat 100-point bonus for submitting "
        "a Cabrillo log electronically is not applied either, because it is not about contacts at "
        "all. Add 100 to your claimed score. "
        "A ROVING MISSOURI ENTRY COUNTS EACH COUNTY IT MAKES 50 CONTACTS FROM. Rule 3: 'Any "
        "mobile or portable category entry that makes 50 or more valid contacts from a county or "
        "county lines will be given the multiplier for that county or counties.' The app now "
        "counts it. FIFTY IS THE HIGHEST THRESHOLD OF ANY PARTY WITH THIS RULE - five times "
        "TnQP's and VaQP's ten - and it counts CONTACTS, not distinct stations the way VaQP's "
        "does. A county that was also WORKED counts once, not twice: 'Missouri counties (115 "
        "maximum)' is exactly the entity list, so 116 is not available. Out-of-state entrants are "
        "unaffected. "
        "Cabrillo CONTEST value MO-QSO-PARTY per the WA7BNM registry - the rules require Cabrillo, "
        "and even pay 100 points for it, but never print the header token. "
        "THE ENTITY LIST IS 115, NOT 114: Missouri's counties PLUS the independent City of St. "
        "Louis. THE TRAP THIS PARTY TURNS ON IS STL versus SLC - St. Louis CITY is STL and St. "
        "Louis COUNTY is SLC, two adjacent and differently governed entities whose codes share "
        "all three letters in a different order. Watch also the five C-l codes (Callaway CAL, "
        "Clay CLA, Clark CLK, Clinton CLN, Caldwell CWL), the four B counties where the two that "
        "contract are Barton BTN and Butler BTR rather than the guessable ones, and the eight-code "
        "S block (Saline SAL, Schuyler SCH, St. Clair SCL, Scott SCO, Scotland SCT, St. Charles "
        "STC, St. Francois STF, St. Genevieve STG). The sponsor prints 'St. Genevieve' where the "
        "county is officially Ste. Genevieve; it ships as printed. "
        "OPEN QUESTIONS (why this is partial): (1) WHETHER AN EXPEDITION EARNS THE "
        "COUNTY-ACTIVATION MULTIPLIER. Rule 3 names 'any mobile or portable category entry', and "
        "MOQP defines a third roving class it does not name there - Missouri Expedition. "
        "Expedition ships COVERED, because rule 3 pays 'from a county or COUNTY LINES' and the "
        "expedition is the class MOQP permits at 'the intersection of two or more counties'. It "
        "is the one place in this rule where what ships is wider than the sponsor's sentence, so "
        "an expedition entrant may be claiming one multiplier per activated county too many; "
        "confirm with BEARS-St. Louis before submitting. (2) The county-line limit. The rules "
        "permit 'two or more counties' and cap nothing, so this ships on this app's own maximum "
        "of four, which is a default rather than a sponsor's number. "
        "(3) No rule states whether stations outside Missouri may work only Missouri stations; the "
        "objective points that way and out-of-state multipliers are MO counties only, but the same "
        "objective also offers Missouri stations 'an opportunity to work other states and "
        "countries'. The restriction ships ON as for seven other parties, so a stray non-Missouri "
        "contact is visibly flagged NO CREDIT."
    ),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(moqp, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"moqp.json: {len(counties)} entities = 114 counties + the City of St. Louis")
print(f"  STL St. Louis CITY vs SLC St. Louis COUNTY - the trap, asserted")
print(f"  points: phone 1, CW/digital 2; multipliers ONCE overall (maxima 115/49/13)")
print(f"  bands: {len(BANDS)} - joint-largest in the repo")
print(f"  bonuses: W0MA 100 once + K0GQ 100 once (2 of the sponsor's FIVE rules)")
print(f"  schedule: 2 windows, 14 h + 6 h = 20 h, MOVED A WEEK FOR EASTER")
print(f"  activation mults: mobile/portable/expedition, 50 contacts, once, forfeited if worked")
print(f"  NOT shipped: the 40/80 m daytime +1/QSO bonus capped at 250,")
print(f"    and the 100-point Cabrillo-submission bonus")
