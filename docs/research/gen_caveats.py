#!/usr/bin/env python3
"""Populate every bundled party's `caveats` array.

Article 2: `detail` is COPIED from the party's own notes by
`extract_caveats.items()`, never retyped. Only `kind` and `summary` below are
authored, because a classification is judgement rather than data.

The classification rule, applied to each item's full text:

  exportBlocking  the log this app writes cannot be submitted as-is
  scoreAffecting  the app's total will differ from the sponsor's
  ruleInference   the sponsor's text is ambiguous and this app inferred
  provenance      the source is stale/archived; costs the operator nothing now
  cosmetic        recorded for completeness; no scoring or export consequence

Items that only RECAP earlier ones ("(1) and (2) above are...") are dropped:
they carry no new fact, and repeating them would put the same warning on
screen twice. Where such a recap does introduce a new point, it is classified
on that point alone.

RUN THIS AFTER ANY PARTY GENERATOR. A `gen_<party>.py` rewrites its JSON file
whole and knows nothing about caveats, so it silently drops them. That is caught
rather than trusted: `CaveatRosterTests.testEveryBundledPartyWithMarkedNotesHasCaveats`
fails for any bundled party that has OPEN QUESTION / KNOWN LIMITATION prose but
no typed caveats. Re-running this script is idempotent and fixes it.

Run:  python3 docs/research/gen_caveats.py
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract_caveats import items  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
PARTIES = os.path.join(HERE, "..", "..", "Resources", "Parties")

# party id -> [(item index in notes, kind, summary)]
# A `None` index means the summary stands alone with no prose to copy.
KINDS = {
    "alqp": [],
    "arqp": [
        (0, "provenance", "The sponsor prints no contest hours; the window comes from the Challenge calendar."),
        (1, "scoreAffecting", "The 500-point live-streaming bonus is not applied."),
    ],
    "azqp": [
        (0, "ruleInference", "Arizona counting itself as a multiplier is inferred, and the rules are still the 2025 revision."),
    ],
    "bcqp": [
        (0, "cosmetic", "ADIF export writes “BC,<district>” in the CNTY field."),
        (1, "ruleInference", "Whether British Columbia counts as its own province multiplier is inferred — shipped as not counting."),
    ],
    "coqp": [],
    "cqp": [],
    "deqp": [
        (0, "provenance", "The sponsor prints no contest hours; the window comes from the Challenge calendar."),
        (1, "scoreAffecting", "A Delaware-to-Delaware contact is paid ten times the sponsor’s rate."),
        (2, "scoreAffecting", "Contacts on 6 m and up are paid at the HF rate."),
        (3, "scoreAffecting", "The 50-point electronic-submission bonus is not applied."),
        (4, "cosmetic", "FT8/FT4 use a Field Day exchange grammar that is not modelled."),
    ],
    "fqp": [
        (0, "scoreAffecting", "Maritime-mobile ITU regions are credited as DXCC countries, not as their own multiplier class."),
        (1, "ruleInference", "The out-of-state restriction is implied by the rules rather than stated."),
    ],
    "gaqp": [
        (0, "cosmetic", "The band list is inferred; multipliers count per mode, so no band list can change the score."),
        (1, "ruleInference", "No maximum for simultaneous counties is stated; the schema default of four ships."),
    ],
    "hqp": [
        (0, "provenance", "The sponsor’s stated 36 hours and its own local times disagree; the shipped window matches both."),
    ],
    "iaqp": [
        (0, "ruleInference", "The rules page is still titled 2025, and whether outside stations may work only Iowa is inferred."),
    ],
    "idqp": [
        (0, "scoreAffecting", "QRP QSOs are worth 5 points to the sponsor and are paid the normal rate here."),
        (1, "scoreAffecting", "The dormant-county bonus is not applied."),
        (2, "ruleInference", "The sponsor’s own date block contradicts itself; three derivations agree on the shipped window."),
    ],
    "ilqp": [
        (0, "scoreAffecting", "Dupes across CW and digital are not flagged."),
        (1, "scoreAffecting", "FT4/FT8 contacts earn no credit from the sponsor but are scored here."),
        (2, "provenance", "The rules are the 2025 edition; the date follows the sponsor’s own printed formula."),
    ],
    "in7qpne": [
        (0, "scoreAffecting", "The score here is indicative only — the four sponsors score differently. Logging and export are correct."),
        (1, "cosmetic", "Bands and modes are the union of four contests, so a QSO one member would ignore can still be logged."),
    ],
    "inqp": [],
    "ksqp": [],
    "kyqp": [
        (0, "scoreAffecting", "The 100-point log-submission bonus is not applied."),
        (1, "ruleInference", "County-line permission is per category in the rules and per party in this app."),
    ],
    "laqp": [
        (0, "provenance", "The 2026 date is derived — the rules still print 2025 and the sponsor’s dates page is missing."),
        (1, "scoreAffecting", "CW and digital are one mode for the sponsor and two here, which moves the score."),
    ],
    "mdc": [],
    "meqp": [
        (0, "ruleInference", "Whether Maine counts as its own state multiplier is not stated; shipped as not counting."),
    ],
    "miqp": [
        (0, "provenance", "Partial only because the 2026 rules came from an archive rather than a live page."),
    ],
    # The exportBlocking entry closed 2026-07-27: name exchanges landed
    # (forced in by the NAQP pair) and MNQP's flag is on, so the name is
    # logged and exported. The notes record the closure per Article 20.
    "mnqp": [
        (0, "provenance", "The 2026 rules were recovered from a web archive and cannot be re-fetched from the sponsor."),
    ],
    # The NAQP pair's caveats are also written by gen_naqp.py, which builds
    # notes and caveats from the same constants — these entries must match it
    # exactly, so running either generator leaves the files identical.
    "naqpcw": [
        (0, "scoreAffecting", "A Dominican Republic (HI) contact is credited as Hawaii - work both on one band and the score is one multiplier low."),
        (1, "cosmetic", "Entrants outside North America: contacts with other non-NA stations are credited here but removed by the sponsor. No effect on NA entrants."),
        (2, "cosmetic", "Log United Nations HQ as 4U1 - the checklist's '4U1/u' cannot be typed because '/' separates county lines."),
    ],
    "naqpssb": [
        (0, "scoreAffecting", "A Dominican Republic (HI) contact is credited as Hawaii - work both on one band and the score is one multiplier low."),
        (1, "cosmetic", "Entrants outside North America: contacts with other non-NA stations are credited here but removed by the sponsor. No effect on NA entrants."),
        (2, "cosmetic", "Log United Nations HQ as 4U1 - the checklist's '4U1/u' cannot be typed because '/' separates county lines."),
    ],
    "moqp": [
        (0, "scoreAffecting", "The 40 and 80 m daytime bonus is not applied."),
        (1, "scoreAffecting", "The 100-point electronic-submission bonus is not applied."),
        (2, "scoreAffecting", "In-state rovers are short the self-activation multiplier for each county they work 50+ QSOs from."),
        (4, "ruleInference", "The county-line cap and the out-of-state restriction are both this app’s defaults, not the sponsor’s numbers."),
    ],
    "msqp": [
        (0, "scoreAffecting", "Grid-square multipliers are not counted, and this is the biggest gap here."),
        (1, "scoreAffecting", "The FT4/8 exchange is a grid square, not a location."),
        (2, "scoreAffecting", "RTTY and FT4/8 are separate modes to the sponsor and one mode here."),
        (3, "scoreAffecting", "Portable and mobile stations score differently, which is not modelled."),
        (5, "ruleInference", "County lines are unmentioned in the rules; a two-county entry is refused on the reading that silence is not permission."),
    ],
    "ncqp": [
        (0, "scoreAffecting", "Score is a floor: the “Rarest of NC” 10× QSO points are not applied, and this is the largest scoring gap in the app."),
        (1, "scoreAffecting", "The 500-point rare-county sweep is not applied."),
        (2, "scoreAffecting", "In-state entrants are short the self-activation multiplier for each county they operate from."),
    ],
    "ndqp": [
        (0, "scoreAffecting", "A North Dakota station cannot log a DX country the way the rules ask."),
        (1, "cosmetic", "The “no FT8” rule cannot be enforced by this app."),
    ],
    "neqp": [
        (0, "provenance", "The rules’ UTC figures and their local-time glosses are an hour apart; the sponsor’s UTC ships."),
        (1, "ruleInference", "Whether the bonus stations pay once or per QSO is ambiguous; the conservative reading ships."),
        (2, "cosmetic", "The FT8/FT4 competition is a separate contest with its own scoring, and is out of scope."),
        (3, "scoreAffecting", "Satellite QSOs are worth 4 points here and score as whichever mode they are logged under."),
        (4, "scoreAffecting", "The rare-grid bonus is not applied."),
    ],
    "newenglandqp": [
        (0, "ruleInference", "The sponsor counts 14 Canadian areas but names none of them; NF and LB ship as the split."),
    ],
    "nhqp": [
        (0, "ruleInference", "Whether NH counts itself as a multiplier, and whether outside stations may work only NH, are both inferred."),
    ],
    "njqp": [
        (0, "ruleInference", "The sponsor’s table has no DC row, so DC cannot be logged at all here."),
    ],
    "nmqp": [
        (0, "scoreAffecting", "DX collapses to one multiplier where the sponsor counts entities. Affects New Mexico entrants only."),
        (1, "provenance", "The W1AW/5 bonus is 2026-only and must be removed when the 2027 rules are read."),
    ],
    "nyqp": [
        (0, "cosmetic", "The sponsor’s own sample log uses bands above 70 cm, which cannot be logged here."),
        (1, "provenance", "The rules are the 2025 edition; the date comes from the formula in their own title block."),
    ],
    "ohqp": [],
    "okqp": [
        (0, "cosmetic", "FT8 and FT4 are barred by the sponsor and this app cannot enforce it."),
        (1, "cosmetic", "The sponsor wants a single free-text Cabrillo CATEGORY line; this app writes the standard split headers."),
        (2, "ruleInference", "Whether Oklahoma counts as its own state multiplier is inferred; shipped as counting."),
    ],
    "oqp": [
        (0, "scoreAffecting", "The five 10-point club stations are not modelled."),
        (1, "scoreAffecting", "The literal “DX” token cannot be logged."),
        (2, "scoreAffecting", "The activation bonus can be over-credited, bounded at 300 points per multiplier area."),
        (3, "ruleInference", "Whether 60 m is legal is ambiguous; eight bands ship without it."),
    ],
    "paqp": [
        (0, "cosmetic", "630 m, 2200 m and anything above 70 cm are legal here but cannot be logged."),
        (1, "provenance", "The rules are the 2025 revision; the dates are confirmed by the sponsor’s banner and formula."),
    ],
    "qcqp": [
        (0, "scoreAffecting", "The mobile activation bonus can be over-credited when one station is worked on three bands."),
        (1, "ruleInference", "Whether 60 m is legal is ambiguous; seven bands ship without it."),
    ],
    "scqp": [
        (0, "scoreAffecting", "SC mobile and expedition stations undercount their multipliers."),
        (1, "ruleInference", "The rules cap no county-line count; this app’s default of four ships."),
    ],
    "sdqp": [
        (0, "ruleInference", "Whether South Dakota counts itself, and whether outside stations may work only SD, are both inferred."),
    ],
    "sevenqp": [
        (0, "cosmetic", "The sponsor bars WSJT modes and this app cannot enforce it."),
        (1, "ruleInference", "No maximum for simultaneous counties is stated; the schema default of four ships."),
    ],
    "tnqp": [
        (0, "provenance", "The rules document is titled 2025 and no 2026 revision exists yet."),
    ],
    "tqp": [],
    "vaqp": [
        (0, "scoreAffecting", "Contacts with Virginia mobiles, expeditions and rovers are worth 3 points and are paid 1 or 2 here."),
        (1, "scoreAffecting", "The bonus stations are not shipped; confirm the list before submitting."),
        (2, "scoreAffecting", "In-state rovers are short the self-activation multiplier for each county or city they work ten stations from."),
    ],
    "vtqp": [
        (0, "scoreAffecting", "Score is a floor: the fractional power multiplier is not applied. Multiply by 2 for QRP or 1.5 for low power yourself."),
        (1, "scoreAffecting", "The W1AW/1 bonus is credited to Vermont entrants, who the sponsor says get nothing."),
        (2, "scoreAffecting", "RTTY and FT8 are one mode here and two for the sponsor."),
        (3, "cosmetic", "30, 17 and 12 m ship as fully valid although the sponsor allows them for FT8/FT4 only."),
        (4, "scoreAffecting", "Club-station and grid-square multipliers are missing entirely; add both by hand."),
        (5, "ruleInference", "Whether Vermont counts itself, and whether 60 m is legal, are both inferred."),
    ],
    "warun": [
        (0, "scoreAffecting", "A DXCC prefix that equals a state or province code is read as that state, which can leave the 10-DXCC allowance under-used."),
    ],
    "wiqp": [
        (0, "scoreAffecting", "Score is a floor: the fractional power multiplier is not applied. Multiply by 2 for QRP or 1.5 for low power yourself."),
        (1, "scoreAffecting", "The 500-point county bonus is credited for your home county too; subtract it."),
        (2, "scoreAffecting", "The W9FK bonus is credited above 50 MHz, where the sponsor pays nothing; subtract it."),
        (4, "cosmetic", "33 cm and 23 cm are plausibly legal here and cannot be logged at all."),
    ],
}

VALID_KINDS = {"exportBlocking", "scoreAffecting", "ruleInference", "provenance", "cosmetic"}


def main():
    files = sorted(f for f in os.listdir(PARTIES) if f.endswith(".json"))
    assert len(files) == 48, f"expected 48 bundled parties, found {len(files)}"

    unclassified = []
    badge_count = 0
    total = 0

    for name in files:
        path = os.path.join(PARTIES, name)
        with open(path) as f:
            party = json.load(f)
        pid = party["id"]

        if pid not in KINDS:
            unclassified.append(pid)
            continue

        bodies = {i: body for _, i, _, body in items(party.get("notes"))}
        caveats = []
        for index, kind, summary in KINDS[pid]:
            assert kind in VALID_KINDS, f"{pid}: bad kind {kind!r}"
            caveat = {"kind": kind, "summary": summary}
            if index is not None:
                assert index in bodies, f"{pid}: no item [{index}] in notes"
                # Article 2 -- the prose is copied, never retyped.
                caveat["detail"] = bodies[index]
            caveats.append(caveat)

        total += len(caveats)
        if any(c["kind"] in ("exportBlocking", "scoreAffecting") for c in caveats):
            badge_count += 1

        if caveats:
            party["caveats"] = caveats
        else:
            party.pop("caveats", None)

        with open(path, "w") as f:
            json.dump(party, f, indent=2, ensure_ascii=False)
            f.write("\n")

    assert not unclassified, f"unclassified parties: {unclassified}"
    print(f"{total} caveats across {len(files)} parties")
    print(f"{badge_count} parties raise a warning (was 39 under verified: partial)")


if __name__ == "__main__":
    main()
