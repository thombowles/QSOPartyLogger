#!/usr/bin/env python3
"""Generate sdqp.json from the sponsor's own county list and rules page.

Sources (committed alongside this script, so the run is reproducible):
  sdqp_counties.txt            — text of https://sdqsoparty.com/23-2/south-dakota-counties/
                                 (the 66 counties, one per line — the cleanest source)
  sdqp_rules_page.txt          — text of https://sdqsoparty.com/, the CURRENT rules,
                                 headed "South Dakota QSO Party - October 10 & 11, 2026"
  sdqp_rules_2023_superseded.txt — the stale /23-2/ sub-site, headed "2022 CONTEST
                                 RULES", kept for the diff note in sdqp_rules.md §4
  sdqp_rules.md                — full rules research; all fetched 2026-07-24

CAUTION for the next session: sdqsoparty.com serves TWO rule pages. The root is
current; the /23-2/ sub-site is three years stale and still reachable. Read the
root. This script asserts the root still carries the 2026 heading.

Sponsor: Prairie Dog Amateur Radio Club, Yankton SD. Bonus station W0OJY.

Usage:  python3 gen_sdqp.py        (run from docs/research/)
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "sdqp.json")
COUNTIES = os.path.join(HERE, "sdqp_counties.txt")
RULES = os.path.join(HERE, "sdqp_rules_page.txt")
OLD = os.path.join(HERE, "sdqp_rules_2023_superseded.txt")


def read(path):
    return open(path, encoding="utf-8").read().replace("’", "'").replace("“", '"').replace("”", '"')


counties_raw = read(COUNTIES)
rules = re.sub(r"\s+", " ", read(RULES))
old_rules = re.sub(r"\s+", " ", read(OLD))

# --- Counties: "ABBR County name, SD", one per line. ---
counties = {}
for line in counties_raw.splitlines():
    m = re.match(r"^\s*([A-Z]{3,4})\s+(.+?)\s*,\s*SD\s*$", line)
    if not m:
        continue
    abbr, name = m.group(1), m.group(2).strip()
    # The sponsor annotates the renamed county: "Oglala Lakota (Former Shannon
    # county)". The display name is the county's name; the note is an operator
    # aid, not part of it. See sdqp_rules.md §13.
    name = re.sub(r"\s*\(Former [^)]*\)", "", name).strip()
    if abbr in counties:
        sys.exit(f"SDQP duplicate county abbreviation: {abbr}")
    counties[abbr] = name

assert len(counties) == 66, f"expected 66 SD counties, got {len(counties)}: {sorted(counties)}"
assert len(set(counties.values())) == 66, "SD county names not unique"

# Mixed abbreviation lengths — only the Salmon Run has done this before.
lengths = sorted({len(a) for a in counties})
assert lengths == [3, 4], f"expected 3- and 4-letter abbreviations, got {lengths}"
three = [a for a in counties if len(a) == 3]
assert three == ["DAY"], f"DAY should be the only 3-letter code, got {sorted(three)}"

# The renamed county, and the pairs the abbreviation scheme exists to separate.
assert counties["OGLA"] == "Oglala Lakota", \
    f"OGLA should display as Oglala Lakota, got {counties['OGLA']!r}"
assert "(Former Shannon county)" in counties_raw, \
    "the sponsor's Shannon note is gone — check whether the county list changed"
for abbr, name in [
    ("BRWN", "Brown"), ("BROO", "Brookings"),   # BROW/BROO would have collided
    ("CLRK", "Clark"), ("CLAY", "Clay"),
    ("DEWY", "Dewey"), ("DGLS", "Douglas"),
    ("HNSN", "Hanson"), ("HAND", "Hand"),       # HANS/HAND, one letter apart
    ("HRDG", "Harding"), ("JKSN", "Jackson"), ("MRSH", "Marshall"),
    ("MCOO", "McCook"), ("MCPH", "McPherson"),  # internal capitals
    ("BONH", "Bon Homme"), ("CHAR", "Charles Mix"), ("FALL", "Fall River"),
    ("DAY", "Day"),
]:
    assert counties.get(abbr) == name, f"{abbr} should be {name}, got {counties.get(abbr)!r}"

# --- Bands: "160m thru 70cm (no WARC bands)", cross-checked against the
# sponsor's own suggested-frequency table, which tabulates exactly these ten. ---
BANDS = ["160m", "80m", "40m", "20m", "15m", "10m", "6m", "2m", "1.25m", "70cm"]
assert "160m thru 70cm (no WARC bands)" in rules, "the band sentence changed — re-read the source"
for band in ["160m", "80m", "40m", "20m", "15m", "10m", "6m", "2m", "1.25m", "70cm"]:
    assert band in rules, f"{band} is missing from the suggested-frequency table"
for warc in ["12m", "17m", "30m", "60m"]:
    assert warc not in BANDS

# --- The rule sentences this file encodes. ---
for quote in [
    "South Dakota QSO Party - October 10 & 11, 2026",
    "1 PM Central Daylight Time Saturday to 1 PM Central Daylight Time Sunday. GMT is 1800z",
    "2nd full weekend of October",
    "Stations outside South Dakota send signal report and state, province or DXCC country",
    "South Dakota stations send signal report and county",
    "Stations may be worked only once per mode per band",
    "Phone contacts are worth 1 point. CW contacts are worth 2 points",
    "The South Dakota QSO Party does not include digital modes",
    "South Dakota counties may only be used ONCE as a multiplier",
    "the total of the South Dakota counties worked, US States, Provinces and DXCC countries",
    "The sponsoring station 100 point bonus may only be used once",
    "County line contacts will count as multiple contacts for both, but must be logged separately",
    "QSO Points x Multipliers = Total + Bonus = Grand Total",
    "Logs Are Due by 08:00 hours Central Daylight Time(13:00z) on October 24, 2026",
]:
    assert quote in rules, f"current rules no longer contain: {quote!r}"

# The bonus station's own page states the scope a second time.
assert "may only be worked once regardless of mode" in re.sub(r"\s+", " ", counties_raw), \
    "the county page's bonus-station note changed"

# The stale sub-site must still be the stale one — if it ever gets updated, the
# provenance note in sdqp_rules.md §1 needs revisiting.
assert "2022 CONTEST RULES" in old_rules, \
    "the /23-2/ sub-site is no longer the superseded copy — re-read sdqp_rules.md §1"

# The sponsor's own worked example, reproduced in the tests.
assert "50 contacts SSB x 20 counties = 1,000 points + 100 bonus = 1,100 points" in rules, \
    "the worked example changed — update the test that reproduces it"

sdqp = {
    "schemaVersion": 1,
    "id": "sdqp",
    "name": "South Dakota QSO Party",
    # Sponsor requires Cabrillo but prints no CONTEST: token; WA7BNM registry
    # (Article 1 exception). Note the short form, like TQP's TXQP.
    "cabrilloContest": "SDQSOP",
    "homeState": "SD",
    # Mixed 3/4 — reported by countyAbbrLengths; this field is the entry hint.
    "countyAbbrLength": 4,
    # "160m thru 70cm (no WARC bands)"
    "validBands": BANDS,
    # "Phone contacts are worth 1 point. CW contacts are worth 2 points."
    "points": {"phone": 1, "cw": 2, "digital": 2},
    # "Stations may be worked only once per mode per band"
    "dupeScope": "bandMode",
    "multipliers": {
        # "Stations inside South Dakota multiply QSO points by the total of the
        # South Dakota counties worked, US States, Provinces and DXCC countries."
        "inState": {
            "classes": ["county", "state", "province", "dx"],
            # Never stated that an SD county also yields the SD state multiplier,
            # and SD stations send a county so the token SD is never received.
            # No in-state maximum to settle it by arithmetic — see sdqp_rules.md §6.
            "homeStateCountsViaCounty": False,
            "countScope": "once",
        },
        # "Stations outside South Dakota multiply QSO points by total South Dakota
        # counties worked." / "counties may only be used ONCE as a multiplier"
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
        },
    },
    # "Stations that work the Sponsoring Club (W0OJY) station during the event may
    # claim an extra 100 points ... may only be used once", and the county page:
    # "may only be worked once regardless of mode".
    "bonuses": [{"type": "workStation", "call": "W0OJY", "points": 100, "scope": "once"}],
    # "state, province or DXCC country" — in-state stations count DXCC countries
    # separately, which needs the prefix. See sdqp_rules.md §3.
    "dxStyle": "prefix",
    # "The South Dakota QSO Party does not include digital modes."
    "allowedModes": ["phone", "cw"],
    # "County line contacts will count as multiple contacts for both, but must be
    # logged separately." Two QSOs, not one two-county QSO.
    "maxSimultaneousCounties": 1,
    # No DC rule is stated anywhere, so no alias is invented.
    # "send signal report and county" / "signal report and state"
    "exchangeIncludesRST": True,
    # An aim rather than a stated limit; shipped on for consistency, with an open
    # question. See sdqp_rules.md §6.
    "outStateWorksHomeStationsOnly": True,
    # "1 PM Central Daylight Time Saturday to 1 PM Central Daylight Time Sunday.
    # GMT is 1800z." CDT is UTC-5 and 10-11 Oct 2026 is still CDT (DST ends
    # 1 November), so 1800Z both ends — one continuous 24-hour window.
    "schedule": [{"start": "2026-10-10T18:00:00Z", "end": "2026-10-11T18:00:00Z"}],
    "counties": [{"abbr": a, "name": n} for a, n in sorted(counties.items(), key=lambda kv: kv[1])],
    "notes": (
        "verified: partial — rules from the Prairie Dog Amateur Radio Club's official page "
        "(sdqsoparty.com, headed 'South Dakota QSO Party - October 10 & 11, 2026'), read "
        "verbatim 2026-07-24, with the county list from the sponsor's own county page. "
        "PROVENANCE HAZARD FOR RE-VERIFICATION: sdqsoparty.com serves TWO rule pages. The "
        "root is current for 2026; the /23-2/ sub-site is a stale WordPress copy still headed "
        "'OCTOBER 14 - 15, 2023' and '2022 CONTEST RULES', still reachable and still linked "
        "from search results. Read the root. Nothing scoring-related differs between them - "
        "points, multipliers, bands, modes, classes, power and the mobile rule are word for "
        "word identical - so this is not an Article 20 rule change; the current page merely "
        "adds the explicit no-digital clause, a worked final-score example, fuller bonus "
        "wording and a spotting section. "
        "Counties are 66 with MIXED 3- AND 4-CHARACTER abbreviations - DAY (Day) is the only "
        "3-letter code and the other 65 are 4, so this is the second party after the Salmon "
        "Run where a single abbreviation length cannot describe the data. Several codes drop "
        "vowels to break collisions: BRWN Brown against BROO Brookings, CLRK Clark, DEWY "
        "Dewey, DGLS Douglas, HNSN Hanson against HAND Hand, HRDG Harding, JKSN Jackson, MRSH "
        "Marshall; MCOO McCook and MCPH McPherson carry internal capitals; BONH Bon Homme, "
        "CHAR Charles Mix and FALL Fall River are two-word names. NAMING NOTE: the sponsor "
        "prints 'OGLA Oglala Lakota (Former Shannon county)' - Shannon County was renamed "
        "Oglala Lakota County in 2015, the display name is Oglala Lakota, and the "
        "parenthetical is the sponsor's aid to operators with old county lists. "
        "Multipliers count ONCE on both sides, stated outright ('South Dakota counties may "
        "only be used ONCE as a multiplier'): out-of-state count the 66 SD counties, SD "
        "stations count SD counties plus US states, provinces and DXCC countries. Phone 1 "
        "point, CW 2, no digital modes at all. Ten bands - 160 m through 70 cm excluding the "
        "WARC bands - which ties PAQP for the widest list here and is cross-checked against "
        "the sponsor's own suggested-frequency table, row for row. W0OJY pays a 100-point "
        "bonus ONCE for the contest, stated twice ('may only be used once' and 'may only be "
        "worked once regardless of mode'); further W0OJY contacts score as ordinary QSOs. "
        "County lines are logged as SEPARATE contacts, so a county-line entry is refused; an "
        "SD mobile changing county is a new contact. No final-score multiplier - power classes "
        "decide the award, and note the unusual 150 W boundary between high and low rather "
        "than the customary 100 W. No DC rule is stated, so DC is loggable as its own token "
        "and is NOT folded into Maryland. The sponsor's own worked example is reproduced "
        "end-to-end in the tests: 'QSO Points x Multipliers = Total + Bonus = Grand Total "
        "(Example 50 contacts SSB x 20 counties = 1,000 points + 100 bonus = 1,100 points "
        "grand total)', which also confirms the bonus is added after the multiply. Cabrillo "
        "CONTEST value SDQSOP per WA7BNM - the short form, like TQP's TXQP rather than the "
        "usual XX-QSO-PARTY, and not a typo. "
        "OPEN QUESTIONS (why this is partial): (1) Whether South Dakota itself counts as a "
        "state multiplier for SD entrants is not stated. In-state multipliers include 'US "
        "States', but SD stations send a county so the token SD is never received, and there "
        "is no in-state maximum to settle it by arithmetic the way KSQP, COQP, IAQP and AZQP "
        "have one. Shipped as NOT counting, so as not to credit a multiplier the sponsor never "
        "described - the same call as NHQP and MEQP. (2) No rule states whether stations "
        "outside South Dakota may work only SD stations. The Object reads 'Stations outside "
        "South Dakota work as many South Dakota stations and counties as possible', which is "
        "an aim rather than a limit, and out-of-state multipliers are SD counties only. "
        "Shipped with the restriction ON, as for NJQP, IAQP, NHQP and PAQP, so a stray non-SD "
        "contact is visibly flagged NO CREDIT rather than silently adding points. Confirm both "
        "with the sponsor (w0ej@arrl.net) before submitting a log."
    ),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(sdqp, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"sdqp.json: {len(counties)} counties, abbreviation lengths {lengths} "
      f"(DAY is the only 3)")
print(f"  out-of-state ceiling: {len(counties)} counties, counted once")
print(f"  in-state: {len(counties)} counties + states + provinces + DXCC, counted once")
print(f"  bands: {len(BANDS)} — 160 m through 70 cm less WARC, matching the "
      f"sponsor's frequency table")
print(f"  bonus: W0OJY +100 once for the contest")
print(f"  schedule: 1 window, 24 h (1800Z Sat 10 Oct -> 1800Z Sun 11 Oct 2026)")
