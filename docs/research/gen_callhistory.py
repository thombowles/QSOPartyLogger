#!/usr/bin/env python3
"""Generate `callHistory` blocks for the bundled parties from the N1MM
call history file listing (constitution Article 2: the mapping is derived
from the site's own inventory and verified against the files' own
`# QSOPARTY` declarations, never hand-typed).

Two phases:

  --fetch   Scrape the listing (11 pages as of 2026-07-28) into
            n1mm_callhistory_inventory.json, then download each mapped
            party's newest file and record its `#` comment tokens and
            `!!Order!!` line into n1mm_callhistory_verify.json.
            Network. Re-run before a new season.

  (default) Read the two banked files, assert the roster, and patch
            Resources/Parties/*.json with `callHistory` blocks.
            Offline; deterministic from the banked data.

RUN THE DEFAULT PHASE AFTER ANY PARTY GENERATOR, exactly as with
gen_caveats.py. A `gen_<party>.py` rewrites its JSON file whole and knows
nothing about `callHistory`, so it silently drops the block. That is caught
rather than trusted — `CallHistorySourceTests.testExactlyThreePartiesHaveNoCallHistoryFile`
fails, naming the party as a fourth file-less one — and re-running this is
idempotent and fixes it.

Provenance: docs/research/n1mm_callhistory.md.
"""

import json
import re
import sys
import time
from pathlib import Path

HERE = Path(__file__).parent
PARTIES = HERE.parent.parent / "Resources" / "Parties"
INVENTORY = HERE / "n1mm_callhistory_inventory.json"
VERIFY = HERE / "n1mm_callhistory_verify.json"

BASE = "https://n1mmwp.hamdocs.com"
LISTING = BASE + "/mmfiles/categories/callhistory/"

# Parties served by one combined file for the shared May weekend. The file's
# own header declares every one of these tokens ("There will be only one file
# for all, in 2026").
COMBINED_PREFIX = "QSOP_IN7QPNE_DE"
COMBINED_TOKENS = {
    "inqp": "QSOPARTY IN",
    "sevenqp": "QSOPARTY 7QP",
    "newenglandqp": "QSOPARTY NEWE",
    "deqp": "QSOPARTY DE",
    "in7qpne": "QSOPARTY IN7QPNE",
}

# The NAQPs are N1MM contest modules, not QSOPARTY sub-states; their files
# carry the module name as a bare comment.
NAQP = {"naqpcw": ("NAQPCW", "NAQPCW"), "naqpssb": ("NAQPSSB", "NAQPSSB")}

# Verified against the full inventory 2026-07-28: no call history file exists
# for these parties under any name (no QSOP_AZ, QSOP_MD/MDC, QSOP_VT).
EXPECTED_UNMAPPED = {"azqp", "mdc", "vtqp"}


def bundled_parties():
    out = {}
    for f in sorted(PARTIES.glob("*.json")):
        with open(f) as fh:
            out[f.stem] = json.load(fh)
    return out


def mapping_for(pid: str, party: dict):
    """(filePrefix, token) for a party, or None when no file is expected."""
    if pid in EXPECTED_UNMAPPED:
        return None
    if pid in COMBINED_TOKENS:
        return (COMBINED_PREFIX, COMBINED_TOKENS[pid])
    if pid in NAQP:
        return NAQP[pid]
    state = party["homeState"]
    return (f"QSOP_{state}", f"QSOPARTY {state}")


def matches(filename: str, prefix: str) -> bool:
    """The app's rule, mirrored: prefix followed by a separator, so QSOP_NE
    cannot claim QSOP_NEWE and QSOP_IN cannot claim QSOP_IN7QPNE_DE."""
    up, pre = filename.upper(), prefix.upper()
    return any(up.startswith(pre + sep) for sep in "-_.")


def newest(inventory, prefix):
    """Newest inventory entry for a prefix: by listed date, then by listing
    position (the listing was scraped sort=newest)."""
    cands = [
        (e["date"], -i, e)
        for i, e in enumerate(inventory)
        if matches(e["title"], prefix)
    ]
    return max(cands)[2] if cands else None


# --- fetch phase -----------------------------------------------------------

def fetch_inventory():
    import urllib.request

    def get(url):
        req = urllib.request.Request(
            url, headers={"User-Agent": "QSOPartyLogger-research/1.0"}
        )
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.read().decode("utf-8", "replace")

    entries, page = [], 1
    while True:
        url = (
            f"{LISTING}?view=list&sort=newest"
            if page == 1
            else f"{LISTING}page/{page}/?view=list&sort=newest"
        )
        try:
            html = get(url)
        except urllib.error.HTTPError as e:
            if e.code == 404:  # one page past the end
                break
            raise
        found = re.findall(
            r'<a href="(https://n1mmwp\.hamdocs\.com/mmfiles/[^"]+)">\s*'
            r'<span class="cmdm-list-item-title">([^<]+)</span>\s*</a>\s*'
            r'<div class="cmdm-list-item-desc">\s*([^<]*?)\s*</div>',
            html,
        )
        if not found:
            break
        entries.extend(
            {"pageURL": u, "title": t, "date": d} for u, t, d in found
        )
        print(f"page {page}: {len(found)}")
        page += 1
        time.sleep(1)
    assert len(entries) > 400, f"suspiciously small inventory: {len(entries)}"
    with open(INVENTORY, "w") as f:
        json.dump(entries, f, indent=1)
    return entries


