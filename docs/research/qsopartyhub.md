# QSO Party Hub — spot source research

**Source:** `http://qsopartyhub.com` — a volunteer-run spotting board several
QSO party sponsors direct their operators to for self-spotting.

**Fetched:** 2026-07-25. **Verified:** partial — open questions in §6.

Sponsors linking to it, from rules already banked in this repo:

- `docs/research/sdqp_rules_page.txt:94` — "In-State Operators please spot
  yourself at http://qsopartyhub.com/sdqp-spots.php"
- `docs/research/iaqp_page.txt:34` — `http://qsopartyhub.com/iaqp-spots.php`
- `docs/research/paqp_rules_2025.txt:363` — `http://qsopartyhub.com/paqp-spots.php`

---

## 1. Why this source exists

A DX cluster spot never carries a county. A hub spot does, and the county is
the multiplier a state QSO party is scored on. That one field is the entire
reason to poll this site — **not** volume. A live sample during the 2026
Alabama QSO Party held four spots from a single spotter, against the hundreds
a cluster carries. It is a complement to cluster spotting, never a replacement.

## 2. Page structure

Each party has two pages:

| Page | Role |
| --- | --- |
| `{prefix}-spots.php` | Human-facing: self-spot form, plus an iframe holding the table |
| `{prefix}-table.php` | The spot table itself — what this app polls |

The public page is a WebSite X5 wrapper; the table is server-rendered HTML with
no JavaScript dependency, about 5 KB.

**The table URL must be read from the page's iframe, never guessed from the
party id.** `caqp-table.php` exists and returns a well-formed but permanently
empty table, while the California page actually embeds the shared
`qp-table.php`, which 302-redirects. A prefix guess produces a poller that runs
forever, never errors, and shows nothing.

### Table markup

```html
<table id=spots>
  <tr><th>TIME (UTC)</th><th>SPOT</th><th>FREQ</th><th>QTH</th>
      <th>COMMENT</th><th>POSTER</th></tr>
  <tr class='age1bg'><td>2024-10-12 23:12:23</td><td>KT0A</td><td>14.041</td>
      <td>FALL</td><td></td><td>KT0A</td></tr>
</table>
```

- Row `class` is the age bucket: `age1bg` <6 min, `age2bg` 6–25, `age3bg`
  25–45, `age4bg` 45–60. Older than 60 minutes is dropped server-side.
- `TIME` is absolute UTC, so a spot's true age survives a first poll.
- The preceding `<table id=agekey>` is **never closed**, so strict HTML/XML
  parsers choke. Row extraction must be lenient.
- The page carries `<meta http-equiv="refresh" content="53">`, which sets the
  expectation for polling cadence.
- No `ETag`, no `Last-Modified`, no `Cache-Control` — conditional GET is not
  available.
- Port 443 serves a **self-signed certificate**, so the site is HTTP-only and
  needs a scoped ATS exception.

## 3. Coverage

**17 of 19 bundled parties.** Generated and asserted by
`docs/research/gen_hub_map.py`; banked in `qsopartyhub_map.json`.

Not served:

- **CQP** — `caqp-spots.php` is an unfinished sponsor template. It still reads
  "The California QSO Party allows/does not allow self-spotting", has no
  self-spot form, and embeds the redirecting `qp-table.php`.
- **WA Salmon Run** — `waqp-spots.php` returns 404. `waqp-table.php` exists but
  is an orphan shell no page links to.

Three served parties use a prefix that is not the party id: `mdc`→`mdcqp`,
`tqp`→`txqp`, `hqp`→`hiqp`.

## 4. County tokens

Each page's county `<select>` carries that party's own token list. Seventeen
parties expose one; sixteen match our official county lists **exactly**,
including TQP's 254.

One divergence: **Illinois spells Pulaski `PULS`; the official ILQP
abbreviation list (`ilqp_counties.txt:9`) spells it `PULA`.** Ours is correct
per Article 1, so the hub token is aliased inbound — and must be translated
back when self-spotting, because `PULS` is the only value the hub's form
accepts.

## 5. Self-spot form

```
POST /{prefix}-spots.php        enctype: multipart/form-data
  station    required   max 15    call spotted
  frequency  required   max 10    kHz — the form's own placeholder is "14150"
  county     optional             a hub token, from the page's <select>
  comment    optional   max 50
  poster     required   max 15    the spotter's call
```

No CSRF token, no authentication, no session. Anything posted reaches a public
board immediately, and a repeated submit posts twice.

## 6. Open questions (`verified: partial`)

1. **Row format** is confirmed against the SDQP 2024-10-12 capture (Wayback,
   the only populated page in 551 archived snapshots) and a live 2026-07-25
   ALQP capture series of 19 snapshots holding 13 distinct rows from six
   spotters. It is **not** confirmed against a high-volume party, a
   county-line spot, or a DX spot.

   That live series exercised, unprompted, several things worth recording:

   | Observed | Handling |
   | --- | --- |
   | `N4UC 1042.3` then `N4UC 14042.3` 25 s later | The typo is not a frequency under any reading, so it is refused and surfaced; the correction parses |
   | `N4RT 7.0745` | MHz to four decimals — resolves, flagged reconstructed |
   | `WA1FCN/4` | Portable suffix kept intact |
   | `KB3A 7252` from two spotters | Same spot corroborated across spotters |
   | `W5LNX … 59 CA` | An exchange in the comment; not mistaken for a county |
2. **The POST contract is derived from form markup only.** No test post was
   made to the live public board. The first real send must be verified against
   the following poll rather than assumed from an HTTP 200.
3. **Data quality.** Live ALQP showed a busted call and its correction both
   retained by the server (`KC4TE` 21:57:30, then `KC4TEO` 22:01:10 with the
   comment `RIGHT CALL`, same frequency). The supersede heuristic that handles
   this rests on that single observed instance.
4. **Third-party spotting.** The hub is not self-spot-only: every live ALQP
   spot was posted by `N4EMP` for other stations. Both patterns occur.
5. **County lines are posted off-contract.** §5 records `county` as a `<select>`
   carrying single tokens, and open question 1 above notes that no county-line
   spot has ever been observed on the board. This app nevertheless posts a
   county line whole and slash-joined — `MDSN/LIME`, each half translated
   through the party's own alias map separately, so ILQP's `PULA/JACK` goes out
   as `PULS/JACK`.

   Taken deliberately: a spot naming only the first county tells a chaser
   hunting the second to skip a station that would have given them the
   multiplier. Correct information off-contract beats misleading information
   on it.

   **Unverified.** What the server stores for a value outside its own
   `<select>`, and how its table then renders it, are both unknown. The first
   real county-line send must be checked against the following poll — the
   same discipline open question 2 already imposes on every send — and what it
   shows recorded here. Inbound parsing is unchanged: `HubSpotParser` reads the
   county column by position and will surface whatever string comes back.

## 7. Etiquette

This is a small volunteer-run site on shared hosting. The app polls one page
per minute only while a party's own schedule window is open, and identifies
itself in the User-Agent. That is lighter than the page's own 53-second
meta-refresh in a single open browser tab.
