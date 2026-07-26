#!/usr/bin/env python3
"""Generate idqp.json from the Idaho QSO Party's own documents.

Sources (committed alongside this script, so the run is reproducible):
  idqp_rules_2026.txt — text of https://idahoqsoparty.org/rules.htm. THE AUTHORITY
                        for every rule EXCEPT the dates; see below.
  idqp_counties.txt   — text of https://idahoqsoparty.org/MAPcountylist.htm,
                        "MAP & LIST of the 44 Idaho Counties"
  idqp_rules.md       — full rules research; all fetched 2026-07-26

Sponsor: Idaho QSO Party Contest Committee ("The SPUD RUN"), idahoqso@gmail.com.

RETRIEVAL NOTE: the county page 403s a plain fetch. It needs a browser
User-Agent AND a Referer of https://idahoqsoparty.org/ .

THE RULES' DATE BLOCK IS THE WORST IN THE REPO AND IS NOT READ LITERALLY HERE.
In eleven lines it calls 13 March 2026 a Saturday (it is a Friday), prints a
literal "xxxxZ" placeholder where the Saturday start time should be, dates the
Saturday end "14/March/2025" (wrong year), and labels 1400Z on "14/March/2026"
as the SUNDAY start (the 14th is a Saturday).

The schedule below is reconstructed from the three things that DO agree, and each
is asserted: the formula ("always the second full weekend of March"), the stated
12-hour durations, and the local-time anchors read under EDT - which the sponsor
itself flags with "LOOK OUT! check your computer time, Daylight time kicked in",
DST having begun 8 March 2026. See idqp_rules.md section 2.

WHAT DELIBERATELY DOES NOT SHIP, both verified and both unrepresentable:
  * "ALL QRP QSO's count 5 points" - PointsTable is keyed by mode alone and knows
    nothing of the entrant's power class. A QRP entrant is understated 2.5-5x.
  * the dormant-county bonus, which pays 500 OR 1000 OR 1500 depending which
    county, from a separately published list that changes yearly.

Usage:  python3 gen_idqp.py        (run from docs/research/)
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "idqp.json")
RULES = os.path.join(HERE, "idqp_rules_2026.txt")
COUNTIES = os.path.join(HERE, "idqp_counties.txt")


def read(path):
    s = open(path, encoding="utf-8", errors="replace").read()
    for a, b in [("’", "'"), ("‘", "'"), ("“", '"'), ("”", '"'),
                 ("–", "-"), ("—", "-"), (" ", " "), ("�", "")]:
        s = s.replace(a, b)
    return s


raw_rules = read(RULES)
rules = re.sub(r"\s+", " ", raw_rules)
counties_txt = read(COUNTIES)

# --- Counties: the sponsor's page lays them out as a table, so the text comes
# out as "ABBR" then "Name" - sometimes on one line, sometimes split. Collect
# every 3-letter code followed by a capitalised name. ---
body = counties_txt.split("Counties")[-1]
counties = {}
for abbr, name in re.findall(r"\b([A-Z]{3})\s+([A-Z][a-z]+(?: [A-Z][a-z]+)?)\b", body):
    name = " ".join(name.split())
    if abbr in counties and counties[abbr] != name:
        sys.exit(f"IDQP conflicting names for {abbr}: {counties[abbr]!r} vs {name!r}")
    counties[abbr] = name

assert len(counties) == 44, f"expected 44 ID counties, got {len(counties)}: {sorted(counties)}"
assert len(set(counties.values())) == 44, "ID county names not unique"
assert {len(a) for a in counties} == {3}, "ID codes are uniformly 3 letters"
assert "44 Idaho" in counties_txt, "the sponsor's own county count changed"
assert "the number of Idaho counties (44 total) is the multiplier" in rules

# THE B CLUSTER IS THE WORST IN THE REPO: ten counties begin with B, and BON is
# not a code at all, because Bonner and Bonneville would both claim it.
for abbr, name in [
    ("BAN", "Bannock"), ("BEA", "Bear Lake"), ("BEN", "Benewah"),
    ("BIN", "Bingham"), ("BLA", "Blaine"), ("BOI", "Boise"),
    ("BNR", "Bonner"), ("BNV", "Bonneville"),   # neither is BON
    ("BOU", "Boundary"), ("BUT", "Butte"),
    ("CAM", "Camas"), ("CAN", "Canyon"), ("CAR", "Caribou"), ("CAS", "Cassia"),
    ("CLA", "Clark"), ("CLE", "Clearwater"), ("CUS", "Custer"),
    ("LAT", "Latah"), ("LEM", "Lemhi"), ("LEW", "Lewis"), ("LIN", "Lincoln"),
    ("NEZ", "Nez Perce"), ("TWI", "Twin Falls"),     # two words each
    ("IDA", "Idaho"),      # the county, distinct from the never-sent ID token
    ("KOO", "Kootenai"), ("JEF", "Jefferson"), ("OWY", "Owyhee"),
]:
    assert counties.get(abbr) == name, f"{abbr} should be {name!r}, got {counties.get(abbr)!r}"
assert "BON" not in counties, \
    "BON is not an Idaho code - Bonner is BNR and Bonneville is BNV"
assert len([a for a in counties if a.startswith("B")]) == 10, \
    "the B cluster should be ten counties"

# --- Bands: "only 160 - 80 - 40 - 20 - 15 - 10 meters", stated twice. ---
BANDS = ["160m", "80m", "40m", "20m", "15m", "10m"]
assert "only 160 - 80 - 40 - 20 - 15 - 10 meters" in rules, "the band sentence changed"
assert rules.count("only 160 - 80 - 40 - 20 - 15 - 10 meters") >= 2, \
    "the sponsor states the band list twice; one of them is gone"
for excluded in ["60m", "30m", "17m", "12m", "6m", "2m", "1.25m", "70cm"]:
    assert excluded not in BANDS, f"{excluded} is not an IDQP band - HF only"

# --- The rule sentences this file encodes. ---
for quote in [
    # Contest period: the formula and the durations. NOT the printed dates.
    "Always the second full weekend of March",
    "Daylight time kicked in",
    # Exchange
    "Idaho stations send your counties three letter abbreviation",
    "W/VE stations (including KH6/KL7) send your state or province",
    "DX stations (including KH2/KP4, etc.) send your DXCC prefix/country",
    "the RST is no longer part of the contest",
    "you are not scored on RST reports",
    # Points
    "Each phone QSO counts as one point",
    "Each CW and Digital QSO counts as two points",
    # Multipliers
    "count each US state (including Idaho), Canada province, and DXCC country",
    "A multiplier is counted once per mode, regardless of the number of bands on which it is worked",
    "For non-Idaho stations: Idaho counties are multipliers",
    "An Idaho county multiplier will be counted once per mode",
    # County lines
    "Idaho stations on a county line may be claimed as a QSO and a multiplier from each county "
    "(2 QSO's and 2 multipliers)",
    # Dupes and modes
    "Stations may be worked once per mode, per band",
    "No cross-mode contacts are allowed",
    "FT-8 is incompatible with our exchange, so No FT-8 type modes",
    # Logs
    "ALL Logs must be Cabrillo files",
]:
    assert quote in rules, f"the rules no longer contain: {quote!r}"

# The two rules that deliberately do not ship. Assert they are still there, so a
# future edition dropping them leaves no stale limitation in the notes.
assert "ALL QRP QSO's count 5 points" in rules, \
    "the QRP points rule changed - revisit KNOWN LIMITATION 1"
assert "Bonus Points for activating dormant counties" in rules and \
    "500 bonus points (or 1000) (or 1500)" in rules, \
    "the dormant-county bonus changed - revisit KNOWN LIMITATION 2"

# The date block's own errors. Asserted so that a corrected page is NOTICED
# rather than silently absorbed - if any of these disappears, re-read section 2
# and check whether the reconstruction still holds.
for wrong in [
    "starts Saturday, March 13",   # the 13th is a Friday
    "xxxxZ",                       # literal placeholder for the Saturday start
    "14/March/2025",               # wrong year on the Saturday end
]:
    assert wrong in rules, (
        f"the rules no longer contain the erroneous {wrong!r} - the sponsor may have "
        "fixed the date block, so RE-READ IT and re-derive the schedule"
    )
# ...and the anchors the reconstruction actually rests on.
for anchor in ["03:59Z", "1400Z", "01:59Z", "12 Hours"]:
    assert anchor in rules, f"the date block no longer prints {anchor!r}"

idqp = {
    "schemaVersion": 1,
    "id": "idqp",
    "name": "Idaho QSO Party",
    # The rules require Cabrillo but print no CONTEST: token anywhere;
    # WA7BNM registry (Article 1's codified exception).
    "cabrilloContest": "ID-QSO-PARTY",
    "homeState": "ID",
    "countyAbbrLength": 3,
    # "only 160 - 80 - 40 - 20 - 15 - 10 meters" - HF only, no WARC, no VHF.
    "validBands": BANDS,
    # "Each phone QSO counts as one point. Each CW and Digital QSO counts as two."
    # NOTE the QRP rule ("ALL QRP QSO's count 5 points") cannot be expressed; see
    # notes, KNOWN LIMITATION 1.
    "points": {"phone": 1, "cw": 2, "digital": 2},
    # "Stations may be worked once per mode, per band."
    "dupeScope": "bandMode",
    "multipliers": {
        # "count each US state (including Idaho), Canada province, and DXCC
        # country as 'a' (one) multiplier."
        "inState": {
            "classes": ["county", "state", "province", "dx"],
            # "each US state (INCLUDING IDAHO)" - stated outright, as SCQP does,
            # and Idaho stations send a county so the token ID is never received.
            "homeStateCountsViaCounty": True,
            # "A multiplier is counted once per mode, regardless of the number of
            # bands on which it is worked."
            "countScope": "perMode",
        },
        # "For non-Idaho stations: Idaho counties are multipliers ... counted
        # once per mode, regardless of the number of bands."
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "perMode",
        },
    },
    # The dormant-county bonus pays 500 OR 1000 OR 1500 depending which county,
    # from a separately published list. activatedCountyCount carries one value,
    # so nothing ships. See notes, KNOWN LIMITATION 2.
    "bonuses": [],
    # "DX stations send your DXCC prefix/country", and Idaho stations count DXCC
    # countries individually.
    "dxStyle": "prefix",
    # Phone, CW and digital - "any digital mode that requires operator input",
    # which excludes FT8. See notes.
    "allowedModes": ["phone", "cw", "digital"],
    # "may be claimed as a QSO and a multiplier from each county (2 QSO's and 2
    # multipliers)."
    "maxSimultaneousCounties": 2,
    # "the RST is no longer part of the contest ... you are not scored on RST
    # reports." The exchange is a county, or a state/province, or a DX prefix.
    "exchangeIncludesRST": False,
    # Inferred rather than stated - see notes and idqp_rules.md section 13.
    "outStateWorksHomeStationsOnly": True,
    # RECONSTRUCTED - the sponsor's printed date block contains four errors. The
    # formula ("second full weekend of March" -> 14-15 March 2026), the stated
    # "12 Hours" per day, and the local anchors under EDT (DST began 8 March)
    # all agree on these four instants, as does the Challenge calendar.
    "schedule": [
        {"start": "2026-03-14T16:00:00Z", "end": "2026-03-15T04:00:00Z"},
        {"start": "2026-03-15T14:00:00Z", "end": "2026-03-16T02:00:00Z"},
    ],
    "counties": [{"abbr": a, "name": n} for a, n in sorted(counties.items(), key=lambda kv: kv[1])],
    "hubSpots": {
        "tableURL": "http://qsopartyhub.com/idqp-table.php",
        "postURL": "http://qsopartyhub.com/idqp-spots.php",
    },
    "notes": (
        "verified: partial - rules from the Idaho QSO Party's own pages, "
        "https://idahoqsoparty.org/rules.htm and its 'MAP & LIST of the 44 Idaho Counties', both "
        "read verbatim 2026-07-26. Sponsor contact idahoqso@gmail.com; logs to "
        "https://idqp.contesting.com/idqpsubmitlog.php, Cabrillo required. Known as THE SPUD RUN. "
        "Idaho is also one of the seven states of the 7th Call Area QSO Party, so this county list "
        "is reusable when 7QP is built. "
        "THE DATES ARE RECONSTRUCTED, NOT COPIED, AND THAT IS THE MAIN THING TO KNOW ABOUT THIS "
        "PARTY. The sponsor's date block contains four errors in eleven lines: it calls 13 March "
        "2026 a Saturday (it is a Friday), prints a literal 'xxxxZ' PLACEHOLDER where the Saturday "
        "start time should be, dates the Saturday end '14/March/2025' with the wrong year, and "
        "labels 1400Z on '14/March/2026' as the SUNDAY start when the 14th is a Saturday. The "
        "windows shipped here - 1600Z to 0400Z Saturday 14 March and 1400Z to 0200Z Sunday 15 "
        "March 2026, twelve hours each - are derived from the three things that do agree: the "
        "formula 'always the second full weekend of March', the 'ON THE AIR 12 Hours' printed "
        "under each day, and the local-time anchors read under EDT. That last point is the one the "
        "sponsor itself flags - 'LOOK OUT! check your computer time, Daylight time kicked in' - "
        "because US daylight time began 8 March 2026, the weekend before; under EST every anchor "
        "would be an hour out. The State QSO Party Challenge calendar independently prints the "
        "same four instants. The generator asserts the sponsor's errors are still present, so that "
        "a corrected page is noticed rather than silently absorbed. "
        "THE EXCHANGE CARRIES NO SIGNAL REPORT - 'the RST is no longer part of the contest ... you "
        "are not scored on RST reports' - the fourth party after MDC, MNQP and NCQP to drop it. "
        "Idaho stations send a county code and nothing else; W/VE stations send a state or "
        "province, with ALASKA AND HAWAII COUNTING AS W/VE; DX stations send a DXCC prefix, with "
        "GUAM AND PUERTO RICO COUNTING AS DX. Phone 1 point, CW and digital 2. Multipliers count "
        "ONCE PER MODE on both sides - not per band. Idaho stations count all 50 states INCLUDING "
        "IDAHO, the provinces and DXCC countries individually with no cap; everyone else counts "
        "the 44 Idaho counties. Idaho itself is reachable only through a county, which the sponsor "
        "states outright. County lines pay '2 QSO's and 2 multipliers', logged as separate lines, "
        "which is what this app writes; county lines are defined by County Hunter rules, by "
        "reference. Six bands, 160 m through 10 m, stated twice. FT8 is barred and the sponsor "
        "gives the reason - 'FT-8 is incompatible with our exchange' - since the exchange is a "
        "county abbreviation; that distinction is below this app's mode-class granularity, so KEEP "
        "FT8 OUT OF THE LOG. "
        "KNOWN LIMITATION 1 - QRP QSOs ARE WORTH 5 POINTS AND THIS APP PAYS THE NORMAL RATE. The "
        "rules say 'ALL QRP QSO's count 5 points. voice, CW, digital.' This app pays points by "
        "MODE only and knows nothing of the entrant's power class when scoring, so A QRP ENTRANT'S "
        "SCORE IS UNDERSTATED BY BETWEEN 2.5 AND 5 TIMES PER QSO. TO CORRECT BY HAND: score every "
        "QSO at 5 points instead of 1 or 2. Everyone at low or high power is exact. Note the rule "
        "is also ambiguous as written - 'ALL QRP QSO's' could mean QSOs made BY a QRP station or "
        "QSOs WITH one, and only the former scores consistently, since a worked station's power is "
        "not part of the exchange. KNOWN LIMITATION 2 - THE DORMANT-COUNTY BONUS IS NOT APPLIED. "
        "An Idaho expedition, rover or home station activating a county that was dormant in "
        "previous years earns 500, 1000 or 1500 bonus points - the amount depending which county - "
        "for more than 10 contacts from it. This app's activation bonus carries a single points "
        "value, and the tier list is published separately and changes every year, so nothing "
        "ships. IDAHO ROVERS AND EXPEDITIONS ONLY; every out-of-state entrant is unaffected. "
        "Cabrillo CONTEST value ID-QSO-PARTY per the WA7BNM registry - the rules require Cabrillo "
        "but print no header token. Counties are 44 with uniform 3-letter codes, and THE B CLUSTER "
        "IS THE WORST IN THIS APP: ten counties begin with B and BON IS NOT A CODE AT ALL, because "
        "Bonner (BNR) and Bonneville (BNV) would both claim it. Watch also BAN Bannock, BEA Bear "
        "Lake, BEN Benewah, BIN Bingham, BLA Blaine, BOI Boise, BOU Boundary and BUT Butte; the "
        "four Ca counties CAM Camas, CAN Canyon, CAR Caribou and CAS Cassia; CLA Clark against CLE "
        "Clearwater; and the four L counties LAT Latah, LEM Lemhi, LEW Lewis and LIN Lincoln. IDA "
        "is Idaho COUNTY, distinct from the ID state token, which is never sent. "
        "OPEN QUESTIONS (why this is partial): (1) THE DATES, per the reconstruction above. Three "
        "independent derivations and an outside calendar agree, but the sponsor's own block "
        "contradicts itself, so one email to idahoqso@gmail.com would settle it. (2) Whether "
        "stations outside Idaho may work only Idaho stations. The objective and the multiplier "
        "rules both point that way but no sentence forbids other contacts outright, unlike MNQP "
        "and NCQP; the restriction ships ON, as for six other parties, so a stray non-Idaho "
        "contact is visibly flagged NO CREDIT rather than silently scored. (3) Whether an Idaho "
        "station counts a received Idaho county as a multiplier in its own right, on top of the "
        "Idaho state multiplier it yields; the county classes ship on for in-state entrants, which "
        "is the reading that makes the received token meaningful. (4) 'Multiply QSO x Mode "
        "multiplier x Mults' in the final-score rule uses a term defined nowhere else; read as a "
        "restatement of the once-per-mode multiplier scope, which is how this app behaves. (5) The "
        "two KNOWN LIMITATIONS above are missing app features, not rules in doubt."
    ),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(idqp, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"idqp.json: {len(counties)} counties, uniform 3-letter codes")
print(f"  B cluster: 10 counties, and BON is not a code (Bonner BNR, Bonneville BNV)")
print(f"  points: phone 1, CW/digital 2; multipliers ONCE PER MODE both sides")
print(f"  exchange carries NO signal report; DX sends a prefix, uncapped")
print(f"  bands: {len(BANDS)} - 160 m through 10 m, stated twice")
print(f"  schedule: RECONSTRUCTED from formula + 12 h durations + EDT anchors")
print(f"    2 windows, 12 h + 12 h = 24 h (the printed block has FOUR date errors)")
print(f"  NOT shipped: QRP 5-point rule, tiered dormant-county bonus")
