#!/usr/bin/env python3
"""Generate Resources/Parties/miqp.json — the Michigan QSO Party.

Per CONSTITUTION.md Article 2: the county list is parsed, never typed.

THE LIVE SITE HAD ALREADY ROLLED FORWARD TO 2027 when this was built - its
header reads "Next MiQP Sat 17 Apr 2027" - so the 2026 edition comes from the
Wayback Machine and BOTH EDITIONS ARE BANKED AND DIFFED HERE. Exactly one
sentence differs, and this script asserts both halves of it so the difference
can never be absorbed silently:

  2026-03-14: "...49 American states (excluding Michigan), and 13 Canadian..."
  live 2027 : "...49 American states (excluding Michigan) + 1 District of
               Columbia, 13 Canadian..."

That reads like a scoring change and is not one. The rules defer to the Official
List of Mults twice, in BOTH editions, and the list archived four days before
the 2026 contest already carried DC - so the 2027 edit is a clarification of
wording. The mult lists are diffed here too, which is what proves it.

Sources (all banked):

  miqp_rules_2026.txt        web.archive.org/web/20260314141558/miqp.org/index.php/rules/
  miqp_rules_live_2027.txt   https://miqp.org/index.php/rules/          (for the diff)
  miqp_mults_2026.tsv        web.archive.org/web/20260414033926/.../official-list-of-mults/
  miqp_mults_live_2027.tsv   https://miqp.org/index.php/official-list-of-mults/
  miqp_cabrillo_2026.txt     https://miqp.org/index.php/cabrillo-information/
  miqp_cabrillo_name.txt     WA7BNM Cabrillo Names (Article 1 exception - header only)

  All fetched 2026-07-26. See miqp_rules.md.

THE SPONSOR'S MULT PAGE CROSS-CHECKS ITSELF. It prints the 83 counties twice -
once inside the 147-entry Michigan-station table (49 states + DC + 13 provinces
+ DX + 83 counties) and once alone in the 83-entry non-Michigan table. Both are
parsed and required to agree.

Run:  python3 docs/research/gen_miqp.py
"""

import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "miqp.json")

# The app's own thirteen, duplicated here only so the sponsor's list can be
# checked against it. North Dakota's is different; Michigan's is not.
APP_PROVINCES = {"AB", "BC", "MB", "NB", "NL", "NT", "NS", "NU", "ON", "PE",
                 "QC", "SK", "YT"}


