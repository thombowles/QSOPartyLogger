#!/usr/bin/env python3
"""Generate paqp.json from the sponsor's own three PDFs.

Nothing is hand-typed: the 67 counties and the 85 ARRL/RAC sections are parsed
out of the sponsor's own abbreviation lists, and every rule below is asserted
against the quoted text of the rules PDF.

Sources (committed alongside this script, so the run is reproducible):
  paqp_rules_2025.txt      — pdftotext -layout of https://www.paqso.org/files/PAQSO_Rules.pdf
                             13 pages, footer "Revision: 08/19/25"
  paqp_rules_page.txt      — text of https://www.paqso.org/pa-qso-party-rules.html,
                             whose banner carries the 2026 dates the rules body lacks
  paqp_counties.txt        — https://paqso.org/files/PA_QSO_County_Abbreviations.pdf
  paqp_arrl_sections.txt   — https://paqso.org/files/ARRL-Section-List.pdf
  paqp_rules.md            — full rules research; all fetched 2026-07-24

Both abbreviation PDFs are laid out in columns, so both are parsed with
column-aware patterns and hard count assertions (67 and 85).

NOTE the rules text is still the 2025 revision and the 2026 bonus station has
not been announced; the party ships verified: partial for both. See
paqp_rules.md sections 2 and 7.

Usage:  python3 gen_paqp.py        (run from docs/research/)
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "paqp.json")
RULES = os.path.join(HERE, "paqp_rules_2025.txt")
PAGE = os.path.join(HERE, "paqp_rules_page.txt")
COUNTIES = os.path.join(HERE, "paqp_counties.txt")
SECTIONS = os.path.join(HERE, "paqp_arrl_sections.txt")


def read(path):
    return open(path, encoding="utf-8").read().replace("’", "'").replace("“", '"').replace("”", '"')


rules_raw, page_raw = read(RULES), read(PAGE)
rules = re.sub(r"\s+", " ", rules_raw)
page = re.sub(r"\s+", " ", page_raw)

# --- Counties: three "ABBR Name" columns per line. ---
counties_txt = read(COUNTIES)
if "County Abbreviations" not in counties_txt:
    sys.exit("county list heading not found in paqp_counties.txt")
body = counties_txt.split("County Abbreviations", 1)[1]
pairs = re.findall(r"\b([A-Z]{3})\s+([A-Z][A-Za-z]+)", body)
counties = {}
for abbr, name in pairs:
    if abbr in counties:
        sys.exit(f"PAQP duplicate county abbreviation: {abbr}")
    counties[abbr] = name

assert len(counties) == 67, f"expected 67 PA counties, got {len(counties)}: {sorted(counties)}"
assert len(set(counties.values())) == 67, "PA county names not unique"
assert all(len(a) == 3 for a in counties), "all PAQP county abbreviations are 3 letters"
# The rules state the count themselves, in rule 10.b.
assert "Out-of-State Multipliers: 67 PA Counties" in rules, \
    "the rules' own county count is gone — re-read the source"

# Spot checks on the ten that are NOT the first three letters (Article 18).
# Each exists to break a collision cluster; see paqp_rules.md section 13.
for abbr, name in [
    ("BUX", "Bucks"),           # BUT is Butler
    ("CMB", "Cambria"),         # CAM would collide with Cameron
    ("CRN", "Cameron"),         # CAR is Carbon
    ("DCO", "Delaware"),        # not DEL
    ("INN", "Indiana"),         # not IND
    ("MOE", "Monroe"),          # MON is ambiguous across three counties
    ("MGY", "Montgomery"),
    ("MTR", "Montour"),
    ("NHA", "Northampton"),     # NOR is ambiguous with Northumberland
    ("NUM", "Northumberland"),
    ("MCK", "McKean"),          # internal capital
]:
    assert counties.get(abbr) == name, f"{abbr} should be {name}, got {counties.get(abbr)!r}"

# The collision clusters the scheme exists to separate must all be present and
# distinct — if a future edit collapsed any of them the list is wrong.
for cluster in [("BUX", "BUT"), ("CMB", "CRN", "CAR"), ("CLA", "CLE", "CLI"),
                ("MER", "MIF", "MOE", "MGY", "MTR"), ("WAR", "WAS", "WAY", "WES"),
                ("NHA", "NUM")]:
    assert all(a in counties for a in cluster), f"missing member of cluster {cluster}"
    assert len(set(cluster)) == len(cluster)

# --- Sections: "Name .......... ABBR", two columns per line. ---
sections_txt = read(SECTIONS)
found = re.findall(r"([A-Za-z][A-Za-z0-9\-' ]*?)\s*\.{2,}\s*([A-Z]{2,4})\b", sections_txt)
sections = []
section_names = {}
for name, abbr in found:
    if abbr in section_names:
        sys.exit(f"PAQP duplicate section abbreviation: {abbr}")
    sections.append(abbr)
    section_names[abbr] = name.strip()

assert len(sections) == 85, f"expected 85 ARRL/RAC sections, got {len(sections)}: {sections}"
assert len(set(sections)) == 85, "section abbreviations not unique"

# The rules state the Canadian count themselves, in rule 16.a.
CANADIAN = ["AB", "BC", "GH", "MB", "NB", "NL", "NS", "ONE", "ONN", "ONS", "PE", "QC", "SK", "TER"]
assert "The 14 Canadian Sections" in rules, "the rules' own Canadian count is gone"
assert len(CANADIAN) == 14
for abbr in CANADIAN:
    assert abbr in section_names, f"Canadian section {abbr} missing from the section list"
assert len(sections) - len(CANADIAN) == 71, "71 US sections + 14 Canadian = 85"

# Sections are NOT states: several state codes must be absent, and the four
# Ontario tokens present. This is the whole reason PAQP needed a new class.
for not_a_token in ["TX", "NY", "CA", "FL", "PA", "MA", "WA", "NJ", "ON", "NT", "NU", "YT"]:
    assert not_a_token not in section_names, \
        f"'{not_a_token}' is a state/province code and must not be a PAQP section"
for onta in ["GH", "ONE", "ONN", "ONS"]:
    assert onta in section_names, f"Ontario section {onta} missing"
# Pennsylvania's own two sections exist but are never sent — see grantedMultipliers.
assert section_names.get("EPA", "").startswith("Eastern Pennsylvania")
assert section_names.get("WPA", "").startswith("Western Pennsylvania")
assert "EPA and WPA multipliers are automatically added" in rules, \
    "rule 12.d is gone — re-read the source before keeping grantedMultipliers"

# --- Bands: everything the licensee holds except the four WARC bands. The app's
# Band enum has no 630 m or 2200 m, which the rules do permit; recorded in notes
# rather than invented here. ---
BANDS = ["160m", "80m", "40m", "20m", "15m", "10m", "6m", "2m", "1.25m", "70cm"]
assert "QSOs are not permitted on the WARC bands (12m, 17m, 30m, or 60m)" in rules, \
    "the WARC exclusion changed — re-read the source"
for warc in ["12m", "17m", "30m", "60m"]:
    assert warc not in BANDS
assert "including 630m and 2200m" in rules, \
    "the 630/2200 m permission is gone — the notes' limitation paragraph is now stale"

# --- The rule sentences this file encodes. ---
for quote in [
    "Sequential serial number plus PA county, ARRL section, Canadian section, or \"DX\"",
    "CW: 2 points/QSO",
    "Phone: 1 point/QSO",
    "Work stations once per band and mode",
    "Work Rovers and Mobiles again when they change counties",
    "In-State Multipliers: ARRL Sections + Canadian Sections + PA Counties + 1 DX",
    "Each multiplier counts once, not once per band",
    "QRP Operation Multiplier: Multiply QSO Points times 2",
    "PA Mobile and Rover Bonus: Add 500 Points to final score for each PA County you operated from where you made at least 10 valid QSOs",
    "Valid QSOs with the bonus station are worth 200 points",
    "sends a single report with the multiple county abbreviations (CAR/LEH)",
    "Final Score: Total points times Total Multipliers + Bonus Station Points",
]:
    assert quote in rules, f"rules text no longer contains: {quote!r}"

# Digital was removed outright; the change log says so.
assert "Removed digital modes" in rules, "the digital-mode removal note is gone"

# The rules body is last year's; the 2026 dates live only in the site banner.
assert "Pennsylvania QSO Party 2025 Rules" in rules and "Revision: 08/19/25" in rules, \
    "the rules PDF is no longer the 2025 revision — re-verify and revisit the partial marker"
assert "October 10 & 11, 2026" in page and "2nd Full Weekend in October" in page, \
    "the 2026 dates are no longer in the rules-page banner — re-read the source"
# The 2025 window pattern, whose times transfer to 2026 unchanged (still EDT).
assert "1600Z (1200EDT)" in rules and "0400Z (Midnight EDT)" in rules \
    and "1300Z (0900EDT)" in rules and "2200Z (1800EDT)" in rules, \
    "the operating-window times changed — re-derive the 2026 schedule"
# The 2025 bonus station is still the one named, i.e. 2026 is unannounced.
assert "The Bonus Station(s) for the 2025 PAQSO Party is N3XF" in rules, \
    "rule 11.d moved — check whether the 2026 bonus station is now named"

paqp = {
    "schemaVersion": 1,
    "id": "paqp",
    "name": "Pennsylvania QSO Party",
    # Sponsor mandates Cabrillo 3.0 but prints no CONTEST: token; WA7BNM
    # registry (Article 1 exception).
    "cabrilloContest": "PA-QSO-PARTY",
    "homeState": "PA",
    "countyAbbrLength": 3,
    # "all ham band allocations ... except ... the WARC bands (12m, 17m, 30m, or
    # 60m)". 630 m and 2200 m are permitted too but absent from Band; see notes.
    "validBands": BANDS,
    # "CW: 2 points/QSO" / "Phone: 1 point/QSO"
    "points": {"phone": 1, "cw": 2, "digital": 2},
    # "Work stations once per band and mode."
    "dupeScope": "bandMode",
    "multipliers": {
        # "In-State Multipliers: ARRL Sections + Canadian Sections + PA Counties
        # + 1 DX. Each multiplier counts once, not once per band."
        "inState": {
            "classes": ["county", "section", "dx"],
            # PAQP has no state class at all — the home jurisdiction arrives as
            # the two PA sections below, not as a state token.
            "homeStateCountsViaCounty": False,
            "countScope": "once",
            # "+ 1 DX" — a cap of exactly one.
            "dxMultCap": 1,
            # Rule 12.d: "EPA and WPA multipliers are automatically added during
            # the rescore process - there is no need to enter them." PA stations
            # send a county, so neither token is ever transmitted.
            "grantedMultipliers": [
                {"multClass": "section", "value": "EPA"},
                {"multClass": "section", "value": "WPA"},
            ],
        },
        # "Out-of-State Multipliers: 67 PA Counties. Each multiplier counts once,
        # not once per band."
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
        },
    },
    # "PA Mobile and Rover Bonus: Add 500 Points to final score for each PA
    # County you operated from where you made at least 10 valid QSOs."
    #
    # The 200-point-per-QSO bonus station is deliberately ABSENT: the rules still
    # name the 2025 station (N3XF) and the 2026 one is unannounced, so shipping a
    # call here would credit a phantom bonus. See notes.
    "bonuses": [{"type": "activatedCountyCount", "minQSOs": 10, "points": 500}],
    # 'or "DX"' — the literal token, not a prefix.
    "dxStyle": "token",
    # "Removed digital modes. Deleted 4.c and 6.b" (change log).
    "allowedModes": ["phone", "cw"],
    # "A County Line station sends a single report with the multiple county
    # abbreviations (CAR/LEH)" — one exchange, one row per county. The rules say
    # "at least two or more" with no maximum, so the app's ceiling stands.
    "maxSimultaneousCounties": 4,
    # 85 ARRL/RAC sections, parsed above. Supplants states and provinces
    # entirely: NTX is valid here and TX is not.
    "sections": sections,
    # "Sequential serial number plus PA county, ARRL section, ..." — no RST.
    "exchangeIncludesRST": False,
    "exchangeIncludesSerial": True,
    # Not stated outright; see notes. Out-of-state multipliers are PA counties
    # only, and rule 1.b frames the party as working PA stations.
    "outStateWorksHomeStationsOnly": True,
    # "QRP Operation Multiplier: Multiply QSO Points times 2."
    "scoreMultipliers": {"power": {"HIGH": 1, "LOW": 1, "QRP": 2}},
    # 2026 dates from the sponsor's banner ("October 10 & 11, 2026" / "Always the
    # 2nd Full Weekend in October"); times from rule 2.a, whose own EDT
    # parentheticals still hold in 2026 (DST ends 1 November). 12 h + 9 h = 21 h.
    "schedule": [
        {"start": "2026-10-10T16:00:00Z", "end": "2026-10-11T04:00:00Z"},
        {"start": "2026-10-11T13:00:00Z", "end": "2026-10-11T22:00:00Z"},
    ],
    "counties": [{"abbr": a, "name": n} for a, n in sorted(counties.items(), key=lambda kv: kv[1])],
    "notes": (
        "verified: partial — rules from the PA QSO Party Association's official PDF "
        "(paqso.org/files/PAQSO_Rules.pdf, 13 pages, footer 'Revision: 08/19/25'), plus the "
        "sponsor's two official abbreviation PDFs for the 67 counties and the 85 ARRL/RAC "
        "sections, all read verbatim 2026-07-24. "
        "THE EXCHANGE IS A SERIAL NUMBER PLUS A SECTION, NOT A STATE: 'Sequential serial "
        "number plus PA county, ARRL section, Canadian section, or \"DX\"'. There is no RST. "
        "Non-PA stations send their ARRL/RAC SECTION, so NTX, STX and WTX are valid and TX is "
        "NOT a PAQP token; likewise ENY/NLI/NNY/WNY rather than NY, and EPA/WPA rather than PA. "
        "Canada is 14 SECTIONS rather than 13 provinces and differs in kind: Ontario alone is "
        "four tokens (GH Golden Horseshoe, ONE, ONN, ONS) and NT, NU and YT do not exist - they "
        "are TER. "
        "Multipliers count ONCE, not per band, on both sides, which the sponsor clarified "
        "deliberately in 2023. PA stations count PA counties + all 85 sections + exactly 1 DX "
        "('+ 1 DX', the tightest DX cap of any bundled party, and one the literal 'DX' token "
        "satisfies exactly since every DX station sends the same thing). Non-PA stations count "
        "the 67 PA counties and nothing else. EPA AND WPA ARE GRANTED OUTRIGHT to PA entrants: "
        "rule 12.d says 'EPA and WPA multipliers are automatically added during the rescore "
        "process - there is no need to enter them', because PA stations send a county and so "
        "neither PA section token is ever transmitted. "
        "CW 2 points, phone 1; there is no digital mode at all - the change log records "
        "'Removed digital modes. Deleted 4.c and 6.b' - so a digital QSO is invalid rather than "
        "zero-point. QRP is a FINAL-SCORE MULTIPLIER of 2 ('QRP Operation Multiplier: Multiply "
        "QSO Points times 2'), applied only to QRP-specific entry divisions. PA mobiles and "
        "rovers earn 500 points per PA county worked from with 10 or more valid QSOs. County "
        "lines are ONE exchange with several counties ('sends a single report with the multiple "
        "county abbreviations (CAR/LEH)'), logged as a QSO per county, with no stated maximum, "
        "so the app's ceiling of four applies; a county-line station is fixed for the whole "
        "party, and mobiles, rovers and bonus stations may not be county-line stations. "
        "KNOWN LIMITATION: the rules permit 630 m and 2200 m and any VHF/UHF/microwave "
        "frequency, but this app's band list stops at 70 cm, so QSOs on 630 m, 2200 m or above "
        "70 cm cannot be logged. The sponsor itself describes typical activity as 160 m through "
        "2 m, so this is recorded rather than fixed. Ten bands ship: 160, 80, 40, 20, 15, 10, "
        "6, 2, 1.25 m and 70 cm - everything but the WARC bands the rules exclude. "
        "Cabrillo CONTEST value PA-QSO-PARTY per WA7BNM; the sponsor mandates Cabrillo 3.0 and "
        "cites the Cabrillo QSO-data spec but prints no header token. County and section lists "
        "are parsed from the sponsor's own PDFs with hard count assertions (67 and 85, both of "
        "which the rules state independently in 10.b and 16.a). "
        "OPEN QUESTIONS (why this is partial): (1) The published rules are the 2025 revision "
        "('Pennsylvania QSO Party 2025 Rules', Revision 08/19/25), so a 2026 rule change would "
        "not be visible. The DATES are not in doubt - the sponsor's banner says 'October 10 & "
        "11, 2026', the rules' own formula is 'Always the 2nd Full Weekend in October', and the "
        "rules' EDT parentheticals (1600Z = 1200EDT, 0400Z = midnight, 1300Z = 0900EDT, 2200Z = "
        "1800EDT) all still hold in 2026 since DST ends 1 November. Re-check paqso.org before "
        "10 October 2026 and re-run gen_paqp.py, whose quoted-sentence assertions fail loudly "
        "if the text moved. (2) THE 2026 BONUS STATION IS NOT ANNOUNCED. Valid QSOs with it are "
        "worth 200 points each - confirmed by the sponsor's own published arithmetic, the 2025 "
        "station N3XF reporting '1796 QSO's which results in 359,200 bonus points', exactly 200 "
        "per QSO - but the rules still name the 2025 station and the bonus-station page still "
        "describes 2025. NO BONUS STATION SHIPS, because shipping last year's call would credit "
        "a phantom 200 points per QSO. Add one as a user file (Article 21) once it is named. "
        "(3) No rule states whether a non-PA station may work only PA stations. Rule 1.b frames "
        "the party as 'Non-Pennsylvania Amateurs try to contact as many Pennsylvania Amateurs "
        "as possible' and out-of-state multipliers are PA counties only, but neither is a "
        "prohibition. Shipped with the restriction ON, as for NJQP, IAQP and NHQP, so a stray "
        "non-PA contact is visibly flagged NO CREDIT rather than silently scoring. Confirm all "
        "three with the sponsor (info@paqso.org) before submitting a log."
    ),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(paqp, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"paqp.json: {len(counties)} counties, {len(sections)} sections "
      f"({len(sections) - len(CANADIAN)} US + {len(CANADIAN)} Canadian)")
print(f"  in-state: {len(counties)} counties + {len(sections)} sections + 1 DX, counted once,")
print(f"            plus EPA and WPA granted outright (rule 12.d)")
print(f"  out-of-state ceiling: {len(counties)} counties (rules say 67)")
print(f"  bands: {len(BANDS)} — all but WARC; 630 m / 2200 m unavailable, see notes")
print(f"  schedule: 12 h + 9 h = 21 h across two windows")
print(f"  bonus station: NONE — 2026 call unannounced (2025 was N3XF at 200 pts/QSO)")
