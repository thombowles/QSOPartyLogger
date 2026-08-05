#!/usr/bin/env python3
"""Generate the `hubSpots` block in every Resources/Parties/*.json from the
live qsopartyhub.com pages.

Source: http://qsopartyhub.com/{prefix}-spots.php  (fetched 2026-07-25)

RUN THIS AFTER ANY PARTY GENERATOR THAT DOES NOT WRITE `hubSpots` ITSELF —
gen_tnqp.py is the one, since it predates the hub map. A `gen_<party>.py`
rewrites its JSON file whole, so it silently drops any block it does not know
about, exactly as with gen_caveats.py and gen_callhistory.py.
`HubSpotSourceTests.testExactlyThirtyNinePartiesAreServedByTheHub` catches it.

Two things here are deliberate and load-bearing:

1. **The table URL comes from the page's iframe, never from the party id.**
   `caqp-table.php` exists and returns a well-formed, permanently empty table,
   while the California page actually embeds `qp-table.php` — which 302s. A
   prefix guess yields a poller that runs forever, never errors, and shows
   nothing. The iframe is the only authority.

2. **County aliases are diffed, not typed.** The hub keeps its own county
   token list per party. Where it disagrees with the sponsor's official list
   (Constitution Article 1), the app's value wins and the hub token is aliased
   inbound. Only Illinois needs one today: the hub spells Pulaski `PULS`, the
   official ILQP list `PULA`.

Re-run after any hub change:

    python3 docs/research/gen_hub_map.py

Writes the mapping into the party files and banks a compact record in
docs/research/qsopartyhub_map.json. Provenance: docs/research/qsopartyhub.md
"""
import json
import os
import re
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
PARTY_DIR = os.path.join(REPO, "Resources", "Parties")
MAP_OUT = os.path.join(HERE, "qsopartyhub_map.json")
BASE = "http://qsopartyhub.com"
UA = "QSOPartyLogger/1.0 (mapping generator; contact KE5CW)"

# Party id -> the prefix the hub uses. Most match; five do not, and two of
# those five turn out not to be served at all (verified below, not assumed).
HUB_PREFIX = {
    "alqp": "alqp", "azqp": "azqp", "coqp": "coqp", "cqp": "caqp",
    "hqp": "hiqp", "iaqp": "iaqp", "ilqp": "ilqp", "ksqp": "ksqp",
    "mdc": "mdcqp", "meqp": "meqp", "nhqp": "nhqp", "njqp": "njqp",
    "nyqp": "nyqp", "ohqp": "ohqp", "paqp": "paqp", "sdqp": "sdqp",
    "tnqp": "tnqp", "tqp": "txqp", "warun": "waqp",
}

EXPECTED_SERVED = 17
EXPECTED_ALIAS_PARTIES = {"ilqp"}


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def table_url(html):
    """The spot table this page actually embeds, or None."""
    m = re.findall(r'<iframe[^>]*class="responsive-iframe"[^>]*src="([^"]*)"', html)
    if not m:
        m = re.findall(r'<iframe[^>]*src="(%s/[^"]*)"' % re.escape(BASE), html)
    return m[-1] if m else None


def county_tokens(html):
    """Values the page's county <select> offers, minus the blank placeholder."""
    m = re.search(r'<select name="county".*?</select>', html, re.S | re.I)
    if not m:
        return set()
    return {v for v in re.findall(r'<option value="([^"]*)"', m.group(0)) if v}


def has_self_spot_form(html):
    return bool(re.search(r"<form id=subForm", html))


