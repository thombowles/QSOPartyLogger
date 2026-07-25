# QSO Party Hub spots — design

Parse the per-party spot tables at `qsopartyhub.com` into the active party's
band map, and post self-spots back to it.

**Status:** implemented 2026-07-25, across the six commits in §13. 875 tests
pass, up from 811 at the start. Provenance stays `verified: partial` — §6's
open questions are unchanged, and no test post was ever made to the live board.

---

## 1. Provenance

Per Constitution Article 1. All facts below were fetched and verified on
**2026-07-25**; nothing here comes from model recall or another logger.

| Source | What it establishes |
| --- | --- |
| `http://qsopartyhub.com/{prefix}-spots.php` (19 pages, fetched 2026-07-25) | Self-spot form contract; the authoritative table iframe; per-party county token lists |
| `http://qsopartyhub.com/{prefix}-table.php` (19 pages, fetched 2026-07-25) | Spot table markup and column contract |
| Wayback capture `20241012231637` of `sdqp-table.php` | The only populated capture in 551 archived snapshots — 7 rows of real SDQP 2024 spot data |
| **Live ALQP capture, 2026-07-25 22:15Z onward** | Real in-contest traffic: third-party spotting, a busted-call correction, three more frequency formats |
| `docs/research/ilqp_counties.txt:9` | Official ILQP abbreviation `PULA` (the hub uses `PULS`) |
| `docs/research/sdqp_rules_page.txt:94`, `iaqp_page.txt:34`, `paqp_rules_2025.txt:363` | Sponsor rules directing operators to the hub |

**`verified: partial`.** Open questions, named per Article 3:

1. The row format is confirmed against two populated captures (SDQP 2024, ALQP
   2026) covering two parties and two seasons. It is **not** confirmed against
   a high-volume party, a county-line spot, or a DX spot.
2. The self-spot POST contract is derived from form markup only. **No test post
   was made to the live public board.** First real send must be verified
   against the next poll.
3. Correction/superseded heuristics rest on a single observed instance.

---

## 2. Coverage

Resolved from each party page's iframe `src`, **not** by guessing the URL
prefix — see §3.1 for why that distinction is load-bearing.

**17 of 19 bundled parties** have a live table and self-spot form. Of those 17,
14 use the party `id` directly and 3 use an alias: `mdc`→`mdcqp`,
`tqp`→`txqp`, `hqp`→`hiqp`. (The two excluded parties were probed as
`cqp`→`caqp` and `warun`→`waqp`.)

Two are excluded, and the app must show the feature as unavailable rather than
fail quietly:

- **CQP** — page is an unfinished template (placeholder text "allows/does not
  allow self-spotting"), has no form, and its iframe points at `qp-table.php`,
  which **302-redirects**. Note `caqp-table.php` *does* return a normal empty
  table, which is precisely the trap in §3.1.
- **WA Salmon Run** — `waqp-spots.php` returns **404**. `waqp-table.php` exists
  but is an orphan shell no page links to.

Seventeen parties expose a county `<select>` (the two excluded ones do not).
Sixteen match the app's county lists **exactly**, including TQP's 254. The
seventeenth, Illinois, differs by a single token: Pulaski is `PULS` on the hub
and `PULA` in the official county list. **The app is correct; the hub has a
typo** — hence `countyAliases`.

---

## 3. Architecture

### 3.1 Data — banked, script-generated

`PartyDefinition` gains one optional block. Additive, with `nil` meaning "no hub
support", so every existing party keeps scoring identically (Article 4):

```json
"hubSpots": {
  "tableURL": "http://qsopartyhub.com/alqp-table.php",
  "postURL":  "http://qsopartyhub.com/alqp-spots.php",
  "countyAliases": { "PULS": "PULA" }
}
```

`docs/research/gen_hub_map.py` generates this offline, following the existing
`gen_parties.py` pattern (Article 2 — never hand-type data that exists in a
file). It resolves `tableURL` **from the page's iframe**, diffs hub county
tokens against the party JSON to emit aliases automatically, and asserts counts.

> **Why the iframe, not the prefix.** `caqp-table.php` returns a well-formed but
> permanently empty table, while the CQP page actually embeds `qp-table.php`.
> Prefix-guessing yields a poller that runs forever, errors never, and shows
> nothing. The iframe is the only authority.

### 3.2 Core — pure, no network

- **`HubSpotParser.parse(html:source:) -> HubParseResult`**
  Extracts `<tr class='ageNbg'>` rows from `<table id=spots>`. Regex-based, because
  the page's unclosed `<table id=agekey>` breaks strict parsers.
- **`HubFrequency.normalize(_:) -> (kHz: Double, confidence: Confidence)?`**
  The kHz → MHz → tenths ladder (§4).
- **`HubModeInference`** — party-aware mode classification (§5).

### 3.3 App — network

- **`HubSpotClient`** — `@MainActor @Observable`, mirroring `SpotClient`'s shape
  (`status`, `lastError`, `console`, `spotsReceived`) so existing UI patterns
  carry over. Feeds the same `spotStore.add(spot)` sink at
  `Sources/UI/MainView.swift:558`, inheriting band map, filters, stacking and
  ⌘←/⌘→ unchanged.
- **`HubSpotPoster`** — builds and sends the multipart self-spot (§8).

---

## 4. Frequency normalization

The FREQ column is operator-typed and inconsistent. Real values observed:
`14.041`, `143095`, `14.0677`, `14045.25`, `14226`, `21330`, `7041.4`,
`7043.40`, `7047.0`.

Ladder, first interpretation that lands on a valid band wins:

| order | reading | rationale |
| --- | --- | --- |
| 1 | `n` kHz | The form's own placeholder is `14150` |
| 2 | `n × 1000` kHz | Operator typed MHz (`14.041`) |
| 3 | `n ÷ 10` kHz | Decimal omitted (`143095` → 14309.5) |

**Verified 9 of 9 against real data.** The ladder is safe by construction: steps
2 and 3 are only reached by values no earlier reading accepts. `143095` is
correctly rejected as kHz because 143.095 MHz falls in the gap below 2 m.

Two guards, because six of nine samples needed no fallback but three did:

- A frequency resolved via step 3 is **low confidence** — reconstructed, not
  read. Display it as such, and warn before the radio QSYs there.
- **Never QSY outside the party's `validBands`.** A resolution landing off the
  party's band list is rejected and logged to the console, not tuned.

---

## 5. Party-aware mode inference

**Defect found in live ALQP data.** `SpotFilter.segments` puts the 40 m CW
boundary at 7045, so the live spot `KC4TEO 7047.0 MDSN` classifies as
`digital`. ALQP allows only phone and CW, and
`ScoreEngine.wouldAddMultiplier` opens with
`guard party.allowedModeClasses.contains(modeClass)` — returning `false`. A
genuine needed Madison County multiplier gets **no NEW MULT badge**. That is
one of four live spots: a 25% failure rate on the feature's headline capability.

The generic band plan is tuned for cluster spots, where FT8 at 7074 matters. In
a party that forbids digital, that bucket should not exist; ALQP CW legitimately
runs 7040–7060.

**Fix:** constrain inference to the party's `allowedModeClasses`. When the
band-plan guess is not an allowed mode, snap to the nearest allowed one. The
party's own rules outrank a generic band plan.

This also affects cluster spots in QSO parties, so it lands in the shared
inference path — in its own commit (Article 4).

---

## 6. Rover handling — the county is worth more for un-hiding than for labeling

`DupeChecker.DupeKey` includes `theirLoc`, so the scoring engine already knows a
mobile in a new county is a **new contact** — matching SDQP's rule that mobiles
"are considered a new contact each time they change counties."

But the band map's worked-tracking keys on callsign alone
(`SpotFilter.Options.workedCalls: Set<String>`, and `SpotStore.next` steps over
those calls). So once worked, a rover is greyed, skipped by ⌘←/⌘→, and hidden
under "hide worked" — **permanently, even after it moves into a county you still
need.** Rovers are the largest multiplier source in a state QSO party; the
naive design would systematically hide the best remaining mults.

This was previously invisible because cluster spots carry no county. The hub's
county field does not merely enable a badge — it fixes a blind spot the app had
no way to see.

**Design:**

- Worked-tracking for hub spots keys on **call + county**, not call.
- A worked rover un-greys and re-enters ⌘←/⌘→ rotation the moment it reports a
  new county, badged `LINC → MINN`.
- `Spot` gains `county: String?` and `source: SpotSource` (`.cluster` / `.hub`),
  both defaulted so every existing call site and test is unchanged.
- `SpotStore.add` carries a non-nil county forward when replacing a spot of the
  same identity, so a later cluster spot cannot erase multiplier information.

County recovery: when QTH is empty, scan the comment for a token matching the
party's county list. Verified against the 2024 capture, where `N4LDB` carried
`CHAR` (Charles Mix) in the comment rather than QTH.

---

## 7. Data quality — superseded spots

Live ALQP, four minutes apart, both rows retained by the server:

```
21:57:30  KC4TE    7047.0  MDSN                N4EMP
22:01:10  KC4TEO   7047.0  MDSN  "RIGHT CALL"  N4EMP
```

A busted call and its correction. Shown naively, the band map carries a phantom
station beside the real one; calling it wastes contest time or logs a bad call.

**Design:** when two spots share a frequency within tolerance, arrive close in
time, and their calls are within one edit, mark the **older** superseded — grey
it and step over it in ⌘←/⌘→. Never delete: the heuristic rests on a single
observed instance, so the operator must be able to see and overrule it.

---

## 8. Self-spotting

Contract derived from form markup (no test post was made):

```
POST /{prefix}-spots.php        enctype: multipart/form-data
  station    required   max 15     call spotted
  frequency  required   max 10     kHz, per the form's own "14150" placeholder
  county     optional              must be a hub token (send PULS, not PULA)
  comment    optional   max 50
  poster     required   max 15     your call
```

No CSRF token, no auth, no session — anything posted reaches a public board
immediately, and a double submit posts twice.

- **Auto-filled from live state**: call, the radio's current frequency, and the
  log's current county. Retyping mid-run is why operators stop self-spotting.
- **Offer to re-spot on county change** — the moment that matters for rovers,
  and the thing they most often forget.
- **Confirm every send**, showing the exact payload. Keyboard path per Article 9:
  ⌘⇧S opens, Return confirms, Esc cancels.
- **Throttle**: refuse an identical spot within a short window, so a stuck key
  cannot spam a volunteer-run board.
- **Verify, don't assume.** HTTP 200 means *sent*. The next poll looks for the
  call in the table to report *confirmed on hub*; if it has not appeared after
  two polls, say so rather than leaving the operator believing they are spotted.
- Frequency is sent as clean kHz, which reduces the very ambiguity §4 exists to
  resolve.

---

## 9. Networking

- **Schedule-gated polling.** Poll only inside the active party's
  `PartyDefinition.schedule` window (ALQP 2026: `15:00Z` → `03:00Z`). Polling a
  volunteer-run shared host year-round for a 12-hour event is rude and pointless.
- 60 s interval; the page's own `<meta http-equiv="refresh" content="53">` sets
  the expectation. Backoff 60 → 120 → 300 s on failure, reset on success.
- No `ETag`/`Last-Modified`, so each poll is a full ~5 KB — roughly 300 KB/hour,
  comparable to leaving the page open in a browser.
- Descriptive `User-Agent` identifying app and version, so the site owner can
  identify and contact us.
- ATS exception scoped to the one domain — port 443 serves a **self-signed
  cert**, so the site is HTTP-only:

  ```yaml
  NSAppTransportSecurity:
    NSExceptionDomains:
      qsopartyhub.com: { NSExceptionAllowsInsecureHTTPLoads: true }
  ```

  Not `NSAllowsArbitraryLoads`. The sandbox already grants `network.client`.
- Hub polling must never block or slow the entry path, and hub failures surface
  once in a status line — never as repeated modal errors. Cluster spots keep
  flowing regardless.

**Honest scale note:** the live ALQP sample was 4 spots from a single spotter.
The hub is low-traffic next to a DX cluster. Its value is the **county field**,
not volume — a complement to cluster spotting, not a replacement.

---

## 10. Running alongside a DX cluster

This is the **default mode**, not a special case. Both sources feed the same
`spotStore.add(spot)` sink (`Sources/UI/MainView.swift:557`), so a hub client is
simply a second producer: one band map, one filter set, one ⌘←/⌘→ rotation, and
automatic de-duplication because same `call|band` is a single entry.

### 10.1 Per-source age-out — blocking defect

`spotMaxAgeMinutes` defaults to 15, tuned for cluster spots. Measured against
the live ALQP table at poll time 22:34:12Z:

| spot | spotted at | age | survives 15-min age-out |
| --- | --- | --- | --- |
| W4NBS | 22:15:25 | 18.8 min | no — purged on arrival |
| N4NM | 22:08:43 | 25.5 min | no — purged on arrival |
| KC4TEO | 22:01:10 | 33.0 min | no — purged on arrival |
| KC4TE | 21:57:30 | 36.7 min | no — purged on arrival |

**0 of 4.** Shipped as originally designed, the hub contributes nothing at all,
presenting as a broken parser rather than a misconfigured lifetime.

The two sources differ in kind. Cluster spots stream continuously from skimmers,
so 15 minutes is generous. Hub spots are hand-posted and sparse, and the hub
retains them a full 60 minutes because a mobile parked in a county stays
workable far longer than a skimmer decode stays fresh.

**Design:** `spotMaxAgeMinutes` becomes cluster-only; hub spots get an
independent lifetime defaulting to **60 minutes**, matching the source's own
retention. `SpotStore.purge` applies the limit per `Spot.source`.

### 10.2 Volume asymmetry

Hundreds of cluster spots against 4 from the hub. The county-bearing spots — the
entire point of the feature — get buried. Mitigations: a source badge on the
band map, and a **hub-only filter axis** for hunting counties specifically.

### 10.3 Merge, and why it protects rover un-hiding

Same `call|band` from both sources collapses to one entry, newest winning on
frequency, time, comment and spotter. The county carry-forward rule in §6 does
double duty here: without it a cluster spot arriving after a hub spot would strip
the county and silently re-hide a rover that had just been un-hidden.

**Cross-source corroboration** is a confidence signal worth surfacing — a station
seen on both the cluster and the hub is independently confirmed. Not a fix for
busted calls, but had the cluster carried `KC4TEO` and not `KC4TE`, it would have
indicated which was real.

### 10.4 Independent failure

Separate clients, separate status and error surfaces. A hub outage never
disturbs the cluster feed, and vice versa (§9).

---

## 11. Header contract

Rows are parsed positionally, so the header is a **hard gate**: the six columns
must be exactly `TIME (UTC)`, `SPOT`, `FREQ`, `QTH`, `COMMENT`, `POSTER`. Any
mismatch parses nothing and raises a visible warning.

Without this, a hub-side column insertion slides county into comment and the app
confidently displays wrong multiplier data. Rejected rows appear in the node
console the way cluster chatter already does, so drift is diagnosable in seconds
rather than presenting as an unexplained empty band map.

---

## 12. Testing

Per `CLAUDE.md`, tests run with no network. All fixtures are saved HTML.

| Fixture | Origin |
| --- | --- |
| `sdqp-table-2024-10-12.html` | Real 7-row mid-contest capture |
| `alqp-table-2026-07-25-*.html` | **Live ALQP capture series**, recorded through the 03:00Z window close |
| `paqp-table-empty.html` | Live empty table |
| `caqp-table-stub.html` | The CQP trap — well-formed, permanently empty |
| Synthetic edges | Derived from the above: header drift, missing QTH, county-in-comment, malformed frequency |

Cases: the 7 SDQP rows and the live ALQP rows parse exactly; the frequency
ladder across all 9 real samples; `7047.0` badges as a needed mult under ALQP
rules (§5 regression); `PULS`→`PULA`; the KC4TE/KC4TEO supersede heuristic;
rover un-hiding on county change; empty table → 0 spots, no error; 404 and
garbage → 0 spots, no crash; header mismatch → 0 spots plus warning; a golden
multipart body; and county preservation when a cluster spot overwrites a hub spot.

Concurrent-source cases (§10): all four live ALQP spots survive the hub's own
60-minute lifetime while a 15-minute cluster spot in the same store ages out
(§10.1 regression); a cluster spot overwriting a hub spot does not re-hide an
un-hidden rover (§10.3).

Per `prove-regression-tests-red-first`: the §5 mode-inference, §6 rover, and
§10.1 age-out tests must be shown failing against current behavior before their
fixes land. The §10.1 test is the sharpest of the three — it fails with an empty
band map, which is exactly how the defect would present in the field.

---

## 13. Commit sequence

One spec, staged commits — each independently bisectable:

1. **Schema + generator + banked mapping + provenance doc.** Data only, no behavior.
2. **Party-aware mode inference** (§5). Own commit; fixes cluster spots too.
3. **Per-source spot lifetime** (§10.1). Own commit; cluster default unchanged
   at 15 minutes, so existing behavior is identical until a hub source exists.
4. **Parser + frequency ladder + fixtures and tests.** Pure Core, no network.
5. **Client + schedule-gated polling + ATS + county/mult badge + rover un-hiding
   + source badge + hub-only filter + README.**
6. **Self-spot poster + confirm sheet + autofill + re-spot prompt + README.**

Docs ship in the same commit as behavior (Article 8): README features, keyboard
table (⌘⇧S), test count, and the 17-of-19 coverage caveat.

---

## 14. Deferred

- **Needed-mult-only ⌘←/⌘→ navigation** — considered, not selected.
- **Fuzz/property testing** the parser against invariants — worth revisiting once
  the live corpus is larger.
- A courtesy note to the site owner before shipping. Traffic is modest and
  self-identifying, but this is a volunteer-run site.
