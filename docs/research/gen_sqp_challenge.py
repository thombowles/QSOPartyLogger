#!/usr/bin/env python3
"""Generate Resources/Challenge/sqp_challenge_2026.json from the committed
State QSO Party Challenge calendar text (Constitution Article 2: never
hand-type data that exists in a file).

Sources (see sqp_challenge_rules.md):
  - 2026_state_qso_party_calendar.txt — the challenge's own calendar PDF,
    fetched 2026-07-24, pdftotext -layout.
  - SITE_NAMES — the homepage's "47 Approved Contests" list, stateqsoparty.com,
    read 2026-07-25. The two lists must agree 1:1 (alias table below for the
    two spelling differences).

Bundled-party mapping is asserted against the actual party files in
Resources/Parties/ — Maine (meqp) is deliberately unmapped: it is not on the
2026 approved list.
"""

import json
import pathlib
import re
from datetime import datetime, timedelta, timezone

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent
CALENDAR = HERE / "2026_state_qso_party_calendar.txt"
OUT = REPO / "Resources" / "Challenge" / "sqp_challenge_2026.json"

# stateqsoparty.com homepage, "47 Approved Contests", read 2026-07-25.
SITE_NAMES = [
    "7th Call Area QSO Party", "Atlantic Canada QSO Party", "Alabama QSO Party",
    "Arizona QSO Party", "Arkansas QSO Party", "British Columbia QSO Party",
    "California QSO Party", "Canadian Prairies QSO Party", "Colorado QSO Party",
    "Delaware QSO Party", "Florida QSO Party", "Georgia QSO Party",
    "Hawaii QSO Party", "Idaho QSO Party", "Illinois QSO Party",
    "Indiana QSO Party", "Iowa QSO Party", "Kansas QSO Party",
    "Kentucky QSO Party", "Louisiana QSO Party", "Maryland/DC QSO Party",
    "Michigan QSO Party", "Minnesota QSO Party", "Mississippi QSO Party",
    "Missouri QSO Party", "Nebraska QSO Party", "New England QSO Party",
    "New Hampshire QSO Party", "New Jersey QSO Party", "New Mexico QSO Party",
    "New York QSO Party", "North Carolina QSO Party", "North Dakota QSO Party",
    "Ohio QSO Party", "Oklahoma QSO Party", "Ontario QSO Party",
    "Pennsylvania QSO Party", "Quebec QSO Party", "South Carolina QSO Party",
    "South Dakota QSO Party", "Tennessee QSO Party", "Texas QSO Party",
    "Vermont QSO Party", "Virginia QSO Party", "Washington State Salmon Run",
    "West Virginia QSO Party", "Wisconsin QSO Party",
]
assert len(SITE_NAMES) == 47, f"site list must carry 47 names, got {len(SITE_NAMES)}"
assert len(set(SITE_NAMES)) == 47, "site names not unique"

# Calendar spelling -> site spelling (the only two rows that differ).
CALENDAR_ALIASES = {
    "Washington St Salmon Run": "Washington State Salmon Run",
    "Maryland-DC QSO Party": "Maryland/DC QSO Party",
}

# Site name -> bundled party id. Maine QSO Party is absent from the approved
# list, so meqp appears nowhere here — asserted below against Resources/Parties.
BUNDLED_BY_SITE_NAME = {
    "Alabama QSO Party": "alqp",
    "Arizona QSO Party": "azqp",
    "British Columbia QSO Party": "bcqp",
    "California QSO Party": "cqp",
    "Colorado QSO Party": "coqp",
    "Hawaii QSO Party": "hqp",
    "Idaho QSO Party": "idqp",
    "Illinois QSO Party": "ilqp",
    "Iowa QSO Party": "iaqp",
    "Kansas QSO Party": "ksqp",
    "Louisiana QSO Party": "laqp",
    "Maryland/DC QSO Party": "mdc",
    "Minnesota QSO Party": "mnqp",
    "Mississippi QSO Party": "msqp",
    "Missouri QSO Party": "moqp",
    "North Carolina QSO Party": "ncqp",
    "Georgia QSO Party": "gaqp",
    "New Hampshire QSO Party": "nhqp",
    "New Mexico QSO Party": "nmqp",
    "New Jersey QSO Party": "njqp",
    "New York QSO Party": "nyqp",
    "Ohio QSO Party": "ohqp",
    "Oklahoma QSO Party": "okqp",
    "Pennsylvania QSO Party": "paqp",
    "South Carolina QSO Party": "scqp",
    "South Dakota QSO Party": "sdqp",
    "Tennessee QSO Party": "tnqp",
    "Texas QSO Party": "tqp",
    "Vermont QSO Party": "vtqp",
    "Virginia QSO Party": "vaqp",
    "Washington State Salmon Run": "warun",
    "Wisconsin QSO Party": "wiqp",
}

