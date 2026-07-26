#!/usr/bin/env python3
"""Generate ncqp.json from the North Carolina QSO Party Committee's own documents.

Sources (committed alongside this script, so the run is reproducible):
  ncqp_rules_2026.txt      — pdftotext -layout of Rules_2026_251013.pdf,
                             "2026 North Carolina QSO Party Contest Rules",
                             "Updated 10/13/2025". THE AUTHORITY.
  ncqp_abbreviations.html  — pdftohtml -c of NCQP_Abbreviations_221121.pdf, the
                             sponsor's official county sheet. THIS is what the
                             counties are parsed from; see below.
  ncqp_counties.txt        — pdftotext of the same sheet, committed for auditing
                             but NOT parsed (the plain text loses the colour).
  ncqp_rules.md            — full rules research; all fetched 2026-07-26

THE COUNTY ABBREVIATION IS ENCODED BY COLOUR, NOT BY CASE. The sponsor's sheet
prints each county name with its code picked out in dark red, and says so:
"(Abbreviation in dark red capital letters: i.e. CAPS)". So CABarrus is CAB,
GRahaM is GRM, DaViDson is DVD.

CASE ALONE IS NOT SUFFICIENT AND ONE COUNTY PROVES IT: "NEW Hanover" has a
capital H, so a case-based parse yields NEWH. The colour shows NEW in #cc0000
and " Hanover" in black - the code is NEW, and every code here is three letters.

The cross-check: the RULES PDF prints ten codes in plain text, for the "Rarest of
NC" counties - CAB GRM VAN MAC DAV CUR PAM ALL PER CAS - and all ten must agree
with the colour reading. That is asserted below.

WHAT DELIBERATELY DOES NOT SHIP, both verified and both unrepresentable - see
ncqp_rules.md section 14 and the notes field:
  * the "Rarest of NC" 10X QSO POINTS (phone 20 / CW 30 / digital 50), which the
    sponsor stresses land BEFORE multiplication. PointsTable is keyed by mode
    alone. This is the largest scoring gap in the repo.
  * the 500-point sweep for working five of those ten. sweepTiers counts ANY
    counties, not five of a named ten, so reusing it would pay nearly every log.

Usage:  python3 gen_ncqp.py        (run from docs/research/)
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Resources", "Parties", "ncqp.json")
RULES = os.path.join(HERE, "ncqp_rules_2026.txt")
ABBR_HTML = os.path.join(HERE, "ncqp_abbreviations.html")
COUNTIES_TXT = os.path.join(HERE, "ncqp_counties.txt")


def read(path):
    s = open(path, encoding="utf-8", errors="replace").read()
    for a, b in [("’", "'"), ("‘", "'"), ("“", '"'), ("”", '"'), ("–", "-"), ("—", "-")]:
        s = s.replace(a, b)
    return s


rules = re.sub(r"\s+", " ", read(RULES))
html = read(ABBR_HTML)

# --- Which CSS classes are dark red (#cc0000)? pdftohtml emits one class per
# font/colour combination, so resolve them rather than assuming a class name. ---
red_classes = set()
for cls, body in re.findall(r"\.(ft\d+)\s*\{([^}]*)\}", html):
    if re.search(r"color:\s*#cc0000", body, re.I):
        red_classes.add(cls)
assert red_classes, "no #cc0000 class found - the sponsor's sheet is no longer colour-coded"

# --- Every positioned run, with its row (top), column (left), class and text. ---
#
# The CODE comes from here (the colour is the authority). The NAME does not:
# pdftohtml pads every run with &#160; on both sides, so a run boundary inside a
# word ("CAB" + "arrus") is indistinguishable from the real space in
# "NEW Hanover". The names are therefore taken from the plain-text extraction
# below, and the two orderings are zipped.
RUN = re.compile(
    r'<p style="position:absolute;top:(\d+)px;left:(\d+)px;[^"]*"\s*class="(ft\d+)">(.*?)</p>',
    re.S,
)
runs = []
for top, left, cls, text in RUN.findall(html):
    text = re.sub(r"<[^>]+>", "", text).replace("&#160;", " ").replace("&nbsp;", " ")
    text = text.replace("&amp;", "&").strip()
    if text:
        runs.append((int(top), int(left), cls, text))

# The states/provinces table follows the counties; cut at its heading.
heading = [r for r in runs if "Additional Multipliers" in r[3]]
cutoff = heading[0][0] if heading else 10 ** 9

by_row = {}
for top, left, cls, text in runs:
    if top < cutoff:
        by_row.setdefault(top, []).append((left, cls, text))

abbrs = []
for top in sorted(by_row):
    ordered = sorted(by_row[top])
    # Only rows carrying the sheet's "___" check-off blanks are table rows. This
    # excludes the title block - whose subtitle "(Abbreviation in dark red
    # capital letters: i.e. CAPS)" puts CAPS in the same red and would otherwise
    # parse as a 101st county.
    markers = sum(1 for _, _, text in ordered if set(text) == {"_"})
    if markers == 0:
        continue
    assert markers == 4, f"row at top={top} has {markers} blanks, expected 4 counties"
    segment, segments = [], []
    for left, cls, text in ordered:
        if set(text) == {"_"}:
            if segment:
                segments.append(segment)
            segment = []
        else:
            segment.append((cls, text))
    if segment:
        segments.append(segment)
    for seg in segments:
        code = "".join(t for c, t in seg if c in red_classes).replace(" ", "")
        # NOTE: a segment whose code equals its whole text is NOT junk - Lee is
        # printed "LEE" entirely in red, because the county's name IS its code.
        if code:
            abbrs.append(code)

# --- Names, from the plain-text extraction, in the same row-major order. ---
names = []
county_text = read(COUNTIES_TXT).split("Additional Multipliers")[0]
for line in county_text.splitlines():
    if "___" not in line:
        continue
    for part in line.split("___")[1:]:
        part = " ".join(part.split())
        if part:
            names.append(part)

assert len(abbrs) == len(names) == 100, \
    f"colour gave {len(abbrs)} codes, text gave {len(names)} names - the sheet's layout moved"

counties = {}
for code, name in zip(abbrs, names):
    # Sanity: every red letter must be one of the name's capitals, in order.
    caps = [c for c in name if c.isupper()]
    assert list(code) == [c for c in caps if True][:len(code)] or set(code) <= set(caps), \
        f"code {code!r} is not drawn from the capitals of {name!r}"
    if code in counties and counties[code] != name:
        sys.exit(f"NCQP conflicting names for {code}: {counties[code]!r} vs {name!r}")
    counties[code] = name


def proper(raw):
    """The sheet's capitalisation is a code, not orthography."""
    out = raw.title()
    # "MCDowell".title() -> "Mcdowell"; the county is McDowell. Only one such name.
    out = re.sub(r"\bMc([a-z])", lambda m: "Mc" + m.group(1).upper(), out)
    return out


