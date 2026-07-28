# Assisted-category enforcement — a NON-ASSISTED entry takes no spots

> **Revised 2026-07-28, same day, after the first version shipped.** KE5CW,
> having tried the build: *"Actually, just prevent usage of clusters when
> non-assisted is selected."* The design below was warning-only — it let the
> feeds run and told the operator afterwards that the claim was now false.
> **Prevention replaces it as the primary mechanism**: a NON-ASSISTED entry
> cannot connect, cannot auto-connect, cannot poll the hub, and loses both
> the connection and the network spots the moment the claim is declared.
>
> What survives from the original, and why: the **record** (`usedSpots`) and
> the **strip badge**, in a strictly narrower role. Prevention cannot reach
> backwards — spots taken legitimately under ASSISTED are already in the log,
> so switching the claim to NON-ASSISTED afterwards is the one case left, and
> it is exactly the case that would otherwise ship a false Cabrillo header in
> silence. Under prevention the badge can arise no other way, which turns it
> from a nag into a precise signal. The dismissal (⌘.) and the
> Cabrillo-export re-arm are unchanged.
>
> `AssistedSpotWarning` is renamed `SpottingPolicy`, since the type now owns
> permission as well as wording. Sections below are the original design;
> read them as the state of things before this revision, except where the
> revision says otherwise.

---

# Assisted-category warning — spots used while the entry says NON-ASSISTED

**Date:** 2026-07-28 · **Trigger:** follow-up to
[2026-07-28-contest-entry-fields-design.md](2026-07-28-contest-entry-fields-design.md),
whose explicit non-goals list ends: *"A 'cluster connected while NON-ASSISTED'
warning — worthwhile but a behavior feature, not a setup field; left for its
own session."* This is that session. Designed and executed autonomously; the
approval gates of the brainstorming flow are collapsed into this document plus
the commit record.

## Problem

Contest Setup now collects `CATEGORY-ASSISTED` and the Cabrillo export
declares it. Nothing connects that claim to what the app actually did. The
app has two spotting feeds — the telnet DX cluster (`SpotClient`, which can
**auto-connect when a contest opens**) and the QSO Party Hub poller
(`HubSpotClient`) — and using either while the profile says `NON-ASSISTED`
silently invalidates the claimed category. NAQP rule 5A(ii) (banked in
`docs/research/naqp_rules_2026.txt`, fetched 2026-07-28) is the canonical
statement:

> "Access to spotting information obtained directly or indirectly from any
> source other than the station operator, such as from other stations or
> automated tools, spotting networks, skimmers, social media, watching
> participating stations live streaming, etc., is prohibited."

The distinction is universal Cabrillo V3 (`CATEGORY-ASSISTED:` applies to
every contest that splits SO/SOA), so the mechanism is party-neutral: **no
party-specific branching anywhere**, per the layout rule for `Sources/UI/`.
NAQP is provenance, not a branch condition.

## What ships

### 1. The fact: `ContestLog.usedSpots`

`var usedSpots: Bool = false` on the persisted document — set the first time
a spot from **either** feed is delivered into the session's `SpotStore`, via
a new `LogDocument.noteSpotsUsed()`. Decoding is tolerant
(`decodeIfPresent ?? false`, the `exchangeName` pattern), so every existing
`.qplog`, preference blob, and archive record still opens; `schemaVersion`
stays 1 (old builds ignore unknown keys, as with `exchangeName`).

Decisions inside that sentence:

- **Reception is use.** Rule 5A prohibits *access* to spotting information;
  a spot delivered into the band map is access. TCP connect with zero spots
  received records nothing — no information arrived — and the connect
  control gets its own inline caution instead (below).
- **Recorded unconditionally**, even while the profile says `ASSISTED`. The
  fact and the claim are independent; flip the profile to `NON-ASSISTED`
  after a week of cluster use and the warning still knows. Flipping to
  `ASSISTED` is the legitimate resolution and clears the warning without
  erasing the fact.
