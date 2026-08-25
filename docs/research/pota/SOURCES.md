# POTA support — banked official sources

All sources fetched/verified 2026-08-05. N1MM and other loggers were not
consulted; the ADIF specification and POTA's own documentation and API are
the only sources of the field names, grammar, upload semantics, and park
data below.

## ADIF 3.1.4 specification
`https://adif.org/314/ADIF_314.htm` (fetched 2026-08-05)

- `MY_POTA_REF` — data type **POTARefList** — "a comma-delimited list of one
  or more of the logging station's POTA (Parks on the Air) reference(s)."
  Spec examples: `<MY_POTA_REF:6>K-0059`, `<MY_POTA_REF:7>K-10000`,
  `<MY_POTA_REF:40>K-0817,K-4566,K-4576,K-4573,K-4578@US-WY`.
- `POTA_REF` — data type **POTARefList** — the same for the contacted
  station. Examples: `<POTA_REF:6>K-5033`, `<POTA_REF:13>VE-5082@CA-AB`.
- **POTARef** — "a sequence of case-insensitive Characters representing a
  Parks on the Air park reference in the form `xxxx-nnnnn[@yyyyyy]`":
  program 1–4 characters, park number 4–5 characters (the `K-10000` example
  row notes 5-digit numbers are reserved for future use), optional `@` +
  ISO 3166-2 code of 4–6 characters for a park spanning subdivisions.
  Data-type examples: `K-5033`, `K-10000`, `VE-5082@CA-AB`, `8P-0012`,
  `VK-0556`, `K-4562@US-CA`.
- **POTARefList** — "a comma-delimited list of one or more POTARef items."
- `MY_SIG` / `MY_SIG_INFO` / `SIG` / `SIG_INFO` — String; `SIG_INFO` is "a
  description of the SIG for the contacted station", `MY_SIG_INFO` the same
  for the station operating in the QSO.
- The changelog adds all of `MY_POTA_REF`, `POTA_REF`, `POTARef`,
  `POTARefList` in 3.1.4.

## POTA ADIF technical reference
`https://docs.pota.app/docs/activator_reference/ADIF_for_POTA_reference.html`
(fetched 2026-08-05)

- Required activator fields: `STATION_CALLSIGN` or `OPERATOR`, `CALL`,
  `QSO_DATE`, `TIME_ON`, `BAND`, `MODE` (submode takes precedence when both
  appear). `AdifExporter` already emits every one of these.
- POTA processes `MY_SIG=POTA` + `MY_SIG_INFO=<park>` for the activator's
  park and `SIG=POTA` + `SIG_INFO=<park>` for park-to-park. The reference
  does not document reading `POTA_REF`/`MY_POTA_REF` at all — the SIG
  family is what earns credit. When `MY_SIG`/`MY_SIG_INFO` are missing or
  invalid, the uploader prompts during upload.
- The park fields matter "primarily when an activator is located at
  multiple parks during the same UTC day" — per-QSO values in one file.
- P2P example, one park per record: `<SIG:4>POTA` `<SIG_INFO:7>CA-0008`.

## POTA park-to-park reference
`https://docs.pota.app/docs/activator_reference/park_2_park.html`
(fetched 2026-08-05)

- "Both activators are strongly recommended (although not required) to
  record the park number of the other activator in the ADIF log file's
  SIG_INFO ADIF field."
- Working a three-fer: "list the same QSO three times in the ADIF log
  file, each with one of the three park references in SIG_INFO, with the
  rest unchanged." Otherwise "you will only get one P2P credit."
- One's own multi-park lines survive the duplicate check only with unique
  park references per line.
- P2P matching: both logs' times within 15 minutes, exact callsigns.

## POTA park data API
Verified live 2026-08-05:

- `GET https://api.pota.app/program/parks/US` — unauthenticated, JSON
  array of **12,938** parks (~2.7 MB). Entry shape, verbatim first entry:
  `{"reference": "US-0001", "name": "Acadia National Park",
  "latitude": 44.31, "longitude": -68.2034, "grid": "FN54vh",
  "locationDesc": "US-ME", "attempts": 636, "activations": 568,
  "qsos": 18900}`. Every entry carried coordinates on the verification
  date; the app decodes them optionally anyway.
- `HEAD` on the same URL → **403 MissingAuthenticationTokenException**
  (API Gateway routes GET only). Consequence: no cheap freshness probe
  exists — the client re-downloads on a weekly throttle or the operator's
  Refresh, and the first download is an explicit button.
- `Tests/Fixtures/pota_parks_sample.json` holds six entries copied
  verbatim from this payload (Acadia plus five DFW-area parks), so the
  tests exercise the real shape.

## What this bakes into the app

