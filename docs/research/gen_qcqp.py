#!/usr/bin/env python3
"""Generate Resources/Parties/qcqp.json — the Quebec QSO Party.

Per CONSTITUTION.md Article 2: both lists are parsed, never typed.

THE SPONSOR PUBLISHES THE RULES IN FRENCH AND IN ENGLISH, so this script parses
BOTH and requires them to agree. That is a genuine second source rather than a
second fetch of the same page - and it earns its keep, because the two editions
DISAGREE ABOUT CANADA:

  English: NT = "Northern Territories"        <- not a Canadian entity
  French : NT = "Territoires du Nord-Ouest"   <- correct: Northwest Territories

and BOTH then carry a fourteenth row, NWT = "Northwest Territories", which is
the same entity again. The French page left that row UNTRANSLATED - the only
English string in an otherwise French table - which is the signature of a row
appended late and never revisited. All fourteen ship as printed: accepting NWT
never blocks a legal exchange, and rejecting it would.

Sources (all banked):

  qcqp_rules_en_2026.txt   https://quebecqsoparty.org/rules-quebec-qso-party/
  qcqp_rules_fr_2026.txt   https://quebecqsoparty.org/reglements-quebec-qso-party-2/
  qcqp_home_2026.txt       https://quebecqsoparty.org/
  qcqp_cabrillo_name.txt   WA7BNM Cabrillo Names (Article 1 exception - header only)

  All fetched 2026-07-26. See qcqp_rules.md.

WATCH PARAGRAPH 20. It says "a multiplier of two (2) is granted to stations
working at a lower power level" - and that applies ONLY to the club and
per-region award tallies, not to the entrant's score, which paragraph 16 fixes
as QSO points x multipliers. No scoreMultipliers ships. A reader skimming for
"multiplier of two" would give every low-power entrant a wrong x2.

Run:  python3 docs/research/gen_qcqp.py
"""

import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "qcqp.json")


