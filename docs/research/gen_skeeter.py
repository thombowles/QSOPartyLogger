#!/usr/bin/env python3
"""Generate Resources/Parties/skeeter.json — the NJQRP Skeeter Hunt.

WHAT IS UNUSUAL HERE, all four firsts for this catalogue:

  1. NO COUNTY LIST AT ALL. The multipliers are S/P/Cs counted once — the
     app's own state/province tables plus DXCC entities — so `counties` is
     empty (permitted for hasHomeRegion: false parties). The Article 2
     hard-count assertion therefore has nothing to count; its analogue here
     is the SCORE FORMULA VERIFICATION below, plus roster spot checks.
  2. THE POINTS COME FROM THE RECEIVED EXCHANGE, not the mode: a member
     number pays 3, a QRP power 2, anything else 1 (`memberExchange`).
  3. THE CLASS MULTIPLIER IS SELF-DECLARED X1–X4 (`entryClasses`), not a
     product of the Cabrillo category axes.
  4. THE SCORE FORMULA IS NOWHERE PRINTED. This generator re-derives
     total = (3·skeeter + 2·qrp + 1·qro) × S/P/Cs × class + bonus
     from the sponsor's own 2025 final scoreboard and asserts it EXACTLY on
     named rows (the top three, the contest manager, and KE5CW's own
     High Score TX row) — a wrong formula cannot regenerate this file.

Sources (all banked beside this script; see skeeter_rules.md):
  - skeeter_rules_2026.txt — W2LJ's blog page, the current (15th Annual,
    2026) rules, fetched 2026-08-04.
  - skeeter_qslnet_page_2025.txt — the qsl.net official page, still the
    2025 edition on the same date; rules identical except date/roster link.
  - skeeter_scoreboard_2025.csv — the sponsor's 2025 final scoreboard.
  - skeeter_roster_2026.csv — the live 2026 roster, 187 numbers assigned
    at fetch.

Run:  python3 docs/research/gen_skeeter.py
Then (pipeline order, or blocks silently drop):
      python3 docs/research/gen_callhistory.py
      python3 docs/research/gen_caveats.py
"""
import csv
import json
import re
from pathlib import Path

HERE = Path(__file__).parent
OUT = HERE.parent.parent / "Resources" / "Parties" / "skeeter.json"

RULES = (HERE / "skeeter_rules_2026.txt").read_text()
FLAT = re.sub(r"\s+", " ", RULES)

# --- 1. The rules, verbatim -------------------------------------------------

REQUIRED_QUOTES = [
    "15th Annual",
    "held on Sunday August 16th, 2026",
    "from 17:00 UTC to 21:00 UTC",
    "Skeeter number",
    "Output power (For example - 559 NY 5W)",
    "Working a Skeeter Station - 3 points",
    "Working a non-Skeeter, but QRP station - 2 points",
    "Working any other QRO station - 1 point",
    "only count once for multiplier credit",
    "X1 Home stations - commercial transceiver or separates",
    "X2 Home stations - home brewed or kit built transceiver or separates",
    "X3 Portable station - commercial transceiver or separates",
    "X4 Portable station - home brewed or kit built transceiver or separates",
    "5W max CW, 10 Watts max SSB",
    "add up to exactly 21",
    "1,000 Bonus Points",
    "You can use any call sign worked ONCE",
    "no later than 14 days after the event",
    "Please no ADIF, Cabrillo or N1MM files",
]
for quote in REQUIRED_QUOTES:
    assert quote in FLAT, f"rules text lost: {quote!r}"

# The five bands, from the watering-hole lists — CW and SSB frequencies both.
for mhz in ["3.560", "7.040", "14.060", "21.060", "28.060",
            "3.985", "7.285", "14.285", "21.385", "28.885"]:
    assert mhz in FLAT, f"watering hole missing: {mhz}"
assert "160" not in re.sub(r"\d\.\d+", "", FLAT.split("Suggested frequencies")[1]
                           .split("Categories")[0]), "an unexpected band appeared"

