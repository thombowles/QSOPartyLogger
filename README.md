# QSO Party Logger

Mac-native QSO Party contest logger (SwiftUI, macOS 15+) with first-class
county-line support, live rules-based scoring, Elecraft K3 CAT control with
direct DTR/RTS CW keying, and ADIF / Cabrillo export.

Built for KE5CW. Bundled parties, all with official county data:

- **Alabama QSO Party** (Jul 25–26, 2026) — verified against the official 2026
  rules: 2 pts CW/phone, mults once **per mode**, DX-prefix mults, DC→MD,
  county-line sitting not permitted, phone/CW only.
- **Kansas QSO Party** (Aug 29–30, 2026) — verified against the official 2026
  rules; 1×1 word tracker included.
- **Texas QSO Party** (Sep 19–20, 2026) — rules verified against txqp.net
  2026 (bands: all except 60/30/17/12; Cabrillo name `TXQP` per WA7BNM;
  robot site not yet live).

Research for seven more (MD-DC, Hawaii, Ohio, Tennessee, Colorado, Iowa,
New Jersey, New Hampshire, WA Salmon Run) is complete and banked in the
project notes; definitions land as they're built.

## Features

- **County-line logging, N1MM style.** Enter `LIN/AND` (or set your own
  location to up to 4 counties) and every county pair becomes its own log row —
  exactly what KSQP rule 11 requires ("a separate QSO must be logged for each
  county"). Rows share a group marker so they edit/delete together.
- **County abbreviation validation** against each party's official list
  (KSQP: 105 3-letter, TQP: 254 4-letter, both generated from the sponsors'
  official files). Typos get suggestions (`LNI` → `LIN`); the home-state token
  is rejected (Kansas stations always send a county).
- **Live scoring per party rules**: points by mode, single-count multipliers,
  KSQP's first-KS-county-counts-as-KS-state rule, dupes flagged but kept
  (sponsors want them), KS0KS +100 bonus, TQP mobile 5-county bonuses, and a
  "NEW MULT" badge before you log. KSQP 1×1 word tracker (KANSAS, QSOPARTY,
  SUNFLOWER, YELLOWBRICKROAD) with wildcard handling.
- **Elecraft K3/K3S/KX3/KX2 CAT** over serial (4800–38400 baud): live
  frequency/mode/TX polling (`IF;` — verified against Programmer's Reference
  revs F2 and G5), band stamped onto each QSO.
- **CW keying two ways**: direct DTR/RTS line keying with sub-millisecond
  software timing (8–50 WPM, optional PTT line with lead/tail), or the K3's
  internal keyer (`KY`). F1–F8 messages with `{MYCALL} {CALL} {RST} {EXCH}`
  macros; **Esc aborts instantly**.
- **Exports**: Cabrillo V3 (per-county-line QSO rows, category headers,
  claimed score) and ADIF 3.1.4 (`CNTY`/`MY_CNTY` with full county names,
  `STX_STRING`/`SRX_STRING`, group ids in an APP_ field).
- **Documents**: each contest is a `.qplog` file (JSON) with autosave + undo.

## K3 wiring for direct CW keying

1. Connect the K3's RS-232 port (or KUSB adapter) to the Mac.
2. On the K3: `CONFIG:PTT-KEY` (menu 103) → set to `RTS-DTR` (PTT on RTS,
   CW key on DTR) — the app's default mapping, changeable in the radio bar.
3. In the app: pick the port, 38400 baud, Connect. The app deasserts both
   lines at open so the rig never keys on connect.

No extra interface is needed — same single-cable setup N1MM uses.

## Adding a QSO party (no code)

Drop a JSON file in `~/Library/Application Support/QSOPartyLogger/Parties/`
(sandboxed apps: the container's equivalent path). Files there override
bundled parties with the same `id`. Schema (see `Resources/Parties/ksqp.json`
for a complete example):

```jsonc
{
  "schemaVersion": 1,
  "id": "mnqp",
  "name": "Minnesota QSO Party",
  "cabrilloContest": "MN-QSO-PARTY",
  "homeState": "MN",
  "countyAbbrLength": 3,
  "validBands": ["160m", "80m", "40m", "20m", "15m", "10m", "6m", "2m"],
  "points": { "phone": 1, "cw": 2, "digital": 2 },
  "dupeScope": "bandMode",
  "multipliers": {
    "inState":  { "classes": ["state", "county", "province", "dx"],
                  "homeStateCountsViaCounty": false, "countScope": "once" },
    "outState": { "classes": ["county"],
                  "homeStateCountsViaCounty": false, "countScope": "once" }
  },
  "bonuses": [
    { "type": "workStation", "call": "W0AA", "points": 100 },
    { "type": "mobileCountyCount", "per": 5, "points": 500 }
  ],
  "oneByOne": null,
  "counties": [ { "abbr": "AIT", "name": "Aitkin" } ],
  "notes": "Verify against current-year rules."
}
```

Malformed files are reported with the reason; the app keeps running with the
bundled parties.

## Adding a radio

Implement `RadioDriver` (see `Sources/Hardware/Radio/ElecraftK3Driver.swift`)
and append a `RadioDescriptor` in `RadioRegistry.all`. Kenwood-style ASCII
radios can reuse most of the K3 driver's parsing approach.

## Building

```bash
xcodegen generate
xcodebuild -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger build
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS'
```

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). 100 unit tests cover the scoring engine, county
data, exporters, K3 protocol, and keyer timing.

## Data provenance

- KSQP: rules + county abbreviations fetched from ksqsoparty.org (2026 rules
  PDF, official mults PDF) on 2026-07-23. County JSON generated by script
  from the official file — never hand-typed.
- TQP: rules from txqp.net; counties from the official `txcounty.zip`
  (2014 revision, current as of fetch). Marked `verified: partial` — confirm
  band list and current-year details before submitting.
- DC is accepted as a loggable state token (counted with states); strictly,
  KSQP rules enumerate 50 states — sponsors' checkers accept DC.