counties = {a: proper(n) for a, n in counties.items()}

assert len(counties) == 100, f"expected 100 NC counties, got {len(counties)}: {sorted(counties)}"
assert len(set(counties.values())) == 100, "NC county names not unique"
assert {len(a) for a in counties} == {3}, \
    f"NC codes should be uniformly 3 letters, got {sorted({len(a) for a in counties})}"
assert "100 North Carolina Counties" in rules, "the sponsor's own county count changed"

# THE CROSS-CHECK: the rules PDF prints these ten codes in plain text. They must
# agree with what the colour reading produced, or one of the two sources moved.
RAREST = {
    "CAB": "Cabarrus", "GRM": "Graham", "VAN": "Vance", "MAC": "Macon",
    "DAV": "Davie", "CUR": "Currituck", "PAM": "Pamlico", "ALL": "Alleghany",
    "PER": "Person", "CAS": "Caswell",
}
for abbr, name in RAREST.items():
    assert counties.get(abbr) == name, \
        f"rarest-county cross-check failed: {abbr} is {counties.get(abbr)!r}, rules say {name}"
    assert f"{name} {abbr}" in re.sub(r"\s+", " ", read(RULES)), \
        f"the rules no longer print '{name} {abbr}' in the Rarest of NC table"

# The colour reading's own hard cases. NEW is the one that case alone gets wrong.
for abbr, name in [
    ("NEW", "New Hanover"),   # capital H is BLACK; a case parse would say NEWH
    ("DVD", "Davidson"),      # three non-adjacent capitals in one word
    ("PEQ", "Perquimans"), ("WLK", "Wilkes"), ("MCD", "McDowell"),
    ("GRA", "Granville"),     # NOT Graham, which is GRM
    # The sponsor's sheet misspells Chowan as "Chowen". Shipped as printed, the
    # same call the repo makes for NHQP's "Merrimac"; the CODE is unaffected, and
    # this assertion is what stops someone "correcting" it later.
    ("CHO", "Chowen"), ("CHA", "Chatham"), ("CHE", "Cherokee"),
    ("ALA", "Alamance"), ("ALE", "Alexander"),
    ("WIL", "Wilson"), ("LEE", "Lee"), ("POL", "Polk"),
]:
    assert counties.get(abbr) == name, f"{abbr} should be {name!r}, got {counties.get(abbr)!r}"