def read(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        s = f.read()
    for a, b in [("’", "'"), ("‘", "'"), ("“", '"'),
                 ("”", '"'), ("–", "-"), ("—", "-"), (" ", " ")]:
        s = s.replace(a, b)
    return s.split("=" * 72, 1)[-1]


def tsv(name):
    """The banked mult page, as {table index: [(abbr, long), ...]}."""
    out, cur = {}, None
    for line in read(name).splitlines():
        line = line.rstrip()
        # The table marker is itself a '#' line, so it has to be matched before
        # the provenance comments are skipped.
        m = re.match(r"### TABLE (\d+)", line)
        if m:
            cur = int(m.group(1))
            out[cur] = []
            continue
        if line.startswith("#") or not line.strip() or cur is None:
            continue
        cells = line.split("\t")
        if cells[:2] == ["Abbr", "Long"]:
            continue
        abbr = cells[0].strip()
        long = cells[1].strip() if len(cells) > 1 else ""
        if abbr:
            out[cur].append((abbr, long))
    return out


# --------------------------------------------------------------- the two rules
rules = read("miqp_rules_2026.txt")          # THE AUTHORITY
live = read("miqp_rules_live_2027.txt")      # for the diff only

a = [l.strip() for l in rules.splitlines() if l.strip()]
b = [l.strip() for l in live.splitlines() if l.strip()]
changed = [(x, y) for x, y in zip(a, b) if x != y]

assert len(a) == len(b), (
    f"the 2027 rules gained or lost lines ({len(a)} vs {len(b)}) - re-read both "
    "editions by hand before trusting anything below")
assert len(changed) == 1, (
    f"expected exactly one changed sentence between the 2026 and 2027 editions, "
    f"found {len(changed)}: {changed}")

was, now = changed[0]
assert was == (
    'For Michigan stations, multipliers are the 83 Michigan counties, 49 American '
    'states (excluding Michigan), and 13 Canadian provinces (NL, NB, NS, PE, QC, ON, '
    'MB, SK, AB, BC, NT, YT, NU), and "DX" (a non-W/VE station).'), was
assert now == (
    'For Michigan stations, multipliers are the 83 Michigan counties, 49 American '
    'states (excluding Michigan) + 1 District of Columbia, 13 Canadian provinces (NL, '
    'NB, NS, PE, QC, ON, MB, SK, AB, BC, NT, YT, NU), and "DX" (a non-W/VE station).'), now

# ------------------------------------------------------------------ the mults
mults_2026 = tsv("miqp_mults_2026.tsv")
mults_live = tsv("miqp_mults_live_2027.tsv")

# THIS IS WHAT SETTLES THE DC QUESTION. The rules sentence changed; the list the
# rules defer to did not, and it already carried DC before the 2026 contest.
assert mults_2026 == mults_live, (
    "the multiplier list changed between editions - the DC finding in "
    "miqp_rules.md section 6 has to be re-argued from scratch")
assert ("DC", "DISTRICT OF COLUMBIA") in mults_2026[0], \
    "DC must be on the list archived four days before the 2026 contest"

michigan_table, outside_table = mults_2026[0], mults_2026[1]
assert len(michigan_table) == 147, len(michigan_table)
assert len(outside_table) == 83, len(outside_table)

# Split the Michigan table into its four parts by what each token is.
counties_a = {a: n for a, n in michigan_table if len(a) in (3, 4) and a not in APP_PROVINCES
              and a != "DX" and len(a) > 2}
tokens = {a for a, _ in michigan_table if len(a) == 2}
assert "DX" in {a for a, _ in michigan_table}, "DX is itself a listed multiplier"

provinces = tokens & APP_PROVINCES
states = tokens - APP_PROVINCES - {"DX"}   # DX is two letters too, and is its own class
assert len(provinces) == 13, sorted(provinces)
assert provinces == APP_PROVINCES, (
    "Michigan's thirteen should be the app's thirteen - North Dakota's are not, "
    "so this is worth checking rather than assuming")
assert len(states) == 50, sorted(states)          # 49 states + DC
assert "DC" in states
assert "MI" not in states, '"49 American states (excluding Michigan)"'

assert len(counties_a) == 83, len(counties_a)
assert len(counties_a) + len(states) + len(provinces) + 1 == 147, "the sponsor's table"

# The sponsor prints the counties twice. Require its own two copies to agree.
counties_b = {a: n for a, n in outside_table}
assert counties_a == counties_b, {
    k: (counties_a.get(k), counties_b.get(k))
    for k in set(counties_a) ^ set(counties_b)
}

counties = [{"abbr": a, "name": n.title()} for a, n in sorted(counties_a.items())]
assert len({c["name"] for c in counties}) == 83, "county names must be unique"

lengths = sorted({len(c["abbr"]) for c in counties})
assert lengths == [3, 4], lengths
threes = sorted(c["abbr"] for c in counties if len(c["abbr"]) == 3)
assert threes == ["BAY"], f"BAY should be the only 3-letter code, got {threes}"

by_abbr = {c["abbr"]: c["name"] for c in counties}
assert by_abbr["OAKL"] == "Oakland", "the county in the sponsor's own worked example"
assert by_abbr["WASH"] == "Washtenaw", "and the one in its Cabrillo example"

# The sponsor's table is all upper case, so names are title-cased on the way in.
# These are the five that title-casing could plausibly mangle, and does not.
# Note "St Clair" and "St Joseph" carry no full stop - the sponsor prints none.
for abbr, name in [("GRTR", "Grand Traverse"), ("PRES", "Presque Isle"),
                   ("STCL", "St Clair"), ("STJO", "St Joseph"),
                   ("VANB", "Van Buren")]:
    assert by_abbr[abbr] == name, (abbr, by_abbr.get(abbr))

# ------------------------------------------------------------- the rules, read
flat = re.sub(r"\s+", " ", rules)

assert ("Non-Michigan stations may work only Michigan stations, while Michigan "
        "stations may contact anyone.") in flat

# The date, as a formula with no year in it - which is why the site rolling
# forward to 2027 did not corrupt it.
assert "occurs annually on the Saturday of the third full weekend in April" in flat
assert ("The contest period runs from 1200 EDT (noon in Detroit, MI) to 2400 EDT "
        "(midnight in Detroit, MI) (16Z Saturday until 04Z Sunday UTC)") in flat
assert "All stations may operate the full twelve hours." in flat
assert "2026" not in flat, "the 2026 rules never name their own year"

# Bands and modes, with the sponsor's own worked example of the dupe rule.
assert "CW and SSB on 80, 40, 20, 15 and 10 meters." in flat
assert "Stations may be worked once per band and mode." in flat
assert ("may be contacted on each of the (5) bands [80m-10m] on each of the (2) modes "
        "[CW,SSB] for a maximum of (10) ten QSOs.") in flat
assert "No cross-mode contacts." in flat
assert "digital" not in flat.lower() and "RTTY" not in flat, "CW and SSB only"

# The exchange, including the two parenthetical rulings.
assert "Michigan stations send a RST, and their Michigan county." in flat
assert ("Non-Michigan W/VE stations (including KH6/KL7) send a RST, and their state "
        "or province.") in flat
assert ('Stations outside of the U.S.A. (including KP2/KP4) or Canada send a RST, and '
        '"DX".') in flat
assert "change from QSO# to RST for 2022" in flat, \
    "a source predating 2022 would have this party exchanging a serial"

# Points and scope.
assert "Each complete non-duplicate SSB contact is worth one point." in flat
assert "Each complete non-duplicate CW contact is worth two points." in flat
assert ("Multipliers are counted once per mode. Working the same multiplier on both CW "
        "and SSB counts as two multipliers.") in flat
assert "For non-Michigan stations, multipliers are the 83 Michigan counties." in flat
assert ("Multipliers for mobile entrants are the same as above and apply to the overall "
        "log regardless of the number of counties activated.") in flat
assert "Final Score - multiply total QSO points by the total number of multipliers." in flat

# County lines: forbidden outright, not merely split into separate contacts.
assert ("No station may claim simultaneous operation in more than one county, state, or "
        "province.") in flat
assert ("A mobile or rover station must move a minimum of 500 feet before claiming to be "
        "in a new county, state or province.") in flat

# Power categorises but does not scale, and nothing pays a bonus.
assert "QRP (5W transmitter output or less)" in flat
assert "bonus" not in flat.lower(), "a bonus rule would need modelling"

# Cabrillo: the sponsor has a page about it and still never names a header.
cab = read("miqp_cabrillo_2026.txt")
assert "MiQP does NOT use Cabrillo header info" in re.sub(r"\s+", " ", cab)
assert "CONTEST:" not in cab, \
    "if the sponsor ever prints a CONTEST: header, drop the WA7BNM exception"
assert "QSO: 7040 CW 2021-04-17 1648 K8MQP 599 WASH K8MAD 599 OH" in cab
assert "Michigan stations must list county abbreviation and NOT MI or MICH" in cab
name = read("miqp_cabrillo_name.txt")
assert "Michigan QSO Party" in name and "MI-QSO-PARTY" in name

NOTES = (
    "verified: partial - rules and multiplier list from the Mad River Radio Club's own "
    "site, read verbatim 2026-07-26. THE LIVE SITE HAD ALREADY ROLLED FORWARD TO 2027 by "
    "then ('Next MiQP Sat 17 Apr 2027'), so the 2026 edition comes from the Wayback "
    "Machine - rules archived 2026-03-14, five weeks before the contest, and the "
    "multiplier list archived 2026-04-14, four days before it. BOTH EDITIONS ARE BANKED "
    "AND DIFFED by the generator, which is how the one real change was found rather than "
    "absorbed. EXACTLY ONE SENTENCE DIFFERS: the 2027 rules add '+ 1 District of Columbia' "
    "to the Michigan-station multiplier list. THAT IS A CLARIFICATION, NOT A RULE CHANGE - "
    "the rules defer to the Official List of Mults twice in both editions ('the official "
    "abbreviations must be used to assure scoring credit'), and the list archived four "
    "days before the 2026 contest already carried DC and is otherwise identical to the "
    "live one. DC ships as a multiplier, correct for both years. THE RULES CARRY NO YEAR "
    "AT ALL - the date is a formula, 'the Saturday of the third full weekend in April', "
    "which is why the rollover did not corrupt them; and the formula reproduces the "
    "sponsor's own stated 'Sat 17 Apr 2027' exactly, which verifies the reading better "
    "than any calendar could. Twelve hours, 16Z to 04Z. FIVE BANDS AND TWO MODES - 80 "
    "through 10 metres, CW and SSB, no 160 m, no 6 m, NO DIGITAL - the narrowest band list "
    "in this app, and the sponsor works the dupe arithmetic out loud: 5 bands x 2 modes = "
    "10 QSOs with one station. Multipliers count PER MODE, so the same multiplier on CW "
    "and on SSB is two. Michigan is NOT a state multiplier ('49 American states (excluding "
    "Michigan)'); MI stations count the 83 counties instead. DX IS A REAL MULTIPLIER here, "
    "worth one per mode, since the exchange is the literal token - so unlike Georgia and "
    "North Dakota this is not a points-but-no-multiplier party. The 13 provinces ARE the "
    "app's standard 13, listed in full by the sponsor, so no override is needed - unlike "
    "North Dakota's. COUNTY LINES ARE FORBIDDEN OUTRIGHT: 'No station may claim "
    "simultaneous operation in more than one county, state, or province', with a 500-foot "
    "minimum move - stricter than North Dakota, which permits parking on the line and only "
    "requires separate contacts. The sponsor rules on the awkward cases in the exchange "
    "itself: KH6/KL7 are W/VE and send HI/AK, KP2/KP4 are not and send DX. The exchange "
    "became RST rather than a QSO number in 2022, so any source predating that is wrong. "
    "The Cabrillo CONTEST header is the one thing not from the sponsor: it has a whole "
    "page about Cabrillo and deliberately names no header ('MiQP does NOT use Cabrillo "
    "header info as it has been found over the years to be incorrect'), so MI-QSO-PARTY "
    "comes from WA7BNM's Cabrillo Names table under Article 1's exception. No bonus points "
    "and no power or station score multiplier: 'Final Score - multiply total QSO points by "
    "the total number of multipliers.' NO OPEN QUESTIONS - every modelled rule is stated, "
    "the changed sentence is settled by a second source, and the date formula is confirmed "
    "against the sponsor's own future date. It is partial only because the 2026 rules came "
    "from an archive rather than a live page."
)

party = {
    "schemaVersion": 1,
    "id": "miqp",
    "name": "Michigan QSO Party",
    "cabrilloContest": "MI-QSO-PARTY",
    "homeState": "MI",
    "countyAbbrLength": 4,
    "validBands": ["80m", "40m", "20m", "15m", "10m"],
    "points": {"phone": 1, "cw": 2, "digital": 0},
    "dupeScope": "bandMode",
    "multipliers": {
        # 83 counties + 49 states + DC + 13 provinces + DX = 147, per mode.
        "inState": {
            "classes": ["county", "state", "province", "dx"],
            "homeStateCountsViaCounty": False,
            "countScope": "perMode",
        },
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "perMode",
        },
    },
    "bonuses": [],
    "dxStyle": "token",
    "allowedModes": ["phone", "cw"],
    "maxSimultaneousCounties": 1,
    "exchangeIncludesRST": True,
    "outStateWorksHomeStationsOnly": True,
    "schedule": [
        {"start": "2026-04-18T16:00:00Z", "end": "2026-04-19T04:00:00Z"},
    ],
    "counties": counties,
    "hubSpots": {
        "tableURL": "http://qsopartyhub.com/miqp-table.php",
        "postURL": "http://qsopartyhub.com/miqp-spots.php",
    },
    "notes": NOTES,
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(party, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"miqp.json: {len(counties)} counties, parsed from the sponsor's own two copies")
print("  THE TWO RULE EDITIONS DIFFER IN EXACTLY ONE SENTENCE:")
print("    2026: '...49 American states (excluding Michigan), and 13 Canadian...'")
print("    2027: '...49 American states (excluding Michigan) + 1 District of Columbia...'")
print("    ...and the mult lists are IDENTICAL, with DC on both - so it is a")
print("    clarification, not a rule change. DC ships as a multiplier.")
print(f"  the Michigan table is {len(states)} states+DC + {len(provinces)} provinces "
      f"+ DX + {len(counties)} counties = {len(michigan_table)}")
print("  BAY is the only 3-letter code; every other is 4")
print("  5 bands, 2 modes - the narrowest band list here; no digital")
print("  points: SSB 1, CW 2; multipliers PER MODE; DX is a real multiplier")
print("  county lines FORBIDDEN outright, 500-foot minimum move")
print("  schedule: 1 window, 12 h - formula only, no year printed anywhere")
print(f"  wrote {os.path.normpath(OUT)}")
