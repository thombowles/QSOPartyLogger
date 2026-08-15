# Data provenance

Every rule, county list, band list, date and CAT byte in this app traces to a
named official source with a fetch date — [Article 1 of the
constitution](CONSTITUTION.md). This file is that audit trail: what was read,
when, which generator turned it into data, and what each generator asserts.

Per-party behaviour and known limitations are in [PARTIES.md](PARTIES.md).

- QRP Labs QMX+ / QMX CAT: the **QMX CAT programming manual, firmware
  1_04_004** (qrp-labs.com/images/qmx/manuals/cat_1_04_004.pdf,
  `Last-Modified` Thu 23 Jul 2026 19:53:36 GMT, fetched 2026-08-09), banked
  verbatim as [`qmx_cat_1_04_004.txt`](research/qmx_cat_1_04_004.txt) because
  qrp-labs.com stamps the firmware revision into the URL and replaces it each
  release. Its own revision history dates this one "1_04_004 23-Jul-2026"
  while every page footer still reads 1_04_003; the title page and the history
  agree, so 1_04_004 is what `QRPLabsQMXDriver` cites. `IF`, `FA`, `MD`, `KY`,
  `AI`, `RX` and the 80-character `KY` buffer arithmetic all come from it.
  Two values it does *not* print come from named sources it names itself:
  `KS`'s three-digit field width from the **Kenwood TS-480 PC control
  reference** (kenwood.com/i/products/info/amateur/ts_480/pdf/ts_480_pc.pdf,
  `KSP1P1P1;`, 010–060 WPM), which the CAT manual links and declares itself a
  subset of; and the keying, port and baud behaviour from the **QMX operating
  manual, firmware 1_04_004** (same fetch date), banked as the five passages
  the code cites in
  [`qmx_operation_1_04_004_excerpts.txt`](research/qmx_operation_1_04_004_excerpts.txt)
  — "Key from USB DTR" (why `supportsDirectKeying` is true), "PTT from DTR"
  (why the README tells you to leave the PTT line off), the AUX-jack baud list,
  and the statement that baud "is irrelevant to the USB Virtual COM Port".
  Nothing here traces to hamlib, N1MM, or a forum post. The same manual is why
  the driver sends no `KY` at all: "Keying via the DTR signal works in
  straight-key mode independently of the main keyer", so a QMX has key lines
  and is keyed directly and only directly ([Article 11](CONSTITUTION.md)). It
  is also why the README's setup note is emphatic — the CW menu's
  "Key from USB DTR" lists "None (default)", so an out-of-the-box QMX will not
  key until the operator changes it.

- Elecraft K3S / K3 / KX3 / KX2 CAT: the **Programmer's Reference, Rev. G5,
  Feb. 20, 2019** (ftp.elecraft.com/KX2/Manuals Downloads/K3S&K3&KX3&KX2 Pgmrs
  Ref, G5.pdf, `Last-Modified` Mon 08 Sep 2025 21:52:03 GMT, fetched
  2026-08-09), banked verbatim as
  [`k3_programmers_reference_g5.txt`](research/k3_programmers_reference_g5.txt).
  G5 is what elecraft.com's Programmer's Reference Manuals page currently
  links; the archived **Rev. F2, July 24, 2015** that `ElecraftK3Driver` also
  cites is unchanged for every command the driver speaks. `IF`, `FA`, `MD`,
  `KS` and `AI` come from it. Two facts here decide behaviour elsewhere:
  `KS`'s field is "008-050 (8-50 WPM)", which is exactly the app's clamp; and
  the `KY` entry is the authority for CW speed being changeable mid-message —
  "If * is a W (for "wait"), processing of any following host commands will be
  delayed until the current message has been sent. This is useful when a KY
  command is followed by other commands that may have side-effects, e.g., KS
  (keyer speed)." The blank form the driver used therefore let a following
  `KS` land on a message already sending, and `KYW` is documented as the way
  to *opt out* of that. The app no longer sends `KY` to a K3 at all
  ([Article 11](CONSTITUTION.md)), but that sentence is why the constitution
  forbids any future driver adopting a deferred-side-effect form.

- FlexRadio 6000/8000 CAT: the **SmartSDR TCP/IP API** wiki in FlexRadio's own
  GitHub organisation (github.com/flexradio/smartsdr-api-docs), which
  flexradio.com/api points to, fetched 2026-08-09 as raw markdown and banked as
  [`flex_smartsdr_tcpip_api_cw.txt`](research/flex_smartsdr_tcpip_api_cw.txt) —
  the `TCPIP-cw` and `TCPIP-cwx` pages whole, because the wiki carries no
  revision number or date to cite instead. The keyer speed command is
  `cw wpm <speed>`, printed identically on both pages; every *other* verb on
  the cwx page is `cwx ...`, and WPM alone is not, which is how the driver came
  to emit a `cwx wpm` that no radio ever answered. **Explicitly partial
  ([Article 3](CONSTITUTION.md)):** the `cwx ... wpm=<n>` status format that
  `FlexRadioDriver.parseCWXSpeed` reads appears on neither page, nor on the
  wiki's `SmartSDR-Status-Responses` page, which does not mention `cwx` at all.
  That parser predates this entry and is still unverified against an official
  source — front-panel speed sync from a Flex is the one radio capability in
  this app resting on nothing banked. A second gap the same file documents and
  the driver does not yet honour: `cwx send` specifies spaces be replaced with
  `0x7F`, and `cmdSendCW` sends them literally.

- skeeter (NJQRP Skeeter Hunt): rules from W2LJ's blog page
  (w2lj.blogspot.com/p/njqrp-skeeter-hunt.html, the current 15th-Annual/2026
  edition), fetched 2026-08-04 and banked as
  [`skeeter_rules_2026.txt`](research/skeeter_rules_2026.txt); the qsl.net
  "Official NJQRP Skeeter Hunt Webpage" still carried the 2025 edition the
  same day ([`skeeter_qslnet_page_2025.txt`](research/skeeter_qslnet_page_2025.txt)),
  every rule identical but the date. The **score formula is nowhere printed**
  and its authority is the sponsor's own 2025 final scoreboard
  ([`skeeter_scoreboard_2025.csv`](research/skeeter_scoreboard_2025.csv)):
  [`gen_skeeter.py`](research/gen_skeeter.py) re-derives
  (3·Skeeter + 2·QRP + 1·QRO) × S/P/Cs × class + bonus and asserts it exact
  on all 112 scored rows, plus named rows including KE5CW's own. The 2026
  roster sheet (banked as
  [`skeeter_roster_2026.csv`](research/skeeter_roster_2026.csv), 187 numbers
  at fetch) is **live and its document id changes each season**, so the app
  discovers it from the blog page at use time. The WA7BNM registry has no
  Cabrillo name and the sponsor accepts no log files — `SKEETER-HUNT` is
  this app's own header. Research write-up:
  [`skeeter_rules.md`](research/skeeter_rules.md).

- fobb (ARS Flight of the Bumblebees): rules from the sponsor's own page
  (ars-qrp.com/FOBB/FOBB.html), fetched 2026-08-10 and banked as
  [`fobb_rules_2026.txt`](research/fobb_rules_2026.txt). One page carries
  both annual runnings; at fetch it was headed for the Fall event
  ("Sunday, September 20, 2026"), and its only revision marker is a
  "Last Updated : 27JUL26" footer — it is edited in place, so **re-check
  before each running**. Its HTML `<title>` still reads 2024: never take a
  date from it. The **July running's printed date** comes from the Internet
  Archive's capture of the same URL three days before that event (snapshot
  20260723202047, "Sunday, July 26, 2026"), banked as
  [`fobb_rules_2026_july_wayback.txt`](research/fobb_rules_2026_july_wayback.txt);
  every rule is identical between the two captures. The score formula **is**
  printed, and is additionally corroborated by the results venue the rules
  designate by name: all 90 rows of the July 2026 claimed scores at
  3830scores.com (`editionscores.php?arg=RvJxJizV77DLxU`, fetched
  2026-08-10, banked as
  [`fobb_3830_claimed_2026-07.csv`](research/fobb_3830_claimed_2026-07.csv))
  satisfy Contacts × Bumblebees × 3 exactly, and
  [`gen_fobb.py`](research/gen_fobb.py) re-verifies them. The Bumblebee
  roster is the sponsor's self-serve report at a **stable** URL
  (ars-qrp.com/FOBB/Process_Get_All_By_Number.php, fetched 2026-08-10,
  banked as [`fobb_roster_page_2026-07.html`](research/fobb_roster_page_2026-07.html)
  and [`fobb_roster_2026-07.csv`](research/fobb_roster_2026-07.csv) — 234
  numbers, of which 233 carry a callsign), so no discovery hop is needed;
  numbers are reissued per event. The WA7BNM registry has no Cabrillo name
  (checked 2026-08-10) and the sponsor accepts no log files at all —
  `ARS-FOBB` is this app's own header. Research write-up:
  [`fobb_rules.md`](research/fobb_rules.md).