ROW = re.compile(
    r"^\s*(\d{1,2}/\d{1,2}/\d{4})\s+(\d{4})Z\s+(\d{1,2}/\d{1,2}/\d{4})\s+(\d{4})Z\s+(.+?)\s*$"
)


def instant(date_s: str, time_s: str) -> datetime:
    m, d, y = (int(x) for x in date_s.split("/"))
    base = datetime(y, m, d, tzinfo=timezone.utc)
    # The calendar writes end-of-day as 2400Z.
    return base + timedelta(hours=int(time_s[:2]), minutes=int(time_s[2:]))


def main() -> None:
    windows_by_name: dict[str, list[tuple[datetime, datetime]]] = {}
    for line in CALENDAR.read_text().splitlines():
        m = ROW.match(line)
        if not m:
            continue
        start = instant(m.group(1), m.group(2))
        end = instant(m.group(3), m.group(4))
        assert end > start, f"window inverted: {line!r}"
        name = CALENDAR_ALIASES.get(m.group(5), m.group(5))
        windows_by_name.setdefault(name, []).append((start, end))

    names = set(windows_by_name)
    assert len(names) == 47, f"expected 47 distinct contests, got {len(names)}: {sorted(names)}"
    assert names == set(SITE_NAMES), (
        f"calendar/site mismatch: only-calendar={sorted(names - set(SITE_NAMES))}, "
        f"only-site={sorted(set(SITE_NAMES) - names)}"
    )
    assert "Maine QSO Party" not in names, "Maine is not approved for 2026 — see rules doc"

    bundled_ids = {json.loads(p.read_text())["id"] for p in (REPO / "Resources" / "Parties").glob("*.json")}
    assert bundled_ids, "no bundled parties found"
    mapped = set(BUNDLED_BY_SITE_NAME.values())
    assert len(mapped) == len(BUNDLED_BY_SITE_NAME), "duplicate party id in mapping"
    assert mapped == bundled_ids - {"meqp"}, (
        f"mapping must cover exactly the bundled parties minus meqp: "
        f"missing={sorted((bundled_ids - {'meqp'}) - mapped)}, extra={sorted(mapped - bundled_ids)}"
    )
    assert set(BUNDLED_BY_SITE_NAME) <= names, "mapping names must be approved-contest names"

    contests = [
        {
            "name": name,
            "partyID": BUNDLED_BY_SITE_NAME.get(name),
            "windows": [
                {
                    "start": s.strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "end": e.strftime("%Y-%m-%dT%H:%M:%SZ"),
                }
                for s, e in sorted(windows_by_name[name])
            ],
        }
        for name in sorted(windows_by_name, key=lambda n: min(windows_by_name[n])[0])
    ]

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "year": 2026,
                "source": (
                    "stateqsoparty.com 2026 calendar PDF (fetched 2026-07-24) + homepage "
                    "approved list (read 2026-07-25); docs/research/sqp_challenge_rules.md. "
                    "Bundled parties keep their own sponsor-verified schedules — these "
                    "windows are display data for non-bundled contests (the calendar's "
                    "NJQP row is known-wrong; the sponsor says Sep 12)."
                ),
                "approvedContests": contests,
            },
            indent=1,
        )
        + "\n"
    )
    print(f"wrote {OUT.relative_to(REPO)}: {len(contests)} contests, "
          f"{sum(len(c['windows']) for c in contests)} windows, "
          f"{sum(1 for c in contests if c['partyID'])} bundled")


if __name__ == "__main__":
    main()
