#!/usr/bin/env python3
"""Generate Resources/Parties/fobb.json — the ARS Flight of the Bumblebees.

WHAT IS UNUSUAL HERE:

  1. NO COUNTY LIST AT ALL, and the S/P/C earns NOTHING. The exchange
     carries a state/province/country, which is validated against the app's
     standard tables and DXCC prefixes, and no counting phrase attaches to
     it anywhere in the rules. `counties` is empty (permitted for
     hasHomeRegion: false parties). The Article 2 hard-count assertion has
     no county list to count; its analogues here are the SCORE FORMULA
     VERIFICATION and the ROSTER ASSERTIONS below.
  2. THE MULTIPLIER IS BUMBLEBEES WORKED, counted again on each band — the
     `member` MultClass, driven by the received member element.
  3. THE MULTIPLIER HAS A PRINTED FLOOR OF 1, so a log with contacts and no
     Bumblebee still scores contacts x 1 x 3 (`multiplierFloor`).
  4. THE x3 IS FOLDED INTO THE POINTS. Every valid contact pays 3 whatever
     the received element says, so the engine's points x multipliers IS the
     sponsor's printed formula with no new arithmetic. The member element
     therefore decides Bumblebee-ness only, never the rate.
  5. TWO WINDOWS A YEAR (the NAQP precedent), both sponsor-printed: the
     Legacy running in July and the Fall running in September.

Sources (all banked beside this script; see fobb_rules.md):
  - fobb_rules_2026.txt — the sponsor's live page, fetched 2026-08-10,
    headed for the Fall running ("Last Updated : 27JUL26").
  - fobb_rules_2026_july_wayback.txt — the same page as captured by the
    Internet Archive on 2026-07-23 (snapshot 20260723202047), printing the
    July running's date. Every rule identical.
  - fobb_3830_claimed_2026-07.csv — the July 2026 claimed scores from
    3830scores.com, the results venue the rules designate by name.
  - fobb_roster_2026-07.csv — the sponsor's self-serve Bumblebee number
    report, 234 numbers at fetch.

Run:  python3 docs/research/gen_fobb.py
Then (pipeline order, or blocks silently drop):
      python3 docs/research/gen_hub_map.py
      python3 docs/research/gen_callhistory.py
      python3 docs/research/gen_caveats.py
"""
import csv
import json
import re
from pathlib import Path

HERE = Path(__file__).parent
OUT = HERE.parent.parent / "Resources" / "Parties" / "fobb.json"

FALL = (HERE / "fobb_rules_2026.txt").read_text()
JULY = (HERE / "fobb_rules_2026_july_wayback.txt").read_text()
FLAT_FALL = re.sub(r"\s+", " ", FALL)
FLAT_JULY = re.sub(r"\s+", " ", JULY)

# --- 1. The rules, verbatim -------------------------------------------------
# A drifted page must fail here rather than ship quietly.

REQUIRED_QUOTES = [
    "held twice each Year",
    "last Sunday of July",
    "3rd Sunday in September",
    "1700 to 2100 UTC",
    "Your BB Number",
    "Your Power Output",
    "once on each Band",
    "additional Bumblebee Worked",
    "[Total Contacts]",
    "x [Number of Bumblebees]",
    "Defaults to [Total Contacts] = 1",
    "Bumblebee Numbers are only valid for One FOBB Event",
    "5W QRP Maximum",
]
for quote in REQUIRED_QUOTES:
    assert re.sub(r"\s+", " ", quote) in FLAT_FALL, f"rules text lost: {quote!r}"

# Both runnings' dates come from the sponsor's own page — the Fall one live,
# the July one from the pre-event capture (Article 19: printed, never derived
# from the formula, even though both agree with it).
assert "Sunday, September 20, 2026" in FLAT_FALL, "the Fall date is the live page's"
assert "Sunday, July 26, 2026" in FLAT_JULY, "the Legacy date is the capture's"

# Five bands and no others: the TARGET SCENTS list is the only place the
# sponsor names bands at all.
for mhz in ["3.566", "7.036", "14.036", "21.036", "28.036"]:
    assert mhz in FLAT_FALL, f"target scent missing: {mhz}"
