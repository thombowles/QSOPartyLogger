#!/usr/bin/env python3
"""Fetch AD1C's Big CTY cty.csv into Resources/CTY/ and stamp its provenance.

CONSTITUTION Article 1: the file is the authority for callsign → entity, CQ/ITU
zone, continent (spec §1.6). Article 2: bundled verbatim, never retyped.
The server refuses a bare python User-Agent (verified 2026-08-17), so a browser
UA is sent. Re-run each season; commit cty.csv and VERSION.txt together.
"""
import datetime, hashlib, pathlib, re, urllib.request

URL = "https://www.country-files.com/bigcty/cty.csv"
ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "Resources/CTY"
OUT.mkdir(parents=True, exist_ok=True)

req = urllib.request.Request(URL, headers={"User-Agent": "Mozilla/5.0 (Macintosh) QSOPartyLogger-fetch"})
data = urllib.request.urlopen(req, timeout=60).read()
text = data.decode("utf-8", errors="strict")
records = [l for l in text.splitlines() if l.strip()]
assert len(records) >= 340, f"only {len(records)} records"
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
