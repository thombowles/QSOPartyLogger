# QSO Party Logger — Constitution

Governing law for two recurring jobs in this repository: **adding a radio** and
**adding or updating a QSO party**. It binds every session that does either —
human or agent, attended or looped.

It exists because both jobs share a failure mode that testing does not catch:
**a wrong number that looks right.** A mistyped county abbreviation, a
multiplier counted once instead of once-per-band, a CAT byte string from the
wrong manual revision — none of these crash, none fail a build, and none
surface until a sponsor's log checker disagrees months later, or a pileup dies
because the radio stopped answering. The articles below exist to make those
mistakes hard to commit rather than easy to miss.

Where this document and a sponsor's rules disagree, the sponsor wins — and this
document is wrong and should be amended. Where this document and convenience
disagree, this document wins.

---

## Part I — Common law

### Article 1 — Provenance or it does not exist

Every rule, county abbreviation, band list, date, and protocol byte in this
repository traces to a **named official source with a fetch date**:

- **Parties:** the sponsoring club's own rules page or PDF.
- **Radios:** the manufacturer's programmer's reference, cited *with its
  revision* (`ElecraftK3Driver` cites revs F2 and G5 — follow that).

Secondary sources — N1MM/N3FJP config files, contest wikis, other loggers'
source, forum posts, LLM recall — are **never authority for a rule.** They are
at most a hint that tells you which primary source to go read. Do not paraphrase
a rule you have not seen in the sponsor's own words.

Two codified exceptions, both of the same shape — a value no other authority
publishes, and neither of them a rule:

1. **WA7BNM's Cabrillo name registry** (`contestcalendar.com/cabnames.php`) is
   authority for the `CONTEST:` header string when the sponsor publishes no
   value. Say so in the research doc when you rely on it.
2. **AD1C's `cty.dat`** (`country-files.com/bigcty/cty.dat`) is authority for
   **one field: the primary prefix a DXCC entity is displayed as.** The ARRL
   DXCC List — which is authority for the entities themselves — publishes only
   prefix *ranges*, so it designates no primary among them: its rows begin
   `DA`, `7J`, `OU` and `AX` where an operator reads `DL`, `JA`, `OZ` and `VK`.
   `cty.dat` is the only place that field exists, and N1MM's manual states the
   same use of it ("PA will be the the prefix shown in the multiplier window").

   **Scoped, and the scope is enforced by assertion.** `gen_dxcc.py` lets
   `cty.dat` only *choose among* the prefixes the ARRL list already gives, and
   asserts that every label is one of that entity's own ARRL prefixes. It never
   contributes a prefix, an entity, a name or a count, and nothing it supplies
   reaches scoring.

   **Check it with the ARRL list each season, and take a newer one:**

   ```bash
   python3 docs/research/gen_dxcc.py --check   # compares, downloads nothing
   python3 docs/research/gen_dxcc.py --fetch   # ...and takes it if newer
   ```

   The committed release date lives in the sidecar `docs/research/cty.dat.version`,
   because the file's own `=VERSION` alias carries no date and the server's
   `Last-Modified` is the only stamp there is. **Do not download it by hand** —
   a plain `curl` throws that stamp away, which is how the first copy landed
   here uncitable. Exit codes are 0 current, 1 newer upstream, 2 unknowable.

   A newer file is not by itself a reason to do anything: nearly every release
   only adds `=CALL` DXpedition entries this repo ignores. After taking one,
   re-run the generator with no flags — **its assertions are what decide
   whether anything load-bearing moved**, and they fail rather than let a
   label change quietly.

   **The app watches the same file, and may only relabel.** `DXCCLabelClient`
   checks at launch and at contest load, throttled daily, and applies a newer
   file's primary prefixes to the bundled entities at the next launch.
   `DXCCLabelRefresh` enforces the same confinement the generator does — a
   label must be one of that entity's own ARRL prefixes — and refuses a file
   whose entity or WAE counts do not agree with the bundled table. **It cannot
   add an entity, change a resolving prefix, or move a score.** A new DXCC
   entity is a generator run and a release, not a download. AD1C republishes every few days to weeks,
   but almost always to add `=CALL` DXpedition entries this repo ignores; the
   one field consumed here moves only when DXCC gains or loses an entity. The
   generator's assertions are the real guard, so a release that touched
   anything load-bearing fails the run instead of moving a label quietly.