- Cabrillo V3 header values — the `CATEGORY-*` enumerations (including
  `CATEGORY-ASSISTED`), the `OPERATORS:` `@host` convention, and
  `GRID-LOCATOR:` — from the WWROF Cabrillo specification
  (wwrof.org/cabrillo, fetched 2026-07-28), banked in
  [`docs/research/cabrillo_v3_headers.md`](research/cabrillo_v3_headers.md)
  with KE5CW's own January 2026 NAQP CW submission (N1MM) as the reference
  log. The NAQP rule 5/6 → `CATEGORY-*` mapping (SO / SOA / M2, QRP / Low /
  check log) is recorded in
  [`docs/research/naqpcw_rules.md`](research/naqpcw_rules.md) §11; team
  competition stays out of the log by rule 14's own words.
- Call history: file format from the N1MM Logger+ documentation
  (n1mmwp.hamdocs.com/setup/call-history/, fetched 2026-07-28); the 45-party
  prefix mapping generated by
  [`docs/research/gen_callhistory.py`](research/gen_callhistory.py) from
  the full 504-file listing scraped the same day, each mapped file downloaded
  and its own `# QSOPARTY` declaration verified (whitespace-blind — Ohio's
  writes `QSO PARTY OH`). Banked inventory, per-party verification and
  mechanics in [`docs/research/n1mm_callhistory.md`](research/n1mm_callhistory.md).
  **Hint data only, never rule authority** (constitution Article 1): nothing
  from these files reaches scoring, and every value is re-parsed by the
  party's own rules before being offered.
- Super check partial: `MASTER.SCP` from supercheckpartial.com (HTTPS,
  `Last-Modified` verified against the file's own `# Release` stamp;
  observed 2026-08-04, release 2026.07.31, 50,021 calls). Downloaded and
  cached by the app itself — never bundled, never hand-fetched — and
  re-checked daily by HEAD. Server behavior and file shape banked in
  [`docs/research/scp_masterfile.md`](research/scp_masterfile.md).
  **Hint data only, never rule authority** (constitution Article 1):
  nothing from it reaches scoring, validation, or export.
- NAQP CW + SSB: rules from NCJ's own "Rules: 2026 North American QSO Party
  (CW/SSB/RTTY)" (ncjweb.com, printed NCJ Oct/Nov 2025), the official paper
  log form whose Multiplier Check List is the country list, and the ARRL DXCC
  List (January 2026 edition) that NAQP rules 3 and 11 designate by name for
  entity definitions — all fetched 2026-07-27. Both parties' countries
  generated by one run of
  [`docs/research/gen_naqp.py`](research/gen_naqp.py) from the committed
  checklist + ARRL texts — never hand-typed — and asserted identical.
  Cabrillo headers `NAQP-CW` / `NAQP-SSB` from the WA7BNM registry (entries
  218 and 229), the one value the sponsor does not print. **Not State QSO
  Party Challenge contests**, by the Challenge's own approved list and
  KE5CW's requirement. **No home region** (`hasHomeRegion: false`, 2026-07-28):
  rule 10 gives every North American entrant the same exchange, so setup asks
  one location question — your state, province, NA country code, or DX — and
  the export carries exactly what you entered.
- KSQP: rules + county abbreviations fetched from ksqsoparty.org (2026 rules
  PDF, official mults PDF) on 2026-07-23. County JSON generated by script
  from the official file — never hand-typed.
- TQP: rules from txqp.net; counties from the official `txcounty.zip`
  (2014 revision, current as of fetch). Marked `verified: partial` — confirm
  band list and current-year details before submitting.
- MDC: rules + Table 1 entities from the sponsor's official PDF
  ("The Fun Contest Maryland-DC QSO Party Rules", rev. 06 AUG 2024 v.5,
  w3vpr.org) fetched 2026-07-23, sponsor page re-checked 2026-07-24. Entities
  generated from the committed rules text by
  [`docs/research/gen_mdc.py`](research/gen_mdc.py) — never hand-typed.
  The sponsor has not published 2026 dates; the Aug 8 window is derived from
  the rules' "second Saturday in August" formula and cross-checked against two
  calendars.
- HQP: rules read verbatim from hawaiiqsoparty.org/rules-page/ on 2026-07-24.
  District abbreviations exist only on the sponsor's multiplier map
  (`docs/research/multmap_all.png`), transcribed to
  [`hqp_districts.tsv`](research/hqp_districts.tsv) and generated by
  [`gen_hqp.py`](research/gen_hqp.py). Marked `verified: partial`: the
  sponsor's rule 1 says "36 hours from 1800 UTC Aug 22 through 0359 UTC Aug 24"
  and *also* "6am Saturday … to 6pm Sunday in Hawaii" — those disagree (the
  literal UTC pair is 33h59m, and 1800Z is 8am HST). The shipped window is
  1600Z→0400Z, the only span matching both the stated 36 hours and both Hawaii
  times. Confirm with `info@hawaiiqsoparty.org` before submitting a log.
- OhQP: rules from ohqp.org (captured 2026-07-23, re-checked 2026-07-24);
  counties generated by [`gen_ohqp.py`](research/gen_ohqp.py) from the
  sponsor's official multiplier list, which states "these abbreviations must be
  used … this list trumps all other lists". The generator asserts the rules'
  stated 150-multiplier total, which independently confirms the county count and
  Ohio's exclusion from the state list. Two sponsor typos ("Auglaze",
  "VanWert") are corrected in the display name with the abbreviations kept
  verbatim. The sponsor states it ignores Cabrillo headers entirely, so the
  `MRRC-OHQP` CONTEST value comes from WA7BNM's registry.
- TnQP: rules from the Tennessee Contest Group's posted document at tnqp.org
  (read 2026-07-23, page re-checked 2026-07-24 — still the same embedded DOCX,
  no 2026 revision announced). Counties generated by
  [`gen_tnqp.py`](research/gen_tnqp.py) from the sponsor's official
  abbreviation PDF; `HARD` is Hardeman and `HARN` is Hardin, asserted in the
  generator. Cabrillo `TN-QSO-PARTY` comes from the sponsor's own Cabrillo
  template. TnQP's self-activation *multiplier* for TN mobiles — distinct from
  the 500-point bonus, and counted **once** rather than per band on the
  sponsor's own singular "one multiplier" — has been modeled since 2026-08-04.
  `verified: partial` — the rules document is titled for 2025, so re-check in
  late August.
- COQP: rules from coloradoqsoparty.org (captured 2026-07-23, re-fetched
  verbatim 2026-07-24); the page dates its own revision "July 15, 2026".
  Counties generated by [`gen_coqp.py`](research/gen_coqp.py) from the
  sponsor's official abbreviation page, with the lookalike groups
  (`MON`/`MOT`/`MOF`/`MOR`, `LAK`/`LAP`/`LAR`/`LAA`, `ELP`/`ELB`,
  `SAG`/`SAJ`/`SAM`, `KIO`/`KIC`, `RIB`/`RIG`) asserted. The generator also
  asserts the rules' in-state ceiling of 128 mults per mode, which is what
  establishes that Colorado counts as a state multiplier earned via a county.
