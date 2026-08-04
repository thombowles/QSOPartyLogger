#!/usr/bin/env python3
"""Generate Resources/DXCC/dxcc_entities.json — the ARRL DXCC List as a
prefix -> entity table the engine can resolve a callsign against.

Per CONSTITUTION.md Article 2: parsed from the sponsor-designated source,
never typed.

WHY THIS EXISTS. Six parties count DXCC entities individually and could not,
because nothing here could tell one entity from another:

  nhqp   NH stations count "up to 10 DXCC country"; every DX station sends
         the literal token "DX", so the count ran up to 9 low.
  meqp   DXCC entities are multipliers for EVERY entrant, uncapped.
  nmqp   "DX entities worked" counted individually; the log carries "DX".
  ndqp   the rules want the DX country logged; there was no way to type one.
  oqp    counts entities individually AND accepts the literal "DX".
  warun  a DXCC prefix equal to a state code (PA, ON, OK, LA) was read as
         the state, leaving the 10-DXCC allowance under-used.

SOURCE, and why it is the right one (Article 1):

  arrl_dxcc_current_2026.txt   http://www2.arrl.org/files/file/DXCC/DXCC_Current.pdf
                               "ARRL DXCC LIST / CURRENT ENTITIES",
                               January 2026 Edition, fetched 2026-07-27.

NAQP rules 3 and 11 designate "the ARRL DXCC List" BY NAME, and
gen_naqp.py already consumes this same committed file for its 46 North
American entity names. This generator reads the whole list rather than the
NA slice. No new source is introduced, and no secondary source (cty.dat,
N1MM's country file, a wiki) is authority for a single entity here.

HOW THE RESOLUTION MODEL WAS CHOSEN. From the N1MM Logger+ manual, which is
prior art for BEHAVIOUR, never for a rule:

  * The entity comes from the CALLSIGN, matched against the country file --
    n1mmwp.hamdocs.com/appendices/customizing-the-dxcc-list/ -- with an
    exact-callsign entry overriding the prefix match where prefix matching
    gets it wrong (KG4 is the manual's own example).
  * The received exchange is validated against a CLOSED LIST and never
    guessed at; an unlisted token logs as an error. The HF setup page states
    it flatly: "There is a check on provinces and states, no check on
    countries."

So this table is keyed for longest-prefix matching, and the engine resolves
entity from the call, not from the exchange field.

WHAT THE SOURCE CANNOT SETTLE, recorded rather than papered over (Article 3):

1. SPRATLY IS. (entity 247) HAS NO PREFIX IN THE SOURCE. The prefix cell is
   empty in the ARRL PDF's own text layer -- verified against the committed
   PDF directly, so it is not an extraction artifact. It ships with no
   prefix and no callsign resolves to it. Supplying "1S" from memory would
   be exactly the hand-typed datum Article 2 forbids.

2. NINE PREFIX BLOCKS ARE SHARED BY SEVERAL ENTITIES in the ARRL list
   itself -- FO is Clipperton AND French Polynesia AND Austral AND
   Marquesas; VP6 is Pitcairn AND Ducie. The list expects a human to know
   which. Each block is designated to one entity in AMBIGUOUS below, with
   the losers named, and the engine credits the designated one. This is
   N1MM's behaviour too: its prefix match picks one, and only an
   exact-callsign entry in the country file splits them.

FOOTNOTE DIGITS ARE STRIPPED BY DATA, NOT BY EYE. The prefix column glues
footnote numbers to prefixes -- "TR32", "9G7", "BS711", "Z341". Whether the
trailing digits are a footnote or part of the prefix cannot be seen (T31 is
genuinely Central Kiribati; TR32 is Gabon plus footnote 32). The NOTES
section names each footnote's own prefix -- "32 (TR) Only contacts made
August 17, 1960..." -- so a digit run is stripped ONLY when the note it
would name lists the remaining stem. Anything else keeps its digits.

Run:  python3 docs/research/gen_dxcc.py
"""

import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "..", "..", "Resources", "DXCC")
SOURCE = "arrl_dxcc_current_2026.txt"

# The document states its own total, which is what makes this assertable.
EXPECTED_ENTITIES = 340

