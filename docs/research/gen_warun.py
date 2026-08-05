#!/usr/bin/env python3
"""Generate warun.json from the official WA county abbreviation list.

Sources (committed alongside this script, so the run is reproducible):
  warun_counties.tsv — the 39 Washington counties and their abbreviations, from
                       https://salmonrun.wwdxc.org/wa-county-abbreviations/
  warun_rules.md     — full rules research; the rules page was re-read and
                       quoted back verbatim on 2026-07-24

Sponsor: Western Washington DX Club (WWDXC), club call W7DX.
Rules "Updated - July 22, 2024"; 2026 dates from the site-wide sidebar.

Usage:  python3 gen_warun.py        (run from docs/research/)
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "warun.json")
SRC = os.path.join(HERE, "warun_counties.tsv")

counties = {}
for line in open(SRC, encoding="utf-8"):
    line = line.rstrip("\n")
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    parts = line.split("\t")
    if len(parts) != 2:
        sys.exit(f"malformed TSV row (want abbr/county): {line!r}")
    abbr, name = (p.strip() for p in parts)
    if abbr in counties:
        sys.exit(f"WA duplicate abbreviation: {abbr}")
    counties[abbr] = name

# Rules: "Washington counties (39)".
assert len(counties) == 39, f"expected 39 WA counties, got {len(counties)}"
assert len(set(counties.values())) == 39, "WA county names not unique"

# Unlike every other bundled party, WA abbreviations are MIXED length: 3 and 4.
lengths = sorted({len(a) for a in counties})
assert lengths == [3, 4], f"WA abbreviations should be 3 and 4 chars, got {lengths}"

# The 4-char codes exist precisely to disambiguate same-prefix pairs. Pin them:
# guessing a 3-char truncation would collide or mis-credit.
EXPECTED = {
    "CLAL": "Clallam", "CLAR": "Clark",
    "GRAN": "Grant", "GRAY": "Grays Harbor",
    "KITS": "Kitsap", "KITT": "Kittitas",
    "SKAG": "Skagit", "SKAM": "Skamania",
    "JEFF": "Jefferson", "KING": "King", "PEND": "Pend Oreille",
    # 3-char neighbours that could be confused with the above.
    "COL": "Columbia", "COW": "Cowlitz", "KLI": "Klickitat",
    "WAH": "Wahkiakum", "WAL": "Walla Walla", "WHA": "Whatcom", "WHI": "Whitman",
    "SAN": "San Juan", "SNO": "Snohomish", "SPO": "Spokane", "STE": "Stevens",
}
for abbr, name in EXPECTED.items():
    assert counties.get(abbr) == name, \
        f"{abbr} should be {name!r}, source says {counties.get(abbr)!r}"

# Rules, Washington stations: 39 counties + "US States less WA (49)" +
# "VE multipliers (13)" + "Up to 10 DXCC entities" = 111.
STATES_LESS_WA = 49   # DC counts as MD, so it adds nothing
PROVINCES = 13
DX_CAP = 10
ceiling = len(counties) + STATES_LESS_WA + PROVINCES + DX_CAP
assert ceiling == 111, f"WA in-state ceiling should be 111, computed {ceiling}"

warun = {
    "schemaVersion": 1,
    "id": "warun",
    "name": "Washington Salmon Run",
    "cabrilloContest": "WA-SALMON-RUN",
    "homeState": "WA",
    # Mixed 3/4; this is the maximum. The entry-field hint is derived from the
    # county data (PartyDefinition.countyAbbrLengthHint), not from this number.
    "countyAbbrLength": 4,
    # "Contest Bands: 160, 80, 40, 20, 15, 10, and 6 meters"
    "validBands": ["160m", "80m", "40m", "20m", "15m", "10m", "6m"],
    # "2 points for Phone / 3 points for CW". Digital is not a contest mode.
    "points": {"phone": 2, "cw": 3, "digital": 0},
    # "The same station may be worked for QSO points on each band on Phone and CW."
    "dupeScope": "bandMode",
    "multipliers": {
        # 39 counties + US States less WA (49) + VE (13) + up to 10 DXCC = 111.
        "inState": {
            "classes": ["county", "state", "province", "dx"],
            # "US States less WA (49)" — Washington is excluded outright.
            "homeStateCountsViaCounty": False,
            # "Each multiplier may be counted ONLY ONCE regardless of mode or band"
            "countScope": "once",
            # "Up to 10 DXCC entities other than US and VE can be worked for
            # multiplier credit." DX stations send a prefix, so this cap binds.
            "dxMultCap": 10,
            # "DXCC entities" one by one, and the sponsor's own "other than US
            # and VE" is what settles a token like PA or ON: the worked
            # callsign decides which of the two readings applies.
            "dxCountsEntities": True,
        },
        # "Non-Washington stations: Washington counties (39 total)" — only type.
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
        },
    },
    "bonuses": [
        # "A QSO with ... W7DX, will add a 500-point bonus for each mode (Phone
        # and CW). A total of 1000 points may be earned in this manner (not 500
        # points for each QSO on each different band)."
        {"type": "workStation", "call": "W7DX", "points": 500, "scope": "perMode"},
    ],
    # "DX stations send DXCC entity prefix" — not a literal token.
    "dxStyle": "prefix",
    # "Contest Modes: Phone and CW. We cannot accept WJST modes (e.g. FT-8/FT-4)"
    "allowedModes": ["phone", "cw"],
    # "District of Columbia counts as MD, Alaska and Hawaii count as states."
    "stateAliases": {"DC": "MD"},
    # "In the case of 3-county or more intersections ... only one county line
    # consisting of two counties may be run at a time."
    "maxSimultaneousCounties": 2,
    # OBJECT: "Stations outside Washington state work ONLY Washington state
    # stations for QSO Points and County Multiplier credit."
    "outStateWorksHomeStationsOnly": True,
    # "from 1600Z (9AM PDT) Saturday through 0700Z (12AM PDT) Sunday and then
    # from 1600Z - 2400Z (9AM-5PM PDT) Sunday ... the full 23 hours".
    # 2026: third full weekend = Sep 19-20. 15 h + 8 h = 23 h.
    "schedule": [
        {"start": "2026-09-19T16:00:00Z", "end": "2026-09-20T07:00:00Z"},
        {"start": "2026-09-20T16:00:00Z", "end": "2026-09-21T00:00:00Z"},
    ],
    "counties": [{"abbr": a, "name": n} for a, n in sorted(counties.items(), key=lambda kv: kv[1])],
    "notes": (
        "Verified against the sponsor's official rules (salmonrun.wwdxc.org/rules/, 'Updated "
        "- July 22, 2024', re-read and quoted back verbatim 2026-07-24); the 2026 dates come "
        "from the site-wide sidebar, 'Salmon Run 2026: 1600Z Saturday, September 19, 2026 - "
        "2359Z Sunday, September 20'. Sponsor is the Western Washington DX Club, club call "
        "W7DX. UNIQUE IN THIS REPO: Washington's county abbreviations are MIXED LENGTH, 3 and "
        "4 characters, because the 4-character codes disambiguate same-prefix pairs — "
        "CLAL/CLAR (Clallam/Clark), GRAN/GRAY (Grant/Grays Harbor), KITS/KITT "
        "(Kitsap/Kittitas), SKAG/SKAM (Skagit/Skamania) — so countyAbbrLength records the "
        "maximum and the entry-field hint is derived from the county data instead. Counties "
        "generated from the sponsor's abbreviation page via warun_counties.tsv, never "
        "hand-typed. Phone 2 pts, CW 3 pts (older editions used 4 for CW — do NOT use 4); "
        "digital is not a contest mode at all, so digital rows are invalid rather than "
        "zero-scored ('We cannot accept WJST modes ... because they do not provide the proper "
        "exchange'). Multipliers count ONCE regardless of mode or band on both sides. The "
        "in-state ceiling of 111 (39 counties + 49 states less WA + 13 VE + 10 DXCC) is "
        "asserted by the generator. Washington itself is never a state multiplier ('US States "
        "less WA'), DC counts as MD, and AK/HI count as states. DX stations send their DXCC "
        "ENTITY PREFIX rather than a literal token, so unlike NHQP the 10-DXCC cap actually "
        "binds — this is the only bundled party where dxMultCap has an effect. Out-of-state "
        "stations may work only Washington stations, stated outright in the OBJECT section: "
        "'Stations outside Washington state work only Washington state stations for QSO "
        "Points and County Multiplier credit.' County lines are logged as two QSOs and at "
        "most two counties may be run at once, even at a 3-county intersection. W7DX pays a "
        "500-point bonus PER MODE, capped at 1000 for a mixed-mode entry and 500 for a "
        "single-mode entry, added after multiplication and never per band or per QSO; W7DX "
        "also counts for its normal county multiplier and normal QSO points. No power or "
        "category multiplier. Cabrillo CONTEST value WA-SALMON-RUN, which the sponsor calls "
        "'our official name'. A PREFIX THAT EQUALS A STATE OR PROVINCE CODE IS NOW DECIDED BY "
        "THE CALLSIGN, as of 2026-08-01, and it matters more here than anywhere else because "
        "this is the party where DX prefixes carry the most multiplier weight. PA is both "
        "Pennsylvania and the Netherlands, ON both Ontario and Belgium, OK both Oklahoma and the "
        "Czech Republic, LA both Louisiana and Norway; the exchange token alone cannot tell them "
        "apart, and every one of them used to be read as the state or province, which could "
        "leave the 10-DXCC allowance under-used. The exchange field now says which LOCATION was "
        "sent and the callsign says which ENTITY sent it - the split N1MM makes, whose manual "
        "puts the exchange half as 'There is a check on provinces and states, no check on "
        "countries'. So PA0AAA sending PA is the Netherlands while W3XYZ sending PA is "
        "Pennsylvania, and the reading only flips when the callsign resolves to the very same "
        "entity the token names, which is why a VE5 sending SK stays Saskatchewan even though SK "
        "is Sweden's. This also delivers what the rules ask and this app used to list as not "
        "modeled: claimed DXCC prefixes are matched against the current ARRL DXCC Entities List "
        "(January 2026 edition, Resources/DXCC, generated by gen_dxcc.py), so a token the list "
        "does not carry is an error rather than a phantom entity. Not modeled: the "
        "single-mode-entry restriction (contacts on "
        "other modes earning no credit) is an entry-class matter this app does not track; and "
        "mobile and expedition entrants counting multipliers only once across all counties "
        "activated, which matches the engine's behaviour anyway."
    ),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(warun, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"warun.json: {len(counties)} counties, abbreviation lengths {lengths}")
print(f"  in-state ceiling: {len(counties)} + {STATES_LESS_WA} + {PROVINCES} + {DX_CAP} = {ceiling}")
print(f"  schedule: 15 h + 8 h = 23 h (rules say 23)")