- NJQP: rules from the Burlington County Radio Club's official 2026 page
  (version `2026rev0.5`, captured 2026-07-23, re-read live 2026-07-24).
  **The sponsor's date contradicts the State QSO Party Challenge calendar** —
  the sponsor says Sep 12, the calendar said Sep 19, and WA7BNM agreed with the
  sponsor; Article 19 gives the sponsor authority. The multiplier tables exist
  only as images, committed as `docs/research/njqp_mults_*.png` and transcribed
  to [`njqp_counties.tsv`](research/njqp_counties.tsv).
- IAQP: rules from w0yl.com/IAQP (captured 2026-07-23, re-checked live
  2026-07-24). Counties generated by
  [`gen_iaqp.py`](research/gen_iaqp.py) from the sponsor's official county
  list, which pins 32 abbreviations by name because Iowa's codes cluster so
  badly. `verified: partial` — the page is still titled for 2025 and its rules
  PDF is dated 2018, with only the 2026 date announced; re-check in early
  September.
- NHQP: rules from w1wqm.org (revision "August 19, 2025", the one carrying the
  2026 dates), read verbatim 2026-07-24. The generator asserts the rules' own
  stated figures — a 50-multiplier out-of-state ceiling (10 counties × 5 bands)
  and a 22-hour total across two windows. NH stations may count "up to 10 DXCC
  country" while every DX station sends the same literal token "DX" — the
  entity is resolved from the **worked callsign** against the ARRL list below,
  so ten entities count ten and `dxMultCap` finally binds. Out-of-state
  entrants are unaffected either way — DX is not one of their multiplier
  classes.
- ALQP: the **2026 rules page** (alabamacontestgroup.org/aqp/rules/, fetched
  2026-07-25, extracted to [`alqp_rules_2026.txt`](research/alqp_rules_2026.txt))
  states it as the party Object — "Stations outside of Alabama make contact with
  Alabama amateur radio stations and as many Alabama counties as possible" —
  with out-of-state multipliers capped at "Maximum of 67 Alabama counties".
  Resolved as for the other aim-not-prohibition parties; analysis in
  [`alqp_out_of_state_credit.md`](research/alqp_out_of_state_credit.md).
  The short `/aqp-rules/` path 404s; the rules are at `/aqp/rules/`.
- KSQP: the **2026 rules PDF** (ksqsoparty.org, fetched 2026-07-25, extracted to
  [`ksqp_rules_2026.txt`](research/ksqp_rules_2026.txt)) states the
  restriction as the party's OBJECT and names both sides — "Stations outside of
  Kansas work as many Kansas stations in as many Kansas counties as possible.
  Stations in Kansas work everyone" — with the multiplier table capping
  non-Kansas entrants at "105 Kansas county multipliers". Resolved as for the
  other aim-not-prohibition parties; analysis in
  [`ksqp_out_of_state_credit.md`](research/ksqp_out_of_state_credit.md).
  That PDF also carries an **FT4/8 category** the bundled definition predates.
- TQP: the **operating rules** at txqp.net (fetched 2026-07-25, extracted to
  [`tqp_operating_rules.txt`](research/tqp_operating_rules.txt)) write the
  out-of-state restriction into the QSO points rule itself — a non-Texas station
  counts points only "with any Texas station" — so a non-Texas entrant earns
  nothing for working another non-Texas station. Best-evidenced instance of that
  rule in the catalogue after MDC 10b; analysis in
  [`tqp_out_of_state_credit.md`](research/tqp_out_of_state_credit.md). Note
  `txqp.net/rules/` 404s; the rules live under the Joomla `index.php` path.