# Blocks the ARRL list itself gives to more than one entity. The value is the
# entity code that wins a bare prefix match; every other claimant is listed so
# the merge is visible and a future edition that splits them trips the
# assertion below rather than changing scores quietly.
#
# Designation rule: the entity an operator is overwhelmingly more likely to
# work from a US state QSO party -- the populated one over the rare DXpedition
# rock. Where both are rare, the first-listed in the ARRL row wins.
AMBIGUOUS = {
    # prefix: (winning entity code, [names of the entities that lose])
    "3D2":  ("176", ["Conway Reef", "Rotuma I."]),            # Fiji
    "3Y":   ("024", ["Peter 1 I."]),                          # Bouvet
    "CE0":  ("047", ["Juan Fernandez Is.",
                     "San Felix & San Ambrosio"]),            # Easter I.
    "CU":   ("149", ["Portugal"]),                            # Azores: the
    #        Azores' own row is CU, and Portugal's CQ-CU range ends on it. The
    #        specific entry beats the range.
    "E5":   ("234", ["N. Cook Is."]),                         # S. Cook Is.
    "FK":   ("162", ["Chesterfield Is."]),                    # New Caledonia
    "FO":   ("175", ["Austral I.", "Clipperton I.",
                     "Marquesas Is."]),                       # French Polynesia
    "HK0":  ("216", ["Malpelo I."]),                          # San Andres
    "JD1":  ("192", ["Minami Torishima"]),                    # Ogasawara
    "KH8":  ("009", ["Swains I."]),                           # American Samoa
    "PP0":  ("056", ["St. Peter & St. Paul Rocks",
                     "Trindade & Martim Vaz Is."]),           # Fernando de Noronha
    "VK0":  ("153", ["Heard I."]),                            # Macquarie I.
    # THE SOURCE PRINTS "VP0" FOR THE FOUR SOUTH ATLANTIC ENTITIES, not VP8 --
    # confirmed against the committed PDF's own text layer, so it is the
    # document's value and not an extraction slip. Consequence, recorded
    # rather than silently corrected: a station actually signing VP8 resolves
    # to Falkland Is. (141), whose row does read VP8.
    "VP0":  ("235", ["South Orkney Is.", "South Sandwich Is.",
                     "South Shetland Is."]),                  # South Georgia I.
    "VP6":  ("172", ["Ducie I."]),                            # Pitcairn I.
}

# France's TO and TX pools are shared across five and three entities in this
# very list, so no callsign beginning TO or TX can be attributed to one entity
# from this document. Dropped rather than designated -- guessing between
# Guadeloupe, Martinique, Reunion, Tromelin and Saint Martin would be
# inventing a fact. Each of those entities keeps its own unambiguous prefix
# (FG, FM, FR, FT/T, FS), which is what stations actually sign.
SHARED_ALTERNATE = re.compile(r"^(TO|TX)\d*$")

# Prefix cells the mechanical parse cannot read, each with the source text it
# replaces and why. Keyed by entity code so a renumbered row fails loudly.
PREFIX_OVERRIDES = {
    # "UA-UI1-7" is a two-axis range: letters UA..UI crossed with call areas
    # 1..7. Written out because the range syntax below varies one axis only.
    "054": ["UA1", "UA3", "UA4", "UA6", "UB1", "UB3", "UB4", "UB6",
            "UC1", "UC3", "UC4", "UC6", "UD1", "UD3", "UD4", "UD6",
            "UE1", "UE3", "UE4", "UE6", "UF1", "UF3", "UF4", "UF6",
            "UG1", "UG3", "UG4", "UG6", "UH1", "UH3", "UH4", "UH6",
            "UI1", "UI3", "UI4", "UI6",
            "RA1", "RA3", "RA4", "RA6"],
    # "UA-UI8,9,0" -- the Asiatic call areas.
    "015": ["UA8", "UA9", "UA0", "UB8", "UB9", "UB0", "UC8", "UC9", "UC0",
            "UD8", "UD9", "UD0", "UE8", "UE9", "UE0", "UF8", "UF9", "UF0",
            "UG8", "UG9", "UG0", "UH8", "UH9", "UH0", "UI8", "UI9", "UI0",
            "RA8", "RA9", "RA0"],
    # "9M2, 48*" is prefixes 9M2 and 9M4 carrying footnote 8 -- note 8 reads
    # "(9M2,4,6,8)", which is what identifies the 4 as a prefix and the 8 as
    # the note.
    "299": ["9M2", "9M4"],
    # "9M6, 88*" -- same shape: prefixes 9M6 and 9M8, footnote 8.
    "046": ["9M6", "9M8"],
    # "PJ5, 652" -- prefixes PJ5 and PJ6, footnote 52 ("(PJ5, 6)").
    "519": ["PJ5", "PJ6"],
    # "YN,H6-7,HT" -- H6-7 is H6 and H7, a bare-digit range on stem H.
    "086": ["YN", "H6", "H7", "HT"],
    # "3B6, 7" -- bare-digit continuation of the 3B stem.
    "004": ["3B6", "3B7"],
    # "C8-9" -- bare-digit range on stem C.
    "181": ["C8", "C9"],
    # "70" in note 5 is the Yemen prefix 7O (letter O), which pdftotext
    # renders as a zero in the notes but correctly as 7O5 in the row.
    "492": ["7O"],
    # Note 1 is the only footnote that names no prefix -- it reads just
    # "Unofficial prefix." -- so the data-driven strip cannot attribute it.
    # Both rows that carry it are entities whose prefix genuinely is
    # unofficial, which is the note's whole point.
    "246": ["1A"],      # "1A1" = prefix 1A + note 1, Sov. Mil. Order of Malta
    "522": ["Z6"],      # "Z61,55" = prefix Z6 + notes 1 and 55, Kosovo
}

