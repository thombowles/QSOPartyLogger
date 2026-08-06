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