- **DXCC entities, all parties.** `Resources/DXCC/dxcc_entities.json` is the
  **ARRL DXCC List, Current Entities, January 2026 Edition**
  (`www2.arrl.org/files/file/DXCC/DXCC_Current.pdf`, fetched 2026-07-27),
  generated by [`gen_dxcc.py`](research/gen_dxcc.py) from the
  committed text — never hand-typed. NAQP rules 3 and 11 designate that list by
  name and `gen_naqp.py` already reads the same file, so no new source is
  introduced. The generator asserts the document's **own stated total of 340
  entities**, expands its prefix ranges to 739 keys, and strips the footnote
  digits glued to prefixes (`TR32`, `BS711`, `9G7`) using the NOTES section's
  own `(TR)`/`(BS7)`/`(9G)` attributions rather than by eye.

  **22 of the 35 parties that count DX set `dxCountsEntities`.** The other 13
  grant exactly one DX multiplier in their sponsors' own words — OhQP's
  multipliers end "and 1 DX", MnQP gives "1 multiplier for working a DX
  station", NCQP "only one 'DX' multiplier … representing all DX worked" — so
  the flag is opt-in per party, and a party whose rules nobody has re-read with
  this question in mind keeps scoring exactly as before.

  **A DX multiplier is labelled by its prefix and identified by its entity.**
  `DL1ABC` reads as `DL`, because that is what an operator recognises — but
  Germany's ARRL row is `DA`–`DR`, so `DL` and `DJ` are one country and only
  the entity code can say so. The ARRL list designates no primary among a
  row's prefixes; its rows begin `DA`, `7J`, `OU` and `AX` where an operator
  reads `DL`, `JA`, `OZ` and `VK`. That field exists only in **AD1C's
  `cty.dat`** (`country-files.com/bigcty/cty.dat`, released 2026-08-03, fetched
  2026-08-04), which
  N1MM uses the same way — *"PA will be the the prefix shown in the multiplier
  window"*.

  **The app checks this for you** — at launch and at every contest load,
  throttled to once a day, so six logs in an afternoon still make one small
  request. It is a HEAD comparing one date; the ~350 KB body is fetched only
  when that date has moved, and a newer file takes effect at the **next
  launch** rather than mid-contest. Failure is silent and the labels in
  service stay. **It can only move a label:** a new DXCC entity does not
  arrive this way, because entities come from the ARRL list and still need a
  generator run and a release — which is the point, since those are the
  changes that move a score.

  For the repo's own copy, `python3 docs/research/gen_dxcc.py --check`
  compares and downloads nothing; `--fetch` takes a newer one and restamps
  the `cty.dat.version` sidecar, which exists because the file carries no
  version of its own.

  So `cty.dat` is a **second codified source, confined to that one field**
  (constitution Article 1, amended 2026-08-04). It only ever *chooses among*
  the prefixes the ARRL list already gives, and `gen_dxcc.py` asserts every
  label is one of that entity's own ARRL prefixes — so each label resolves
  back through the table to the entity it names, and nothing `cty.dat`
  supplies reaches scoring. 313 of the 339 labels are its primary outright;
  the rest are the ARRL key its primary pointed at, where `cty.dat` is more
  specific (`CE0Y` → `CE0`) or shaped differently (`JD/o` → `JD1`).

  **Resolution follows N1MM's split, which is prior art for behaviour and never
  for a rule:** the exchange field says which *location* was sent and the
  callsign says which *entity* sent it. N1MM matches the entity from the call
  against its country file, and its manual states the exchange half flatly —
  "There is a check on provinces and states, no check on countries". So a
  received prefix names the entity where the sponsor's exchange carries one,
  the worked callsign names it where the exchange is the literal `DX`, and a
  token that is *both* a state code and a prefix is decided by the callsign —
  but only when the call resolves to that very same entity, so `PA0AAA` sending
  `PA` is the Netherlands while `W3XYZ` sending it is Pennsylvania. A US or
  Canadian call never flips the reading, which is what keeps Alberta's `AB` a
  province even though it falls inside the ARRL list's US block `AA-AK`.

  **This replaced a shape guess.** Any token matching no county, state or
  section used to be *guessed* at as a DXCC prefix — a prefix can be almost any
  short string, and there was no table to check against. The guess had been
  narrowed to run only where DX was a multiplier class for the operator's role,
  which left it in place for *in-state* entrants on those parties. It is gone
  for everyone: `SAF` and the grid square `EM42` are errors again (note `EM`
  alone *is* Ukraine's, which is why shape was never a safe test), and the
  multiplier-class gate went with it — so North Dakota can log the DX country
  its rules ask for even though DX earns it nothing.

  **What the source cannot settle, recorded rather than papered over.**
  Spratly Is. (entity 247) has **no prefix at all** in the ARRL PDF's own text
  layer — verified against the committed PDF directly — so no callsign resolves
  to it. Fourteen prefix blocks are shared by several entities *in the ARRL list
  itself* (`FO` is Clipperton *and* French Polynesia *and* Austral *and*
  Marquesas; `VP6` is Pitcairn *and* Ducie); each resolves to one designated
  entity, with the losers named in `mergedPrefixes`, and the generator fails if
  the set ever changes. France's `TO` and `TX` pools are shared across five and
  three entities, so they resolve to nothing rather than to a guess. And the
  source prints `VP0`, not VP8, for the four South Atlantic entities.
- Salmon Run: rules from salmonrun.wwdxc.org ("Updated – July 22, 2024",
  re-read verbatim 2026-07-24); 2026 dates from the site-wide sidebar. Counties
  generated by [`gen_warun.py`](research/gen_warun.py), which asserts the
  mixed 3/4 abbreviation lengths and the rules' in-state ceiling of 111
  (39 + 49 + 13 + 10). A DXCC prefix equal to a US state or province code —
  `PA` (Netherlands), `ON` (Belgium), `OK` (Czech Republic), `LA` (Norway) —
  used to be read as the state, which could leave the 10-DXCC allowance
  under-used; the **worked callsign decides** now. This also delivers what the
  rules ask and the definition used to list as not modelled: claimed prefixes
  are matched against the current ARRL DXCC Entities List.
- MEQP: rules from the Wireless Society of Southern Maine's official PDF
  (ws1sm.com/Images/Maine_QSO_Party_Rules.pdf, title block "2026 Official
  Rules") **and** rules page (ws1sm.com/MEQP.html), both read verbatim
  2026-07-24 — the two are not redundant, since the Canadian province list and
  the DC→MD note appear only on the page and the county-line rule only in the
  PDF. Counties and the 14 province tokens are parsed out of the committed
  source text by [`gen_meqp.py`](research/gen_meqp.py); nothing is retyped.
  The sponsor publishes no multiplier ceiling, so the per-band-**and**-mode
  scope is verified against the sponsor's **own published results** instead: the
  2024 winner's 494,834 points on 1,212 QSOs factors only as 1,234 × 401, and
  401 multipliers is unreachable from a pool counted once or per mode. Those
  same numbers confirm the points rule (1,234 points on 1,212 QSOs = exactly 22
  two-point Maine contacts). The PDF's contest-period line misprints the year as
  2025; its own title block, its Oct 12 2026 deadline, the "last full weekend in
  September" formula, and the fact that 2025-09-26 was a Friday all settle it.
  DXCC entities are multipliers for every entrant, uncapped, counted once per
  band *and* per mode — and all of them used to collapse into one, which made
  this the largest single scoring gap in the catalogue. The entity now comes
  from the **worked callsign** against the ARRL list above.
- CQP: rules from NCCC's official page and PDF (cqp.org/Rules.html and
  cqp.org/pdf/CQP_2026_Rules.pdf, both stamped "Last Update: 19-July-2026 at
  1500 UTC"), plus cqp.org/cqp_multipliers.html, which alone carries the county
  table, the DC→MD fold and the "1st CA county counts as CA" rule. Read verbatim
  2026-07-24. Counties are verified **twice** by
  [`gen_cqp.py`](research/gen_cqp.py): parsed from the sponsor's table, then
  re-derived from the sponsor's own published abbreviation formula and asserted
  to match. **Rule change for 2026:** phone QSOs went from 2 points to 3, marked
  "**NEW in 2026**" by the sponsor; a full diff against the still-published 2025
  revision (Last Update 05-July-2025) shows it is the only substantive change.
  The exchange is "QSO number and 4-letter county abbreviation" and carries no
  RST; the QSO numbers reach Cabrillo's exchange columns, which is what CQP's log
  checker reads. Per the sponsor, county-line counties are sent "in a single
  exchange", so a county-line contact carries **one** number however many rows it
  logs.
- AZQP: rules from azqp.org/rules and the rules PDF linked there, read verbatim
  2026-07-24. `verified: partial` — **both are still the 2025 revision** (headed
  "2025 Arizona QSO Party", footer "Rev: 2501 6/23/2025"), so a 2026 rule change
  would not be visible; re-check before Oct 10. The **date** is not in doubt: the
  sponsor's site-wide banner gives "1500z Oct 10 to 0500z Oct 11, 2026 (UTC)",
  which agrees with the rules' own formula "2nd October Saturday, 8 AM to 10 PM
  (AZ)" — Arizona keeps MST year round, so 8 AM is 1500Z and 10 PM is 0500Z. The
  generator asserts both of the sponsor's multiplier totals, `(50 + 13 + DXCC) ×
  2` in-state and `15 × 6 × 2 = 180` out-of-state, which between them pin the
  county count, the band count and the mode count. County names and codes are
  published on two different pages as parallel lists, never paired, so
  [`gen_azqp.py`](research/gen_azqp.py) verifies the positional pairing
  three ways — same codes in the same order from both sources, names
  alphabetical, and every code a subsequence of its county name (`CNO` ⊂
  `COCONINO`, `SCZ` ⊂ `SANTACRUZ`).
- PAQP: rules from the PA QSO Party Association's official PDF
  (paqso.org/files/PAQSO_Rules.pdf, 13 pages, footer "Revision: 08/19/25"), plus
  the sponsor's two official abbreviation PDFs — 67 counties and 85 ARRL/RAC
  sections — all read verbatim 2026-07-24. Both lists are parsed from the
  committed source text by [`gen_paqp.py`](research/gen_paqp.py) with hard
  count assertions, and the rules state both counts independently (rule 10.b's
  "67 PA Counties", rule 16.a's "The 14 Canadian Sections"). `verified: partial`
  for two reasons: the rules are still the 2025 revision, and **the 2026 bonus
  station is unannounced**. Its value is not in doubt — the 2025 station N3XF
  published "1796 QSO's which results in 359,200 bonus points", exactly 200 per
  QSO — but shipping last year's call would credit a phantom bonus, so none
  ships. The **dates** are settled: the sponsor's banner says Oct 10 & 11 2026,
  the rules' own formula is "Always the 2nd Full Weekend in October", and their
  EDT parentheticals (1600Z = 1200EDT, 0400Z = midnight, …) still hold in 2026.
  **Known limitation:** the rules permit 630 m, 2200 m and microwave, which
  `Band` cannot express, so those QSOs cannot be logged; the sponsor itself
  describes typical activity as 160 m through 2 m.
- SDQP: rules from the Prairie Dog Amateur Radio Club's current page
  (sdqsoparty.com, headed "October 10 & 11, 2026"), read verbatim 2026-07-24.
  **Provenance hazard worth knowing:** the domain serves *two* rule pages — the
  root is current, while `/23-2/` is a stale WordPress copy still headed "2022
  CONTEST RULES" and still linked from search results. Nothing scoring-related
  differs between them, so this is not a rule change; the current page adds the
  explicit no-digital clause, a worked score example, and fuller bonus wording.
  Counties are generated by [`gen_sdqp.py`](research/gen_sdqp.py), which
  asserts the mixed 3/4 lengths, that `DAY` is the only 3-letter code, and that
  the band list matches the sponsor's own suggested-frequency table row for row.
- NYQP: rules from the Rochester (NY) DX Association's official PDF ("2025 New
  York QSO Party", footer "v1.2 FINAL 2025-10-01"), read verbatim 2026-07-24, with
  the 62 county **codes cross-checked against the sponsor's own CSV** while the
  **names** come from the PDF's table — [`gen_nyqp.py`](research/gen_nyqp.py)
  asserts the two sets agree exactly. The sponsor also states its Cabrillo
  `CONTEST:` value and its in-state multiplier maximum, both of which the
  generator asserts (50 + 62 + 13 = 125). `verified: partial` — no 2026 revision
  is posted, though the date is settled by the formula printed in the document's
  own title block ("Third Saturday in October") plus its EDT parentheticals.
  **Two readings worth knowing:** 60 m is included because the rules exclude only
  30/17/12 m, which no other bundled party does; and the sponsor's sample log
  contains 902 MHz, 1.2 GHz and 10 GHz QSOs, which `Band` cannot express, so
  microwave contacts cannot be logged.
- ILQP: rules from the Western Illinois ARC's official PDF ("Announcing the 2025
  Illinois QSO Party") plus the club's official county abbreviation PDF, both read
  verbatim 2026-07-24. **A secondary source was wrong and it mattered:** a web
  search reported that ILQP awards "one extra multiplier for every eight QSOs made
  with the same Illinois county". No such rule is in the sponsor's rules, and
  taking it on trust would have inflated every ILQP score —
  [`gen_ilqp.py`](research/gen_ilqp.py) asserts the phrase is still absent.
  The generator also asserts the two abbreviation traps the rules name themselves,
  `WHIT`/`WTSD` and `MASN`/`MACN`; that second pair settles a conflict between two
  sponsor documents, since the site's FAQ says Macon is `MCON` while the county
  list and the rules both say `MACN`. *Retrieval note:* the rules PDF is on page 2
  of the site's file browser, which paginates in JavaScript with no link href.
- VTQP: rules from the Radio Amateurs of Northern Vermont's **official 2026 rules
  document** (`ranv.org/vtqso.doc`, titled "VERMONT QSO Party Rules", created
  2026-01-13, footer `13-JAN-2026`) with the RANV summary page
  (`ranv.org/vtqso.html`, page-dated January 31 2026) alongside it, both read
  verbatim 2026-07-26, and re-read 2026-07-28 for the rounding question below.
  The page says outright that it is a summary and that the
  `.doc` carries the specific rules, so the `.doc` is the authority; the page
  supplies only the county **names**, since the `.doc` prints abbreviations only.
  [`gen_vtqp.py`](research/gen_vtqp.py) makes the two documents check each
  other — names parsed from the page's table, and the resulting abbreviation set
  asserted equal to the `.doc`'s own sentence "14 Vermont Counties: ADD, BEN, …".
  It also asserts the sponsor's own trap note ("Take care to not mix up WiNdHam
  (WNH) and WiNdSor (WNS)!!") and that `GRA` is Grand Isle, not the "Grand Island"
  that appears in one operating-schedule line. **This is the first party in the
  repo built entirely from a current-year rules document since MEQP** — nothing
  here rests on a stale edition. **The power multiplier of rule 7(D)(1) — QRP
  ×2, low power ×1.5, high ×1 — is applied in full since 2026-07-28**, when the
  score factor became an exact fraction; before that this party shipped no power
  multiplier rather than a wrong whole number. **The sponsor states no rounding
  rule for a fractional final score**, and its only rounding instruction
  anywhere is rule 7(B)(f)'s grid-square count, *"dividing by 3, and rounding
  down"* — so this app rounds **down**, once, on the points × multipliers
  product, following the sponsor's own idiom and taking the direction that
  cannot overstate a claimed score. `verified: partial` all the same, because
  four verified rules cannot be expressed — the W1AW/1 bonus being out-of-state
  only, RTTY and FT8 sharing one mode class where the sponsor counts two,
  30/17/12 m shipping as fully valid when the sponsor allows them for FT8/FT4
  only, and two absent multiplier kinds (approved club stations `W1NVT`, and
  grid squares) — and one placement cannot be settled: rule 1A(F) calls the
  W1AW/1 credit "an additional 2 point bonus" while rule 7(D)'s formula has no
  bonus term, so this app adds it after the power multiplier rather than inside
  it. Two genuine unknowns are open: whether Vermont is a state multiplier for
  Vermont entrants, and whether 60 m is legal.
- MNQP: rules from the Minnesota Wireless Association's **2026** document,
  `MNQP_Contest_Rules rev 31.pdf`, footer `Rev 31 – December 31, 2025`, read
  verbatim 2026-07-26, with the sponsor's official county multiplier list PDF.
  Counties are generated by [`gen_mnqp.py`](research/gen_mnqp.py), which
  parses the sponsor's list **twice** — the PDF prints all 87 alphabetically by
  county *and* alphabetically by designator — and requires the two orderings to
  agree. **The live site no longer serves the 2026 rules.** w0aa.org now
  publishes only `MNQP_2027_Contest_Rules_A.pdf`, which flags four of its own
  changes as "NEW 2027": multipliers move to once-per-mode, in-state county
  multipliers stop counting for MN stations while Minnesota itself starts
  counting, CW rises from 2 points to 3, and rovers gain two-county operation.
  Building from the live document would have been wrong in all four. Rev 31 was
  recovered from the Wayback Machine snapshot of 2026-02-09, whose copy of the
  rules page reads "last updated for the 2026 QSO Party" and links exactly that
  file; the generator pins both editions so a future re-verification cannot
  apply the 2027 rules by accident or miss them. *Two retrieval notes:* the
  sponsor's own changelog sentence is stale and identical in both years, badly
  understating the revision; and w0aa.org 404s its own PDFs unless the request
  carries a `Referer` of `https://www.w0aa.org/mnqp-rules/`.
  `verified: partial` — the exchange carries a **first name** and no signal
  report, and this repo has no name field, so an exported Cabrillo log's `ex1`
  column is empty where the log robot expects the name.
- BCQP: rules from the Orca DX and Contest Club's own 2026 page
  (`orcadxcc.org/bcqp_rules.html`, footer `Updated: Feb. 5, 2026 VA7ST`), with its
  official multiplier list, its FAQ and its score summary sheet — four current,
  mutually consistent sponsor documents, read verbatim 2026-07-26. **The sponsor
  prints its own Cabrillo `CONTEST:` value**, so unlike almost every other
  bundled party this one does not rest on the WA7BNM registry. **Reading the FAQ
  was not optional:** three rules appear nowhere else — DX contacts earn points
  but no multiplier, "There is no power multiple", and there is no mobile or
  rover category — and the first of those would have handed a BC entrant a
  phantom multiplier on every band and mode. The FAQ's two worked scoring
  examples are asserted arithmetically by
  [`gen_bcqp.py`](research/gen_bcqp.py), which also pins the sponsor's three
  own misspellings (`Shuwswap`, `Okangan`, `Richmond Center`) so nobody corrects
  them, and asserts the retired district code `NWB` is absent. `verified: partial`
  — see the BC-as-a-multiplier question above, plus one export note: ADIF's `cnty`
  field is written `BC,<district>`, which is well formed but meaningless for a
  region that has no counties. Cabrillo, the format the sponsor requires, is
  unaffected.
- SCQP: rules from the SCQP Team's official 2026 PDF, header `SOUTH CAROLINA QSO
  PARTY RULES (rev. 2.2.26)`, read verbatim 2026-07-26. The cleanest source of
  the run: one current-year document carries the rules, the 46 counties, the
  states, the provinces **and** the sponsor's own Cabrillo `CONTEST:` value, so
  nothing rests on an archive, a secondary page or a registry. **The filename
  lies and the revision line does not** — the PDF is served as
  `SCQPRULES2024_0126.pdf`, which reads like a 2024 document, while its header
  says `rev. 2.2.26` and its contents carry the 2026 dates and bonus stations.
  That is the mirror image of MNQP, whose filename was honestly 2027 while the
  trap was that the sponsor no longer published the year being built. Between
  them: never take a year from a URL.
  [`gen_scqp.py`](research/gen_scqp.py) asserts all four of the sponsor's
  point sentences, because the pay-by-who-was-worked shape is the easiest thing
  here to get backwards — and, since 2026-08-04, all three sentences of the
  county-activation multiplier, so a revision that moves its threshold or its
  scope fails the generator rather than scoring on last year's reading.
- NCQP: rules from the North Carolina QSO Party Committee's official 2026 PDF
  ("Updated 10/13/2025") plus the sponsor's county abbreviation sheet, both read
  verbatim 2026-07-26. **The abbreviation is encoded by colour, not by case** —
  the sheet prints each county name with its code in dark red and says so — so
  [`gen_ncqp.py`](research/gen_ncqp.py) parses `pdftohtml -c` output and
  takes the `#cc0000` runs as the code, while taking the *names* from the plain
  text (pdftohtml pads every run, making a mid-word boundary indistinguishable
  from the real space in "New Hanover"). The cross-check is the rules PDF, which
  prints ten codes in plain text for the "Rarest of NC" counties; all ten agree.
  Independent validation: 99 of the 100 names match the real North Carolina
  county list exactly, and the hundredth is the sponsor's own typo — the sheet
  spells Chowan "Chowen", which ships as printed and is asserted, the same call
  the repo makes for NHQP's "Merrimac". The **rare-county scoring is parsed, not
  typed**: the generator reads the 10× factor, the sweep's threshold of five and
  its 500 points out of the sponsor's own sentences, and asserts that the factor
  times the ordinary points reproduces the 20/30/50 table printed beside it — so
  an edition that changes either half of the rule fails the run instead of
  quietly scoring last year's numbers. The generator likewise asserts the
  sentences behind the self-activation multiplier, including "each county
  activated where at least one QSO was completed". What keeps NCQP
  `verified: partial` is no longer a scoring gap at all: the Cabrillo
  `CONTEST:` value is the WA7BNM registry's, because the rules enumerate the
  `CATEGORY` headers an entrant must set and omit `CONTEST:` entirely.
- OKQP: rules from the sponsor's official 2026 PDF (`k5cm.com/okqp2026rules.pdf`)
  with its county locator page and its own 2026 summary, read verbatim
  2026-07-26. **The first search result for this party is the 2003 rules** —
  `qsl.net/okdxa/OKQP.htm`, headline "2003 Oklahoma QSO Party", still live — and
  it is wrong in four scoring dimensions: it says the exchange carries a QSO
  *number* (2026: a signal report), that *nine* Canadian provinces count (13),
  that 160 m is a contest band (80 m and up now), and it has no mobile activation
  bonus at all. Reaching the real rules took three hops, via the log robot at
  `okqp.contesting.com`. [`gen_okqp.py`](research/gen_okqp.py) pins all four
  2026 values, and asserts the sponsor's own list of confusable abbreviations
  verbatim. *A schedule note worth keeping:* the sponsor's local anchors ("9 to 9
  on Saturday, 9 to 5 on Sunday") only land under **CDT** — its remark that "DST
  does NOT start on this weekend" means daylight time began the weekend *before*,
  not that Oklahoma is on standard time.
- IDQP: rules from the Idaho QSO Party's own pages, read verbatim 2026-07-26.
  **The dates are reconstructed rather than copied**, because the sponsor's date
  block contains four errors in eleven lines: it calls 13 March 2026 a Saturday
  (it is a Friday), prints a literal `xxxxZ` placeholder for the Saturday start,
  dates the Saturday end `14/March/2025`, and labels 1400Z on the 14th as the
  *Sunday* start. [`gen_idqp.py`](research/gen_idqp.py) derives the four
  instants from the formula, the printed "12 Hours" per day and the local anchors
  under EDT — and **asserts the sponsor's errors are still present**, so a
  corrected page is noticed rather than silently absorbed. *Retrieval note:* the
  county page 403s a plain fetch and needs both a browser User-Agent and a
  Referer.
- WIQP: rules from the West Allis Radio Amateur Club's 2026 page, with the
  sponsor's official Multiplier List and its Cabrillo guide, read verbatim
  2026-07-26. **The Cabrillo guide was not optional reading:** the rules say
  non-Wisconsin stations send "State or Province or Country", which reads like a
  DX prefix, while the sponsor's own worked example logs `DL6QK` as the literal
  token `DX` — so reading only the rules page would have shipped the wrong
  `dxStyle` and rejected the sponsor's own sample line. The same example confirms
  the exchange carries no signal report, and the guide prints the `CONTEST:`
  value. DC appears **nowhere in the rules** and only in the multiplier list, as
  the single row `MD Maryland/(D.C.)`. **The POWER LEVEL table — QRP ×2, low
  power ×1.5, high ×1 — is applied in full since 2026-07-28**, and its SCORING
  section states the order this app computes outright: *"Then multiply by Power
  Level multiplier. Then multiply by your multiplier count under MULTIPLIERS.
  Finally, add your bonus points."* **The sponsor states no rounding rule
  anywhere** — none of the three documents contains any rounding language, and
  all three were searched for it on 2026-07-28 — so a fractional total is
  rounded **down**, once, on the points × multipliers product: the direction
  that cannot overstate a claimed score, and the same rule Vermont gets, where
  the sponsor does at least round its own fractions down. *Retrieval note:*
  warac.org 403s a plain fetch of its multiplier page and needs both a browser
  User-Agent and a Referer.
- VAQP: rules from the Sterling Park Amateur Radio Club's official 2026 PDF and
  the sponsor's entity list, read verbatim 2026-07-26. **Its entity list is 95
  counties and 38 independent cities**, and four names — Fairfax, Franklin,
  Richmond, Roanoke — belong to both a county and a city, so this is the first
  bundled party whose county *names* are not unique.
  [`gen_vaqp.py`](research/gen_vaqp.py) reads the sponsor's asterisk to tell
  them apart and renders cities as `Name (City)`; it explicitly pins that the
  "code ends in X" convention is **not** a city test, since `FFX` is Fairfax
  County. *A retrieval note worth keeping:* the rules PDF is **two-column**, so
  `pdftotext` interleaves the columns once whitespace is normalised — quoted
  assertions have to be fragments that sit inside one column line, and several
  had to be split after failing.
- LAQP: rules from the Louisiana Contest Club's own pages, read verbatim
  2026-07-26. **Its 2026 date is derived rather than published:** rule 2 still
  carries the 2025 running, the sponsor's "LAQP Dates" page 404s, and its Recent
  Posts stop at the 2021 results. The shipped window rests on the stable
  1400Z–0200Z shape, on "first Saturday in April" fitting both the printed 2025
  date and the sponsor's archived "2020 LAQP is April 4th", and on the Challenge
  calendar agreeing — but **no formula is stated**, which is weaker than ILQP's
  derivation and is why the party ships partial.
  [`gen_laqp.py`](research/gen_laqp.py) asserts rule 2 still shows 2025, so a
  sponsor update forces the derivation to be re-checked rather than silently kept.
- MSQP: rules from the Vicksburg ARC's official "2026 MS QSO PARTY RULES" PDF and
  the sponsor's County Check List, read verbatim 2026-07-26, with msqp.eqth.net
  corroborating the date. **The first bundled party that treats FT4/FT8 as a
  first-class mode**, which is where all four of its limitations come from — most
  sharply that a grid square is not merely uncounted but **silently accepted as a
  phantom DX multiplier**, since DX stations here send a country prefix and
  `EM42` looks like one. *(A test written to assert the grid would be rejected
  failed, which is how that was found.)* *Retrieval note:* arrlmiss.org 404s a
  plain fetch of its own PDFs and needs both a browser User-Agent and a Referer.
- MOQP: rules from BEARS-St. Louis's official "2026 Missouri QSO Party Rules"
  PDF and the sponsor's Missouri County Listing, read verbatim 2026-07-26.
  **Its date does not follow its own formula and the sponsor says why** — "For
  2026 due to the Easter weekend the contest is on 11-12th of April" — where the
  usual first full weekend would have been the 4th–5th, colliding with Louisiana
  and Mississippi. A test pins that it is *not* the first weekend, so a future
  session cannot re-derive it wrongly. *Retrieval note:* the site's own "2026
  MOQP Rules" link 403s; the identical file is served from a different path, and
  a session stopping at the advertised link would have fallen back to the 2025
  edition, which is still the top search result.
- NMQP: rules from the New Mexico QSO Party's own "2026 New Mexico QSO Party
  Form Packet" (last modified 09 April 2026), read verbatim 2026-07-26. **The
  packet keeps its own change log**, and it matters: the W1AW/5 bonus was
  "Reduced… from 500 to 250" on 9 April, so any copy captured in the preceding
  fortnight is wrong. The `DX` decision comes from the packet's log
  specification and sample log (`LY2ZZ 599 DX`) rather than the prose rule that
  says "DXCC entity" — the field on the wire is what this app parses, and the
  sponsor's own scorer reads the same field.
- GQP: rules, dates and the 159-county list all from the sponsors' own site
  (gaqsoparty.com — South East Contest Club and Southeastern DX Club), read
  verbatim 2026-07-26. **Entirely first-party, with no inference needed for the
  dates**: the rules give the formula and the home page states the 2026 dates
  outright. The county list is parsed twice — from the live HTML table and from
  the page's own nine-year-old printable PDF — and the two are required to
  agree, which they do on all 159. Two open questions are recorded rather than
  guessed away: the sponsor never states which bands are legal (only suggested
  frequencies), and never caps simultaneous counties (it defers to MARAC).
- NDQP: rules, the 53-county list and the Canadian abbreviations all from the
  ARRL North Dakota Section's own "2026 ND QSO Party Rules" PDF (Last-Modified
  2026-03-06), read verbatim 2026-07-26. The sponsor here is a **section, not a
  club** — the ND Section Manager runs it directly, and there is no separate
  contest site. **Its Canadian list is parsed rather than typed**, because it is
  not the app's: `NF` + `LB` instead of `NL`, and no Nunavut. The Cabrillo
  `CONTEST:` header is the one thing not from the sponsor — five pages ask for
  Cabrillo logs without ever naming the header — so `ND-QSO-PARTY` comes from
  WA7BNM's Cabrillo Names table under Article 1's exception.
- MiQP: rules and multiplier list from the Mad River Radio Club's own site, read
  verbatim 2026-07-26 — **but the live site had already rolled forward to 2027**
  ("Next MiQP Sat 17 Apr 2027"), so the 2026 edition came from the Wayback
  Machine and **both editions are banked and diffed by the generator**. Exactly
  one sentence differs: the 2027 rules add "+ 1 District of Columbia" to the
  multiplier list. That reads like a scoring change and is not one — the rules
  defer to the Official List of Mults twice in both editions, and the list
  archived four days before the 2026 contest already carried DC. The rules name
  no year at all, and their formula reproduces the sponsor's own stated 2027
  date exactly, which verifies the reading better than any calendar could.
- OQP: rules from Contest Club Ontario's own site and the multiplier list from
  its `OQPMultList.pdf`, read verbatim 2026-07-26. **The site rolled forward to
  2027 but the rules did not** — the landing page advertises the 30th Annual OQP
  while `rules.htm` is still the 2026 edition, byte-identical to the archived
  copy of 2026-05-04. The generator asserts that split *and* diffs the 2025
  edition against it, confirming every item on the sponsor's own change list:
  phone went from 1 point to 2, VE3RHQ joined the bonus stations, a 250 m
  county-line definition arrived, and **two hours moved from Saturday night to
  Sunday** — so any pre-2026 source is wrong about both the times and the
  points. *Retrieval note:* the spot hub serves Ontario as `onqp`, not `oqp`;
  the obvious URL 404s.
- QCQP: rules from Club Radio Amateur de l'Outaouais, read verbatim 2026-07-26
  in **both language editions** — which is a real second source, not a second
  fetch, and the generator requires them to agree on all 17 region codes. They
  do, and they **disagree about Canada**: the English calls `NT` "Northern
  Territories" (not a Canadian entity) where the French correctly says
  "Territoires du Nord-Ouest", and both then add a fourteenth row, `NWT`, for
  the same territory — a row the French page left untranslated, which is the
  tell that it was appended late. All fourteen ship as printed, since refusing
  one would block a legal exchange. The home page flags the 2026 hours as new,
  so a pre-2026 source has the wrong window.
- NEQP: rules from the Nebraska QSO Party Committee's own site, read verbatim
  2026-07-26. **Two retrieval traps, both banked.** `nebraskaqsoparty.org` has
  the obvious name and is a GoDaddy content farm — generic prose, no rules, no
  dates, no county list, outbound links to a law firm and Nielsen radio
  ratings; it is banked as a *counter-example* so a later session recognises it.
  The sponsor is the `.com`, whose current rules sit at
  `…/f/rules-for-2022-nebraska-qso-party` because it edits one post in place,
  and whose body is absent from both the HTML and the site's own feeds.
  **The sponsor also contradicts itself about the start hour**: 1400 UTC is 9 AM
  CDT, but the rules gloss it "8:00 AM CDT" — WA7BNM trusted the local times and
  publishes 1300Z. The sponsor's own UTC ships, per Article 19, recorded as an
  open question.
- FQP: rules, both county lists, the Cabrillo specification and the Spelling Bee
  calls all from the Florida Contest Group's own site, read verbatim
  2026-07-26 — **the first party in six whose Cabrillo header needs no WA7BNM
  exception**, because the sponsor publishes its own spec, and it says
  `FCG-FQP`. The county list is parsed twice, from the live table and the
  printable PDF, and required to agree; they do on all 67 once one typographic
  difference is normalised. *Retrieval note:* the spot hub serves Florida as
  `flqp`, not `fqp` — the third party after California and Ontario where the hub
  prefix is not the party id.
- POTA support — the ADIF 3.1.4 `POTA_REF`/`MY_POTA_REF` fields and the
  POTARef grammar (adif.org/314/ADIF_314.htm), POTA's own ADIF and
  park-to-park references (docs.pota.app), and the park list served by
  `api.pota.app/program/parks/US` (12,938 parks; `HEAD` answers 403, which
  is why the client re-downloads weekly rather than probing freshness). All
  verified 2026-08-05 and banked verbatim in
  [`research/pota/SOURCES.md`](research/pota/SOURCES.md). The export
  duplicates a record per park pair because POTA's park-to-park page
  requires it for n-fer credit, not because ADIF asks for it — ADIF's own
  field is a comma list.
- Band edges and ADIF band strings: the ADIF 3.1.4 Band Enumeration
  (adif.org/314/ADIF_314.htm), read 2026-07-24, cross-checked against
  47 CFR §97.301(a). Default per-band frequencies — used only for Cabrillo rows
  logged without CAT data — are the ARRL band plan's calling frequencies
  (arrl.org/band-plan, same date). 1.25 m is 222–225 MHz only: the US 219–220
  MHz point-to-point digital allocation is outside the ADIF band and is
  deliberately not loggable.
- Band plan (the CW→phone crossovers that drive automatic mode switching):
  **47 CFR §97.305(c)**, the authorized-emission-types table, read 2026-07-25
  via Cornell LII because ecfr.gov 302-redirects to an interstitial;
  **§97.301(a)** for the one boundary §97.305(c) names without a number
  (80 m is 3.500–3.600 and 75 m 3.600–4.000 in ITU Region 2, so the crossover
  is 3600 kHz); and the **ARRL band plan** (arrl.org/band-plan, same date) for
  160 m alone, where §97.305(c) permits phone band-wide and so supplies no
  crossover — the plan reads "1.843-2.000 SSB, SSTV and other wideband modes".
  Excerpts banked in
  [`band_plan_sources.md`](research/band_plan_sources.md). The
  emission-type edges are used deliberately in place of §97.301(a)'s stricter
  license-class phone edges: the logger does not know the operator's class, and
  putting a radio in SSB is not itself an unlawful act. 30 m has an RTTY/data
  row and no phone row, so it is treated as CW throughout; 60 m, 1.25 m and
  70 cm have no defensible CW/phone split and the mode is left alone there.
  This table is **separate from the spot mode-inference table** in
  `SpotFilter`, on purpose — that one guesses what mode a cluster spot is in
  and is allowed to be wrong, this one decides what mode your radio is put in
  and is not.
- DC is accepted as a loggable state token (counted with states); strictly,
  KSQP rules enumerate 50 states — sponsors' checkers accept DC.
- State QSO Party Challenge: rules from the official 2026 PDF
  (stateqsoparty.com, fetched 2026-07-25, committed verbatim in
  `docs/research/`), scoring formula and award levels quoted in
  [`sqp_challenge_rules.md`](research/sqp_challenge_rules.md). The
  approved-contest resource is **generated** by
  [`gen_sqp_challenge.py`](research/gen_sqp_challenge.py) from the
  challenge's own calendar (fetched 2026-07-24) and homepage list (read
  2026-07-25), with hard assertions: 47 contests, 61 windows, 44 mapped to
  bundled parties. **Maine QSO Party is not on the 2026 approved list**
  (verified twice), so the dashboard shows MEQP logs but excludes them from
  challenge scoring, saying so. The calendar's NJQP row is known-wrong
  (Sep 19; the sponsor says Sep 12) — bundled sponsor schedules always
  supersede calendar dates, which are used only for parties this app has no
  rules for, labeled as calendar-sourced.