# Entities whose prefix cell is empty in the source. Named so the gap is a
# deliberate, tested fact rather than a silent hole.
NO_PREFIX = {"247": "Spratly Is."}


def read(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        s = f.read()
    for a, b in [("’", "'"), ("‘", "'"), ("“", '"'),
                 ("”", '"'), ("–", "-"), ("—", "-"),
                 (" ", " ")]:
        s = s.replace(a, b)
    # pdftotext marks each page break with a form feed, always immediately
    # after the newline ending the previous line -- verified for every one of
    # the ten in this file. Dropping it leaves the line structure intact and
    # stops "\x0c43 (E4)" hiding a footnote from the parse.
    assert "\x0c" not in s.replace("\n\x0c", "\n"), "a form feed is not at a line start"
    return s.replace("\x0c", "")


raw = read(SOURCE)

# ------------------------------------------------------------------- header
# The list states its own total, and that is the count assertion.
stated = re.search(r"Current Entities Total:\s*(\d+)", raw)
assert stated, "the list no longer states its own entity total"
assert int(stated.group(1)) == EXPECTED_ENTITIES, (
    f"ARRL now lists {stated.group(1)} entities, not {EXPECTED_ENTITIES} -- "
    "re-read the list and update EXPECTED_ENTITIES deliberately"
)
assert "January 2026 Edition" in raw, "edition changed -- re-verify provenance"

# -------------------------------------------------------------------- notes
# footnote number -> the prefixes it applies to, from "32 (TR) ..." lines.
notes_text = raw.split("\nNOTES:", 1)[1].split("\n^ Also", 1)[0]
FOOTNOTES = {}
for m in re.finditer(r"(?m)^(\d{1,2})\s+(?:\(([^)]*)\))?", notes_text):
    n = int(m.group(1))
    if n in FOOTNOTES:
        continue
    FOOTNOTES[n] = [p.strip() for p in m.group(2).split(",")] if m.group(2) else []
# Notes run 1..55 with none missing; a gap means the parse slipped.
assert set(FOOTNOTES) == set(range(1, 56)), (
    f"expected notes 1-55, got {sorted(FOOTNOTES)}"
)
assert FOOTNOTES[32] == ["TR"], FOOTNOTES[32]
assert FOOTNOTES[8] == ["9M2", "4", "6", "8"], FOOTNOTES[8]
assert FOOTNOTES[1] == [], "note 1 names no prefix and must not strip anything"

# --------------------------------------------------------------------- rows
body = raw.split("\n Prefix ", 1)[-1].split("\nNOTES:", 1)[0]
lines = [l for l in body.splitlines() if l.strip()]

CODE_TAIL = re.compile(r"\s(\d{3})\s*$")
# Anchored on the tail, because the head's column gap is not reliable: two
# rows (VK9C, VK9X) separate prefix from name by a single space, and Sudan's
# ITU cell contains one ("47, 48"). `zones` must start with a digit or "(" so
# the continent cannot be mistaken for it -- otherwise "ITU HQ  EU  28  14"
# parses with cont="HQ".
ROW = re.compile(
    r"^(?P<head>.*?)"
    r"\s+(?P<cont>[A-Z]{2}(?:/[A-Z]{2})?)"
    r"\s+(?P<zones>[\d(][\d,\s\-()A-Z]*?)"
    r"\s+(?P<code>\d{3})\s*$"
)


def split_head(head):
    """(prefix, name) from a row's leading columns.

    Columns are normally 2+ spaces apart. Two rows use a single space, and
    the Spratly row has no prefix at all -- recognised by its deep indent,
    since every real prefix starts within two columns of the margin.
    """
    if len(head) - len(head.lstrip(" ")) >= 4:
        return "", head.strip()
    parts = [p for p in re.split(r"\s{2,}", head.strip()) if p]
    if len(parts) >= 2:
        return parts[0], " ".join(parts[1:])
    single = head.strip().split(" ", 1)
    return (single[0], single[1].strip()) if len(single) == 2 else ("", single[0])
# A continuation carrying only prefix syntax (no lowercase): "AA-AK#", "WL#*".
PFX_CONT = re.compile(r"^[A-Z0-9][A-Z0-9,\-/*#\s]*$")
# A leading fragment: prefix + start of a name, with the code on the NEXT
# line. Only ZL9 does this, but detect it by shape rather than by name.
LEAD = re.compile(r"^\s*(?P<pfx>[A-Z0-9][A-Z0-9,\-/*#]*)\s\s+(?P<name>[A-Z][A-Za-z .&'()-]*)$")

rows = []
lead = None
for ln in lines:
    if ln.strip().startswith("Entity") and "Cont" in ln:
        continue
    if not CODE_TAIL.search(ln):
        if re.fullmatch(r"[\s\d,]+", ln):
            continue                                  # spilled zone columns
        if (m := LEAD.match(ln)):
            lead = (m.group("pfx"), m.group("name"))
            continue
        if PFX_CONT.match(ln.strip()) and rows:
            rows[-1]["pfx"] += "," + ln.strip()        # wrapped prefix cell
            continue
        if rows:
            rows[-1]["name"] += " " + ln.strip()       # wrapped name
        continue
    m = ROW.match(ln)
    assert m, f"unparsed entity row: {ln!r}"
    pfx, name = split_head(m.group("head"))
    if lead:
        pfx = lead[0] if not pfx else pfx
        name = (lead[1] + " " + name).strip()
        lead = None
    rows.append({"pfx": pfx, "name": name, "cont": m.group("cont"),
                 "code": m.group("code")})

assert len(rows) == EXPECTED_ENTITIES, f"parsed {len(rows)} rows, expected {EXPECTED_ENTITIES}"
codes = [r["code"] for r in rows]
assert len(set(codes)) == EXPECTED_ENTITIES, "entity codes are not unique"

# Names carrying a wrapped tail keep only their head, as gen_naqp.py does:
# "Bahamas (Commonwealth of the)" -> the paren tail is ARRL layout, not the
# working name.
for r in rows:
    r["name"] = re.sub(r"\s+", " ", r["name"]).strip()
    if "(" in r["name"]:
        head = r["name"].split("(", 1)[0].strip()
        if head:
            r["name"] = head
    assert r["name"], f"empty name for {r['code']}"


# ----------------------------------------------------------------- prefixes
def strip_footnote(token):
    """Drop a trailing footnote number, but only when the NOTES section says
    that number belongs to the stem left behind."""
    m = re.match(r"^(.*?[A-Za-z/])(\d+)$", token)
    if not m:
        return token
    stem, digits = m.group(1), m.group(2)
    # Try the longest digit run first, then shorter ones: "BS711" is BS7 + 11.
    for cut in range(len(digits)):
        keep, note = digits[:cut], digits[cut:]
        candidate = stem + keep
        n = int(note)
        # The stem must be the note's own subject, or a longer form of it
        # ("JD1" under note 19's "(JD)"). The reverse must NOT be accepted:
        # letting note 18's "(H40)" validate a stem of "H4" would merge
        # Temotu Province into the Solomon Is., and note 31's "(TN)" would
        # reduce C. Kiribati's "T31" to a bare "T".
        if n in FOOTNOTES and any(candidate.startswith(p) for p in FOOTNOTES[n]):
            return candidate
    return token


def expand_range(part):
    """One 'A-B' range into its members. Varies exactly one character."""
    a, b = part.split("-", 1)
    if not a or not b:
        return [part]
    if b.isdigit() and len(b) == 1 and a[-1].isdigit():
        # "H6-7", "C8-9": bare-digit end sharing the alpha stem.
        stem = a[:-1]
        return [stem + chr(c) for c in range(ord(a[-1]), ord(b) + 1)]
    if len(a) == len(b) and a[:-1] == b[:-1]:
        lo, hi = a[-1], b[-1]
        if lo <= hi:
            return [a[:-1] + chr(c) for c in range(ord(lo), ord(hi) + 1)]
    if len(a) == len(b) and a[0] == b[0] and a[2:] == b[2:] and len(a) >= 2:
        lo, hi = a[1], b[1]
        if lo <= hi:
            return [a[0] + chr(c) + a[2:] for c in range(ord(lo), ord(hi) + 1)]
    return [a, b]


def prefixes_for(row):
    if row["code"] in PREFIX_OVERRIDES:
        return sorted(set(PREFIX_OVERRIDES[row["code"]]))
    if row["code"] in NO_PREFIX:
        assert not row["pfx"].strip(), (
            f"{row['code']} now HAS a prefix ({row['pfx']!r}) -- drop it from NO_PREFIX"
        )
        return []
    cell = row["pfx"].replace("*", "").replace("#", "").replace("^", "")
    out = set()
    previous = None
    for part in re.split(r"[,\s]+", cell):
        part = part.strip()
        if not part or SHARED_ALTERNATE.match(part):
            continue
        # A bare digit run is either a footnote annotating the token before it
        # ("4W 44", note 44 = "(4W)") or a continuation sharing that token's
        # alpha stem ("KP3,4" = KP3 and KP4; "PJ5, 6" = PJ5 and PJ6). The
        # NOTES section decides which: if the note names the previous token,
        # it is a footnote.
        if part.isdigit() and previous:
            n = int(part)
            if n in FOOTNOTES and any(previous.startswith(p) for p in FOOTNOTES[n]):
                continue
            stem = re.match(r"^(.*?[A-Za-z])\d*$", previous)
            if stem:
                out.add(stem.group(1) + part)
            continue
        part = strip_footnote(part)
        if not part:
            continue
        for token in (expand_range(part) if "-" in part and "/" not in part else [part]):
            token = strip_footnote(token.strip())
            if not token or SHARED_ALTERNATE.match(token):
                continue
            out.add(token)
            previous = token
            # "4U_ITU" and "4U_UN" are printed with an underscore where the
            # call-area digit goes -- verified against the PDF, which prints
            # the underscore itself. The ARRL form is kept as the canonical
            # key, and the digit is filled in so the callsigns stations
            # actually sign (4U1UN) resolve.
            if "_" in token:
                out.update(token.replace("_", d) for d in "0123456789")
    return sorted(out)


for r in rows:
    r["prefixes"] = prefixes_for(r)

missing = [r for r in rows if not r["prefixes"]]
assert {r["code"] for r in missing} == set(NO_PREFIX), (
    "entities with no prefix changed: "
    f"{sorted((r['code'], r['name']) for r in missing)}"
)

# ----------------------------------------------- one key -> one entity code
claims = {}
for r in rows:
    for p in r["prefixes"]:
        claims.setdefault(p, []).append(r)

by_code = {r["code"]: r for r in rows}
shared = {p: v for p, v in claims.items() if len(v) > 1}
assert set(shared) == set(AMBIGUOUS), (
    "the set of shared prefix blocks changed.\n"
    f"  now shared: {sorted(shared)}\n"
    f"  designated: {sorted(AMBIGUOUS)}"
)
for p, (winner, losers) in AMBIGUOUS.items():
    got = sorted(r["name"] for r in shared[p] if r["code"] != winner)
    assert winner in {r["code"] for r in shared[p]}, f"{p}: winner {winner} does not claim it"
    assert got == sorted(losers), f"{p}: losers are {got}, expected {sorted(losers)}"

table = {}
for p, v in claims.items():
    table[p] = AMBIGUOUS[p][0] if p in AMBIGUOUS else v[0]["code"]

# -------------------------------------------------------------- spot checks
# Chosen from the irregular rows: ranges, glued footnotes, state-code
# collisions, and the entities the six affected parties actually care about.
def entity(prefix):
    return by_code[table[prefix]]["name"]


assert entity("DL") == "Germany", entity("DL")            # from the DA-DR range
assert entity("DA") == "Germany"
assert entity("DR") == "Germany"
assert "DS" not in table, "the DA-DR range must not run past DR"
assert entity("G") == "England"
assert entity("GM") == "Scotland"                         # not England
assert entity("JA") == "Japan"                            # JA-JS range
assert entity("PA") == "Netherlands"                      # the WARUN collision
assert entity("ON") == "Belgium"                          # the WARUN collision
assert entity("OK") == "Czech Republic", entity("OK")
assert entity("LA") == "Norway"
assert entity("OH") == "Finland"
assert entity("TR") == "Gabon"                            # TR32, footnote 32
assert entity("T31") == "C. Kiribati"                     # T31 is NOT T3 + note 1
assert entity("BS7") == "Scarborough Reef"                # BS711, footnote 11
assert entity("9G") == "Ghana"                            # 9G7, footnote 7
assert entity("Z3") == "North Macedonia"                  # Z341, footnote 41
assert entity("KP4") == "Puerto Rico"
assert entity("KH6") == "Hawaii"
assert entity("KL") == "Alaska"                           # wrapped prefix cell
assert entity("K") == "United States of America"          # wrapped prefix cell
assert entity("AA") == "United States of America"
assert entity("VE") == "Canada", entity("VE")             # wrapped prefix cell
assert entity("VO") == "Canada"
assert entity("XE") == "Mexico"                           # XA-XI range
assert entity("EA6") == "Balearic Is."                    # beats EA-EH by length
assert entity("EA") == "Spain"
assert entity("FO") == "French Polynesia"                 # designated winner
assert entity("VP6") == "Pitcairn I."                     # designated winner
assert entity("ZL9") == "New Zealand Subantarctic Islands", entity("ZL9")
assert entity("4U_UN") == "United Nations HQ"
assert entity("4U1UN") == "United Nations HQ"              # the call actually signed
assert entity("4U1ITU") == "ITU HQ"
assert "1S" not in table, "Spratly's prefix is absent from the source"

# gen_naqp.py's 46 NA tokens must all resolve here, or the two readings of the
# same file disagree.
for token in ["C6", "CM", "ZF", "KG4", "YV0", "HK0", "PJ5", "PJ7", "XF4",
              "VP2E", "TI", "YN", "YS", "HP", "HR", "TG", "FG", "FJ", "FM",
              "FS", "6Y", "8P", "J3", "J6", "J7", "J8", "V2", "HH", "HI"]:
    assert token in table, f"NAQP checklist token {token} does not resolve"
assert entity("HI") == "Dominican Republic"

# --------------------------------------------------------------------- emit
entities = sorted(
    (
        {
            "code": r["code"],
            "name": r["name"],
            "continent": r["cont"],
            "prefixes": r["prefixes"],
        }
        for r in rows
    ),
    key=lambda e: e["code"],
)

payload = {
    "schemaVersion": 1,
    "source": "ARRL DXCC List, Current Entities, January 2026 Edition",
    "sourceURL": "http://www2.arrl.org/files/file/DXCC/DXCC_Current.pdf",
    "fetched": "2026-07-27",
    "generatedBy": "docs/research/gen_dxcc.py",
    "entityCount": len(entities),
    "entities": entities,
    "prefixes": dict(sorted(table.items())),
    # Recorded so the app can explain itself rather than silently merging.
    "mergedPrefixes": {
        p: {"entity": by_code[w]["name"], "alsoClaimedBy": losers}
        for p, (w, losers) in sorted(AMBIGUOUS.items())
    },
    "withoutPrefix": {code: name for code, name in sorted(NO_PREFIX.items())},
}

os.makedirs(OUT_DIR, exist_ok=True)
path = os.path.join(OUT_DIR, "dxcc_entities.json")
with open(path, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"wrote {path}")
print(f"  {len(entities)} entities (ARRL states {EXPECTED_ENTITIES})")
print(f"  {len(table)} prefix keys")
print(f"  {len(AMBIGUOUS)} shared blocks designated, {len(NO_PREFIX)} entity without a prefix")