assert "1.8" not in FLAT_FALL, "no 160 m anywhere in the rules"
assert "10.1" not in FLAT_FALL, "no WARC anywhere in the rules"

# --- 2. The score formula, verified against the sponsor's own calculator ----
# The rules print the formula; 3830scores.com — designated by the rules as
# the results venue — computes it. Every row of the July 2026 table must
# satisfy it exactly, which is what makes a wrong formula unshippable.

rows = list(csv.DictReader(open(HERE / "fobb_3830_claimed_2026-07.csv")))
assert len(rows) == 90, f"expected 90 claimed rows, got {len(rows)}"
sections = {r["section"] for r in rows}
assert sections == {
    "Bumblebee LP", "Bumblebee QRP", "Home LP", "Home QRP",
}, f"3830's own section split changed: {sections}"
def number(cell):
    """3830 prints thousands separators in the score column."""
    return int(cell.replace(",", ""))


for r in rows:
    q, b, s = number(r["qsos"]), number(r["bumblebees"]), number(r["score"])
    assert s == q * b * 3, f"{r['call']}: {q} x {b} x 3 != {s}"

# The one observed zero row anchors OPEN QUESTION 1: a 0/0 entry scored 0,
# not the 1 x 1 x 3 a literal reading of the printed defaults would give.
zero = [r for r in rows if r["qsos"] == "0"]
assert [r["call"] for r in zero] == ["K4UPG"], f"unexpected zero rows: {zero}"
assert zero[0]["score"] == "0", "the observed zero row scores 0"

# --- 3. The roster ----------------------------------------------------------

roster = list(csv.DictReader(open(HERE / "fobb_roster_2026-07.csv")))
assert len(roster) == 234, f"expected 234 numbered rows, got {len(roster)}"
numbers = sorted(int(r["BB"]) for r in roster)
assert numbers == list(range(1, 235)), "numbers 1..234, no gap and no duplicate"

by_call = {}
for r in roster:
    call = r["Callsign"].strip().upper()
    by_call.setdefault(call, []).append(r["BB"])

assert by_call["K2SQS"] == ["1"], "the first number"
assert by_call["W4KAC"] == ["7"]
assert by_call["K4KBL"] == ["234"], "the last number at fetch"
assert by_call["NN5DE"] == ["65", "122"], "one call, two numbers — the parser's repeat case"
# One number was issued and never claimed: its call, name and SPC cells are
# all empty, so 234 numbers yield 233 offerable stations and the parser must
# drop the row rather than index a record keyed on nothing.
assert by_call[""] == ["50"], "exactly one callsign-less number, and it is #50"
assert len(by_call) - 1 == 232, "232 distinct calls besides the blank row"
assert sum(len(v) for v in by_call.values() if v != ["50"]) == 233

# --- 4. The party -----------------------------------------------------------

