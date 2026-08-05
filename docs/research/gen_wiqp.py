#!/usr/bin/env python3
"""Generate wiqp.json from the West Allis Radio Amateur Club's own documents.

Sources (committed alongside this script, so the run is reproducible):
  wiqp_rules_2026.txt — text of https://www.warac.org/wqp/wiqp_rules.htm, headed
                        2026. THE AUTHORITY.
  wiqp_mults.txt      — the sponsor's official Multiplier List: 72 counties, the
                        states (note "MD Maryland/(D.C.)") and the 13 provinces
  wiqp_cabrillo.txt   — the sponsor's Cabrillo guide. NOT OPTIONAL: it prints the
                        CONTEST: value, and its worked example shows DX logged as
                        the literal token DX rather than as a country prefix
  wiqp_rules.md       — full rules research; all fetched 2026-07-26

WIQP WAS THE SECOND USER OF THE FRACTIONAL-SCORE-MULTIPLIER GAP, and the one
that got it built. Its power multipliers are QRP x2, LOW x1.5, HIGH x1 -
identical to VTQP's, down to the same three numbers - and while ScoreMultipliers
was [String: Int] nothing shipped, for the same reason as VTQP: {QRP:2, LOW:1,
HIGH:1} would understate the commonest power class by a third while looking
correct. Two sponsors wanting it met this repo's own bar, ScoreFactor landed on
2026-07-28, and the table now ships in full.

READING THE CABRILLO GUIDE CHANGED A FIELD. The rules say non-Wisconsin stations
send "State or Province or Country", which reads like a DX prefix; the sponsor's
own example logs DL6QK as "DX". dxStyle is token, and had only the rules page
been read this would have shipped as prefix and rejected the sponsor's own line.

RETRIEVAL NOTE: warac.org 403s a plain fetch of the multiplier page. It needs a
browser User-Agent and a Referer of the rules page.

Usage:  python3 gen_wiqp.py        (run from docs/research/)
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "wiqp.json")
RULES = os.path.join(HERE, "wiqp_rules_2026.txt")
MULTS = os.path.join(HERE, "wiqp_mults.txt")
CABRILLO = os.path.join(HERE, "wiqp_cabrillo.txt")


def read(path):
    s = open(path, encoding="utf-8", errors="replace").read()
    for a, b in [("’", "'"), ("‘", "'"), ("“", '"'), ("”", '"'),
                 ("–", "-"), ("—", "-"), (" ", " "), ("�", "-")]:
        s = s.replace(a, b)
    return s


rules = re.sub(r"\s+", " ", read(RULES))
mults_txt = read(MULTS)
cabrillo = read(CABRILLO)

# --- Counties: the multiplier list prints four "ABBR Name" pairs per line,
# bounded by the STATES table that follows. ---
block = mults_txt.split("WISCONSIN COUNTIES")[1].split("STATES")[0]
# Each line holds four "ABBR Name" pairs. Names may be several words ("Fond du
# Lac", "St Croix"), so locate the CODES - three capitals followed by a space and
# a capital - and take everything between them as the name.
CODE = re.compile(r"(?<![A-Za-z])([A-Z]{3})(?= [A-Z])")
counties = {}
for line in block.splitlines():
    hits = list(CODE.finditer(line))
    for i, m in enumerate(hits):
        end = hits[i + 1].start() if i + 1 < len(hits) else len(line)
        name = " ".join(line[m.end():end].split())
        abbr = m.group(1)
        if not name:
            continue
        if abbr in counties and counties[abbr] != name:
            sys.exit(f"WIQP conflicting names for {abbr}: {counties[abbr]!r} vs {name!r}")
        counties[abbr] = name

assert len(counties) == 72, f"expected 72 WI counties, got {len(counties)}: {sorted(counties)}"
assert len(set(counties.values())) == 72, "WI county names not unique"
assert {len(a) for a in counties} == {3}, "WI codes are uniformly 3 letters"
assert "max. 72" in rules, "the sponsor's own county maximum changed"

# Wisconsin's clusters are dense and several codes are NOT the naive first three.
for abbr, name in [
    ("MAR", "Marathon"), ("MRN", "Marinette"), ("MRQ", "Marquette"),   # three Mar-
    ("GRA", "Grant"), ("GRE", "Green"), ("GRL", "Green Lake"),         # three Gr-
    ("WAL", "Walworth"), ("WAS", "Washington"), ("WSB", "Washburn"),
    ("WAU", "Waukesha"), ("WAP", "Waupaca"), ("WSR", "Waushara"),      # six W-
    ("FON", "Fond du Lac"), ("LAC", "La Crosse"), ("STC", "St Croix"),
    ("EAU", "Eau Claire"), ("ONE", "Oneida"), ("MIL", "Milwaukee"),
    ("DAN", "Dane"), ("BRO", "Brown"), ("RAC", "Racine"), ("KEN", "Kenosha"),
]:
    assert counties.get(abbr) == name, f"{abbr} should be {name!r}, got {counties.get(abbr)!r}"
for absent in ["MARI", "WASH", "GREE", "STCR"]:
    assert absent not in counties, f"{absent} is not a WIQP abbreviation"

# --- Bands. The rules publish NO list - "All amateur bands and modes not
# prohibited for contesting may be used" - so the suggested-frequency table is
# what fixes the set. It covers exactly these ten. ---
BANDS = ["160m", "80m", "40m", "20m", "15m", "10m", "6m", "2m", "1.25m", "70cm"]
assert "All amateur bands and modes not prohibited for contesting may be used" in rules, \
    "the band sentence changed - re-derive the list from the frequency table"
assert "CW: 1.820, 3.550, 7.050, 14.050, 21.050, 28.050" in rules, \
    "the CW suggested-frequency row changed - re-check the band list against it"
assert "Phone: 1.870, 3.860, 7.230, 14.260, 21.350, 28.400" in rules
for vhf in ["6 meters", "2 meters", "1.25 meters", "70 cm"]:
    assert vhf in rules, f"the suggested-frequency table no longer lists {vhf}"
for excluded in ["60m", "30m", "17m", "12m"]:
    assert excluded not in BANDS, f"{excluded} is prohibited for contesting by convention"
# 33 cm and 23 cm appear only in the do-not-use calling-frequency list and are
# outside the Band enum; see wiqp_rules.md section 10.
assert "906.50" in rules and "1294.50" in rules

# --- The rule sentences this file encodes. ---
for quote in [
    # Date/time
    "March 15, 2026 from 1800Z to 0100Z March 16",
    "(1:00PM CDT to 8:00PM CDT on March 15)",
    # Exchange
    "Wisconsin stations send County",
    "Non-Wisconsin stations send State or Province or Country",
    # Modes and dupes
    "FT8/FT4 QSO's are not accepted",
    "All stations may be worked once per mode on each band",
    "Cannot work the same station on more than one Digital mode on the same band",
    "Mobiles and portables may be worked once per mode per Wisconsin county",
    # County lines: FORBIDDEN
    "Mobiles or portables may not sit on a county line",
    # Multipliers, with the sponsor's own maxima
    "The sum of Wisconsin counties (max. 72), plus US states (max. 50) plus Canadian "
    "provinces (max. 13) worked",
    "Wisconsin may be counted as a state multiplier",
    "DX countries worked count for QSO points but not as multipliers",
    "The number of Wisconsin counties worked (max.72)",
    "Only Wisconsin stations may be worked",
    # Points and scoring order
    "Phone contacts count 1 point; CW and Digital contacts count 2 points",
    "Then multiply by Power Level multiplier",
    # Bonuses
    "Add 500 bonus points for each county that you operate from outside your home county",
    "A minimum of 12 QSO",
    "Add 100 points for each time you work W9FK on each band and mode below 50Mhz",
]:
    assert quote in rules, f"the 2026 rules no longer contain: {quote!r}"

assert "2026" in rules and "Logs due March 29" in rules, \
    "this may no longer be the 2026 edition - re-verify before shipping"

# The fractional power multipliers, which SHIP. Identical to VTQP's. If any of
# these change, update scoreMultipliers below to match - a wrong factor is a
# wrong score.
for quote in ["QRP less than 5 watts Power Mult = 2",
              "Low 5 to 100 watts Power Mult = 1.5",
              "High over 100 watts Power Mult = 1"]:
    assert quote in rules, f"the power multiplier table changed: {quote!r}"

# THE CABRILLO GUIDE, which decides dxStyle and the CONTEST value.
assert "CONTEST: WI-QSO-PARTY" in cabrillo, \
    "the sponsor no longer prints its own CONTEST value - fall back to WA7BNM"
assert "DL6QK DX" in cabrillo, (
    "the sponsor's example no longer logs DX as a literal token - re-read it "
    "before trusting dxStyle"
)
assert "W9HNW RAC ND9Z BRO" in cabrillo, \
    "the example no longer shows a report-free exchange - re-check exchangeIncludesRST"

# "MD Maryland/(D.C.)" is the ONLY place DC is mentioned; the rules page never is.
assert "MD Maryland/(D.C.)" in mults_txt, \
    "the multiplier list no longer folds DC into Maryland - re-check stateAliases"
assert "WI Wisconsin" in mults_txt, \
    "Wisconsin is no longer listed among the states - re-check homeStateCountsViaCounty"

wiqp = {
    "schemaVersion": 1,
    "id": "wiqp",
    "name": "Wisconsin QSO Party",
    # Printed by the sponsor in its own Cabrillo guide.
    "cabrilloContest": "WI-QSO-PARTY",
    "homeState": "WI",
    "countyAbbrLength": 3,
    # No band list is published; the suggested-frequency table fixes these ten.
    # The largest band list of any bundled party.
    "validBands": BANDS,
    # "Phone contacts count 1 point; CW and Digital contacts count 2 points."
    "points": {"phone": 1, "cw": 2, "digital": 2},
    # "All stations may be worked once per mode on each band."
    "dupeScope": "bandMode",
    "multipliers": {
        # "The sum of Wisconsin counties (max. 72), plus US states (max. 50) plus
        # Canadian provinces (max. 13) worked." The stated maxima are what fix
        # the scope at once-overall rather than per band or per mode.
        "inState": {
            "classes": ["county", "state", "province"],
            # "Wisconsin may be counted as a state multiplier" - stated outright,
            # and WI stations send a county so the token WI is never received.
            "homeStateCountsViaCounty": True,
            "countScope": "once",
        },
        # "The number of Wisconsin counties worked (max.72)."
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
        },
    },
    "bonuses": [
        # "Add 500 bonus points for each county that you operate from outside
        # your home county. A minimum of 12 QSO's per county is required."
        # NOTE the engine cannot exclude the home county; see notes.
        {"type": "activatedCountyCount", "minQSOs": 12, "points": 500},
        # "Add 100 points for each time you work W9FK on each band and mode below
        # 50Mhz." NOTE the engine cannot apply the below-50-MHz limit; see notes.
        {"type": "workStation", "call": "W9FK", "points": 100, "scope": "perBandMode"},
    ],
    # The rules say "Country", which reads like a prefix - but the sponsor's own
    # Cabrillo example logs DL6QK as "DX". The token is what the robot sees, and
    # DX multiplies nothing anyway.
    "dxStyle": "token",
    # "CW, Phone and Digital (RTTY, PSK, Olivia, Feld-Hell)." No FT8/FT4.
    "allowedModes": ["phone", "cw", "digital"],
    # "Mobiles or portables may not sit on a county line."
    "maxSimultaneousCounties": 1,
    # "MD Maryland/(D.C.)" - from the multiplier list, the only place DC appears.
    "stateAliases": {"DC": "MD"},
    # No report anywhere in the rules, and the Cabrillo example carries none.
    "exchangeIncludesRST": False,
    # "Only Wisconsin stations may be worked."
    "outStateWorksHomeStationsOnly": True,
    # POWER LEVEL, verbatim: "QRP - less than 5 watts - Power Mult = 2 / Low -
    # 5 to 100 watts - Power Mult = 1.5 / High - over 100 watts - Power Mult =
    # 1". IDENTICAL FACTORS TO VERMONT'S, on different wattage boundaries - the
    # second sponsor to want the 1.5, which is what got ScoreFactor built. The
    # sponsor states no rounding rule anywhere; the app rounds down, once, on
    # the points x multipliers product, per rules_md §8.
    "scoreMultipliers": {"power": {"QRP": 2, "LOW": 1.5, "HIGH": 1}},
    # "March 15, 2026 from 1800Z to 0100Z March 16 (1:00PM CDT to 8:00PM CDT)".
    # Round instants, anchors agree under CDT. SEVEN HOURS - the shortest TOTAL
    # operating time of any bundled party (KSQP and TQP have shorter single
    # sessions at six hours, but run eighteen hours overall).
    "schedule": [{"start": "2026-03-15T18:00:00Z", "end": "2026-03-16T01:00:00Z"}],
    "counties": [{"abbr": a, "name": n} for a, n in sorted(counties.items(), key=lambda kv: kv[1])],
    "hubSpots": {
        "tableURL": "http://qsopartyhub.com/wiqp-table.php",
        "postURL": "http://qsopartyhub.com/wiqp-spots.php",
    },
    "notes": (
        "verified: partial - rules from the West Allis Radio Amateur Club's own 2026 page, "
        "https://www.warac.org/wqp/wiqp_rules.htm, with the sponsor's official Multiplier List "
        "and its Cabrillo guide, all read verbatim 2026-07-26. Logs to wiqp-logs@warac.org by 29 "
        "March. SEVEN HOURS in one window, 1800Z to 0100Z on 15 March 2026 - THE SHORTEST TOTAL "
        "OPERATING TIME OF ANY BUNDLED STATE QSO PARTY, beating Illinois's eight (the NJQRP "
        "Skeeter Hunt, a four-hour QRP sprint, is shorter still but is no state party); note "
        "that Kansas and Texas each have a SHORTER single session, six hours, but run eighteen "
        "hours overall. "
        "Round instants with local anchors that agree under CDT, so nothing had to be "
        "reconstructed. (The page carries a stale note, 'First day of Daylight Saving Time!', "
        "which is wrong for 2026 - US daylight time began 8 March, a week earlier - and appears "
        "to be leftover copy the sponsor meant to comment out. It changes nothing.) READING THE "
        "SPONSOR'S CABRILLO GUIDE CHANGED A FIELD, which is worth recording. The rules say "
        "non-Wisconsin stations send 'State or Province or Country', which reads like a DX "
        "prefix; the sponsor's own worked example logs DL6QK as the literal token 'DX'. Had only "
        "the rules page been read, this party would have shipped expecting prefixes and would "
        "have rejected the sponsor's own sample line. The same example also confirms the "
        "exchange carries NO SIGNAL REPORT - 'W9HNW RAC ND9Z BRO' is call and location only - "
        "which is the fifth party after MDC, MNQP, NCQP and IDQP to drop it. Wisconsin stations "
        "send a county; everyone else sends a state, a province, or DX. Phone 1 point, CW and "
        "digital 2. Multipliers count ONCE OVERALL - the sponsor's own maxima (72 counties, 50 "
        "states, 13 provinces) are what settle that, since a per-band or per-mode scope could "
        "not have a maximum of 72. Wisconsin stations count the 72 counties plus states plus "
        "provinces for 135; everyone else counts the 72 counties. WISCONSIN ITSELF IS A "
        "MULTIPLIER, stated outright - 'Wisconsin may be counted as a state multiplier' - and "
        "reachable only through a county, since WI stations send a county. DX EARNS POINTS BUT "
        "NO MULTIPLIER. DC counts as Maryland, which appears NOWHERE in the rules and only in "
        "the multiplier list, printed as the single row 'MD Maryland/(D.C.)'. Ten bands - the "
        "largest list of any bundled party - derived from the suggested-frequency table, since "
        "the rules publish no list and say only 'all amateur bands not prohibited for "
        "contesting'; that table covers 160 through 10 m plus 6 m, 2 m, 1.25 m and 70 cm. "
        "COUNTY-LINE OPERATION IS FORBIDDEN: 'Mobiles or portables may not sit on a county "
        "line', so a two-county entry is rejected, as in ALQP and MNQP. FT8 and FT4 are not "
        "accepted while RTTY, PSK, Olivia and Feld-Hell are, which is below this app's "
        "mode-class granularity - KEEP FT8/FT4 OUT OF THE LOG. All digital modes count as one, "
        "stated outright ('Cannot work the same station on more than one Digital mode on the "
        "same band'), which is exactly how this app behaves. THE POWER MULTIPLIER IS APPLIED IN "
        "FULL, INCLUDING ITS HALF. The POWER LEVEL table gives QRP (under 5 W) x2, LOW POWER "
        "(5-100 W) x1.5 and high power x1 - THE SAME THREE FACTORS VERMONT PRINTS, on different "
        "wattage boundaries, and it was this second sponsor that met the repo's two-user bar for "
        "building them. The x1.5 shipped once the score factor became an exact fraction on "
        "2026-07-28; before that this party shipped no power multiplier at all rather than a "
        "wrong whole number. THE SPONSOR'S STATED ORDER IS EXACTLY WHAT THE ENGINE COMPUTES: "
        "'Add CW, Phone and Digital points. Then multiply by Power Level multiplier. Then "
        "multiply by your multiplier count under MULTIPLIERS. Finally, add your bonus points.' - "
        "so the county and W9FK bonuses are added after the power factor and are never scaled by "
        "it. THE SPONSOR STATES NO ROUNDING RULE ANYWHERE - not in the rules, the Multiplier "
        "List or the Cabrillo guide, which contain no rounding language at all - so this app "
        "rounds DOWN, once, on the whole points x multipliers product, the direction that cannot "
        "overstate a claimed score. That is an inference; Vermont at least has its own idiom for "
        "it, rounding its grid-square multiplier count down. KNOWN LIMITATION 1 - the 500-point "
        "county bonus is credited for EVERY county with 12 or more QSOs, including your home "
        "county, while the sponsor pays it only 'for each county that you operate from OUTSIDE "
        "your home county'. A Wisconsin mobile or portable who also makes 12+ QSOs from home is "
        "over-credited 500; subtract it. IN-STATE MOBILES AND PORTABLES ONLY. KNOWN LIMITATION 2 "
        "- the W9FK bonus is credited on every band and mode, while the sponsor pays it only "
        "BELOW 50 MHz. Working W9FK on 6 m, 2 m, 1.25 m or 70 cm over-credits 100 points per "
        "slot; subtract those. Cabrillo CONTEST value WI-QSO-PARTY, printed by the sponsor in "
        "its own Cabrillo guide, so this does not rest on the WA7BNM registry. Counties are 72 "
        "with uniform 3-letter codes and several dense clusters: THREE Mar- counties of which "
        "only Marathon is MAR (Marinette is MRN, Marquette MRQ); THREE Gr- counties (Grant GRA, "
        "Green GRE, Green Lake GRL - the last two one letter apart); and SIX W- counties "
        "(Walworth WAL, Washington WAS, Washburn WSB, Waukesha WAU, Waupaca WAP, Waushara WSR), "
        "where neither Washburn nor Waushara takes the naive form. Multi-word names are printed "
        "without punctuation: Fond du Lac FON, La Crosse LAC, St Croix STC (no period, as in "
        "Minnesota's St Louis). OPEN QUESTIONS (why this is partial): (1) and (2) - the two "
        "bonus rules above, each of which over-credits a narrow case. Neither is a rule in "
        "doubt; both are missing app features. Note also that the sponsor's do-not-use list "
        "names 906.50 and 1294.50 MHz, so 33 cm and 23 cm contacts are plausibly legal here and "
        "cannot be logged at all - the same gap NYQP has."
    ),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(wiqp, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"wiqp.json: {len(counties)} counties, uniform 3-letter codes")
print(f"  clusters asserted: MAR/MRN/MRQ, GRA/GRE/GRL, and six W- counties")
print(f"  dxStyle TOKEN - decided by the sponsor's Cabrillo example, not its rules")
print(f"  multipliers ONCE OVERALL (the stated maxima 72/50/13 settle it); DX pays none")
print(f"  bands: {len(BANDS)} - the largest list in the repo, from the frequency table")
print(f"  county lines FORBIDDEN; exchange carries NO signal report")
print(f"  bonuses: 500/county (12+ QSOs) and W9FK 100 per band/mode")
print(f"  schedule: 1 window, 7 h - the shortest TOTAL of any bundled party")
print(f"  power mult: QRP x2 / LOW x1.5 / HIGH x1 - the same table VTQP prints, applied in full")
