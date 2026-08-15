# Spotting to several networks at once — design

**Date:** 2026-08-15 · **Status:** approved for implementation (autonomous
session — the open calls in §10 default as stated; Tom evaluates the build)

KE5CW runs QSO parties from a POTA park with a cluster node open. One contact
found, one CQ frequency settled on, and the same fact wants to reach three
audiences: the DX cluster (his node is WA9PIE's DXSpider, `dxc.wa9pie.net`),
the party's board on qsopartyhub.com, and the POTA spot page. Today ⇧⌘S
composes a spot for the hub alone, and the other two mean two more apps and
retyping the frequency twice — which is why operators stop spotting.

The request: **one spot, sent to every network that applies, from one sheet,
with one keystroke** — and the operator always knowing what went where.

## Sources

Every wire contract below traces to the network's own material, fetched
2026-08-15, and is banked verbatim in `docs/research/` in the same commit as
the behavior (constitution rule 1). No other logger was consulted for a rule.

- **POTA spot API — pota.app's own "Add Spot" form.** `https://pota.app/`
  loads `/js/app.54fcf9fc.js`; its `SpotForm` component's `save()` posts
  `{activator, spotter, frequency, reference, mode, source: "Web", comments}`
  as JSON to `https://api.pota.app/spot` with **no authentication header**
  (the neighbouring `ActivationForm` passes `authTokenHeader`; the spot form
  does not), then commits the response body to the site's spot list
  (`SET_SPOTS(o.data)`), and on error shows `e.response.data` as text. Its
  field rules: `frequencyRules` — "Frequency (kHz) required", `^[\d.]+$`
  ("Example: 7123 or 14234"), `parseInt > 1000` ("Frequency in kHz (>
  1000)"); `activatorRules`/`spotterRules` — the store's
  `validCallsignRegex` `/^(?:[A-Z\d]{1,4}\/)?[A-Z\d]{1,3}\d[A-Z\d]*(?:\/[A-Z\d]{1,4})?$/i`;
  `referenceRules` — `validReferenceRegex` `/^[A-Z0-9]{1,2}-[0-9]{4,5}$/` or
  the literal `K-TEST`. The form's own hint: *"Wrong mode? Mention a mode in
  the Comments field to change the mode for this spot (e.g. "QSY CW", "RTTY"
  or "Switching to FT8"). Mention QRT if this activator is no longer on the
  air to mark this spot as finished."* The site itself reads spots from
  `GET https://api.pota.app/v1/spots`; `GET https://api.pota.app/spot/activator`
  serves the same list in a shorter shape.
- **POTA live board, `GET /spot/activator`, 2026-08-15 16:05Z** — 162 spots;
  `source` carried other loggers' names verbatim (`Ham2K Portable Logger`,
  `HAMRS Pro/2.52.0`, `GT2`, `POTACAT`, `Smart Logger`, `Greyline FT8`, plus
  `Web` and `RBN`), so a logger posting under its own name is the norm; 11
  spots carried `mode: ""`, so an empty mode is accepted; frequencies came as
  `"14039.5"`, `"14062.0"` and `"18101"` alike.
- **POTA activator guide** (`docs.pota.app/docs/activator_reference/activator_guide-english.html`):
  *"Self-spot on the POTA spotting page if you have access to the internet."*
  and *"If you cannot self-spot, ask your first contact on the air to spot
  you, and repeat your request once in a while to keep your spot fresh."* —
  re-spotting is expected, third-party spotting is expected.
- **DXSpider User Manual v1.51, "Getting and posting DX"**
  (`dxspider.org/usermanual_en-4.html`; also `wiki.dxcluster.org/wiki/Getting_and_posting_DX`):
  *"dx (frequency) (callsign) (remarks)"* where *"frequency is in kilohertz
  and the callsign is the callsign of the station you have worked or heard,
  (ie not your own callsign!)"*; *"DXSpider will allow the frequency and
  callsign fields to be entered in any order"*; examples
  `dx 14004 pa3ezl OP Aurelio 599`; and — the confirmation mechanism —
  *"This posting, or callout as it is known, will be forwarded to all other
  connected stations both at the cluster you are connected to and other
  active clusters in the network. The callout will also be sent to you as
  proof of receipt."* The command reference
  (`wiki.dxcluster.org/wiki/DXSpider_User_Command_Reference`, last modified
  17 July 2025): `dx [by <call>] <freq> <call> <remarks> - Send a DX spot`.