# --- 2. The score formula, from the sponsor's own arithmetic ---------------

rows = list(csv.reader((HERE / "skeeter_scoreboard_2025.csv").open()))
header = [c.strip() for c in rows[0]]
assert header[:12] == ["Skeeter #", "Call", "Name", "S/P/C", "Mode",
                       "Skeeter QSOs", "Non-Skeeter QRP QSOs", "Non-QRP QSOs",
                       "S/P/C", "Station Class", "Bonus Points", "Total"], header[:12]

verified = {}
for row in rows[1:]:
    if len(row) < 12:
        continue
    cells = [c.strip() for c in row[:12]]
    if not all(cells[i].lstrip("-").isdigit() for i in [5, 6, 7, 8, 9, 10, 11]):
        continue
    sk, qrp, qro, spc, cls, bonus, total = (int(cells[i]) for i in
                                            [5, 6, 7, 8, 9, 10, 11])
    if total == 0:
        continue
    computed = (3 * sk + 2 * qrp + qro) * spc * cls + bonus
    assert computed == total, (
        f"{cells[1]}: formula gives {computed}, scoreboard says {total} — "
        "the score model is wrong, do not ship it")
    verified[cells[1].upper()] = total

assert len(verified) >= 100, f"only {len(verified)} scoreboard rows verified"
for call, expected in [("AD0YM", 25832), ("NK9G", 24968), ("W4MPS", 24880),
                       ("KE5CW", 14464), ("W2LJ", 10660)]:
    assert verified.get(call) == expected, (call, verified.get(call), expected)

# --- 3. The roster, spot-checked -------------------------------------------

roster = list(csv.reader((HERE / "skeeter_roster_2026.csv").open()))
assigned = {}
for row in roster[1:]:
    if len(row) > 3 and row[0].strip().isdigit() and row[1].strip():
        assigned.setdefault(row[1].strip().upper(), []).append(row[0].strip())
assert len(assigned) == 186, f"{len(assigned)} distinct calls (K3UT holds two numbers)"
assert sum(len(v) for v in assigned.values()) == 187, "187 assigned numbers at fetch"
assert assigned["W2LJ"] == ["13"], "the manager's traditional number"
assert assigned["KE5CW"] == ["20"]
assert assigned["K3UT"] == ["25", "183"], "one call, two numbers — the parser's overwrite case"

# --- 4. The caveat prose (numbered items; gen_caveats.py copies bodies) -----

OPEN_Q_DUPES = (
    "MAY A MIXED ENTRY WORK THE SAME STATION ON BOTH MODES OF ONE BAND? "
    "The rules say only 'Stations can be worked on different bands for QSO "
    "points', naming bands alone, and the categories are mode-split so the "
    "case arises only for Mixed entries. This app counts band x mode, so a "
    "same-band CW and SSB pair with one station is credited as two QSOs; a "
    "stricter per-band reading would count one. Ask W2LJ (w2ljqrp@gmail.com) "
    "before claiming such a pair."
)
KL_CABRILLO = (
    "THE CABRILLO CONTEST HEADER 'SKEETER-HUNT' IS THIS APP'S OWN INVENTION. "
    "The sponsor accepts no log files at all - 'Please no ADIF, Cabrillo or "
    "N1MM files!' - and the WA7BNM registry has no Skeeter Hunt entry "
    "(checked 2026-08-04), so the header has no recipient anywhere; the "
    "export exists for your own records. Submission is a plain-text summary "
    "email to w2ljqrp@gmail.com within 14 days, and the score sidebar keeps "
    "every number it wants on screen: Skeeter / QRP / QRO QSO counts, "
    "S/P/Cs, the class factor, and the bonus."
)
KL_QRP = (
    "'QRP STATION' IS READ AS AT MOST 5 W ON CW AND 10 W ON PHONE, "
    "inclusive - the event's own power limits ('Power - 5W max CW, 10 Watts "
    "max SSB') - because the scoring text never defines it. A received "
    "'10W' on phone pays 2 points; the same on CW pays 1."
)
KL_BLACKJACK = (
    "A CALLSIGN'S BLACKJACK DIGIT IS READ AS ITS FIRST DIGIT, with 0 worth "
    "10 - every example the sponsor gives satisfies this, but portable and "
    "DX call shapes are not addressed by the rules. The 1,000 points are "
    "credited automatically the moment some set of distinct worked calls "
    "can hit exactly 21, but the sponsor requires listing the calls in the "
    "summary email - pick and list them yourself."
)

