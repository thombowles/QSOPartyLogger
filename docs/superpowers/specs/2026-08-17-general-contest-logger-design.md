# A General Contest Logger — Design

**Date:** 2026-08-17 · **For:** KE5CW · **Status:** approved (Tom, in
conversation, 2026-08-17: schema strategy B, identity kept, big-five
reference set, digital seams only; Part 1 and Part 2 of the design each
approved as presented).

## What Tom asked for

> help me make qsoparty logger a general logger for all types of contests.
> in the future we'll add rtty and wsjtx support, but for now I want to
> continue to make it world-class for qso-parties, but also make it a
> user-friendly, with all the essential contest features for all sorts of
> contests. Analyze to see what architectural changes need to be made to
> make this happen and what considerations need to be made. I don't want
> this to feel cobbled together, I want it to be cohesive, dead simple to
> use, friction-free with all the right features, and easy to maintain.
> determine what decisions need to be made and help me plan and implement
> once we nail those down.

## Decisions made (2026-08-17)

| # | Decision | Chosen |
| --- | --- | --- |
| 1 | Schema strategy | **B — one general engine model; every JSON schema is a front-end that lowers into it.** The 50 party files stay as they are. |
| 2 | Identity | Keep the app name, bundle id `org.b5n.QSOPartyLogger`, UTType `org.b5n.qsopartylogger.log`, `.qplog`, folder names and User-Agent. Internal names become `Contest*`. A display-name change is a separate later decision. |
| 3 | First-wave reference set | **The big five:** CQ WW DX (CW/SSB), CQ WPX (CW/SSB), ARRL International DX (CW/SSB), ARRL November Sweepstakes (CW/SSB), ARRL Field Day + Winter Field Day. Their sponsors' rules were read verbatim before this model was fixed (Appendix A). |
| 4 | RTTY / WSJT-X | Seams and typed exchange only; no transport built. |
| 5 | Zone/entity authority | cty.dat (AD1C) — the bigcty `cty.csv`, versioned — for callsign → entity, CQ/ITU zone, continent, WAE flag. Constitution Article 1 amended. |
| 6 | Entry model | Discrete typed fields on one row, generated from the exchange spec; Space cycles required received fields, Tab all, Enter logs. |
| 7 | Operating-time rules | In scope: engine cutoff + sidebar meter. |
| 8 | Calendar | Dated UTC windows per contest per year (Article 19), as today. |
| 9 | Delivery | Worktree branch; five phases, each merging green (Article 4 quarantine); one contest per commit in phase 3. |
| 10 | Log format | New saves write the v2 row shape only (`schemaVersion: 2`); a log saved by this build needs this build or later. Old logs decode unchanged. |

## What was there, measured (2026-08-17, master `3043edf`)

- **Already contest-agnostic:** everything in `Sources/Hardware/` (drivers, CW keyer, voice player/recorder), cluster spotting and the band map, POTA, Cabrillo headers and the five category axes, `StationProfile`, call-history/SCP plumbing, `RateMeter`, ESM and the Space/Tab/Enter model, F-key messages and voice memories, the `.qplog` document, iCloud folder and dashboard, the Advisor's `runFading`/`moveCall` strands, the ARRL DXCC entity table.
- **QSO-party-shaped:**
  - `PartyDefinition` (1,118 lines): 14 required + 28 optional fields, all expressed as *home state + counties + inState/outState*. NAQP, Skeeter and FOBB shipped through `homeState: "NA"`, countries in the county slot and `hasHomeRegion: false`. The worklist's "Deferred engine gaps" records eleven more limits (points by band / callsign / entrant role, one-sided bonuses, mode sub-classes, one dupe scope, exactly two sides…).
  - `MultClass`: a closed enum — county / state / province / dx / section / member. No CQ or ITU zone, no WPX prefix, no grid, no HQ station.
  - Exchange: one free-text *location* field plus typed RST / serial / name / member / park columns toggled by flags. `QSO` has 21 stored fields; no zone, precedence, check, class, grid or power.
  - `ScoreEngine` (692 lines): points by mode class or worked-station class; multipliers only from the location token; one dupe scope (band × mode + both locations).
  - Cabrillo: QSO line hard-coded (`ex1 loc [member]`, 3-character exchange columns); `CATEGORY-BAND: ALL` fixed; no overlay/time.
  - No zone data (cty.dat downloaded, used only for prefix labels). No operating-time rule anywhere.
  - UI: `MyLocation` in/out enum, county picker in Setup, county grouping in the sidebar, hub-only "needed mult" advisor strand, band map keyed on `spot.county`, ~40 "party" strings.
  - Naming footprint: `PartyDefinition` 325 refs / 147 files; `PartyCatalog` 349; `partyID` 662 refs / 130 files. Persisted keys that must not change: `partyID` in every `.qplog`, the party JSON keys, `Messages/<id>.json`, `Voice/<id>/`, UserDefaults `"<id>.<class>"`, the UTType and extension, the `os.Logger` subsystem, the User-Agent, the Application Support paths.
- **Tests:** 2,875 (211 files); ~46 per-party files pin county counts, scopes, points, exchange parsing, dupes, schedules and bonuses. Several roster tests pin catalogue-wide facts (39 hub-served parties, 47 with call history, badge set, fractional-factor set).

## Approaches considered

- **A. Keep growing `PartyDefinition`** — add zone/prefix/serial flags to the party schema. Least work now; every DX contest becomes another `"NA"` hack; Article 4's own warning ("the schema must not accrete flags forever") already applies. Rejected.
- **B. One general model, party JSON lowered into it — chosen.** `ContestDefinition` is the only type the engine, parser, exporters and UI consume. `PartyDefinition` stays as the QSO-party authoring schema and is lowered by a pure function; general contests are authored in v2 JSON that *is* the model's Codable form. Proven by every bundled party scoring identically through the general engine.
- **C. `kind`-switched engines** — a QSO-party engine, a DX engine, a Sweepstakes engine… Exact per kind, duplicated features across kinds. Rejected.

