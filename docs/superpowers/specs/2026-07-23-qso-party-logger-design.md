# QSO Party Logger — Design

**Date:** 2026-07-23 · **Author:** Claude (autonomous session for Tom, KE5CW)
**Status:** Approved-by-default (autonomous build per explicit request: "build it and test in Xcode"). Key decisions and assumptions are flagged so Tom can redirect any of them.

## 1. Purpose

A world-class, Mac-native (SwiftUI) QSO Party contest logger with first-class support for **county-line operation** (N1MM-style: one logged line per county), per-party **county abbreviation validation**, **live rules-based scoring with bonus stations**, **Elecraft K3 CAT control + direct CW keying (DTR/RTS)** over serial, and **ADIF / Cabrillo export** — architected so new radios and new QSO parties are easy to add.

Per Tom's direction, the **Kansas QSO Party is the first bundled party** (fully verified against the official 2026 rules); the **Texas QSO Party** ships second (rules + official county file verified).

## 2. Verified rules data (research results)

### Kansas QSO Party (primary; source: ksqsoparty.org, 2026 rules PDF + official mults PDF)
- **Dates 2026:** Aug 29 1400Z–Aug 30 0200Z, and Aug 30 1400Z–2000Z.
- **Exchange:** KS: RS(T) + county (official **3-letter** abbr, 105 counties). Others: RS(T) + state / Canadian province / "DX". `KS` itself is never used as an abbreviation.
- **Dupes:** same station workable once per **band × mode-class** (Phone, CW, RTTY). A KS station that changes county is a *new station* (rule 10).
- **County lines (rule 11):** "a separate QSO must be logged for each county. Don't log multiple-county QSOs on one line."
- **Points:** Phone 2, CW 3, RTTY/digital 3.
- **Multipliers (counted once, not per band):** non-KS: 105 KS counties. KS stations: 50 states (the **first KS county logged counts as the KS state multiplier**) + 13 provinces (AB BC MB NB NL NT NS NU ON PE QC SK YT) + DX (1) = max 64.
- **Bonus:** +100 one-time for working **KS0KS**. Score = QSO pts × mults + bonus.
- **Bands:** 80/40/20/15/10/6 m, no WARC.
- **1x1 award words** (tracked, not scored): KANSAS, QSOPARTY, SUNFLOWER, YELLOWBRICKROAD, spelled from 1x1-call suffix letters; duplicate letters need distinct calls; KS0KS is a once-only wildcard.
- **Cabrillo CONTEST:** `KS-QSO-PARTY`.

### Texas QSO Party (secondary; source: txqp.net rules + official `TX_county_abbrevs.txt`)
- **Exchange:** TX: RS(T) + county (official **4-letter** abbr, 254 counties). Others: RS(T) + state/province/country.
- **Points:** Phone 2, CW/digital 3. **Mults:** non-TX: TX counties (254). TX: states(49) + TX counties + provinces + DXCC.
- **Bonus:** +500 per TX **mobile worked in 5 different counties** (each additional 5 counties → +500; one contact per county per mobile counts).
- **County lines:** separate QSO + exchange logged per county. Cabrillo CONTEST: `TX-QSO-PARTY`.

### Elecraft K3 (source: K3 Programmer's Reference Rev. G5, local copy)
- Serial 38400-8N1 default; commands ASCII terminated `;`.
- `IF` GET → `IF[11-digit freq][5 sp]±[4-digit RIT]rx*00tmvspbd1 ;` — mode at fixed index 29, TX flag at 28.
- `MD`: 1 LSB, 2 USB, 3 CW, 4 FM, 5 AM, 6 DATA, 7 CW-REV, 9 DATA-REV. `FA`/`FB` 11-digit Hz. `KS` 008–050 WPM. `KY ` sends ≤24 chars via internal keyer (prosigns: `(`=KN `+`=AR `=`=BT `%`=AS `*`=SK).
- **Direct keying:** K3 CONFIG **PTT-KEY** (menu 103) maps RS-232 **DTR→CW key / RTS→PTT** (configurable). The app toggles control lines via `ioctl(TIOCMBIS/TIOCMBIC)`.
- ⚠️ Unlike K3MacroKeyer, the logger must **not blanket-assert DTR/RTS at port open** when direct keying is configured — that would key the transmitter. Lines configured for keying initialize deasserted.

## 3. Decisions (with alternatives considered)