def download_file(page_url):
    import http.cookiejar
    import urllib.request

    cj = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(
        urllib.request.HTTPCookieProcessor(cj)
    )
    opener.addheaders = [("User-Agent", "QSOPartyLogger-research/1.0")]
    html = opener.open(page_url, timeout=30).read().decode("utf-8", "replace")
    action = re.search(
        r'class="CMDM-downloadForm" action="([^"]+)"', html
    ).group(1)
    nonce = re.search(r'name="cmdm_nonce" value="([^"]+)"', html).group(1)
    fid = re.search(r'name="id" value="([^"]+)"', html).group(1)
    req = urllib.request.Request(
        action,
        data=f"cmdm_nonce={nonce}&id={fid}".encode(),
        headers={"Referer": page_url, "User-Agent": "QSOPartyLogger-research/1.0"},
    )
    return opener.open(req, timeout=60).read()


def fetch_verify(inventory):
    parties = bundled_parties()
    verify, seen_pages = {}, {}
    for pid, party in sorted(parties.items()):
        m = mapping_for(pid, party)
        if not m:
            continue
        prefix, token = m
        entry = newest(inventory, prefix)
        assert entry, f"{pid}: no inventory file matches {prefix}"
        if entry["pageURL"] in seen_pages:
            body = seen_pages[entry["pageURL"]]
        else:
            print(f"{pid}: downloading {entry['title']}")
            body = download_file(entry["pageURL"])
            seen_pages[entry["pageURL"]] = body
            time.sleep(1)
        text = body.decode("utf-8", "replace")
        # The app's rule, mirrored: a token matches when some comment line,
        # uppercased with all whitespace removed, equals it. Whitespace-blind
        # because QSOP_OH-2025-003.txt writes "# QSO PARTY OH" where every
        # sibling writes "# QSOPARTY XX".
        squeeze = lambda s: "".join(s.upper().split())
        matched = next(
            (line.strip() for line in text.splitlines()
             if line.startswith("#")
             and squeeze(line.lstrip("#")) == squeeze(token)),
            None,
        )
        order = next(
            (l.strip() for l in text.splitlines()
             if l.strip().upper().startswith("!!ORDER!!")),
            None,
        )
        verify[pid] = {
            "filePrefix": prefix,
            "token": token,
            "resolvedFile": entry["title"],
            "pageURL": entry["pageURL"],
            "listedDate": entry["date"],
            "bytes": len(body),
            "orderLine": order,
            "matchedComment": matched,
            "tokenVerified": matched is not None,
        }
    with open(VERIFY, "w") as f:
        json.dump(verify, f, indent=1, sort_keys=True)
    return verify


# --- patch phase -----------------------------------------------------------

def patch():
    inventory = json.load(open(INVENTORY))
    verify = json.load(open(VERIFY))
    parties = bundled_parties()

    mapped = {p for p in parties if mapping_for(p, parties[p])}
    unmapped = set(parties) - mapped
    assert unmapped == EXPECTED_UNMAPPED, (
        f"unmapped drifted: {sorted(unmapped)}"
    )
    assert len(mapped) == len(parties) - len(EXPECTED_UNMAPPED), (
        f"expected {len(parties) - len(EXPECTED_UNMAPPED)} mapped, "
        f"got {len(mapped)}"
    )
    assert set(verify) == mapped, "verify file out of step with the catalog"

    for pid in sorted(mapped):
        prefix, token = mapping_for(pid, parties[pid])
        v = verify[pid]
        assert v["filePrefix"] == prefix, f"{pid}: banked prefix drifted"
        assert newest(inventory, prefix), f"{pid}: no file matches {prefix}"
        assert v["tokenVerified"], (
            f"{pid}: {v['resolvedFile']} does not declare '{token}' — "
            "re-run --fetch and inspect before shipping a token the app "
            "will reject good files over"
        )
        block = {"filePrefix": prefix, "token": token}

        path = PARTIES / f"{pid}.json"
        data = json.load(open(path))
        if data.get("callHistory") == block:
            continue
        data["callHistory"] = block
        with open(path, "w") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
        print(f"patched {pid}: {block}")

    print(f"OK: {len(mapped)} parties mapped, "
          f"{sorted(EXPECTED_UNMAPPED)} verified file-less")


if __name__ == "__main__":
    if "--fetch" in sys.argv:
        inv = fetch_inventory()
        fetch_verify(inv)
    patch()
