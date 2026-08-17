#!/usr/bin/env python3
"""Fetch AD1C's Big CTY cty.csv into Resources/CTY/ and stamp its provenance.

CONSTITUTION Article 1: the file is the authority for callsign → entity, CQ/ITU
zone, continent (spec §1.6). Article 2: bundled verbatim, never retyped.
The server refuses a bare python User-Agent (verified 2026-08-17), so a browser
UA is sent. Re-run each season; commit cty.csv and VERSION.txt together.

Run:  python3 docs/research/fetch_cty.py            fetch, assert, stamp
      python3 docs/research/fetch_cty.py --check     verify the committed
                                                       cty.csv still matches
                                                       its own VERSION.txt
                                                       stamp -- no network
"""
import datetime, hashlib, pathlib, re, sys, urllib.request

URL = "https://www.country-files.com/bigcty/cty.csv"
ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "Resources/CTY"

# The VERSION.txt fields that are recomputable from cty.csv itself (plus the
# constant source URL) and so are what --check compares. "fetched" has no
# recomputed counterpart, and "format"/"see" are fixed descriptive text, not
# data -- so none of the three is checked. Freeform lines appended below the
# stamp (the "written by"/"checked by" provenance pair) are ignored too: each
# field is pulled out by its own anchored line, never a whole-file compare.
CHECKED_FIELDS = ("source", "release", "records", "bytes", "sha256")


def _field(text, name):
    m = re.search(rf"(?m)^{name}:\s*(.*)$", text)
    return m.group(1).strip() if m else None


def check():
    """Recompute release/records/bytes/sha256 from the committed cty.csv and
    compare against what VERSION.txt has stamped -- no download. Catches
    cty.csv and VERSION.txt drifting apart (a hand edit to either) without
    needing the network fetch itself to notice."""
    csv_path, version_path = OUT / "cty.csv", OUT / "VERSION.txt"
    data = csv_path.read_bytes()
    text = data.decode("utf-8", errors="strict")
    records = [l for l in text.splitlines() if l.strip()]
    m = re.search(r"=VER(\d{8})", text)
    computed = {
        "source": URL,
        "release": f"VER{m.group(1)}" if m else None,
        "records": str(len(records)),
        "bytes": str(len(data)),
        "sha256": hashlib.sha256(data).hexdigest(),
    }
    stamped_text = version_path.read_text()
    stamped = {name: _field(stamped_text, name) for name in CHECKED_FIELDS}
    mismatches = [name for name in CHECKED_FIELDS if computed[name] != stamped[name]]
    if mismatches:
        for name in mismatches:
            print(f"{name}: cty.csv says {computed[name]!r}, VERSION.txt says {stamped[name]!r}")
        return 1
    print("check: OK")
    return 0


if "--check" in sys.argv:
    sys.exit(check())

OUT.mkdir(parents=True, exist_ok=True)

req = urllib.request.Request(URL, headers={"User-Agent": "Mozilla/5.0 (Macintosh) QSOPartyLogger-fetch"})
data = urllib.request.urlopen(req, timeout=60).read()
text = data.decode("utf-8", errors="strict")
records = [l for l in text.splitlines() if l.strip()]
assert len(records) >= 340, f"only {len(records)} records"
assert all(len(l.split(",")) == 10 for l in records), "a record does not have 10 fields — truncated or format changed"
assert text.rstrip().endswith(";")
assert sum(1 for l in records if not l.startswith("*")) >= 340, "fewer than 340 DXCC records"
m = re.search(r"=VER(\d{8})", text)
assert m, "no =VERyyyymmdd release marker in the file"
(OUT / "cty.csv").write_bytes(data)
(OUT / "VERSION.txt").write_text(
    f"source: {URL}\nfetched: {datetime.date.today().isoformat()}\nrelease: VER{m.group(1)}\n"
    f"records: {len(records)}\nbytes: {len(data)}\nsha256: {hashlib.sha256(data).hexdigest()}\n"
    "format: primary prefix, name, ADIF entity code, continent, CQ zone, ITU zone, lat, lon, tz, prefix list ending ';'\n"
    "        (a leading * on the primary prefix marks a WAE-only entity; =CALL is an exact callsign; (n) CQ and [n] ITU overrides)\n"
    "see: docs/research/cty_dat_format.txt\n")
print(f"wrote {len(data)} bytes, {len(records)} records, release VER{m.group(1)}")