- **AR-Cluster manual, DX command** (`ng3k.com/Cluster/dx.html`, mirroring
  the AR-Cluster user manual): `DX frequency callsign misc-info`, frequency
  *"14025.10, for example"*, *"Misc-info should be kept brief as the system
  will add the date and time after it"*, *"Misc-info is optional"*. Frequency
  first is the form both node families accept.

Neither manual states a remark length limit, so none is enforced; the
comment is sanitised (no CR/LF — a newline would end the command early) and
shown in full before it goes.

---

## 1. Approaches considered

1. **One sheet, a row of network toggles** *(chosen)*. ⇧⌘S keeps its one
   meaning (Run → you, S&P → the call field), the sheet gains a **Send to**
   section listing every network with a checkbox, and Return posts to every
   ticked one concurrently. Each network's own fields (the hub's county, POTA's
   park and mode) live inline on its row. The choice of networks is
   remembered.
2. **One command per network** (⇧⌘S hub, ⌥⇧⌘S cluster, ⌃⇧⌘S POTA).
   Rejected for the reason `SpotCommand` already records: *"Two spot commands
   a single modifier apart is how a sheet ends up open with your own call in it
   mid-QSO."* It also triples the retyping the feature exists to remove.
3. **Spot profiles that post without a sheet** ("always spot to cluster + hub
   + POTA"). Rejected: every send is confirmed because the hub's form has no
   authentication and reaches a public board at once, and fanning one press
   out to three public boards makes that rule more important, not less.

## 2. The networks

| Network | Transport | Available when | Confirmed by |
| --- | --- | --- | --- |
| **DX cluster** | the open telnet session, `DX <kHz> <call> <remarks>` | `SpotClient.status == .connected` (so never under NON-ASSISTED, which cannot connect) | the node echoing the spot back — *"proof of receipt"* — seen as an incoming `Spot` whose spotter is us and call is the station |
| **QSO Party Hub** | the existing multipart POST | the party has a `hubSpots` page | the next poll showing the call (existing) |
| **POTA** | JSON POST to `api.pota.app/spot`, `source: "QSOPartyLogger"` | spotting yourself: the log is an activation (`myPotaRefs` non-empty); spotting another station: a park reference is in the draft | the POST's response body — the board's spot list — containing our activator + reference; else one follow-up `GET /spot/activator` at +10 s and +40 s |

Availability is a pure function (`SpotNetworkAvailability`), so every reason
string is testable and no view decides policy:

- cluster: `.available("dxc.wa9pie.net")` / `.unavailable("Not connected — Spots ▸ Connect")` / under NON-ASSISTED, `SpottingPolicy.blockedReason`.
- hub: `.available("qsopartyhub.com")` / `.unavailable("This party has no page on qsopartyhub.com")`.
- POTA, myself: `.available("pota.app · US-0817")` / `.unavailable("Set your park in Contest Setup to spot yourself on POTA")`.
- POTA, another station: available once the draft's park field holds a
  reference pota.app accepts; until then `.unavailable("Enter their park to spot them on POTA")`. The field sits on the row, so typing one enables the checkbox — the operator then ticks it (⌘3); nothing ticks itself.

Availability is recomputed on every redraw of the sheet from live state (the
cluster's status, the draft's park), not frozen at open.

The whole command is enabled when a callsign is set and **at least one**
network is available; otherwise the toolbar button is disabled with a help
text naming all three ways to get one.

## 3. Core types (`Sources/Core/Spotting/`)

- **`SpotNetwork`** — `enum { cluster, hub, pota }`, `CaseIterable`,
  `Codable` by raw value. `displayName` ("DX cluster", "QSO Party Hub",
  "POTA"), `shortName` ("Cluster", "Hub", "POTA"), `shortcutDigit` (1/2/3
  — ⌘1/⌘2/⌘3 toggle the row in the sheet). Plus the pure preference rule
  `updatedPreference(preferred:available:selected:)`: only the networks the
  sheet actually offered move; a network that was unavailable keeps its old
  bit, so being at home one weekend never un-ticks POTA for the next park.
- **`SpotNetworkAvailability`** — the §2 rules; input is a plain
  `Context` struct (cluster status + host, assisted claim, hub host, target
  kind, my parks, draft park).
- **`SpotDraft`** — the sheet's model: `station`, `frequencyKHz`,
  `county: String?` (party term), `comment`, `poster`, `park`, `mode`,
  `networks: Set<SpotNetwork>`. Derives each network's payload:
  `hubFields` (`HubSelfSpot.Fields`), `clusterFields(party:)`
  (`ClusterSpot.Fields`), `potaFields` (`PotaSpot.Fields`); and
  `problem(for:party:)` asks each network's own validator, so the sheet
  shows a problem under the row it belongs to. `problems(party:)` covers the
  ticked networks; **Post is enabled only when at least one network is ticked
  and none of the ticked ones has a problem** — the operator fixes it or
  unticks it, nothing is skipped silently.
- **`ClusterSpot`** — pure. `Fields { call, frequencyKHz, remarks }`;
  `command(fields)` → `"DX 7047 KE5CW AL-QSO-PARTY MDSN MOBILE"`; the
  remarks are composed by `remarks(party:county:comment:)` = the party's
  Cabrillo contest name (the sponsor's own identifier — the one party-neutral
  tag there is), then the county (the cluster has no county field of its
  own), then the operator's comment, single-spaced, CR/LF and control
  characters removed. `validate` — call and frequency present. `isEcho(spot,
  fields, poster)` — spotter == poster, call == station, frequency within
  0.5 kHz. Frequency text via **`SpotFrequency.text(kHz:)`**, the clean-kHz
  formatter lifted out of `HubSelfSpot` (which now delegates, so its
  byte-pinned tests still hold).
- **`PotaSpot`** — pure. `Fields { activator, spotter, frequencyKHz,
  reference, mode, comments }`; `validate` — the form's own rules verbatim
  (callsign regex on both calls, reference regex or `K-TEST`, frequency >
  1000 kHz); `reference` is normalised through `PotaRef.normalize` first with
  any `@subdivision` suffix dropped, because the spot page's regex has no
  room for one. `jsonBody(fields)` — sorted keys, `source: "QSOPartyLogger"`,
  frequency as clean kHz text. `contains(spot:in responseData:)` — decodes
  the board's array leniently (`activator`, `reference`, `spotter`,
  `frequency`, `mode`, `spotTime`, `source`) and answers whether ours is on
  it. Problem strings in the app's inline voice.