NOTES = (
    "Rules from the sponsor's own current page: W2LJ's 'NJQRP Skeeter Hunt' "
    "blog page (w2lj.blogspot.com/p/njqrp-skeeter-hunt.html), naming the "
    "15th Annual event, read live and fetched 2026-08-04; the qsl.net "
    "'Official NJQRP Skeeter Hunt Webpage' still carried the 2025 edition "
    "the same day, every rule identical except the date and the roster "
    "link. NOT A STATE QSO PARTY: a four-hour NJQRP club QRP sprint, absent "
    "from the Challenge calendar, added at KE5CW's request (he is Skeeter "
    "#20 this year and took High Score TX in 2025). ONE WINDOW (Article 19, "
    "target year only): 'The event is to be held on Sunday August 16th, "
    "2026. It will be a four hour sprint - from 17:00 UTC to 21:00 UTC "
    "(1:00 TO 5:00 PM EDT).' EXCHANGE IS RST + S/P/C + SKEETER NUMBER OR "
    "OUTPUT POWER ('For example - 559 NY 5W'), and the third element "
    "decides the points regardless of mode: 'Working a Skeeter Station - 3 "
    "points / Working a non-Skeeter, but QRP station - 2 points / Working "
    "any other QRO station - 1 point'. In this app the element is required "
    "- a contact will not log without a number or a power with its unit "
    "(5W, 500MW, 2.5W), which is what keeps the 3/2/1 honest. MULTIPLIERS "
    "ARE S/P/CS COUNTED ONCE for the whole contest - 'S/P/C's only count "
    "once for multiplier credit', with the sponsor's own example (W2LJ on "
    "40, 20 and 15 is three QSOs and one NJ) - drawn from the app's "
    "standard state and province tables plus DXCC entities counted "
    "individually (the C in S/P/C), WHICH IS WHY THIS PARTY ENUMERATES NO "
    "LIST OF ITS OWN. STATION CLASS X1-X4 MULTIPLIES THE WHOLE SCORE: X1 "
    "home/commercial, X2 home/home-brew-or-kit, X3 portable/commercial, X4 "
    "portable/home-brew-or-kit; mobiles count as portable, and a kit "
    "counts as home-brew when 'The operator's hands were involved in more "
    "than 50% of the building'. Pick yours in Contest Setup - unset, the "
    "app scores the lowest (X1). THE SCORE FORMULA IS NOWHERE PRINTED AND "
    "WAS VERIFIED AGAINST THE SPONSOR'S OWN 2025 FINAL SCOREBOARD: (3 x "
    "Skeeter + 2 x QRP + 1 x QRO) x S/P/Cs x class + bonus, exact on every "
    "one of 100+ scored rows including the top three and KE5CW's own - "
    "gen_skeeter.py re-derives it and refuses to build otherwise. SKEETER "
    "HUNT BLACKJACK (returning from 2025; the bonus gimmick can change "
    "yearly): 1,000 points once when distinct worked callsigns' call-area "
    "digits - '0' worth 10, 'any call sign worked ONCE' - sum to exactly "
    "21. BANDS 80/40/20/15/10, taken from the rules' QRP 'Watering Holes' "
    "frequency lists, the only bands the sponsor names. MODES CW AND SSB "
    "('Mode - CW, SSB'); power limits 5W CW / 10W SSB are entry "
    "conditions, not categories. CATEGORIES (CW Only / SSB Only / Mixed, "
    "and informal multi-op) are not modelled - submission is prose. THE "
    "ROSTER IS THE PREFILL SOURCE: a live Google Sheet linked from the "
    "blog page ('The entire 2026 Skeeter Hunt roster can be seen'), "
    "re-fetched through the call history machinery on the daily clock "
    "because numbers issue until the day before the event; its document id "
    "changes every season, so the app discovers it from the blog page "
    "rather than pinning a URL. Roster data is prefill only - the points "
    "come from what the station actually sends you, never from roster "
    "membership. verified: partial - the sponsor's prose leaves real "
    "questions open, each below with what it costs. "
    f"OPEN QUESTION 1: {OPEN_Q_DUPES} "
    f"KNOWN LIMITATION 1: {KL_CABRILLO} "
    f"KNOWN LIMITATION 2: {KL_QRP} "
    f"KNOWN LIMITATION 3: {KL_BLACKJACK}"
)