def main():
    served, skipped, records = {}, {}, {}

    for party_id, prefix in sorted(HUB_PREFIX.items()):
        post_url = f"{BASE}/{prefix}-spots.php"
        html = fetch(post_url)

        if html is None:
            skipped[party_id] = f"{prefix}-spots.php returns 404 — no hub page"
            continue

        embedded = table_url(html)
        if not embedded:
            skipped[party_id] = f"{prefix}-spots.php embeds no spot table"
            continue

        # An unfinished sponsor template points at the shared qp-table.php,
        # which redirects. Polling it would be silent and permanent failure.
        if embedded.rsplit("/", 1)[-1] == "qp-table.php":
            skipped[party_id] = (
                f"{prefix}-spots.php is an unfinished stub — embeds the shared "
                "qp-table.php, which redirects"
            )
            continue

        if not has_self_spot_form(html):
            skipped[party_id] = f"{prefix}-spots.php has no self-spot form"
            continue

        path = os.path.join(PARTY_DIR, f"{party_id}.json")
        with open(path, encoding="utf-8") as f:
            party = json.load(f)
        official = {c["abbr"] for c in party["counties"]}
        hub_tokens = county_tokens(html)

        # Where the hub's token is not one of ours, and the shapes otherwise
        # line up 1:1, the odd token out is a hub typo. Anything less tidy is
        # not guessed at — it is reported for a human.
        aliases = {}
        hub_only = sorted(hub_tokens - official)
        ours_only = sorted(official - hub_tokens)
        if hub_only or ours_only:
            if len(hub_only) == 1 and len(ours_only) == 1:
                aliases[hub_only[0]] = ours_only[0]
            else:
                sys.exit(
                    f"{party_id}: county lists diverge in a way this script will "
                    f"not guess at.\n  hub only: {hub_only}\n  ours only: {ours_only}"
                )

        served[party_id] = {"tableURL": embedded, "postURL": post_url}
        if aliases:
            served[party_id]["countyAliases"] = aliases
        records[party_id] = {
            "prefix": prefix,
            "countyTokens": len(hub_tokens),
            "officialCounties": len(official),
            "aliases": aliases,
        }

    # --- Assertions. A change here moves where the app polls, so it stops the
    # generator rather than quietly rewriting the mapping.
    assert len(served) == EXPECTED_SERVED, (
        f"expected {EXPECTED_SERVED} served parties, got {len(served)}: "
        f"{sorted(served)}\nskipped: {json.dumps(skipped, indent=2)}"
    )
    aliased = {p for p, v in served.items() if v.get("countyAliases")}
    assert aliased == EXPECTED_ALIAS_PARTIES, (
        f"expected county aliases only for {sorted(EXPECTED_ALIAS_PARTIES)}, "
        f"got {sorted(aliased)}"
    )
    for party_id, entry in served.items():
        assert entry["tableURL"].endswith("-table.php"), (
            f"{party_id}: unexpected table URL {entry['tableURL']}"
        )

    # --- Write the mapping into the party files.
    changed = []
    for party_id in sorted(HUB_PREFIX):
        path = os.path.join(PARTY_DIR, f"{party_id}.json")
        with open(path, encoding="utf-8") as f:
            party = json.load(f)
        before = json.dumps(party, sort_keys=True)
        if party_id in served:
            party["hubSpots"] = served[party_id]
        else:
            party.pop("hubSpots", None)
        if json.dumps(party, sort_keys=True) != before:
            with open(path, "w", encoding="utf-8") as f:
                json.dump(party, f, indent=2, ensure_ascii=False)
                f.write("\n")
            changed.append(party_id)

    with open(MAP_OUT, "w", encoding="utf-8") as f:
        json.dump(
            {
                "source": f"{BASE}/{{prefix}}-spots.php",
                "fetched": "2026-07-25",
                "served": served,
                "skipped": skipped,
                "detail": records,
            },
            f, indent=2, ensure_ascii=False, sort_keys=True,
        )
        f.write("\n")

    print(f"served {len(served)} parties; skipped {len(skipped)}")
    for party_id, why in sorted(skipped.items()):
        print(f"  skip {party_id}: {why}")
    print(f"updated {len(changed)} party files: {', '.join(changed) or '(none)'}")


if __name__ == "__main__":
    main()