- **`SpotSendState`** — `idle, sending, sent(Date), confirmed, failed(String)`
  — lifted from `HubSpotClient.SendState`, now shared by all three networks.
- **`SpotReceipt`** — pure model of one dispatch: station, frequency, the
  moment it began, and `states: [SpotNetwork: SpotSendState]`. Wording lives
  here so tests pin it: `line(for:)` ("Hub — on the board", "Cluster —
  echoed by the node", "Cluster — sent", "POTA — on pota.app", "POTA —
  Couldn't reach pota.app"), `tint` (any failed → orange; every entry
  confirmed → green; otherwise secondary — "sent" is provisional and stays
  neutral), `failedNetworks`, and visibility as a pure function of time:
  `isVisible(now:)` is true from the last state change until 12 s later
  when nothing has failed and 60 s later when something has (long enough to
  read and act; the consoles keep the record). A change that lands after the
  capsule has gone — the hub's poll saying the spot never appeared —
  re-shows it for another window; `dismiss()` records the moment and hides
  everything up to it, so a later change still surfaces.
- **`SpotRepeat`** — the hub's five-minute identical-spot guard generalised:
  `isRepeat(payload, of previous, lastSentAt, now)`; `HubSelfSpot.isDuplicate`
  delegates.

## 4. App clients (`Sources/App/`)

