#!/usr/bin/env python3
"""Generate meqp.json from the sponsor's own rules text.

Nothing here is hand-typed: the 16 counties come out of the official PDF's
county sentence, and the 14 Canadian province tokens out of the rules page's
multiplier note (constitution Article 2).

Sources (committed alongside this script, so the run is reproducible):
  meqp_rules_2026.txt — pdftotext -layout of the official rules PDF, title block
                        "Maine QSO Party / 2026 Official Rules"
                        http://www.ws1sm.com/Images/Maine_QSO_Party_Rules.pdf
  meqp_page.txt       — text of http://www.ws1sm.com/MEQP.html
  meqp_rules.md       — full rules research; both sources fetched 2026-07-24

The two sources are not redundant. The province list and the DC/MD note appear
ONLY on the web page; the mobile/county-line rule appears ONLY in the PDF.

Sponsor: Wireless Society of Southern Maine (WS1SM), http://www.ws1sm.com/MEQP.html

Usage:  python3 gen_meqp.py        (run from docs/research/)
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "meqp.json")
PDF_TXT = os.path.join(HERE, "meqp_rules_2026.txt")
PAGE_TXT = os.path.join(HERE, "meqp_page.txt")


def flat(path):
    """The file as one line, curly quotes normalised — the sponsor's sentences
    wrap mid-list in both sources, so nothing can be matched line by line."""
    text = open(path, encoding="utf-8").read()
    text = text.replace("’", "'").replace("“", '"').replace("”", '"')
    return re.sub(r"\s+", " ", text)


pdf = flat(PDF_TXT)
page = flat(PAGE_TXT)

# --- Counties: "The counties are: Androscoggin (AND), Aroostook (ARO), ..." ---
m = re.search(r"The counties are:(.*?)\.\s", pdf)
if not m:
    sys.exit("county sentence not found in meqp_rules_2026.txt")
counties = {}
for name, abbr in re.findall(r"([A-Za-z]+)\s*\(([A-Z]{2,4})\)", m.group(1)):
    if abbr in counties:
        sys.exit(f"MEQP duplicate abbreviation: {abbr}")
    counties[abbr] = name

assert len(counties) == 16, f"expected 16 ME counties, got {len(counties)}: {sorted(counties)}"
assert len(set(counties.values())) == 16, "ME county names not unique"
assert all(len(a) == 3 for a in counties), "all MEQP abbreviations are 3 letters"
# The rules state the count themselves: "Maine counties (16)" and "Sixteen in
# total". Both must agree with what was parsed.
assert "Maine counties (16)" in pdf and "Sixteen in total" in pdf, \
    "the rules' own county count is missing — re-read the source"

# Spot checks on the irregular ones (Article 18). Checking KEN->Kennebec would
# prove nothing; these are the abbreviations that are not the first 3 letters.
for abbr, name in [
    ("CBL", "Cumberland"),   # not CUM
    ("PSQ", "Piscataquis"),  # not PIS
    ("SAG", "Sagadahoc"),
    ("ARO", "Aroostook"),
    ("KNO", "Knox"),
    ("WAS", "Washington"),
]:
    assert counties.get(abbr) == name, f"{abbr} should be {name}, got {counties.get(abbr)!r}"

# --- Provinces: web page only, 14 tokens, NF and LB counted separately ---
m = re.search(
    r"For Canadian\s*Provinces, use the following abbreviations:([^.]*)\.", page
)
if not m:
    sys.exit("Canadian province list not found in meqp_page.txt")
provinces = [p.strip() for p in m.group(1).split(",") if p.strip()]

assert len(provinces) == 14, f"expected 14 province tokens, got {len(provinces)}: {provinces}"
assert len(set(provinces)) == 14, "province tokens not unique"
# The rules state the count themselves, twice over.
assert "Canadian Provinces (14)" in pdf, "the rules' own province count is missing"
# "Please note that Newfoundland (NF) and Labrador (LB) will count seperately."
# [sic] — so the repo default NL is NOT valid here, and NF+LB are two mults.
assert "NF" in provinces and "LB" in provinces, "NF and LB count separately in MEQP"
assert "NL" not in provinces, "MEQP splits Newfoundland and Labrador; NL is not a MEQP token"
assert "will count seperately" in page, "the split-Labrador note is missing — re-read the source"

# --- Bands: "160, 80, 40, 20, 15, and 10" — six of them, per the rules' own
# repeated phrase "each of the six contest bands". ---
BANDS = ["160m", "80m", "40m", "20m", "15m", "10m"]
assert "160, 80, 40, 20, 15, and 10" in pdf, "band list sentence changed — re-read the source"
assert pdf.count("six contest bands") >= 2, "the rules' own band count is missing"
assert len(BANDS) == 6

# --- Modes: "CW and phone (SSB, FM, AM)" and "the two modes" — no digital. ---
assert "CW and phone (SSB, FM, AM)" in pdf, "mode list changed — re-read the source"
assert "two modes" in pdf, "the rules' own mode count is missing"

# --- The rule sentences this file encodes. If the sponsor edits the PDF in
# place (they publish no revision markers), these fail rather than drift. ---
for quote in [
    "Contacts with stations in Maine are worth 2 points",
    "Contacts with stations outside Maine are\nworth 1 point".replace("\n", " "),
    "Multipliers are the same for all participants",
    "Each multiplier may be counted once\non each mode on each of the six contest bands".replace("\n", " "),
    "County line QSO's should be logged as two\nseparate QSO's".replace("\n", " "),
    "The entry deadline for logs is October 12, 2026",
]:
    assert quote in pdf, f"rules text no longer contains: {quote!r}"
assert "DC and MD will be counted as a single multiplier" in page
assert "all QSOs made during the contest period that meet MEQP criteria are eligible for points" in page

meqp = {
    "schemaVersion": 1,
    "id": "meqp",
    "name": "Maine QSO Party",
    # Sponsor prints no CONTEST: token; WA7BNM registry (Article 1 exception).
    "cabrilloContest": "ME-QSO-PARTY",
    "homeState": "ME",
    "countyAbbrLength": 3,
    # "Bands and Modes: 160, 80, 40, 20, 15, and 10, CW and phone (SSB, FM, AM)."
    "validBands": BANDS,
    # "Contacts with stations outside Maine are worth 1 point." Mode is
    # irrelevant in MEQP — the worked station's location decides.
    "points": {"phone": 1, "cw": 1, "digital": 1},
    # "Contacts with stations in Maine are worth 2 points."
    "homeStationPoints": {"phone": 2, "cw": 2, "digital": 2},
    # "You may work any station once on each of the two modes, on each of the
    # six contest bands."
    "dupeScope": "bandMode",
    # "Multipliers are the same for all participants: Use Maine counties (16),
    # States (50), Canadian Provinces (14), and DXCC countries as multipliers."
    # "Each multiplier may be counted once on each mode on each of the six
    # contest bands." Symmetric — Article 16's exception, quoted not assumed.
    "multipliers": {
        "inState": {
            "classes": ["county", "state", "province", "dx"],
            # Never stated that a Maine county also yields the ME state mult,
            # and ME stations send a county so the token ME is never received.
            # See meqp_rules.md §6 — the single open question.
            "homeStateCountsViaCounty": False,
            "countScope": "perBandMode",
            # "and DXCC countries as multipliers" — counted one by one, and
            # uncapped, for both sides. The exchange is the literal token
            # "DX", so the entity comes from the worked callsign.
            "dxCountsEntities": True,
        },
        "outState": {
            "classes": ["county", "state", "province", "dx"],
            "homeStateCountsViaCounty": False,
            "countScope": "perBandMode",
            "dxCountsEntities": True,
        },
    },
    # No bonus station, no bonus points, in either source.
    "bonuses": [],
    # 'DX stations send signal report and "DX."'
    "dxStyle": "token",
    # "CW and phone (SSB, FM, AM)" — no digital category exists.
    "allowedModes": ["phone", "cw"],
    # "County line QSO's should be logged as two separate QSO's." Two-county
    # operation is allowed but is two QSOs, not one two-county QSO.
    "maxSimultaneousCounties": 1,
    # "For U.S. states, DC and MD will be counted as a single multiplier."
    "stateAliases": {"DC": "MD"},
    # 14 tokens, NF and LB separately — parsed above, never typed.
    "provinces": provinces,
    # "Stations in Maine send signal report and county."
    "exchangeIncludesRST": True,
    # "all QSOs made during the contest period that meet MEQP criteria are
    # eligible for points—not just contacts with Maine stations."
    "outStateWorksHomeStationsOnly": False,
    # "1200 UTC Saturday, September 26 to 1200 UTC Sunday, September 27, 2026"
    # (rules page). The PDF's contest-period line misprints the year as 2025;
    # see meqp_rules.md §2 — its own title block, its October 12 2026 deadline,
    # the "last full weekend in September" formula and the fact that 2025-09-26
    # was a Friday all settle it on 2026.
    "schedule": [{"start": "2026-09-26T12:00:00Z", "end": "2026-09-27T12:00:00Z"}],
    "counties": [{"abbr": a, "name": n} for a, n in sorted(counties.items(), key=lambda kv: kv[1])],
    "notes": (
        "verified: partial — rules from the Wireless Society of Southern Maine's official PDF "
        "(ws1sm.com/Images/Maine_QSO_Party_Rules.pdf, title block '2026 Official Rules') and "
        "rules page (ws1sm.com/MEQP.html), both read verbatim 2026-07-24. The two are not "
        "redundant: the Canadian province list and the DC/MD note appear only on the page, the "
        "mobile/county-line rule only in the PDF. "
        "POINTS ARE BY LOCATION, NOT MODE: 'Contacts with stations in Maine are worth 2 points. "
        "Contacts with stations outside Maine are worth 1 point.' CW and phone pay alike. "
        "MULTIPLIERS ARE SYMMETRIC — 'Multipliers are the same for all participants: Use Maine "
        "counties (16), States (50), Canadian Provinces (14), and DXCC countries as multipliers' "
        "— and are counted ONCE PER BAND PER MODE: 'Each multiplier may be counted once on each "
        "mode on each of the six contest bands.' That scope is confirmed by the sponsor's own "
        "published results: the 2024 winner scored 494,834 points on 1,212 QSOs, which factors "
        "only as 1,234 QSO points x 401 multipliers, and 401 is unreachable from a pool of 16 "
        "counties + 50 states + 14 provinces + DXCC counted once or per mode. Those same numbers "
        "confirm the points rule (1,234 points from 1,212 QSOs = exactly 22 two-point Maine "
        "contacts) and that a non-Maine contact scores at all. "
        "OUT-OF-STATE ENTRANTS SCORE NON-MAINE QSOs, which is unusual and explicit: 'all QSOs "
        "made during the contest period that meet MEQP criteria are eligible for points-not just "
        "contacts with Maine stations.' "
        "CANADA IS 14 TOKENS, NOT THE USUAL 13: 'Please note that Newfoundland (NF) and Labrador "
        "(LB) will count seperately' [sic], so NF and LB are two multipliers and the usual NL is "
        "NOT a valid MEQP token. DC counts as MD. "
        "DXCC ENTITIES COUNT ONE BY ONE as of 2026-08-01, which is what the rules ask and what "
        "this app could not do before. They are multipliers for every entrant with no cap, but "
        "the exchange is 'DX stations send signal report and \"DX\"' — every DX station sends the "
        "same literal token, so DX used to collapse to a SINGLE multiplier per band/mode and "
        "anyone working several DX countries saw a count low by one per extra entity per "
        "band/mode slot. That was the largest single scoring gap in the catalogue: NHQP had the "
        "same cause but affected in-state entrants only and capped at 10, while MEQP gives DXCC "
        "to everyone, uncapped. The entity now comes from the WORKED CALLSIGN rather than the "
        "exchange field, resolved against the ARRL DXCC List (January 2026 edition, "
        "Resources/DXCC, generated by gen_dxcc.py) — the same split N1MM makes, and the only "
        "evidence there is when the exchange carries no country. RESIDUAL: a callsign whose "
        "prefix the ARRL list shares between entities resolves to the designated one, and one "
        "this app cannot resolve at all falls back to a single DX multiplier rather than being "
        "lost. "
        "Six bands including 160 m, no WARC, no VHF. CW and phone only - a digital QSO is invalid, "
        "not zero-point. County-line operation is permitted but 'County line QSO's should be "
        "logged as two separate QSO's', so a county-line entry is refused; a mobile changing "
        "county is a new station for both multiplier and point credit. No bonus stations, no "
        "bonus points, no final-score multiplier. Cabrillo CONTEST value ME-QSO-PARTY per WA7BNM; "
        "the sponsor requires Cabrillo but prints no header token. The PDF's contest-period "
        "sentence misprints the year as 2025 - its own title block says 2026, its deadline says "
        "October 12 2026, the rules' formula is 'the last full weekend in September', and "
        "2025-09-26 was a Friday, so the 2026-09-26 date is not in doubt. "
        "OPEN QUESTION (why this is partial): whether Maine itself counts as a state multiplier "
        "for Maine entrants. The rules list 'States (50)' as a class but never say a Maine county "
        "also yields the ME state multiplier, Maine stations always send a county so the token ME "
        "is never received, and there is no stated multiplier maximum to settle it by arithmetic. "
        "Shipped as NOT counting, so as not to credit a multiplier the sponsor never described - "
        "the same call as NHQP. Affects Maine entrants only; confirm with the sponsor "
        "(maineqsoparty@gmail.com) before submitting a log."
    ),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(meqp, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"meqp.json: {len(counties)} counties, {len(provinces)} province tokens")
print(f"  bands: {len(BANDS)} (rules say 'six contest bands')")
print(f"  mult pool per band/mode slot: {len(counties)} counties + 50 states + "
      f"{len(provinces)} provinces + DXCC")
print(f"  schedule: 1 window, 24 h (1200Z Sat 26 Sep -> 1200Z Sun 27 Sep 2026)")
