#!/usr/bin/env python3
"""Generate Resources/Parties/deqp.json — the Delaware QSO Party.

Three counties, which makes this the smallest county list in the app - and the
one party where the LIST is trivial and everything else is not.

THREE THINGS TO GET RIGHT:

1. THE NEWEST RULES ARE TITLED 2024. rules-2025 and rules-2026 both 404, and
   the site reaches its own newest edition only from the home page's link:
     /qsoparty/rules.htm      -> rules-2022.htm -> rules-2023.html  (dead end)
     /qso-rules (home page)   -> rules-2024.html                     (current)
   The obvious URL lands two editions short.

2. THE RULES STATE NO CONTEST TIMES. Only "Date: First full weekend in May".
   The date derives from the sponsor; the HOURS do not exist in any sponsor
   document and come from the SQP Challenge calendar. OPEN QUESTION 1.

3. QSO POINTS DEPEND ON WHICH SIDE YOU ARE ON, not on what you receive:
   "Stations inside DE earn 1 point per phone QSO, 2 points for digital QSO,
   and 2 points per CW QSO. Stations outside DE earn 10 points per phone QSO,
   20 points per digital QSO and 20 points per CW QSO."
   pointsTable() keys on the RECEIVED location, not the entrant's role, so this
   is modelled as closely as the schema allows and the residue is recorded.
   See KNOWN LIMITATION 1.

Sources (both banked):

  deqp_rules_2024.txt      https://www.fsarc.org/qsoparty/rules-2024.html
  deqp_cabrillo_name.txt   WA7BNM Cabrillo Names (Article 1 exception - header only)

  Both fetched 2026-07-26. See deqp_rules.md.

Run:  python3 docs/research/gen_deqp.py
"""

import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "deqp.json")