## Radio protocols — Elecraft voice memories

Extracted and reasoned about in
[`docs/research/k3_voice_keyer.md`](research/k3_voice_keyer.md). All fetched
2026-08-09.

- **K3S/K3/KX3/KX2 Programmer's Reference, Rev. G5, Feb. 20 2019** —
  <https://ftp.elecraft.com/KX2/Manuals%20Downloads/K3S&K3&KX3&KX2%20Pgmrs%20Ref,%20G5.pdf>
  Authority for every command byte and switch code: `SWT`/`SWH` Tables 7, 8 and
  8A, `RX`, `IC` Table 4, `OM`. The same revision the driver already cited for
  `IF`/`FA`/`MD`/`KS`/`KY`. Its `OM` entry reserves the K3's trailing dashes
  "for future module letters and product ID", which is why `parseOM` will not
  read a recorder-equipped K3 as a KX however those bytes are filled.
- **K3 Owner's Manual, Rev. D10** —
  <https://ftp.elecraft.com/K3/Manuals%20Downloads/E740107%20K3%20Owner's%20man%20D10.pdf>
  Front-panel semantics: what M1–M4 mean, and the `CONFIG:KDVR3` note that
  playing a transmit message asserts PTT by itself.
- **KDVR3 Option Installation, Rev. C** —
  <https://ftp.elecraft.com/K3S/Manuals%20Downloads/E740130%20KDVR3%20Option%20Installation%20Rev%20C.pdf>
  Authority for the K3's memory count: 2 banks of 4.