| # | Decision | Alternatives | Why |
|---|----------|--------------|-----|
| D1 | **XcodeGen** project (`project.yml`), app + unit-test targets | hand-written pbxproj; SPM-only | XcodeGen installed; reproducible, diff-able, Xcode 26-native |
| D2 | **Document-based** app (`ReferenceFileDocument`, `.qplog` JSON) | SwiftData store; single implicit log | one file per contest = natural contest workflow, autosave, Finder-visible, trivially backed up |
| D3 | **Data-driven party definitions**: JSON bundled + user-installable at `~/Library/Application Support/QSOPartyLogger/Parties/*.json` | Swift protocol per party | new party without recompiling = the extensibility ask; generic rules engine covers points/mults/bonus shapes of both verified parties |
| D4 | Bonus rules as **typed strategies** in JSON: `workStation` (KSQP KS0KS) and `mobileCountyCount` (TQP 500/5-counties) | hard-code per party | both verified shapes covered; new shapes = new enum case |
| D5 | County-line logging = **cartesian expansion** (my counties × their counties), one `QSO` row per pair, shared `groupID` | log one row w/ multi-county field, expand only at export | matches N1MM + KSQP rule 11 exactly; dupe/score/export all operate on real rows; UI groups rows visually |
| D6 | Dupe key = `call + band + modeClass + theirLoc + myLoc` | ignore myLoc | when *I* straddle a line, each of my counties is a distinct contact context (both sides log 2) |
| D7 | Serial via **POSIX/termios + IOKit enumeration** (pattern proven in K3MacroKeyer), `ORSSerialPort` not used | ORSSerialPort SPM dep | zero deps, code Tom already trusts, full TIOCM control for keying |
| D8 | CW keyer: **dedicated high-priority Thread**, mach-time absolute deadlines, DTR-key/RTS-PTT mapping configurable; **K3 `KY` internal-keyer mode as fallback** | DispatchQueue timers | sub-ms jitter needed at 30+ WPM; `KY` mode gives a zero-wiring option |
| D9 | Radio abstraction: `RadioDriver` protocol + `RadioRegistry` (name→factory); K3 driver built on a reusable Kenwood-style ASCII transport | CAT lib dep | "easy adding of new radio support": new driver = one file conforming to protocol |
| D10 | Bundle ID `org.b5n.QSOPartyLogger`, macOS 15+, sandbox **on** with `com.apple.security.device.serial` + `device.usb` (K3MacroKeyer precedent) | no sandbox | matches Tom's shipped-app conventions |
| D11 | Swift 6 language mode; UI `@MainActor`/`@Observable`, serial+keyer isolated behind `Sendable` boundaries | Swift 5 mode | modern, and the concurrency layout is clean enough to satisfy strict checking |
| A1 | **Assumption:** Tom's own operating categories default Single-Op; category pickers cover the Cabrillo axes | — | Cabrillo needs them; editable in Station settings |
| A2 | **Assumption:** TQP band list and some TQP details are less battle-verified than KSQP; TQP JSON marked `verified: partial` in `notes` | — | user said start with Kansas; TQP data from official sources but 2026 page not re-checked |

## 4. Architecture

Single Xcode project, two targets. Folders = module boundaries; Core has **zero** UI/serial imports (pure, fast tests).

```
QSOPartyLogger/
├── project.yml                     # XcodeGen
├── Sources/
│   ├── App/                        # QSOPartyLoggerApp, LogDocument (ReferenceFileDocument), AppSettings
│   ├── Core/
│   │   ├── Models/                 # QSO, Band, ModeClass, StationProfile, MyLocation
│   │   ├── Parties/                # PartyDefinition (Codable schema v1), PartyCatalog (bundle+user dir loader), County
│   │   ├── Engine/                 # ExchangeParser, CountyLineExpander, DupeChecker, ScoreEngine, OneByOneTracker
│   │   └── Export/                 # AdifExporter, CabrilloExporter
│   ├── Hardware/
│   │   ├── Serial/                 # SerialPort (POSIX), SerialPortEnumerator (IOKit), SerialTransport protocol
│   │   ├── Radio/                  # RadioDriver protocol, RadioState, RadioRegistry, ElecraftK3Driver
│   │   └── Keying/                 # MorseCode, CWKeyer (direct DTR/RTS), K3InternalKeyer, KeyerLine mapping
│   └── UI/                         # MainView, EntryBar, LogTable, ScoreSidebar, RadioBar, SettingsView, MessagesView
├── Resources/
│   └── Parties/ksqp.json, tqp.json
├── Tests/                          # unit tests per Core/Hardware component (mock transports)
└── docs/superpowers/specs/…
```

**Data flow:** EntryBar → `ExchangeParser` (validate against active `PartyDefinition`) → `CountyLineExpander` (cartesian rows, shared `groupID`) → `LogDocument.append` → `ScoreEngine.recompute` (pure fold over rows) → sidebar/score UI. RadioBar ⇄ `ElecraftK3Driver` (0.5 s poll `IF;`) → band/mode/freq stamped onto new QSOs. F-keys → `CWKeyer` (macros expanded) → DTR pulses on the same `SerialPort`.

