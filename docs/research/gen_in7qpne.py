#!/usr/bin/env python3
"""Generate Resources/Parties/in7qpne.json — the combined May-weekend entry.

Four QSO parties run on the first weekend of May and their sponsors coordinate
so that ONE log covers all of them. From the New England rules:

  "You may submit a single log that combines all of your QSOs from the New
   England, 7th Call Area, Indiana and Delaware QSO parties. QSOs not
   applicable to the NEQP will be ignored."

N1MM+ models this with a module named IN7QPNE, and its manual is explicit about
WHO it is for:

  "If you are an 'in-state' user of one of these QSO parties, select the
   appropriate state party option (7QP, IN, NEWE or DE). If you are
   'out-of-state' for all four contests this weekend, select the IN7QPNE
   option."

SO THE FOUR MEMBER PARTIES ARE NOT REPLACED. An Indiana station is in-state for
Indiana and out-of-state for the other three; its exchange and multipliers
differ from an out-of-region entrant's, so it must still pick Indiana. This
file adds a FIFTH option for the out-of-region case, exactly as N1MM does.

  (N1MM's own list also calls New England "NEWE" because "NE" is Nebraska -
   the same id collision this repo hit, resolved the same way.)

THE COUNTY LIST IS THE UNION OF THE FOUR, built from the bundled definitions
rather than re-fetched, so it cannot drift from them. Every county carries its
own state via County.state, which is what lets one log span sixteen states.

WHAT THIS PARTY CANNOT DO, and it is the headline limitation: PRODUCE A SCORE.
The four sponsors score differently - 7QP pays 2/3/4 by mode and counts
multipliers once, Indiana pays a flat 2 and counts per mode, New England pays
1/2 and counts once, Delaware pays 10/20/20 to out-of-state entrants and counts
per band. No single set of numbers is right for all four. N1MM has the same
problem and says so ("there may be minor scoring anomalies"); the real per-
contest scores come from the 4QP parsing tool at stateqsoparty.com, which
splits the combined Cabrillo. This definition therefore exists to LOG and to
EXPORT correctly, and its score is indicative only.

Run:  python3 docs/research/gen_in7qpne.py
"""

import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
PARTIES = os.path.join(HERE, "..", "..", "Resources", "Parties")
OUT = os.path.join(PARTIES, "in7qpne.json")

MEMBERS = ["inqp", "sevenqp", "newenglandqp", "deqp"]


def load(pid):
    with open(os.path.join(PARTIES, f"{pid}.json"), encoding="utf-8") as f:
        return json.load(f)


members = {pid: load(pid) for pid in MEMBERS}

# Every member must still exist and stay independently selectable - that is the
# whole point of N1MM's design and the thing this file must not break.
for pid, d in members.items():
    assert d["id"] == pid
    assert d["schedule"], f"{pid} needs a schedule to prove it shares the weekend"

# THEY MUST ALL BE THE SAME WEEKEND, or combining them is meaningless.
starts = {pid: d["schedule"][0]["start"][:10] for pid, d in members.items()}
assert set(starts.values()) == {"2026-05-02"}, starts

# ------------------------------------------------------------- the union
counties, home_states, seen = [], [], {}
for pid in MEMBERS:
    d = members[pid]
    for c in d["counties"]:
        # A single-state member's counties carry no state of their own; take the
        # party's. A multi-state member's already do.
        state = c.get("state") or d["homeState"]
        assert state, (pid, c)
        prev = seen.get(c["abbr"])
        assert prev is None, (
            f"code {c['abbr']} is claimed by both {prev} and {pid} - a combined "
            "log could not tell the two contests apart")
        seen[c["abbr"]] = pid
        counties.append({"abbr": c["abbr"], "name": c["name"], "state": state})
        if state not in home_states:
            home_states.append(state)

counties.sort(key=lambda c: c["abbr"])
home_states.sort()

expected = sum(len(members[p]["counties"]) for p in MEMBERS)
assert len(counties) == expected, (len(counties), expected)
assert len({c["abbr"] for c in counties}) == len(counties), "codes must stay unique"

# The sixteen: Indiana, Delaware, 7QP's eight and New England's six.
assert len(home_states) == 16, home_states
for s in ["IN", "DE", "AZ", "WA", "MA", "CT"]:
    assert s in home_states, s

# Bands: the union, so no member's QSO is refused for being on a band the
# others do not use.
bands = []
for b in ["160m", "80m", "40m", "20m", "15m", "10m", "6m", "2m", "1.25m", "70cm"]:
    if any(b in members[p]["validBands"] for p in MEMBERS):
        bands.append(b)