def read(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        s = f.read()
    for a, b in [("’", "'"), ("‘", "'"), ("“", '"'), ("”", '"'),
                 ("–", "-"), ("—", "-"), (" ", " ")]:
        s = s.replace(a, b)
    return s.split("=" * 72, 1)[-1]


def _ascii(s):
    """Accent-folded, for assertions about French prose where the point is the
    wording rather than the diacritics. Region NAMES are asserted with their
    accents intact - see the block below."""
    import unicodedata
    return "".join(c for c in unicodedata.normalize("NFD", s)
                   if unicodedata.category(c) != "Mn")


en = read("qcqp_rules_en_2026.txt")
fr = read("qcqp_rules_fr_2026.txt")
home = read("qcqp_home_2026.txt")
flat_en = re.sub(r"\s+", " ", en)
flat_fr = re.sub(r"\s+", " ", fr)

# --------------------------------------------------------- the 17 regions, x2
# Both editions print "<n>- <Name>" on one line and the code on the next.
REGION = re.compile(r"^(\d{1,2})-\s*(.+)$")


def regions(doc, appendix, stop):
    block = doc.split(appendix, 1)[1].split(stop, 1)[0]
    lines = [l.strip() for l in block.splitlines() if l.strip()]
    out = {}
    for i, l in enumerate(lines):
        m = REGION.match(l)
        if not m:
            continue
        code = lines[i + 1].strip()
        assert re.fullmatch(r"[A-Z]{3}", code), f"bad code after {l!r}: {code!r}"
        out[int(m.group(1))] = (code, m.group(2).strip())
    return out


# Split on the full HEADING, not the bare words - both documents cross-reference
# "Appendix I" several times before the appendix itself begins.
regions_en = regions(en, "Appendix I: List of Administrative Regions of Quebec",
                     "Appendix II:")
regions_fr = regions(fr, "Annexe I: Liste de zones de multiplicateurs", "Annexe II:")

assert len(regions_en) == 17, f"17 administrative regions, parsed {len(regions_en)}"
assert len(regions_fr) == 17, f"17 regions in French, parsed {len(regions_fr)}"
assert sorted(regions_en) == list(range(1, 18)), "numbered 1..17 with no gaps"

# THE CROSS-CHECK: the two editions must agree on every code. They may - and do -
# differ on the NAMES, because the English edition strips the French accents.
for n in range(1, 18):
    assert regions_en[n][0] == regions_fr[n][0], (
        f"region {n}: English says {regions_en[n]}, French says {regions_fr[n]}")

# The accented forms ship. They are the correct proper nouns and the French page
# is the sponsor's primary language; the English edition's stripped spellings are
# asserted too, so the divergence stays recorded rather than silently resolved.
counties = [{"abbr": code, "name": name} for _, (code, name) in sorted(regions_fr.items())]
by_abbr = {c["abbr"]: c["name"] for c in counties}

assert len(by_abbr) == 17, "codes must be unique"
assert {len(a) for a in by_abbr} == {3}, "uniformly 3 letters"

# THE TRAP: QUE is region 3, the Quebec City region - not the province, which is
# not a valid entry at all (see Appendix II below).
assert by_abbr["QUE"] == "Capitale-Nationale", by_abbr.get("QUE")
assert regions_en[3] == ("QUE", "National Capital"), regions_en[3]

# Accents survived from the French edition, and are absent from the English one.
for code, fr_name, en_name in [
    ("CND", "Côte-Nord", "Cote-Nord"),
    ("MTL", "Montréal", "Montreal"),
    ("MEE", "Montérégie", "Monteregie"),
    ("CDQ", "Centre-du-Québec", "Centre-du-Quebec"),
    ("ATE", "Abitibi-Témiscamingue", "Abitibi-Temiscamingue"),
]:
    assert by_abbr[code] == fr_name, (code, by_abbr.get(code))
    assert en_name in flat_en, f"the English edition should print {en_name}"

# Three codes that are one letter apart and mean different halves of the province.
assert by_abbr["CDQ"] == "Centre-du-Québec"
assert by_abbr["NDQ"] == "Nord-du-Québec"
assert by_abbr["CND"] == "Côte-Nord"

# ----------------------------------------------- Appendix II, and its 14th row
CAN = re.compile(r"^([A-Z]{2,3})$")


def canada(doc, appendix):
    block = doc.split(appendix, 1)[1]
    lines = [l.strip() for l in block.splitlines() if l.strip()]
    out = []
    for i, l in enumerate(lines):
        if CAN.fullmatch(l) and i and lines[i - 1] not in ("Abbreviation", "Abréviation"):
            out.append((l, lines[i - 1]))
    return out


can_en = canada(en, "Canadian Provinces and territories shall be logged")
can_fr = canada(fr, "Les provinces et territoires canadiens devront")

assert len(can_en) == 14, f"the sponsor prints 14 rows, parsed {len(can_en)}: {can_en}"
assert len(can_fr) == 14, f"14 rows in French, parsed {len(can_fr)}: {can_fr}"
assert [c for c, _ in can_en] == [c for c, _ in can_fr], "the codes must agree"

provinces = [c for c, _ in can_en]
assert len(set(provinces)) == 14, "no duplicate codes"

# FOURTEEN ROWS FOR THIRTEEN ENTITIES. NT and NWT are the same territory.
assert "NT" in provinces and "NWT" in provinces
assert dict(can_en)["NT"] == "Northern Territories", \
    "the English edition mislabels NT - if that is fixed, re-read Appendix II"
assert dict(can_fr)["NT"] == "Territoires du Nord-Ouest", \
    "the French edition has it right"
assert dict(can_en)["NWT"] == "Northwest Territories"
assert dict(can_fr)["NWT"] == "Northwest Territories", \
    "the French page never translated this row - the tell that it was appended late"

# Newfoundland is split, as North Dakota's list also splits it; Nunavut is here,
# unlike North Dakota's. Quebec itself is excluded outright.
assert "NF" in provinces and "LB" in provinces and "NL" not in provinces
assert "NU" in provinces, "unlike North Dakota's list, this one has Nunavut"
assert "QC" not in provinces
assert "Note that the Province of Quebec (QC) is not a valid territory entry" in flat_en

# The US side: 50 states + DC, with KP2/KP4 pushed out to DX.
assert ("Contacts with the 50 continental US States shall be logged using the common "
        "state abbreviation. Hawaii HI (KH6), Alaska AK (KL7) and District of Columbia "
        "DC shall be included in the continental states but KP2 and KP4 are excluded."
        ) in flat_en
assert "Other DXCC entities must be logged as DX." in flat_en

# ------------------------------------------------------------- the rules, read
assert ("Club Radio Amateur de l'Outaouais (CRAO) is proud to sponsor the Quebec QSO "
        "Party.") in flat_en
assert "QCQP is the abbreviation used for the Quebec QSO Party." in flat_en

# Dates: stated outright in both languages, and NEW FOR 2026.
assert ("The Quebec QSO Party will be held on Sunday April 19th, 2026, from 13:00 to "
        "24:00 UTC.") in flat_en
assert "the event will be held on the Sunday of the third full weekend of April" in flat_en
flat_home = re.sub(r"\s+", " ", home)
assert "19 avril 2026 de 1300-2400 UTC - April 19th, 2026 1300-2400Z" in flat_home, \
    "the home page's bilingual banner"
assert ("This year the event will be held on Sunday April 19th, 2026 from 13:00 to "
        "24:00 UTC which is 9 AM to 8 PM Eastern Daylight Time.") in flat_home
assert ("l'evenement aura lieu le dimanche 19 avril 2026, de 13:00 a 24:00 UTC ou 9h a "
        "20h Heure avancee de l'est.") in _ascii(flat_home), "and the French one, with local time"
assert "Nouvelles heures d'operations - New operating times" in _ascii(flat_home), \
    "the sponsor flags 2026 hours as NEW - a pre-2026 source has the wrong window"

# Bands: 80 to 2, so NO 160 m - which Ontario, one day earlier, does have.
assert "All amateur bands between 80 et 2 m, excepted WARC bands." in flat_en
assert not re.search(r"\b160\b", flat_en), "the range genuinely starts at 80 m"
suggested = flat_en.split("Suggested Frequencies")[1].split("Frequency Modulation")[0]
assert "5." not in suggested, "no 5 MHz frequency is suggested - see OPEN QUESTION 1"
assert "1.8" not in suggested, "and no 1.8 MHz one either"

# Modes and dupes.
assert "Phone (SSB or FM) and Morse code (CW)." in flat_en
assert "operators cannot use repeaters" in flat_en
assert "digital" not in flat_en.lower() and "RTTY" not in flat_en
assert "A station can be contacted twice per band, once on phone and once on CW" in flat_en
assert ("Additional logged QSOs have no value but are not penalized either." in flat_en)

# Points - and Ontario, sharing the weekend, pays 2 for phone.
assert "1 point per QSO on phone on each frequency band" in flat_en
assert "2 points per QSO on CW on each frequency band" in flat_en

# Scope, with the mode axis denied in so many words.
assert ("one multiplier point is given for each first contact made in each "
        "administrative region, on each frequency band worked on these regions. No "
        "additional multipliers are given for working multiple modes.") in flat_en
assert ("Only one DX multiplier is given for entities worked outside of Canada or USA."
        ) in flat_en, "this is what makes dxStyle 'token' the rule rather than a rounding"

assert ("QSO-score = (Total of the QSO points) * (Total of the multiplier points)"
        in flat_en)
assert "Non-VE2 stations obtain points for contacts for VE2 stations only." in flat_en

# Region boundaries.
assert ("If a mobile station is on a boundary between 2 or more administrative regions, "
        "a separate QSO and complete exchange must be made and logged for each "
        "administrative regions worked.") in flat_en

# Bonuses: placement, the 2026 removal, and the mobile rule Ontario shares word for word.
assert "Bonuses are added after the calculation of the QSO-score." in flat_en
assert "Starting in 2026, there is no bonus station(s)" in flat_en, \
    "if a bonus station returns, it needs a workStation rule"
assert "Il n'y a pas de station bonus commencant en 2026" in flat_fr
assert ("Mobile stations add 300 bonus points for each Quebec administrative region "
        "activated. To earn the mobile/rover bonus a station must make at least three "
        "contacts with three different stations from the multiplier area.") in flat_en

# PARAGRAPH 20's x2 IS AN AWARD TALLY, NOT A SCORE MULTIPLIER.
assert ("A multiplier of one (1) is used for stations operating at High Power and a "
        "multiplier of two (2) is granted to stations working at a lower power level."
        ) in flat_en
assert flat_en.index("Awards per club, inside Quebec") < flat_en.index(
    "A multiplier of one (1) is used"), \
    "that x2 lives under the club-award heading and must not reach scoreMultipliers"

# Cabrillo: never named, in either language.
assert "CONTEST:" not in en and "CONTEST:" not in fr
assert "shall be submitted in Cabrillo format" in flat_en
assert "contestdetails.php?ref=53" in flat_en, \
    "the sponsor cites WA7BNM itself, which is where the header value comes from"
name = read("qcqp_cabrillo_name.txt")
assert "Quebec QSO Party" in name and "QC-QSO-PARTY" in name

NOTES = (
    "verified: partial - rules from Club Radio Amateur de l'Outaouais (CRAO), read "
    "verbatim 2026-07-26. THE SPONSOR PUBLISHES BOTH A FRENCH AND AN ENGLISH EDITION and "
    "the generator parses both, requiring them to agree on all 17 region codes - a real "
    "second source, not a second fetch. Unlike Michigan and Ontario, this site is current "
    "for 2026 and has not rolled forward. Eleven hours in ONE window, 1300-2400 UTC on the "
    "Sunday of the third full weekend of April, and THE HOURS ARE NEW FOR 2026 (the home "
    "page banner says so in both languages), so a pre-2026 source has the wrong window. "
    "SEVEN BANDS, 80 THROUGH 2 M - NO 160 M, which Ontario has; the range genuinely starts "
    "at 80. Phone 1 point, CW 2 - worth noting beside Ontario, which shares the weekend and "
    "raised phone to 2 for 2026. Multipliers count PER BAND with the mode axis denied "
    "outright: 'No additional multipliers are given for working multiple modes.' DXSTYLE "
    "TOKEN IS THE RULE HERE, NOT A ROUNDING: 'Only one DX multiplier is given for entities "
    "worked outside of Canada or USA', and 'Other DXCC entities must be logged as DX' - so "
    "the single collapsed multiplier is exactly what the sponsor pays, the opposite of "
    "Ontario one day earlier. APPENDIX II PRINTS FOURTEEN ROWS FOR THIRTEEN ENTITIES AND "
    "THE TWO EDITIONS DISAGREE: the English calls NT 'Northern Territories', which is not a "
    "Canadian entity, while the French correctly calls it 'Territoires du Nord-Ouest'; and "
    "both then add a fourteenth row, NWT 'Northwest Territories', for the same territory - "
    "a row the French page never translated, which is the tell that it was appended late. "
    "ALL FOURTEEN SHIP AS PRINTED, because accepting NWT never blocks a legal exchange and "
    "rejecting it would; the over-count it allows needs one operator to log one territory "
    "under two labels. Newfoundland is split into NF and LB, as North Dakota's list also "
    "splits it, but unlike North Dakota's this one has Nunavut. QUEBEC ITSELF IS NOT A "
    "VALID ENTRY - 'the Province of Quebec (QC) is not a valid territory entry' - so VE2 "
    "stations are reached only through their region. WATCH QUE: it is region 3, the "
    "Capitale-Nationale around Quebec City, NOT the province. Region names ship with the "
    "French edition's accents, which are the correct proper nouns; the English edition "
    "strips them and the generator asserts both spellings so the divergence stays visible. "
    "'Starting in 2026, there is no bonus station(s)' - asserted, so its return is noticed. "
    "PARAGRAPH 20'S 'MULTIPLIER OF TWO FOR LOWER POWER' IS AN AWARD TALLY, NOT A SCORE "
    "MULTIPLIER: it sits under 'Awards per club, inside Quebec', while paragraph 16 fixes "
    "the entrant's score as QSO points x multipliers, so no scoreMultipliers ships. KNOWN "
    "LIMITATION - the mobile bonus requires 'three contacts with three different stations' "
    "and activatedCountyCount counts three QSOs, which three bands' worth of one station "
    "satisfies; SECOND USER of that gap after Ontario, one day apart on the calendar, which "
    "meets the two-user bar and makes it worth building. Overpayment is bounded at 300 "
    "points per region. The Cabrillo CONTEST header is the one thing not from the sponsor - "
    "neither edition names one - so QC-QSO-PARTY comes from WA7BNM under Article 1's "
    "exception, which sits comfortably here because the sponsor cites WA7BNM itself for "
    "upcoming dates. OPEN QUESTION 1: IS 60 M LEGAL? 'All amateur bands between 80 et 2 m, "
    "excepted WARC bands' puts 60 m inside the range and 60 m is not strictly WARC - the "
    "same ambiguity Ontario and North Dakota have, resolved the same way. Seven bands ship "
    "without it, and no 5 MHz frequency appears in the sponsor's suggested list."
)

party = {
    "schemaVersion": 1,
    "id": "qcqp",
    "name": "Quebec QSO Party",
    "cabrilloContest": "QC-QSO-PARTY",
    "homeState": "QC",
    "countyAbbrLength": 3,
    "validBands": ["80m", "40m", "20m", "15m", "10m", "6m", "2m"],
    "points": {"phone": 1, "cw": 2, "digital": 0},
    "dupeScope": "bandMode",
    "multipliers": {
        # "on each frequency band worked on these regions. No additional
        # multipliers are given for working multiple modes."
        "inState": {
            "classes": ["county", "state", "province", "dx"],
            "homeStateCountsViaCounty": False,
            "countScope": "perBand",
        },
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "perBand",
        },
    },
    "bonuses": [
        {"type": "activatedCountyCount", "minQSOs": 3, "points": 300},
    ],
    "dxStyle": "token",
    "allowedModes": ["phone", "cw"],
    "maxSimultaneousCounties": 1,
    "provinces": provinces,
    "exchangeIncludesRST": True,
    "outStateWorksHomeStationsOnly": True,
    "schedule": [
        {"start": "2026-04-19T13:00:00Z", "end": "2026-04-20T00:00:00Z"},
    ],
    "counties": counties,
    "hubSpots": {
        "tableURL": "http://qsopartyhub.com/qcqp-table.php",
        "postURL": "http://qsopartyhub.com/qcqp-spots.php",
    },
    "notes": NOTES,
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(party, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"qcqp.json: {len(counties)} administrative regions, uniform 3-letter codes")
print("  BOTH LANGUAGE EDITIONS PARSED; they agree on all 17 codes")
print("  QUE is region 3, the Capitale-Nationale - NOT the province, "
      "which is not a valid entry")
print(f"  APPENDIX II PRINTS {len(provinces)} ROWS FOR 13 ENTITIES:")
print("    EN 'NT = Northern Territories' vs FR 'NT = Territoires du Nord-Ouest'")
print("    ...and both add NWT for the same territory; the FR page left it in English")
print("    all fourteen ship as printed - refusing one would block a legal exchange")
print("  NL is split into NF + LB (as North Dakota), but NU is present (unlike it)")
print("  points: phone 1, CW 2; multipliers PER BAND, mode axis denied outright")
print("  dxStyle token is THE RULE: 'only one DX multiplier is given'")
print("  no bonus station from 2026; 300 per activated region with 3+ QSOs")
print("  NOT shipped: paragraph 20's x2 for low power - it is a club-award tally")
print("  schedule: 1 window, 11 h, and the hours are NEW FOR 2026")
print(f"  wrote {os.path.normpath(OUT)}")