- Park references are validated against the POTARef grammar, verbatim above.
- The ADIF export duplicates each row's record per (my park × their park)
  pair with singular `MY_SIG_INFO`/`SIG_INFO` — POTA's documented shape —
  and stamps the matching singular `MY_POTA_REF`/`POTA_REF` on each record
  so no record contradicts itself. A single record carrying the spec's
  comma-list form would be valid ADIF but lose n-fer credit at POTA.
- The park picker searches a cached copy of the US program list and sorts
  by distance from the operator's Core Location fix or grid square — so it
  works offline at the park.

## POTA spot API — pota.app's own "Add Spot" form
Fetched 2026-08-15. POTA's documentation describes the spot page but not the
API behind it, so the contract is taken from the site's own client code — the
same standard `docs/research/qsopartyhub.md` §5 applies to the hub, where the
form's markup is the contract.

- **The activator guide** (`docs.pota.app/docs/activator_reference/activator_guide-english.html`):
  *"Self-spot on the POTA spotting page if you have access to the internet."*
  and *"If you cannot self-spot, ask your first contact on the air to spot
  you, and repeat your request once in a while to keep your spot fresh."* —
  re-spotting is expected; third-party spotting is expected. The guide does
  not mention an API.
- **The form's code.** `https://pota.app/` loads `/js/app.54fcf9fc.js`
  (content-hashed name as of the fetch date); its `SpotForm` component:
  - `save()` — verbatim, from the minified bundle:
    `var e={activator:this.activator,spotter:this.spotter,frequency:this.frequency,reference:this.reference,mode:this.mode,source:"Web",comments:this.comments};O.a.post("https://".concat("api.pota.app","/spot"),e).then((function(o){t.$store.commit("SET_SPOTS",o.data),t.$store.dispatch("addHunted",e)})).catch((function(e){t.$dialog.error({title:"Error",text:"".concat(e.response.data)})}))`
    — a JSON POST (axios' default `Content-Type: application/json`) to
    `https://api.pota.app/spot`, **no authentication header** (the
    neighbouring `ActivationForm` passes `this.$store.getters.authTokenHeader`
    to its `/activation` POST; the spot form passes nothing), the response
    body committed to the site's spot list (`SET_SPOTS(o.data)`), and an
    error's `e.response.data` shown as text.
  - `frequencyRules`: `"Frequency (kHz) required"`, `/^[\d.]+$/` with the
    message `"Example: 7123 or 14234"`, and `parseInt(t)>1e3` with the message
    `"Frequency in kHz (> 1000)"`. The field label is `"Frequency (kHz)"`.
  - `activatorRules` / `spotterRules`: required, and the store's
    `validCallsignRegex` =
    `/^(?:[A-Z\d]{1,4}\/)?[A-Z\d]{1,3}\d[A-Z\d]*(?:\/[A-Z\d]{1,4})?$/i`;
    both fields upper-case on keyup.
  - `referenceRules`: required, and the store's `validReferenceRegex` =
    `/^[A-Z0-9]{1,2}-[0-9]{4,5}$/` **or the literal `"K-TEST"`**.
  - `mode`: taken from a prop (`pmode`) — set when re-spotting an existing
    spot; a new spot from the form carries whatever it was given, and the
    form's own hint reads: *"Wrong mode? Mention a mode in the Comments field
    to change the mode for this spot (e.g. "QSY CW", "RTTY" or "Switching to
    FT8"). Mention QRT if this activator is no longer on the air to mark this
    spot as finished."* The client-side preview (`scanComments`) checks each
    comment word against the ADIF submode list, folding LSB/USB to SSB — so a
    mode word in the comment overrides the mode field, server-side.
  - `comments`: free text; the anonymous form shows the field read-only
    ("Login to add a comment") but still posts it.
- **The site reads spots from** `GET https://api.pota.app/v1/spots`
  (`getSpots` in the store). `GET https://api.pota.app/spot/activator` serves
  the same list in a shorter shape (verified 2026-08-15: both returned 162
  rows). Row shape, verbatim first row of `/spot/activator`:
  `{"spotId": 55209219, "activator": "W8EKM", "frequency": "21320",
  "mode": "SSB", "reference": "US-6653", "parkName": null,
  "spotTime": "2026-08-15T16:04:15", "spotter": "W8EKM", "comments": "CQ",
  "source": "Web", "invalid": null, "name": "Dansville State Game Land",
  "locationDesc": "US-MI", "grid4": "EN72", "grid6": "EN72um",
  "latitude": 42.5111, "longitude": -84.3128, "count": 9, "expire": 1764}`.
- **Live board observations, 2026-08-15 16:05Z (162 spots):** `source`
  carried other loggers' names verbatim — `Ham2K Portable Logger` (17),
  `HAMRS Pro/2.52.0` (2), `GT2` (13), `GT` (7), `POTACAT` (2),
  `Smart Logger` (3), `Greyline FT8` (1), beside `Web` (74) and `RBN` (41) —
  so a logger posting under its own name is the norm; 11 spots carried
  `mode: ""`, so an empty mode is accepted; frequencies came as `"14039.5"`,
  `"14062.0"` and `"18101"` alike; comments included `"Self-spot via HAMRS
  Pro"`, `"QRT"`, `"Moved 2-fer: US-1044 US-3791"`.
- `Tests/Fixtures/pota_spots_sample.json` holds five rows copied verbatim
  from that payload (W8EKM, K1SN, KQ4TAX, N4GBN with `"source": "HAMRS
  Pro/2.52.0"`, and one RBN row), so the tests exercise the real shape.
- **No test post was made.** The board is public and a test spot is a real
  spot; the first live send is verified by the POST's own response — the
  board's list — and, failing that, by two follow-up reads of
  `/spot/activator`.

### What this bakes into the app

- `PotaSpot` posts exactly the form's seven keys as JSON to
  `https://api.pota.app/spot`, `source: "QSOPartyLogger"`, frequency as
  clean-kHz text, calls upper-cased, the reference through the ADIF grammar
  with any `@subdivision` dropped (the page's regex has no room for one),
  and validates with the form's own regexes and its `> 1000` kHz rule.
- A 2xx whose body is the board's list and shows the spot is `confirmed` at
  once; a 2xx that does not is `sent` and looked for on `/spot/activator` at
  +10 s and +40 s; a non-2xx shows the server's own text when it is a
  readable line, else the status.
- The mode sent is the ADIF mode of the radio's current mode
  (`AdifExporter.adifMode` — USB/LSB → SSB), editable in the sheet; the
  comment is the operator's own words, uncombined with the county, because
  a mode word in the comment overrides the mode field.

## POTA rules for the dedicated mode
Fetched 2026-08-25, for the POTA contest mode
(`docs/superpowers/specs/2026-08-25-pota-mode-and-callbook-design.md`).

From `https://docs.pota.app/docs/rules.html`:

- **Validity** (Activations / Attempts): *"A successful activation requires a
  minimum of 10 QSOs from a park in the designated list within a single UTC
  day (Zulu day)."*
- **Sessions combine** (same section): *"Multiple activities at the same park
  in the same state/province/entity and the same UTC day count as a single
  activation, provided that the ten or more QSOs combined were made."*
- **Required log fields** (Logging Requirements): `STATION_CALLSIGN` or
  `OPERATOR`, `CALL`, `QSO_DATE`, `TIME_ON`, `BAND`, and `MODE` or `SUBMODE`
  — the same list the ADIF technical reference above carries.
- **Separate log per park** (Activation Location and Access): *"Such a
  multi-park activation requires an overlapped area where all activated
  parks' boundaries intersect. The intersection must entirely contain the
  activator and the station equipment."* and *"A separate log must be
  submitted for each park of the multi-park simultaneous activation."*
- **OPEN QUESTION — does the ten dedupe?** The rules page addresses duplicate
  QSO rejection in logging but says nothing about whether working the same
  station twice (same band, mode, UTC day) counts once or twice toward the
  10-QSO minimum. The app's validity meter counts the stricter unique form
  — unique (call, band, mode) per own park per UTC day — which can only
  under-promise. Re-check each season.

From `https://docs.pota.app/docs/activator_reference/submitting_logs.html`:

- **File naming**: *"follow the filename format:
  `callsign@parkNumber-activationDdate.adi` (e.g.,
  KA8H@US-1515-20201127.adi)"* (the template's "Ddate" typo is the page's
  own). Multi-state parks: *"If the park spans multiple states, include the
  activation state (i.e., W8MSC@US-4239-20181231-US-MI.adi)."* — the state
  suffix rides after the date.
- **Advisory for the self-uploader**: the format is stated as a requirement
  only *"When submitting logs via email"*; the normal path is *"Upload from
  My Log Uploads page of pota.app"*, email fallback via a helpdesk ticket to
  help@parksontheair.com.
- **One file may span sessions**: *"It is recommended to combine logs from a
  single activation into a single ADIF file where applicable (same park and
  same station callsign), although not required."*

### What this bakes into the app

- `PotaStats.validationTarget = 10`, counting unique (call, band, mode) per
  own park per UTC day — the meter is advisory UI, never a score.
- `AdifExporter.exportForPota` writes one file per own park;
  `AdifExporter.potaFileName` produces `CALL@US-1234-YYYYMMDD.adi`, with a
  park's `@subdivision` appended after the date (`-US-MI`), matching the
  W8MSC example.
- `pota.json`'s dupe rule: `bandMode` scope with `utcDay` and `perMyPark` —
  a new UTC day or a rove to a new park makes the same station workable
  again, POTA's per-activation scoring.
