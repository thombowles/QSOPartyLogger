#!/usr/bin/env python3
"""Generate cqp.json from the sponsor's own multiplier table.

Nothing is hand-typed. The 58 counties are parsed out of the committed
multipliers-page text, and then every abbreviation is RE-DERIVED from the rule
the sponsor publishes alongside the table and asserted to match:

    "Use the first 4 characters of the county name to make them unique.
     This rule is broken for Contra Costa (CCOS) and Los Angeles (LANG).
     Marin (MARN) and Mariposa (MARP) counties are not unique in 4 characters.
     If the county name is one of the 10 counties that start with 'San' or
     'Santa' abbreviate that part to a single 'S'."

A typo would have to survive both the parse and the formula to reach the JSON.

Sources (committed alongside this script, so the run is reproducible):
  cqp_multipliers.txt  — text of https://www.cqp.org/cqp_multipliers.html
                         (county table, abbreviation formula, DC/MD fold,
                         Canadian list, "1st CA county counts as CA")
  cqp_rules_2026.txt   — pdftotext -layout of https://www.cqp.org/pdf/CQP_2026_Rules.pdf
                         "Rules: 2026 California QSO Party (CQP)
                          Last Update: 19-July-2026 at 1500 UTC"
  cqp_rules_2025.txt   — the superseded revision, kept for the Article 20 diff
                         (phone was 2 points in 2025, 3 in 2026)
  cqp_rules.md         — full rules research; all sources fetched 2026-07-24

Sponsor: Northern California Contest Club, https://www.cqp.org/Rules.html

Usage:  python3 gen_cqp.py        (run from docs/research/)
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "cqp.json")
MULTS = os.path.join(HERE, "cqp_multipliers.txt")
RULES = os.path.join(HERE, "cqp_rules_2026.txt")
RULES_2025 = os.path.join(HERE, "cqp_rules_2025.txt")


def read(path):
    return open(path, encoding="utf-8").read().replace("’", "'").replace("“", '"').replace("”", '"')


mults_raw = read(MULTS)
rules = re.sub(r"\s+", " ", read(RULES))
rules_2025 = re.sub(r"\s+", " ", read(RULES_2025))

# --- Counties: the table between the two multiplier headings. Rows arrive as
# an abbreviation line followed by its county-name line (the page lays the 58
# out in three columns, which flattens to that alternation). ---
m = re.search(
    r"CA County Multipliers for Out-of-State Participants \(58\)(.*?)"
    r"USA/Canada Multipliers for California Participants",
    mults_raw,
    re.S,
)
if not m:
    sys.exit("county table not found in cqp_multipliers.txt")

lines = [ln.strip() for ln in m.group(1).splitlines() if ln.strip()]
counties = {}
for i, line in enumerate(lines[:-1]):
    if re.fullmatch(r"[A-Z]{4}", line):
        name = lines[i + 1]
        # The formula prose above the table also contains bare 4-letter tokens
        # in parentheses; those are followed by prose, not a county name.
        if not re.fullmatch(r"[A-Za-z' ]{3,20}", name):
            continue
        if line in counties:
            sys.exit(f"CQP duplicate abbreviation: {line}")
        counties[line] = name

assert len(counties) == 58, f"expected 58 CA counties, got {len(counties)}: {sorted(counties)}"
assert len(set(counties.values())) == 58, "CA county names not unique"
assert all(len(a) == 4 for a in counties), "all CQP abbreviations are 4 letters"
# The sponsor states the count in three places; all must still say 58.
assert "CA County Multipliers for Out-of-State Participants (58)" in mults_raw
assert "Count all 58 California Counties for a maximum of 58 multipliers" in rules
assert "Maine" not in counties.values(), "wrong state's data"

# --- Re-derive every abbreviation from the sponsor's published formula. ---
# "If the county name is one of the 10 counties that start with San or Santa
#  abbreviate that part to a single S" -> S + first 3 of the remainder.
# Otherwise: first 4 characters of the name with spaces removed.
# Four names are called out as breaking the plain rule.
STATED_EXCEPTIONS = {
    "Contra Costa": "CCOS",   # "This rule is broken for Contra Costa (CCOS)"
    "Los Angeles": "LANG",    # "... and Los Angeles (LANG)"
    "Marin": "MARN",          # "Marin (MARN) and Mariposa (MARP) counties are
    "Mariposa": "MARP",       #  not unique in 4 characters"
}


def derived(name):
    if name in STATED_EXCEPTIONS:
        return STATED_EXCEPTIONS[name]
    m = re.match(r"^(San|Santa) (.+)$", name)
    if m:
        return ("S" + m.group(2).replace(" ", "")[:3]).upper()
    return name.replace(" ", "")[:4].upper()


san_family = [n for n in counties.values() if re.match(r"^(San|Santa) ", n)]
assert len(san_family) == 10, \
    f"the sponsor counts 10 San/Santa counties, formula found {len(san_family)}: {sorted(san_family)}"

for abbr, name in sorted(counties.items()):
    want = derived(name)
    assert want == abbr, f"{name}: sponsor's formula gives {want}, table says {abbr}"

# The exceptions must actually be exceptions — if a future edit made one of them
# regular, the "broken rule" prose would be stale and worth re-reading.
for name, abbr in STATED_EXCEPTIONS.items():
    plain = name.replace(" ", "")[:4].upper()
    assert plain != abbr, f"{name} no longer breaks the first-4 rule ({plain})"
assert "This rule is broken for" in mults_raw, "the abbreviation formula prose is gone — re-read the source"

# --- The rule sentences this file encodes. The sponsor revises in place at a
# stable URL, so these fail loudly rather than drifting. ---
for quote in [
    "Rules: 2026 California QSO Party (CQP)",
    "Begins: 1600 UTC - 03 October 2026",
    "Ends: 2200 UTC - 04 October 2026",
    "California stations send QSO number and 4-letter county abbreviation",
    "Each complete non-duplicate Phone contact is worth 3 points. **NEW in 2026**",
    "Each complete non-duplicate CW contact is worth 3 points",
    "Maximum of 58 Scored Multipliers out of 63 Total Multipliers",
    "the maximum number of counted multipliers toward the CA station's final score is 58",
    "Non-CA to non-CA contacts do not count for QSO credit",
    "Stations may be worked once on CW and once on Phone on each of the 6 bands",
    "BANDS: 160, 80, 40, 20, 15, and 10 meters",
    "MODES: CW, Phone",
]:
    assert quote in rules, f"2026 rules text no longer contains: {quote!r}"

# Article 20: the one substantive change from the superseded revision.
assert "Each complete non-duplicate Phone contact is worth 2 points" in rules_2025, \
    "the 2025 rules should still read 2 points for phone — recheck the diff note"
assert "Rules: 2025 California QSO Party (CQP)" in rules_2025

for quote in [
    "The first valid CA QSO logged with 4-letter county abbreviation will count as the multiplier for California",
    "1st CA county counts as CA",
    "Maryland & DC",
    "DX QSO's do not count for non-California participants",
]:
    assert re.sub(r"\s+", " ", mults_raw).find(quote) >= 0, \
        f"multipliers page no longer contains: {quote!r}"

# US states 50 + provinces 13 = the sponsor's stated 63 possible in-state mults.
IN_STATE_POSSIBLE = 50 + 13
assert IN_STATE_POSSIBLE == 63, "the rules' own 63-multiplier arithmetic"
SCORED_CAP = 58
assert SCORED_CAP == len(counties), \
    "the CA cap of 58 is exactly the county count — that is why the number is 58"

cqp = {
    "schemaVersion": 1,
    "id": "cqp",
    "name": "California QSO Party",
    # Sponsor prints no CONTEST: token; WA7BNM registry (Article 1 exception).
    "cabrilloContest": "CA-QSO-PARTY",
    "homeState": "CA",
    "countyAbbrLength": 4,
    # "BANDS: 160, 80, 40, 20, 15, and 10 meters"
    "validBands": ["160m", "80m", "40m", "20m", "15m", "10m"],
    # "(CW Qs x 3 pts) + (Phone Qs x 3 pts)" — phone rose from 2 in 2026.
    "points": {"phone": 3, "cw": 3, "digital": 3},
    # "Stations may be worked once on CW and once on Phone on each of the 6
    # bands (maximum of 12 QSOs with any one station)."
    "dupeScope": "bandMode",
    "multipliers": {
        # "A. California Stations: Maximum of 58 Scored Multipliers out of 63
        # Total Multipliers (U.S. states = 50 and Canadian provinces = 13)."
        # Counties are NOT an in-state class: a CA county's only multiplier
        # effect is to yield CA itself, once.
        "inState": {
            "classes": ["state", "province"],
            # "The first valid CA QSO logged with 4-letter county abbreviation
            # will count as the multiplier for California." Stated outright —
            # the multiplier table's CA row literally reads "1st CA county
            # counts as CA".
            "homeStateCountsViaCounty": True,
            "countScope": "once",
            "maxScoredMultipliers": SCORED_CAP,
        },
        # "B. Non-California Stations: Count all 58 California Counties for a
        # maximum of 58 multipliers." The stated maximum equals the county
        # count, so no separate cap is needed.
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
        },
    },
    # No bonus station, no bonus points. The special award categories are
    # claimed with SOAPBOX: lines and do not touch the score.
    "bonuses": [],
    # 'or "DX"' — the sponsor's preferred form; a DXCC prefix is permitted as an
    # alternative but carries no multiplier either way (see cqp_rules.md §3).
    "dxStyle": "token",
    # "MODES: CW, Phone" — no digital category exists.
    "allowedModes": ["phone", "cw"],
    # County-line stations send "all such counties in a single exchange"; the
    # sponsor's own logging guide uses DELN/SISK/HUMB and Writelog fields
    # CNTY/CTY2/CTY3/CTY4 — four.
    "maxSimultaneousCounties": 4,
    # Multiplier table prints "MD  Maryland & DC".
    "stateAliases": {"DC": "MD"},
    # "Canadian provinces/territories = 13" — the standard 13, unlike OhQP (11),
    # NJQP (NF for NL) or MEQP (14, NF and LB split). Left at the default.
    # "California stations send QSO number and 4-letter county abbreviation" —
    # there is no RST anywhere in the CQP exchange.
    "exchangeIncludesRST": False,
    # "Non-CA to non-CA contacts do not count for QSO credit."
    "outStateWorksHomeStationsOnly": True,
    # "Begins: 1600 UTC - 03 October 2026  Ends: 2200 UTC - 04 October 2026"
    "schedule": [{"start": "2026-10-03T16:00:00Z", "end": "2026-10-04T22:00:00Z"}],
    "counties": [{"abbr": a, "name": n} for a, n in sorted(counties.items(), key=lambda kv: kv[1])],
    "notes": (
        "Rules from the Northern California Contest Club's official page and PDF "
        "(cqp.org/Rules.html and cqp.org/pdf/CQP_2026_Rules.pdf, both stamped 'Rules: 2026 "
        "California QSO Party (CQP), Last Update: 19-July-2026 at 1500 UTC'), plus the "
        "multipliers page (cqp.org/cqp_multipliers.html) which alone carries the county "
        "table, the DC/MD fold and the 'first CA county counts as CA' rule. All read "
        "verbatim 2026-07-24. "
        "KNOWN LIMITATION - READ BEFORE SUBMITTING A LOG: the CQP exchange is 'QSO number "
        "and 4-letter county abbreviation' (or QSO number and state/province/DX). It "
        "carries NO RST, and this app does not yet model serial numbers at all. Scoring is "
        "unaffected - points and multipliers never depend on the serial - but the exported "
        "Cabrillo leaves the QSO-number element EMPTY, and CQP accepts Cabrillo only. Add "
        "serial numbers before submitting, or wait for serial support. "
        "RULE CHANGE FOR 2026: phone QSOs are now worth 3 points, up from 2; the sponsor "
        "marks it '**NEW in 2026**'. CW was and remains 3. A full diff against the still-"
        "published 2025 revision (cqp.org/pdf/CQP_2025_Rules.pdf, Last Update 05-July-2025) "
        "shows this is the ONLY substantive change between the two. "
        "Multipliers are asymmetric in an unusual way: California stations count STATES AND "
        "PROVINCES, never counties, with a cap of 58 SCORED multipliers out of 63 possible "
        "(50 states + 13 provinces) - the sponsor's own distinction between what accrues to "
        "the tally and what reaches the final score, so this app tallies all of them and "
        "scores at most 58. California itself is earned via a county: 'The first valid CA "
        "QSO logged with 4-letter county abbreviation will count as the multiplier for "
        "California', which the multiplier table restates as '1st CA county counts as CA' - "
        "the first party to state that rule outright rather than leave it to arithmetic. "
        "Non-California stations count the 58 counties, once each, and nothing else. DX "
        "scores QSO points for California stations but is NEVER a multiplier for anyone, and "
        "'DX QSO's do not count for non-California participants' at all, since 'Non-CA to "
        "non-CA contacts do not count for QSO credit'. Canada is the standard 13 including "
        "NL, and DC counts as Maryland. Six bands including 160 m, no WARC, no VHF; CW and "
        "phone only, so a digital QSO is invalid rather than zero-point. County lines are "
        "sent as one exchange and are capped at 4 counties, matching the sponsor's own "
        "logging guide (DELN/SISK/HUMB, and Writelog fields CNTY/CTY2/CTY3/CTY4); "
        "state-line operations are not allowed. A California mobile changing county or state "
        "is a new station for both point and multiplier credit. No bonus stations, no bonus "
        "points, no final-score multiplier - the special award categories are claimed with "
        "SOAPBOX: lines and do not touch the score. Cabrillo CONTEST value CA-QSO-PARTY per "
        "WA7BNM; the sponsor requires Cabrillo but prints no header token. County "
        "abbreviations are verified twice: parsed from the sponsor's table, then re-derived "
        "from the sponsor's own published formula (first 4 characters, 'San'/'Santa' folded "
        "to a single S, with Contra Costa, Los Angeles, Marin and Mariposa called out as "
        "exceptions) and asserted to match."
    ),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(cqp, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"cqp.json: {len(counties)} counties, all 4 letters, formula re-derived and matched")
print(f"  San/Santa family: {len(san_family)} (sponsor says 10)")
print(f"  exceptions to the first-4 rule: {', '.join(sorted(STATED_EXCEPTIONS.values()))}")
print(f"  in-state: {IN_STATE_POSSIBLE} possible multipliers, {SCORED_CAP} scored (= county count)")
print(f"  out-of-state ceiling: {len(counties)} counties once each (rules say 58)")
print(f"  schedule: 1 window, 30 h (1600Z Sat 3 Oct -> 2200Z Sun 4 Oct 2026)")