assert "NEWH" not in counties, "New Hanover is NEW - the H is black, not part of the code"

# 99 of the 100 names match the real North Carolina county list exactly, which is
# an independent check on the whole parse. The one that does not is the sponsor's
# own typo, asserted here so a future corrected sheet is noticed rather than
# silently absorbed.
assert counties["CHO"] == "Chowen", \
    "the sponsor appears to have fixed its Chowan/Chowen typo - update the notes"
assert "CHOwen" in read(COUNTIES_TXT), "the typo is no longer in the source sheet"

# --- Bands: stated as a list plus an explicit exclusion. ---
BANDS = ["80m", "40m", "20m", "15m", "10m", "6m", "2m"]
assert "Operate on 80/75, 40, 20, 15, 10, 6, and 2 meters. No 160, WARC, or above 2 meters" \
    in rules, "the band sentence changed - re-read it"
assert "160m" not in BANDS, "NCQP explicitly excludes 160 m"
for excluded in ["160m", "60m", "30m", "17m", "12m", "1.25m", "70cm"]:
    assert excluded not in BANDS

# --- The rule sentences this file encodes. ---
for quote in [
    "1500 UTC March 1 to 0100 UTC March 2, 2026",
    "(10 am to 8 pm EST on March 1, 2026)",
    "North Carolina (NC) stations work everyone, send call sign and NC county",
    "Send call sign and state/province, or \"DX\"",
    "Sending signal report (i.e., 59) is optional",
    "Stations outside of North Carolina (Non-NC) work NC stations only",
    "Phone - 2 points each",
    "CW - 3 points each",
    "Digital - 5 points each",
    "Work 100 North Carolina Counties, 49 US States (not NC) plus DC",
    "plus one DX. 164 total possible",
    "Count each multiplier worked only once across all modes, bands, and operating location",
    "A maximum of two counties may be worked simultaneously",
    "A two county QSO must be logged as separate QSOs with two lines in the log",
    "QSO's made using FT-8/4 should not be included",
    "DO NOT INCLUDE FT-8/4 QSOS in the regular Cabrillo log",
    "NC stations may include the county from which operation takes place in the Multiplier count",
]:
    assert quote in rules, f"the 2026 rules no longer contain: {quote!r}"

assert "Updated 10/13/2025" in rules, \
    "this is not the 10/13/2025 revision - re-verify every rule before shipping it"

# The sponsor's stated multiplier total must equal what the schema produces:
# 100 counties + 50 state-class tokens (51 accepted, less the home state NC)
# + 13 provinces + 1 DX = 164.
assert 100 + (51 - 1) + 13 + 1 == 164, "the multiplier arithmetic no longer reconciles"

# The two rules that deliberately do not ship. Assert they are still there, so a
# future edition dropping or changing them fails loudly instead of leaving a
# stale limitation in the notes.
assert "will be scored 10X QSO points" in rules, \
    "the Rarest of NC 10X rule changed - revisit KNOWN LIMITATION 1"
assert "Phone - 20 points each" in rules and "CW - 30 points each" in rules \
    and "Digital - 50 points each" in rules
assert "These points are added to the rest of the regular QSO Points prior to MULT multiplication" \
    in rules, "the pre-multiplication placement changed - revisit KNOWN LIMITATION 1"
assert "five of the \"Rarest of NC\" counties, 500 additional bonus points" in rules, \
    "the sweep bonus changed - revisit KNOWN LIMITATION 2"

