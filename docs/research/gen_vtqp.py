#!/usr/bin/env python3
"""Generate vtqp.json from the Vermont QSO Party sponsor's own two documents.

Sources (committed alongside this script, so the run is reproducible):
  vtqp_rules_2026.txt — textutil -convert txt of https://www.ranv.org/vtqso.doc,
                        "VERMONT QSO Party Rules", created 2026-01-13, footer
                        "13-JAN-2026". THIS IS THE AUTHORITY.
  vtqp_page.txt       — text of https://www.ranv.org/vtqso.html, page-dated
                        January 31 2026. The sponsor calls it a summary and
                        points at the .doc; it is used here only for the county
                        NAMES (the .doc prints abbreviations only) and the
                        approved-club list.
  vtqp_rules.md       — full rules research; all fetched 2026-07-26

Sponsor: Radio Amateurs of Northern Vermont (RANV). Manager: W1SJ, w1sj@arrl.net.

The two documents cross-check each other on the county list: names come from the
page's table, and the resulting abbreviation set must equal the .doc's own
sentence "14 Vermont Counties: ADD, BEN, ...". Neither is trusted alone.

THE POWER MULTIPLIER SHIPS, x1.5 AND ALL. Rule 7(D)(1) pays QRP x2, low power
x1.5 and high power x1, and until 2026-07-28 ScoreMultipliers was [String: Int],
so nothing shipped at all: {QRP:2, LOW:1, HIGH:1} would have under-scored every
low-power entrant by 33% while looking correct. ScoreFactor made the factor an
exact fraction and this was the first party to want it.

WHAT STILL DELIBERATELY DOES NOT SHIP, both verified and both unrepresentable —
see vtqp_rules.md section 14 and the notes field:
  * approved Vermont CLUB STATION multipliers (W1NVT for 2026) — a multiplier
    keyed on callsign, which MultClass has no case for.
  * GRID SQUARE multipliers on WSJT-X modes (in-state: grids/3 rounded down;
    out-of-state: VT grids worked, max 5).

Usage:  python3 gen_vtqp.py        (run from docs/research/)
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "vtqp.json")
RULES = os.path.join(HERE, "vtqp_rules_2026.txt")
PAGE = os.path.join(HERE, "vtqp_page.txt")


def read(path):
    s = open(path, encoding="utf-8").read()
    return s.replace("’", "'").replace("“", '"').replace("”", '"')


rules = re.sub(r"\s+", " ", read(RULES))
page_raw = read(PAGE)
page = re.sub(r"\s+", " ", page_raw)

# --- Counties: the page's "ABBR<TAB>NAME" table, bounded so the VERMONT CLUBS
# table that follows (also CALL<TAB>NAME pairs) cannot leak in. ---
block = re.search(r"VERMONT COUNTIES(.*?)VERMONT CLUBS", page_raw, re.S)
if not block:
    sys.exit("VTQP: the county table is gone from the sponsor's page — re-read it")

counties = {}
for abbr, name in re.findall(r"^([A-Z]{3})\s*\t\s*([A-Z][A-Z ]+?)\s*$", block.group(1), re.M):
    name = " ".join(w.capitalize() for w in name.split())
    if abbr in counties and counties[abbr] != name:
        sys.exit(f"VTQP conflicting names for {abbr}: {counties[abbr]!r} vs {name!r}")
    counties[abbr] = name

assert len(counties) == 14, f"expected 14 VT counties, got {len(counties)}: {sorted(counties)}"
assert len(set(counties.values())) == 14, "VT county names not unique"
assert {len(a) for a in counties} == {3}, "VT abbreviations are uniformly 3 letters"

# The .doc states the abbreviations itself. Requiring the two sponsor documents
# to agree is the strongest cross-check available without a machine-readable file.
DOC_SENTENCE = ("14 Vermont Counties: ADD, BEN, CAL, CHI, ESS, FRA, GRA, LAM, "
                "ORA, ORL, RUT, WAS, WNH, WNS.")
assert DOC_SENTENCE in rules, \
    "the official rules' own county sentence changed — re-read vtqp_rules_2026.txt"
doc_abbrs = set(DOC_SENTENCE.split(":")[1].replace(".", "").replace(" ", "").split(","))
assert doc_abbrs == set(counties), \
    f"page table and rules sentence disagree: {doc_abbrs ^ set(counties)}"

# The sponsor names its own worst trap, which makes it the best spot check:
# "Take care to not mix up WiNdHam (WNH) and WiNdSor (WNS)!!"
assert "WiNdHam (WNH) and WiNdSor (WNS)" in page, "the sponsor's own trap note is gone"
for abbr, name in [
    ("WNH", "Windham"), ("WNS", "Windsor"),   # neither is the naive WIN
    ("GRA", "Grand Isle"),                    # NOT "Grand Island" — see rules.md 13
    ("CHI", "Chittenden"), ("CAL", "Caledonia"), ("LAM", "Lamoille"),
    ("ORA", "Orange"), ("ORL", "Orleans"),    # ORA/ORL are one letter apart
    ("ESS", "Essex"), ("FRA", "Franklin"), ("BEN", "Bennington"),
    ("ADD", "Addison"), ("RUT", "Rutland"), ("WAS", "Washington"),
]:
    assert counties.get(abbr) == name, f"{abbr} should be {name}, got {counties.get(abbr)!r}"

# --- Bands. This party publishes no band list: one prohibition and one blanket
# permission. See vtqp_rules.md section 10 for why 30/17/12 are IN (explicitly
# allowed for FT8/FT4, and validBands is not mode-scoped) and 60 m is OUT. ---
BANDS = ["160m", "80m", "40m", "30m", "20m", "17m", "15m", "12m", "10m",
         "6m", "2m", "1.25m", "70cm"]
assert ("Use of 30, 17 and 12 meters are prohibited except when operating FT8/FT4"
        in rules), "the WARC sentence changed — re-read it before trusting BANDS"
assert "VHF and UHF frequencies are allowed, but repeaters may not be used" in rules
assert "60m" not in BANDS, "60 m is excluded as an open question, not silently included"
# 60 m is excluded because the sponsor never mentions it. Assert that silence, so
# that a future edition adding 60 m fails here instead of passing unnoticed.
_freq_section = rules.split("8) Frequencies:")[1].split("9) Miscellaneous")[0]
assert "60 meter" not in _freq_section and "60m" not in _freq_section, \
    "the sponsor now says something about 60 m — re-read section 8 and revisit BANDS"

# --- The rule sentences this file encodes, quoted from the official .doc. ---
for quote in [
    # 2 Date/Time
    "will start at 0000 UTC on February 7, 2026 and end 2400 UTC on February 8, 2026",
    "This is a 48 hour period",
    "The Vermont QSO Party will be held on the first full weekend of February",
    # 6 Exchange
    "Vermont stations send signal report and Vermont county",
    "W/VE stations (including Alaska and Hawaii) send signal report and state or province",
    "DX stations (including U.S. Territories) send signal report",
    "Properly configured contest software will determine the DXCC country and list the official prefix",
    # 7(A) Points
    "Phone contact is worth 1 point",
    "CW contact is worth 3 points",
    "RTTY contact is worth 2 points",
    "Digital contact is worth 2 points",
    # 7(B) Multipliers
    "DC is counted as MD",
    "13 Canadian Provinces and Territories (per RAC listing): AB, BC, MB, NB, NL, NS, NT, NU, ON, PE, QC, SK, YT",
    "U.S., Canada, Alaska and Hawaii will not count as DXCC multipliers",
    "A multiplier can be counted only once per mode, regardless of the number of bands on which it is worked",
    "For Non-Vermont stations: Vermont Counties and Vermont Club Stations",
    # 7(B)(c) county line
    "may be claimed as a QSO and a multiplier from each county (2 QSO's and 2 multipliers)",
    # 9(D) dupes
    "Stations may be worked once per mode, per band",
    # 1 objective / out-of-state scope
    "Stations outside Vermont work Vermont stations. Stations within Vermont work everyone",
    # 1A(F) bonus
    "Stations OUTSIDE of Vermont will get an additional 2 point bonus for each W1AW/1 station they work",
    "Vermont stations will not get this bonus",
]:
    assert quote in rules, f"official rules no longer contain: {quote!r}"

# The power multiplier is real, is fractional, and SHIPS. If either assertion
# fails the sponsor changed the factors, which is the moment to change
# scoreMultipliers below to match — a wrong factor is a wrong score.
assert "multiply your score by 1.5" in rules, \
    "the x1.5 low-power multiplier changed — update scoreMultipliers"
assert "If all QSO's were made using 5W or less, multiply your score by 2" in rules

# W1AW/1 is a 2026-only America250/YOTC rule and must not survive into 2027.
assert "Special rules for W1AW/1 operation in 2026" in rules, \
    "the W1AW/1 rule is gone — REMOVE the bonus from vtqp.json (see notes)"

# The 2026 approved club multiplier, which this app cannot model (see notes).
assert "Club multiplier for 2026: W1NVT" in page, "the approved club call changed"

vtqp = {
    "schemaVersion": 1,
    "id": "vtqp",
    "name": "Vermont QSO Party",
    # Rule 10(A) requires Cabrillo but neither document prints a CONTEST: token;
    # WA7BNM registry entry 236 (Article 1's codified exception).
    "cabrilloContest": "VT-QSO-PARTY",
    "homeState": "VT",
    "countyAbbrLength": 3,
    # No band list is published: 30/17/12 prohibited except FT8/FT4, VHF+UHF
    # allowed, "any frequency allowed by their license" otherwise. See rules.md 10.
    "validBands": BANDS,
    # "Phone 1 point ... CW 3 points ... RTTY 2 points ... Digital 2 points".
    # RTTY and WSJT-X pay alike, so four sponsor modes collapse into three mode
    # classes with no loss of points accuracy. CW at 3 is the highest in the repo.
    "points": {"phone": 1, "cw": 3, "digital": 2},
    # "Stations may be worked once per mode, per band."
    "dupeScope": "bandMode",
    "multipliers": {
        # "For Vermont stations, the multipliers are: U.S. States, Canadian
        # Provinces, DXCC Countries, Vermont Counties and Vermont Club Stations."
        # Club stations have no MultClass; see notes.
        "inState": {
            "classes": ["county", "state", "province", "dx"],
            # Not stated, and no multiplier total to settle it by arithmetic. VT
            # stations send a county, so the token VT is never received. Shipped
            # NOT counting, as for NHQP, MEQP, SDQP and ILQP. Open question.
            "homeStateCountsViaCounty": False,
            # "only once per mode, regardless of the number of bands"
            "countScope": "perMode",
            # No DX cap is stated on either side.
        },
        # "For Non-Vermont stations: Vermont Counties and Vermont Club Stations."
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "perMode",
        },
    },
    # 1A(F): +2 points for each W1AW/1 QSO, and 1A(E) says W1AW/1 may be worked
    # "in each Vermont County on each band/mode" — hence perQSO, not once.
    # NOTE the sponsor limits this to stations OUTSIDE Vermont; the engine has no
    # such condition. See notes, KNOWN LIMITATION 2. 2026-ONLY RULE.
    "bonuses": [
        {"type": "workStation", "call": "W1AW/1", "points": 2, "scope": "perQSO"},
    ],
    # DX sends only a report, but the sponsor has the software supply the country
    # and rule 10(C) requires the logged exchange to carry the DXCC prefix, which
    # is what makes each entity a separate multiplier for VT entrants.
    "dxStyle": "prefix",
    # "Entrants may use any combination of modes" (rule 5).
    "allowedModes": ["phone", "cw", "digital"],
    # "2 QSO's and 2 multipliers" — the sponsor states the number outright.
    "maxSimultaneousCounties": 2,
    # "DC is counted as MD" — rule 7(B)(a).
    "stateAliases": {"DC": "MD"},
    # Every exchange form carries a signal report.
    "exchangeIncludesRST": True,
    # "Stations outside Vermont work Vermont stations." Stated outright, twice.
    "outStateWorksHomeStationsOnly": True,
    # Rule 7(D)(1), verbatim: "If all QSO's were made using 5W or less, multiply
    # your score by 2 / ... more than 5W and less than or equal to 150W output,
    # multiply your score by 1.5 / ... more than 150W, multiply your score by 1".
    # THE 1.5 IS THE POINT: it is why ScoreFactor exists. Rule 4 makes an
    # unmarked log high power. The sponsor states no rounding rule for the
    # resulting fraction; the app rounds down, once, per rules_md §8.
    "scoreMultipliers": {"power": {"QRP": 2, "LOW": 1.5, "HIGH": 1}},
    # "0000 UTC on February 7, 2026 ... 2400 UTC on February 8, 2026 ... a 48
    # hour period". 2400Z Feb 8 is 0000Z Feb 9. Longest window of any bundled
    # party.
    "schedule": [{"start": "2026-02-07T00:00:00Z", "end": "2026-02-09T00:00:00Z"}],
    "counties": [{"abbr": a, "name": n} for a, n in sorted(counties.items(), key=lambda kv: kv[1])],
    "hubSpots": {
        "tableURL": "http://qsopartyhub.com/vtqp-table.php",
        "postURL": "http://qsopartyhub.com/vtqp-spots.php",
    },
    "notes": (
        "verified: partial - rules from the sponsor's OFFICIAL 2026 document, "
        "https://www.ranv.org/vtqso.doc ('VERMONT QSO Party Rules', created 2026-01-13, footer "
        "13-JAN-2026), read verbatim 2026-07-26, plus the RANV summary page "
        "https://www.ranv.org/vtqso.html (page-dated January 31, 2026) for the county NAMES and "
        "the approved-club list. The page says outright that it is a summary and that the .doc "
        "carries the specific rules, so the .doc is the authority throughout. Sponsor: Radio "
        "Amateurs of Northern Vermont; Contest Manager W1SJ, w1sj@arrl.net. UNUSUALLY FOR THIS "
        "REPO THE RULES ARE THE CURRENT YEAR'S - nothing here rests on a stale edition. 48 hours "
        "in one window, 0000Z Sat 7 Feb to 2400Z Sun 8 Feb 2026, the longest window of any "
        "bundled party; the sponsor states the length ('This is a 48 hour period') and both "
        "local anchors (7PM EST Fri to 7PM EST Sun) agree, which settles the one-minute "
        "discrepancy in sub-rule 1A(H), where the same window is restated as ending 2359Z. Phone "
        "1 point, CW 3 - the highest CW value of any bundled party - RTTY 2 and digital 2. "
        "Multipliers count ONCE PER MODE on both sides. Vermont stations count US states, "
        "Canadian provinces, DXCC countries, the 14 VT counties and approved VT club stations; "
        "everyone else counts VT counties and VT club stations only. The province list is the "
        "standard 13 with the standard NL spelling, read and confirmed rather than assumed. 'DC "
        "is counted as MD', so DC logs and credits Maryland. Alaska and Hawaii are W/VE here and "
        "send AK/HI - they are explicitly NOT DXCC multipliers. County lines pay '2 QSO's and 2 "
        "multipliers'; enter them as ADD/CHI and the app writes the two separate log lines the "
        "sponsor asks for. Stations outside Vermont work Vermont stations only, stated outright "
        "in rule 1 and repeated on the page. No band list is published - 30, 17 and 12 m are "
        "prohibited EXCEPT for FT8/FT4 on named frequencies, VHF and UHF are allowed, and any "
        "other licensed frequency is permitted. THE POWER MULTIPLIER IS APPLIED IN FULL, "
        "INCLUDING ITS HALF. Rule 7(D)(1): QRP (5W or less) x2, LOW POWER (over 5W to 150W) "
        "x1.5, high power x1, and rule 7(D) gives the formula as 'Final Score = Total Points X "
        "Total Multipliers X Power Multiplier'. The x1.5 shipped once the score factor became an "
        "exact fraction on 2026-07-28; before that this party shipped no power multiplier at all "
        "rather than a wrong whole number. THE SPONSOR STATES NO ROUNDING RULE FOR A FRACTIONAL "
        "FINAL SCORE - its only rounding instruction anywhere is rule 7(B)(f), on a fractional "
        "multiplier count, 'dividing by 3, and rounding down' - so this app rounds DOWN, once, "
        "on the whole points x multipliers product, which is the sponsor's own idiom and the "
        "direction that cannot overstate a claimed score. Rule 4: 'Logs not showing power output "
        "category will be listed as high power.' KNOWN LIMITATION 1 - the W1AW/1 bonus is "
        "credited to everyone. Rule 1A(F) gives 'an additional 2 point bonus for each W1AW/1 "
        "station they work' to stations OUTSIDE Vermont only, and says 'Vermont stations will "
        "not get this bonus'; this app applies station bonuses without regard to the entrant's "
        "own location, so a VERMONT entrant is over-credited 2 points per W1AW/1 QSO and should "
        "subtract them. Note also that W1AW/1 IS A 2026-ONLY RULE, for the America250 WAS and "
        "ARRL Year of the Club celebration - it must be deleted when the 2027 rules are read. "
        "W1AW active from other states (AL, IN, KS) earns no VTQP credit, which this app already "
        "flags because those contacts are not Vermont stations. KNOWN LIMITATION 2 - RTTY AND "
        "FT8 ARE ONE MODE HERE AND TWO FOR THE SPONSOR. The page says 'RTTY is considered a "
        "legacy mode and is not part of this digital group', and the two families do not even "
        "share a multiplier kind: RTTY counts states and countries, WSJT-X counts grid squares. "
        "Since multipliers count once per mode, a Vermont entrant working one state on both RTTY "
        "and FT8 earns two multipliers from the sponsor and one here. KNOWN LIMITATION 3 - 30, "
        "17 and 12 m are shipped as fully valid bands although the sponsor allows them for "
        "FT8/FT4 only, on 10.136/10.140, 18.110/18.104 and 24.915/24.919 MHz USB. Including them "
        "lets a legal digital QSO be logged; the cost is that a phone or CW QSO there is not "
        "flagged. KNOWN LIMITATION 4 - TWO MULTIPLIER KINDS ARE MISSING ENTIRELY. Approved "
        "Vermont CLUB STATIONS count as multipliers on each mode and the 2026 approved club is "
        "W1NVT; a multiplier keyed on a callsign has no class in this app. And on WSJT-X modes, "
        "Vermont entrants count grid squares worked divided by 3 rounded down, while entrants "
        "outside Vermont count Vermont grid squares worked to a maximum of 5 (FN34, FN33, FN32, "
        "FN44, FN35). Add both by hand on the summary sheet if you work them. Cabrillo CONTEST "
        "value VT-QSO-PARTY per the WA7BNM registry, entry 236 - the rules require Cabrillo but "
        "print no header token. Digital contacts are submitted separately as ADIF, not Cabrillo. "
        "Logs go to https://vtqp.contesting.com/vtqpsubmitlog.php by 2026-02-22 2359Z. Counties "
        "are 14 with uniform 3-letter codes, the smallest county list of any bundled party. The "
        "sponsor names its own worst trap and the generator asserts it: 'Take care to not mix up "
        "WiNdHam (WNH) and WiNdSor (WNS)!!' - neither is the naive WIN. GRA is Grand Isle, not "
        "'Grand Island', which appears only in an operating-schedule note. KNOWN LIMITATION 5 - "
        "THE W1AW/1 BONUS IS ADDED AFTER THE POWER MULTIPLIER, NOT INSIDE IT. Rule 1A(F) calls "
        "it 'an additional 2 point bonus', which reads as QSO points, but it lives in section 1A "
        "rather than in the scoring section, and rule 7(D)'s formula names only 'Total Points X "
        "Total Multipliers X Power Multiplier' with no bonus term - so where the 2 points enter "
        "is not stated. This app adds them last, scaled by neither the multipliers nor the power "
        "factor. A low-power station outside Vermont who works W1AW/1 may therefore be "
        "under-credited by half a point per such QSO if the sponsor counts the bonus as QSO "
        "points; add it by hand if you want the other reading. Moot from 2027, when W1AW/1 goes "
        "away. OPEN QUESTIONS (why this is partial): (1) Whether Vermont itself counts as a "
        "state multiplier for Vermont entrants is not stated, and there is no stated multiplier "
        "total to settle it by arithmetic; shipped as NOT counting, the same call as NHQP, MEQP, "
        "SDQP and ILQP. (2) Whether 60 m is legal here. The rules prohibit only 30, 17 and 12 m "
        "and otherwise permit 'any frequency allowed by their license', which would admit 60 m, "
        "but the sponsor never lists it, suggests no frequency for it, and US 60 m is five fixed "
        "channels. Excluded rather than silently included. (3) The five KNOWN LIMITATIONS above "
        "are rules this app cannot express or, in limitation 5, cannot place with certainty - "
        "not rules in doubt. Confirm (1) and (2) with the Contest Manager at w1sj@arrl.net "
        "before submitting a log."
    ),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(vtqp, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"vtqp.json: {len(counties)} counties, uniform 3-letter codes")
print(f"  cross-check: page table == rules sentence ({len(doc_abbrs)} abbreviations)")
print(f"  points: phone 1, CW 3 (highest in repo), RTTY/digital 2")
print(f"  multipliers: perMode both sides; in-state county+state+province+dx, out-of-state county")
print(f"  bands: {len(BANDS)} - no published list; 30/17/12 in for FT8/FT4, 60 m out (open question)")
print(f"  bonus: W1AW/1 +2 per QSO (2026 only)")
print(f"  schedule: 1 window, 48 h (0000Z 7 Feb -> 0000Z 9 Feb 2026) - longest in repo")
print(f"  power mult: QRP x2 / LOW x1.5 / HIGH x1 - rule 7(D)(1), applied in full")
print(f"  NOT shipped: club-station mults, grid-square mults")
