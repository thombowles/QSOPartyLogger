#!/usr/bin/env python3
"""Generate nmqp.json from the New Mexico QSO Party's own 2026 form packet.

Source (committed alongside this script, so the run is reproducible):
  nmqp_rules_2026.txt — pdftotext -layout of NMQP_Forms.pdf, "2026 New Mexico
                        QSO Party Form Packet", last modified 09 April 2026.
                        THE AUTHORITY: one document carries the rules, the county
                        check sheet and the Cabrillo specification.
  nmqp_rules.md       — full rules research; fetched 2026-07-26

THE FIRST PARTY THIS RUN WHOSE POWER MULTIPLIER ACTUALLY FITS. QRP x5, Low x2,
High x1 - all whole numbers - so scoreMultipliers ships. The shape is identical
to VTQP's and WIQP's except that their low-power factor is 1.5; NMQP's is 2, and
that single difference is why this one fits and those two wait on a schema change.

THE PACKET KEEPS ITS OWN CHANGE LOG, which matters: the W1AW/5 bonus was CUT FROM
500 TO 250 on 09 April 2026. A copy captured between 24 March and 9 April would
have the wrong number. The 250 is asserted below.

Usage:  python3 gen_nmqp.py        (run from docs/research/)
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "nmqp.json")
RULES = os.path.join(HERE, "nmqp_rules_2026.txt")


def read(path):
    s = open(path, encoding="utf-8", errors="replace").read()
    for a, b in [("’", "'"), ("‘", "'"), ("“", '"'), ("”", '"'),
                 ("–", "-"), ("—", "-"), (" ", " "), ("§", "*")]:
        s = s.replace(a, b)
    return s


raw = read(RULES)
rules = re.sub(r"\s+", " ", raw)

# --- Counties: the packet's own Check Sheet, "______  Name  ABC" per line. ---
PAIR = re.compile(r"^_+\s+([A-Z][A-Za-z ]+?)\s+([A-Z]{3})\s*$", re.M)
counties = {}
for name, abbr in PAIR.findall(raw):
    name = " ".join(name.split())
    if abbr in counties and counties[abbr] != name:
        sys.exit(f"NMQP conflicting names for {abbr}: {counties[abbr]!r} vs {name!r}")
    counties[abbr] = name

assert len(counties) == 33, f"expected 33 NM counties, got {len(counties)}: {sorted(counties)}"
assert len(set(counties.values())) == 33, "NM county names not unique"
assert {len(a) for a in counties} == {3}, "NM codes are uniformly 3 letters"
assert "NM county worked (up to 33)" in rules, "the sponsor's own county count changed"

# THE TRAP: four San/Santa entities, and SAN belongs to NONE of them - it is
# Sandoval. See nmqp_rules.md section 11.
for abbr, name in [
    ("SAN", "Sandoval"), ("SJU", "San Juan"), ("SMI", "San Miguel"), ("SFE", "Santa Fe"),
    ("COL", "Colfax"), ("CIB", "Cibola"),
    ("LOS", "Los Alamos"), ("RIO", "Rio Arriba"), ("DEB", "De Baca"),
    ("DON", "Dona Ana"),        # sponsor drops the tilde of the official Dona Ana
    ("BER", "Bernalillo"), ("MCK", "McKinley"), ("LEA", "Lea"), ("TAO", "Taos"),
]:
    assert counties.get(abbr) == name, f"{abbr} should be {name!r}, got {counties.get(abbr)!r}"
for absent in ["SJN", "SNM", "STF", "DONA"]:
    assert absent not in counties, f"{absent} is not an NMQP abbreviation"

# --- Bands: both the inclusion AND the exclusion are stated, with 60 m named
# separately from the WARC bands - a distinction several sponsors blur. ---
BANDS = ["160m", "80m", "40m", "20m", "15m", "10m", "6m", "2m"]
assert "Contest bands: 160-10 meters, plus 6 and 2 meters" in rules, "the band list changed"
assert "Not permitted: WARC bands, 60 meters, and bands above 2 meters" in rules
for excluded in ["60m", "30m", "17m", "12m", "1.25m", "70cm"]:
    assert excluded not in BANDS

# --- The rule sentences this file encodes. ---
for quote in [
    # Object / scope of credit
    "New Mexico stations: Work anyone for NM counties, states, provinces, and DX",
    "Non-NM stations: Work NM stations for NM counties only",
    # Contest period - formula, UTC, local and duration in one sentence
    "Second Saturday of April, 8:00 MDT (1400 UTC) to 20:00 MDT (0200 UTC)",
    "Duration: 12 hours",
    # Exchange
    "New Mexico stations: RS(T) + New Mexico county",
    "Non-New Mexico stations: RS(T) + State/Province/DXCC entity",
    # Points
    "Each Phone contact = 1 point",
    "Each CW contact = 2 points",
    "Each Digital contact = 2 points",
    # Power multiplier - WHOLE NUMBERS, which is why this party ships one
    "QRP (5 watts or less): x5",
    "Low Power (> 5 - 150 watts): x2",
    "High Power: (> 150 watts): x1",
    # Location multipliers
    "states worked (up to 50)",
    "District of Columbia (DC) counts as Maryland",
    "Each multiplier may be counted ONLY ONCE, regardless of mode or band",
    "Multiply QSO points by total of each different NM county worked (up to 33)",
    # Bonuses
    "Add an additional 5,000 points to the final score for every county from which at "
    "least 15 valid QSOs were made",
    "Add an additional 250 points to your final score for a valid contact with",
    "Bonus points are valid for one (1) W1AW/5 QSO only",
    # Dupes and county lines
    "Stations may be worked only once per mode, per band",
    "only two counties at a time may be counted for the same contact",
    # Cabrillo - the SPONSOR prints its own CONTEST value and the QTH shape
    "CONTEST: NM-QSO-PARTY",
    'QTH is three letter NM county abbreviation, or two-letter State/Province abbreviation, or "DX"',
]:
    assert quote in rules, f"the 2026 packet no longer contains: {quote!r}"

assert "2026 New Mexico QSO Party Form Packet" in rules, \
    "this is not the 2026 packet - re-verify every rule before shipping it"

# THE CHANGE LOG. The W1AW/5 bonus was cut from 500 to 250 on 09 April; assert
# both the cut and the 2026-only marker, so a later edition is noticed.
assert "Reduced number of bonus points for working W1AW/5 from 500 to 250" in rules, \
    "the packet's change log no longer records the 500->250 cut - re-read it"
assert "W1AW/5 Bonus (new, for 2026 only)" in rules, \
    "the W1AW/5 bonus is no longer marked 2026-only - it may need removing for 2027"

# The Cabrillo sample logs DX as a LITERAL TOKEN, which is what decides dxStyle
# even though the multiplier rule speaks of "DX entities" individually.
assert "599 DX" in rules, \
    "the sample log no longer shows DX as a literal token - re-check dxStyle"

nmqp = {
    "schemaVersion": 1,
    "id": "nmqp",
    "name": "New Mexico QSO Party",
    # Printed by the sponsor in its own sample log.
    "cabrilloContest": "NM-QSO-PARTY",
    "homeState": "NM",
    "countyAbbrLength": 3,
    # "160-10 meters, plus 6 and 2 meters", with WARC, 60 m and above-2 m
    # excluded by name.
    "validBands": BANDS,
    "points": {"phone": 1, "cw": 2, "digital": 2},
    # "Stations may be worked only once per mode, per band."
    "dupeScope": "bandMode",
    "multipliers": {
        # "each different NM county worked (up to 33), states worked (up to 50),
        # Canadian provinces/territories (up to 13) and DX entities worked."
        "inState": {
            "classes": ["county", "state", "province", "dx"],
            # "states worked (UP TO 50)" - fifty, not forty-nine, so New Mexico
            # is included; and NM stations send a county, so NM is never received.
            "homeStateCountsViaCounty": True,
            # "Each multiplier may be counted ONLY ONCE, regardless of mode or band."
            "countScope": "once",
        },
        # "each different NM county worked (up to 33)."
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
        },
    },
    "bonuses": [
        # "for a valid contact with W1AW/5 ... valid for one (1) W1AW/5 QSO only".
        # 2026 ONLY - delete when the 2027 packet is read.
        {"type": "workStation", "call": "W1AW/5", "points": 250, "scope": "once"},
        # "5,000 points ... for every county from which at least 15 valid QSOs
        # were made" - by far the largest activation bonus in this app.
        {"type": "activatedCountyCount", "minQSOs": 15, "points": 5000},
    ],
    # The rules say "DXCC entity", but the log format - and the sponsor's own
    # sample - carry the literal token "DX". See notes for what that costs.
    "dxStyle": "token",
    "allowedModes": ["phone", "cw", "digital"],
    # "only two counties at a time may be counted for the same contact."
    "maxSimultaneousCounties": 2,
    # "District of Columbia (DC) counts as Maryland."
    "stateAliases": {"DC": "MD"},
    # "RS(T) + New Mexico county"
    "exchangeIncludesRST": True,
    # "Non-NM stations: Work NM stations for NM counties only."
    "outStateWorksHomeStationsOnly": True,
    # WHOLE NUMBERS, so this ships - the first party since PAQP to carry a power
    # multiplier, and the largest QRP factor in the app.
    "scoreMultipliers": {"power": {"QRP": 5, "LOW": 2, "HIGH": 1}},
    # "Second Saturday of April, 8:00 MDT (1400 UTC) to 20:00 MDT (0200 UTC).
    # Duration: 12 hours." 11 April 2026 is that Saturday.
    "schedule": [{"start": "2026-04-11T14:00:00Z", "end": "2026-04-12T02:00:00Z"}],
    "counties": [{"abbr": a, "name": n} for a, n in sorted(counties.items(), key=lambda kv: kv[1])],
    "hubSpots": {
        "tableURL": "http://qsopartyhub.com/nmqp-table.php",
        "postURL": "http://qsopartyhub.com/nmqp-spots.php",
    },
    "notes": (
        "verified: partial - rules from the sponsor's own '2026 New Mexico QSO Party Form Packet' "
        "(NMQP_Forms.pdf, last modified 09 April 2026), read verbatim 2026-07-26. One document "
        "carries the rules, the county check sheet and the Cabrillo specification. "
        "THE PACKET KEEPS ITS OWN CHANGE LOG, which no other sponsor here does, and it earns its "
        "place: the W1AW/5 bonus was REDUCED FROM 500 TO 250 POINTS on 09 April, so a copy "
        "captured between 24 March and 9 April carries the wrong number. The 250 ships and the "
        "generator asserts it. The sponsor asks readers to re-check the page before the contest. "
        "THIS PARTY'S POWER MULTIPLIER WAS THE FIRST TO FIT A WHOLE NUMBER, which is worth "
        "saying because two others' did not. QRP is x5, low power x2 and high power x1 - all "
        "whole numbers - where Vermont's and Wisconsin's low-power factor is x1.5 and had to "
        "wait for exact fractions, which arrived 2026-07-28. All three are applied in full now. "
        "QRP at x5 is the largest score multiplier in this app. "
        "Twelve hours, 1400Z to 0200Z on Saturday 11 April 2026 - the second Saturday of April, "
        "and the sponsor states the formula, both UTC instants, both local instants and the "
        "duration in a single sentence, which is the most self-checking date statement of the "
        "run. It overlaps Missouri for its whole twelve hours. "
        "Phone 1 point, CW 2, digital 2. Multipliers count ONLY ONCE, regardless of mode or band. "
        "New Mexico stations count the 33 counties, all 50 states INCLUDING NEW MEXICO - the "
        "sponsor's 'up to 50' is what settles that, and NM is reachable only through a county - "
        "the 13 provinces and DX; everyone else counts the 33 counties. DC counts as Maryland. "
        "Alaska and Hawaii are states, not DX. Eight bands, with 60 m named separately from the "
        "WARC bands, which is the correct distinction and one several sponsors blur. County lines "
        "pay two counties and no more: the sponsor rules out the three-county case explicitly, "
        "and defines county lines by MARAC's county-hunter rules with a 50-metre tolerance. "
        "TWO BONUSES, BOTH MODELLED. New Mexico mobiles earn 5,000 points for every county from "
        "which they make at least 15 valid QSOs - by far the largest activation bonus in this app. "
        "And W1AW/5 pays 250 points ONCE, however many times it is worked; note this is a 2026-ONLY "
        "RULE, for the same ARRL celebration as Vermont's W1AW/1, and it must be deleted when the "
        "2027 packet is read. The sponsor also allows W1AW/5 to be worked again on the same band "
        "and mode from a different county, which this app already handles, since a county change "
        "makes a new QSO. "
        "FT8 AND FT4 ARE PERMITTED BUT CANNOT BE LOGGED NATIVELY. The sponsor requires the normal "
        "exchange, not grid squares: 'QSOs that contain grid squares or signal reports instead of "
        "the required exchange cannot be scored', and participants must either use a mode that "
        "carries the exchange, such as JS8Call, or EDIT THEIR LOGS BEFORE SUBMISSION - replacing "
        "signal reports with 599 and converting grid squares to the state, province or DXCC "
        "entity. That is the opposite of Mississippi, which makes grid squares a first-class "
        "exchange; both parties allow FT8 and neither can be logged natively. "
        "KNOWN LIMITATION - DX COLLAPSES TO ONE MULTIPLIER WHERE THE SPONSOR COUNTS ENTITIES. The "
        "multiplier rule counts 'DX entities worked' individually, but the log format carries the "
        "literal token DX - the packet says the QTH field is a county, a state or province, or "
        "'DX', and its own sample log shows LY2ZZ 599 DX. So a New Mexico entrant working ten "
        "DXCC entities is credited ONE multiplier instead of ten. THE SPONSOR'S OWN AUTOMATED "
        "SCORER FACES THE SAME PROBLEM, since the field it reads is DX too; it must derive the "
        "entity from the callsign, which is exactly the DXCC prefix table this app has wanted "
        "since NHQP. OUT-OF-STATE ENTRANTS ARE UNAFFECTED - their only multipliers are NM "
        "counties. Count your DX entities by hand if you are in New Mexico. "
        "Cabrillo CONTEST value NM-QSO-PARTY, printed by the sponsor in its own sample log. The "
        "packet also asks New Mexico stations to set ARRL-SECTION: NM or LOCATION: NM so the "
        "automated scorer identifies them. Counties are 33 with uniform 3-letter codes, and THE "
        "TRAP IS THE SAN/SANTA CLUSTER: SAN is SANDOVAL, not San Juan (SJU), not San Miguel (SMI) "
        "and not Santa Fe (SFE). Watch also COL Colfax against CIB Cibola. The sponsor prints "
        "'Dona Ana' without the tilde of the official Dona Ana County; it ships as printed. "
        "OPEN QUESTIONS (why this is partial): (1) The DX multiplier collapse above, which is a "
        "missing app feature rather than a rule in doubt, and which affects New Mexico entrants "
        "only. (2) The W1AW/5 bonus is explicitly 2026-only and must be removed for 2027; the "
        "generator asserts the marker is still present so its disappearance is noticed."
    ),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(nmqp, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"nmqp.json: {len(counties)} counties, uniform 3-letter codes")
print(f"  SAN is SANDOVAL - not San Juan (SJU), San Miguel (SMI) or Santa Fe (SFE)")
print(f"  POWER MULTIPLIER SHIPS: QRP x5, LOW x2, HIGH x1 - whole numbers, unlike VTQP/WIQP")
print(f"  points: phone 1, CW/digital 2; multipliers ONCE overall")
print(f"  bands: {len(BANDS)}; county lines capped at TWO, three ruled out explicitly")
print(f"  bonuses: W1AW/5 250 once (2026 ONLY) + 5,000 per county with 15+ QSOs")
print(f"  schedule: 1 window, 12 h - formula, UTC, local AND duration all stated")
print(f"  NOT shipped: individual DX entity multipliers (the log carries only 'DX')")
