#!/usr/bin/env python3
"""Generate ilqp.json from the sponsor's own rules and county PDFs.

Sources (committed alongside this script, so the run is reproducible):
  ilqp_rules_2025.txt  — pdftotext -layout of "Announcing the 2025 Illinois QSO
                         Party", w9awe.org/download/86/2025/2064/...
  ilqp_counties.txt    — pdftotext -layout of "ILQP Counties & Abbreviations",
                         w9awe.org/download/68/ilqp/1919/...
  ilqp_page.txt        — text of https://w9awe.org/ilqp/, which carries the
                         "Sunday the third full weekend of October" formula
  ilqp_rules.md        — full rules research; all fetched 2026-07-24

RETRIEVAL NOTE: the rules PDF sits on PAGE 2 of the site's file browser, which
paginates in JavaScript with no href on the "Next" control, so a plain fetch of
w9awe.org/ilqp/ never reveals it. It was reached by driving the page in a browser.

A web search claimed ILQP awards "one extra multiplier for every eight QSOs made
with the same Illinois county". THAT RULE IS NOT IN THE SPONSOR'S RULES and would
have inflated every score. See ilqp_rules.md §1 — Article 1 in action.

NOTE the rules are the 2025 edition; the 2026 date comes from the formula on the
sponsor's page. The party ships verified: partial. See ilqp_rules.md §2.

Usage:  python3 gen_ilqp.py        (run from docs/research/)
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "ilqp.json")
RULES = os.path.join(HERE, "ilqp_rules_2025.txt")
COUNTIES = os.path.join(HERE, "ilqp_counties.txt")
PAGE = os.path.join(HERE, "ilqp_page.txt")


def read(path):
    return open(path, encoding="utf-8").read().replace("’", "'").replace("“", '"').replace("”", '"')


rules = re.sub(r"\s+", " ", read(RULES))
page = re.sub(r"\s+", " ", read(PAGE))
counties_txt = read(COUNTIES)

# --- Counties: three "Name ABBR" columns per row, with single-letter group
# headers ("A Adams ADAM") that must be stripped off the name. ---
counties = {}
for name, abbr in re.findall(r"([A-Z][A-Za-z.'\s]*?[a-z.])\s{2,}([A-Z]{3,4})(?=\s|$)", counties_txt):
    name = re.sub(r"^[A-Z]\s+", "", name.strip())
    if abbr in counties and counties[abbr] != name:
        sys.exit(f"ILQP conflicting names for {abbr}: {counties[abbr]!r} vs {name!r}")
    counties.setdefault(abbr, name)

assert len(counties) == 102, f"expected 102 IL counties, got {len(counties)}: {sorted(counties)}"
assert len(set(counties.values())) == 102, "IL county names not unique"

# "Each Illinois county has an established 4 letter abbreviation (Lee County
# excepted)" — so LEE is the only 3-letter code, and the rules say so.
lengths = sorted({len(a) for a in counties})
assert lengths == [3, 4], f"expected 3- and 4-letter abbreviations, got {lengths}"
assert [a for a in counties if len(a) == 3] == ["LEE"], \
    "Lee should be the only 3-letter code — re-read the source"
assert "4 letter abbreviation (Lee County excepted)" in rules, \
    "the rules' own note about Lee is gone"

# The rules name their own worst traps; assert both pairs. The Mason/Macon pair
# also settles a conflict with the website FAQ, which says MCON for Macon while
# the county list and the rules both say MACN. See ilqp_rules.md §13.
assert "White (WHIT) and Whiteside (WTSD)" in rules
assert "Mason (MASN) and Macon (MACN)" in rules
for abbr, name in [
    ("WHIT", "White"), ("WTSD", "Whiteside"),
    ("MASN", "Mason"), ("MACN", "Macon"),
    ("LEE", "Lee"),
    ("BURO", "Bureau"), ("CHRS", "Christian"),
    ("CLRK", "Clark"), ("CLAY", "Clay"), ("CLNT", "Clinton"),
    ("DEKA", "DeKalb"), ("DEWT", "DeWitt"), ("DUPG", "DuPage"),
    ("EFFG", "Effingham"), ("JODA", "JoDaviess"), ("LASA", "LaSalle"),
    ("LIVG", "Livingston"), ("MCPN", "Macoupin"), ("MADN", "Madison"),
    ("MSHL", "Marshall"), ("MSSC", "Massac"), ("MCDN", "McDonough"),
    ("ROCK", "Rock Island"), ("SCHY", "Schuyler"), ("SCLA", "St. Clair"),
    ("STEP", "Stephenson"), ("TAZW", "Tazewell"),
]:
    assert counties.get(abbr) == name, f"{abbr} should be {name}, got {counties.get(abbr)!r}"

# --- Bands: "160 through 2 meters, excluding WARC bands (60, 30, 17 and 12
# meters)". The sponsor counts 60 m among the WARC bands, which is loose, but the
# exclusion is unambiguous. "through 2 meters" caps the list at 2 m. ---
BANDS = ["160m", "80m", "40m", "20m", "15m", "10m", "6m", "2m"]
assert "160 through 2 meters, excluding WARC bands (60, 30, 17 and 12 meters)" in rules, \
    "the band sentence changed — re-read the source"
for excluded in ["60m", "30m", "17m", "12m", "1.25m", "70cm"]:
    assert excluded not in BANDS

# --- The rule sentences this file encodes. ---
for quote in [
    "IL stations give RS/T and county; others give RS/T and state, province or country",
    "Phone QSO: 1 point; CW/digital QSO 2 points",
    "Stations may be worked once per band and mode (phone and CW/digital)",
    "IL stations multiply points by the sum of IL counties, US states, VE provinces and DXCC countries (maximum 5) worked",
    "Non-IL stations multiply points by the number of IL counties worked",
    "count as 2/3/4 counties and 2/3/4 QSOs",
    "FT4 and FT8 contacts will receive no contact credit",
    "any entrant contacting these stations will have a 100 point bonus added to the final score",
    "Total of 200 points possible",
]:
    assert quote in rules, f"rules text no longer contains: {quote!r}"

# The two bonus callsigns are the club's own, unlike PAQP's rotating station.
assert "W9AWE" in rules and "W9OAB" in rules, "the bonus callsigns changed"

# The rules are the 2025 edition; the 2026 date comes from the formula.
assert "Announcing the 2025 Illinois QSO Party" in rules, \
    "the rules PDF is no longer the 2025 edition — re-verify and revisit the partial marker"
assert "1700 UTC October 19, 2025 to 0100 UTC October 20, 2025" in rules
assert "Sunday the third full weekend of October" in page, \
    "the formula is gone from the sponsor's page — the 2026 date rests on it"

# The multiplier bonus a secondary source invented must not be in the rules.
assert "eight QSOs" not in rules and "every eight" not in rules, \
    "a per-eight-QSOs multiplier rule now exists — see ilqp_rules.md §1 and model it"

ilqp = {
    "schemaVersion": 1,
    "id": "ilqp",
    "name": "Illinois QSO Party",
    # Sponsor prefers but does not require Cabrillo and prints no CONTEST: token;
    # WA7BNM registry (Article 1 exception).
    "cabrilloContest": "IL-QSO-PARTY",
    "homeState": "IL",
    # Mixed 3/4 — countyAbbrLengths reports both; this is the entry hint.
    "countyAbbrLength": 4,
    # "160 through 2 meters, excluding WARC bands (60, 30, 17 and 12 meters)"
    "validBands": BANDS,
    # "Phone QSO: 1 point; CW/digital QSO 2 points."
    "points": {"phone": 1, "cw": 2, "digital": 2},
    # "Stations may be worked once per band and mode (phone and CW/digital)".
    # NOTE the sponsor's mode split is TWO-WAY; this app keys on three mode
    # classes, so a CW + digital pair on one band is not flagged as a dupe. See
    # notes and ilqp_rules.md §5.
    "dupeScope": "bandMode",
    "multipliers": {
        # "IL stations multiply points by the sum of IL counties, US states, VE
        # provinces and DXCC countries (maximum 5) worked."
        "inState": {
            "classes": ["county", "state", "province", "dx"],
            # Never stated that an IL county also yields the IL state multiplier,
            # and IL stations send a county so the token IL is never received.
            # No in-state maximum to settle it by arithmetic.
            "homeStateCountsViaCounty": False,
            "countScope": "once",
            # "(maximum 5)" — honourable here, because DX sends a prefix.
            "dxMultCap": 5,
            # The sponsor counts DXCC entities individually -- see the
            # multiplier quote in the notes. Resolved against the ARRL
            # DXCC List (Resources/DXCC, generated by gen_dxcc.py).
            "dxCountsEntities": True,
        },
        # "Non-IL stations multiply points by the number of IL counties worked."
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
        },
    },
    # "NEW FOR 2025: BONUS STATIONS!! ... W9AWE (the historical call) and W9OAB
    # ... any entrant contacting these stations will have a 100 point bonus added
    # to the final score. Total of 200 points possible." Two fixed club calls, so
    # unlike PAQP's rotating station they ship; 200 total fixes the scope at once
    # per station.
    "bonuses": [
        {"type": "workStation", "call": "W9AWE", "points": 100, "scope": "once"},
        {"type": "workStation", "call": "W9OAB", "points": 100, "scope": "once"},
    ],
    # "others give RS/T and state, province or country" — in-state counts DXCC
    # countries separately, so the prefix is what distinguishes them.
    "dxStyle": "prefix",
    # Phone and CW/digital are all legal; FT4/FT8 earn no credit, which is below
    # the granularity of ModeClass. See notes.
    "allowedModes": ["phone", "cw", "digital"],
    # "Contacts with/by stations at the border of 2/3/4 counties count as 2/3/4
    # counties and 2/3/4 QSOs." Stated numerically, and the FAQ discusses three-
    # and four-county corners at length.
    "maxSimultaneousCounties": 4,
    # No DC rule is stated, so no alias is invented.
    # "IL stations give RS/T and county"
    "exchangeIncludesRST": True,
    # Not stated either way; shipped on with an open question, as for six other
    # parties.
    "outStateWorksHomeStationsOnly": True,
    # "Sunday the third full weekend of October" (sponsor's page) with the rules'
    # 1700Z-0100Z times: 18 October 2026 is that Sunday. Eight hours, the
    # shortest window and the only Sunday-only party here.
    "schedule": [{"start": "2026-10-18T17:00:00Z", "end": "2026-10-19T01:00:00Z"}],
    "counties": [{"abbr": a, "name": n} for a, n in sorted(counties.items(), key=lambda kv: kv[1])],
    "notes": (
        "verified: partial — rules from the Western Illinois Amateur Radio Club's official PDF "
        "('Announcing the 2025 Illinois QSO Party') and the club's official county abbreviation "
        "PDF, both read verbatim 2026-07-24, plus the ILQP page for the date formula. "
        "PROVENANCE NOTE WORTH KEEPING: a web search reported that ILQP awards 'one extra "
        "multiplier for every eight QSOs made with the same Illinois county'. NO SUCH RULE IS IN "
        "THE SPONSOR'S RULES - the multiplier paragraph is a plain sum with a DX cap - and taking "
        "it on trust would have inflated every ILQP score. The generator asserts the phrase is "
        "still absent. Retrieval note: the rules PDF sits on page 2 of the site's file browser, "
        "which paginates in JavaScript with no link href, so a plain fetch of w9awe.org/ilqp/ "
        "never reveals it. "
        "Phone 1 point, CW and digital 2. IL stations count IL counties + US states + VE "
        "provinces + DXCC countries with a cap of FIVE DX entities, all counted ONCE; non-IL "
        "stations count the 102 IL counties, once each. 'Canada, KH6 and KL7 do not count as DX "
        "entities', which is how this app already treats them - provinces and states "
        "respectively. Eight bands, 160 m through 2 m; note the sponsor counts 60 m among the "
        "'WARC bands' it excludes, which is loose but unambiguous, and the opposite of NYQP, "
        "which includes 60 m by excluding only three bands. County corners count 2, 3 or 4 "
        "counties as 2, 3 or 4 QSOs, stated numerically, so the county-line limit is four; county "
        "lines formed by waterways may not be activated. Both club callsigns, W9AWE and W9OAB, "
        "pay a 100-point bonus once each for a maximum of 200. "
        "KNOWN LIMITATION 1 - DUPES ACROSS CW AND DIGITAL ARE NOT FLAGGED. The sponsor's mode "
        "split is TWO-WAY: 'Stations may be worked once per band and mode (phone and CW/digital)'. "
        "This app keys dupes on three mode classes, so working one station on CW and again on "
        "RTTY on the same band shows as two valid QSOs when ILQP counts the second as a "
        "duplicate. Multipliers are unaffected - they count once regardless - and the sponsor's "
        "stated penalty is loss of the QSO with no further deduction, but the extra QSO points "
        "will not survive adjudication. KNOWN LIMITATION 2 - 'FT4 and FT8 contacts will receive "
        "no contact credit. Other digital modes are encouraged.' That distinction is below the "
        "granularity of this app's mode classes, so an FT8 QSO logs and scores here and earns "
        "nothing from the sponsor. "
        "No final-score multiplier; power classes and the new Unlimited class decide awards only, "
        "and the high/low boundary moved to 100 W for 2025 (it was 200 W). Cabrillo CONTEST value "
        "IL-QSO-PARTY per WA7BNM; the sponsor prefers Cabrillo but explicitly accepts an Excel or "
        "hand-written paper log, and prints no header token. Counties are 102 with MIXED 3- AND "
        "4-CHARACTER abbreviations - the rules say 'Each Illinois county has an established 4 "
        "letter abbreviation (Lee County excepted)', so LEE is the only 3-letter code. The rules "
        "name their own worst traps and the generator asserts both pairs: 'White (WHIT) and "
        "Whiteside (WTSD)' and 'Mason (MASN) and Macon (MACN)'. That second pair also settles a "
        "conflict between two sponsor documents - the website FAQ says Macon should be MCON, "
        "while the county list and the rules both say MACN, so MACN ships. "
        "OPEN QUESTIONS (why this is partial): (1) The published rules are the 2025 edition and "
        "the site's banner still reads 'Next Date for the ILQP: October 19, 2025'. The DATE is "
        "not in doubt - the sponsor's page prints the formula 'Held Annually on Sunday the third "
        "full weekend of October', 18 October 2026 is that Sunday, and the same formula "
        "reproduces the 2025 date the rules print - but no 2026 rule revision has been posted, "
        "and in particular the bonus stations are marked 'NEW FOR 2025' and have run only once. "
        "Re-check w9awe.org/ilqp before 18 October 2026 (the rules PDF is on page 2 of the file "
        "browser) and re-run gen_ilqp.py, whose quoted-sentence assertions fail loudly if the "
        "text moved. (2) Whether Illinois itself counts as a state multiplier for IL entrants is "
        "not stated, and there is no in-state maximum to settle it by arithmetic; shipped as NOT "
        "counting, the same call as NHQP, MEQP and SDQP. (3) No rule states whether stations "
        "outside Illinois may work only Illinois stations; out-of-state multipliers are IL "
        "counties only, and the restriction ships ON as for six other parties, so a stray non-IL "
        "contact is visibly flagged NO CREDIT. Confirm all three with the sponsor "
        "(n9jf@arrl.net) before submitting a log."
    ),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(ilqp, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"ilqp.json: {len(counties)} counties, lengths {lengths} (LEE is the only 3)")
print(f"  out-of-state ceiling: {len(counties)} counties, counted once")
print(f"  in-state: counties + states + provinces + DXCC capped at 5, counted once")
print(f"  bands: {len(BANDS)} — 160 m through 2 m, 60/30/17/12 excluded")
print(f"  bonuses: W9AWE +100 and W9OAB +100, once each (200 max)")
print(f"  schedule: 1 window, 8 h Sunday-only (1700Z 18 Oct -> 0100Z 19 Oct 2026)")
