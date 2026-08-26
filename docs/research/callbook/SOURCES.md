# Callbook lookup — banked official sources

Both services' own documents, fetched 2026-08-25, plus live-probe notes from
2026-08-24 (root elements and running versions). N1MM and other loggers were
not consulted; these pages and the live endpoints are the only sources of
the URL shapes, session semantics and field names below.

## QRZ.com XML Data Interface
`https://www.qrz.com/docs/xml/current_spec.html` — "Version: 1.34",
"Date: July 15, 2020" (fetched 2026-08-25). The live server stamps
`version="1.36"` on responses (probed 2026-08-24); no 1.36 document is
published. Per the spec, the version attribute "represents the QRZ XML
version currently in use" — **the version is data, never a gate**.

- **Login** (Access Methodology, verbatim example):
  `https://xmldata.qrz.com/xml/current/?username=xx1xxx;password=abcdef;agent=q5.0`
  — separators may be `;` or `&`; values must be percent-encoded
  defensively (the spec is silent on reserved characters in passwords).
- **Lookup** (Callsign Lookups, verbatim example):
  `https://xmldata.qrz.com/xml/current/?s=f894c4bd29f3923f3bacf02c532d7bd9;callsign=aa7bq`
- **Session lifetime** (Access Methodology, verbatim): *"Session keys are
  dynamically managed by the server and have no guaranteed lifetime."*
  *"Client programs should cache all session keys provided by the server
  and reuse them until they expire."* *"A session key is valid only for a
  single user and may become immediately invalidated if it is detected
  that the user's IP address or other identifying information changes
  after login has been completed."* — so: **one login, cached key, re-login
  only when the server says the session died. Never login per lookup.**
- **Errors** (Error Conditions, verbatim): *"Should a session expire or
  become invalidated, the `<Key>` field will not be sent."* (example:
  `Session Timeout`). *"A special Error message, `Connection refused` is
  significant in that it indicates that service is refused for the given
  user. No further explanation is given, however, it does indicate that
  successful login will not be possible for at least 24 hours."* — the
  client backs the service off for a day on sight.
- **Errors ride beside valid data**: *"Both Error and Message responses
  should be presented to the end user."* An error can appear in a response
  that still carries a `<Key>` — check every response, not just login.
- **The agent parameter** (Session Input Fields, verbatim): *"The use of
  the agent parameter is strongly recommended as it assists in
  troubleshooting and end user support."* Ours: `QSOPartyLogger/<version>`.
- **Non-subscriber access** (Overview, verbatim): *"While any QRZ user may
  login to the service, an active QRZ Logbook Data subscription is
  required to access most of its features. Non-subscriber access limits
  the data fields that are returned and is primarily intended for testing
  and troubleshooting purposes only."* The withheld-data signal is a
  **Message**, not an Error: *"A subscription is required to obtain the
  complete data"*. **OPEN QUESTION:** the spec nowhere enumerates the
  free tier's exact field set; the app assumes nothing about it and shows
  whatever comes back. (The operator's own QRZ account is the free tier.)
- **Fields that matter for logging** (Callsign node table): `fname` +
  `name` (or `name_fmt`), `addr2` (city), `state`, `county`, `grid`,
  `email` — and the entity pair, verbatim: *"`country` — country name for
  the QSL mailing address"*; *"`land` — DXCC country name of the
  callsign"*. **`land`/`dxcc` is the entity; `country` is mail.**
- **Parsing**: top-level node `<QRZDatabase>` with `version` and `xmlns`
  attributes; live namespace `http://xmldata.qrz.com` (note http:// even
  over HTTPS transport, probed 2026-08-24). Elements Capitalized
  (`Session`, `Callsign`); field order not guaranteed — parse by name,
  namespace-tolerant. XML only; no JSON exists for callsign data.

## HamQTH.com XML callbook
`https://www.hamqth.com/developers.php` (fetched 2026-08-25). Docs print
`version="2.7"`; the live server answers 2.8 (probed 2026-08-24) — same
rule, the version is data.

- **Login** (verbatim): `https://www.hamqth.com/xml.php?u=username&p=password`
  answering `<HamQTH version="2.7" xmlns="https://www.hamqth.com">`
  `<session><session_id>09b0ae90…</session_id></session></HamQTH>`.
- **Session lifetime** (verbatim): *"Session ID is valid for one hour."*
  The client renews on the clock (a minute early) and on the expiry error.
- **Lookup** (verbatim):
  `https://www.hamqth.com/xml.php?id=<session>&callsign=ok2cqr&prg=YOUR_PROGRAM_NAME`
  — `prg` is *"Name of the application using XML search (without
  spaces)"*, in every documented example; treated as required. Ours:
  `QSOPartyLogger`.
- **Errors** (verbatim strings): `Wrong user name or password`,
  `Session does not exist or expired`, `Callsign not found` — all inside
  `<session><error>…</error></session>`.
- **Fields** (callsign search): `nick`, `qth`, `country`, `adif` (DXCC
  entity id), `itu`, `cq`, `grid`, the `adr_*` address family, `district`,
  `us_state`, `us_county`, `oblast`, `dok`, `iota`, QSL flags, `email`,
  `latitude`/`longitude`, `continent`, `utc_offset` — for logging: `nick`,
  `grid`, `us_state`, `us_county`, `qth`, `country` + `adif`.
- **Free** (verbatim): *"Everything provided by this website is free of
  charge and doesn't have any limits."* (a registered account is still
  required to use the XML callbook).
- **HTTPS** (verbatim): *"The HamQTH API is available also on http but
  it's only for backward compatibility. Using secure version is highly
  recommended!"* — the app uses https only.
- **Parsing**: root `<HamQTH>`, namespace `https://www.hamqth.com`,
  elements lowercase (`session`, `search`, `error`) — the opposite case
  convention to QRZ; one namespace-tolerant scanner serves both.

## What this bakes into the app

- `QRZXML` / `HamQTHXML` (Sources/Core/Lookup): URL builders that
  percent-encode credentials and calls, parsers that read every response's
  error and message, and the recognisers the client's session logic keys
  on (`Session Timeout` → one re-login; `Connection refused` → 24-hour
  backoff; `Session does not exist or expired` → renew; the not-found
  strings are misses, not failures).
- `CallbookClient` logs in once per session per service, caches the QRZ
  key indefinitely and the HamQTH id for its documented hour, and never
  logs in per lookup.
- `CallbookRecord.country` is QRZ's `land` / HamQTH's `country`;
  `dxccID` is QRZ's `dxcc` / HamQTH's `adif`. QRZ's `country` (the QSL
  mailing address) is deliberately not read.
- A 30-day on-disk cache in front of both services, so a call is asked
  about at most monthly.