# Modes: the union too. Delaware and 7QP allow digital; Indiana and New England
# do not, and a digital QSO simply will not count for those two.
modes = ["phone", "cw", "digital"]

NOTES = (
    "verified: partial - a COMBINED ENTRY for the four QSO parties that share the first "
    "weekend of May, not a contest in its own right. The New England rules state the "
    "arrangement: 'You may submit a single log that combines all of your QSOs from the New "
    "England, 7th Call Area, Indiana and Delaware QSO parties. QSOs not applicable to the "
    "NEQP will be ignored.' N1MM+ models it with a module called IN7QPNE and this "
    "definition follows that design deliberately, including who it is for. USE THIS ONLY IF "
    "YOU ARE OUTSIDE ALL FOUR REGIONS. N1MM's manual is explicit: 'If you are an in-state "
    "user of one of these QSO parties, select the appropriate state party option (7QP, IN, "
    "NEWE or DE). If you are out-of-state for all four contests this weekend, select the "
    "IN7QPNE option.' An Indiana station is in-state for Indiana and out-of-state for the "
    "other three, so its exchange and multipliers differ and it must still choose Indiana - "
    "which is why all four member parties remain selectable here. KNOWN LIMITATION 1: THIS "
    "ENTRY CANNOT GIVE YOU A SCORE. The four sponsors score differently - the 7th Call Area "
    "pays 2, 3 and 4 points by mode and counts multipliers once; Indiana pays a flat 2 and "
    "counts per mode; New England pays 1 and 2 and counts once; Delaware pays 10, 20 and 20 "
    "to out-of-state entrants and counts per band - so no single set of numbers is right for "
    "all four at once. N1MM has the same problem and says so. The score shown here is "
    "INDICATIVE ONLY; submit the same Cabrillo file to all four sponsors and use the 4QP "
    "parsing tool at stateqsoparty.com to split it and get each contest's real claimed "
    "score. What this entry does do correctly is LOG and EXPORT: its county list is the "
    "union of all four, built from the bundled definitions so it cannot drift from them, "
    "and every county carries its own state so one log spans sixteen. KNOWN LIMITATION 2: "
    "the band and mode lists are unions too, so a QSO can be logged that one member contest "
    "would not count - a digital QSO counts for the 7th Call Area and Delaware but not for "
    "Indiana or New England, and 160 m counts for the 7th Call Area but for none of the "
    "others. The sponsors' own instruction covers this: QSOs not applicable to a contest are "
    "ignored by that contest."
)

party = {
    "schemaVersion": 1,
    "id": "in7qpne",
    "name": "Combined: Indiana + 7th Call Area + New England + Delaware",
    # No combined Cabrillo header exists; the same file goes to all four
    # sponsors, and N1MM writes the combined module's own name.
    "cabrilloContest": "IN7QPNE",
    "homeState": "IN",
    # The members stay selectable; this only groups them in the picker.
    "combines": MEMBERS,
    "homeStates": home_states,
    "inStateLabel": "the four-party region",
    "countyAbbrLength": 5,
    "validBands": bands,
    "points": {"phone": 1, "cw": 1, "digital": 1},
    "dupeScope": "bandMode",
    "multipliers": {
        "inState": {
            "classes": ["county", "state", "province"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
        },
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
        },
    },
    "bonuses": [],
    "dxStyle": "token",
    "allowedModes": modes,
    "maxSimultaneousCounties": 4,
    "exchangeIncludesRST": True,
    "outStateWorksHomeStationsOnly": True,
    "schedule": [
        {"start": "2026-05-02T13:00:00Z", "end": "2026-05-04T00:00:00Z"},
    ],
    "counties": counties,
    "hubSpots": None,
    "notes": NOTES,
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(party, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"in7qpne.json: {len(counties)} counties across {len(home_states)} states")
for pid in MEMBERS:
    print(f"    {pid:<14} {len(members[pid]['counties']):>3}")
print("  ALL FOUR MEMBER PARTIES REMAIN SELECTABLE - N1MM keeps them and so do we:")
print("    in-state operators need their own party's exchange and multipliers")
print(f"  bands are the union: {' '.join(bands)}")
print("  KNOWN LIMITATION 1: this entry cannot give a score - the four sponsors")
print("    score differently; the 4QP parsing tool does that from the same file")
print(f"  wrote {os.path.normpath(OUT)}")