NOTES = (
    "Rules from the sponsor's own page: ars-qrp.com/FOBB/FOBB.html, read live and "
    "fetched 2026-08-10 ('Last Updated : 27JUL26'), headed for the next running - "
    "'Fall Flight of the Bumblebees / Sunday, September 20, 2026 / 1700 to 2100 UTC'. "
    "The July (Legacy) edition of the same page, captured by the Internet Archive on "
    "2026-07-23 (snapshot 20260723202047), printed 'Legacy Flight of the Bumblebees / "
    "Sunday, July 26, 2026' with every rule identical. NOT A STATE QSO PARTY: a "
    "four-hour Adventure Radio Society QRP CW sprint held twice a year - 'held twice "
    "each Year - Annually on the last Sunday of July. - Annually on the 3rd Sunday in "
    "September' - and the event the NJQRP Skeeter Hunt was modelled on. BOTH 2026 "
    "WINDOWS SHIP (Article 19, target year only - the NAQP precedent for a twice-a-year "
    "contest): 2026-07-26 and 2026-09-20, each 1700-2100Z, both sponsor-printed. "
    "EXCHANGE IS RST + S/P/C + BUMBLEBEE NUMBER OR POWER OUTPUT ('If you are a "
    "Bumblebee: RST / Your State, Province, or Country / Your BB Number. If you are a "
    "Home Station: RST / Your State, Province, or Country / Your Power Output'). THE "
    "NUMBER IS WHAT MAKES A BUMBLEBEE CONTACT, NOT THE /BB SUFFIX: 'Bumblebees will "
    "put a /BB after their Call, and/or will give you a BB Number', and the POTA/SOTA "
    "note settles it - 'As long as a Bumblebee Number is sent in the Outgoing "
    "Exchange, that will be a valid FOBB Bumblebee Contact.' Log the call as sent, /BB "
    "and all, and type the number you copy; a station that sends no number is a home "
    "station whatever its suffix. EVERY VALID CONTACT PAYS THE SAME - the printed "
    "formula is '[Total Score] = [Total Contacts] x [Number of Bumblebees] x 3', and "
    "'[Total Contacts] includes both Bumblebees and non-Bumblebees' - carried here as "
    "3 points per contact times the Bumblebee multiplier. THE MULTIPLIER IS BUMBLEBEES "
    "WORKED, COUNTED AGAIN ON EACH BAND: 'Working the same Bumblebee on a different "
    "band counts as an additional Contact and as an additional Bumblebee Worked.' THE "
    "S/P/C IS NOT A MULTIPLIER - no counting phrase attaches to it anywhere in the "
    "rules; it is exchanged and validated (the standard state and province tables plus "
    "DXCC prefixes, the C in S/P/C) and worth nothing, WHICH IS WHY THIS PARTY "
    "ENUMERATES NO LIST OF ITS OWN. THE MULTIPLIER NEVER DROPS BELOW ONE: '(Defaults "
    "to [Total Contacts] = 1 and [Number of Bumblebees] = 1)' - a log with contacts "
    "and no Bumblebee scores contacts x 1 x 3. DUPES: 'You can work each Bumblebee or "
    "Home Station once on each Band' - and with one legal mode, the app's band-x-mode "
    "dupe scope IS that rule, so nothing here is inferred. MODE IS CW ONLY, QRP: 'Open "
    "to all QRP CW operators', 'You run QRP CW - You can work Non-QRP Stations'; the "
    "power limits ('Participating FOBB Home Stations are expected to be running 5W QRP "
    "Maximum'; hunters over 5 W 'cannot Submit FOBB Results') are entry conditions, "
    "not categories, and never move a score here. BANDS 80/40/20/15/10, taken from the "
    "rules' TARGET SCENTS frequency list (3.566/7.036/14.036/21.036/28.036 '+/-'), the "
    "only bands the sponsor names. HOME vs BUMBLEBEE IS A REPORTING SPLIT on "
    "3830scores.com ('Select 'Home' or 'Bumblebee' so that you end up in the proper "
    "Results List'), not a scoring class - same formula, separate lists. THE FORMULA "
    "WAS ALSO VERIFIED AGAINST THE SPONSOR-DESIGNATED CALCULATOR: all 90 rows of the "
    "July 2026 claimed-scores table on 3830scores.com satisfy Contacts x Bumblebees x "
    "3 exactly - gen_fobb.py re-verifies from the banked table and refuses to build "
    "otherwise. THE ROSTER IS THE PREFILL SOURCE: the sponsor's self-serve Bumblebee "
    "number report at the stable URL ars-qrp.com/FOBB/Process_Get_All_By_Number.php "
    "(number, call, name, S/P/C), re-fetched through the call history machinery on the "
    "daily clock - 'Self-Serve Bumblebee Numbers Will Be Available Starting One Month "
    "Before the Event Date', and numbers issue until the event. Each bee is offered "
    "under both its bare call and its /BB form, since bees sign /BB on the air. Roster "
    "data is prefill only - Bumblebee credit comes from the number the station "
    "actually sends you, never from roster membership. verified: partial - one reading "
    "is unconfirmed by data, below, with what it costs. OPEN QUESTION 1: WHAT DOES A "
    "LOG WITH CONTACTS BUT NO BUMBLEBEES SCORE? The printed default says the "
    "multiplier is 1 (contacts x 3); the 3830 calculator's one observed zero row "
    "(K4UPG, 0 QSOs / 0 Bumblebees) computed 0, and no contacts-but-no-Bumblebees row "
    "has appeared to decide the case. This app follows the printed line - points x "
    "max(1, Bumblebees) - which also gives an empty log 0. If the sponsor's calculator "
    "instead zeroes a Bumblebee-less log, this app overstates it. KNOWN LIMITATION 1: "
    "THE CABRILLO CONTEST HEADER 'ARS-FOBB' IS THIS APP'S OWN INVENTION. The sponsor "
    "accepts no log files at all - results are self-reported totals on 3830scores.com "
    "('You will enter your [Total Contacts] that you made and the [Number of "
    "Bumblebees] that you worked') - and the WA7BNM registry has no FOBB entry "
    "(checked 2026-08-10), so the header has no recipient anywhere; the export exists "
    "for your own records. The score sidebar keeps both numbers the form wants on "
    "screen: valid contacts, and Bumblebees as the multiplier count. KNOWN LIMITATION "
    "2: BETWEEN EVENTS THE ROSTER PREFILLS THE PREVIOUS EVENT'S NUMBERS. 'Bumblebee "
    "Numbers are only valid for One FOBB Event' and are reissued each time, with "
    "self-serve opening a month before the event - so a number offered before the new "
    "event's roster opens can be a station's old one. Prefill is a hint: log the "
    "number the station sends."
)
assert "verified: partial" in NOTES
for marker in ["OPEN QUESTION 1", "KNOWN LIMITATION 1", "KNOWN LIMITATION 2"]:
    assert marker in NOTES, f"missing notes marker: {marker}"