## The design — Part 1: the rules model

### 1.1 What the sponsors' sentences require

Read verbatim on 2026-08-17 (Appendix A). Every column below is expressible with the eight concepts in 1.2, and nothing the parties do is lost.

| Concept | State QSO parties (50 files) | CQ WW DX | CQ WPX | ARRL DX | Sweepstakes | Field Day / WFD |
| --- | --- | --- | --- | --- | --- | --- |
| Sides | inside / outside, chosen in Setup | one; my country/continent from callsign | same, plus "both in NA" | W/VE = DXCC entity USA or Canada (AK, HI, CY9/CYØ, KP4… are DX) | W/VE incl. territories | one |
| Exchange | RST? serial? name? *location* (county×N / state / province / DX / prefix), member-or-power | RS(T) + CQ zone | RS(T) + serial from 001 | RS(T) + state/province ⇄ RS(T) + power ("KW", "500") | nr, prec Q/A/B/U/M/S, call, check (2 digits), section (85) | class token ("3A") + section, DX (WFD: MX); no RST |
| Points | by mode; by worked side; designated counties ×N; member/QRP/other | 0 same country (still a multiplier) · 1 same continent · 2 both in NA · 3 different continent | 3/6, 1/2, NA 2/4, same country 1 — by high/low band group | 3 | 2 | phone 1, CW 2, digital 2 |
| Multipliers | county / state / province / DX / section / member; per-side scope, caps, granted, activated | zone (received) per band + country (callsign → "DXCC + WAE + IG9/IH9") per band; /MM zone only | prefix computed from callsign, once | W/VE: DXCC entities per band (KH6/KL7 count); DX: 48 states + DC + 14 provinces (NF/LB split) per band, from received token | sections, once per contest | none — power tier ×5/×2/×1 (FD); 1 + Σ objectives (WFD) |
| Dupe | band × mode + both locations | once per band | once per band | once per band | once regardless of band | band × mode, three mode groups |
| Pairing | MDC: outside works inside only; NAQP: NA ↔ any | everyone | everyone | W/VE ⇄ DX only | W/VE ⇄ W/VE | everyone |
| Operating time | — | Classic overlay 24 of 48 h, 60-min off | single-op 36 of 48 h, 60-min off | none | 24 of 30 h, 30-min off, minute granularity | 24 of 27 h by class |
| Categories | Cabrillo axes | + overlay CLASSIC/ROOKIE/YOUTH, station DISTRIBUTED, single band | + TB-WIRES | Limited-Antennas overlay (token NOT STATED) | precedence *derived* from category | class + section; Cabrillo not required by ARRL |

### 1.2 `ContestDefinition`

A Swift value; **the v2 JSON file is exactly its Codable form.** Every field below is a JSON key of the same name.

```
ContestDefinition
├─ schemaVersion: 2, id, name, family, sponsor?, notes, caveats, provenance
├─ schedule: [{start, end}]  bands: [Band]  modeClasses: [ModeClass]  allowedRawModes: [String]?
├─ tokenSets: [TokenSet]
├─ sides: [Side]
├─ exchange: [ExchangeElement]
├─ multipliers: [MultiplierClass]
├─ points: [PointRule]
├─ dupe: DupeRule
├─ pairing: [SideID: [SideID]]?
├─ sideRules: [SideID: SideRules]
├─ bonuses: [BonusRule]
├─ scoreFactors: ScoreFactors?
├─ operatingTime: OperatingTimeRule?
├─ categories: Categories
├─ cabrillo: CabrilloSpec
└─ sources: { hubSpots?, callHistory?, oneByOne?, combines: [id] }
```

**`family`** — `stateQSOParty | dx | domestic | fieldDay | sprint | qrp | vhf`. Picker grouping ("State & provincial QSO parties" holds the Canadian provincial parties too) and dashboard wording only; never read by the engine.

