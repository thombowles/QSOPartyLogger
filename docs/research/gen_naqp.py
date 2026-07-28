#!/usr/bin/env python3
"""Generate Resources/Parties/naqpcw.json and naqpssb.json — the North
American QSO Parties (NCJ), CW and SSB.

Per CONSTITUTION.md Article 2: the multiplier lists are parsed, never typed.

WHAT IS UNUSUAL HERE, so the next reader is not surprised:

1. THE "COUNTY" LIST IS THE SPONSOR'S OTHER-NA-COUNTRY LIST. NAQP has no
   counties; its finest enumerated multiplier class is the 47-entity country
   checklist printed six times (once per band) on the official paper log form.
   The BCQP precedent covers this: nothing requires the county class to hold
   literal counties. States and provinces ride the engine's existing state /
   province tables.

2. TWO SOURCES JOIN. Tokens come from the sponsor's checklist
   (naqp_paper_log_form.txt); entity names come from the ARRL DXCC List
   (arrl_dxcc_current_2026.txt), which is not a secondary source here — NAQP
   rules 3 and 11 designate "the ARRL DXCC List" by name. Every checklist
   token must resolve to an ARRL line whose continent column is NA, or this
   script fails loudly.

3. 46 OF 47 SHIP. HI (Dominican Republic) is printed by the sponsor as both a
   state and a country; the engine's state table shadows it, so it is omitted
   and carried as a scoreAffecting caveat. 4U1/u ships as 4U1 because "/" is
   the county-line separator and cannot be typed. Both are asserted below.

4. THE PAPER FORM'S STATE ROWS OMIT DC; RULE 11 GRANTS IT. The rules win —
   DC is its own multiplier, unaliased — and both facts are asserted so a
   future checklist revision that adds DC is noticed.

Sources (all banked, all fetched 2026-07-27):

  naqp_rules_2026.txt          https://www.ncjweb.com/NAQP-Rules.pdf
  naqp_paper_log_form.txt      https://ncjweb.com/NAQP-Paper-Log-Form.pdf
  arrl_dxcc_current_2026.txt   http://www2.arrl.org/files/file/DXCC/DXCC_Current.pdf

  See naqpcw_rules.md / naqpssb_rules.md.

Run:  python3 docs/research/gen_naqp.py
"""

import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
PARTIES = os.path.join(HERE, "..", "..", "Resources", "Parties")


