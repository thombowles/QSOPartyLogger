#!/usr/bin/env python3
"""Generate mnqp.json from the Minnesota Wireless Association's own documents.

Sources (committed alongside this script, so the run is reproducible):
  mnqp_rules_2026_rev31.txt — pdftotext -layout of MNQP_Contest_Rules rev 31.pdf,
                              footer "Rev 31 - December 31, 2025". THE AUTHORITY.
  mnqp_rules_2027.txt       — pdftotext -layout of MNQP_2027_Contest_Rules_A.pdf,
                              footer "June 8, 2026". Kept ONLY so the Article 20
                              diff can be asserted; NOT the authority.
  mnqp_counties.txt         — pdftotext -layout of MNQP-MN-Counties.pdf, the
                              sponsor's official county multiplier list
  mnqp_page.txt             — the MNQP main page
  mnqp_rules.md             — full rules research; all fetched 2026-07-26

Sponsor: Minnesota Wireless Association (W0AA), mnqp-committee@w0aa.org.

RETRIEVAL NOTES, both of which cost real time:

  (1) w0aa.org NO LONGER PUBLISHES THE 2026 RULES. The live rules page says the
      rules "were last updated for the 2027 QSO Party" and links the 2027 PDF.
      Rev 31 came from the Wayback Machine snapshot 20260209103319 - two days
      after the 2026 contest - whose copy of the page says "last updated for the
      2026 QSO Party" and links exactly this file.

  (2) w0aa.org 404s its own PDFs to a plain fetch. They need
      -e https://www.w0aa.org/mnqp-rules/ (a Referer). A session concluding "the
      rules PDF is gone" would be wrong.

USING THE 2027 DOCUMENT WOULD HAVE BEEN WRONG IN FOUR PLACES - it flags its own
changes as "NEW 2027": multipliers move to once-per-mode, in-state county
multipliers stop counting for MN stations (and MN itself starts counting), CW
goes from 2 points to 3, and rovers gain 2-county operation. The assertions
below pin the 2026 values AND the 2027 markers, so that re-running this script
against a future edition fails loudly instead of silently rescoring the party.

The county list is parsed TWICE and the two parses must agree: the sponsor's PDF
prints all 87 counties "Alphabetical by County" and again "Alphabetical by
Designator", which is two independent orderings of the same data in one document.

Usage:  python3 gen_mnqp.py        (run from docs/research/)
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "mnqp.json")
RULES = os.path.join(HERE, "mnqp_rules_2026_rev31.txt")
RULES_2027 = os.path.join(HERE, "mnqp_rules_2027.txt")
COUNTIES = os.path.join(HERE, "mnqp_counties.txt")
PAGE = os.path.join(HERE, "mnqp_page.txt")


def read(path):
    s = open(path, encoding="utf-8").read()
    # Normalise the typography the sponsor's PDFs use, so every quoted assertion
    # below can be written with plain ASCII: curly quotes, en/em dashes, and the
    # slashed O the club spells its own callsign with (WØAA).
    for a, b in [("’", "'"), ("‘", "'"), ("“", '"'), ("”", '"'),
                 ("–", "-"), ("—", "-"), ("Ø", "0")]:
        s = s.replace(a, b)
    return s


rules = re.sub(r"\s+", " ", read(RULES))
rules_2027 = re.sub(r"\s+", " ", read(RULES_2027))
page = re.sub(r"\s+", " ", read(PAGE))
counties_txt = read(COUNTIES)

PAIR = re.compile(r"([A-Z][A-Za-z.'&\s]*?[A-Za-z.])\s{2,}([A-Z]{3})(?=\s|$)", re.M)


def parse_table(block, label):
    # Drop the table's own sub-heading ("Alphabetical by County" / "…by
    # Designator"). Without this it runs into the first county name, because a
    # name may legitimately contain spaces and newlines ("Lake of the Woods").
    block = re.sub(r"(?m)^\s*Alphabetical by \w+\s*$", "", block)
    found = {}
    for name, abbr in PAIR.findall(block):
        name = " ".join(name.split())
        if abbr in found and found[abbr] != name:
            sys.exit(f"MNQP {label}: conflicting names for {abbr}: "
                     f"{found[abbr]!r} vs {name!r}")
        found[abbr] = name
    return found


# The document prints the county list twice, in two different orders. Split on
# the shared heading and cut each section off at the states table that follows.
sections = counties_txt.split("87 - Minnesota Counties and 3 letter designators")[1:]
if len(sections) != 2:
    sys.exit(f"MNQP: expected 2 county tables in the sponsor's PDF, found {len(sections)}")

by_county = parse_table(sections[0].split("50 - US States")[0], "by-county table")
by_designator = parse_table(sections[1].split("50 - US States")[0], "by-designator table")

assert len(by_county) == 87, f"expected 87 MN counties by county, got {len(by_county)}"
assert len(by_designator) == 87, f"expected 87 by designator, got {len(by_designator)}"
assert by_county == by_designator, (
    "the sponsor's two orderings of its own county list disagree: "
    f"{ {k: (by_county.get(k), by_designator.get(k)) for k in set(by_county) ^ set(by_designator)} }"
)
counties = by_county
assert len(set(counties.values())) == 87, "MN county names not unique"
assert {len(a) for a in counties} == {3}, "MN designators are uniformly 3 letters"

# Irregular designators worth pinning - none of these is the naive first three
# letters, and several are one letter apart from a neighbour. See mnqp_rules.md 13.
for abbr, name in [
    ("CRL", "Carlton"), ("CRV", "Carver"), ("CRO", "Crow Wing"),
    ("KNB", "Kanabec"), ("KND", "Kandiyohi"),
    ("MRS", "Marshall"), ("MRT", "Martin"),
    ("STL", "St Louis"),        # printed without a period
    ("OTT", "Ottertail"),       # printed as one word
    ("LKW", "Lake of the Woods"), ("LAK", "Lake"),
    ("RDL", "Red Lake"), ("RDW", "Redwood"),
    ("LAC", "Lac Qui Parle"), ("LES", "Le Sueur"), ("YEL", "Yellow Medicine"),
    ("BLU", "Blue Earth"), ("BIG", "Big Stone"), ("MIL", "Mille Lacs"),
    ("WSC", "Waseca"), ("WSH", "Washington"), ("WAT", "Watonwan"),
]:
    assert counties.get(abbr) == name, f"{abbr} should be {name}, got {counties.get(abbr)!r}"
assert "CAR" not in counties, "CAR is not a designator here - Carlton is CRL, Carver CRV"
assert "KAN" not in counties, "KAN is not a designator here - Kanabec is KNB, Kandiyohi KND"

# --- Bands: "160m - 10m (excluding WARC bands)", confirmed row for row by the
# suggested-frequency table, which carries exactly one frequency per band. ---
BANDS = ["160m", "80m", "40m", "20m", "15m", "10m"]
assert "HF: 160m - 10m (excluding WARC bands)" in rules, "the band sentence changed"
assert "restricted to 160 through 10 meters (exclusive of WARC Bands)" in rules
assert "CW: 1.850, 3.550, 7.050, 14.050, 21.050, 28.050" in rules, \
    "the CW suggested-frequency row changed - re-check the band list against it"
assert "SSB: 1.870, 3.850, 7.250, 14.270, 21.350, 28.450" in rules
for f in ["1.850", "3.550", "7.050", "14.050", "21.050", "28.050"]:
    assert f in rules
assert len(BANDS) == 6, "six bands, one per suggested frequency"
for excluded in ["60m", "30m", "17m", "12m", "6m", "2m", "1.25m", "70cm"]:
    assert excluded not in BANDS, f"{excluded} is not an MNQP band - HF only"

# --- The 2026 rule sentences this file encodes. ---
for quote in [
    # Time
    "Contest runs on the first Saturday of February from 1400 through 2359 UTC",
    "(8 AM through 5:59 PM CST)",
    # QSO rules / scope of credit
    "MN stations work everyone; all other W/VE & DX work MN stations",
    "Work stations once per band & mode",
    # Modes
    "Phone (SSB, DSB, FM, AM all count as Phone) CW - only",
    "A station may be worked once on CW and once on Phone",
    # Exchange - name, and no signal report anywhere
    "MN Stations: First name & county (three letter designator)",
    "W/VE Stations: First name and state / province (two letter abbreviation)",
    "DX Stations: First name only. Section should be logged as DX",
    "Use only one name throughout the contest",
    # Multipliers, with the sponsor's own totals
    "87 Minnesota counties, 49 states (does not include Minnesota), 1 District of "
    "Columbia, 10 Canadian provinces, 3 Canadian Territories, and 1 DX; 151 maximum",
    "receive 1 multiplier for working a DX station",
    "Multipliers for W/VE and DX (outside Minnesota): MN counties: 87 maximum",
    "Multipliers count once overall - not once per band or mode",
    # Scoring
    "Score 2 QSO points for all QSO's, i.e. Phone and CW QSO's equal 2 QSO points each",
    "The final score is QSO points total times multiplier total",
    # County lines: forbidden
    "No station may claim simultaneous operation in more than one county, state, or province",
    "must move to a location clearly within the new county before claiming a county change",
    # Cabrillo, and the name column this app cannot fill
    "Cabrillo format is required",
    "ex1: Name",
]:
    assert quote in rules, f"rev 31 no longer contains: {quote!r}"

assert "Rev 31 - December 31, 2025" in rules, \
    "this is not rev 31 any more - re-verify every rule before shipping it"

# The sponsor's stated multiplier totals must equal what the schema will produce.
# 87 counties + 50 state-class tokens (51 accepted, less the home state MN)
# + 13 provinces + 1 DX = 151.
assert 87 + (51 - 1) + 13 + 1 == 151, "the multiplier arithmetic no longer reconciles"

# --- Article 20: pin the 2027 changes, so a future re-verification cannot apply
# them by accident and cannot miss them either. See mnqp_rules.md section 14. ---
for marker in [
    "NEW 2027 - Multipliers may be worked once on each mode",
    "In state county multipliers no longer count for MN stations",
    "50 states (includes Minnesota)",
    "Phone QSO's equal 2 points each",
    "CW QSO's equal 3 QSO points each",
    "Rovers may operate simultaneously from up to 2 counties",
]:
    assert marker in rules_2027, (
        f"the 2027 edition no longer says {marker!r} - re-read BOTH editions before "
        "trusting the diff in mnqp_rules.md section 14"
    )
for not_in_2026 in ["once on each mode", "50 states (includes Minnesota)"]:
    assert not_in_2026 not in rules, \
        f"rev 31 now contains {not_in_2026!r} - the wrong file is being read as 2026"

# --- The date. The rules say "through 2359 UTC", the main page says 2400 UTC /
# 6:00 PM CST; inclusive of the 2359 minute these are the same instant. ---
assert "Saturday, February 7th, 2026" in page
assert "Hours: 1400 UTC (8:00 AM CST) to 2400 UTC (6:00 PM CST)" in page, \
    "the main page's stated hours changed - re-derive the schedule"
assert "The Minnesota QSO Party is always the first Saturday in February" in page
assert "February 6, 2027" in page, "the sponsor's published future dates moved"

mnqp = {
    "schemaVersion": 1,
    "id": "mnqp",
    "name": "Minnesota QSO Party",
    # Cabrillo is REQUIRED but the sponsor prints no CONTEST: token;
    # WA7BNM registry entry 238 (Article 1's codified exception).
    "cabrilloContest": "MN-QSO-PARTY",
    "homeState": "MN",
    "countyAbbrLength": 3,
    # "HF: 160m - 10m (excluding WARC bands)" - no VHF/UHF at all, unlike VTQP.
    "validBands": BANDS,
    # "Score 2 QSO points for all QSO's". Digital is not a legal mode; the value
    # is set equal so a future edition adding digital cannot inherit a guess.
    "points": {"phone": 2, "cw": 2, "digital": 2},
    # "Work stations once per band & mode."
    "dupeScope": "bandMode",
    "multipliers": {
        # "87 Minnesota counties, 49 states (does not include Minnesota), 1
        # District of Columbia, 10 Canadian provinces, 3 Canadian Territories,
        # and 1 DX; 151 maximum."
        "inState": {
            "classes": ["county", "state", "province", "dx"],
            # "49 states (DOES NOT include Minnesota)" - stated outright, in the
            # negative, which is rare. The 2027 edition reverses it.
            "homeStateCountsViaCounty": False,
            # "Multipliers count once overall - not once per band or mode."
            "countScope": "once",
            # No numeric cap: "1 DX" falls out of dxStyle "token", since every DX
            # contact yields the single value DX.
        },
        # "Multipliers for W/VE and DX (outside Minnesota): MN counties: 87 maximum."
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
        },
    },
    # No bonus station, no bonus points, no activation bonus. Awards only.
    "bonuses": [],
    # "DX Stations: First name only. Section should be logged as DX." One
    # multiplier for all DX, which is exactly what the token style produces.
    "dxStyle": "token",
    # "Phone (SSB, DSB, FM, AM all count as Phone) / CW - only". No digital.
    "allowedModes": ["phone", "cw"],
    # "No station may claim simultaneous operation in more than one county,
    # state, or province." County-line sitting is FORBIDDEN, as in ALQP.
    "maxSimultaneousCounties": 1,
    # NO stateAliases, deliberately: the sponsor counts "1 District of Columbia"
    # as a multiplier SEPARATE from the 50 states, so DC must stay itself.
    # The exchange is name + location. There is no signal report at all.
    "exchangeIncludesRST": False,
    # "MN stations work everyone; all other W/VE & DX work MN stations."
    "outStateWorksHomeStationsOnly": True,
    # "first Saturday of February from 1400 through 2359 UTC" (rules) and
    # "1400 UTC to 2400 UTC (6:00 PM CST)" (main page) - the same instant, since
    # "through 2359" includes that minute. 7 February 2026, ten hours.
    "schedule": [{"start": "2026-02-07T14:00:00Z", "end": "2026-02-08T00:00:00Z"}],
    "counties": [{"abbr": a, "name": n} for a, n in sorted(counties.items(), key=lambda kv: kv[1])],
    "hubSpots": {
        "tableURL": "http://qsopartyhub.com/mnqp-table.php",
        "postURL": "http://qsopartyhub.com/mnqp-spots.php",
    },
    "notes": (
        "verified: partial - rules from the Minnesota Wireless Association's OFFICIAL 2026 "
        "document, 'MNQP_Contest_Rules rev 31.pdf', footer 'Rev 31 - December 31, 2025', read "
        "verbatim 2026-07-26, plus the sponsor's official county multiplier list PDF and the MNQP "
        "main page. Counties are generated by gen_mnqp.py, which parses the sponsor's county list "
        "TWICE - the PDF prints all 87 alphabetically by county AND alphabetically by designator - "
        "and requires the two orderings to agree exactly. "
        "PROVENANCE NOTE WORTH KEEPING: W0AA.ORG NO LONGER PUBLISHES THE 2026 RULES. The live "
        "rules page says the rules were 'last updated for the 2027 QSO Party' and links the 2027 "
        "PDF, which flags FOUR of its own changes as 'NEW 2027' - multipliers move to once per "
        "mode, in-state county multipliers stop counting for MN stations while Minnesota itself "
        "starts counting, CW goes from 2 points to 3, and rovers gain two-county operation. "
        "Building this party from the live document would have been wrong in all four. Rev 31 was "
        "recovered from the Wayback Machine snapshot of 2026-02-09, two days after the contest, "
        "whose copy of the rules page reads 'last updated for the 2026 QSO Party'. Note also that "
        "the sponsor's own changelog sentence is stale and understates the revision badly: both "
        "the 2026 and 2027 versions of the page carry the identical line 'Changed entry deadline "
        "to seven days after the contest'. And w0aa.org 404s its own PDFs unless the request "
        "carries a Referer of https://www.w0aa.org/mnqp-rules/. "
        "Ten hours in one window, 1400Z to 2400Z Saturday 7 February 2026. The rules say 'from "
        "1400 through 2359 UTC (8 AM through 5:59 PM CST)' and the main page says '1400 UTC (8:00 "
        "AM CST) to 2400 UTC (6:00 PM CST)'; inclusive of the 2359 minute these are the same "
        "instant, and both are internally consistent against CST. The sponsor publishes future "
        "dates - 6 February 2027, 5 February 2028, 3 February 2029 - which are recorded here but "
        "deliberately NOT put in the schedule, since Article 19 ships the target year only. "
        "TWO POINTS FOR EVERY QSO, phone and CW alike, stated in those words. Multipliers count "
        "ONCE OVERALL - not per band, not per mode, the only bundled party with that scope on "
        "both sides. Minnesota stations count 87 MN counties + 49 states (explicitly NOT "
        "Minnesota) + DC + 13 provinces and territories + one DX, for the sponsor's stated 151 "
        "maximum, and this app reproduces that total exactly. Everyone else counts the 87 MN "
        "counties, for 87. DC IS ITS OWN MULTIPLIER HERE and is deliberately not aliased to MD, "
        "unlike VTQP and MDC. All DX is worth ONE multiplier however many entities are worked, "
        "which is what the DX token style produces. HF only - 160 through 10 m excluding WARC, "
        "six bands, confirmed one-for-one against the sponsor's suggested-frequency table; no "
        "VHF or UHF at all. COUNTY-LINE OPERATION IS FORBIDDEN: 'No station may claim "
        "simultaneous operation in more than one county, state, or province', so entering two "
        "counties is rejected, as in ALQP. Minnesota entrants are capped at 100 watts by class "
        "(5 W for QRP) while W/VE classes run to 1500 W - an eligibility rule, not a scoring one. "
        "No bonus stations and no final-score multiplier of any kind. "
        "KNOWN LIMITATION 1 - THE EXCHANGE IS A NAME AND THIS APP CANNOT LOG IT, WHICH BLOCKS "
        "SUBMISSION. MNQP exchanges a FIRST NAME plus a location and NO signal report: 'MN "
        "Stations: First name & county (three letter designator). W/VE Stations: First name and "
        "state / province. DX Stations: First name only.' This app has no name field on a QSO, so "
        "the name is not captured, and the Cabrillo exporter writes the signal-report/serial slot "
        "into the ex1 column the sponsor reserves for the name - which for a party with neither "
        "is EMPTY. SCORING IS COMPLETELY UNAFFECTED: names are not multipliers, not points and "
        "not part of the dupe key, so live operating, dupe checking, multiplier tracking and the "
        "score are all correct. But Cabrillo is REQUIRED for submission and the log robot expects "
        "the name in ex1, so AN EXPORTED MNQP LOG NEEDS ITS NAME COLUMN FILLED IN BEFORE IT IS "
        "SUBMITTED. Recorded as a deferred engine gap; the fix is a name field on the QSO plus an "
        "exchangeIncludesName flag, which touches the entry bar and the edit sheet and is "
        "therefore its own commit. "
        "Cabrillo CONTEST value MN-QSO-PARTY per the WA7BNM registry, entry 238 - the rules "
        "require Cabrillo but print no header token. Logs are due within 7 days at "
        "https://mnqp.contesting.com/mnqpsubmitlog.php. Counties are 87 with uniform 3-letter "
        "designators, and several are NOT the naive first three letters: Carlton is CRL, Carver "
        "CRV and Crow Wing CRO, so CAR is not a designator at all; Kanabec is KNB and Kandiyohi "
        "KND, so KAN is not either; Marshall MRS and Martin MRT sit one letter apart. St Louis is "
        "printed without a period as 'St Louis' (STL) and Otter Tail as one word, 'Ottertail' "
        "(OTT); both ship as the sponsor prints them. "
        "OPEN QUESTIONS (why this is partial): (1) KNOWN LIMITATION 1 above - the name half of "
        "the exchange is not logged, so the exported Cabrillo is not submittable as it stands. "
        "This is a missing app feature, not a rule in doubt. (2) The 2026 rules are no longer "
        "published by the sponsor and were recovered from a web archive; they are the right "
        "document - the archived rules page of the same date names them - but they cannot be "
        "re-fetched from w0aa.org to confirm. If MNQP is ever re-verified for 2027, note that the "
        "2027 edition is a DIFFERENT PARTY in four fields, all of which this schema already has: "
        "countScope perMode, homeStateCountsViaCounty true, points phone 2 / CW 3, and "
        "maxSimultaneousCounties 2. Confirm with the Rules Committee at mnqp-committee@w0aa.org."
    ),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(mnqp, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"mnqp.json: {len(counties)} counties, uniform 3-letter designators")
print(f"  cross-check: by-county table == by-designator table (both {len(by_county)})")
print(f"  points: 2 for every QSO, phone and CW alike")
print(f"  multipliers: ONCE OVERALL both sides; in-state 87+50+13+1 = 151 (sponsor's own total)")
print(f"  bands: {len(BANDS)} - HF only, 160-10 m excluding WARC")
print(f"  county lines: FORBIDDEN (maxSimultaneousCounties 1)")
print(f"  schedule: 1 window, 10 h (1400Z -> 2400Z 7 Feb 2026)")
print(f"  Article 20: 2027 edition pinned as a diff - 4 scoring changes, none applied")
