# Worked stations on the band map, and spotting other stations to the hub

Date: 2026-07-25
Status: approved

Two requests from the operator:

1. A station worked but never spotted leaves no mark on the band map. Log it,
   and it should appear there.
2. Spotting is self-spotting only. A right-click on a band map spot, or on a
   log row, should offer to post that station to the QSO Party Hub.

## Reference

**N1MM Logger+ Bandmap window** (<https://n1mmwp.hamdocs.com/manual-windows/bandmap-window/>,
read 2026-07-25):

- Locally-added calls share the map with network spots and are distinguished
  from them: *"Bold – This is a self-spotted call. In this context 'self
  spotted' means that the user typed in the call, not that the spot came from
  the spotting network."*
- Worked stations stay and grey out rather than disappearing: `"Gray: Dupe"`.
- One timeout governs the map: *"Set Spot Timeout – Set the length of time
  spots will remain on the bandmap before timing out and disappearing (unless
  re-spotted)"*.

**qsopartyhub.com** (`docs/research/qsopartyhub.md` §5, §6.4): the form takes
`station` and `poster` as separate fields, and third-party spotting is its
normal traffic — *"every live ALQP spot was posted by `N4EMP` for other
stations"*. Posting for someone else needs no new contract, only a different
prefill.

## 1. Worked stations reach the band map

`SpotSource` gains `.local`: your own log as a feed, beside `.cluster` and
`.hub`.

`WorkedSpot.spot(for:myCall:now:)` is a pure map from a logged `QSO` to a
`Spot`:

| Field | Value |
| --- | --- |
| `call` | the QSO's call |
| `freqKHz` | the QSO's logged frequency |
| `spotter` | your own callsign |
| `county` | the QSO's `theirLoc` |
| `source` | `.local` |
| `receivedAt` | the QSO's timestamp |

`theirLoc` is deliberately used as the county even when it is a state or `DX`.
It is the same key `workedCallCounties` is built from (`CALL|THEIRLOC`), so the
spot greys out the instant it appears, and `isNeededMultiplier` scores it
through the same path every other spot uses. What it must **not** do is reach
the hub's form, where only a real county token is valid — see §2.

A QSO with no logged frequency yields no spot. That happens exactly when no
radio was connected, so there is no frequency to place it at and none to
invent.

A county-line contact expands to several rows sharing one `groupID`; it is one
contact on one frequency, so it adds one spot.

**Only when absent.** `SpotStore.addIfAbsent` adds nothing when that call is
already on the map for that band. An existing cluster or hub spot keeps its
reported frequency and simply greys out.

**Lifetime.** `.local` ages out on the operator's existing "Age out after"
setting, alongside cluster spots — one timeout for the map, as N1MM has.

**Filters.** `.local` is exempt from the source filter: "QSO Party Hub spots
only" chooses between feeds, and your own log is not one of them. "Hide
stations already worked" is the control that clears them, and clears all of
them, since every station in your log is worked by definition.

## 2. Spotting another station

`SelfSpotSheet` already titles itself "Spot to QSO Party Hub" and already
separates `station` from `poster`, so it stays the single confirm-before-send
path. Every send is confirmed, including these: the board takes anything
posted, immediately and publicly.

`HubSpotPrefill.fields(station:frequencyKHz:location:poster:party:)` builds the
sheet's fields from any origin. Its one judgement is the county: `location` is
carried only when it matches a county of the active party. An out-of-state
`TX`, a `DX`, or an exchange fragment is dropped rather than posted as a county
token. From the entry bar the exchange is scanned token by token, so `599 JOH`
and `JOH/WYD` both find `JOH`. The party's own abbreviation is what is carried;
`HubSelfSpot` translates to the board's spelling at the wire, which is the only
place that knows it.

When the origin has no frequency — a QSO logged with no radio — the sheet
opens with the frequency field empty and focused. The existing validation keeps
Post disabled until a real one is typed; a guessed frequency on a public board
is worse than an empty field.

## 3. Three ways in

| Path | Origin | Prefill |
| --- | --- | --- |
| Right-click a band map spot | `Spot` | its call, frequency, county |
| Right-click a log row | `QSO` | its call, logged frequency, `theirLoc` |
| ⌥⌘S | the entry bar | the call field, the VFO, the county in the exchange |

⌥⌘S is the keyboard path the constitution requires, and the fastest one while
running: you are already on the station. It sits in the toolbar beside Spot
Myself (⇧⌘S), disabled when the call field is empty, when the party has no hub
page, or when no callsign is set.

Nothing here posts by itself. Each path opens the sheet.

## Tests

- A logged QSO becomes a `.local` spot carrying call, frequency, county and
  your call as spotter; one with no frequency becomes nothing; a county-line
  group becomes one spot.
- `addIfAbsent` leaves an existing hub spot for that call and band untouched,
  and adds when the band is clear.
- `.local` spots survive the hub-only source filter, and are removed by hide-worked.
- `.local` spots age out on the cluster timeout.
- Prefill drops a non-party county from each origin, translates an aliased
  county to the hub's token, and finds the county inside a copied exchange.

## Out of scope

- Persisting local spots across a restart. The store is in-memory and cluster
  spots do not survive one either.
- Any automatic posting. The hub is a public board with no authentication;
  every send stays behind a confirmation.