def read(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        s = f.read()
    for a, b in [("’", "'"), ("‘", "'"), ("“", '"'), ("”", '"'),
                 ("–", "-"), ("—", "-"), (" ", " ")]:
        s = s.replace(a, b)
    return s.split("=" * 72, 1)[-1]


rules = read("deqp_rules_2024.txt")
flat = re.sub(r"\s+", " ", rules)

# ---------------------------------------------------------------- the counties
# Three, and the sponsor prints them twice - in the header and in the multiplier
# rule. Both copies are parsed and required to agree.
header = dict(re.findall(r"([A-Z][a-z]+(?: [A-Z][a-z]+)*)\s*County\s+([NKS]DE)\b", flat))
mults = dict((n, c) for c, n in
             [(m[1], m[0]) for m in re.findall(r"(New Castle|Kent|Sussex) \(([NKS]DE)\)", flat)])
assert header == {"New Castle": "NDE", "Kent": "KDE", "Sussex": "SDE"}, header
assert mults == header, (header, mults)

counties = [{"abbr": c, "name": n} for n, c in sorted(header.items(), key=lambda kv: kv[1])]
assert len(counties) == 3, "Delaware has three counties"
assert {len(c["abbr"]) for c in counties} == {3}

# The code is the county's INITIAL plus DE, not a truncation of its name - so
# New Castle is NDE, not NEW.
by_abbr = {c["abbr"]: c["name"] for c in counties}
assert by_abbr["NDE"] == "New Castle" and by_abbr["KDE"] == "Kent" and by_abbr["SDE"] == "Sussex"
assert "NEW" not in by_abbr and "KEN" not in by_abbr

# ------------------------------------------------------------------- the rules
assert "Date: First full weekend in May" in flat
assert not re.search(r"\b(1700|2359|2400)\s*(Z|UTC)?\b", flat), \
    "the rules state no contest times - if they now do, resolve OPEN QUESTION 1"
assert "Logs should indicate times in UTC" in flat, \
    "the only mention of UTC anywhere, and it is about log format"

assert ("Delaware stations send signal report and county. Stations outside Delaware send "
        "signal report and state, province or DX.") in flat
assert ("Work stations once per band per mode. The three valid mode categories are CW, "
        "Phone, and Digital.") in flat
assert "Delaware stations work everyone." in flat
assert "Non-Delaware stations work Delaware only." in flat
assert ("Delaware stations may contact other Delaware stations but only count for QSO point "
        "credit.") in flat, "so a DE-to-DE contact yields no multiplier"
assert "County line QSOs should be logged as two separate QSOs" in flat

# THE ASYMMETRIC POINTS - the whole of KNOWN LIMITATION 1.
assert ("Stations inside DE earn 1 point per phone QSO, 2 points for digital QSO, and 2 "
        "points per CW QSO.") in flat
assert ("Stations outside DE earn 10 points per phone QSO, 20 points per digital QSO and 20 "
        "points per CW QSO.") in flat
INSIDE = {"phone": 1, "cw": 2, "digital": 2}
OUTSIDE = {"phone": 10, "cw": 20, "digital": 20}
assert all(OUTSIDE[m] == INSIDE[m] * 10 for m in INSIDE), "outside earns exactly ten times"

assert "Multipliers are counted only once." in flat
assert "Multipliers are by Band." in flat
assert "Delaware stations use, states, Canadian provinces, and DXCC countries." in flat
assert ("Stations outside Delaware use Delaware counties, New Castle (NDE), Kent (KDE), and "
        "Sussex (SDE).") in flat

assert "-Greater than 100 watts (>100 watts), total score X1" in flat
assert "100 watts or less (< = 100 watts) total score X2" in flat
assert "-5 watts or less (< = 5 watts), total score X3" in flat
assert ("Final score = the total of QSO points X location multipliers X power multiplier, + "
        "50 point electronic submission bonus if applicable.") in flat

assert "Suggested frequencies: All HF bands excluding WARC bands" in flat
assert ("DEQP also allows contacts on any band and mode 6 meters and up to include repeater "
        "contacts within Delaware. 1 point per voice contact, 2 points per digital contact "
        "to include CW.") in flat, "VHF and up score differently - KNOWN LIMITATION 2"
assert "Stations using these modes must use the Field Day contest overlay in WSJT-X." in flat
assert "the exchange needs to be 1A DE" in flat, "FT8 uses a Field Day exchange entirely"

assert "CONTEST:" not in rules
name = read("deqp_cabrillo_name.txt")
assert "Delaware QSO Party" in name and "DE-QSO-PARTY" in name

NOTES = (
    "verified: partial - rules from the First State Amateur Radio Club (FSARC), read "
    "verbatim 2026-07-26. THREE COUNTIES, the smallest list in this app, and the codes are "
    "the county's INITIAL plus DE: New Castle is NDE, not a truncation. THE NEWEST RULES "
    "ARE TITLED 2024 - rules-2025 and rules-2026 both 404 - so this party ships against a "
    "two-year-old document, which is why it is partial. WORSE, THE SITE'S OWN LINKS LAND "
    "SHORT: /qsoparty/rules.htm redirects to rules-2022.htm, which redirects to "
    "rules-2023.html and stops there; only the home page's /qso-rules link reaches "
    "rules-2024.html. Every Last-Modified on the site reads 2026-07-17, a server-wide "
    "touch, so header dates prove nothing. OPEN QUESTION 1: THE RULES STATE NO CONTEST "
    "TIMES AT ALL, only 'Date: First full weekend in May'. The DATE is the sponsor's; the "
    "HOURS exist in no sponsor document and come from the SQP Challenge calendar (1700Z 2 "
    "May to 2359Z 3 May). Article 19 wants the sponsor's own times and there are none, so "
    "the calendar's ship with this flagged - an operator should confirm before 2027. KNOWN "
    "LIMITATION 1 - QSO POINTS DEPEND ON WHICH SIDE YOU ARE ON, and the schema keys points "
    "on what you RECEIVE. 'Stations inside DE earn 1 point per phone QSO, 2 for digital and "
    "2 per CW. Stations outside DE earn 10 per phone, 20 per digital and 20 per CW' - "
    "exactly ten times as much. homeStationPoints fires whenever the received location is a "
    "Delaware county, which is right for every out-of-state entrant (all their valid QSOs "
    "are with Delaware) and right for a Delaware station working outside, but WRONG for a "
    "DELAWARE STATION WORKING ANOTHER DELAWARE STATION, which scores 10/20/20 where the "
    "sponsor pays 1/2/2. That is the smallest wrong case available: those contacts earn no "
    "multiplier either way, by the sponsor's own rule, and they are a minority of a Delaware "
    "log. The fix is to give pointsTable the entrant's role as well as the received "
    "location. KNOWN LIMITATION 2 - VHF AND UP SCORE DIFFERENTLY: 'DEQP also allows contacts "
    "on any band and mode 6 meters and up to include repeater contacts within Delaware. 1 "
    "point per voice contact, 2 points per digital contact to include CW.' Points are keyed "
    "by mode, never by band, so a 6 m contact scores the HF value. Second user of a "
    "points-table gap after North Carolina's points-by-county and Ontario's points-by-call. "
    "KNOWN LIMITATION 3 - the 50-point electronic-submission bonus is not modelled: it pays "
    "for how the log is SENT, not for anything on the air, and no BonusRule shape describes "
    "that. KNOWN LIMITATION 4 - FT8/FT4 use a Field Day exchange entirely ('1A DE' for New "
    "Castle, '2A DE' for Kent), which is a different exchange grammar, not a different "
    "token; it is not modelled. Multipliers count PER BAND. Delaware entrants count states, "
    "provinces and DXCC countries - NOT counties, so a Delaware-to-Delaware contact yields "
    "points only, which the rules say outright. The power multiplier fits: over 100 W x1, "
    "100 W or less x2, 5 W or less x3 - the fourth party to ship one. County lines are "
    "logged as two separate QSOs, so maxSimultaneousCounties is 1. The Cabrillo CONTEST "
    "header is the one thing not from the sponsor - it has a whole Cabrillo Info page and "
    "still never names the header - so DE-QSO-PARTY comes from WA7BNM under Article 1's "
    "exception."
)

party = {
    "schemaVersion": 1,
    "id": "deqp",
    "name": "Delaware QSO Party",
    "cabrilloContest": "DE-QSO-PARTY",
    "homeState": "DE",
    "countyAbbrLength": 3,
    "validBands": ["160m", "80m", "40m", "20m", "15m", "10m",
                   "6m", "2m", "1.25m", "70cm"],
    # The DELAWARE-station table. homeStationPoints below carries the
    # out-of-state one - see KNOWN LIMITATION 1.
    "points": INSIDE,
    "homeStationPoints": OUTSIDE,
    "dupeScope": "bandMode",
    "multipliers": {
        # "Delaware stations use, states, Canadian provinces, and DXCC
        # countries" - and NOT counties, which is why a DE-to-DE contact
        # "only count[s] for QSO point credit".
        "inState": {
            "classes": ["state", "province", "dx"],
            "homeStateCountsViaCounty": False,
            "countScope": "perBand",
            # The sponsor counts DXCC entities individually -- see the
            # multiplier quote in the notes. Resolved against the ARRL
            # DXCC List (Resources/DXCC, generated by gen_dxcc.py).
            "dxCountsEntities": True,
        },
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "perBand",
        },
    },
    "bonuses": [],
    "dxStyle": "token",
    "allowedModes": ["phone", "cw", "digital"],
    "maxSimultaneousCounties": 1,
    "exchangeIncludesRST": True,
    "outStateWorksHomeStationsOnly": True,
    "scoreMultipliers": {"power": {"QRP": 3, "LOW": 2, "HIGH": 1}},
    "schedule": [
        {"start": "2026-05-02T17:00:00Z", "end": "2026-05-04T00:00:00Z"},
    ],
    "counties": counties,
    "hubSpots": None,
    "notes": NOTES,
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(party, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"deqp.json: {len(counties)} counties - the smallest list in the app")
print("  NDE / KDE / SDE: the county's INITIAL plus DE, not a truncation")
print("  NEWEST RULES ARE TITLED 2024; rules-2025 and rules-2026 both 404")
print("    and rules.htm redirects to 2022 -> 2023 and stops two editions short")
print("  OPEN QUESTION 1: the rules state NO CONTEST TIMES, only the weekend")
print(f"  points inside DE {INSIDE} vs outside {OUTSIDE} - exactly ten times")
print("    the schema keys points on what you RECEIVE, so DE-to-DE is the wrong case")
print("  multipliers PER BAND; DE entrants count no counties at all")
print("  POWER MULTIPLIER SHIPS: QRP x3, LOW x2, HIGH x1")
print("  NOT shipped: VHF-and-up point values, the 50-pt submission bonus, FT8's")
print("    Field Day exchange")
print(f"  wrote {os.path.normpath(OUT)}")