> **Amended 2026-08-04.** The original text carried the WA7BNM exception alone
> and said secondary sources are "never authority for a rule". A DX multiplier
> still has to be *shown* as something, and the sourced options were a country
> name or one of the ARRL row's own oddities. Rather than invent a rule for
> picking — the first version of this shipped "whichever prefix you worked
> first", which made the label depend on log order — the field was taken from
> the file that publishes it, and confined to display by an assertion. The
> article was not wrong about rules; it had nothing to say about labels.

### Article 2 — Never hand-type data that exists in a file

County lists are **generated by script** from the sponsor's own file, with a
hard count assertion that fails loudly:

```python
assert len(al) == 67, f"expected 67 AL counties, got {len(al)}: {sorted(al)}"
assert len(set(al.values())) == 67, "AL county names not unique"
```

Generators live in [`docs/research/gen_parties.py`](research/gen_parties.py),
alongside the raw source text they parse. A hand-typed abbreviation is a
scoring bug with no symptom: the county validates, the QSO logs, the multiplier
counts, and the sponsor rejects it.

Where a sponsor publishes counties only as an image or a PDF map, extract to
text first, commit the extracted text, and generate from that — so the next
person can audit what you read.

### Article 3 — Verified, or explicitly partial. Never silently uncertain

Every party's `notes` field states the source, the fetch date, and **either**
full verification **or** the literal marker `verified: partial` followed by the
specific open questions:

> `"verified: partial — points/mults/bonus from txqp.net rules; counties from official txcounty.zip (2014 file, fetched 2026-07-23). Confirm band list and current-year rules before submitting."`

Partial ships. Unlabeled uncertainty does not. "I could not find the band list"
is an acceptable outcome recorded in `notes`; quietly guessing the band list is
not.

**The marker is load-bearing, not decorative.** `PartyDefinition.isPartiallyVerified`
matches the literal string `verified: partial`. So:

- Write the marker exactly. A party whose rules are unconfirmed but whose notes
  paraphrase it ("mostly verified", "some details unclear") ships looking
  trustworthy.
- Introduce the open questions with the literal words **`OPEN QUESTION`** (or
  `OPEN QUESTIONS`), and modelling gaps with **`KNOWN LIMITATION`**.
  `PartyDefinition.openQuestions` splits the notes at the first marker for
  auditing, and `operatorAlerts` cuts each numbered item to its headline
  sentence for display.
- Both properties are covered by `PartyCatalogTests`, including a per-party
  roster of which parties are partial — so a status change has to be deliberate.

**But the marker no longer decides what the operator sees.** It fired on 39 of
46 parties, which is the default state rather than a signal, and the picker read
as a catalogue of broken things. **What the operator sees is
[`caveats`](../Sources/Core/Parties/PartyDefinition.swift), classified by what
the gap costs them** — see
[the design](superpowers/specs/2026-07-26-party-caveats-design.md):

| kind | means | raises a warning |
| --- | --- | --- |
| `exportBlocking` | the log this app writes cannot be submitted as-is | **yes** |
| `scoreAffecting` | the app's total will differ from the sponsor's | **yes** |
| `ruleInference` | the sponsor's text is ambiguous; this app inferred a reading | no |
| `provenance` | source stale or archived; re-check before the next running | no |
| `cosmetic` | recorded for completeness; no scoring or export consequence | no |

So a **new party must carry both**: the `verified: partial` marker in `notes`
where the rules were not fully confirmed, *and* a typed caveat for each thing
that costs the operator something. A party whose only gaps are provenance ones is
still `verified: partial`, and correctly raises no warning. Caveats are never
read by `ScoreEngine`; `summary` is authored, `detail` is copied from the notes
rather than retyped (Article 2).

### Article 4 — The schema evolves additively; refactors are quarantined

New rule shapes arrive as **optional fields with a computed accessor whose
default reproduces prior behavior exactly** — the pattern already used by
`dxStyle`, `allowedModes`, `maxSimultaneousCounties`, `stateAliases`,
`excludedStateTokens`, `provinces`, `exchangeIncludesRST`, `dxMultCap`, and
`scoreMultipliers`:

```swift
/// Max counties one station may claim simultaneously (county lines).
var maxSimultaneousCounties: Int { maxSimultaneousCountiesRaw ?? 4 }
private let maxSimultaneousCountiesRaw: Int?
```

Every already-bundled party must score **identically** before and after your
change. Its existing tests are the proof.

Structural refactoring of `ScoreEngine`, `PartyDefinition`, or `RadioDriver` is
permitted — the schema must not accrete flags forever — but a refactor is **its
own commit, adding no party and no radio**, with the full suite green before and
after. Never bundle a refactor with "add Ohio": it makes a scoring regression
unbisectable, and a scoring regression is the one bug this repo cannot afford to
lose track of.