- **No undo registration.** ⌘Z must not silently clear an integrity record,
  and the direct-mutation precedent already exists
  (`document.log.operatingMode`, MainView's Run/S&P binding). Same
  dirty-tracking class as that shipped feature.
- **Self-spotting (⇧⌘S) does not set the flag.** Sending a spot receives no
  spotting information, and self-spotting legality genuinely varies by
  sponsor (NAQP 5A forbids it; many state QSO parties invite it). A
  party-neutral trigger can only be reception. Recorded here as a known
  limitation, not an oversight.

### 2. The judgment: `ContestLog.spotsContradictNonAssistedClaim`

`usedSpots && station.categoryAssisted == .nonAssisted`, computed on the
Core model where both facts live. Everything visible hangs off this one
predicate.

### 3. The surfaces — inline, non-blocking, keyboard-dismissable

One decision type, `AssistedSpotWarning` (Sources/UI, view-free — the
`PartyNotice` / `KeyMonitorGate` pattern), owns every string and every
show/hide rule so they are assertable. The views do nothing but read it.

- **Station strip badge** (the always-visible strip that already hosts the
  COUNTY LINE badge): an orange capsule — `SPOTS USED — ENTRY SAYS
  NON-ASSISTED` — with tooltip detail and a dismiss button. Dismissal is
  ⌘. (the macOS cancel key; free per `KeyMonitorGate` and the README key
  table) or a click. Session-scoped `@State`, deliberately not persisted: a
  claim that is still wrong earns one nag per sitting.
- **Re-armed where the claim ships.** Cabrillo export (⇧⌘E) clears the
  dismissal when the conflict holds — the export itself proceeds untouched
  (non-blocking, nothing rewritten), but the operator cannot produce the
  file without the warning standing back up. ADIF (⌘E) carries no
  `CATEGORY-ASSISTED` claim and does not re-arm. A conflict that *returns*
  (profile flipped away and back) also re-arms, via one pure
  `rearm(dismissed:conflict:)` rule shared by both events.
- **Cluster popover caution**: while the profile says `NON-ASSISTED`, the
  connect UI carries an orange caption — status by the control that creates
  the condition, before the first spot arrives. No dismissal; it lives in a
  popover.
- **Setup sheet caution**: under the Assisted picker, when the log has
  already used spots and the selection is `NON-ASSISTED` — status by the
  control that *fixes* the condition. `SetupSheet` already holds the
  `LogDocument`, so this is read-only, no API change.

What deliberately does **not** happen: no modal alert, no blocked or
modified export (the app never rewrites the operator's claim — a log the
sponsor reclassifies is the operator's call to make), no `ScoreEngine`
involvement, no party lookup anywhere in the chain.

## Approaches considered

1. **Warn at connect only** — invisible under auto-connect (the popover is
   never open), silent at export where the claim ships, forgotten on
   restart. Kept only as the secondary popover caution.
2. **Persist the fact on the document; warn live and re-arm at export**
   — chosen, for the reasons above. Restart-proof, which matters because
   crash-and-reopen mid-contest is an explicitly supported workflow.
3. **Session-memory only, export-time only** — no schema change, but a
   mid-contest reopen silently launders ten hours of assisted operating,
   and the operator learns at the end instead of at spot #1.

## Tests (red first)

- **Core** (`ModelTests`): `usedSpots` defaults false on a legacy payload
  built by encoding and deleting the key (the
  `testLogWithoutAStoredModeDerivesItFromLocation` fixture pattern);
  round-trips true; `spotsContradictNonAssistedClaim` truth table (all four
  combinations).
- **App** (`LogDocumentTests`): `noteSpotsUsed()` sets the flag, is
  idempotent, and takes no undo manager by signature.
- **UI** (`AssistedSpotWarningTests`, new): visibility truth table
  (conflict × dismissed); `rearm` truth table (re-arms only under conflict,
  preserves dismissal otherwise); the badge names the claim it contradicts;
  the detail names the fix (Contest Setup) and the key (⌘.); **no string
  names any party** — the party-neutrality guard, asserted rather than
  promised.

## Docs, same commit

README: a Spots/cluster feature bullet for the warning, the ⌘. row in the
keyboard table, updated test count. The keyboard path and the non-blocking
behavior are the two things the bullet must say.

## Compatibility

Additive schema with a tolerated-absent default; no party JSON, no
`ScoreEngine`, no exporter output change for any profile (the export text is
byte-identical — the warning lives entirely beside the flow, never in the
file). Existing per-party suites prove scoring is untouched.