assert "verified: partial" in NOTES
for body in [OPEN_Q_DUPES, KL_CABRILLO, KL_QRP, KL_BLACKJACK]:
    assert body in NOTES

# --- 5. The party ----------------------------------------------------------

party = {
    "schemaVersion": 1,
    "id": "skeeter",
    "name": "NJQRP Skeeter Hunt",
    # KNOWN LIMITATION 1: no Cabrillo name exists anywhere; this is the
    # app's own header for the operator's records.
    "cabrilloContest": "SKEETER-HUNT",
    # A pseudo-state, labels only — the NAQP precedent. hasHomeRegion: false
    # keeps it out of every export that matters.
    "homeState": "NA",
    "countyAbbrLength": 2,
    "validBands": ["80m", "40m", "20m", "15m", "10m"],
    # The floor a row falls back to when its member element is unreadable —
    # every gated row scores from memberExchange instead.
    "points": {"phone": 1, "cw": 1, "digital": 1},
    "dupeScope": "bandMode",
    "multipliers": {
        # No home region: both sides identical by construction.
        side: {
            "classes": ["state", "province", "dx"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
            "dxCountsEntities": True,
        }
        for side in ("inState", "outState")
    },
    "bonuses": [{"type": "callAreaSum", "target": 21, "points": 1000}],
    "dxStyle": "prefix",
    # A DX country is typed as its prefix; a bare DX is also accepted and
    # the entity resolves from the callsign (the OQP pairing).
    "acceptsDXToken": True,
    "allowedModes": ["phone", "cw"],
    "maxSimultaneousCounties": 1,
    "hasHomeRegion": False,
    "memberExchange": {
        "term": "Skeeter number",
        "shortTerm": "Skeeter #",
        "memberPoints": 3,
        "qrpPoints": 2,
        "otherPoints": 1,
        # KNOWN LIMITATION 2: the event's own power limits, inclusive.
        "qrpMaxWatts": {"phone": 10, "cw": 5, "digital": 5},
    },
    "entryClasses": [
        {"id": "X1", "label": "Home station, commercial equipment", "factor": 1},
        {"id": "X2", "label": "Home station, home brewed or kit built", "factor": 2},
        {"id": "X3", "label": "Portable station, commercial equipment", "factor": 3},
        {"id": "X4", "label": "Portable station, home brewed or kit built", "factor": 4},
    ],
    "schedule": [
        {"start": "2026-08-16T17:00:00Z", "end": "2026-08-16T21:00:00Z"},
    ],
    "counties": [],
    "notes": NOTES,
    # gen_callhistory.py verifies this block against its own roster of
    # special sources; gen_caveats.py appends the caveats. Run both after
    # this script (pipeline order).
    "callHistory": {
        "kind": "w2ljRosterPage",
        "pageURL": "http://w2lj.blogspot.com/p/njqrp-skeeter-hunt.html",
        "filePrefix": "SKEETER",
        "token": "SKEETER ROSTER",
    },
}

with open(OUT, "w") as f:
    json.dump(party, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"wrote {OUT.name}: formula verified on {len(verified)} rows, "
      f"roster {sum(len(v) for v in assigned.values())} numbers")