### Article 5 — Tests are the contract, and they run without hardware or network

- No party lands without a per-party test file (Article 18).
- No radio lands without protocol tests over a mock transport (Article 13).
- Tests never open a serial port, never dial a cluster, never fetch a URL.

A test suite that needs a K3 on the desk is a suite that stops being run.

### Article 6 — Docs ship in the same commit as the behavior

A change that adds a party or a radio also updates, in the same commit:

- the README's supported-parties table or radio feature bullet,
- the party's entry in [`PARTIES.md`](PARTIES.md) — what is unusual about it,
  and every rule that could not be modelled,
- the README's test count,
- [`PROVENANCE.md`](PROVENANCE.md) (source + fetch date),
- the README's keyboard reference table, if any key gained a behavior.

The README is the operator's document and stays short: one table row per party,
one line per feature. Detail belongs in `PARTIES.md`, sources in
`PROVENANCE.md`. A party's row is derived from its JSON — dates, window length
and multiplier count are never hand-typed (Article 2). The row names the
entities the way the sponsor does (parishes, districts, regions), which is
`countyTerm` where the party sets one and the sponsor's own word where it
does not.

### Article 7 — Keyboard-first

Every feature has a keyboard path. This app is operated at 35 WPM with both
hands on the keyboard; a control reachable only by mouse is, during a run,
unreachable.

### Article 8 — Verification is by test, build, and log — never by looking

Claims that something works are backed by the command and its output:

```bash
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS'
```

Do not report a party as landed because the JSON parses. Do not report a driver
as working because it compiles. If a step was skipped, say which.

### Article 9 — One party, or one radio, per commit

So that a scoring regression bisects to a single sponsor's rules, and a CAT
regression bisects to a single manufacturer's manual.

---

## Part II — Adding a radio

### Article 10 — Blast radius

A new radio consists of **exactly**:

1. one driver in `Sources/Hardware/Radio/`, conforming to `RadioDriver`,
2. one `RadioDescriptor` appended to `RadioRegistry.all`,
3. one test file in `Tests/Hardware/`.

Nothing else changes. **No model name, model number, radio `id`, driver type, or
model-specific constant may appear in executable code or in operator-visible
text under `Sources/App/` or `Sources/UI/`.** The registry descriptor is how the
UI learns what the radio can do — `connection` decides serial-port picker vs.
host/port fields, `baudRates` and `defaultNetworkPort` fill those fields and
their hints, `keyerLabel` supplies the picker's name for this radio's own keyer
(Article 11), `supportsDirectKeying` decides whether the keyer group is shown at
all, and `RadioRegistry.defaultRadioID` is the radio a fresh install starts on:

```swift
if descriptor?.supportsDirectKeying ?? true {
    keyerGroup
}
```

If a radio cannot be added inside that boundary, **the protocol is wrong** —
widen `RadioDriver` or `RadioDescriptor` in a separate commit (Article 4), then
add the radio. Do not smuggle a special case into the app layer.

**Two things are not violations, and the check must not flag them:**

- **Comments.** Naming the radio an observation came from is provenance
  (Article 1); deleting the model name deletes the evidence. What the rule
  actually forbids is the app *behaving* differently per model, and a comment
  cannot. A comment must still describe the general rule the code follows —
  `RadioController`'s note that a rig in QSK drops its TX flag between CW
  elements explains why the TX badge is held for the estimated send duration,
  and that guard is unconditional, which is the part that matters. A comment
  implying the app special-cases a model is wrong even when it greps clean.
  (Keep such a note on its own line; the check reads only the start of a line,
  so a model named in a trailing comment is flagged.)
- **Frozen `UserDefaults` tokens.** `AppSettings.KeyerBackend`'s raw values are
  storage, never display (Article 11). `case radioInternal = "K3 internal (KY)"`
  is load-bearing: change that string and an existing operator's keyer choice
  silently resets to `.direct` on next launch. It is pinned by
  `KeyerBackendLabelTests.testStoredDefaultsStillDecode`.

Enforcement check before committing — this must return nothing:

```bash
grep -rniE "k3|kx3|kx2|flex|icom|yaesu|kenwood|elecraft|ci-v" Sources/App Sources/UI \
  | grep -vE ':[0-9]+: *(//|\*)' \
  | grep -vE ':[0-9]+: *case [A-Za-z]+ = "'
```