**`TokenSet`** — `{ id, term, termPlural, tokens: [{abbr, name?, group?}], aliases: [String: String] }`. Built-in sets, bundled as data with provenance: `usStates` (50 + DC), `provinces` (13), `sections` (the 85 ARRL/RAC sections, generated from the banked ARRL list), `cqZones` (1–40), `ituZones` (1–90). A contest declares its own (`counties`, `naEntities`, FQP's `ituRegions`). Two dynamic sets exist by name: `dxToken` (the literal `DX`) and `dxccPrefix` (any prefix `DXCCTable` knows, honouring the enumerated aliases FQP needs).

**`Side`** — `{ id, label, predicate, workedPredicate }`. `predicate` classifies the entrant, `workedPredicate` the worked station; both use the same kinds:

| kind | fields | who uses it |
| --- | --- | --- |
| `always` | — | CQ WW, WPX, SS, FD |
| `sentTokenIn` / `receivedTokenIn` | `element`, `set` | parties (`location` ∈ `counties` ⇒ inside) |
| `dxccIn` / `dxccOfCallsignIn` | `codes: [ADIF entity code]` | ARRL DX (W/VE = 291, 1) |
| `continentIn` | `continents` | reserved (NAQP's NA rule 12) |

The log **stores** `sideID`. The entrant predicate only *defaults* the choice in Setup: a county code can collide with a state code, so a party operator's Inside/Outside is never inferred from a token.

**`ExchangeElement`** — `{ id, kind, label, shortLabel, sentBy: [SideID: SentSpec], fixed: Bool, required: Bool, cabrilloWidth, prefill: [PrefillSource], derived: Derivation? }`. `sentBy` names every side that sends the element and, for `token` kinds, **what that side sends**: `SentSpec = { sets: [setRef]?, multi: {max}? }` — a party's `location` is `{ inside: {sets: [counties], multi: {max: 2}}, outside: {sets: [usStates, provinces, dxToken, dxccPrefix]} }`; ARRL DX's `state` is sent by `wve` and its `power` by `dx`. `fixed` means the sent value is set once in Setup and stamped per row (`nameSent` idiom); a non-fixed sent element is per-QSO (serial). The received fields a side sees are the elements sent by the sides it may work (per `pairing`), in spec order, and a token field accepts the **union of those sides' sets** — which is how MDC's outside entrant receives counties only, exactly as today.

| kind | validation | well-known ids |
| --- | --- | --- |
| `rst` | 2–3 digits by mode class; default 59/599 | `rst` |
| `serial` | integer ≥ 1; sent value from `cabrillo.serialSequence` | `serial` |
| `name` | 1–15 letters | `name` |
| `token` | value ∈ the union of the sending sides' `sets` (aliases folded); `multi` allows `/`- or `,`-separated values (county lines) | `location`, `section`, `state` |
| `cqZone` / `ituZone` | 1–40 / 1–90, leading zero allowed | `zone`, `ituZone` |
| `precedence` | `{ letters }` one of | `precedence` |
| `check` | exactly 2 digits | `check` |
| `classToken` | `{ letters, minNumber }` — `\d+` + one letter | `class` |
| `power` | `\d+(W|K|KW)?` or `K` / `KW` — stored verbatim | `power` |
| `memberOrPower` | today's `MemberExchange.parse` (`{ term, shortTerm, memberPlural, qrpMaxWatts }` on the element) | `member` |
| `callEcho` | the worked call itself; no field; `cabrilloWidth` 0 | `call` |
| `grid` | Maidenhead 4 or 6 | `grid` |
| `report` | signed dB report | `report` |

`prefill` sources, in priority order as listed: `cty` (zone/ituZone from `CTYTable`), `callHistory` (the mapped column), `stationMemory` (this log), `spot` (a hub spot's county). `derived` (SS precedence): `{ kind: "categoryTable", table: [{ when: {operator?, assisted?, power?, station?, overlay?}, value }] }`, first match.

**`MultiplierClass`** — `{ id, term, termPlural, resolvers: [Resolver], counting: [SideID: CountScope], caps: [SideID: Int]?, roster: setRef?, layout }`. `counting` omits a side that does not count the class. `CountScope` is today's `once | perMode | perBand | perBandMode` with the same `component(band:modeClass:)`. `layout` ∈ `groupedTokens(by: group) | tokens | zoneGrid | workedOnly`. Resolvers are tried in order; the first that yields a value wins; each takes optional `sides: [SideID]` and `unlessSuffix: ["MM", "AM"]`:

| kind | fields | value |
| --- | --- | --- |
| `receivedToken` | `element`, `set`, `mapTo?` (`countyState` maps a county to its state) | the token, or its mapping |
| `dxccEntity` | `from: callsign \| receivedToken \| receivedTokenOrCallsign`, `list: arrl \| arrlPlusWAE`, `exclude: [codes]`, `countEntities: Bool` | entity (label = primary prefix, identity = code / WAE name); when `countEntities` is false the literal `DX` |
| `cqZone` / `ituZone` | `from: received` | the zone |
| `wpxPrefix` | — | `WPXPrefix.of(call)` |
| `grid` | `element`, `precision` | the grid |
| `workedStation` | `whenMemberElement` | the worked call (FOBB) |

Well-known class ids keep today's raw values — `county`, `state`, `province`, `dx`, `section`, `member` — so `ScoreSnapshot.multsByClass` and the sidebar's UserDefaults keys read unchanged. New: `zone`, `ituZone`, `country`, `prefix`, `grid`.

**`PointRule`** — `{ when: [Condition], points: Int }`, ordered, first match wins; the last rule has no conditions. Conditions: `modeClass`, `band`, `relation` (`sameEntity | sameContinent | differentContinent`, entrant vs worked, both from `CTYTable`), `bothInContinent`, `side`, `workedSide`, `receivedTokenIn { element, set }`, `workedStationKind` (`member | qrp | other`), `callsign: [String]`. Lowering emits *explicit* tables (NCQP's ×10 becomes 20/30/50 rows, exactly what its generator already asserts).

**`DupeRule`** — `{ scope: contest | band | bandMode, locationSensitive: Bool }`. Parties: `bandMode` + `true` (today's key). CQ WW / WPX / ARRL DX: `band`. SS: `contest`. FD/WFD: `bandMode` (mode *classes* are already the sponsors' three groups).

**`pairing`** — for each side, the worked sides that count; `nil` = everyone. MDC `{outside: [inside]}`; ARRL DX `{wve: [dx], dx: [wve]}`; SS `{wve: [wve]}`. Rows outside the pairing are `outOfScope`, exactly today's MDC handling.

**`SideRules`** — `{ maxScoredMultipliers?, multiplierFloor?, granted: [{class, value}], activated: ActivatedRule? }`; `ActivatedRule` is today's five required fields plus `class` (any enumerated class — VHF rovers later).

**`bonuses`** — today's `BonusRule` cases, names and JSON `type` strings unchanged (`workStation`, `mobileCountyCount`, `activatedCountyCount`, `sweepTiers`, `designatedCountySweep`, `callAreaSum`); the county-keyed cases read the `location` element and the `county` class. Each gains an optional `sides` filter (VTQP's W1AW/1 bonus becomes expressible).

**`ScoreFactors`** — `{ power: [String: ScoreFactor]?, station: [String: ScoreFactor]?, entryClasses: [EntryClass], objectives: [{id, label, om: Int}], declaredBonuses: [{id, label, points, perCount: {label, max}?}] }`. Applied as today: `factor(points × mults) + bonuses`, rounded down once. FD's power tiers are `entryClasses` (×5/×2/×1); WFD's factor is `1 + Σ selected objectives`; FD's checklist bonuses are `declaredBonuses`, added after the multiplier and never scaled.

**`OperatingTimeRule`** — `{ maxMinutes, minOffMinutes, appliesTo: {operator?, assisted?, overlay?, power?}? }`. Operating time starts at the first valid QSO; a gap counts as off time only when the empty clock minutes strictly between two QSOs number ≥ `minOffMinutes` (SS package: 0115–0144 is 30 minutes and counts; 0115–0143 does not); rows logged after `maxMinutes` are `outOfTime` — no points, no multipliers, still logged and exported (SS 1.2, WPX FAQ).

**`Categories`** — allowed values per Cabrillo axis: `operator`, `assisted`, `power`, `band`, `mode`, `transmitter`, `station`, `overlay`, `time`. Setup shows only these; an axis absent from the JSON keeps today's full enum. `overlay` and `time` are new optional axes on `StationProfile`.

**`CabrilloSpec`** — `{ contest, location: state | section | entrantToken, transmitterColumn: Bool, serialSequence: contest | perBand, categoryMode: String? }`. `LOCATION:` — `state`: the entrant's state/province token (a party's sent `location`, resolved to its state for an inside entrant, exactly `MyLocation.entrantToken` today; otherwise `exchangeDefaults.state`, asked in Setup); `section`: the sent `section` element or `exchangeDefaults.section`; `entrantToken`: the sent `location` element verbatim. An entrant whose callsign resolves outside USA/Canada writes `DX`. The QSO line is derived: `QSO: freq mo date time mycall <sent elements> call <received elements> [t]`, each element padded to its `cabrilloWidth`; sponsors state that spaces delimit and columns need not align, so widths matter only for our own byte-identity.

**`sources`** — `hubSpots` and `callHistory` as today (the latter gains `columns: [elementID: N1MMColumn]`), `oneByOne`, `combines`.

Sketch of `cqwwcw.json` (v2):

```json
{ "schemaVersion": 2, "id": "cqwwcw", "name": "CQ World Wide DX Contest, CW", "family": "dx",
  "cabrillo": { "contest": "CQ-WW-CW", "location": "state", "transmitterColumn": true },
  "bands": ["160m","80m","40m","20m","15m","10m"], "modeClasses": ["cw"],
  "sides": [{ "id": "all", "label": "Everyone", "predicate": {"kind":"always"}, "workedPredicate": {"kind":"always"} }],
  "exchange": [{ "id": "rst", "kind": "rst", "sentBy": { "all": {} } },
               { "id": "zone", "kind": "cqZone", "label": "Zone", "sentBy": { "all": {} },
                 "fixed": true, "prefill": ["cty"], "cabrilloWidth": 6 }],
  "multipliers": [
    { "id": "zone", "term": "zone", "resolvers": [{ "kind": "cqZone", "from": "received" }],
      "counting": { "all": "perBand" }, "roster": "cqZones", "layout": "zoneGrid" },
    { "id": "country", "term": "country", "termPlural": "countries",
      "resolvers": [{ "kind": "dxccEntity", "from": "callsign", "list": "arrlPlusWAE", "unlessSuffix": ["MM"] }],
      "counting": { "all": "perBand" }, "layout": "workedOnly" } ],
  "points": [ { "when": [{ "relation": "sameEntity" }], "points": 0 },
              { "when": [{ "bothInContinent": "NA" }], "points": 2 },
              { "when": [{ "relation": "sameContinent" }], "points": 1 },
              { "points": 3 } ],
  "dupe": { "scope": "band", "locationSensitive": false },
  "categories": { "operator": ["SINGLE-OP","MULTI-OP","CHECKLOG"], "assisted": ["NON-ASSISTED","ASSISTED"],
                  "power": ["HIGH","LOW","QRP"], "band": ["ALL","160M","80M","40M","20M","15M","10M"],
                  "transmitter": ["ONE","TWO","UNLIMITED"], "overlay": ["CLASSIC","ROOKIE","YOUTH"],
                  "station": ["FIXED","DISTRIBUTED"] },
  "operatingTime": { "maxMinutes": 1440, "minOffMinutes": 60, "appliesTo": { "overlay": "CLASSIC" } },
  "schedule": [{ "start": "2026-11-28T00:00:00Z", "end": "2026-11-29T23:59:59Z" }],
  "notes": "…provenance…", "caveats": [] }
```

### 1.3 Lowering `PartyDefinition` → `ContestDefinition`

`PartyLowering.lower(_:)` is a pure function in `Sources/Core/Contests/PartyLowering.swift`. Every v1 field has one destination:

| v1 field | v2 |
| --- | --- |
| `id`, `name`, `cabrilloContest`, `schedule`, `validBands`, `notes`, `caveats` | same; `cabrillo.contest`; `bands` |
| `allowedModes` | `modeClasses` |
| `family` (new optional v1 field, default `stateQSOParty`; `domestic` for the two NAQPs, `qrp` for Skeeter and FOBB) | `family` |
| `counties`, `countyTerm(Plural)`, `countyAbbrLength(s)` | `tokenSets.counties` (`group` = the county's state for multi-state parties); the term; the length hint is derived from the set |
| `homeState`, `homeStates`, `inStateLabel`, `hasHomeRegion` | sides `inside` ("Inside \<inStateLabel\>", `sentTokenIn(location, counties)`, worked `receivedTokenIn`) and `outside`; a single side `all` when `hasHomeRegion` is false. `cabrillo.location = state`, `entrantToken` when no home region |
| `stateAliases`, `excludedStateTokens`, `provinces`, `sections`, `dxStyle`, `acceptsDXToken`, `dxTokenAliases` | the `location` element's `sentBy`: `inside: {sets: [counties]}`; `outside`'s sets are `sections` **instead of** states+provinces when present, else `usStates` minus exclusions with aliases and `provinces` (party override or the 13); plus `dxToken` when accepted, `dxccPrefix` when `dxStyle == prefix`, and an enumerated alias set (FQP's `R1 R2 R3`) that the `dx` class credits as literal tokens |
| `maxSimultaneousCounties` | `location.sentBy.inside.multi.max` (capped at 4) |
| `exchangeIncludesRST` / `Serial` / `Name` | `rst`, `serial`, `name` elements present |
| `memberExchange` | `member` element (`memberOrPower`, labels), point rules by `workedStationKind`, and the `member` class where the party lists it |
| `points`, `homeStationPoints`, `countyPointFactor` | explicit `points` rules: designated ∧ home → scaled home table; designated → scaled; home (`receivedTokenIn(location, counties)`) → home table; default → `points` |
| `dupeScope: bandMode` | `dupe: {bandMode, locationSensitive: true}` |
| `multipliers.inState / .outState` `classes`, `countScope` | one `MultiplierClass` per class named on either side; `counting[side]` per side |
| `homeStateCountsViaCounty` | a second `state` resolver `receivedToken(location, counties, mapTo: countyState, sides: [that side])` |
| `dxCountsEntities` | the `dx` class resolver `dxccEntity(from: receivedTokenOrCallsign, list: arrl, countEntities:, sides:)` |
| `dxMultCap` | `caps[side]` on `dx` |
| `maxScoredMultipliers`, `multiplierFloor`, `grantedMultipliers`, `activatedCountyMultiplier` | `sideRules[side]` |
| `outStateWorksHomeStationsOnly` | `pairing: {outside: [inside]}` |
| `bonuses` | same rules (renamed cases decode the old `type` strings) |
| `scoreMultipliers`, `entryClasses` | `scoreFactors.power / .station / .entryClasses` |
| `oneByOne`, `hubSpots`, `callHistory`, `combines` | `sources` |

`ScoreEngine.score(log:party:)` remains as an overload that lowers first, so every existing test exercises the general engine without edits. `PartyDefinition` gains **one** optional field (`family`); its four non-state files gain it through their generators.

### 1.4 The engine on the model

`ScoreEngine.score(log: ContestLog, contest: ContestDefinition) -> ScoreBreakdown`, rows in chronological order:

1. **Mode** — a row whose `modeClass` (or `rawMode`, when `allowedRawModes` is set) is not allowed is `invalid` (as today).
2. **Pairing** — the worked side comes from the sides' `workedPredicate`s; a row outside `pairing[log.sideID]` is `outOfScope`.
3. **Operating time** — with a rule that applies to this log's category, rows past `maxMinutes` are `outOfTime`.
4. **Dupes** — `DupeChecker` keys on `DupeRule`; first occurrence wins.
5. **Points** — first matching `PointRule`; `pointsByRowID` as today.
6. **Multipliers** — every class whose `counting` names this side: the first resolver that yields a value makes a `MultKey(classID, value, scope)`; per-class caps; `sideRules` granted first, activated last (after bonuses, as today).
7. **Bonuses**, then **factors** (`power × station × entryClass × (1 + Σ objectives)`), then `declaredBonuses` and rule bonuses added.
8. `ScoreBreakdown` gains `outOfTimeRowIDs`, `operatingMinutes`, `offMinutes`; `MultKey.multClass` becomes `classID: String`; `classCounts` is `[String: Int]`.

`ExchangeParser` becomes `ExchangeValidator.validate(element, raw, contest, side) -> Result<[String], ExchangeError>` — the same tokeniser, suggestions and edit-distance help for token kinds, one validator per kind otherwise. `NeededMult`, `MultiplierRoster`, `Advisor` and the sidebar read `MultiplierClass` instead of `MultClass`.

### 1.5 The log

**`QSO`** — `sent: Exchange`, `rcvd: Exchange` where `Exchange` is an ordered `[String: String]` (element id → value); `myPotaRefs`, `theirPotaRefs`, `posture`, `freqKHz`, `rawMode`, `band`, `modeClass`, `call`, `timestampUTC`, `id`, `groupID` unchanged. Legacy keys decode into the maps: `rstSent → sent.rst`, `rstRcvd → rcvd.rst`, `serialSent/Rcvd → serial`, `nameSent/Rcvd → name`, `memberSent/Rcvd → member`, `myLoc → sent.location`, `theirLoc → rcvd.location`. Typed accessors (`rstSent`, `theirLoc`, `serialRcvd`…) remain as computed properties over the maps so call sites and tests do not change. New saves write `sent`/`rcvd` only.

**`ContestLog`** — `contestID` (JSON key `partyID`, unchanged), `sideID: String`, `sentExchange: [String: [String]]` (a list for county lines; every other element one value), `station`, `qsos`, `messages`, `operatingMode`, `setupCompleted`, `entryClassID`, `selectedObjectives: [String]`, `declaredBonuses: [String: Int]`, `myPotaRefs`, `usedSpots`, `scoreSnapshot`, `schemaVersion: 2`. Legacy decode: `myLocation.inState(counties)` → `sideID = "inside"`, `sentExchange.location = counties`; `.outOfState(loc)` → `"outside"` (or the party's single side) and `[loc]`; `exchangeName → name`, `exchangeMember → member`. `nextSerial` is unchanged; `derivedOperatingMode` becomes "the first-listed side runs, every other side searches; a single-side contest runs" — inside runs and outside searches exactly as today.

**`StationProfile`** gains `categoryOverlay: String?`, `categoryTime: String?`, and `exchangeDefaults: [String: String]` (my section, zone, check, grid, state, name, power… remembered across contests through `lastStationProfile`). All decode with defaults.

**`ScoreSnapshot`** — `countiesWorked` stays for the state-party family; `multsByClass` keys are class ids (the same strings as before).

### 1.6 `CTYTable`, `DXCCTable`, `WPXPrefix`

- **`CTYTable`** (`Sources/Core/Contests/CTYTable.swift`) parses the bigcty **`cty.csv`** — fields: primary prefix, name, ADIF entity code, continent, CQ zone, ITU zone, lat, lon, tz, prefix/callsign list with `(n)`/`[n]` overrides and `=` exact calls, `*` WAE-only entities. Bundled under `Resources/CTY/cty.csv` with a `VERSION` file naming the CTY release, URL and fetch date; refreshed by the existing label client (renamed `CTYClient`; the download needs a browser User-Agent), validated (≥ 340 non-WAE records, parseable, VERSION entity present) and applied at launch only. API: `match(callsign) -> {entityCode, name, primaryPrefix, waeOnly, cqZone, ituZone, continent}` (longest prefix; exact `=` calls first; a callsign under two entities takes the first).
- **`DXCCTable`** (ARRL roster) stays for ARRL-list rules — parties' `dxCountsEntities`, ARRL DX's W/VE multipliers, `isDXPrefix`. `DXCCLabelRefresh` is replaced by `CTYTable`'s primary prefixes. A test pins that the ARRL roster and cty's non-WAE entities agree on all 340 codes; CQ WW's `arrlPlusWAE` list adds cty's `*` entities (`4U1V`, `GM/s`, `IG9`, `IT9`, `JW/b`, `TA1`).
- **`WPXPrefix.of(call)`** implements CQ WPX V.C.1: the letters+digits up to the end of the first digit run; portable designators become the prefix, a designator without a digit gets `0` appended (`PA/N8BJQ → PA0`, `OE/K5ZD → OE0`); a call without a digit gets `0` after two letters (`XEFTJW → XE0`); `/MM /M /A /E /J /P /QRP` and other class identifiers are ignored; `KL7RA/WK9 → WK9`; special prefixes keep their whole digit run (`OL25LP → OL25`, `LY1000CW → LY1000`, `DR2006Q → DR2006`). A bare `/digit` designator (`W1ABC/7`) replaces the digit (`W7`) — NOT STATED by the sponsor, carried as a `ruleInference` caveat on the WPX files.

## The design — Part 2: how it flows through the app

### 2.1 Contest Setup

One sheet, asking only what the contest needs:

- **Picker** — grouped by *this weekend* (schedule intersects now−1 d … now+3 d), then by `family`; search by name or Cabrillo token; combined-party nesting kept.
- **Station** — unchanged.
- **Category** — one control per axis, showing only the contest's allowed values; overlay/time only where the contest has them; SS precedence shown as a derived read-only value; FD class = transmitter count + letter; power tier / objectives / declared bonuses render from `scoreFactors`.
- **Side and my exchange** — parties keep the Inside/Outside control and county grid; callsign-classified contests show the derived side ("W/VE station — from your callsign") with an override menu. One field per fixed sent element for my side: token pickers (counties, sections), zone pre-filled from cty, check/name/power/grid text — each seeded from `exchangeDefaults`. `canSave` = callsign present and every fixed element valid.

### 2.2 The entry row

- Fields = call + the received elements of the sides I may work, in spec order, widths by kind: SS `Nr Prec Ck Sect`; CQ WW `RST Zone`; W/VE in ARRL DX `RST Pwr`; a party exactly today's row (`Ser S/R`, `Name`, `County/State`, `Member`, `P2P`). Space cycles the *required* received elements (reports stepped over), Tab walks all, Enter logs or sends the next ESM message, F12 wipes — **the keyboard table does not change**.
- Validation per kind with the same suggestions and edit-distance help; provisional (ghost) prefill by element from `cty`, call history, `StationMemory` (generalised to every fixed element per call within the log) and hub spots; the operator confirms with Space/Enter as today.
- Live badges: `DUPE` from `DupeRule`, `NEW MULT` across every class, `OUT OF TIME` when the rule is exhausted, today's `COUNTY LINE ×N`.
- `RowExpander` (today's `CountyLineExpander`) expands multi-valued location elements only.
- `EditQSOSheet` and `BulkEdit` edit any received element as text, validated the same way.

### 2.3 Score sidebar, band map, advisor

- Totals card unchanged; an **operating-time meter** (operated / off credited / remaining, minute granularity) appears where the contest has a rule.
- Rosters per class from `layout`: grouped tokens (counties by state), token chips (states/provinces/sections), a 1–40 zone grid, worked-only lists with counts (DXCC entities, prefixes); per-band/mode slots exactly as `MultiplierRoster` draws them today. Bonus rows and 1×1 stay data-gated.
- `NeededMult` generalises: hub spots still carry a county token; cluster spots resolve country / zone / prefix from the callsign, so the band map and the advisor's "needed multipliers spotted" strand work in the DX contests (zone marked *likely*, since the received zone decides). Worked keys are `call|location` only when `dupe.locationSensitive`.

### 2.4 Messages and macros

`MessageSets.defaults(for:)` composes `[RST?] [SERIAL?] {EXCH}` from the spec, where `{EXCH}` = my fixed sent elements in order (SS: `A KE5CW 65 NTX`; a party: the county). One macro per element id — `{ZONE} {SECT} {PREC} {CHECK} {CLASS} {PWR} {GRID} {NAME} {MEMBER}` — expanded from the log's `sentExchange`; the static tokens (`{MYCALL} {CALL} {RST} {SERIAL} {EXCH}`) keep their exhaustive switch and cut-number rule. Message memory and voice recordings stay keyed by contest id in the same folders.

### 2.5 Call history and SCP

`CallHistoryFile.Field` grows to N1MM's standard columns (`Call Name Loc1 Loc2 Sect State CK BirthDate Exch1 Misc UserText Power CqZone ItuZone Grid1 Grid2`); a default element→column map (`name→Name`, `section→Sect`, `location→State/Loc1/Exch1`, `check→CK`, `zone→CqZone`, `ituZone→ItuZone`, `grid→Grid1`, `power→Power`) is overridable per contest in `sources.callHistory.columns`. Everything stays hint-only. `master.scp` unchanged.

### 2.6 Exports and history

- **Cabrillo** — header from `categories`/`cabrillo`: real `CATEGORY-BAND`, `CATEGORY-OVERLAY`, `CATEGORY-TIME`, `CATEGORY-STATION`, `LOCATION` per contest, optional `OFFTIME:` lines from the computed off periods, the `t` column when `transmitterColumn` (always `0` — one transmitter). QSO line derived from element widths: parties byte-identical to today; CQ WW / WPX / SS lines equal to the sponsors' samples; FD/WFD emit the WFD-style class + section line, and FD carries a caveat that ARRL's entry is the web app.
- **ADIF** — adds `cqz`, `ituz`, `arrl_sect`, `class`, `precedence`, `check`, `gridsquare`, `tx_pwr`, `dxcc`, `cont` when present; `contest_id` from `cabrillo.contest`; `stx_string`/`srx_string` remain the location element.
- **Dashboard / history** — identity `partyID|year|callsign` unchanged; "Party" → "Contest"; the counties card becomes "multipliers by class" (state parties still read as counties); the SQP Challenge section keys off its approved list as today.

### 2.7 Digital seams (no transports built)

- `MessageTransport` seam: `EntryFlow` already routes CW text vs a voice clip by mode class; a `DigitalTextSender` protocol slot (nil today) sits beside `CWSender` and `VoicePlayer`.
- `ExternalQSOSource` — `AsyncStream<ExternalQSO>` where `ExternalQSO = { call, band, rawMode, freqKHz?, start, end?, sent: Exchange, rcvd: Exchange }` — and `EntryFlow.log(external:)` running the same validation and expansion path. WSJT-X's UDP protocol implements it later; `grid` and `report` element kinds exist now.

### 2.8 Error handling

- A bad v2 file (unknown kind, missing set, invalid predicate) fails to load with a named error shown in the picker like today's user-party failures; it never scores silently.
- Every element kind reports its own error text; entry never logs an invalid element; `outOfTime` warns and never blocks logging.
- cty refresh rejects malformed downloads and keeps the bundled copy; the label-refresh discipline (validate, apply at launch) carries over.
- The v2 catalogue is validated at load: every set referenced exists, every side referenced exists, every element in `sentBy` names a side, `points` ends with an unconditional rule, `dupe` and `cabrillo.contest` present.

### 2.9 Naming and layout

- `PartyDefinition` keeps its name (the QSO-party authoring schema). New: `ContestDefinition`, `ContestCatalog` (replaces `PartyCatalog`; loads `Resources/Parties/*.json` lowered and `Resources/Contests/*.json`, user overrides by id from `…/QSOPartyLogger/Parties` and `…/Contests`), `PartyLowering`, `ContestNotice` (was `PartyNotice`). Swift `partyID` → `contestID`; the JSON key stays `partyID`.
- `Sources/Core/Contests/` holds the model, catalog, lowering, `CTYTable`, `WPXPrefix`, `HubSpotSource`, `CallHistorySource`, `DXCCTable`; `Sources/Core/Parties/` keeps `PartyDefinition`, `County`, `CountyGrouping`. `MultClass` becomes `MultiplierClassID` constants.
- User-facing strings say "contest"; a family's own words come from data (`term`, side labels). Persisted keys, paths, UTType, subsystem and User-Agent are unchanged (Decision 2).
- `MainView` stays under its type-checker budget: contest-dependent panes arrive as data-driven child views behind the existing opaque seams, never as `if` branches in `leftPaneContent`.

## Testing

- **Lowering equivalence** — until the old engine is deleted: for each of the 50 parties, a seeded deterministic log corpus (counties, county lines, states, provinces, DX tokens and prefixes, serials, names, member elements, dupes, all bands/modes, both sides) scored by the old and new engines; `ScoreBreakdown`s must be identical field by field. Deleting the old engine is the last commit of phase 1.
- **The 2,875 existing tests** remain the permanent oracle through `score(log:party:)`.
- **Byte-identity fixtures** — Cabrillo and ADIF for a fixture log per party shape (county line, serial, name, member, section, multi-state, prefix DX, POTA) checked in before phase 1 and asserted after.
- **Per-contest tests** (Article 18 floor, general form) from the sponsors' own examples: CQ WW `1000 × (30 + 70) = 100,000`, the four point cases including 0-point same-country multiplier credit, /MM zone-only, per-band zone and country keys; WPX the sponsor's prefix example list, band-group points, NA exception, 36-hour cutoff with the FAQ's 09:00 → 10:01 example; ARRL DX both sides, KH6/KL7 as DX and as W/VE multipliers, 63 DX-side multipliers per band, /MM credit-only, W/VE↔W/VE out of scope; SS 85 sections once per contest, precedence derivation for every category row, check as two digits, once-regardless-of-band dupes, the package's 0115–0144 off-time example; FD/WFD points, tiers/objectives, band × mode-group dupes, band lists, class-token validation.
- **Unit tests** — `CTYTable` (overrides, `=` calls, WAE flag, VERSION, agreement with `DXCCTable`), `WPXPrefix`, `ExchangeValidator` per kind, field generation and the Space cycle per contest, `DupeRule`, `OperatingTime`, category-derived precedence, Cabrillo layouts against the sponsors' sample lines, macro expansion per element, call-history column mapping.

## Delivery

Worktree branch `worktree-general-contest-logger`; each phase is a set of commits with the full suite green (Article 8 output recorded), and merges by fast-forward. Article 4 quarantine: phases 0–2 add no contest; phase 3 adds one contest per commit. **Each phase gets its own implementation plan** under `docs/superpowers/plans/`, written when the previous phase has merged, so the plan reads the code as it then is.

0. **Names and seams** — `ContestCatalog`, `contestID`, `ContestNotice`, "party" → "contest" in general strings, `Sources/Core/Contests/`. No behaviour change.
1. **Model and engine** — `ContestDefinition` and its types, `PartyLowering` (+ `family`), `CTYTable`/`CTYClient`, `WPXPrefix`, exchange maps on `QSO`/`ContestLog`, `StationProfile` additions, engine / validator / dupe / roster / exporters on the model, equivalence and byte-identity tests; delete the old engine last. Zero visible change.
2. **UI generalisation** — spec-driven Setup, entry row, sidebar rosters, op-time meter, macros, call-history map, `NeededMult`, dashboard wording, digital seams (`ExternalQSOSource`, `DigitalTextSender`). Parties look and behave identically.
3. **The big five, one contest per commit**, in calendar order — CQ WW SSB (Oct 24–25) → SS CW (Nov 7–9) → CQ WW CW → SS SSB → ARRL DX CW/SSB → CQ WPX SSB/CW → ARRL FD → WFD. Each commit: banked research (`docs/research/<id>_rules.md`, DX-contest template), generator, v2 JSON, per-contest tests, README table row, `docs/CONTESTS.md` entry, `PROVENANCE.md`.
4. **Constitution and docs** — Article 1 (cty as authority), Article 9 ("one contest"), Part III retitled with the party template kept and a general-contest template added, Article 17 mapping table for v2, Article 18 floor for general contests, Article 22 worklist per contest; CLAUDE.md layout rows; README features, keyboard table (unchanged keys), test count.

## Out of scope

Multi-operator networking and SO2R, log import, WAE QTCs, distance scoring, RTTY and WSJT-X transports (seams only), the Contest Dashboard beyond wording, a display-name change.

## Sponsor silences carried as caveats

Recorded here so the phase-3 files inherit them: ARRL DX's acceptable power tokens beyond "number or abbreviation" and its Limited-Antennas overlay token; SS's overlay token; FD's Cabrillo template (none published); CQ WW's zone credit when the received zone is wrong; WPX's bare `/digit` portable prefix; every sponsor's derivation of the entrant's own country/zone (the app resolves the entrant's callsign through cty for entity and continent — the sponsors require the callsign to indicate the entity of operation — and pre-fills the sent zone from it, editable in Setup).

## Appendix A — sources read for this design (fetched 2026-08-17)

Raw text banked in `docs/research/` in the commit following this one:

- CQ WW DX: https://www.cqww.com/rules.htm ("The 2025 CQ World-Wide DX Contest"; PDF footer "September 9, 2025"; no 2026 edition posted), https://www.cqww.com/ (2026 dates), https://www.cqww.com/cabrillo.htm, https://www.cqww.com/rules_faq.htm, https://www.cqww.com/cq_waz_list.htm.
- CQ WPX: https://cqwpx.com/rules/ ("2026 CQ World-Wide WPX Contest"), https://www.cqwpx.com/rules/2026_cqwpx_rules.pdf, https://www.cqwpx.com/cabrillo.htm, https://www.cqwpx.com/rules_faq.htm, https://cqwpx.com/ (2027 dates).
- ARRL DX: https://contests.arrl.org/ContestRules/DX-Rules.pdf ("Version 2.0", 04 Jan 2024), https://www.arrl.org/arrl-dx, https://contests.arrl.org/calendar.php, https://contests.arrl.org/contestmultipliers.php (?a=usa / ?a=ve / ?a=wve).
- ARRL Sweepstakes: https://contests.arrl.org/ContestRules/SS-Rules.pdf ("Version 2.1"), https://www.arrl.org/sweepstakes ("no Changes to Sweepstakes Multipliers for 2026"), the 2025 Information Package, https://contests.arrl.org/sscw/ and /ssph/ (2026 times, deadlines), https://www.arrl.org/section-abbreviations.
- ARRL Field Day: https://www.arrl.org/field-day and the current rules PDF; Winter Field Day: https://winterfieldday.org/sop.php and https://winterfieldday.org/downloads/2026-rules-v3.pdf ("V3 9.8.25").
- Cabrillo: https://wwrof.org/cabrillo/cabrillo-v3-header/ ("Last update: 5 June 2025"), https://wwrof.org/cabrillo/cabrillo-qso-data/, sponsor template pages above, https://www.contestcalendar.com/cabnames.php.
- cty.dat: https://www.country-files.com/cty-dat-format/, https://www.country-files.com/big-cty/, https://www.country-files.com/bigcty/cty.csv (CTY-3627, `=VER20260814`).