**Scoring is a pure function** `score(log, party, myLocation) -> ScoreBreakdown` — recomputed on any mutation (log sizes here are ≤ thousands; no incremental complexity needed).

### PartyDefinition JSON (schema v1, abridged)
```json
{ "schemaVersion": 1, "id": "ksqp", "name": "Kansas QSO Party",
  "cabrilloContest": "KS-QSO-PARTY", "inStateAbbr": null, "homeState": "KS",
  "countyAbbrLength": 3, "counties": [{"abbr": "ALL", "name": "Allen"}, …105…],
  "validBands": ["80m","40m","20m","15m","10m","6m"],
  "points": {"phone": 2, "cw": 3, "digital": 3},
  "dupeScope": "bandMode",
  "multipliers": {
     "inState":  {"classes": ["state","province","dx"], "homeStateCountsViaCounty": true, "countScope": "once"},
     "outState": {"classes": ["county"], "countScope": "once"} },
  "bonuses": [{"type": "workStation", "call": "KS0KS", "points": 100, "scope": "once"}],
  "oneByOne": {"words": ["KANSAS","QSOPARTY","SUNFLOWER","YELLOWBRICKROAD"], "wildcard": "KS0KS"},
  "notes": "Verified against official 2026 rules PDF 2026-07-23." }
```

## 5. Key behaviors

- **Entry:** exchange field accepts `LIN`, `lin/and`, `LIN AND` → parsed, validated (unknown abbr = red, blocked with explanation; valid = green). RST defaults 59/599 by mode. Dupe warning appears live before logging; "NEW MULT" badge when the exchange would add a multiplier. Enter logs; fields clear; focus returns to callsign.
- **County line, worked station:** exchange `LIN/AND` → two rows (same call/time/band/mode, `theirLoc` LIN and AND), one `groupID`.
- **County line, my station:** My Location may hold 1–4 counties (e.g., mobile straddling `MRN/CHS`); each logged contact expands per my county too (2×2 → 4 rows). Sent exchange per row uses that row's my-county — exactly what Cabrillo needs.
- **Mobile county switch:** toolbar quick-picker; changing My Location affects subsequent QSOs only.
- **Score panel:** QSOs, points, mult count w/ per-class breakdown, bonus, total — live. KSQP in-state: KS state mult auto-satisfied by first KS county worked (`homeStateCountsViaCounty`).
- **1x1 tracker (KSQP):** letters collected per word from worked 1x1 suffixes, distinct-call-per-duplicate-letter enforced, KS0KS wildcard usable once; progress shown per word.
- **CW:** F1–F8 messages with `{MYCALL} {CALL} {RST} {EXCH} {WPM+/-}` macros; Esc aborts instantly (key line dropped, queue cleared). WPM 8–50. Keying backend: Direct (DTR/RTS mapping configurable: DTR-key/RTS-PTT default, swappable, PTT lead-in/tail ms) or K3 internal (`KY`, chunked ≤24, `KS` speed sync).
- **CAT:** port picker (IOKit `/dev/cu.*`), baud selectable (38400 default), connect/disconnect, live freq/mode/TX state; logger stamps QSOs from radio state; manual band/mode override when disconnected.
- **Exports:** Cabrillo V3 (header from StationProfile + category pickers; `QSO:` rows freq-kHz, mode PH/CW/RY/DG, per-row sent county) and ADIF 3.1.4 (`STX_STRING`/`SRX_STRING`, `CNTY`/`MY_CNTY` as `ST,County Name`, `CONTEST_ID`, `NOTES` carries county-line `groupID`). Save panels default `CALLSIGN.log` / `CALLSIGN.adi`.
- **Errors:** serial failures surface as non-modal banner w/ retry; port vanishing (USB unplug) → auto-disconnect + banner; malformed party JSON in user dir → listed with validation errors, app still runs with bundled parties.

## 6. Testing strategy

XCTest, no hardware required: engine tests (party load: 105/254 counties, unique abbrs; exchange parsing; expansion cartesian/groupID; dupe matrix incl. county-change and my-line cases; KSQP scoring incl. home-state-via-county + KS0KS once; TQP mobile-5-county bonus; 1x1 word logic incl. wildcard-once and distinct-call duplicate letters), exporter tests (byte-exact golden Cabrillo/ADIF incl. county-line rows), K3 protocol tests over `MockSerialTransport` (IF/FA/MD parse, band mapping, command bytes), Morse tests (element timing math at 20/30 WPM, prosigns), keyer tests (pulse schedule computation — timing model, not the thread). UI is exercised by building; hardware paths are behind protocols with mocks.

## 7. Out of scope (v1)

Rig control beyond K3 family (protocol + registry make it a one-file add), SO2R, networked multi-op, rig sidetone synthesis, spotting-cluster integration, FT4/8 (KSQP requires a separate log anyway), Windows/Linux.
