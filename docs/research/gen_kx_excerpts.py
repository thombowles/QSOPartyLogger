#!/usr/bin/env python3
"""Bank the KX2/KX3 owner's-manual passages the KX driver and README rest on.

Article 2 — never hand-type data that exists in a file. Every line of the two
`*_excerpts.txt` files this writes is sliced out of `pdftotext -layout` output,
so a typo in a menu name or a jack pinout is impossible.

Usage, from a directory holding the two extracted texts:

    pdftotext -layout "KX2 owner's man B2.pdf"            kx2_owners_b2.txt
    pdftotext -layout "E740163 KX3 Owner's man Rev C5.pdf" kx3_owners_c5.txt
    python3 gen_kx_excerpts.py --source-dir .

The line ranges below were located by searching the extracted text for the
headings named in each `note`; they are asserted against a fingerprint so the
script fails loudly rather than banking the wrong passage if the extraction
ever shifts.
"""

from __future__ import annotations

import argparse
import pathlib
import sys

# (first_line, last_line, note, fingerprint that must appear in the slice)
KX2_RANGES = [
    (194, 212, "CW Key/Keyer Paddle — the two keying inputs and the KEY jack",
     "two CW keying inputs"),
    (233, 260, "Computer/Amp Keying (ACC) — the CAT jack pinout, and key OUT",
     "Ring 2: *Key Out"),
    (1543, 1551, "MENU:CW KEY1 / CW KEY2 — HAND, the computer keying input",
     "external keying device"),
    (1016, 1060, "Digital Voice Recorder (DVR) — two messages, MSG then digit",
     "two SSB-mode transmit voice"),
    (1795, 1806, "MENU:VOX MD — hit-the-key transmit in CW",
     "hit-the-key"),
    (1676, 1682, "MENU:RS232 — the CAT rate", "RS232"),
]

KX3_RANGES = [
    (135, 150, "CW keying inputs and the KEY jack", "two CW keying inputs"),
    (150, 192, "Computer/Control Port (ACC1) and Keyline Out/GPIO (ACC2)",
     "keyline"),
    (1908, 1918, "MENU:CW KEY1 / CW KEY2 — HAND, the computer keying input",
     "external keying device"),
    (1074, 1096, "Digital Voice Recorder (DVR) — two messages, MSG then digit",
     "two voice messages"),
]

KX2_HEADER = """\
Elecraft KX2 Owner's Manual, Revision B2 — the passages behind keying the KX2
from a computer, and its two on-board voice memories
==============================================================================

Source: KX2 owner's man B2.pdf
https://ftp.elecraft.com/KX2/Manuals%20Downloads/KX2%20owner's%20man%20B2.pdf
Last-Modified: Mon, 27 Mar 2023 18:52:53 GMT; fetched 2026-08-22.
Extracted with `pdftotext -layout`; sliced by gen_kx_excerpts.py.

Load-bearing here: the CW KEY1 menu entry is the authority for the KEY jack
accepting a computer as a keying input, and the ACC pinout is the authority for
the CAT jack carrying no key *input* at all -- which together are why the KX is
keyed over CAT by this app and the K3 is not. See kx_cw_keying.md.

Two columns of the manual's page layout are interleaved by `-layout`; the
right-hand column of each slice belongs to a neighbouring section and is kept
rather than edited out, because editing is what Article 2 forbids.
"""

KX3_HEADER = """\
Elecraft KX3 Owner's Manual, Revision C5 — the same passages as the KX2's, for
the other radio the elecraft-kx descriptor serves
==============================================================================

Source: E740163 KX3 Owner's man Rev C5.pdf
https://ftp.elecraft.com/KX3/Manuals%20Downloads/E740163%20KX3%20Owner's%20man%20Rev%20C5.pdf
Last-Modified: Thu, 16 Nov 2017 01:06:57 GMT; fetched 2026-08-22.
Extracted with `pdftotext -layout`; sliced by gen_kx_excerpts.py.

The KX3's CW KEY1 wording is identical to the KX2's, which is what lets one
driver serve both. Its ACC1 is the CAT port and its ACC2 is a keyline *output*
plus a GPIO -- configurable as a PTT input, never as a CW key.
"""

RULE = "-" * 74


def slice_manual(text_path: pathlib.Path, ranges, header: str) -> str:
    # The ranges below were located with grep, so this must count lines exactly
    # as grep does -- which takes avoiding two separate traps, each of which
    # silently shifts every range after the first page:
    #
    #   * `splitlines()` breaks on form feeds, and pdftotext writes one at every
    #     page break. grep does not. So: `split("\n")`.
    #   * `read_text()` translates universal newlines, so a lone \r (the KX3's
    #     extraction has them, the KX2's does not) becomes an extra \n that grep
    #     never counted. So: read bytes and decode by hand.
    #
    # The fingerprint assertion in the caller is what caught both of these.
    raw = text_path.read_bytes().decode("utf-8", errors="replace")
    lines = raw.split("\n")
    out = [header]
    for first, last, note, fingerprint in ranges:
        if last > len(lines):
            sys.exit(f"{text_path.name}: lines {first}-{last} run past EOF ({len(lines)})")
        body = "\n".join(lines[first - 1:last]).rstrip()
        if fingerprint not in body:
            sys.exit(
                f"{text_path.name}: lines {first}-{last} ({note}) no longer contain "
                f"{fingerprint!r} -- the extraction shifted; re-locate the range"
            )
        out.append(f"{RULE}\n{note} (extracted lines {first}-{last})\n{RULE}\n{body}\n")
    return "\n".join(out)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=pathlib.Path, required=True,
                        help="directory holding kx2_owners_b2.txt and kx3_owners_c5.txt")
    parser.add_argument("--out-dir", type=pathlib.Path,
                        default=pathlib.Path(__file__).resolve().parent)
    args = parser.parse_args()

    for stem, ranges, header in (
        ("kx2_owners_b2", KX2_RANGES, KX2_HEADER),
        ("kx3_owners_c5", KX3_RANGES, KX3_HEADER),
    ):
        source = args.source_dir / f"{stem}.txt"
        if not source.exists():
            sys.exit(f"missing {source} -- run pdftotext -layout first (see the docstring)")
        target = args.out_dir / f"{stem}_excerpts.txt"
        target.write_text(slice_manual(source, ranges, header), encoding="utf-8")
        print(f"wrote {target} ({len(ranges)} passages)")


if __name__ == "__main__":
    main()