def read(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        s = f.read()
    for a, b in [("’", "'"), ("‘", "'"), ("“", '"'), ("”", '"'),
                 ("–", "-"), ("—", "-"), (" ", " ")]:
        s = s.replace(a, b)
    return s


# --------------------------------------------------- the checklist, six times
# The form prints two pages of three band columns each. Cells sit side by
# side separated by 2+ spaces; a cell whose tokens include a digit is a
# country cell (VP9, XF4, 6Y…), a cell of pure 2-letter tokens is states or
# provinces. Column position within the page identifies the band box.
form = read("naqp_paper_log_form.txt")
# The checklist runs from its header to the web-entry links; page 3 is the
# paper log sheet (whose "Name Sent / QTH Sent" columns are one more
# confirmation of the exchange shape) and is not parsed.
checklist = form.split("Multiplier Check List", 1)[1].split("Manually enter", 1)[0]

BAND_HEADER = re.compile(r"^\s*(160M|80M|40M|20M|15M|10M)")

columns = {}          # band -> list of cells (each cell = one printed row)
current_bands = []    # the three bands of the block being read

for line in checklist.splitlines():
    headers = BAND_HEADER.findall(line)
    cells = [c for c in re.split(r"\s{2,}", line.strip()) if c]
    if headers and all(h in ("160M", "80M", "40M", "20M", "15M", "10M") for h in cells):
        current_bands = cells
        for band in cells:
            columns.setdefault(band, [])
        continue
    if not current_bands or not cells:
        continue
    # Data line: one cell per band column, left to right.
    assert len(cells) <= len(current_bands), f"more cells than bands: {line!r}"
    for band, cell in zip(current_bands, cells):
        columns[band].append(cell.split())

assert set(columns) == {"160M", "80M", "40M", "20M", "15M", "10M"}, sorted(columns)


def classify(cells):
    """(states, provinces, countries) for one band column, in printed order.

    Classified per printed ROW, not per token: eighteen country prefixes (CM,
    XE, ZF…) are two plain letters exactly like a state code, but every
    country row also carries at least one token with a digit (4U1/u, HK0,
    TI9, V2, YV0…) and no state or province row carries any. Membership then
    separates provinces from states.
    """
    states, provinces, countries = [], [], []
    PROVINCES = {"AB", "BC", "MB", "NB", "NL", "NT", "NS", "NU", "ON", "PE", "QC", "SK", "YT"}
    for cell in cells:
        if any(any(ch.isdigit() for ch in t) for t in cell):
            countries.extend(cell)
        elif all(t in PROVINCES for t in cell):
            provinces.extend(cell)
        else:
            states.extend(cell)
    return states, provinces, countries


per_band = {band: classify(cells) for band, cells in columns.items()}

# All six boxes must agree exactly, or the form changed and a human looks.
reference = per_band["160M"]
for band, triple in per_band.items():
    assert triple == reference, f"{band} box differs from 160M box"

states, provinces, countries = reference

# The paper form's states: 50, no DC. Rule 11 grants DC explicitly — "the
# District of Columbia (DC)" — and the engine's state table carries it; if a
# future form adds DC here, this assertion trips and both places get checked.
assert len(states) == 50 and len(set(states)) == 50, (len(states), states)
assert "DC" not in states, "form now lists DC — reconcile with rule 11"
assert "HI" in states and "AK" in states, "rule 3/11: Alaska and Hawaii are states"

rules = read("naqp_rules_2026.txt")
flat = re.sub(r"\s+", " ", rules)
assert ("Multipliers are all 50 US states, including Alaska and Hawaii, the District "
        "of Columbia (DC), the 13" in flat)

assert len(provinces) == 13 and len(set(provinces)) == 13, provinces

assert len(countries) == 47, (len(countries), countries)
assert len(set(countries)) == 47, "country tokens must be unique"
assert "4U1/u" in countries and "HI" in countries and "CM" in countries
assert "CO" not in countries, "the sponsor's Cuba token is CM, not CO"

# ------------------------------------------------- names from the ARRL list
# Rule 11: "other North American entities as defined by the ARRL DXCC List.
# For other North American entities, please use the standard DXCC prefix".
# Every token maps to one ARRL line; the line must carry continent NA. The
# messy prefix fields (ranges, alternates, glued footnote digits) get
# explicit line patterns; simple prefixes match themselves.
ARRL_OVERRIDES = {
    "4U1/u": r"4U.?UN",     # printed "4U_UN" by pdftotext; United Nations HQ
    "CM": r"CL-CM,\s*CO",   # "CL-CM, CO#*"  Cuba
    "HP": r"HO-HP",         # Panama
    "HR": r"HQ-HR",         # Honduras
    "TG": r"TG,\s*TD",      # Guatemala
    "TI": r"TI,\s*TE",      # Costa Rica
    "XE": r"XA-XI",         # Mexico
    "XF4": r"XA4-XI4",      # Revillagigedo
    "YN": r"YN,H6-7,HT",    # Nicaragua
    "YS": r"YS,\s*HU",      # El Salvador
    "KP4": r"KP3,4",        # Puerto Rico
    "KP5": r"KP5",          # "KP522" — Desecheo I., footnote 22 glued
    "PJ5": r"PJ5",          # "PJ5,652" — Saba & St. Eustatius
    "PJ7": r"PJ7",          # "PJ753" — Sint Maarten
    "FG": r"FG,\s*TO",      # Guadeloupe
    "FJ": r"FJ,\s*TO",      # Saint Barthelemy
    "FM": r"FM,\s*TO",      # Martinique
    "FO": r"FO,\s*TX",      # Clipperton I. — the NA row, not French Polynesia
    "FS": r"FS,\s*TO",      # Saint Martin
}

arrl_lines = [l for l in read("arrl_dxcc_current_2026.txt").splitlines()
              if re.search(r"\s(NA)\s", l)]


def arrl_name(token):
    pattern = ARRL_OVERRIDES.get(token, re.escape(token))
    line_re = re.compile(r"^\s*" + pattern + r"[^A-Za-z]*\s+([A-Za-z].*?)\s+NA\s")
    matches = [m.group(1).strip() for l in arrl_lines if (m := line_re.match(l))]
    assert matches, f"no ARRL NA line for {token}"
    name = matches[0]
    # pdftotext truncates one wrapped name mid-parenthesis:
    # "Bahamas (Commonwealth". Keep the head; the paren tail is a style
    # suffix in the ARRL layout, not part of the working name.
    if "(" in name and ")" not in name:
        name = name.split("(", 1)[0].strip()
    assert name, f"empty name for {token}"
    return name


# HI is deliberately NOT shipped: the engine's state table reads HI as
# Hawaii (rule 3 makes Hawaii a state), so the Dominican Republic cannot be
# a distinct token here. Asserted against the ARRL list so the omission
# stays explained, and carried as a scoreAffecting caveat in both parties.
assert arrl_name("HI") == "Dominican Republic"

shipped = []
for token in countries:
    if token == "HI":
        continue
    abbr = "4U1" if token == "4U1/u" else token
    assert "/" not in abbr, f"'/' is the county-line separator: {abbr}"
    shipped.append({"abbr": abbr, "name": arrl_name(token)})

assert len(shipped) == 46, len(shipped)
assert len({c["abbr"] for c in shipped}) == 46
assert {len(c["abbr"]) for c in shipped} == {2, 3, 4}, sorted({len(c["abbr"]) for c in shipped})

by_abbr = {c["abbr"]: c["name"] for c in shipped}
assert by_abbr["XE"] == "Mexico"
assert by_abbr["CM"] == "Cuba"
assert by_abbr["4U1"] == "United Nations HQ"
assert by_abbr["KP4"] == "Puerto Rico"
assert by_abbr["KP5"] == "Desecheo I."
assert by_abbr["PJ5"] == "Saba & St. Eustatius"
assert by_abbr["PJ7"] == "Sint Maarten"
assert by_abbr["FO"] == "Clipperton I."
assert by_abbr["HK0"] == "San Andres & Providencia"
assert by_abbr["C6"] == "Bahamas"
assert by_abbr["KG4"] == "Guantanamo Bay"
assert by_abbr["VP2E"] == "Anguilla"
assert by_abbr["YV0"] == "Aves I."
assert by_abbr["ZF"] == "Cayman Is."
assert "HI" not in by_abbr

# ------------------------------------------------------------------ the rules
assert "1800 UTC Jan 10 to 0559 UTC Jan 11" in flat
assert "1800 UTC Aug 1 to 0559 UTC Aug 2" in flat
assert "1800 UTC Jan 17 to 0559 UTC Jan 18" in flat
assert "1800 UTC Aug 15 to 0559 UTC Aug 16" in flat
assert "The contest period ends at 05:59:59 UTC" in flat
assert ("Exchange: Operator name and station location (state, province, or country) for "
        "North American stations; operator name only for non-North American stations." in flat)
assert "Mode: CW only in CW parties. SSB only in phone parties." in flat
assert "Bands: 160, 80, 40, 20, 15, and 10 meters only" in flat
assert "Stations may be worked once per band." in flat
assert "Multipliers count again on each band." in flat
assert ("Non-North American countries, maritime mobiles, and aeronautical mobiles do not "
        "count as multipliers but may be worked for QSO credit; these should be entered as "
        "DX in the received location field." in flat)
assert ("Scoring: Multiply total valid contacts by the sum of the number of multipliers "
        "worked on each band." in flat)
assert "Maximum of 100 W from the output of the final amplifier" in flat
assert "CONTEST:" not in rules, "rules now print a Cabrillo header — drop the WA7BNM citation"

# ------------------------------------------------------------------ assembly
CAVEAT_HI = (
    "A DOMINICAN REPUBLIC CONTACT IS CREDITED AS HAWAII, AND THE SCORE IS A FLOOR WHEN "
    "BOTH ARE WORKED ON ONE BAND. The sponsor's own multiplier checklist prints HI twice - "
    "among the states (Hawaii, a state by rule 3) and among the other-NA countries "
    "(Dominican Republic, ARRL DXCC list). One token cannot be two multipliers in this "
    "app; the state table wins, so a received HI always credits Hawaii, the Dominican "
    "Republic is omitted from the country list, and working both KH6 and an HI3 on the "
    "same band earns two multipliers from the sponsor but one here - at most one "
    "multiplier per band low, only when both are worked. The sponsor's log checker "
    "resolves the token by callsign; this app cannot."
)
CAVEAT_LOCATION = (
    "SETUP FOR US AND CANADIAN ENTRANTS IS 'OUTSIDE' PLUS YOUR STATE OR PROVINCE TOKEN; "
    "entrants in one of the 46 listed NA countries choose Inside and pick their country, "
    "and their exported Cabrillo LOCATION header then reads NA and must be hand-corrected "
    "to DX before submission. Entrants outside North America can log (location DX) but "
    "get no valid-contact filtering for non-NA-to-non-NA contacts, which the rules "
    "exclude. Neither affects a US or Canadian entrant."
)
CAVEAT_4U1 = (
    "THE CHECKLIST TOKEN '4U1/u' SHIPS AS 4U1, because '/' is reserved for county-line "
    "entry and cannot be typed in the exchange field. Log United Nations HQ as 4U1; the "
    "other 4U1 station (4U1WB, World Bank, Washington DC) sends DC and is unaffected."
)


def notes(mode_word, cabrillo, jan, aug, due, manager, form_url):
    return (
        f"Rules from the sponsor's own document: 'Rules: 2026 North American QSO Party "
        f"(CW/SSB/RTTY)', NCJ (National Contest Journal), printed NCJ October/November "
        f"2025, fetched from ncjweb.com 2026-07-27 and read verbatim - one document "
        f"governs all three NAQP modes, and this party is its {mode_word} event. NOT A "
        f"STATE QSO PARTY: NAQP is deliberately absent from the State QSO Party Challenge "
        f"approved list, appears under 'not approved' in the dashboard, and adds nothing "
        f"to the Challenge score. TWO RUNNINGS IN 2026, both windows shipped (Article 19, "
        f"target year only): {jan}, already past, and {aug}. The rules pin the endpoint "
        f"exactly - 'The contest period ends at 05:59:59 UTC'. Single ops may operate at "
        f"most 10 of the 12 hours with 30-minute minimum off-times, which this app does "
        f"not track. EXCHANGE IS NAME + LOCATION AND NOTHING ELSE - no RST, no serial: "
        f"'Operator name and station location (state, province, or country) for North "
        f"American stations; operator name only for non-North American stations', one "
        f"name for the whole contest. ONE POINT PER VALID CONTACT, one legal mode "
        f"('{mode_word} only'), stations worked once per band. MULTIPLIERS COUNT AGAIN ON "
        f"EACH BAND: all 50 US states plus DC - DC IS ITS OWN MULTIPLIER, never aliased "
        f"to MD - the standard 13 Canadian provinces/territories (NL spelling), and the "
        f"46-of-47 other-NA-country list generated by gen_naqp.py from the sponsor's own "
        f"paper-log multiplier checklist joined to the ARRL DXCC List (January 2026 "
        f"edition), which rules 3 and 11 designate by name. The country list rides in the "
        f"county slot (the BCQP precedent), so every country validates exactly and counts "
        f"per band; the sponsor's checklist prints the state rows WITHOUT DC while rule "
        f"11 grants it, and the rules win. Your own state counts - nothing is excluded. "
        f"Non-NA stations, maritime mobiles and aeronautical mobiles are QSO credit only, "
        f"'entered as DX in the received location field', which the dx-token-with-no-dx-"
        f"class shape reproduces: DX is loggable, pays its point, never multiplies. "
        f"Cuba is CM on the sponsor's checklist - typing CO credits Colorado. NO bonus "
        f"stations, NO final-score multipliers; QRP and Low Power are entry categories "
        f"(over 100 W is reclassified a check log). Bands 160/80/40/20/15/10 m. Cabrillo "
        f"CONTEST header {cabrillo} per the WA7BNM registry (Article 1 exception - the "
        f"rules print no token). Logs due within 7 days ({due}) at "
        f"ncjweb.com/naqplogsubmit; paper logs via {form_url}. Contest manager: "
        f"{manager}. Not modelled, deliberately: the 10-of-12-hour off-time accounting, "
        f"M2's 10-minute band timer (rule 5C(vi)), and the sponsor-side NIL/bust penalty "
        f"arithmetic of rule 12. Nothing may follow the last marked item below: the "
        f"caveats pass (gen_caveats.py) copies each item's body from the notes, and a "
        f"trailing paragraph would ride along into the last caveat's detail. "
        f"KNOWN LIMITATION 1: {CAVEAT_HI} KNOWN LIMITATION 2: "
        f"{CAVEAT_LOCATION} KNOWN LIMITATION 3: {CAVEAT_4U1}"
    )


def party(pid, pname, cabrillo, mode, schedule, note_text):
    return {
        "schemaVersion": 1,
        "id": pid,
        "name": pname,
        "cabrilloContest": cabrillo,
        "homeState": "NA",
        "countyAbbrLength": 2,
        "validBands": ["160m", "80m", "40m", "20m", "15m", "10m"],
        "points": {"phone": 1, "cw": 1, "digital": 1},
        "dupeScope": "bandMode",
        "multipliers": {
            "inState": {
                "classes": ["county", "state", "province"],
                "homeStateCountsViaCounty": False,
                "countScope": "perBand",
            },
            "outState": {
                "classes": ["county", "state", "province"],
                "homeStateCountsViaCounty": False,
                "countScope": "perBand",
            },
        },
        "bonuses": [],
        "dxStyle": "token",
        "allowedModes": [mode],
        "maxSimultaneousCounties": 1,
        "inStateLabel": "the other NA countries",
        "exchangeIncludesRST": False,
        "exchangeIncludesName": True,
        "schedule": schedule,
        "counties": shipped,
        "notes": note_text,
        "caveats": [
            {
                "kind": "scoreAffecting",
                "summary": "A Dominican Republic (HI) contact is credited as Hawaii - "
                           "work both on one band and the score is one multiplier low.",
                "detail": CAVEAT_HI,
            },
            {
                "kind": "cosmetic",
                "summary": "US/VE entrants: set up as Outside with your state or "
                           "province. Entrants in another NA country: Inside, then "
                           "hand-fix the Cabrillo LOCATION header to DX.",
                "detail": CAVEAT_LOCATION,
            },
            {
                "kind": "cosmetic",
                "summary": "Log United Nations HQ as 4U1 - the checklist's '4U1/u' "
                           "cannot be typed because '/' separates county lines.",
                "detail": CAVEAT_4U1,
            },
        ],
    }


naqpcw = party(
    "naqpcw",
    "North American QSO Party, CW",
    "NAQP-CW",
    "cw",
    [
        {"start": "2026-01-10T18:00:00Z", "end": "2026-01-11T06:00:00Z"},
        {"start": "2026-08-01T18:00:00Z", "end": "2026-08-02T06:00:00Z"},
    ],
    notes(
        "CW", "NAQP-CW",
        "1800 UTC 10 January to 0559:59 UTC 11 January",
        "1800 UTC 1 August to 0559:59 UTC 2 August",
        "CW August: 0600 UTC August 9",
        "Dave Mueller, N2NL, cwnaqpmgr@ncjweb.com",
        "b4h.net/cabforms/naqpcw_cab.php",
    ),
)

naqpssb = party(
    "naqpssb",
    "North American QSO Party, SSB",
    "NAQP-SSB",
    "phone",
    [
        {"start": "2026-01-17T18:00:00Z", "end": "2026-01-18T06:00:00Z"},
        {"start": "2026-08-15T18:00:00Z", "end": "2026-08-16T06:00:00Z"},
    ],
    notes(
        "SSB", "NAQP-SSB",
        "1800 UTC 17 January to 0559:59 UTC 18 January",
        "1800 UTC 15 August to 0559:59 UTC 16 August",
        "SSB August: 0600 UTC August 23",
        "Bill Lippert, AC0W, ssbnaqpmgr@ncjweb.com",
        "b4h.net/cabforms/naqpssb_cab.php",
    ),
)

# The caveat details above are copied into notes verbatim (Article 2's rule
# that `detail` is never retyped) — prove the copy holds.
for p in (naqpcw, naqpssb):
    for caveat in p["caveats"]:
        assert caveat["detail"] in p["notes"], f"{p['id']}: caveat detail not in notes"
    assert "verified: partial" not in p["notes"].lower(), \
        "NAQP is fully verified — the marker must not appear"

for p, fname in ((naqpcw, "naqpcw.json"), (naqpssb, "naqpssb.json")):
    path = os.path.join(PARTIES, fname)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(p, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"wrote {path}: {len(p['counties'])} countries, "
          f"{len(p['schedule'])} windows")

assert naqpcw["counties"] == naqpssb["counties"], "the two lists must be identical"
print("OK: 46 countries shipped (HI omitted, 4U1/u -> 4U1), 50 states + 13 "
      "provinces verified on the sponsor's checklist, DC granted by rule 11.")
