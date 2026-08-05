#!/usr/bin/env python3
"""Generate azqp.json from the sponsor's own pages.

The sponsor publishes county names and county abbreviations in TWO DIFFERENT
PLACES as parallel lists, never as a paired table, so pairing is positional —
exactly the step Article 2 exists to make safe. Rather than trust a zip(), this
script cross-checks the pairing three ways:

  1. the rules and the counties page must list the SAME 15 abbreviations in the
     SAME order;
  2. the county names must be in alphabetical order (both lists are);
  3. every abbreviation's letters must form a SUBSEQUENCE of its county name
     (CNO in COCONINO, LPZ in LAPAZ, SCZ in SANTACRUZ) — which a mis-alignment
     by even one position would break.

Sources (committed alongside this script, so the run is reproducible):
  azqp_rules_pdf.txt      — pdftotext -layout of the rules PDF linked from
                            azqp.org/rules, footer "Rev: 2501 6/23/2025 1100"
  azqp_rules_page.txt     — text of https://www.azqp.org/rules, whose site-wide
                            banner carries the 2026 date the rules body lacks
  azqp_counties_page.txt  — text of https://www.azqp.org/counties (county names)
  azqp_rules.md           — full rules research; all fetched 2026-07-24

NOTE the rules text is still the 2025 revision under a 2026 banner; the party
ships verified: partial for that reason. See azqp_rules.md section 2.

Usage:  python3 gen_azqp.py        (run from docs/research/)
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "azqp.json")
PDF = os.path.join(HERE, "azqp_rules_pdf.txt")
PAGE = os.path.join(HERE, "azqp_rules_page.txt")
COUNTIES = os.path.join(HERE, "azqp_counties_page.txt")


def read(path):
    return open(path, encoding="utf-8").read().replace("’", "'").replace("“", '"').replace("”", '"')


pdf_raw, page_raw, counties_raw = read(PDF), read(PAGE), read(COUNTIES)
pdf = re.sub(r"\s+", " ", pdf_raw)
page = re.sub(r"\s+", " ", page_raw)

# --- Abbreviations, from the rules' exchange sentence (both sources) ---
def abbrs_from(text, label):
    m = re.search(r"3-letter county abbreviation:\s*\(([^)]*)\)", text)
    if not m:
        sys.exit(f"county abbreviation list not found in {label}")
    found = [a.strip() for a in m.group(1).split(",") if a.strip()]
    if not all(re.fullmatch(r"[A-Z]{3}", a) for a in found):
        sys.exit(f"non 3-letter token in {label}: {found}")
    return found


abbrs = abbrs_from(pdf, "azqp_rules_pdf.txt")
assert abbrs == abbrs_from(page, "azqp_rules_page.txt"), \
    "the rules page and the rules PDF disagree on the county abbreviations"

# --- County names, from the counties page. The names block sits between the
# page heading and the abbreviation block that repeats after it. ---
m = re.search(r"AZQP 2026 Activated Counties(.*?)\bAPH\b", counties_raw, re.S)
if not m:
    sys.exit("county name block not found in azqp_counties_page.txt")
names = [ln.strip() for ln in m.group(1).splitlines() if ln.strip()]

# The same page repeats the abbreviations after the names; parse them too, so
# the ordering can be cross-checked against the rules (the Pima row carries an
# activation note, "PMA K7A (K6WSC)", so take the leading token only).
tail = counties_raw[m.end(1):]
page_abbrs = []
for line in tail.splitlines():
    tok = line.strip().split(" ")[0].strip()
    if re.fullmatch(r"[A-Z]{3}", tok):
        page_abbrs.append(tok)
    elif page_abbrs:
        break

assert len(names) == 15, f"expected 15 AZ county names, got {len(names)}: {names}"
assert len(abbrs) == 15, f"expected 15 AZ abbreviations, got {len(abbrs)}: {abbrs}"
assert page_abbrs == abbrs, \
    f"counties page and rules list the abbreviations differently:\n {page_abbrs}\n {abbrs}"
assert len(set(abbrs)) == 15, "AZ abbreviations not unique"
assert len(set(names)) == 15, "AZ county names not unique"
assert names == sorted(names), f"county names are not in alphabetical order: {names}"

# --- Check 3: each abbreviation is a subsequence of its county name. ---
def is_subsequence(abbr, name):
    it = iter(name.upper().replace(" ", ""))
    return all(ch in it for ch in abbr)


counties = {}
for abbr, name in zip(abbrs, names):
    assert is_subsequence(abbr, name), \
        f"{abbr} is not a subsequence of {name!r} — the positional pairing is wrong"
    counties[abbr] = name

# Every AZQP abbreviation is irregular; none is the first three letters. If that
# ever stops being true the sponsor has changed the scheme.
assert not any(a == n.upper().replace(" ", "")[:3] for a, n in counties.items()), \
    "an AZQP abbreviation is now just the first three letters — re-read the source"

# --- The rules' own arithmetic, which pins county count, bands and modes. ---
BANDS = ["160m", "80m", "40m", "20m", "15m", "10m"]
MODES = 2  # "MODES: CW, Phone"
assert "Total possible multipliers = 15 x 6 x 2 = 180" in pdf, \
    "the sponsor's out-of-state multiplier arithmetic changed — re-read the source"
assert len(counties) * len(BANDS) * MODES == 180, "15 counties x 6 bands x 2 modes"
assert "maximum of 12 contacts" in pdf, "the sponsor's own 6 bands x 2 modes check"
assert len(BANDS) * MODES == 12

# In-state: "Total possible multipliers = (50 + 13 + DXCC) x 2" — the 50 is what
# settles homeStateCountsViaCounty, since an AZ station can never receive "AZ".
assert "(50 + 13 + DXCC) x 2" in pdf, \
    "the sponsor's in-state multiplier arithmetic changed — see azqp_rules.md section 6"

# --- The rule sentences this file encodes. ---
for quote in [
    "BANDS: 160, 80, 40, 20, 15, 10 meters",
    "MODES: CW, Phone",
    "QSO POINTS: CW=2; Phone=1",
    "Multipliers count again for each mode",
    "Multipliers count again for each band and mode",
    "DX stations send signal report RS(T) and DXCC prefix",
    "between an Arizona station (AZ) and any other station (Non-AZ or AZ)",
    "spanning multiple county lines should be logged as multiple contacts",
    "one-time bonus of 100 points for a QSO with K7A",
    "2nd October Saturday, 8 AM to 10 PM (AZ)",
]:
    assert quote in pdf, f"rules text no longer contains: {quote!r}"

# The rules body is last year's; the 2026 date lives only in the site banner.
assert "2025 Arizona QSO Party" in pdf and "Rev: 2501" in pdf, \
    "the rules PDF is no longer the 2025 revision — re-verify and drop the partial marker"
assert "1500z Oct 10 to 0500z Oct 11, 2026" in page, \
    "the 2026 date is no longer in the rules-page banner — re-read the source"

azqp = {
    "schemaVersion": 1,
    "id": "azqp",
    "name": "Arizona QSO Party",
    # Sponsor prints no CONTEST: token; WA7BNM registry (Article 1 exception).
    "cabrilloContest": "AZ-QSO-PARTY",
    "homeState": "AZ",
    "countyAbbrLength": 3,
    # "BANDS: 160, 80, 40, 20, 15, 10 meters"
    "validBands": BANDS,
    # "QSO POINTS: CW=2; Phone=1"
    "points": {"phone": 1, "cw": 2, "digital": 2},
    # "Work stations once per band per mode per AZ county." / "maximum of 12
    # contacts" with a fixed single-county station.
    "dupeScope": "bandMode",
    "multipliers": {
        # "Multipliers are the 50 US states, the 13 Canadian provinces and
        # territories, and DXCC countries. Multipliers count again for each
        # mode. Total possible multipliers = (50 + 13 + DXCC) x 2."
        "inState": {
            "classes": ["state", "province", "dx"],
            # Not stated in words. An AZ station can never receive the token AZ
            # (AZ stations send counties), so the sponsor's own stated total of
            # 50 states is unreachable unless a county yields AZ — the same
            # arithmetic that settles KSQP, COQP and IAQP. See azqp_rules.md §6.
            "homeStateCountsViaCounty": True,
            "countScope": "perMode",
            # The sponsor counts DXCC entities individually -- see the
            # multiplier quote in the notes. Resolved against the ARRL
            # DXCC List (Resources/DXCC, generated by gen_dxcc.py).
            "dxCountsEntities": True,
        },
        # "Multipliers are the 15 Arizona counties. Multipliers count again for
        # each band and mode. Total possible multipliers = 15 x 6 x 2 = 180."
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "perBandMode",
        },
    },
    # "Receive a one-time bonus of 100 points for a QSO with K7A on any band or
    # mode during the contest." One-time, so scope is once — not per mode.
    "bonuses": [{"type": "workStation", "call": "K7A", "points": 100, "scope": "once"}],
    # "DX stations send signal report RS(T) and DXCC prefix."
    "dxStyle": "prefix",
    # "MODES: CW, Phone" — no digital category exists.
    "allowedModes": ["phone", "cw"],
    # "Expeditions (or mobiles) spanning multiple county lines should be logged
    # as multiple contacts" — a county line is two QSOs, not one two-county QSO.
    "maxSimultaneousCounties": 1,
    # No DC rule is stated anywhere in the AZQP rules, so no alias is invented.
    # "Send signal report RS(T) and 3-letter county abbreviation"
    "exchangeIncludesRST": True,
    # "A valid contact consists of ... the two-way exchange between an Arizona
    # station (AZ) and any other station (Non-AZ or AZ)."
    "outStateWorksHomeStationsOnly": True,
    # Site banner: "1500z Oct 10 to 0500z Oct 11, 2026 (UTC)"; the rules'
    # formula "2nd October Saturday, 8 AM to 10 PM (AZ)" agrees — 10 Oct 2026 is
    # the 2nd Saturday, and Arizona keeps MST (UTC-7) year round, so 8 AM =
    # 1500Z and 10 PM = 0500Z next day. 14 hours.
    "schedule": [{"start": "2026-10-10T15:00:00Z", "end": "2026-10-11T05:00:00Z"}],
    "counties": [{"abbr": a, "name": n} for a, n in sorted(counties.items(), key=lambda kv: kv[1])],
    "notes": (
        "verified: partial — rules from azqp.org/rules and the rules PDF linked there, read "
        "verbatim 2026-07-24. Both are the SAME document and both are still last year's: "
        "headed '2025 Arizona QSO Party', footer 'Rev: 2501 6/23/2025 1100', log deadline "
        "'0000z October 22, 2025'. The 2026 date comes from the sponsor's own site-wide "
        "banner, '1500z Oct 10 to 0500z Oct 11, 2026 (UTC)', which agrees with the rules' own "
        "formula '2nd October Saturday, 8 AM to 10 PM (AZ)': 10 October 2026 is the second "
        "Saturday, and Arizona keeps MST (UTC-7) all year, so 8 AM is 1500Z and 10 PM is "
        "0500Z next day - a 14-hour window. The DATE is therefore not in doubt; what is "
        "unverified is whether any RULE changed for 2026, since the sponsor has not re-issued "
        "the document. "
        "Multiplier scopes are asymmetric and BOTH sides differ: Arizona stations count "
        "states, provinces and DXCC countries ONCE PER MODE ('Total possible multipliers = "
        "(50 + 13 + DXCC) x 2'), while stations outside Arizona count the 15 Arizona counties "
        "ONCE PER BAND AND PER MODE ('Total possible multipliers = 15 x 6 x 2 = 180'). The "
        "generator asserts both of the sponsor's own totals, which between them pin the county "
        "count, the band count and the mode count. Counties are not an in-state multiplier "
        "class at all. DX stations send their DXCC PREFIX rather than the literal 'DX', so "
        "unlike NHQP and MEQP this app can tell entities apart - subject to the standing "
        "limitation that a prefix equal to a US state or Canadian province code (PA "
        "Netherlands, ON Belgium, LA Norway) is read as that state or province, the same way "
        "sponsors' log checkers resolve it. CW 2 points, phone 1. Six bands including 160 m, "
        "no WARC, no VHF; CW and phone only, so a digital QSO is invalid rather than "
        "zero-point. K7A pays a one-time 100-point bonus on any band or mode. County lines are "
        "logged as SEPARATE contacts ('Expeditions (or mobiles) spanning multiple county lines "
        "should be logged as multiple contacts'), so a county-line entry is refused; a mobile "
        "changing county is a new station for both point and multiplier credit. No DC rule is "
        "stated anywhere in the AZQP rules, so DC is loggable as its own token and is NOT "
        "folded into Maryland, unlike ALQP/TnQP/COQP/IAQP/MEQP/CQP. No final-score multiplier: "
        "'Total Score = (QSO POINTS x MULTIPLIERS) + BONUS POINTS'. Cabrillo CONTEST value "
        "AZ-QSO-PARTY per WA7BNM; the sponsor requires Cabrillo but prints no header token. "
        "County names and abbreviations are published on two different pages as parallel lists "
        "rather than a paired table, so the generator verifies the positional pairing three "
        "ways: both sources must list the same 15 abbreviations in the same order, the names "
        "must be alphabetical, and every abbreviation must be a subsequence of its county name "
        "(CNO in COCONINO, LPZ in LAPAZ, SCZ in SANTACRUZ). "
        "OPEN QUESTIONS (why this is partial): (1) The published rules are the 2025 revision "
        "under a 2026 banner, so a 2026 rule change would not be visible. Re-check azqp.org in "
        "the fortnight before 10 October 2026, and re-run gen_azqp.py, whose quoted-sentence "
        "assertions fail loudly if the text moved. (2) Whether Arizona itself counts as a state "
        "multiplier for Arizona stations is not stated in words. It ships as counting, because "
        "an AZ station can never receive the token AZ and the sponsor's stated total of 50 "
        "states is otherwise unreachable - the same arithmetic that settles KSQP, COQP and "
        "IAQP, but an inference rather than a quotation. Confirm both with the sponsor "
        "(info@azqp.org) before submitting a log."
    ),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(azqp, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"azqp.json: {len(counties)} counties, all 3 letters, pairing verified 3 ways")
print(f"  out-of-state ceiling: {len(counties)} x {len(BANDS)} x {MODES} = "
      f"{len(counties) * len(BANDS) * MODES} (rules say 180)")
print(f"  in-state: (50 + 13 + DXCC) x {MODES}, AZ reachable only via a county")
print(f"  schedule: 1 window, 14 h (1500Z Sat 10 Oct -> 0500Z Sun 11 Oct 2026)")