**The grep is necessary, not sufficient.** It matches names, so it is blind to a
model-specific *number*: `4992` (the Flex CAT port) and `38400` (the K3's baud)
sat in `RadioBar`'s help text and baud fallback the whole time the unfiltered
check was being run, and never once appeared in its output. Every such constant
comes from the descriptor. Two tests do the half the grep cannot:
`RadioRegistryTests` asserts the registry supplies the app layer's defaults, and
`KeyerBackendLabelTests.testNoDisplayedLabelNamesAManufacturer` asserts that no
string an operator can actually see names a manufacturer — which is also what
stops the frozen-token exemption above from being used to smuggle in a label.

> **Amended 2026-07-25.** The original check was `grep -rniE
> "k3|kx3|kx2|flex|icom|yaesu|kenwood|ci-v" Sources/App Sources/UI` with no
> filters and the instruction that it "must return nothing". It returned eight
> hits, and could not return zero without breaking something: one of them,
> `AppSettings.KeyerBackend`'s frozen raw value, is *required* by Article 11 and
> resets an operator's keyer choice if changed. An article that cannot be
> satisfied gets ignored, so the check was narrowed to what is actually
> forbidden — and, in the same pass, found to be missing two real violations it
> had no way to see (`4992`, `38400`). Three of the eight were genuine, and are
> fixed in the commits that follow this one: a radio `id` literal and a driver
> type reference in `AppSettings.init`, and a help string naming a vendor's
> client software in `RadioBar`.

### Article 11 — Direct CW keying is the only path where key lines exist; voice is played by the app, or by the radio

**Every radio has exactly one way to send CW.** Where the radio's interface
exposes hardware key lines, the app keys it directly and *only* directly, and
the driver ships `supportsDirectKeying: true`. Where it does not, the radio's
own keyer is the only path, and the driver says so by conforming to
`InternalKeyerDriver`. Never both, never neither —
`RadioRegistryTests.testEveryRadioHasExactlyOneWayToSendCW` enforces it.

Direct DTR/RTS line keying — timed in the app by
[`CWKeyer`](../Sources/Hardware/Keying/CWKeyer.swift) — wins over handing text
to the radio's own keyer, because:

- **Esc aborts mid-character.** Text sitting in a radio's keyer buffer keeps
  sending after you have decided to stop.
- **Timing is ours.** Buffer latency and the radio's internal housekeeping do
  not stretch a dit.
- **Element timing is testable** without a radio on the bench
  (`KeyerTimingTests`, `MorseCodeTests`, `CWKeyerTests`).
- **Behaviour stops being a per-model firmware question.** Speed changes
  mid-message, abort lands mid-character, and completion is known rather than
  estimated — on every serial radio, by the same code, proved by the same test.

Therefore:

- Any radio reached over serial or USB-serial gets `supportsDirectKeying: true`
  and a `KeyerLineConfig`-compatible wiring story documented in the README.
- **A driver with key lines implements no internal-keyer path at all.** Not a
  stub, not an unused-but-tested builder: `sendInternalKeyerText` and
  `stopInternalKeyer` live on `InternalKeyerDriver`, which such a driver does
  not conform to. Dead protocol members are how a second path creeps back.
- **There is no keyer preference.** One path per radio means nothing to choose
  between, so no setting, no picker, and no per-model label. `RadioInternalKeyer`
  is named for the protocol members it drives, not for a model.
- **The wiring story is now load-bearing, not advisory.** Removing the fallback
  means an operator whose key line is not set up has no in-app way out, and
  keying is open-loop — no radio reports that a line it is ignoring was
  toggled. A QMX ships `Key from USB DTR: None`. The README tells them, per
  model, in the same commit as the driver.
- **Never key on connect.** Deassert both control lines when the transport
  opens, before any polling starts, so the rig cannot transmit because the app
  launched. Abort must take effect immediately, not at the end of the current
  message.
- Keyer speed syncs **both ways**: `setKeyerSpeed(wpm:)` out, and
  `onKeyerSpeedChange` in when the operator turns the front-panel knob.
- **Speed is a live parameter, not a per-message constant.** `⌘=` during a
  transmission changes *that* transmission. A keyer that reads the speed once,
  at the top of a message, is broken however accurate its timing is.
  Concretely:
  - Schedules are denominated in **dit units, never milliseconds**
    (`KeyerTiming.KeyEvent.dits`). A schedule that cannot name a speed cannot
    bind a stale one; speed is applied at playback, one element at a time.
  - A key-down element in flight finishes at the speed it began at — half of
    one speed and half of another is a malformed element on the air, and worse
    than a few milliseconds of lag. Key-up gaps re-read every dit, which caps
    the lag at one dah rather than the seven dits of a word gap.
  - `setKeyerSpeed(wpm:)` goes out the moment the operator asks, never queued
    behind the message in flight — and a driver must not adopt a protocol form
    that *defers* side-effects. Elecraft's `KYW` ("wait") is the trap this
    names: rev G5 documents it as delaying "any following host commands …
    until the current message has been sent … e.g., KS (keyer speed)", which
    is precisely the behaviour this article forbids.
  - Nothing may infer that a message has ended from a duration computed when
    it began. Once speed can change mid-message that arithmetic is wrong, so
    the direct keyer reports real completion (`CWKeyer.onFinished`).
  - The test floor is a **timed** one: drive the keyer through a transport that
    timestamps every line transition, change speed part-way, and assert both
    that later elements really did change length and that no single element
    was sent at two speeds (`CWKeyerTests`).

#### Voice: recordings this app plays itself, and the radio's own memories

**Phone messages are recordings made on this Mac, played to the radio by this
app, which keys the radio around them.** Where a radio also has on-board voice
memories, those remain a supported source the operator can choose instead. Two
things are absolute either way: the app never hands playback to something it
cannot stop, and it never keys a radio it has not been asked to key.

The reasoning parallels the CW rule above — **own the path, and the path can be
tested and aborted:**

- **The app knows when the clip ends, because it is playing it.** Esc stops the
  player and drops PTT the same instant; repeat CQ times itself off the real
  end; the TX badge clears when the audio does, not on an estimate.
- **The recording is the operator's, per contest.** "CQ Texas QSO Party" and
  "CQ Alabama" are different files; the exchange changes county to county. A
  set kept per party outlives the log, and is re-recorded only where the
  contest changed.
- **The audio path is stated, not assumed.** Level is the one thing the app
  cannot know, so it gives the operator a meter, a level control, and a
  play-to-radio button, and the README says which jack and which menu.

Therefore:

- **A radio the app plays through implements exactly one of two paths, in its
  driver, and nothing in the app layer names either radio.**
  `TransmitControlCapable` (`setTransmit`) is for a radio reached through a
  sound card, which the app keys over CAT — `TX;`/`RX;` on the Elecraft
  family. `AudioStreamTransmitCapable` is for a radio that takes the samples
  over its own link — DAX on a Flex — where the driver keys, streams and unkeys
  and reports `started`/`finished`/`stopped`/`failed` for real. A driver whose
  radio can do neither conforms to neither; the phone keys then use the radio's
  memories if it has any, and say so.
- **Recordings are the default source; the radio's memories are the option.**
  On a radio with both, `AppSettings.phoneMessageSource` picks; it starts on
  recordings. On a radio with no recorder there is nothing to pick.
- **A source that is not ready leaves the keys inert, with the reason.** No
  output device chosen, a stream the radio refused, a memory that holds nothing:
  the key is disabled and its tooltip and the Messages editor say why. **It
  never falls back to the other source on its own** — the operator chose, and
  a fallback would put a different recording on the air than the one they
  expect.
- A radio with on-board voice memories still implements `VoiceMessageCapable`,
  reports **how many memories exist** and **whether the hardware that provides
  them is fitted** — discovered from the radio at connect, never hard-coded per
  model (Article 10) — and still **never transmits an unconfirmed memory**:
  where reaching one takes a bank change first, the driver confirms the bank or
  abandons the play. Wrong audio on the air is worse than silence.
- **Never transmit on connect**, exactly as for CW. No socket, no stream, no
  `TX;` until an F-key, Return under ESM, repeat CQ, or the editor's
  play-to-radio asks.
- **The transport is tested without a radio:** the exact CAT bytes and the exact
  packet bytes over mock transports, the keying sequence (lead, play, tail,
  unkey; abort at every point) over a fake player, and the flow's choice of
  what goes on the air over synthetic buffers (`DAXPacketizerTests`,
  `VoicePlayerSequenceTests`, `FlexRadioDriverTests`, `K3ProtocolTests`,
  `EntryFlowTests`).

> **Amended 2026-08-09.** The article covered CW only, which left the obvious
> reading of "add voice keying" pointing at what every other logger does: play
> WAV files from the computer. N1MM's own manual records where that leads for a
> radio that has its own recorder — it documents that the program cannot know
> when a radio's built-in recorder has finished, and therefore requires VOX,
> cannot reliably abort with Esc, and cannot time an auto-CQ repeat. Every one
> of those is a consequence of the audio living on the wrong side of the cable.
> The Elecraft radios answer all three over CAT (`RX;`, `IC;` byte a bit B2, and
> automatic PTT during message play), so the rule was written down before
> someone reached for a sound card on the next radio.

> **Amended 2026-08-15.** Six days later the sound card was reached for on
> purpose. The operator asked to record, edit and save voice files for each
> contest and play them to the radio — over the network on a Flex, through the
> sound card on an Elecraft — with the radio's own memories kept as an option.
> The 2026-08-09 text had weighed only the case where *another program* owns
> the WAV: no end signal, no reliable Esc, VOX required. When this app owns
> the player all three invert, and the article's real principle — own the path
> so it can be aborted and tested — points the other way. Two facts the earlier
> text did not weigh forced it: a Flex has no recorder at all, so Article 11 as
> written left the app's network radio with no phone keys; and message sets are
> per contest while a radio's recorder holds one set. The 2026-08-09 design
> stays in force for the radio's memories; see
> [`2026-08-15-voice-messages-design.md`](superpowers/specs/2026-08-15-voice-messages-design.md)
> for the recordings.

### Article 12 — Protocol provenance

The driver's header comment names the document and revision it was written
against, and the test file quotes the byte strings it verifies. When a manual
revision changes a command's response format, the test names both revisions —
`K3ProtocolTests` covering `IF;` across revs F2 and G5 is the standard.

### Article 13 — Required capabilities and their tests

A driver implements the whole `RadioDriver` surface, honestly:

| Capability | Requirement |
| --- | --- |
| `start(transport:)` / `stop()` | Idempotent; safe line states at open (Article 11) |
| `onStateChange` | Frequency, mode, TX state — polled or pushed |
| `onKeyerSpeedChange` | Front-panel speed changes reported |
| `setFrequency(hz:)` | Exact Hz |
| `setMode(rawMode:)` | **Resolves `"SSB"` to the conventional sideband for the current frequency** — the driver owns the band plan, not the caller |
| `setKeyerSpeed(wpm:)` | 8–50 WPM, sent immediately — never queued behind a message in flight |
| `sendInternalKeyerText` / `stopInternalKeyer` | On `InternalKeyerDriver` only, and only for a radio with no key lines (Article 11) |
| `VoiceMessageCapable` | Conformed to — with a real memory count and a real fitted/not-fitted answer — wherever the radio has on-board voice memories (Article 11) |
| `TransmitControlCapable` | Conformed to wherever the app can key the radio over CAT around a sound-card message; the exact bytes for on and off are tested (Article 11) |
| `AudioStreamTransmitCapable` | Conformed to wherever the radio takes transmit audio over its own link; the setup commands, the packet bytes, the key/unkey order and every failure are tested over mock transports (Article 11) |

Tests drive a **mock transport**: feed captured radio responses in, assert
parsed `RadioState` out; assert the exact bytes the driver emits for a QSY, a
mode change, and a speed change. Include at least one malformed/truncated
response — radios do send partial lines, and a driver that traps on one takes
the app down mid-contest.

Two more, both about the path *not* taken:

- A direct-keying driver proves on the wire that it never sends its radio's
  keyer-text command — drive a full session over the mock and assert the bytes
  never appear (`testDriverNeverSendsKY`). Reading the source is not the test:
  the command can come back through a poll loop.
- Mid-message speed change is proved per path. Direct keying gets the timed
  test in Article 11. A radio keyed by its own keyer gets the exact bytes, and
  the driver's banked reference is quoted on whether the radio applies them to
  a message already sending — or the entry states that the manual is silent
  (Article 3). Never assume it works because another maker's does.

### Article 14 — Connection must be validated, never silently "successful"

A TCP connection to the wrong IP succeeds. An open serial port to a powered-off
radio succeeds. Every new radio therefore participates in
`RadioController.startValidation` — connected but not answering within the
window must produce a message that names the target and says what to check.
Where a transport needs an OS permission (Local Network, serial device access),
the failure message says so and names the Settings path.

---

## Part III — Adding or updating a QSO party

### Article 15 — Research before code

Bank `docs/research/<id>_rules.md` **before** writing any JSON, with these
sections, in this order.
[`nhqp_rules.md`](research/nhqp_rules.md) is the reference implementation of
this template — match its specificity, including its habit of quoting the
sponsor's exact words.

1. **Sponsor / sources** — club, callsign, rules URL, PDF URL, revision markers
   as printed, fetch date, log-submission address, and any superseded revision
   you consulted.
2. **Dates and times for the target year, in UTC**, concretized to absolute
   timestamps — not "third weekend in September".
3. **Exchange** — in-state, out-of-state W/VE, and DX forms separately; and
   whether RST is part of it at all (MDC's is call + location only).
4. **QSO points by mode.**
5. **Dupe rule.**
6. **Multipliers** — in-state and out-of-state stated **separately**, each with
   its counting scope (once / per mode / per band) and any cap.
7. **Bonus stations and bonus points** — including an explicit "NONE" when
   there are none, so a later reader knows you looked.
8. **Final-score multipliers** — likewise explicit when none.
9. **County-line / multi-county rules** — how many counties one station may
   claim at once, and whether mobiles may change county mid-contest.
10. **Valid bands** — and note WARC/VHF exclusions in the sponsor's phrasing.
11. **Categories** — for Cabrillo `CATEGORY-*` headers.
12. **Cabrillo `CONTEST:` header** — with its authority (Article 1).
13. **County list** — abbreviation length, plus spelling anomalies flagged
    (NHQP's rules print "Merrimac" for Merrimack; the abbreviation is
    unaffected, and the note is what stops someone "fixing" it later).
14. **Engine shapes to watch** — the unusual bits, named. This section is what
    turns research into an implementation plan.

Commit the raw extracted sources next to the write-up.

### Article 16 — Asymmetry is the norm, not the exception

In-state and out-of-state stations almost never count the same things the same
way. NHQP is the canonical trap: in-state counts a combined list **once for the
contest** with a **10-DXCC cap**, while out-of-state counts NHQP counties
**once per band** — and the dupe scope (band + mode) matches neither.

Never fill `outState` by copying `inState`. Derive each from its own sentence in
the rules, and if the rules only describe one side explicitly, that is an open
question under Article 3, not an invitation to infer.

### Article 17 — Mapping rules to the schema

| What the sponsor's text says | Where it goes |
| --- | --- |
| Points per phone / CW / digital QSO | `points` |
| "once per band per mode" | `dupeScope: "bandMode"` |
| Who counts what, and how often | `multipliers.inState` / `.outState` + `countScope` |
| "up to 10 DXCC countries" | `dxMultCap` |
| Home-state county also gives the state | `homeStateCountsViaCounty: true` |
| "RS(T) + DX" | `dxStyle: "token"` |
| DX stations send their country prefix | `dxStyle: "prefix"` |
| No digital category | `allowedModes: ["phone", "cw"]` |
| County-line sitting forbidden / 2 allowed / junctions | `maxSimultaneousCounties` |
| "DC counts as Maryland" | `stateAliases: {"DC": "MD"}` |
| Home state's own token never sent | `excludedStateTokens` (defaults to `[homeState]`) |
| A short province list (OhQP counts 11) | `provinces` |
| Exchange carries no RST | `exchangeIncludesRST: false` |
| Exchange carries an operator name | `exchangeIncludesName: true` |
| No host region — every entrant sends the same shape (NAQP) | `hasHomeRegion: false` |
| The county slot holds something else — districts, regions, DXCC entities | `countyTerm` / `countyTermPlural` (lowercase; UI capitalizes) |
| Bonus station | `bonuses: [{"type": "workStation", …}]` with the right `scope` |
| Per-N-counties mobile bonus | `mobileCountyCount` |
| Bonus for counties *I* activate | `activatedCountyCount` |
| **Multiplier** for counties *I* activate | `multipliers.inState.activatedCountyMultiplier` — every field required; no two sponsors agree on any of them |
| Named counties pay N× QSO points | `countyPointFactor` (scales the points table, so it lands *inside* the multiplication) |
| "Work five of these ten for 500" | `bonuses: [{"type": "designatedCountySweep", …}]` — a named set, unlike `sweepTiers` |
| Tiered county sweep | `sweepTiers` (ascending; highest reached pays, non-stacking) |
| Power / station-category score multiplier | `scoreMultipliers` |
| Operating windows | `schedule` (UTC) |

A rule with no row here needs a new optional field under Article 4 — and a note
in `notes` if you ship before the field exists.

### Article 18 — The per-party test floor

Every party gets `Tests/Core/<State>QSOPartyTests.swift`, modeled on
[`AlabamaQSOPartyTests`](../Tests/Core/AlabamaQSOPartyTests.swift), asserting at
minimum:

- **County data** — exact count, uniqueness, and **at least six abbreviation
  spot checks chosen from the irregular ones** (`CHOU`→Calhoun, `TDEG`→Talladega,
  `SCLR`→St. Clair). Checking `LEE`→Lee proves nothing.
- `cabrilloContest`, `allowedModeClasses`, `maxSimultaneousCounties`, `dxStyle`.
- **Multiplier scope, in-state and out-of-state, separately** — including a
  case that would pass under the wrong scope and fail under the right one
  (same county on a second band, same county in a second mode).
- Points per mode, and that disallowed modes are **invalid rather than
  zero-point** (no points, no mults, counted in `invalidModeCount`).
- Exchange parsing: a valid county, the home-state token **rejected**, the
  party's DX form accepted, and a county-line entry at the party's exact limit.
- Dupes, and that a mobile's county change is a **new** QSO rather than a dupe.
- The schedule windows, as exact UTC instants.
- Every bonus rule the party has, and its score multipliers if any.

### Article 19 — The schedule is annual and dated

`schedule` carries windows for the **target year only**, in UTC, derived from
both the sponsor's stated formula ("third weekend in September") **and** their
printed dates. When the two disagree, that is an open question under Article 3
— sponsors do publish wrong dates.

**A majority of calendars is not evidence.** NJQP 2026 settled this concretely:
the State QSO Party Challenge's official calendar PDF and a web search both put
it on Sep 19, WA7BNM put it on Sep 12, and the sponsor's own rules say **Sep 12**
— so two of three aggregators, including the one designated primary, were wrong.
Calendars are for deciding *build order*. The date that ships comes from the
sponsor, every time, even when every aggregator agrees against them.

### Article 20 — Updating an existing party

A party is re-verified whenever the sponsor revises its rules, and at minimum
once per contest year. When a rule changes:

- Re-fetch, re-date, and update `notes`.
- **Record the diff.** Cite the superseded revision, quote the changed clause in
  both its old and new form, and state which one the code now follows — the
  model being NHQP's note that the June 2025 PDF counted counties once for a
  max of ten, while the August 2025 revision that carries the 2026 dates counts
  them once per band for a max of 50.
- Update the schedule (Article 19) and re-run that party's tests.

Never silently overwrite a rule. The diff note is what lets next year's session
tell a rule change from a transcription error.

### Article 21 — Bundled versus user-installed

Parties that are verified — fully or partially, per Article 3 — ship bundled in
`Resources/Parties/`. User files in
`~/Library/Application Support/QSOPartyLogger/Parties/` override bundled ones by
`id`, so an operator can always correct a rule mid-season without waiting for a
build. Never make a bundled party the only copy of data a user might need to fix.

---

## Part IV — The worklist

### Article 22 — Date order, and a definition of done

Pending parties are tracked in `docs/parties/WORKLIST-2026.md`, ordered by
contest date, so the next contest to run is always the next one built. Each
entry carries its status and its sources.

A party is **done** when all of these are true:

- [ ] `docs/research/<id>_rules.md` complete, all 14 sections (Article 15)
- [ ] counties generated by script with count assertions (Article 2)
- [ ] `Resources/Parties/<id>.json`, with provenance and any `verified: partial`
      open questions in `notes` (Article 3)
- [ ] per-party test file meeting the floor (Article 18)
- [ ] **full suite green** — command and output recorded (Article 8)
- [ ] docs: README table row + test count, `PARTIES.md` entry, `PROVENANCE.md`
      sources (Article 6)
- [ ] committed alone (Article 9)

A radio is **done** when Articles 10–14 are each satisfied and the README
documents its wiring or network setup.

---

## Appendix A — Known violations

Standing debts against these articles. Fix on contact; do not let them become
precedent.

1. **TQP is `verified: partial`** — band list and current-year details
   unconfirmed against txqp.net. Separately, `tqp.json` ships
   `cabrilloContest: "TX-QSO-PARTY"`, which WA7BNM lists only as an *alias*,
   while [`tqp_verify.md`](research/tqp_verify.md) concludes `TXQP` is the safe
   export value and the sponsor's log robot is still a placeholder with no
   published accepted values. The research and the shipped data disagree;
   resolve under Articles 1 and 20 before anyone submits a TQP log.

---

## Amending this document

These articles are descriptive of what has worked here, not sacred. When a
sponsor's rules or a radio's protocol makes an article wrong, amend the article
in its own commit, with the case that forced the change recorded. An article
nobody can follow gets ignored, and an ignored constitution is worse than none.