- **KX3 Owner's Manual, Rev. C5** —
  <https://ftp.elecraft.com/KX3/Manuals%20Downloads/E740163%20KX3%20Owner's%20man%20Rev%20C5.pdf>
  Two memories; played by tapping MSG then the digit.
- **KX2 Owner's Manual, Rev. B2** —
  <https://ftp.elecraft.com/KX2/Manuals%20Downloads/KX2%20owner's%20man%20B2.pdf>
  Identical two-memory behaviour.

The reference alone was not enough: it gives the switch codes but never says
what a switch *means*, and documents no memory counts at all. Selecting a KX
memory needs both — the owner's manual for the two-keystroke sequence, the
reference for each keystroke's code.

The N1MM Logger+ manual was read for interaction precedent and is cited in the
research file. Per Article 1 it is authority for nothing here, and no byte in
the driver comes from it.

## Radio protocols — Elecraft transmit control and line input

For recordings made on the Mac and played through a sound card into the radio
(Article 11 as amended 2026-08-15). Reasoned about in
[`docs/research/voice_transports.md`](research/voice_transports.md).

- **K3S/K3/KX3/KX2 Programmer's Reference, Rev. G5, Feb. 20 2019** (the
  revision the driver already cites, banked in full as
  [`k3_programmers_reference_g5.txt`](research/k3_programmers_reference_g5.txt))
  — authority for `TX;` ("Same as activating PTT or using the XMIT switch") and
  `RX;` ("Terminates transmit in all modes, including message play"), the two
  bytes `ElecraftK3Driver.setTransmit` sends. Fetched 2026-08-09.