- **`PotaSpotClient`** (`@MainActor @Observable`) — `SCPClient`/`PotaParkClient`
  posture: quiet, inline, never modal. `post(_ fields:)` builds the request
  (`Content-Type: application/json`, the app's User-Agent), sends through a
  **`PotaSpotPosting`** seam (`send(URLRequest) async throws -> (Data,
  HTTPURLResponse)`; tests script it), and sets `sendState`: 2xx with our spot
  in the body → `.confirmed`; 2xx without → `.sent`, then the two follow-up
  GETs; non-2xx → `.failed(<server's text, or the status>)`; transport error
  → `.failed("Couldn't reach pota.app: …")`. Identical spot within five
  minutes → refused before any network. `onSendStateChange` callback,
  `console` lines, `lastError`.
- **`HubSpotClient`** — adopts `SpotSendState`, gains `onSendStateChange`;
  otherwise unchanged (its own tests keep passing).
- **`SpotDispatcher`** (`@MainActor @Observable`) — the one place a draft
  becomes sends. `send(draft, party, now)`: for each ticked network, sets the
  receipt entry to `.sending` and calls the network's transport (a
  `Transports` struct of closures, so tests script all three without TCP or
  HTTP): cluster → `sendClusterCommand(String) -> Bool` (false when not
  connected → `.failed("Cluster not connected")`, true → `.sent`); hub →
  `postToHub(HubSelfSpot.Fields)`; POTA → `postToPota(PotaSpot.Fields)`.
  `update(network, state)` receives the clients' state changes and writes
  them into the *current* receipt only when that receipt includes the
  network. `noteIncomingSpot(_:now:)` — the cluster echo: while the receipt's
  cluster entry is `.sent`, an incoming spot matching `ClusterSpot.isEcho`
  flips it to `.confirmed`; nothing ever fails for a missing echo (a
  `reject/spot` filter on the node would hide it, and the manual promises the
  echo, not the absence of filters). `dismiss()`.

## 5. The sheet (`Sources/UI/SpotSheet.swift`, renamed from `SelfSpotSheet`)

Compact, keyboard-first, everything visible before it goes:

```
Spot Myself                                   (or "Spot N4RT")
Return posts to every network ticked below, publicly. Esc cancels.

Call spotted   [KE5CW   ]
Frequency      [7047    ] kHz
County         [MDSN    ]            (party's own term; hub + cluster remarks)
Comment        [MOBILE  ]

Send to
☑ DX cluster · dxc.wa9pie.net              ⌘1     DX 7047 KE5CW AL-QSO-PARTY MDSN MOBILE
☑ QSO Party Hub · qsopartyhub.com          ⌘2     KE5CW 7047 MDSN
☑ POTA · pota.app   Park [US-0817] Mode [CW]  ⌘3  US-0817 · CW · KE5CW
☐ …unavailable network, greyed, with its reason in place of the preview

Posted by KE5CW                                    [Cancel]  [Post Spot]
```

- Each row: checkbox (disabled with the reason when unavailable), the
  network's name and host, and a monospaced **preview of exactly what will
  go out** — the whole point of a confirming sheet is that nothing is a
  surprise. Problems appear under the row they belong to, in the app's
  orange inline style.
- ⌘1/⌘2/⌘3 toggle the rows from the keyboard; the digits are shown as
  hints. Space on a focused checkbox still works.
- POTA's row carries its **park** (prefilled: your first park when spotting
  yourself — POTA takes one reference per spot; the other station's park
  from the entry bar's P2P field or the log row's `theirPotaRefs` when
  spotting them) and **mode** (prefilled `AdifExporter.adifMode(currentRawMode)`,
  so USB/LSB go out as `SSB`; editable, since the manual mode picker is what
  stands in with no radio).
- Initial focus keeps today's rule (blank station → station; blank frequency
  → frequency; else station).
- Nothing about the sheet is party-specific: the county label is
  `party.countyTerm`, the hub row exists only through `party.hubSpots`.
- The initial tick set is `available ∩ preferred`; on Post the preference
  updates by `SpotNetwork.updatedPreference`.

Right-click **Spot … to QSO Party Hub…** on the band map and the log becomes
**Spot …** (the sheet decides the networks). The rover county-change offer
and the mode-driven ⇧⌘S routing are unchanged.

## 6. The receipt

The sheet closes on Post — hands back on the keyboard at once — and a
**receipt capsule** appears in the station strip, live:

```
◉ KE5CW 7047 · Hub — on the board · Cluster — echoed by the node · POTA — sending…   [Retry] [×]
```

- Secondary while anything is still in flight, green once every ticked
  network is confirmed or sent, orange when any failed. The tooltip carries
  each network's full line, including the server's own failure text.
- Auto-dismisses per `SpotReceipt.expires(at:)`; × dismisses now; a new spot
  replaces it. **Retry** appears when something failed and reopens the sheet
  with the same draft and only the failed network(s) ticked — the operator
  confirms again, which is the rule; nothing re-posts by itself.