party = {
    "schemaVersion": 1,
    "id": "fobb",
    "name": "ARS Flight of the Bumblebees",
    # App-invented: no sponsor value exists and the WA7BNM registry has no
    # entry (Article 1's fallback authority, checked 2026-08-10). Declared as
    # a cosmetic caveat — the header has no recipient anywhere.
    "cabrilloContest": "ARS-FOBB",
    "homeState": "NA",
    "countyAbbrLength": 2,
    "validBands": ["80m", "40m", "20m", "15m", "10m"],
    # The x3 of the printed formula, folded in so that points x multipliers
    # IS the sponsor's product. The member element decides Bumblebee-ness,
    # never the rate, so all three member rates are 3 as well.
    "points": {"phone": 3, "cw": 3, "digital": 3},
    "dupeScope": "bandMode",
    "multipliers": {
        "inState": {
            "classes": ["member"],
            "homeStateCountsViaCounty": False,
            "countScope": "perBand",
            "multiplierFloor": 1,
        },
        "outState": {
            "classes": ["member"],
            "homeStateCountsViaCounty": False,
            "countScope": "perBand",
            "multiplierFloor": 1,
        },
    },
    "bonuses": [],
    "dxStyle": "prefix",
    "acceptsDXToken": True,
    "allowedModes": ["cw"],
    "maxSimultaneousCounties": 1,
    "hasHomeRegion": False,
    "memberExchange": {
        "term": "Bumblebee number",
        "shortTerm": "BB #",
        "memberPlural": "Bumblebees",
        "memberPoints": 3,
        "qrpPoints": 3,
        "otherPoints": 3,
        # The event's own "5W QRP Maximum". Cosmetic here — the split feeds
        # the sidebar's counts and never a score, since all rates are equal.
        "qrpMaxWatts": {"phone": 5, "cw": 5, "digital": 5},
    },
    "schedule": [
        {"start": "2026-07-26T17:00:00Z", "end": "2026-07-26T21:00:00Z"},
        {"start": "2026-09-20T17:00:00Z", "end": "2026-09-20T21:00:00Z"},
    ],
    "counties": [],
    "notes": NOTES,
    # gen_callhistory.py verifies this block against its own roster of
    # special sources; gen_caveats.py appends the caveats. Run both after
    # this script (pipeline order).
    "callHistory": {
        "kind": "arsFobbRoster",
        "pageURL": "https://ars-qrp.com/FOBB/Process_Get_All_By_Number.php",
        "filePrefix": "FOBB",
        "token": "FOBB ROSTER",
    },
}

with open(OUT, "w") as f:
    json.dump(party, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"wrote {OUT.name}: formula verified on {len(rows)} rows, "
      f"roster {len(roster)} numbers ({len(roster) - 1} with a callsign)")
