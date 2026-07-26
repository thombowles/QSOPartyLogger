#!/usr/bin/env python3
"""Generate bcqp.json from the Orca DX and Contest Club's own documents.

Sources (committed alongside this script, so the run is reproducible):
  bcqp_rules_2026.txt  — orcadxcc.org/bcqp_rules.html, footer "Updated: Feb. 5,
                         2026 VA7ST". THE AUTHORITY.
  bcqp_districts.txt   — orcadxcc.org/bcqp_districts.html, the official multiplier
                         list: 43 federal electoral districts, footer "Updated:
                         July 4, 2025 VA7ST"
  bcqp_faq.txt         — orcadxcc.org/bcqp_faq.html. NOT decoration: it is the ONLY
                         place the sponsor says DX earns no multiplier, that there
                         is no mobile/rover category, and that there is no power
                         multiplier. It also carries two worked scoring examples.
  bcqp_summary.txt     — the official score summary sheet PDF, a third listing of
                         the multipliers
  bcqp_rules.md        — full rules research; all fetched 2026-07-26

THE FIRST NON-US PARTY IN THIS REPO. British Columbia has no counties, so the
county class carries FEDERAL ELECTORAL DISTRICTS. That needs no schema change -
homeState "BC" is correct for the UI labels, the ADIF state field and the
Cabrillo in-state location - but it does need `provinces` overridden; see below.

THE DISTRICT LIST IS NEW. "A redrawing of the electoral map for the October 2025
election gave BC 43 federal electoral districts", and the sponsor says they "came
into effect in 2025 and are used for the 2026 BCQP". Any older BCQP district list
is wrong for 2026 - the sponsor's own Cabrillo sample still shows a retired code
(NWB), which is exactly the trap.

Usage:  python3 gen_bcqp.py        (run from docs/research/)
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "bcqp.json")
RULES = os.path.join(HERE, "bcqp_rules_2026.txt")
DISTRICTS = os.path.join(HERE, "bcqp_districts.txt")
FAQ = os.path.join(HERE, "bcqp_faq.txt")
SUMMARY = os.path.join(HERE, "bcqp_summary.txt")


def read(path):
    s = open(path, encoding="utf-8").read()
    for a, b in [("’", "'"), ("‘", "'"), ("“", '"'), ("”", '"'),
                 ("–", "-"), ("—", "-"), ("", "'")]:
        s = s.replace(a, b)
    return s


rules = re.sub(r"\s+", " ", read(RULES))
faq = re.sub(r"\s+", " ", read(FAQ))
summary = re.sub(r"\s+", " ", read(SUMMARY))
districts_txt = read(DISTRICTS)

# --- Districts: the multiplier page lists them one per line as "ABC Name". The
# US-state table that follows is two-letter, so bound the parse anyway. ---
block = districts_txt.split("View a printer-friendly PDF of the multipliers")[-1]
block = block.split("United States Abbreviations")[0]

districts = {}
for abbr, name in re.findall(r"^([A-Z]{3}) ([A-Z][A-Za-z'\- ]+)$", block, re.M):
    name = name.strip()
    if abbr in districts and districts[abbr] != name:
        sys.exit(f"BCQP conflicting names for {abbr}: {districts[abbr]!r} vs {name!r}")
    districts[abbr] = name

assert len(districts) == 43, \
    f"expected 43 BC electoral districts, got {len(districts)}: {sorted(districts)}"
assert len(set(districts.values())) == 43, "BC district names not unique"
assert {len(a) for a in districts} == {3}, "BC district codes are uniformly 3 letters"

# The sponsor states the count in three places; assert all three, because the
# 2025 redistribution changed it and a stale list is the obvious failure mode.
assert "43 BC Federal Electoral Districts" in rules
assert "43 British Columbia electoral districts" in rules
assert "gave BC 43 federal electoral districts" in faq
assert "BC Districts (43 max)" in summary
assert "came into effect in 2025 and are used for the 2026 BCQP" in districts_txt, \
    "the sponsor's note pinning this list to 2026 is gone - re-verify the districts"

# Spot checks. CKS/KSC are near-anagrams that both end in "Rockies"; the three
# spellings below are the sponsor's own and ship as printed. See bcqp_rules.md 13.
for abbr, name in [
    ("CKS", "Columbia-Kootenay-Southern Rockies"),
    ("KSC", "Kamloops-Shuwswap-Central Rockies"),   # sponsor's spelling of Shuswap
    ("KTN", "Kamloops-Thompson-Nicola"),
    ("SSW", "Similkameen-South Okangan-West Kootenay"),  # sponsor's spelling of Okanagan
    ("RCM", "Richmond Center-Marpole"),             # US spelling, sponsor's own
    ("SUC", "Surrey Centre"),                       # ...and Centre here, inconsistently
    ("SUN", "Surrey Newton"), ("SWR", "South Surrey-White Rock"),
    ("VAC", "Vancouver Centre"), ("VAE", "Vancouver East"),
    ("VAG", "Vancouver Granville"), ("VAK", "Vancouver Kingsway"),
    ("VAQ", "Vancouver Quadra"), ("VIC", "Victoria"),
    ("VSB", "Vancouver Fraserview-South Burnaby"),
    ("BUC", "Burnaby Central"), ("BNS", "Burnaby North-Seymour"),
    ("DEL", "Delta"), ("CML", "Cowichan-Malahat-Langford"),
    ("CPG", "Cariboo-Prince George"), ("PPN", "Prince George-Peace River-Northern Rockies"),
]:
    assert districts.get(abbr) == name, f"{abbr} should be {name!r}, got {districts.get(abbr)!r}"
for absent in ["VAN", "BUR", "NWB", "KAM", "SUR"]:
    assert absent not in districts, \
        f"{absent} is not a 2026 district code - NWB in particular is the RETIRED code " \
        "the sponsor's own Cabrillo sample still shows"

# --- Bands: "160m to 10m, no WARC bands", confirmed by the suggested-frequency
# table, which carries exactly one CW and one phone frequency per band. ---
BANDS = ["160m", "80m", "40m", "20m", "15m", "10m"]
assert "Contest bands: 160m to 10m, no WARC bands" in rules
assert "Contest modes: Phone and CW" in rules
assert "CW - 1815, 3535, 7035, 14035, 21035, 28035 kHz" in rules, \
    "the CW suggested-frequency row changed - re-check the band list against it"
assert "Phone - 1845, 3850, 7230, 14250, 21300, 28490 kHz" in rules
for excluded in ["60m", "30m", "17m", "12m", "6m", "2m", "1.25m", "70cm"]:
    assert excluded not in BANDS, f"{excluded} is not a BCQP band - HF only"

# --- The rule sentences this file encodes. ---
for quote in [
    # Object / scope of credit
    "Stations outside British Columbia to work only BC stations",
    "Stations in BC to work anyone, anywhere",
    # Contest period, and the sponsor's own total
    "starts Saturday, Feb. 7, 2026 at 1600z, and runs for 12 hours until 0359z Sunday Feb. 8, 2026",
    "runs for eight hours until 2359z Sunday Feb. 8, 2026",
    "Participants may operate all 20 hours of the contest",
    # Exchange
    "British Columbia stations send: RS(T) and District (three letter abbreviation)",
    "Non-British Columbia stations send: RS(T) and state/province/territory or DX",
    "Hawaii and Alaska should be included under state, not DX",
    # Points
    "2 points for Phone QSOs",
    "4 points for CW QSOs",
    "The same station may be worked for QSO points on each band on CW and Phone",
    # Multipliers
    "Maryland and DC are lumped together as MD",
    "Multipliers can be counted only once per band and mode",
    "For non-BC stations: 43 British Columbia electoral districts",
    # Bonus and scoring
    "Any QSO with the Orca DXCC station, VA7ODX, will be worth an additional 20 points",
    "Total = (QSO points from all bands X total location multipliers) plus bonus station points",
    # Cabrillo: the SPONSOR prints its own CONTEST value, so WA7BNM is not needed
    "CONTEST: BC-QSO-PARTY",
]:
    assert quote in rules, f"the 2026 rules no longer contain: {quote!r}"

# The three rules that exist ONLY in the FAQ. Each would be a scoring error if
# missed: a phantom DX multiplier, a phantom power multiplier, and a county-line
# allowance the sponsor never grants.
for quote in [
    "DX contacts are worth QSO points but do not provide a multiplier",
    "There is no power multiple",
    "Is there a mobile or rover category? No",
    "Each QSO with VA7ODX will add 20 points to your score AFTER all other calculations",
    "The first Saturday and Sunday of February",
]:
    assert quote in faq, f"the FAQ no longer contains: {quote!r}"

# The FAQ's two worked examples pin the scoring formula arithmetically.
assert "((100 x 4) x 33) + (5 x 20) = 13,300" in faq
assert (100 * 4) * 33 + (5 * 20) == 13300
assert "(((25 x 4) + (25 x 2)) x 50) + (6 x 20)" in faq
assert ((25 * 4) + (25 * 2)) * 50 + (6 * 20) == 7620

assert "Updated: Feb. 5, 2026" in rules, \
    "the rules page is no longer the 2026 revision - re-verify before shipping"

# --- Provinces: the standard 13 LESS BC. A BC station always sends a district,
# so the token BC can never be received; leaving the default in place would make
# it loggable, because validOutStateTokens unions `provinces` in AFTER
# subtracting excludedStateTokens. See bcqp_rules.md section 6. ---
ALL_13 = ["NL", "PE", "NS", "NB", "QC", "ON", "MB", "SK", "AB", "BC", "YT", "NT", "NU"]
assert "NL, PE, NS, NB, QC, ON, MB, SK, AB, BC, YT, NT, NU" in rules, \
    "the sponsor's province enumeration changed - re-read it before dropping BC"
PROVINCES = [p for p in ALL_13 if p != "BC"]
assert len(PROVINCES) == 12 and "BC" not in PROVINCES

bcqp = {
    "schemaVersion": 1,
    "id": "bcqp",
    "name": "British Columbia QSO Party",
    # The SPONSOR prints this in its own Cabrillo sample, so unlike almost every
    # other bundled party this does not rest on the WA7BNM registry.
    "cabrilloContest": "BC-QSO-PARTY",
    # Not a US state - BC is a province, and the schema only requires two
    # characters. Drives the UI labels, the ADIF state field and the Cabrillo
    # in-state location, all of which "BC" is correct for.
    "homeState": "BC",
    "countyAbbrLength": 3,
    # "Contest bands: 160m to 10m, no WARC bands." HF only, no VHF/UHF.
    "validBands": BANDS,
    # "2 points for Phone QSOs / 4 points for CW QSOs" - the highest CW value of
    # any bundled party. Digital is not a legal mode; the value is set equal to CW
    # so a future edition adding digital cannot inherit a guess.
    "points": {"phone": 2, "cw": 4, "digital": 4},
    # "The same station may be worked for QSO points on each band on CW and Phone."
    "dupeScope": "bandMode",
    "multipliers": {
        # "43 BC federal electoral districts, Canadian provinces and U.S. states."
        # NOTE .dx is DELIBERATELY ABSENT - the FAQ: "DX contacts are worth QSO
        # points but do not provide a multiplier."
        "inState": {
            "classes": ["county", "state", "province"],
            # Three sponsor documents list BC among the countable provinces, but
            # no BC station can ever send the token BC - the exchange from BC is
            # always a district. Shipped as NOT counting; open question.
            "homeStateCountsViaCounty": False,
            # "Multipliers can be counted only once per band and mode."
            "countScope": "perBandMode",
        },
        # "For non-BC stations: 43 British Columbia electoral districts."
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "perBandMode",
        },
    },
    # "Any QSO with the Orca DXCC station, VA7ODX, will be worth an additional 20
    # points" - and the FAQ's "Each QSO ... 5 QSOs ... + (5 x 20)" fixes the scope.
    "bonuses": [
        {"type": "workStation", "call": "VA7ODX", "points": 20, "scope": "perQSO"},
    ],
    # "state/province/territory or DX" - a literal token, and one that multiplies
    # nothing, so there is nothing to tell DXCC entities apart for.
    "dxStyle": "token",
    # "Contest modes: Phone and CW"
    "allowedModes": ["phone", "cw"],
    # No mobile or rover category exists at all (FAQ), so no station may claim
    # two districts.
    "maxSimultaneousCounties": 1,
    # "Maryland and DC are lumped together as MD." The sponsor's own US-state
    # table has 50 rows and no DC row.
    "stateAliases": {"DC": "MD"},
    # The standard 13 LESS BC - see the note above PROVINCES.
    "provinces": PROVINCES,
    # "British Columbia stations send: RS(T) and District"
    "exchangeIncludesRST": True,
    # "Stations outside British Columbia to work only BC stations"
    "outStateWorksHomeStationsOnly": True,
    # Two segments, 12 h + 8 h. The printed 0359z/2359z are last-minute notation;
    # the sponsor states the lengths and then the total, "all 20 hours", which
    # only 1600->0400 and 1600->2400 satisfy.
    "schedule": [
        {"start": "2026-02-07T16:00:00Z", "end": "2026-02-08T04:00:00Z"},
        {"start": "2026-02-08T16:00:00Z", "end": "2026-02-09T00:00:00Z"},
    ],
    "counties": [{"abbr": a, "name": n} for a, n in sorted(districts.items(), key=lambda kv: kv[1])],
    "hubSpots": {
        "tableURL": "http://qsopartyhub.com/bcqp-table.php",
        "postURL": "http://qsopartyhub.com/bcqp-spots.php",
    },
    "notes": (
        "verified: partial - rules from the Orca DX and Contest Club's own 2026 page, "
        "http://www.orcadxcc.org/bcqp_rules.html (footer 'Updated: Feb. 5, 2026 VA7ST'), with the "
        "official multiplier list, the FAQ and the score summary sheet PDF, all read verbatim "
        "2026-07-26. All four sponsor documents are current and agree; nothing here rests on an "
        "archive or a stale year. THE FIRST NON-US PARTY IN THIS APP. "
        "BRITISH COLUMBIA HAS NO COUNTIES, so the county field carries the 43 FEDERAL ELECTORAL "
        "DISTRICTS instead - 'not demarcated by signposts and not part of any street addresses', "
        "as the sponsor puts it. THIS DISTRICT LIST IS NEW: a redrawing of the electoral map for "
        "the October 2025 election gave BC 43 districts, and the sponsor says they 'came into "
        "effect in 2025 and are used for the 2026 BCQP'. Any older BCQP district list is WRONG for "
        "2026 - the sponsor's own Cabrillo sample on the rules page still shows the retired code "
        "NWB, and the generator asserts NWB is absent. "
        "Twenty hours in TWO segments with a gap you may not operate in: 1600Z Saturday 7 February "
        "to 0400Z Sunday, then 1600Z Sunday to 2400Z. The page prints the ends as 0359z and 2359z, "
        "but states the lengths as 12 and eight hours and then the total outright - 'Participants "
        "may operate all 20 hours of the contest' - which only the full hours satisfy. Note a "
        "stale-date typo in the second segment's sentence, which begins 'Sunday, Feb. 2, 2025'; "
        "the same sentence ends '2359z Sunday Feb. 8, 2026' and every other statement agrees on "
        "8 February 2026. "
        "PHONE 2 POINTS, CW 4 - the highest CW value of any bundled party. Multipliers count ONCE "
        "PER BAND AND MODE, on both sides, which the sponsor illustrates: 'A mixed mode op can "
        "count DEL on CW 20 and Phone 20 as well as CW 40 and Phone 40'. BC stations count the 43 "
        "districts, Canadian provinces and US states; everyone else counts the 43 districts only, "
        "for a ceiling of 516 across six bands and two modes. 'Maryland and DC are lumped together "
        "as MD', and the sponsor's own state table has 50 rows with no DC row at all. Alaska and "
        "Hawaii are STATES here, not DX - the sponsor says so twice. VA7ODX pays 20 points per "
        "QSO, added after multiplying, which the FAQ's worked examples confirm exactly. "
        "DX CONTACTS EARN POINTS BUT NO MULTIPLIER. That rule appears ONLY in the FAQ, not in the "
        "rules page, and missing it would give a BC entrant a phantom multiplier on every band and "
        "mode. Two more rules live only in the FAQ: 'There is no power multiple', so no final-score "
        "multiplier ships; and there is NO MOBILE OR ROVER CATEGORY at all, because February "
        "weather and the size of the northern districts make it impractical - so no station may "
        "claim two districts and a district-line entry is rejected, as in ALQP and MNQP. "
        "Self-spotting is prohibited in all classes, though packet and Skimmer are allowed - worth "
        "knowing, since this app can post spots to the hub. "
        "KNOWN LIMITATION - ADIF EXPORT WRITES 'BC,<district>' IN THE CNTY FIELD. That is ADIF's "
        "State,County shape for a US secondary administrative subdivision, and BC electoral "
        "districts are neither counties nor in ADIF's enumeration, so the field is well formed but "
        "not meaningful to an ADIF consumer. CABRILLO IS UNAFFECTED - it carries the raw exchange "
        "token, and Cabrillo is the format the sponsor actually requires. "
        "Cabrillo CONTEST value BC-QSO-PARTY, printed by the SPONSOR in its own sample log, so "
        "unlike most bundled parties this does not rest on the WA7BNM registry. Logs are due "
        "within 14 days at http://bcqp.contesting.com/bcqpsubmitlog.php. District codes are 43 "
        "with uniform 3 letters, and the worst trap is a near-anagram: CKS is "
        "Columbia-Kootenay-Southern Rockies while KSC is Kamloops-Shuwswap-Central Rockies, both "
        "ending in Rockies. There are two Kamloops districts (KSC, KTN), three Surreys (SUC, SUN, "
        "SWR), two Burnabys (BUC, BNS - neither is BUR) and seven Vancouver-area codes, of which "
        "none is VAN. Three sponsor spellings ship as printed and are asserted by the generator: "
        "'Shuwswap' for Shuswap (KSC), 'Okangan' for Okanagan (SSW), and 'Richmond Center' with "
        "the US spelling (RCM) even though the same list writes 'Surrey Centre'. "
        "OPEN QUESTIONS (why this is partial): (1) Whether British Columbia itself counts as a "
        "province multiplier for BC entrants. THREE sponsor documents list BC among the countable "
        "provinces - the rules' enumeration, the summary sheet's bracketed list and the FAQ - but "
        "NO BC STATION CAN EVER SEND THE TOKEN 'BC', because the exchange from British Columbia is "
        "always a district, and the FAQ tells an operator who does not know their district to look "
        "it up rather than fall back to the province. Shipped as NOT counting, on the reading that "
        "the enumerations are reference boilerplate listing the standard 13 with their prefixes; "
        "BC is accordingly not a loggable token here either. If that reading is wrong a BC entrant "
        "is one multiplier short per band per mode. (2) The ADIF county-field limitation above. "
        "Confirm (1) with the Contest Coordinator at va7bec@gmail.com before submitting a log."
    ),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(bcqp, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"bcqp.json: {len(districts)} federal electoral districts (2025 redistribution)")
print(f"  points: phone 2, CW 4 (highest in repo)")
print(f"  multipliers: perBandMode both sides; DX earns NO multiplier (FAQ only)")
print(f"  provinces: {len(PROVINCES)} - the standard 13 LESS BC, which is unsendable here")
print(f"  bands: {len(BANDS)} - HF only, 160-10 m no WARC")
print(f"  district lines: FORBIDDEN (no mobile/rover category exists)")
print(f"  bonus: VA7ODX +20 per QSO, added after multiplying")
print(f"  schedule: 2 windows, 12 h + 8 h = the sponsor's stated 20 h")