- Fixes a standing gap: `HubSpotClient.sendState` — *"confirmed on the
  board"* — was tracked and never shown; the README promised it since July.

## 7. Wiring (`MainView`)

`SpotDispatcher` and `PotaSpotClient` join the view's clients. `onAppear`
sets `hubSpotClient.onSendStateChange` / `potaSpotClient.onSendStateChange`
→ `dispatcher.update`, and chains `spotClient.onSpot` so every incoming
cluster spot also reaches `dispatcher.noteIncomingSpot` (the echo). The
sheet's `onSend` calls `dispatcher.send(draft, party:)` and persists the
preference. `canSpotToHub` becomes `canSpot` (callsign set and any network
available); the band map model and log table take the same flag. The
receipt is one extracted view (`SpotReceiptView`, its own file) inserted in
the station strip — the left pane's type-checker budget is respected by
adding nothing inline.

## 8. Settings

`AppSettings.spotNetworks: [String]` (raw values; default all three) through
`Preferences.store`. No other persistence: the draft is rebuilt from live
state on every open, as today.

## 9. Tests and docs

| Area | File | What it pins |
| --- | --- | --- |
| Availability | `Tests/Core/SpotNetworkAvailabilityTests.swift` | every rule and reason string in §2; NON-ASSISTED reason is the policy's own |
| Preference | `Tests/Core/SpotNetworkTests.swift` | `updatedPreference` moves only offered networks; initial selection = available ∩ preferred; raw-value round trip |
| Draft | `Tests/Core/SpotDraftTests.swift` | per-network payload derivation; problems keyed to their network; Post gate (none ticked / a ticked problem) |
| Cluster | `Tests/Core/ClusterSpotTests.swift` | command text byte-for-byte; remarks order and sanitising (CR/LF, control chars, collapsing); no county → no token; echo matching (spotter, call, 0.5 kHz) |
| POTA | `Tests/Core/PotaSpotTests.swift` | the form's own regexes (accept/reject sets); frequency rule; `@`-suffix dropped; JSON body byte-for-byte; response parsing against a fixture copied verbatim from the live board (`Tests/Fixtures/pota_spots_sample.json`); confirmation found/not found |
| Receipt | `Tests/Core/SpotReceiptTests.swift` | lines, tint, expiry (12 s / 60 s), failed set |
| Repeat guard | `Tests/Core/HubSelfSpotTests.swift` (existing) + `SpotRepeat` cases | window and inequality |
| POTA client | `Tests/App/PotaSpotClientTests.swift` | scripted poster: confirmed from body; sent then confirmed by follow-up; sent then failed after two misses; 4xx text surfaced; transport error; five-minute repeat refused |
| Dispatcher | `Tests/App/SpotDispatcherTests.swift` | only ticked networks are called; states per network; cluster not connected → failed; echo → confirmed; stale updates ignored; dismiss |
| Settings | `Tests/App/PreferenceIsolationTests.swift` (existing pattern) | `spotNetworks` round trip and default |

README in the same commit: the "Self-spotting (⇧⌘S)" section becomes
"Spotting to the networks (⇧⌘S)" with the availability table and the receipt;
the keyboard row for ⇧⌘S and the ⌘1/⌘2/⌘3 sheet toggles; the POTA section
gains a spotting bullet; the test count. `docs/research/pota/SOURCES.md` gains
the spot-API section; `docs/research/dxcluster-dx-command.md` is new;
`docs/PROVENANCE.md` lists both. UI verification is by build and Tom's own
eyes, per standing practice.

## 10. Open calls — defaults chosen

1. **Cluster remarks carry the Cabrillo contest name** (default) — or the
   county alone? The name is what tells a reader outside the party what the
   spot is; the preview shows it before it goes.
2. **One POTA spot per send, first park prefilled** (default) — or one spot
   per park of an n-fer? The board's own traffic mentions the second park in
   the comment ("Moved 2-fer: US-1044 US-3791"); the field is editable.
3. **Missing cluster echo stays "sent"** (default) — never "failed".
4. **Retry reopens the sheet** (default) — not a silent re-post.
5. **Receipt expiry 12 s / 60 s** (default).

## Out of scope

Reading POTA spots onto the band map; SOTA/WWFF; posting through the DX
cluster's `DX by <call>` form; a spot log or history; scheduling re-spots.
