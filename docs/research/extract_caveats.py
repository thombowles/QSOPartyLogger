#!/usr/bin/env python3
"""Extract the OPEN QUESTION / KNOWN LIMITATION items from every party's notes.

Article 2: the `detail` text of a caveat is COPIED from the notes, never
retyped. This does the copying. The `kind` and `summary` fields are the
maintainer's judgement and are supplied separately, in caveat_kinds.py.

Mirrors PartyDefinition.operatorAlerts: same marker regex, same
first-sentence rule (terminators are . ? and !), so what the classification
sees is what the app would have shown.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PARTIES = os.path.join(HERE, "..", "..", "Resources", "Parties")

MARKER = re.compile(r"(OPEN QUESTIONS?|KNOWN LIMITATIONS?)\s*(\d+)?\s*[:\-]?\s*", re.I)


def first_sentence(text):
    text = text.strip()
    if not text:
        return None
    m = re.search(r"[.?!]", text)
    return text[: m.end()].strip() if m else text


def items(notes):
    """Every marked item: (marker_kind, index, headline, full_body)."""
    if not notes:
        return []
    marks = list(MARKER.finditer(notes))
    out = []
    for i, m in enumerate(marks):
        start = m.end()
        end = marks[i + 1].start() if i + 1 < len(marks) else len(notes)
        body = notes[start:end].strip()
        if not body:
            continue
        out.append((m.group(1).upper(), i, first_sentence(body), body))
    return out


def main():
    for path in sorted(os.listdir(PARTIES)):
        if not path.endswith(".json"):
            continue
        with open(os.path.join(PARTIES, path)) as f:
            d = json.load(f)
        found = items(d.get("notes"))
        print(f"### {d['id']}  ({len(found)} items)")
        for kind, i, headline, body in found:
            print(f"  [{i}] {kind}: {headline}")
        print()


if __name__ == "__main__":
    main()