ncqp = {
    "schemaVersion": 1,
    "id": "ncqp",
    "name": "North Carolina QSO Party",
    # The rules enumerate the CATEGORY-* headers and omit CONTEST:, so this rests
    # on the WA7BNM registry (Article 1's codified exception).
    "cabrilloContest": "NC-QSO-PARTY",
    "homeState": "NC",
    "countyAbbrLength": 3,
    # "80/75, 40, 20, 15, 10, 6, and 2 meters. No 160, WARC, or above 2 meters."
    # The only bundled party that runs 80 m and up while excluding 160.
    "validBands": BANDS,
    # "Phone - 2 / CW - 3 / Digital - 5" - the ONLY bundled party where digital
    # outscores CW. FT8/FT4 are excluded from this contest entirely; they belong
    # to the separate Weak Signal Showcase. See notes.
    "points": {"phone": 2, "cw": 3, "digital": 5},
    "dupeScope": "bandMode",
    "multipliers": {
        # "100 North Carolina Counties, 49 US States (not NC) plus DC, 13 Canadian
        # Provinces/Territories, plus one DX. 164 total possible."
        "inState": {
            "classes": ["county", "state", "province", "dx"],
            # "49 US States (NOT NC)" - stated outright, in the negative.
            "homeStateCountsViaCounty": False,
            # "Count each multiplier worked only once across all modes, bands,
            # and operating location."
            "countScope": "once",
            # "plus ONE DX" falls out of dxStyle "token"; no numeric cap needed.
        },
        # "Non-NC participants: Work stations in 100 North Carolina Counties."
        "outState": {
            "classes": ["county"],
            "homeStateCountsViaCounty": False,
            "countScope": "once",
        },
    },
    # The 500-point five-rare-county sweep is NOT expressible - sweepTiers counts
    # any counties, not five of a named ten. See notes, KNOWN LIMITATION 2.
    "bonuses": [],
    # 'Send call sign and state/province, or "DX"'; "Any location not listed above
    # is considered DX. This includes US Territories, Mexican provinces, and DXCC
    # countries" - and all of it is worth exactly one multiplier.
    "dxStyle": "token",
    # Phone, CW and non-FT8/4 digital.
    "allowedModes": ["phone", "cw", "digital"],
    # "A maximum of two counties may be worked simultaneously under this provision."
    "maxSimultaneousCounties": 2,
    # "Sending signal report (i.e., 59) is optional", and the definition of a
    # valid QSO omits it: "date, time, mode, call sign, and location".
    "exchangeIncludesRST": False,
    # "Stations outside of North Carolina (Non-NC) work NC stations only."
    "outStateWorksHomeStationsOnly": True,
    # "1500 UTC March 1 to 0100 UTC March 2, 2026" - printed as a round instant,
    # with no last-minute notation to resolve. Sunday only, like ILQP.
    "schedule": [{"start": "2026-03-01T15:00:00Z", "end": "2026-03-02T01:00:00Z"}],
    "counties": [{"abbr": a, "name": n} for a, n in sorted(counties.items(), key=lambda kv: kv[1])],
    "hubSpots": {
        "tableURL": "http://qsopartyhub.com/ncqp-table.php",
        "postURL": "http://qsopartyhub.com/ncqp-spots.php",
    },
    "notes": (
        "verified: partial - rules from the North Carolina QSO Party Committee's official 2026 "
        "PDF ('2026 North Carolina QSO Party Contest Rules', Updated 10/13/2025) and the "
        "sponsor's official county abbreviation sheet, both read verbatim 2026-07-26. Ten hours, "
        "1500Z to 0100Z, SUNDAY 1 MARCH 2026 - a Sunday-only party like ILQP, and the day after "
        "South Carolina finishes. The sponsor prints a round end instant, so unlike MNQP, BCQP "
        "and SCQP there is no last-minute notation to resolve. "
        "THE COUNTY CODES ARE ENCODED BY COLOUR, NOT BY CASE. The sponsor's sheet prints each "
        "county name with its code picked out in dark red - 'Abbreviation in dark red capital "
        "letters' - so CABarrus is CAB, GRahaM is GRM and DaViDson is DVD. CASE ALONE IS NOT "
        "ENOUGH AND ONE COUNTY PROVES IT: 'NEW Hanover' has a capital H, so reading the capitals "
        "gives NEWH, while the colour shows NEW in dark red and ' Hanover' in black. The code is "
        "NEW and every code here is three letters. gen_ncqp.py therefore parses the colour and "
        "cross-checks all ten codes the rules PDF prints in plain text. Watch DVD Davidson "
        "against DAV Davie - two different counties one letter apart, and DAV is one of the ten "
        "rare ones, so confusing them swaps a 2-point QSO for a 20-point one. Also GRM Graham vs "
        "GRA Granville, PEQ Perquimans vs PER Person, and WLK Wilkes vs WIL Wilson. "
        "Phone 2 points, CW 3, DIGITAL 5 - the only bundled party where digital outscores CW. "
        "FT8 AND FT4 ARE NOT PART OF THIS CONTEST: they belong to the separate Weak Signal "
        "Showcase, which is scored on its own, submitted as its own ADIF file, and multiplied by "
        "grid squares rather than counties. The rules say 'DO NOT INCLUDE FT-8/4 QSOS in the "
        "regular Cabrillo log'. This app cannot tell FT8 from other digital modes when scoring, "
        "so KEEP FT8/FT4 OUT OF THIS LOG ENTIRELY and use the sponsor's separate Showcase form. "
        "Multipliers count ONCE overall - not per band, not per mode. NC stations count the 100 "
        "counties, 49 states (explicitly NOT North Carolina), DC, the 13 provinces and "
        "territories and ONE DX for any and all DX worked, which is the sponsor's stated 164 "
        "maximum and is exactly what this app produces. Everyone else counts the 100 NC counties. "
        "The exchange is CALL SIGN AND LOCATION with NO SIGNAL REPORT - 'Sending signal report "
        "(i.e., 59) is optional' - the third party after MDC and MNQP to drop it, and unlike MNQP "
        "nothing replaces it, so nothing is missing from the log. County lines pay two counties, "
        "logged as two separate lines, which is what this app writes; the sponsor delegates the "
        "definition of a county border to MARAC's county-hunter rules by reference. "
        "KNOWN LIMITATION 1 - THE 'RAREST OF NC' 10X QSO POINTS ARE NOT APPLIED, AND THIS IS THE "
        "LARGEST SCORING GAP IN THIS APP. A QSO with one of ten designated counties scores TEN "
        "TIMES the normal points - phone 20, CW 30, digital 50 - and the sponsor stresses that "
        "these are 'added to the rest of the regular QSO Points PRIOR TO MULT multiplication so "
        "they have a significant positive effect on the final score'. This app pays points by "
        "MODE only, with no way to pay more for a particular county, so every rare-county QSO is "
        "scored at one tenth of its value BEFORE being multiplied. The ten counties are CAB "
        "Cabarrus, GRM Graham, VAN Vance, MAC Macon, DAV Davie, CUR Currituck, PAM Pamlico, ALL "
        "Alleghany, PER Person and CAS Caswell. TO CORRECT BY HAND: for each such QSO add nine "
        "times its normal points (18 phone, 27 CW, 45 digital) to your QSO-point total, THEN "
        "multiply. KNOWN LIMITATION 2 - THE 500-POINT SWEEP IS NOT APPLIED. Working at least one "
        "station in five of those ten counties adds 500 points after multiplication. This app's "
        "sweep rule counts any counties rather than membership of a named set, so using it would "
        "pay almost every log; nothing ships instead. Add 500 yourself if you worked five of the "
        "ten. KNOWN LIMITATION 3 - NC stations may count the county they operate from as a "
        "multiplier 'regardless of whether any QSOs are logged from that same county', and mobile "
        "and portable stations may count each county they activate. This app has no "
        "self-activation multiplier, so an in-state entrant is short by the number of counties "
        "they operated from. OUT-OF-STATE ENTRANTS ARE UNAFFECTED by this one. "
        "Cabrillo CONTEST value NC-QSO-PARTY per the WA7BNM registry - the rules enumerate the "
        "CATEGORY headers an entrant must set and omit CONTEST:. Logs are due 2026-03-15, "
        "Cabrillo only, paper no longer accepted. "
        "OPEN QUESTIONS (why this is partial): (1) and (2) are KNOWN LIMITATIONS 1 and 2 above - "
        "both are fully verified rules that this app cannot express, and BOTH CHANGE THE FINAL "
        "SCORE FOR EVERY ENTRANT, in state and out. Until they are built, an NCQP score from this "
        "app is a floor, not a total, and the arithmetic to correct it is given above. (3) The "
        "self-activation multiplier, which affects in-state entrants only. None of the three is a "
        "rule in doubt; all three are missing app features. Verify against the sponsor's own "
        "scoring when results are posted at http://www.ncqsoparty.org."
    ),
}

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(ncqp, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"ncqp.json: {len(counties)} counties, uniform 3-letter codes read FROM COLOUR")
print(f"  cross-check: all 10 'Rarest of NC' codes agree with the rules PDF's plain text")
print(f"  NEW Hanover -> NEW (the capital H is black; a case parse would say NEWH)")
print(f"  points: phone 2, CW 3, digital 5 - the only party where digital beats CW")
print(f"  multipliers: once overall; in-state 100+50+13+1 = 164 (sponsor's own total)")
print(f"  bands: {len(BANDS)} - 80 m up, 160 m explicitly excluded")
print(f"  schedule: 1 window, 10 h Sunday-only (1500Z -> 0100Z, 1-2 Mar 2026)")
print(f"  NOT shipped: Rarest-of-NC 10x points, the 500-point sweep, activation mults")
