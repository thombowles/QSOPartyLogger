#!/usr/bin/env python3
"""Generate Resources/Data/arrl_sections.json — the 85 ARRL/RAC sections.

CONSTITUTION Article 2: parsed from the banked sponsor text, never typed.
SOURCE (Article 1): docs/research/arrl_sections_2026.txt, SOURCE A block =
https://contests.arrl.org/contestmultipliers.php?a=wve ("These are the names
of the 85 W/VE sections used in ARRL contests"), page footer "Version: 1.2.0,
Revised: May 12, 2023", fetched 2026-08-17. The Sweepstakes page the same
day: "There will be no Changes to Sweepstakes Multipliers for 2026."
"""
import json, pathlib, re

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "docs/research/arrl_sections_2026.txt"
OUT = ROOT / "Resources/Data/arrl_sections.json"

lines = SRC.read_text().splitlines()
start = next(i for i, l in enumerate(lines) if l.startswith("Verbatim table")) + 1
end = next(i for i, l in enumerate(lines) if l.startswith("COUNT (Source A"))

tokens, group = [], None
for line in lines[start:end]:
    if not line.strip() or line.startswith("="):
        continue
    if not line.startswith("  "):
        group = line.strip()
        continue
    m = re.match(r"^\s+(.+?)\s{2,}([A-Z]{2,3})$", line)
    assert m, f"unparsed row: {line!r}"
    name = re.sub(r"\s+", " ", m.group(1)).strip()
    tokens.append({"abbr": m.group(2), "name": name, "group": group})

assert len(tokens) == 85, len(tokens)
assert len({t["abbr"] for t in tokens}) == 85
by_group = {}
for t in tokens:
    by_group[t["group"]] = by_group.get(t["group"], 0) + 1
assert by_group == {
    "U.S. Call Area 0": 8, "U.S. Call Area 1": 7, "U.S. Call Area 2": 6,
    "U.S. Call Area 3": 4, "U.S. Call Area 4": 12, "U.S. Call Area 5": 8,
    "U.S. Call Area 6": 10, "U.S. Call Area 7": 10, "U.S. Call Area 8": 3,
    "U.S. Call Area 9": 3, "Canada": 14,
}, by_group
assert {"NTX", "STX", "WTX", "TER", "PAC", "GH", "MDC"} <= {t["abbr"] for t in tokens}

# Cross-check against the source file's own summary line, so a mis-parsed row
# order (right tokens, wrong sequence) trips an assertion instead of shipping.
source_b = next(i for i, l in enumerate(lines) if l.startswith("SOURCE B"))
order_line = next(l for l in lines[start:source_b] if l.startswith("Abbreviations in page order:"))
expected_order = order_line.split(":", 1)[1].split()
assert [t["abbr"] for t in tokens] == expected_order, "page order differs from the banked list"
assert len({t["name"] for t in tokens}) == 85, "duplicate section name"

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps({
    "id": "sections",
    "term": "section",
    "termPlural": "sections",
    "source": "https://contests.arrl.org/contestmultipliers.php?a=wve (Version 1.2.0, Revised May 12, 2023), fetched 2026-08-17; see docs/research/arrl_sections_2026.txt",
    "tokens": tokens,
    "aliases": {},
}, indent=2, ensure_ascii=False) + "\n")
print(f"wrote {OUT} with {len(tokens)} sections")