- **K3 Owner's Manual, Rev. D10** (Aug. 24 2011) —
  <https://ftp.elecraft.com/K3/Manuals%20Downloads/E740107%20K3%20Owner's%20man%20D10.pdf>
  Fetched 2026-08-15; the passages the README's wiring steps rest on are banked
  as [`k3_owners_d10_voice_excerpts.txt`](research/k3_owners_d10_voice_excerpts.txt):
  LINE IN "should be connected to your computer's soundcard output",
  `MAIN:MIC SEL` = LINE IN or `MIC+LIN` ON, and the sound-card level "6 to 10 dB
  below the level at which the sound card's output stage starts clipping".
  The K3S, KX3 and KX2 manuals were **not** read for their audio input; the
  README says so rather than describing a jack it has not seen.

## Radio protocols — Flex transmit audio (DAX)

For recordings made on the Mac and streamed to a FLEX-6000/8000 as its own
transmit audio (Article 11 as amended 2026-08-15). Reasoned about, with the
open questions a bench has yet to answer, in
[`docs/research/voice_transports.md`](research/voice_transports.md). All
fetched 2026-08-15.

- **SmartSDR TCP/IP API wiki** — <https://github.com/flexradio/smartsdr-api-docs/wiki>
  (FlexRadio Systems' own GitHub organisation), pages `SmartSDR-TCPIP-API`,
  `SmartSDR-Ethernet-API`, `TCPIP-client`, `TCPIP-stream`, `TCPIP-dax`,
  `TCPIP-transmit`, `TCPIP-xmit`, `TCPIP-slice`, `TCPIP-sub`, `Boolean-State`,
  `SmartSDR-Status-Responses`, `Known-API-Responses`, banked whole as
  [`flex_smartsdr_tcpip_api_voice.txt`](research/flex_smartsdr_tcpip_api_voice.txt)
  (the wiki carries no revision or date). Authority for every command
  `FlexRadioDriver`'s transmit-audio path sends — `client udpport`, `dax audio
  set … tx=1`, `stream create type=dax_tx`, `stream remove`, `transmit set
  dax=`, `xmit`, `sub dax all` — the `R<seq>|<hex>|<message>` reply format, the
  reply codes it names for the operator, and UDP port 4991 for VITA-49.
- **FlexLib API v3.2.37** (FlexRadio Systems, © 2012-2017; `DAXTXAudioStream.cs`,
  `Radio.cs`, `Slice.cs`, `Vita/*.cs`), read from the versioned copy at
  github.com/KevinSShaffer/JJFlexRadio (`FlexLib_API_v3.2.37/`) — the
  manufacturer's own client, and the only primary source for the packet a
  client sends *to* the radio. Banked as constants and line numbers, not code,
  in [`flexlib_3_2_37_dax_tx_excerpts.txt`](research/flexlib_3_2_37_dax_tx_excerpts.txt):
  header bits, OUI `0x001C2D`, information class `0x534C`, packet class
  `0x03E3`, 128 stereo float32 frames per packet, 263 words, sequence mod 16,
  big-endian throughout — `FlexDAXPacketizer` byte for byte
  (`FlexDAXPacketizerTests`).
- **FlexRadio Community, Steve-N5AC (Community Manager, admin), September 2014**
  — <https://community.flexradio.com/discussion/6346756/what-are-the-audio-stream-specifications-for-dax-and-how-do-they-compare-to-vac-in-the-3000-5000>
  Authority for the sample rate (24 ksps) and format (stereo IEEE-754 float32,
  0 dBFS = 1.0) of DAX audio over the API, quoted in
  [`flex_dax_audio_format_staff_answer.txt`](research/flex_dax_audio_format_staff_answer.txt).

Two working third-party clients (nDAX, FT8CN) were read as **hints only** for
the order in which the wiki's commands are issued; no byte comes from either,
and `voice_transports.md` says where they were consulted.
