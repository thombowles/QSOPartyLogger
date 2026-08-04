#!/usr/bin/env python3
"""Generate scqp.json from the SCQP Team's own 2026 rules PDF.

Sources (committed alongside this script, so the run is reproducible):
  scqp_rules_2026.txt — pdftotext -layout of
                        scqso.com/wp-content/uploads/2026/02/SCQPRULES2024_0126.pdf,
                        header "SOUTH CAROLINA QSO PARTY RULES (rev. 2.2.26)".
                        THE AUTHORITY, and self-contained: rules, the 46 counties,
                        the states, the provinces, and the sponsor's own Cabrillo
                        CONTEST value are all in this one document.
  scqp_page.txt       — scqso.com home page, whose banner confirms the date
  scqp_rules.md       — full rules research; all fetched 2026-07-26

Sponsor: the SCQP Team, scqso.com.

PROVENANCE NOTE: THE FILENAME LIES AND THE REVISION LINE DOES NOT. The PDF is
served as SCQPRULES2024_0126.pdf, which reads like a 2024 document; its own
header says "rev. 2.2.26" (2 February 2026) and it carries the 2026 dates and
bonus stations. The revision line governs. This is the mirror image of MNQP,
where the filename was honestly 2027 and the trap was that the sponsor no longer
published the year being built. Between them: never take a year from a URL.

THIS PARTY PAYS BY WHO WAS WORKED, NOT BY MODE - 2 points for a contact with an
SC station and 4 for one with a station outside SC, phone and CW and digital
alike. That is homeStationPoints + points, the MEQP shape, and the generator
asserts all four of the sponsor's point sentences.

Usage:  python3 gen_scqp.py        (run from docs/research/)
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "scqp.json")
RULES = os.path.join(HERE, "scqp_rules_2026.txt")
PAGE = os.path.join(HERE, "scqp_page.txt")


def read(path):
    s = open(path, encoding="utf-8").read()
    for a, b in [("’", "'"), ("‘", "'"), ("“", '"'), ("”", '"'),
                 ("–", "-"), ("—", "-"), ("’", "'")]:
        s = s.replace(a, b)
    return s


raw = read(RULES)
rules = re.sub(r"\s+", " ", raw)
page = re.sub(r"\s+", " ", read(PAGE))

# --- Counties: section 14.1, two columns of "Name    ABBR". Bounded at 14.2 so
# the two-letter state table that follows cannot leak in. ---
block = raw.split("14.1. South Carolina Counties")[1].split("14.2")[0]

counties = {}
for name, abbr in re.findall(r"([A-Z][A-Za-z' ]*?[a-z])\s{2,}([A-Z]{3,4})(?=\s|$)", block):
    name = " ".join(name.split())
    if abbr in counties and counties[abbr] != name:
        sys.exit(f"SCQP conflicting names for {abbr}: {counties[abbr]!r} vs {name!r}")
    counties[abbr] = name

assert len(counties) == 46, f"expected 46 SC counties, got {len(counties)}: {sorted(counties)}"
assert len(set(counties.values())) == 46, "SC county names not unique"
assert "46 South Carolina counties" in rules, "the sponsor's own county count changed"

# Mixed 3/4: LEE alone is three characters, and unlike ILQP the rules say nothing
# about it, so the assertion is the only thing that would catch a silent change.
lengths = sorted({len(a) for a in counties})
assert lengths == [3, 4], f"expected 3- and 4-character abbreviations, got {lengths}"
assert [a for a in counties if len(a) == 3] == ["LEE"], \
    "LEE should be the only 3-character code - re-read section 14.1"

for abbr, name in [
    ("CHOU", "Calhoun"),        # not CALH - and the SAME code ALQP uses for its Calhoun
    ("CHES", "Chester"), ("CHFD", "Chesterfield"), ("CKEE", "Cherokee"),  # none is CHER
    ("GVIL", "Greenville"), ("GRWD", "Greenwood"),                        # neither is GREE
    ("LNCS", "Lancaster"), ("LAUR", "Laurens"),                           # neither is LAN*
    ("MCOR", "McCormick"), ("ORNG", "Orangeburg"), ("SUMT", "Sumter"),
    ("UNIO", "Union"), ("CLRN", "Clarendon"), ("LEE", "Lee"),
    ("ABBE", "Abbeville"), ("BEAU", "Beaufort"), ("BERK", "Berkeley"),
    ("CHAR", "Charleston"), ("DORC", "Dorchester"), ("HORR", "Horry"),
    ("RICH", "Richland"), ("SPAR", "Spartanburg"), ("WILL", "Williamsburg"),
]:
    assert counties.get(abbr) == name, f"{abbr} should be {name!r}, got {counties.get(abbr)!r}"
for absent in ["CALH", "CHER", "GREE", "LANC", "MCCO"]:
    assert absent not in counties, f"{absent} is not an SCQP abbreviation"

# --- Bands: stated with the word "only", so nothing is derived here. Note the
# suggested-frequency table stops at 6 m; 2 m is in rule 3 and ships. ---
BANDS = ["160m", "80m", "40m", "20m", "15m", "10m", "6m", "2m"]
assert ("The SCQP shall be conducted on the 160, 80, 40, 20, 15, 10, 6 and 2 meter bands only"
        in rules), "the band sentence changed - re-read rule 3"
for excluded in ["60m", "30m", "17m", "12m", "1.25m", "70cm"]:
    assert excluded not in BANDS

# --- The rule sentences this file encodes. ---
for quote in [
    # 2 Contest period, with the sponsor's own length
    "Begins at 1500Z on the 4th Saturday in February and ends on the following Sunday at 0159Z",
    "(11 hours total)",
    # 5 Exchange
    "South Carolina Stations Signal report and county abbreviation",
    "Signal report and two-letter state abbreviation",
    "Note that Washington, D.C. is a multiplier for contest purposes",
    "Puerto Rico, USVI, Guam, and other US territories are considered DX",
    'Signal report and "DX" (not country)',
    # 9 Scoring - all four point sentences, because the pay-by-who-was-worked
    # shape is the easiest thing here to get backwards.
    "PHONE contact with other South Carolina stations shall count as two (2) points",
    "phone contact with stations outside of South Carolina shall count as four (4) points",
    "CW/ Digital contact with other South Carolina stations shall count as two (2)",
    "CW/DIGITAL contact with stations outside of South Carolina shall count as four (4) points",
    "PHONE contact with South Carolina stations shall count as two (2) points",
    "CW or Digital contact with South Carolina stations shall count as two (2) points",
    # Dupes, including the digital collapse this app already implements
    "Stations may be worked ONCE per MODE per BAND for QSO Points",
    "a FT8/4 and RTTY contact on the same band with the same station is considered a dupe",
    # 9.2 Multipliers
    "Multipliers are counted ONCE PER MODE PER BAND",
    "Each USA state including South Carolina and Washington, D.C.",
    "When logging other SC stations, enter the SC County as the exchange (not SC)",
    "DX contacts count for QSO points only",
    # 9.3 Bonus stations, and the scope sentence that needed a new case
    "Bonus Stations may be worked ONCE per BAND per MODE for bonus points",
    "only the first contact with WW4SF on 40m CW will qualify for Bonus Station points",
    "350 points - W4CAE",
    "250 points - WW4SF",
    "250 points - K4YTZ",
    # 9.4 / 9.5
    "Total QSO Points x Multipliers + Bonus Station Points",
    "Stations outside of South Carolina may not count contacts with non-South Carolina "
    "stations or DX stations for contest credit or multipliers",
    # 12 County lines: permitted, shape mandated, no limit given
    '"County-line" contacts must appear in the log as separate contacts',
    # 15 The sponsor prints its own Cabrillo CONTEST value
    "CONTEST: SC-QSO-PARTY",
]:
    assert quote in rules, f"the 2026 rules no longer contain: {quote!r}"

assert "SOUTH CAROLINA QSO PARTY RULES (rev. 2.2.26)" in rules, \
    "this is not rev 2.2.26 any more - re-verify every rule before shipping it"
assert "FEBRUARY 28, 2026 @ 1500Z" in page, \
    "the home page's stated date changed - re-derive the schedule"

# The sponsor caps county-line operation nowhere; assert that silence, so a
# future edition adding a limit fails here instead of passing unnoticed.
assert "county line" not in rules.lower().replace('"county-line"', ""), \
    "the rules now say something more about county lines - re-read rule 12"

# 9.2.2 gives SC Mobile/Expedition stations a multiplier per county ACTIVATED,
# now carried by `activatedCountyMultiplier`. Assert both halves of the rule are
# still printed, so a revision that drops the threshold or changes the scope
# fails here rather than scoring silently on last year's reading.
assert "Each SC county activated" in rules, \
    "the self-activation MULTIPLIER rule changed - re-read 9.2.2 against activatedCountyMultiplier"
assert "At least one (1) QSO must be made from a county" in rules, \
    "the activation threshold changed - minCount is no longer 1"
assert "will receive a multiplier (ONCE PER MODE PER BAND) for each county activated" in rules, \
    "the activation scope changed - countScope is no longer perBandMode"

scqp = {
    "schemaVersion": 1,
    "id": "scqp",
    "name": "South Carolina QSO Party",
    # Printed by the sponsor in its own Cabrillo example (rule 15), so this does
    # not rest on the WA7BNM registry.
    "cabrilloContest": "SC-QSO-PARTY",
    "homeState": "SC",
    # Mixed 3/4 - countyAbbrLengths reports both; this is the entry hint.
    "countyAbbrLength": 4,
    # "160, 80, 40, 20, 15, 10, 6 and 2 meter bands only" - the most explicit
    # band list of any party built this run.
    "validBands": BANDS,
    # PAY BY WHO WAS WORKED, NOT BY MODE. `points` is the table for a contact
    # whose received location is NOT an SC county: four points, every mode.
    "points": {"phone": 4, "cw": 4, "digital": 4},
    # ...and this is the table for a contact WITH an SC station, recognised the
    # only way the exchange allows - they sent a county. Two points, every mode.
    # An out-of-state entrant only ever logs SC counties (rule 9.5), so every one
    # of their contacts resolves here, which is exactly rules 9.1.3 and 9.1.4.
    "homeStationPoints": {"phone": 2, "cw": 2, "digital": 2},
    # "Stations may be worked ONCE per MODE per BAND ... For QSOs with SC
    # Mobiles, also per county."
    "dupeScope": "bandMode",
    "multipliers": {
        # "Each South Carolina county / Each USA state including South Carolina
        # and Washington, D.C. / Each Canadian Province/Territory. / DX contacts
        # count for QSO points only."
        "inState": {
            "classes": ["county", "state", "province"],
            # "Each USA state INCLUDING South Carolina ... When logging other SC
            # stations, enter the SC County as the exchange (NOT SC)." The
            # clearest statement of this rule anywhere in the repo: a multiplier
            # that exists, is reachable only through a county, and whose own
            # token is forbidden.
            "homeStateCountsViaCounty": True,
            "countScope": "perBandMode",
            # 9.2.2 item 3, for SC Mobile/Expedition stations: "Each SC county
            # activated. At least one (1) QSO must be made from a county in
            # order for it to count as activated."
            "activatedCountyMultiplier": {
                "minCount": 1,
                "countUnit": "qsos",
                # 6.2.3, stated outright and matching how SCQP counts every
                # other multiplier: "Expedition stations that operate from more
                # than one county will receive a multiplier (ONCE PER MODE PER
                # BAND) for each county activated."
                "countScope": "perBandMode",
                # 9.2.2's heading is "SC Mobile/Expedition Stations"; 6.2.1
                # defines Mobile Single as "A single mobile OR PORTABLE station
                # that operates from at least two (2) different South Carolina
                # counties". ROVER is excluded because SCQP has no such class.
                "categories": ["MOBILE", "PORTABLE", "EXPEDITION"],
                # THE ONLY ADDITIVE ONE OF THE FIVE. 9.2.2 lists "1. Each South
                # Carolina county" and "3. Each SC county activated" as separate
                # numbered multipliers, with no exclusion clause; and SCQP is
                # alone among the five in printing no county ceiling for the
                # activation to violate (its scope is per band per mode, so no
                # fixed maximum exists). TnQP and VAQP say "if not otherwise
                # worked" outright; NCQP's "164 total possible" and MOQP's "115
                # maximum" are exactly their entity lists and so say it by
                # arithmetic. Nothing here says either.
                "notOtherwiseWorked": False,
            },
        },
        # "Each SC county" - and nothing else.
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "perBandMode",
        },
    },
    # "Bonus Stations may be worked ONCE per BAND per MODE for bonus points."
    # perBandMode was added to WorkStationScope in its own preceding commit.
    "bonuses": [
        {"type": "workStation", "call": "W4CAE", "points": 350, "scope": "perBandMode"},
        {"type": "workStation", "call": "WW4SF", "points": 250, "scope": "perBandMode"},
        {"type": "workStation", "call": "K4YTZ", "points": 250, "scope": "perBandMode"},
    ],
    # 'Signal report and "DX" (not country)' - the sponsor spells out the reason
    # for the token style, and DX multiplies nothing.
    "dxStyle": "token",
    # Phone, CW and Digital are all legal; all WSJT/RTTY/PSK modes are one mode,
    # which is what ModeClass.digital already does.
    "allowedModes": ["phone", "cw", "digital"],
    # NO stateAliases: "Washington, D.C. is a multiplier for contest purposes",
    # counted separately from the 50 states. The opposite of VTQP and BCQP.
    "exchangeIncludesRST": True,
    # 9.5 Invalid Contacts, stated as its own numbered rule.
    "outStateWorksHomeStationsOnly": True,
    # "1500Z on the 4th Saturday in February ... the following Sunday at 0159Z.
    # (11 hours total)" - the stated length puts the end at 0200Z. 28 February
    # 2026 is that Saturday, and the home page's banner says so. The only
    # bundled party whose window crosses a month boundary.
    "schedule": [{"start": "2026-02-28T15:00:00Z", "end": "2026-03-01T02:00:00Z"}],
    "counties": [{"abbr": a, "name": n} for a, n in sorted(counties.items(), key=lambda kv: kv[1])],
    "hubSpots": {
        "tableURL": "http://qsopartyhub.com/scqp-table.php",
        "postURL": "http://qsopartyhub.com/scqp-spots.php",
    },
    "notes": (
        "verified: partial - rules from the SCQP Team's official 2026 PDF, header 'SOUTH CAROLINA "
        "QSO PARTY RULES (rev. 2.2.26)', read verbatim 2026-07-26, with the scqso.com home page "
        "confirming the date. The cleanest source of this run: ONE current-year document carries "
        "the rules, the 46 counties, the states, the provinces AND the sponsor's own Cabrillo "
        "CONTEST value, so nothing here rests on an archive, a secondary page or a registry. "
        "PROVENANCE NOTE: THE FILENAME LIES. The PDF is served as SCQPRULES2024_0126.pdf, which "
        "reads like a 2024 document; its own header says rev. 2.2.26 - 2 February 2026 - and it "
        "carries the 2026 dates and the 2026 bonus stations. The revision line governs. This is "
        "the mirror image of MNQP, whose filename was honestly 2027 while the trap was that the "
        "sponsor no longer published the year being built. Between them: never take a year from a "
        "URL. "
        "Eleven hours in one window, 1500Z Saturday 28 February to 0200Z Sunday 1 March 2026 - "
        "the sponsor prints the end as 0159Z but states '11 hours total', which settles it, and "
        "this is the ONLY bundled party whose window crosses a month boundary. "
        "POINTS ARE PAID BY WHO WAS WORKED, NOT BY MODE, and getting this backwards is the "
        "easiest mistake here: a contact with a South Carolina station is worth TWO points and a "
        "contact with a station outside South Carolina is worth FOUR, with phone, CW and digital "
        "all paying alike. Out-of-state entrants may only work SC stations at all, so every "
        "contact in an out-of-state log is worth two. Multipliers count ONCE PER MODE PER BAND on "
        "both sides. SC stations count the 46 counties, all 50 states INCLUDING South Carolina, "
        "Washington DC, and the 13 provinces and territories, for 110 per band per mode; everyone "
        "else counts the 46 SC counties, for a ceiling of 1,104 across eight bands and three "
        "modes. South Carolina itself is a multiplier reachable only through a county, and the "
        "sponsor says so about as plainly as it can be said - 'Each USA state including South "
        "Carolina' followed immediately by 'When logging other SC stations, enter the SC County "
        "as the exchange (not SC)'. WASHINGTON DC IS ITS OWN MULTIPLIER here and is deliberately "
        "not aliased to MD, unlike VTQP, BCQP and MDC; Puerto Rico, the USVI, Guam and the other "
        "US territories are DX. DX contacts earn points and no multiplier, and the sponsor asks "
        "for the literal token - 'DX' (not country). "
        "THREE BONUS STATIONS, each paying ONCE PER BAND PER MODE: W4CAE 350 points (Columbia "
        "Amateur Radio Club), WW4SF 250 (Swamp Fox Contest Group) and K4YTZ 250 (York County "
        "Amateur Radio Society), for 850 available in every one of the 24 band/mode slots. The "
        "sponsor's own example fixes the scope: 'You can work WW4SF/CHAR, WW4SF/GVIL, WW4SF/JASP "
        "and WW4SF/HORR on 40m CW, but only the first contact with WW4SF on 40m CW will qualify "
        "for Bonus Station points.' Working a bonus station again in a new county still pays QSO "
        "points and multipliers. No final-score multiplier of any kind - power selects the award "
        "category only. All digital modes are ONE mode, stated outright: 'a FT8/4 and RTTY "
        "contact on the same band with the same station is considered a dupe', which is how this "
        "app already behaves and is the exact opposite of VTQP. County-line contacts are "
        "permitted and must be logged as separate contacts, which is what this app produces. "
        "SC MOBILE, PORTABLE AND EXPEDITION STATIONS COUNT THE COUNTIES THEY ACTIVATE. Rule 9.2.2 "
        "item 3 gives them 'Each SC county activated. At least one (1) QSO must be made from a "
        "county in order for it to count as activated', and 6.2.3 scopes it: 'Expedition stations "
        "that operate from more than one county will receive a multiplier (ONCE PER MODE PER BAND) "
        "for each county activated.' The app now counts it, per band and per mode, alongside the "
        "counties worked; the matching bonus points are a separate rule this party does not have. "
        "PORTABLE is included because 6.2.1 defines Mobile Single as 'A single mobile or portable "
        "station that operates from at least two (2) different South Carolina counties'; ROVER is "
        "not, because SCQP has no such class. FIXED SC STATIONS AND EVERY OUT-OF-STATE ENTRANT ARE "
        "UNAFFECTED. "
        "Cabrillo CONTEST value SC-QSO-PARTY, printed by the sponsor in its own example log. Logs "
        "are due within 14 days and CABRILLO ONLY - the sponsor no longer accepts paper. Counties "
        "are 46 with MIXED 3- AND 4-CHARACTER abbreviations: LEE is the only three, and unlike "
        "ILQP the rules give no note about it. Calhoun is CHOU, not CALH - the same code Alabama "
        "uses for its own Calhoun. Three counties begin 'Ch' and none of them is CHER: Chester is "
        "CHES, Chesterfield CHFD and Cherokee CKEE. Greenville is GVIL and Greenwood GRWD; "
        "Lancaster is LNCS and Laurens LAUR. "
        "OPEN QUESTIONS (why this is partial): (1) The county-line limit. The rules permit "
        "county-line contacts and mandate only how they are logged - '\"County-line\" contacts "
        "must appear in the log as separate contacts' - but cap nothing, not two and not four. "
        "Shipped on this app's own maximum of four, which is a default rather than a sponsor's "
        "number; inventing a cap of two would be no better founded and would reject a legal "
        "entry. (2) WHETHER AN ACTIVATED COUNTY THAT WAS ALSO WORKED COUNTS ONCE OR TWICE. 9.2.2 "
        "lists '1. Each South Carolina county' and '3. Each SC county activated' as separate "
        "numbered multipliers, and unlike TnQP and VAQP adds no 'if not otherwise worked' clause; "
        "unlike NCQP and MOQP it also prints no county ceiling that double-counting would break. "
        "Shipped ADDITIVE, on that reading: an SC mobile that both sits in a county and works "
        "somebody there counts it twice in that band/mode slot. If the SCQP Team reads their own "
        "list as one set of counties rather than two, a mobile log claims one multiplier per such "
        "county too many. Confirm both with the SCQP Team via scqso.com before submitting a mobile "
        "or county-line log."
    ),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(scqp, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"scqp.json: {len(counties)} counties, lengths {lengths} (LEE is the only 3)")
print(f"  points: 2 with SC stations, 4 with everyone else - BY WHO, not by mode")
print(f"  multipliers: perBandMode both sides; in-state 46+51+13 = 110 per band/mode")
print(f"  homeStateCountsViaCounty: True - stated outright, the repo's clearest case")
print(f"  bands: {len(BANDS)} - stated with the word 'only'")
print(f"  bonuses: W4CAE 350 + WW4SF 250 + K4YTZ 250 = 850 per band/mode slot")
print(f"  schedule: 1 window, 11 h (1500Z 28 Feb -> 0200Z 1 Mar 2026), crosses a month")
