# Internal Voice Keyer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Play the radio's own recorded voice memories from the F-keys and ESM on phone, with real abort, real end-of-playback, and honest reporting of how many memories the connected radio actually has.

**Architecture:** A new `VoiceMessageCapable` protocol that `ElecraftK3Driver` adopts, alongside a `VoiceKeyerStatus` discovered from the radio at connect. `MessageSets` gains an F-key→memory mapping and per-memory names; `EntryFlow.Outcome` carries a `Transmission` (CW text, a voice memory, or silence) instead of a bare string. `ESM.swift` does not change.

**Tech Stack:** Swift 6, SwiftUI, XCTest, XcodeGen. macOS 15+.

**Spec:** [`docs/superpowers/specs/2026-08-09-internal-voice-keyer-design.md`](../specs/2026-08-09-internal-voice-keyer-design.md)
**Research:** [`docs/research/k3_voice_keyer.md`](../../research/k3_voice_keyer.md)
**Governing law:** Constitution Article 11 as amended 2026-08-09 — voice plays from the radio's memories, never as audio from the Mac.

---

## Conventions used throughout

**New files require a project regeneration before they compile.** `project.yml` globs `Sources`, but the `.xcodeproj` is generated. Any task that creates a file runs `xcodegen generate` first.

**Always pipe xcodebuild through `pipefail`.** A `| tee | grep` pipeline reports the *grep's* exit status, which has masked a failed build as success in this repo before. Every command below uses this form, and you trust the log's own summary lines rather than the shell's exit code alone:

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/SuiteName/testName 2>&1 | tee /tmp/xcb.log | grep -E "Test Case|error:|\*\* TEST"
```

Never `tail` the log — read `/tmp/xcb.log` in full when something is unclear.

**Full suite:**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | tee /tmp/xcb-full.log | grep -E "error:|failed|\*\* TEST|Executed [0-9]+ test"
```

**Prove regression tests red first.** Every test below is run and seen to fail before the implementation is written. A test that has never been observed failing has not been shown to test anything.

---

## File Structure

| File | Responsibility | Task |
| --- | --- | --- |
| **Create** `Sources/Hardware/Keying/VoiceKeyer.swift` | `VoiceKeyerStatus`, `VoiceMessageCapable`. Nothing else — parallel to `CWSender.swift`. | 1 |
| **Modify** `Sources/Core/Models/MessageSets.swift` | F-key→memory mappings, per-memory names, caption composition, additive `Codable`. | 2 |
| **Modify** `Sources/Core/Models/MessagesDraft.swift` | Editor-held value gains the phone mappings and names. | 3 |
| **Modify** `Sources/App/EntryFlow.swift` | `Transmission`, `Outcome` payload, `Context.voiceMemoryCount`, `esmDrivesReturn`, `transmission(at:)`. | 4 |
| **Modify** `Sources/UI/MainView.swift` | Mechanical `Outcome` adaptation (T5); then message keys, repeat CQ, context wiring (T14). | 5, 14 |
| **Modify** `Sources/Hardware/Radio/ElecraftK3Driver.swift` | `parseOM`, `parseIC`, play/stop, bank sequencing, `VoiceMessageCapable` conformance. | 6–10 |
| **Modify** `Sources/App/RadioController.swift` | `voiceStatus`, `isVoicePlaying`, play, unified abort, dropped-play reporting. | 11 |
| **Modify** `Sources/UI/MessagesRow.swift` | Takes prepared `MessageKey`s instead of raw templates. | 12 |
| **Modify** `Sources/UI/MessagesEditor.swift` | CW/Phone picker, memory-name rows, F-key mapping rows, inline status. | 13 |
| **Modify** `Sources/UI/RadioBar.swift`, `Sources/UI/KeyMonitorGate.swift` | `abortCW` → `abortTransmission` rename. | 11 |
| **Modify** `README.md`, `docs/PROVENANCE.md` | Feature bullet, keyboard table, caveats, sources, test count. | 15 |

Tests live beside their subjects: `Tests/Hardware/K3ProtocolTests.swift`, `Tests/Core/MessageSetsVoiceTests.swift` (new), `Tests/Core/MessagesDraftTests.swift`, `Tests/App/EntryFlowTests.swift`, `Tests/App/KeyMonitorGateTests.swift`.

---

# Phase A — Commit 1: protocol and model widening

No radio implements anything in this phase. Every party must score and every radio must key identically at the end of it.

---

### Task 1: `VoiceKeyerStatus` and `VoiceMessageCapable`

**Files:**
- Create: `Sources/Hardware/Keying/VoiceKeyer.swift`
- Test: `Tests/Hardware/VoiceKeyerStatusTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/Hardware/VoiceKeyerStatusTests.swift`:

```swift
import XCTest
@testable import QSOPartyLogger

final class VoiceKeyerStatusTests: XCTestCase {

    func testMemoryCountIsZeroUnlessAvailable() {
        XCTAssertEqual(VoiceKeyerStatus.unsupported.memoryCount, 0)
        XCTAssertEqual(VoiceKeyerStatus.notInstalled.memoryCount, 0)
        XCTAssertEqual(VoiceKeyerStatus.available(count: 8).memoryCount, 8)
        XCTAssertEqual(VoiceKeyerStatus.available(count: 2).memoryCount, 2)
    }

    /// `isReady` is what gates transmission, so a zero-count "available" must
    /// not read as ready — a radio that answers with no memories is not one to
    /// send an F-key to.
    func testIsReadyRequiresAtLeastOneMemory() {
        XCTAssertFalse(VoiceKeyerStatus.unsupported.isReady)
        XCTAssertFalse(VoiceKeyerStatus.notInstalled.isReady)
        XCTAssertFalse(VoiceKeyerStatus.available(count: 0).isReady)
        XCTAssertTrue(VoiceKeyerStatus.available(count: 2).isReady)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
xcodegen generate && set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/VoiceKeyerStatusTests 2>&1 | tee /tmp/xcb.log | grep -E "Test Case|error:|\*\* TEST"
```

Expected: compile failure — `cannot find 'VoiceKeyerStatus' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/Hardware/Keying/VoiceKeyer.swift`:

```swift
import Foundation

/// What the connected radio can do about recorded voice messages.
///
/// Runtime rather than a `RadioDescriptor` flag, because Article 11 requires
/// the count to be discovered from the radio: one descriptor's family answers
/// 8, 2 or 0 depending on the model and on whether an option module is fitted.
enum VoiceKeyerStatus: Equatable, Sendable {
    /// This radio has no voice memories the app can drive.
    case unsupported
    /// It has them, but the hardware that provides them is not fitted.
    case notInstalled
    /// Ready, with memories numbered 1...count.
    case available(count: Int)

    var memoryCount: Int {
        if case .available(let count) = self { max(0, count) } else { 0 }
    }

    /// Whether an F-key may transmit. A zero-count `.available` is not ready:
    /// there is nothing to play.
    var isReady: Bool { memoryCount > 0 }
}

/// A radio that can play its own recorded voice messages.
///
/// A separate protocol rather than more `RadioDriver` members with no-op
/// defaults. Article 11 forbids stubbing out the *CW* keyer members because
/// both keying paths exist on every serial radio and the operator may prefer
/// either. A recorder is different in kind: a radio without one has nothing to
/// stub, and an empty implementation would let it claim a capability by
/// silence. `RadioController` tests for conformance instead.
protocol VoiceMessageCapable: RadioDriver {
    /// Play the radio's own recording in `memory` (1-based). A memory this
    /// radio does not have is ignored, never clamped onto a neighbour.
    func playVoiceMessage(memory: Int)
    /// Stop playback immediately.
    func stopVoiceMessage()
    /// What the radio turned out to be able to do, once asked.
    var onVoiceKeyerStatusChange: (@Sendable (VoiceKeyerStatus) -> Void)? { get set }
    /// True while the radio reports a message actually playing — a real signal,
    /// not an estimate.
    var onVoicePlaybackChange: (@Sendable (Bool) -> Void)? { get set }
    /// A play that could not be carried out safely, and so was not carried out
    /// at all. Carries the memory that was asked for. Nothing was transmitted.
    var onVoiceMessageDropped: (@Sendable (Int) -> Void)? { get set }
    /// The message bank the radio was last *observed* in, on radios that have
    /// banks. Radios without them never fire it, so the UI shows nothing.
    /// Reported because the app leaves the bank where the last play put it,
    /// which changes what the front panel's own buttons address.
    var onVoiceBankChange: (@Sendable (Int) -> Void)? { get set }
}
```

- [ ] **Step 4: Run it and watch it pass**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/VoiceKeyerStatusTests 2>&1 | tee /tmp/xcb.log | grep -E "Test Case|error:|\*\* TEST"
```

Expected: 2 tests pass.

- [ ] **Step 5: Do not commit yet** — Phase A commits once, at Task 5.

---

### Task 2: `MessageSets` phone mappings and memory names

**Files:**
- Modify: `Sources/Core/Models/MessageSets.swift`
- Test: `Tests/Core/MessageSetsVoiceTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `Tests/Core/MessageSetsVoiceTests.swift`:

```swift
import XCTest
@testable import QSOPartyLogger

final class MessageSetsVoiceTests: XCTestCase {

    // MARK: Captions

    func testCaptionLeadsWithTheMemoryNumber() {
        let sets = MessageSets.standard
        XCTAssertEqual(sets.voiceMemoryCaption(1), "M1 CQ")
        XCTAssertEqual(sets.voiceMemoryCaption(4), "M4 AGN?")
    }

    /// An unnamed memory still says which memory it is. The number is the part
    /// the app can vouch for; the name is the operator's own note.
    func testCaptionForAnUnnamedMemoryIsJustTheNumber() {
        XCTAssertEqual(MessageSets.standard.voiceMemoryCaption(6), "M6")
    }

    func testCaptionTrimsAWhitespaceOnlyName() {
        var sets = MessageSets.standard
        sets.voiceMemoryNames[5] = "   "
        XCTAssertEqual(sets.voiceMemoryCaption(6), "M6")
    }

    func testCaptionOutOfRangeIsStillTheNumber() {
        XCTAssertEqual(MessageSets.standard.voiceMemoryCaption(99), "M99")
    }

    /// The property the per-memory indexing exists for: one rename reaches
    /// every F-key pointing at that memory, in both operating styles at once.
    func testRenamingAMemoryChangesEveryKeyThatPointsAtIt() {
        var sets = MessageSets.standard
        sets.voiceMemoryNames[1] = "59 TRAVIS"

        let runMemory = try? XCTUnwrap(sets.voiceMemories(for: .run)[1])
        let spMemory = try? XCTUnwrap(sets.voiceMemories(for: .searchPounce)[1])
        XCTAssertEqual(runMemory, 2)
        XCTAssertEqual(spMemory, 2)
        XCTAssertEqual(sets.voiceMemoryCaption(2), "M2 59 TRAVIS")
    }

    // MARK: Defaults

    /// Defaults stay inside memories 1-4 so the common case never triggers a
    /// bank change on a K3.
    func testDefaultMappingsNeverReachBankTwo() {
        for memory in MessageSets.standard.phoneRun.compactMap({ $0 })
            + MessageSets.standard.phoneSearchPounce.compactMap({ $0 }) {
            XCTAssertLessThanOrEqual(memory, 4, "default mapping reached memory \(memory)")
        }
    }

    func testDefaultRunMapping() {
        XCTAssertEqual(MessageSets.standard.phoneRun, [1, 2, 3, nil, 4, nil, nil, nil])
    }

    /// S&P F1 is the "send my call" step, deliberately unassigned: a callsign
    /// is faster spoken than recorded.
    func testDefaultSearchPounceLeavesF1Unassigned() {
        XCTAssertEqual(MessageSets.standard.phoneSearchPounce, [nil, 2, 3, nil, 4, nil, nil, nil])
    }

    func testVoiceMemoriesSelectsBySet() {
        XCTAssertEqual(MessageSets.standard.voiceMemories(for: .run).first ?? nil, 1)
        XCTAssertNil(MessageSets.standard.voiceMemories(for: .searchPounce).first ?? nil)
    }

    // MARK: Codable

    /// A log written before this shipped carries only `run` and `searchPounce`.
    /// It must decode with those untouched and the phone defaults filled in.
    func testDecodingAPreVoiceLogFillsInPhoneDefaults() throws {
        let json = """
        {"run":["CQ TEST {MYCALL}","X"],"searchPounce":["{MYCALL}"]}
        """
        let sets = try JSONDecoder().decode(MessageSets.self, from: Data(json.utf8))

        XCTAssertEqual(sets.run, ["CQ TEST {MYCALL}", "X"])
        XCTAssertEqual(sets.searchPounce, ["{MYCALL}"])
        XCTAssertEqual(sets.phoneRun, MessageSets.defaultPhoneRun)
        XCTAssertEqual(sets.voiceMemoryNames, MessageSets.defaultVoiceMemoryNames)
    }

    func testPhoneFieldsSurviveARoundTrip() throws {
        var sets = MessageSets.standard
        sets.phoneRun = [7, nil, 3, nil, nil, nil, nil, nil]
        sets.voiceMemoryNames[6] = "QRZ"

        let data = try JSONEncoder().encode(sets)
        let back = try JSONDecoder().decode(MessageSets.self, from: data)

        XCTAssertEqual(back.phoneRun, [7, nil, 3, nil, nil, nil, nil, nil])
        XCTAssertEqual(back.voiceMemoryCaption(7), "M7 QRZ")
        XCTAssertEqual(back.run, sets.run)
    }

    // MARK: Mismatch checks stay off the phone set

    /// `ExchangeMismatch` asks whether a message mentions {SERIAL} or {RST}.
    /// A recording cannot be inspected, so phone content must never trip it —
    /// a warning the operator cannot act on is worse than none.
    func testPhoneContentNeverTripsTheExchangeMismatchCheck() throws {
        let cqp = try XCTUnwrap(PartyCatalog.party(id: "cqp"))
        var sets = MessageSets.defaults(for: cqp)
        sets.phoneRun = [1, 2, 3, nil, 4, nil, nil, nil]
        sets.voiceMemoryNames = Array(repeating: "", count: 8)

        XCTAssertNil(sets.exchangeMismatch(with: cqp))
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/MessageSetsVoiceTests 2>&1 | tee /tmp/xcb.log | grep -E "Test Case|error:|\*\* TEST"
```

Expected: compile failure — `value of type 'MessageSets' has no member 'voiceMemoryCaption'`.

- [ ] **Step 3: Add the stored properties and defaults**

In `Sources/Core/Models/MessageSets.swift`, immediately after `var searchPounce: [String]`:

```swift
    /// F1–F8 → the radio's voice memory number, or nil for an unassigned key.
    ///
    /// Defaulted in the declaration so the memberwise initialiser keeps its
    /// two-argument form: `MessageSets(run:searchPounce:)` is called from
    /// `defaults(for:)`, `.standard` and `MessagesDraft.edited`.
    var phoneRun: [Int?] = MessageSets.defaultPhoneRun
    var phoneSearchPounce: [Int?] = MessageSets.defaultPhoneSearchPounce

    /// What is recorded in each of the radio's voice memories, M1 first.
    ///
    /// The operator's own note: nothing in the protocol reports a memory's
    /// contents. Indexed by memory rather than by F-key, so eight recordings
    /// have eight names — naming per key would give Run F2 and S&P F2 separate
    /// names for the same audio, free to disagree.
    var voiceMemoryNames: [String] = MessageSets.defaultVoiceMemoryNames
```

Then, after `static let standard = …`:

```swift
    /// Phone defaults stay inside memories 1–4, so the default mapping never
    /// triggers a bank change on a radio whose memories are banked. Memories
    /// 5–8 exist for an operator who wants them, not to be spent by a default.
    static let defaultPhoneRun: [Int?] = [1, 2, 3, nil, 4, nil, nil, nil]

    /// S&P F1 — "send my call" — is deliberately unassigned: a callsign is
    /// faster spoken than recorded, and Return with nothing mapped advances and
    /// logs without transmitting, exactly as an empty CW slot does.
    static let defaultPhoneSearchPounce: [Int?] = [nil, 2, 3, nil, 4, nil, nil, nil]

    static let defaultVoiceMemoryNames = ["CQ", "Exch", "TU", "AGN?", "", "", "", ""]

    /// The number of voice memories the app will ever offer. The *radio's* count
    /// is discovered at connect and is usually smaller; this is only how many
    /// rows the editor draws.
    static let voiceMemorySlots = 8
```

- [ ] **Step 4: Add the accessors**

Alongside `messages(for:)` at the bottom of the struct:

```swift
    func voiceMemories(for mode: OperatingMode) -> [Int?] {
        switch mode {
        case .run: phoneRun
        case .searchPounce: phoneSearchPounce
        }
    }

    /// "M4 AGN?", or a bare "M6" when that memory has no name.
    ///
    /// The number always leads. A name can go stale when a recording is
    /// replaced from the front panel, and nothing in the protocol reports what
    /// a memory holds — so the caption degrades to a still-true "M6" rather
    /// than to a claim the app cannot check.
    func voiceMemoryCaption(_ memory: Int) -> String {
        let name = voiceMemoryNames.indices.contains(memory - 1)
            ? voiceMemoryNames[memory - 1].trimmingCharacters(in: .whitespaces)
            : ""
        return name.isEmpty ? "M\(memory)" : "M\(memory) \(name)"
    }
```

- [ ] **Step 5: Add additive decoding**

Add at the very end of `MessageSets.swift`, *outside* the struct — an extension, so the memberwise initialiser survives:

```swift
/// Additive decoding, Article 4. The phone fields arrived on 2026-08-09; a log
/// written before that carries neither, and must decode with its CW macros
/// untouched and the phone defaults filled in.
///
/// `init(from:)` lives in an extension on purpose: an initialiser declared in
/// the struct body would suppress the memberwise `MessageSets(run:searchPounce:)`
/// that `defaults(for:)` and `.standard` are built from. `encode(to:)` stays
/// synthesised from `CodingKeys`.
extension MessageSets {
    enum CodingKeys: String, CodingKey {
        case run, searchPounce, phoneRun, phoneSearchPounce, voiceMemoryNames
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            run: try c.decode([String].self, forKey: .run),
            searchPounce: try c.decode([String].self, forKey: .searchPounce)
        )
        phoneRun = try c.decodeIfPresent([Int?].self, forKey: .phoneRun)
            ?? Self.defaultPhoneRun
        phoneSearchPounce = try c.decodeIfPresent([Int?].self, forKey: .phoneSearchPounce)
            ?? Self.defaultPhoneSearchPounce
        voiceMemoryNames = try c.decodeIfPresent([String].self, forKey: .voiceMemoryNames)
            ?? Self.defaultVoiceMemoryNames
    }
}
```

- [ ] **Step 6: Run the new tests and watch them pass**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/MessageSetsVoiceTests 2>&1 | tee /tmp/xcb.log | grep -E "Test Case|error:|\*\* TEST"
```

Expected: 12 tests pass.

- [ ] **Step 7: Run the existing message suites — nothing may have moved**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/MessageDefaultsTests -only-testing:QSOPartyLoggerTests/MessagesDraftTests 2>&1 | tee /tmp/xcb.log | grep -E "Test Case|error:|\*\* TEST"
```

Expected: all pass unchanged.

---

### Task 3: `MessagesDraft` carries the phone edits

**Files:**
- Modify: `Sources/Core/Models/MessagesDraft.swift`
- Test: `Tests/Core/MessagesDraftTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `Tests/Core/MessagesDraftTests.swift`, inside the existing test class:

```swift
    func testDraftRoundTripsPhoneMappings() {
        var draft = MessagesDraft(.standard)
        draft[voice: .run, 3] = 6
        XCTAssertEqual(draft[voice: .run, 3], 6)
        XCTAssertEqual(draft.edited.phoneRun[3], 6)
        // The other set is untouched — Run and S&P map independently.
        XCTAssertNil(draft.edited.phoneSearchPounce[3])
    }

    func testDraftRoundTripsMemoryNames() {
        var draft = MessagesDraft(.standard)
        draft.setVoiceMemoryName("59 BELL", at: 1)
        XCTAssertEqual(draft.edited.voiceMemoryCaption(2), "M2 59 BELL")
    }

    func testDraftIgnoresOutOfRangeWrites() {
        var draft = MessagesDraft(.standard)
        draft[voice: .run, 99] = 3
        draft.setVoiceMemoryName("nope", at: 99)
        XCTAssertEqual(draft.edited.phoneRun, MessageSets.defaultPhoneRun)
        XCTAssertEqual(draft.edited.voiceMemoryNames, MessageSets.defaultVoiceMemoryNames)
    }

    /// Restore Defaults is whole-set on purpose — a half-restored set is a set
    /// that disagrees with itself — and the phone side restores from constants,
    /// since a party's exchange shape cannot change what is on a recording.
    func testRestoreDefaultsAlsoRestoresThePhoneSide() {
        var draft = MessagesDraft(.standard)
        draft[voice: .run, 0] = 8
        draft.setVoiceMemoryName("stale", at: 0)

        draft.restoreDefaults(for: nil)

        XCTAssertEqual(draft.edited.phoneRun, MessageSets.defaultPhoneRun)
        XCTAssertEqual(draft.edited.voiceMemoryNames, MessageSets.defaultVoiceMemoryNames)
    }
```

- [ ] **Step 2: Run it and watch it fail**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/MessagesDraftTests 2>&1 | tee /tmp/xcb.log | grep -E "Test Case|error:|\*\* TEST"
```

Expected: compile failure — no subscript `[voice:_:]`.

- [ ] **Step 3: Write the implementation**

In `Sources/Core/Models/MessagesDraft.swift`, add after `private(set) var searchPounce: [String]`:

```swift
    private(set) var phoneRun: [Int?]
    private(set) var phoneSearchPounce: [Int?]
    private(set) var voiceMemoryNames: [String]
```

Extend `init` to:

```swift
    init(_ sets: MessageSets = .standard) {
        run = Self.padded(sets.run)
        searchPounce = Self.padded(sets.searchPounce)
        phoneRun = Self.paddedMemories(sets.phoneRun)
        phoneSearchPounce = Self.paddedMemories(sets.phoneSearchPounce)
        voiceMemoryNames = Self.paddedNames(sets.voiceMemoryNames)
    }
```

Extend `edited` to:

```swift
    var edited: MessageSets {
        var sets = MessageSets(run: normalized(run), searchPounce: normalized(searchPounce))
        sets.phoneRun = phoneRun
        sets.phoneSearchPounce = phoneSearchPounce
        sets.voiceMemoryNames = voiceMemoryNames.map { $0.trimmingCharacters(in: .whitespaces) }
        return sets
    }
```

Add the accessors after the existing `subscript`:

```swift
    /// Which memory F<index+1> fires in `mode`, or nil when the key is
    /// unassigned. Labelled `voice:` to sit beside the CW subscript rather
    /// than overload it — the two return different things.
    subscript(voice mode: OperatingMode, index: Int) -> Int? {
        get {
            let set = mode == .run ? phoneRun : phoneSearchPounce
            return set.indices.contains(index) ? set[index] : nil
        }
        set {
            guard (0..<Self.slotCount).contains(index) else { return }
            if mode == .run {
                phoneRun[index] = newValue
            } else {
                phoneSearchPounce[index] = newValue
            }
        }
    }

    /// `memoryIndex` is 0-based: memory M1 is index 0.
    mutating func setVoiceMemoryName(_ name: String, at memoryIndex: Int) {
        guard (0..<MessageSets.voiceMemorySlots).contains(memoryIndex) else { return }
        voiceMemoryNames[memoryIndex] = name
    }

    /// "M4 AGN?" from the names being edited right now. Delegates so the
    /// composition lives in one place — and so the editor's pickers do not
    /// rebuild the whole `edited` value once per row per memory.
    func voiceMemoryCaption(_ memory: Int) -> String {
        var sets = MessageSets.standard
        sets.voiceMemoryNames = voiceMemoryNames
        return sets.voiceMemoryCaption(memory)
    }
```

Extend `restoreDefaults(for:)` — keep the existing two lines and add:

```swift
        phoneRun = Self.paddedMemories(MessageSets.defaultPhoneRun)
        phoneSearchPounce = Self.paddedMemories(MessageSets.defaultPhoneSearchPounce)
        voiceMemoryNames = Self.paddedNames(MessageSets.defaultVoiceMemoryNames)
```

Add the padding helpers beside `padded`:

```swift
    private static func paddedMemories(_ set: [Int?]) -> [Int?] {
        var out = Array(set.prefix(slotCount))
        while out.count < slotCount { out.append(nil) }
        return out
    }

    private static func paddedNames(_ names: [String]) -> [String] {
        var out = Array(names.prefix(MessageSets.voiceMemorySlots))
        while out.count < MessageSets.voiceMemorySlots { out.append("") }
        return out
    }
```

- [ ] **Step 4: Run it and watch it pass**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/MessagesDraftTests 2>&1 | tee /tmp/xcb.log | grep -E "Test Case|error:|\*\* TEST"
```

Expected: all tests pass, including the four new ones.

---

### Task 4: `Transmission` and the `Outcome` payload

**Files:**
- Modify: `Sources/App/EntryFlow.swift`
- Test: `Tests/App/EntryFlowTests.swift`

- [ ] **Step 1: Write the failing test**

Append inside the existing class in `Tests/App/EntryFlowTests.swift`:

```swift
    // MARK: Voice

    private func phoneContext(memories: Int, cursor: ESM.Cursor = .call) -> EntryFlow.Context {
        var keying = KeyingSettings()
        keying.esmEnabled = true
        return EntryFlow.Context(
            modeClass: .phone,
            rawMode: "SSB",
            radioConnected: true,
            cursor: cursor,
            keying: keying,
            voiceMemoryCount: memories
        )
    }

    /// A radio with no memories leaves Return a plain log key, exactly as a
    /// disconnected radio does.
    func testESMDoesNotDriveReturnOnPhoneWithoutMemories() {
        let flow = EntryFlow(document: LogDocument())
        XCTAssertFalse(flow.esmDrivesReturn(phoneContext(memories: 0)))
    }

    func testESMDrivesReturnOnPhoneWithMemories() {
        let flow = EntryFlow(document: LogDocument())
        XCTAssertTrue(flow.esmDrivesReturn(phoneContext(memories: 8)))
    }

    /// Digital never drives ESM in either mode class.
    func testESMNeverDrivesReturnOnDigital() {
        var keying = KeyingSettings()
        keying.esmEnabled = true
        let context = EntryFlow.Context(
            modeClass: .digital, rawMode: "RTTY", radioConnected: true,
            cursor: .call, keying: keying, voiceMemoryCount: 8
        )
        XCTAssertFalse(EntryFlow(document: LogDocument()).esmDrivesReturn(context))
    }

    /// The same F-key indexes as CW — ESM.swift is untouched by this feature.
    func testPhoneTransmissionUsesTheMappedMemoryAndItsCaption() {
        let flow = EntryFlow(document: LogDocument())
        // Run default: F1 → M1, named "CQ".
        XCTAssertEqual(
            flow.transmission(at: 0, context: phoneContext(memories: 8)),
            .voice(memory: 1, caption: "M1 CQ")
        )
    }

    func testUnassignedPhoneKeyIsSilent() {
        let flow = EntryFlow(document: LogDocument())
        // Run default: F4 is unassigned.
        XCTAssertEqual(flow.transmission(at: 3, context: phoneContext(memories: 8)), .silent)
    }

    /// A mapping built for an 8-memory radio must not fire memory 5 at a radio
    /// that has two. Silence, not a clamp onto a neighbouring recording.
    func testPhoneKeyBeyondTheRadiosMemoryCountIsSilent() {
        let document = LogDocument()
        var sets = document.log.messages
        sets.phoneRun = [5, nil, nil, nil, nil, nil, nil, nil]
        document.updateMessages(sets, undoManager: nil)

        let flow = EntryFlow(document: document)
        XCTAssertEqual(flow.transmission(at: 0, context: phoneContext(memories: 2)), .silent)
        XCTAssertEqual(
            flow.transmission(at: 0, context: phoneContext(memories: 8)),
            .voice(memory: 5, caption: "M5")
        )
    }

    func testCWTransmissionStillCarriesExpandedText() {
        let document = LogDocument()
        let flow = EntryFlow(document: document)
        flow.entry.call = "W6ABC"
        var keying = KeyingSettings()
        keying.esmEnabled = true
        let context = EntryFlow.Context(
            modeClass: .cw, rawMode: "CW", radioConnected: true,
            cursor: .call, keying: keying
        )
        guard case .cw(let text) = flow.transmission(at: 0, context: context) else {
            return XCTFail("expected CW")
        }
        XCTAssertFalse(text.isEmpty)
    }
```

- [ ] **Step 2: Run it and watch it fail**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/EntryFlowTests 2>&1 | tee /tmp/xcb.log | grep -E "Test Case|error:|\*\* TEST"
```

Expected: compile failure — `Context` has no `voiceMemoryCount`.

- [ ] **Step 3: Add `Transmission` and widen `Context`**

In `Sources/App/EntryFlow.swift`, add inside the class, just above `enum Outcome`:

```swift
    /// What a message slot puts on the air.
    ///
    /// CW carries expanded text; a voice message carries a memory number,
    /// because a recording has no text and no macro can reach inside one. The
    /// caption rides along so the TX badge and the messages row cannot word the
    /// same memory two different ways.
    enum Transmission: Equatable {
        case cw(String)
        case voice(memory: Int, caption: String)
        /// An empty CW slot, an unassigned phone key, or one pointing at a
        /// memory this radio does not have.
        case silent
    }
```

In `struct Context`, add the stored property after `var keying: KeyingSettings`:

```swift
        /// How many voice memories the connected radio actually has, 0 for none.
        /// A count rather than a Bool so `transmission(at:)` can tell an
        /// unassigned key from one pointing past the end of this radio's
        /// memories — the second is a mapping built for a different radio, and
        /// must not fire a neighbouring recording.
        var voiceMemoryCount: Int
```

and to the initialiser's parameter list, after `keying:`:

```swift
            voiceMemoryCount: Int = 0
```

with `self.voiceMemoryCount = voiceMemoryCount` in the body. The default keeps every existing `Context(...)` literal in the test suite compiling unchanged.

- [ ] **Step 4: Change `Outcome` and add `transmission(at:)`**

Replace the two payload cases in `enum Outcome`:

```swift
        /// Nothing was logged; `transmission` goes on the air.
        case send(index: Int, transmission: Transmission)
        /// `rows` were appended and `transmission` goes out after them —
        /// resolved *before* the append, which is the whole point.
        case logged(rows: [QSO], transmission: Transmission)
```

Add beside `expandedMessage(at:context:)`:

```swift
    /// What F<index+1> would put on the air right now. `expandedMessage` stays
    /// for the CW preview and its existing tests; this is what actually keys.
    func transmission(at index: Int, context: Context) -> Transmission {
        if context.modeClass == .phone {
            guard context.voiceMemoryCount > 0 else { return .silent }
            let memories = document.log.messages.voiceMemories(for: document.log.operatingMode)
            guard memories.indices.contains(index), let memory = memories[index],
                  (1...context.voiceMemoryCount).contains(memory) else { return .silent }
            return .voice(memory: memory,
                          caption: document.log.messages.voiceMemoryCaption(memory))
        }
        let text = expandedMessage(at: index, context: context)
        return text.isEmpty ? .silent : .cw(text)
    }
```

Widen `esmDrivesReturn`:

```swift
    /// ESM drives Return on CW, and on phone once the radio has voice memories
    /// to play — otherwise Return is a plain log key.
    func esmDrivesReturn(_ context: Context) -> Bool {
        guard context.keying.esmEnabled, context.radioConnected else { return false }
        switch context.modeClass {
        case .cw: return true
        case .phone: return context.voiceMemoryCount > 0
        case .digital: return false
        }
    }
```

- [ ] **Step 5: Update the two `returnPressed` arms**

In `returnPressed`, replace the `.sendMessage` arm:

```swift
        case .sendMessage(let index):
            // The cursor is never moved for you. Wherever it is, that is where
            // it stays, so a Return that called once calls again — Space is
            // what advances, when the operator decides the contact has.
            let outgoing = transmission(at: index, context: context)
            return outgoing == .silent ? .nothing : .send(index: index, transmission: outgoing)
```

and the `.logAndSend` arm:

```swift
        case .logAndSend(let index):
            // Resolve before logging: logging advances the entry to the next
            // QSO number, so resolving afterwards would key a number one higher
            // than the one just written to the log — and the other station
            // would log that, putting both of us NIL.
            //
            // This ordering is the 2026-07-25 bug. It is why the resolution
            // happens here rather than in the caller.
            let pending = transmission(at: index, context: context)
            switch logContact(context, undoManager: undoManager) {
            case .logged(let rows, _):
                return .logged(rows: rows, transmission: pending)
            case let other:
                // Nothing was logged — a missing location or an invalid
                // exchange. Do not key a report for a contact that did not
                // happen.
                return other
            }
```

- [ ] **Step 6: Fix `logContact`'s own `.logged` construction**

Find every `return .logged(rows:` inside `EntryFlow` and change the `text: ""` argument to `transmission: .silent`.

```bash
grep -n "\.logged(rows:" Sources/App/EntryFlow.swift
```

- [ ] **Step 7: Run and watch it pass**

`MainView` will not compile yet — that is Task 5. Run only the model-level suite:

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/EntryFlowTests 2>&1 | tee /tmp/xcb.log | grep -E "Test Case|error:|\*\* TEST"
```

If it fails only inside `MainView.swift`, proceed to Task 5 and re-run there.

---

### Task 5: Adapt `MainView` to the new `Outcome`, and commit Phase A

**Files:**
- Modify: `Sources/UI/MainView.swift:953-992`

- [ ] **Step 1: Replace `apply` and `keyed`**

```swift
    private func apply(_ outcome: EntryFlow.Outcome) {
        switch outcome {
        case .qsy(let command):
            execute(command)
        case .send(let index, let transmission):
            keyed(transmission, fromMessageAt: index)
        case .logged(let rows, let transmission):
            addWorkedStationsToBandMap(rows)
            focusedField = .call
            transmit(transmission)
        case .needsSetup:
            showSetup = true
        case .nothing:
            break
        }
    }

    private func keyed(_ transmission: EntryFlow.Transmission, fromMessageAt index: Int) {
        // F1 in Run mode is the CQ — remember where we're running from.
        if operatingMode.wrappedValue == .run, index == 0 {
            captureCQFrequency()
        }
        transmit(transmission)
    }

    /// The one place a resolved transmission reaches the radio. Nothing here
    /// may re-resolve a message — resolution order is exactly what the flow
    /// exists to pin down.
    private func transmit(_ transmission: EntryFlow.Transmission) {
        switch transmission {
        case .cw(let text):
            radio.sendCW(text, settings: settings)
        case .voice(let memory, let caption):
            radio.playVoiceMessage(memory: memory, caption: caption)
        case .silent:
            break
        }
    }
```

- [ ] **Step 2: Replace `sendMessageAt`**

```swift
    private func sendMessageAt(_ index: Int) {
        let transmission = flow.transmission(at: index, context: operatingContext)
        guard transmission != .silent else { return }
        keyed(transmission, fromMessageAt: index)
    }
```

- [ ] **Step 3: Add the temporary `playVoiceMessage` shim**

`RadioController` gains the real one in Task 11. To keep Phase A self-contained and buildable, add to `Sources/App/RadioController.swift`:

```swift
    /// Play one of the radio's recorded voice memories. Wired to a driver in
    /// the commit that adds the K3's voice keyer; inert until then.
    func playVoiceMessage(memory: Int, caption: String) {}
```

- [ ] **Step 4: Build and run the full suite**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | tee /tmp/xcb-full.log | grep -E "error:|failed|\*\* TEST|Executed [0-9]+ test"
```

Expected: `** TEST SUCCEEDED **`. Record the executed-test count — the README needs it in Task 15.

- [ ] **Step 5: Verify Article 10 is still clean**

```bash
grep -rniE "k3|kx3|kx2|flex|icom|yaesu|kenwood|elecraft|ci-v" Sources/App Sources/UI | grep -vE ':[0-9]+: *(//|\*)' | grep -vE ':[0-9]+: *case [A-Za-z]+ = "'
```

Expected: no output.

- [ ] **Step 6: Commit Phase A**

```bash
git add Sources/Hardware/Keying/VoiceKeyer.swift Sources/Core/Models/MessageSets.swift Sources/Core/Models/MessagesDraft.swift Sources/App/EntryFlow.swift Sources/App/RadioController.swift Sources/UI/MainView.swift Tests/ QSOPartyLogger.xcodeproj
git commit -m "$(cat <<'EOF'
keying: widen the message model to carry a voice memory, not just text

Structural only, per Article 4 -- no radio implements anything and no party
scores differently. Outcome carried a bare String with "" meaning silence;
it now carries a Transmission of CW text, a voice memory, or silence.

MessageSets gains the F-key to memory mapping and one name per memory,
decoded additively so every existing log keeps its CW macros untouched.
Context carries the radio's memory count rather than a Bool, so a mapping
built for an eight-memory radio stays silent on a two-memory one instead of
firing a neighbouring recording.

ESM.swift is unchanged: phone returns the same F-key indexes CW does.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

# Phase B — Commit 2: the radio, the controller, the UI, the docs

---

### Task 6: `parseOM` — model and memory count

**Files:**
- Modify: `Sources/Hardware/Radio/ElecraftK3Driver.swift`
- Test: `Tests/Hardware/K3ProtocolTests.swift`

- [ ] **Step 1: Write the failing test**

Append inside `K3ProtocolTests`:

```swift
    // MARK: OM — model and voice memory count

    /// Programmer's Reference G5, OM entry: "OM APXSDFfLVR--;" with a missing
    /// module's letter replaced by a dash. D at index 4 is the KDVR3.
    func testParseOMK3WithRecorderHasEightMemories() throws {
        let result = try XCTUnwrap(ElecraftK3Driver.parseOM("OM APXSDFfLVR--;"))
        XCTAssertEqual(result.model, .k3)
        XCTAssertEqual(result.voice, .available(count: 8))
    }

    func testParseOMK3WithoutRecorderIsNotInstalled() throws {
        let result = try XCTUnwrap(ElecraftK3Driver.parseOM("OM -P-S--------;"))
        XCTAssertEqual(result.model, .k3)
        XCTAssertEqual(result.voice, .notInstalled)
    }

    /// The reference prints the K3 example with a space after OM. Tolerate both.
    func testParseOMWithoutTheSpace() throws {
        let result = try XCTUnwrap(ElecraftK3Driver.parseOM("OMAPXSDFfLVR--;"))
        XCTAssertEqual(result.voice, .available(count: 8))
    }

    /// KX3 and KX2 have the recorder built in — two memories, nothing to detect.
    /// The trailing 0n is the product identifier: 1 = KX2, 2 = KX3.
    func testParseOMKX2() throws {
        let result = try XCTUnwrap(ElecraftK3Driver.parseOM("OM A-F-------01;"))
        XCTAssertEqual(result.model, .kx2)
        XCTAssertEqual(result.voice, .available(count: 2))
    }

    func testParseOMKX3() throws {
        let result = try XCTUnwrap(ElecraftK3Driver.parseOM("OM A-F-------02;"))
        XCTAssertEqual(result.model, .kx3)
        XCTAssertEqual(result.voice, .available(count: 2))
    }

    /// Radios do send partial lines. A driver that traps on one takes the app
    /// down mid-contest (Article 13).
    func testParseOMRejectsTruncatedAndForeignResponses() {
        XCTAssertNil(ElecraftK3Driver.parseOM("OM APX;"))
        XCTAssertNil(ElecraftK3Driver.parseOM("OM;"))
        XCTAssertNil(ElecraftK3Driver.parseOM(""))
        XCTAssertNil(ElecraftK3Driver.parseOM("IF00014042000;"))
    }
```

- [ ] **Step 2: Run it and watch it fail**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/K3ProtocolTests 2>&1 | tee /tmp/xcb.log | grep -E "Test Case|error:|\*\* TEST"
```

Expected: compile failure — no `parseOM`.

- [ ] **Step 3: Write the implementation**

In `ElecraftK3Driver.swift`, add above the class:

```swift
/// Which radio in the family answered. The one place a per-model difference
/// lives, because both the memory count and the play sequence depend on it.
enum ElecraftModel: Equatable, Sendable {
    case k3
    case kx3
    case kx2
}
```

and inside the class, in the parsing section:

```swift
    /// `OM` — installed option modules, and on the KX models a product
    /// identifier. Both variants carry a 12-character field; the reference
    /// prints the K3 example with a space after `OM`, so one is tolerated.
    ///
    /// K3/K3S: `APXSDFfLVR--`, index 4 = `D` when the KDVR3 recorder is fitted.
    /// KX3/KX2: `APF---TBXI0n`, where `0n` is `01` for a KX2 and `02` for a KX3
    /// — neither has a `D` position, because the recorder is built in.
    static func parseOM(_ response: String) -> (model: ElecraftModel, voice: VoiceKeyerStatus)? {
        guard response.hasPrefix("OM") else { return nil }
        var body = response.dropFirst(2)
        if body.hasSuffix(";") { body = body.dropLast() }
        let field = Array(body.trimmingCharacters(in: .whitespaces))
        guard field.count >= 12 else { return nil }

        if field[10] == "0", field[11] == "1" { return (.kx2, .available(count: 2)) }
        if field[10] == "0", field[11] == "2" { return (.kx3, .available(count: 2)) }
        return (.k3, field[4] == "D" ? .available(count: 8) : .notInstalled)
    }
```

- [ ] **Step 4: Run it and watch it pass**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/K3ProtocolTests 2>&1 | tee /tmp/xcb.log | grep -E "Test Case|error:|\*\* TEST"
```

Expected: 6 new tests pass.

---

### Task 7: `parseIC` — playback state and current bank

**Files:**
- Modify: `Sources/Hardware/Radio/ElecraftK3Driver.swift`
- Test: `Tests/Hardware/K3ProtocolTests.swift`

- [ ] **Step 1: Write the failing test**

Append inside `K3ProtocolTests`:

```swift
    // MARK: IC — playback and bank

    /// `ICabcde;` — five 8-bit characters. B7 of every byte is always 1, so no
    /// control character is sent; B2 of byte a is "MSG is playing" and B3 is
    /// the message bank. Programmer's Reference G5, Table 4.
    func icResponse(playing: Bool, bank: Int) -> String {
        var a: UInt8 = 0x80
        if playing { a |= 0x04 }
        if bank == 2 { a |= 0x08 }
        let rest = String(repeating: "\u{80}", count: 4)
        return "IC" + String(UnicodeScalar(a)) + rest + ";"
    }

    func testParseICReadsPlaybackState() throws {
        let playing = try XCTUnwrap(ElecraftK3Driver.parseIC(icResponse(playing: true, bank: 1)))
        XCTAssertTrue(playing.playing)
        let idle = try XCTUnwrap(ElecraftK3Driver.parseIC(icResponse(playing: false, bank: 1)))
        XCTAssertFalse(idle.playing)
    }

    func testParseICReadsBank() throws {
        let one = try XCTUnwrap(ElecraftK3Driver.parseIC(icResponse(playing: false, bank: 1)))
        XCTAssertEqual(one.bank, 1)
        let two = try XCTUnwrap(ElecraftK3Driver.parseIC(icResponse(playing: false, bank: 2)))
        XCTAssertEqual(two.bank, 2)
    }

    /// The always-set B7 must not leak into either answer, and the two bits
    /// must not be read as one.
    func testParseICSeparatesTheTwoBits() throws {
        let both = try XCTUnwrap(ElecraftK3Driver.parseIC(icResponse(playing: true, bank: 2)))
        XCTAssertTrue(both.playing)
        XCTAssertEqual(both.bank, 2)
    }

    func testParseICRejectsShortAndForeignResponses() {
        XCTAssertNil(ElecraftK3Driver.parseIC("IC;"))
        XCTAssertNil(ElecraftK3Driver.parseIC("IC\u{80}\u{80};"))
        XCTAssertNil(ElecraftK3Driver.parseIC("KS020;"))
    }
```

- [ ] **Step 2: Run it and watch it fail**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/K3ProtocolTests 2>&1 | tee /tmp/xcb.log | grep -E "Test Case|error:|\*\* TEST"
```

Expected: compile failure — no `parseIC`.

- [ ] **Step 3: Write the implementation**

```swift
    /// `ICabcde;` — five 8-bit flag bytes. Byte a bit B2 is "MSG is playing"
    /// and bit B3 is the message bank (0 = bank 1). B7 is always 1 so that no
    /// control character reaches the host, which is why this reads unicode
    /// scalar values rather than `asciiValue`: the transport decodes ISO
    /// Latin-1, so every byte becomes exactly one scalar in 0x00...0xFF.
    static func parseIC(_ response: String) -> (playing: Bool, bank: Int)? {
        let scalars = Array(response.unicodeScalars)
        guard scalars.count >= 8, scalars[0] == "I", scalars[1] == "C" else { return nil }
        let a = scalars[2].value
        return (playing: (a >> 2) & 1 == 1, bank: (a >> 3) & 1 == 1 ? 2 : 1)
    }
```

- [ ] **Step 4: Run it and watch it pass**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/K3ProtocolTests 2>&1 | tee /tmp/xcb.log | grep -E "Test Case|error:|\*\* TEST"
```

Expected: 4 new tests pass.

---

### Task 8: The play and stop commands

**Files:**
- Modify: `Sources/Hardware/Radio/ElecraftK3Driver.swift`
- Test: `Tests/Hardware/K3ProtocolTests.swift`

- [ ] **Step 1: Write the failing test**

Append inside `K3ProtocolTests`:

```swift
    // MARK: Voice memory commands

    /// Table 7 — M1-M4 TAP. In a voice mode these play the recorder's
    /// messages; in CW the same switches play CW text memories.
    func testK3MemoryTapCommands() {
        XCTAssertEqual(ElecraftK3Driver.cmdPlayK3Memory[1], "SWT21;")
        XCTAssertEqual(ElecraftK3Driver.cmdPlayK3Memory[2], "SWT31;")
        XCTAssertEqual(ElecraftK3Driver.cmdPlayK3Memory[3], "SWT35;")
        XCTAssertEqual(ElecraftK3Driver.cmdPlayK3Memory[4], "SWT39;")
    }

    /// Tables 8 and 8A — tap MSG (11), then the digit. Codes 19 and 27 are
    /// digits 1 and 2 on both the KX3 and the KX2.
    func testKXMemorySequences() {
        XCTAssertEqual(ElecraftK3Driver.cmdPlayKXMemory[1], ["SWT11;", "SWT19;"])
        XCTAssertEqual(ElecraftK3Driver.cmdPlayKXMemory[2], ["SWT11;", "SWT27;"])
    }

    /// "Terminates transmit in all modes, including message play and repeating
    /// messages" — Programmer's Reference G5, RX entry.
    func testStopVoiceMessageCommand() {
        XCTAssertEqual(ElecraftK3Driver.cmdStopVoiceMessage, "RX;")
    }

    func testBankSelectCommand() {
        XCTAssertEqual(ElecraftK3Driver.cmdSelectBank, "SWH37;")
    }

    // MARK: Playing, end to end over the transport

    /// Bring a driver up as the given model, clear the start-up writes, and
    /// stop it when the test ends so its poll timer does not outlive the case.
    func startedRadio(om: String, bank: Int = 1) -> (ElecraftK3Driver, MockSerialTransport) {
        let driver = ElecraftK3Driver()
        let transport = MockSerialTransport()
        driver.start(transport: transport)
        addTeardownBlock { driver.stop() }
        transport.inject(om)
        transport.injectBytes(icBytes(playing: false, bank: bank))
        transport.clearWritten()
        return (driver, transport)
    }

    /// A K3 with the KDVR3 fitted, with `bank` already confirmed.
    func startedK3(bank: Int = 1) -> (ElecraftK3Driver, MockSerialTransport) {
        startedRadio(om: "OM APXSDFfLVR--;", bank: bank)
    }

    func testPlayingABankOneMemoryTapsImmediately() {
        let (driver, transport) = startedK3()
        driver.playVoiceMessage(memory: 3)
        XCTAssertEqual(transport.writtenExcludingPolls, "SWT35;")
    }

    func testStopSendsRX() {
        let (driver, transport) = startedK3()
        driver.stopVoiceMessage()
        XCTAssertEqual(transport.writtenExcludingPolls, "RX;")
    }

    /// A memory this radio does not have is ignored, never clamped onto a
    /// neighbouring recording.
    func testOutOfRangeMemoriesTransmitNothing() {
        let (driver, transport) = startedK3()
        driver.playVoiceMessage(memory: 0)
        driver.playVoiceMessage(memory: 9)
        driver.playVoiceMessage(memory: -1)
        XCTAssertEqual(transport.writtenExcludingPolls, "")
    }

    func testKX3PlaysWithTheTwoCommandSequence() {
        let (driver, transport) = startedRadio(om: "OM A-F-------02;")

        driver.playVoiceMessage(memory: 2)
        XCTAssertEqual(transport.writtenExcludingPolls, "SWT11;SWT27;")

        transport.clearWritten()
        driver.playVoiceMessage(memory: 3)
        XCTAssertEqual(transport.writtenExcludingPolls, "", "a KX has two memories, not three")
    }

    /// A KX has no banks, so a bank command must never be emitted at one.
    func testKXNeverSelectsABank() {
        let (driver, transport) = startedRadio(om: "OM A-F-------01;")
        driver.playVoiceMessage(memory: 1)
        XCTAssertFalse(transport.writtenExcludingPolls.contains("SWH37;"))
    }

    /// A K3 with no recorder fitted must not emit a tap at all.
    func testNoRecorderMeansNoTap() {
        let (driver, transport) = startedRadio(om: "OM -P-S--------;")
        driver.playVoiceMessage(memory: 1)
        XCTAssertEqual(transport.writtenExcludingPolls, "")
    }
```

- [ ] **Step 2: Add the two test-transport helpers**

`MockSerialTransport.inject` encodes UTF-8, but the driver decodes ISO Latin-1 — so a byte like `0x80` would arrive as two characters and corrupt the `IC` parse. Add to `MockSerialTransport` in `Tests/Hardware/K3ProtocolTests.swift`:

```swift
    /// Inject raw bytes. `inject` encodes UTF-8, which mangles the high-bit
    /// bytes an `IC` response is made of — the driver decodes ISO Latin-1,
    /// where every byte is exactly one character.
    func injectBytes(_ bytes: [UInt8]) {
        onReceive?(Data(bytes))
    }

    func clearWritten() {
        lock.withLock { written.removeAll() }
    }

    /// Writes with the periodic poll filtered out.
    ///
    /// `start` schedules a repeating poll on its own queue, so a test that
    /// asserts *exactly* what a command emitted would race it. Filtering the
    /// poll makes those assertions deterministic instead of merely usually
    /// true, which is the difference between a test and a flake.
    var writtenExcludingPolls: String {
        lock.withLock {
            written.filter { $0 != ElecraftK3Driver.pollCommands }.joined()
        }
    }
```

and add this free helper inside `K3ProtocolTests`:

```swift
    /// The raw bytes of an `IC` response, for `injectBytes`.
    func icBytes(playing: Bool, bank: Int) -> [UInt8] {
        var a: UInt8 = 0x80
        if playing { a |= 0x04 }
        if bank == 2 { a |= 0x08 }
        return Array("IC".utf8) + [a, 0x80, 0x80, 0x80, 0x80] + Array(";".utf8)
    }
```

- [ ] **Step 3: Run it and watch it fail**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/K3ProtocolTests 2>&1 | tee /tmp/xcb.log | grep -E "Test Case|error:|\*\* TEST"
```

Expected: compile failure — no `cmdPlayK3Memory`.

- [ ] **Step 4: Add the command tables and driver state**

In `ElecraftK3Driver`, beside the other command constants:

```swift
    /// K3 M1–M4 tap (Table 7). Memories 5–8 are bank 2's M1–M4.
    static let cmdPlayK3Memory: [Int: String] = [1: "SWT21;", 2: "SWT31;", 3: "SWT35;", 4: "SWT39;"]
    /// KX3/KX2: tap MSG, then tap the digit (Tables 8 and 8A). Codes 19 and 27
    /// are digits 1 and 2 on both models.
    static let cmdPlayKXMemory: [Int: [String]] = [1: ["SWT11;", "SWT19;"], 2: ["SWT11;", "SWT27;"]]
    /// K3 REC hold — selects voice bank 1 or 2. The bank is stored separately
    /// per mode group, so this cannot disturb the operator's CW memory bank.
    static let cmdSelectBank = "SWH37;"
    /// Documented to terminate transmit in all modes, message play included.
    static let cmdStopVoiceMessage = "RX;"
    static let cmdPollOptions = "OM;"
    static let cmdPollIcons = "IC;"
```

and with the other stored properties:

```swift
    var onVoiceKeyerStatusChange: (@Sendable (VoiceKeyerStatus) -> Void)?
    var onVoicePlaybackChange: (@Sendable (Bool) -> Void)?
    var onVoiceMessageDropped: (@Sendable (Int) -> Void)?
    var onVoiceBankChange: (@Sendable (Int) -> Void)?

    private var model: ElecraftModel = .k3
    private var voiceStatus: VoiceKeyerStatus = .unsupported
    private var lastVoicePlaying: Bool?
    /// The bank the radio has actually been *observed* in, not the one we hope
    /// it is in. Nil until an `IC` has been seen.
    private var confirmedBank: Int?
    /// A memory waiting for the bank to confirm before it is tapped.
    private var pendingVoiceMemory: Int?
    /// `IC` responses evaluated since the bank change was requested.
    private var bankConfirmAttempts = 0
```

- [ ] **Step 5: Implement play and stop**

```swift
    func playVoiceMessage(memory: Int) {
        lock.lock()
        let status = voiceStatus
        let model = self.model
        let confirmed = confirmedBank
        lock.unlock()

        guard (1...status.memoryCount).contains(memory) else { return }

        switch model {
        case .kx3, .kx2:
            guard let commands = Self.cmdPlayKXMemory[memory] else { return }
            currentTransport()?.write(commands.joined())

        case .k3:
            let wantedBank = memory <= 4 ? 1 : 2
            guard let tap = Self.cmdPlayK3Memory[memory <= 4 ? memory : memory - 4] else { return }
            if confirmed == wantedBank {
                currentTransport()?.write(tap)
                return
            }
            // The cached bank is up to one poll old, so it is not evidence.
            // Request the change and hold the tap until an IC confirms it —
            // wrong audio on the air is worse than silence (Article 11).
            lock.lock()
            pendingVoiceMemory = memory
            bankConfirmAttempts = 0
            lock.unlock()
            currentTransport()?.write(Self.cmdSelectBank + Self.cmdPollIcons)
        }
    }

    func stopVoiceMessage() {
        lock.lock()
        pendingVoiceMemory = nil
        lock.unlock()
        currentTransport()?.write(Self.cmdStopVoiceMessage)
    }
```

- [ ] **Step 6: Handle `OM` and `IC` in `handle(response:)`**

Add to `handle(response:)`, before the `parseKS` branch:

```swift
        if let om = Self.parseOM(response) {
            lock.lock()
            let changed = om.voice != voiceStatus
            model = om.model
            voiceStatus = om.voice
            lock.unlock()
            if changed { onVoiceKeyerStatusChange?(om.voice) }
            return
        }
        if let ic = Self.parseIC(response) {
            handleIcons(ic)
            return
        }
```

and add the handler:

```swift
    /// One `IC` response: the real playback signal, and the bank confirmation
    /// a pending bank-2 memory is waiting on.
    private func handleIcons(_ ic: (playing: Bool, bank: Int)) {
        lock.lock()
        let playbackChanged = ic.playing != lastVoicePlaying
        let bankChanged = ic.bank != confirmedBank
        let hasBanks = model == .k3
        lastVoicePlaying = ic.playing
        confirmedBank = ic.bank
        let pending = pendingVoiceMemory
        lock.unlock()

        if playbackChanged { onVoicePlaybackChange?(ic.playing) }
        // Only the banked model reports a bank; a KX has none to report.
        if bankChanged, hasBanks { onVoiceBankChange?(ic.bank) }
        guard let pending else { return }

        let wantedBank = pending <= 4 ? 1 : 2
        if ic.bank == wantedBank {
            lock.lock()
            pendingVoiceMemory = nil
            lock.unlock()
            if let tap = Self.cmdPlayK3Memory[pending <= 4 ? pending : pending - 4] {
                currentTransport()?.write(tap)
            }
            return
        }

        // Never toggle twice: a second `SWH37;` would land back where we
        // started. The window exists only to absorb a poll response that was
        // already in flight when the change was requested.
        lock.lock()
        bankConfirmAttempts += 1
        let exhausted = bankConfirmAttempts >= 2
        if exhausted { pendingVoiceMemory = nil }
        lock.unlock()

        if exhausted { onVoiceMessageDropped?(pending) }
    }
```

- [ ] **Step 7: Reset the new state in `stop()`**

Add inside `stop()`, before `lock.unlock()`:

```swift
        voiceStatus = .unsupported
        model = .k3
        lastVoicePlaying = nil
        confirmedBank = nil
        pendingVoiceMemory = nil
        bankConfirmAttempts = 0
```

- [ ] **Step 8: Declare the conformance**

Change the class declaration:

```swift
final class ElecraftK3Driver: RadioDriver, VoiceMessageCapable, @unchecked Sendable {
```

- [ ] **Step 9: Run and watch it pass**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/K3ProtocolTests 2>&1 | tee /tmp/xcb.log | grep -E "Test Case|error:|\*\* TEST"
```

Expected: all pass. `testPlayingABankOneMemoryTapsImmediately` proves the confirmed-bank fast path.

---

### Task 9: Bank sequencing — confirm, or transmit nothing

**Files:**
- Test: `Tests/Hardware/K3ProtocolTests.swift`

This is the test that matters most in the whole plan: it is the difference between a missed transmission and the wrong audio on the air.

- [ ] **Step 1: Write the failing test**

Append inside `K3ProtocolTests`:

```swift
    // MARK: Bank sequencing

    /// Asking for a bank-2 memory requests the bank change and sends no tap.
    func testBankTwoMemoryRequestsTheBankAndDoesNotTapYet() {
        let (driver, transport) = startedK3(bank: 1)
        driver.playVoiceMessage(memory: 6)
        XCTAssertEqual(transport.writtenExcludingPolls, "SWH37;IC;")
        XCTAssertFalse(transport.allWritten.contains("SWT31;"), "tapped before the bank confirmed")
    }

    /// The tap follows only once an IC confirms the radio really is in bank 2 —
    /// and it is bank 2's M2, i.e. memory 6.
    func testTapFollowsTheBankConfirmation() {
        let (driver, transport) = startedK3(bank: 1)
        driver.playVoiceMessage(memory: 6)
        transport.clearWritten()

        transport.injectBytes(icBytes(playing: false, bank: 2))
        XCTAssertEqual(transport.writtenExcludingPolls, "SWT31;")
    }

    /// **The safety property.** If the bank never confirms, nothing is
    /// transmitted at all — and the driver says so rather than failing silent.
    func testAnUnconfirmedBankTransmitsNothingAndReports() {
        let (driver, transport) = startedK3(bank: 1)
        let dropped = expectation(description: "play dropped")
        driver.onVoiceMessageDropped = { memory in
            XCTAssertEqual(memory, 6)
            dropped.fulfill()
        }

        driver.playVoiceMessage(memory: 6)
        transport.clearWritten()

        // Two IC responses that still say bank 1 — the switch did not take.
        transport.injectBytes(icBytes(playing: false, bank: 1))
        transport.injectBytes(icBytes(playing: false, bank: 1))

        wait(for: [dropped], timeout: 1)
        XCTAssertEqual(transport.writtenExcludingPolls, "", "no tap may be sent on an unconfirmed bank")
    }

    /// Never toggle twice: a second SWH37; would land back in bank 1. The
    /// two-response window absorbs a poll that was already in flight, it does
    /// not license a retry.
    func testTheBankIsNeverToggledTwiceForOneRequest() {
        let (driver, transport) = startedK3(bank: 1)
        driver.playVoiceMessage(memory: 5)
        transport.clearWritten()

        transport.injectBytes(icBytes(playing: false, bank: 1))
        transport.injectBytes(icBytes(playing: false, bank: 1))

        XCTAssertFalse(transport.allWritten.contains("SWH37;"))
    }

    /// A stale poll arriving first must not spend the whole window: the real
    /// confirmation still lands the tap.
    func testAStalePollBeforeTheConfirmationStillPlays() {
        let (driver, transport) = startedK3(bank: 1)
        driver.playVoiceMessage(memory: 8)
        transport.clearWritten()

        transport.injectBytes(icBytes(playing: false, bank: 1))   // stale, in flight
        transport.injectBytes(icBytes(playing: false, bank: 2))   // the confirmation

        XCTAssertEqual(transport.writtenExcludingPolls, "SWT39;", "bank 2 M4 is memory 8")
    }

    /// Once bank 2 is confirmed, a second bank-2 memory taps straight away.
    func testASecondBankTwoMemoryNeedsNoFurtherSwitch() {
        let (driver, transport) = startedK3(bank: 2)
        driver.playVoiceMessage(memory: 7)
        XCTAssertEqual(transport.writtenExcludingPolls, "SWT35;")
    }

    /// Aborting clears a pending play: a later IC must not resurrect it.
    func testStopClearsAPendingPlay() {
        let (driver, transport) = startedK3(bank: 1)
        driver.playVoiceMessage(memory: 6)
        driver.stopVoiceMessage()
        transport.clearWritten()

        transport.injectBytes(icBytes(playing: false, bank: 2))
        XCTAssertEqual(transport.writtenExcludingPolls, "")
    }
```

- [ ] **Step 2: Run and watch them pass**

The implementation landed in Task 8. If any of these fail, the bug is in `handleIcons` — fix it there, not in the test.

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/K3ProtocolTests 2>&1 | tee /tmp/xcb.log | grep -E "Test Case|error:|\*\* TEST"
```

- [ ] **Step 3: Prove the safety test can fail**

Temporarily change `handleIcons` to tap regardless of the bank — move the tap above the `if ic.bank == wantedBank` check. Re-run: `testAnUnconfirmedBankTransmitsNothingAndReports` must fail. Restore the code and re-run to green. A test that has never been seen failing has not been shown to test anything.

---

### Task 10: Ask `OM;` at start and on first contact; poll `IC;`

**Files:**
- Modify: `Sources/Hardware/Radio/ElecraftK3Driver.swift`
- Test: `Tests/Hardware/K3ProtocolTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
    // MARK: Discovery

    func testStartAsksForOptionsAndPollsIcons() {
        let driver = ElecraftK3Driver()
        let transport = MockSerialTransport()
        driver.start(transport: transport)
        XCTAssertTrue(transport.allWritten.contains("OM;"), "options never requested")
    }

    /// A radio powered on after the app connected would miss a one-shot query
    /// and read as having no recorder for the rest of the session. The first IF
    /// is the moment it proves it is listening, so ask again there — once.
    func testOptionsAreAskedAgainOnTheFirstIF() {
        let driver = ElecraftK3Driver()
        let transport = MockSerialTransport()
        driver.start(transport: transport)
        transport.clearWritten()

        transport.inject(ifResponse(freqHz: 14_042_000))
        XCTAssertTrue(transport.allWritten.contains("OM;"))

        transport.clearWritten()
        transport.inject(ifResponse(freqHz: 14_043_000))
        XCTAssertFalse(transport.allWritten.contains("OM;"), "asked more than once")
    }

    func testPollIncludesIcons() {
        XCTAssertTrue(ElecraftK3Driver.pollCommands.contains("IC;"))
        XCTAssertTrue(ElecraftK3Driver.pollCommands.contains("IF;"))
        XCTAssertTrue(ElecraftK3Driver.pollCommands.contains("KS;"))
    }

    func testStatusChangeIsReportedOnce() {
        let driver = ElecraftK3Driver()
        let transport = MockSerialTransport()
        var reported: [VoiceKeyerStatus] = []
        driver.onVoiceKeyerStatusChange = { reported.append($0) }
        driver.start(transport: transport)

        transport.inject("OM APXSDFfLVR--;")
        transport.inject("OM APXSDFfLVR--;")
        XCTAssertEqual(reported, [.available(count: 8)])
    }

    func testPlaybackChangeIsReportedOnlyOnChange() {
        let (driver, transport) = startedK3()
        var reported: [Bool] = []
        driver.onVoicePlaybackChange = { reported.append($0) }

        transport.injectBytes(icBytes(playing: true, bank: 1))
        transport.injectBytes(icBytes(playing: true, bank: 1))
        transport.injectBytes(icBytes(playing: false, bank: 1))
        XCTAssertEqual(reported, [true, false])
    }
```

- [ ] **Step 2: Run it and watch it fail**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/K3ProtocolTests 2>&1 | tee /tmp/xcb.log | grep -E "Test Case|error:|\*\* TEST"
```

Expected: failures — `OM;` never sent, no `pollCommands`.

- [ ] **Step 3: Write the implementation**

Replace `poll()` and the poll constants:

```swift
    /// IF = freq/mode/TX; KS = keyer speed (bidirectional speed sync);
    /// IC = icons, which carry the voice-playback flag and the message bank.
    static let pollCommands = cmdPollIF + cmdPollKS + cmdPollIcons

    private func poll() {
        currentTransport()?.write(Self.pollCommands)
    }
```

In `start(transport:)`, extend the opening write:

```swift
        // AI0 = deterministic polling; K31 = K3 extended response mode;
        // OM = which model answered and which option modules are fitted.
        transport.write(Self.cmdAutoInfoOff + Self.cmdExtendedMode + Self.cmdPollOptions)
```

Add a stored property beside the others:

```swift
    /// Whether the options query has been repeated after the radio first
    /// answered. The query at `start` can arrive before the radio is listening.
    private var askedOptionsAfterFirstIF = false
```

In the `parseIF` branch of `handle(response:)`, after the existing state handling and before `return`:

```swift
            lock.lock()
            let needsOptions = !askedOptionsAfterFirstIF
            askedOptionsAfterFirstIF = true
            lock.unlock()
            if needsOptions { currentTransport()?.write(Self.cmdPollOptions) }
```

Reset it in `stop()`:

```swift
        askedOptionsAfterFirstIF = false
```

- [ ] **Step 4: Run and watch it pass**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/K3ProtocolTests 2>&1 | tee /tmp/xcb.log | grep -E "Test Case|error:|\*\* TEST"
```

Expected: all `K3ProtocolTests` pass. Also run `QMXProtocolTests` and `FlexRadioDriverTests` — they must be untouched:

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/QMXProtocolTests -only-testing:QSOPartyLoggerTests/FlexRadioDriverTests 2>&1 | tee /tmp/xcb.log | grep -E "Test Case|error:|\*\* TEST"
```

---

### Task 11: `RadioController` — status, playback, unified abort

**Files:**
- Modify: `Sources/App/RadioController.swift`
- Modify: `Sources/UI/RadioBar.swift:249`, `Sources/UI/KeyMonitorGate.swift`, `Sources/UI/MainView.swift:1433,1465`
- Modify: `Tests/App/KeyMonitorGateTests.swift:117-118`

- [ ] **Step 1: Delete the Task 5 shim and add the real state**

Delete the empty `func playVoiceMessage(memory:caption:) {}` added in Task 5, Step 3. Step 3 below replaces it.

In `RadioController`, add beside the other observable state:

```swift
    /// What the connected radio can do about voice memories. `.unsupported`
    /// until a driver says otherwise, which is the honest default: a driver
    /// that does not conform never reports, and never claims a capability.
    private(set) var voiceStatus: VoiceKeyerStatus = .unsupported
    /// True while the radio reports a voice message actually playing.
    private(set) var isVoicePlaying = false
    /// The message bank the radio was last observed in, or nil on a radio with
    /// no banks. Shown rather than corrected: the app leaves the bank where the
    /// last play put it, which changes what the front panel's buttons address.
    private(set) var voiceBank: Int?
```

and beside the other private state:

```swift
    private var voiceDriver: (any VoiceMessageCapable)?
    /// Which path owns `nowSending`, so the CW timer and the radio's real
    /// end-of-playback signal cannot clear each other's badge.
    private var nowSendingIsVoice = false
```

- [ ] **Step 2: Wire the driver in `connect`**

After `newDriver.start(transport: newTransport)`:

```swift
        // Voice memories are an optional capability: a driver either conforms
        // or the radio has none. Nothing is stubbed (Article 11).
        if var voice = newDriver as? any VoiceMessageCapable {
            voice.onVoiceKeyerStatusChange = { [weak self] status in
                Task { @MainActor [weak self] in self?.voiceStatus = status }
            }
            voice.onVoicePlaybackChange = { [weak self] playing in
                Task { @MainActor [weak self] in self?.voiceDidChangePlayback(playing) }
            }
            voice.onVoiceMessageDropped = { [weak self] memory in
                Task { @MainActor [weak self] in self?.voiceMessageWasDropped(memory) }
            }
            voice.onVoiceBankChange = { [weak self] bank in
                Task { @MainActor [weak self] in self?.voiceBank = bank }
            }
            voiceDriver = voice
        }
```

- [ ] **Step 3: Add the playback methods**

```swift
    func playVoiceMessage(memory: Int, caption: String) {
        guard isConnected, voiceStatus.isReady else { return }
        voiceDriver?.playVoiceMessage(memory: memory)
        // No timer, unlike CW: the radio reports the end of playback for real,
        // so the badge is cleared by the radio rather than by an estimate.
        sendingClearTask?.cancel()
        sendingClearTask = nil
        nowSending = caption
        nowSendingIsVoice = true
    }

    func voiceDidChangePlayback(_ playing: Bool) {
        isVoicePlaying = playing
        if !playing, nowSendingIsVoice {
            nowSending = nil
            nowSendingIsVoice = false
        }
    }

    /// The bank never confirmed, so nothing went out. Say which memory, inline
    /// — a control must never claim a state it has not proved.
    func voiceMessageWasDropped(_ memory: Int) {
        nowSending = nil
        nowSendingIsVoice = false
        lastError = ConnectionError(
            summary: "Voice memory not sent",
            detail: "The radio didn't confirm the message bank in time, so M\(memory) "
                + "was not transmitted. Try again, or move the message to one of the "
                + "first four memories, which need no bank change."
        )
    }
```

- [ ] **Step 4: Rename the abort and cover voice**

Replace `abortCW(settings:)` with:

```swift
    /// Esc. Stops CW and voice both — `RX;` on a radio with voice memories is
    /// documented to terminate message play as well as a keyed transmission.
    func abortTransmission(settings: AppSettings) {
        activeSender(settings)?.abort()
        if voiceStatus.isReady { voiceDriver?.stopVoiceMessage() }
        sendingClearTask?.cancel()
        sendingClearTask = nil
        nowSending = nil
        nowSendingIsVoice = false
    }
```

Set `nowSendingIsVoice = false` in `sendCW` where it sets `nowSending = text`.

Clear the new state in `disconnect()`:

```swift
        voiceDriver = nil
        voiceStatus = .unsupported
        isVoicePlaying = false
        voiceBank = nil
        nowSendingIsVoice = false
```

- [ ] **Step 5: Update the call sites**

```bash
grep -rn "abortCW" Sources Tests
```

- `Sources/UI/RadioBar.swift:249` → `radio.abortTransmission(settings: settings)`
- `Sources/UI/MainView.swift:1433` and `:1465` → same
- `Sources/UI/KeyMonitorGate.swift` — rename the enum case `abortCW` → `abortTransmission` and the `abortsCW` field → `abortsTransmission`, at all five occurrences. It aborts voice now too; a case named for CW would be a lie.
- `Tests/App/KeyMonitorGateTests.swift:117-118` → `.abortTransmission`

- [ ] **Step 6: Build and run the affected suites**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/KeyMonitorGateTests -only-testing:QSOPartyLoggerTests/RadioRegistryTests 2>&1 | tee /tmp/xcb.log | grep -E "Test Case|error:|\*\* TEST"
```

Expected: all pass.

---

### Task 12: `MessagesRow` takes prepared keys

**Files:**
- Modify: `Sources/UI/MessagesRow.swift`

- [ ] **Step 1: Replace the inputs**

Replace the `messages` and `expand` properties with:

```swift
    /// One F-key as the row draws it. Built by the caller so the row never has
    /// to know whether it is showing expanded CW text or a voice memory.
    struct MessageKey: Equatable {
        /// The full caption — "CQ TEST KE5CW", or "M4 AGN?". Truncated here for
        /// the button and shown whole in the tooltip.
        var caption: String
        /// Whether this key does anything: a non-empty CW slot, or a memory
        /// mapping this radio can actually play.
        var isActive: Bool
    }

    let keys: [MessageKey]
```

- [ ] **Step 2: Rewrite the ForEach**

```swift
            ForEach(Array(keys.prefix(8).enumerated()), id: \.offset) { index, key in
                Button {
                    onSend(index)
                } label: {
                    VStack(spacing: 1) {
                        Text("F\(index + 1)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(shortLabel(key.caption))
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .frame(minWidth: 62)
                }
                .disabled(!enabled || !key.isActive)
                .overlay {
                    if index == pendingIndex {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(.purple, lineWidth: 2)
                    }
                }
                .help(index == pendingIndex ? "Return sends this: \(key.caption)" : key.caption)
            }
```

- [ ] **Step 3: Simplify `shortLabel`**

```swift
    private func shortLabel(_ caption: String) -> String {
        caption.count > 13 ? String(caption.prefix(12)) + "…" : caption
    }
```

- [ ] **Step 4: Update the doc comment**

```swift
/// F1–F8 message buttons for the active operating mode — CW text, or the
/// radio's voice memories on phone — plus the Run/S&P toggle, ESM, repeat-CQ,
/// and the CQ-frequency jump chip.
```

---

### Task 13: The messages editor's phone side

**Files:**
- Modify: `Sources/UI/MessagesEditor.swift`

- [ ] **Step 1: Add the mode state and the status text**

Add to the properties:

```swift
    @State private var editClass: ModeClass = .cw
    /// The connected radio's voice-memory situation, for the status line and
    /// for greying memories this radio cannot play.
    let voiceStatus: VoiceKeyerStatus
    /// Which message bank the radio is currently in, or nil on a radio with no
    /// banks. Reported rather than corrected — see `voiceStatusText`.
    let voiceBank: Int?

    /// Radio-neutral, per Article 10 — no manufacturer, no model.
    ///
    /// A `static func` rather than a literal in the view body so the wording is
    /// reachable from `KeyerBackendLabelTests`, which asserts that no string an
    /// operator can see names a manufacturer.
    static func voiceStatusText(_ status: VoiceKeyerStatus, bank: Int?) -> String {
        switch status {
        case .unsupported:
            return "The connected radio has no voice memories. These keys will do "
                + "nothing until a radio that has them is connected."
        case .notInstalled:
            return "This radio's voice recorder option isn't installed, so it has no "
                + "memories to play."
        case .available(let count):
            var text = "\(count) voice \(count == 1 ? "memory" : "memories") available. "
                + "Record them from the radio's front panel; the app only plays them."
            if let bank {
                // The app leaves the bank where the last play put it, so the
                // radio's own M-buttons may not address what their labels say.
                text += " The radio is currently in bank \(bank), so its front-panel "
                    + "buttons play memories \(bank == 1 ? "M1–M4" : "M5–M8")."
            }
            return text
        }
    }
```

- [ ] **Step 2: Add the CW/Phone picker**

Directly above the existing Run/S&P picker:

```swift
            Picker("", selection: $editClass) {
                Text("CW").tag(ModeClass.cw)
                Text("Phone").tag(ModeClass.phone)
            }
            .pickerStyle(.segmented)
            .help("CW messages are text the app keys. Phone messages play the radio's own voice memories.")
```

- [ ] **Step 3: Swap the grid on the selected class**

Wrap the existing eight-row `Grid` in `if editClass == .cw { … }` and add the phone side in the `else`:

```swift
            } else {
                Text("Voice memories — what you recorded in the radio")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    ForEach(0..<MessageSets.voiceMemorySlots, id: \.self) { memoryIndex in
                        GridRow {
                            Text("M\(memoryIndex + 1)")
                                .font(.callout.weight(.bold))
                                .frame(width: 30, alignment: .trailing)
                            TextField("", text: nameBinding(memoryIndex))
                                .frame(width: 360)
                                .disabled(memoryIndex >= voiceStatus.memoryCount
                                          && voiceStatus.memoryCount > 0)
                        }
                    }
                }

                Text("F-keys — which memory each one plays")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    ForEach(0..<MessagesDraft.slotCount, id: \.self) { index in
                        GridRow {
                            Text("F\(index + 1)")
                                .font(.callout.weight(.bold))
                                .frame(width: 30, alignment: .trailing)
                            Picker("", selection: memoryBinding(index)) {
                                Text("—").tag(Int?.none)
                                ForEach(1...MessageSets.voiceMemorySlots, id: \.self) { memory in
                                    // `draft.voiceMemoryCaption`, not
                                    // `draft.edited.…`: the latter rebuilds the
                                    // whole MessageSets once per row per memory,
                                    // 64 times a render.
                                    Text(draft.voiceMemoryCaption(memory)).tag(Int?.some(memory))
                                }
                            }
                            .labelsHidden()
                            .frame(width: 360, alignment: .leading)
                        }
                    }
                }

                Text(Self.voiceStatusText(voiceStatus, bank: voiceBank))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
```

- [ ] **Step 4: Add the two bindings**

```swift
    private func nameBinding(_ memoryIndex: Int) -> Binding<String> {
        Binding(
            get: { draft.voiceMemoryNames[memoryIndex] },
            set: { draft.setVoiceMemoryName($0, at: memoryIndex) }
        )
    }

    private func memoryBinding(_ index: Int) -> Binding<Int?> {
        Binding(
            get: { draft[voice: editMode, index] },
            set: { draft[voice: editMode, index] = $0 }
        )
    }
```

- [ ] **Step 5: Retitle, and hide the CW-only chrome on the phone tab**

- Title: `Text("Messages — \(party?.name ?? document.log.partyID)")`.
- Wrap the macro-help caption, the mismatch banner and both cut-number toggles in `if editClass == .cw { … }`: none of them can apply to a recording.
- Restore Defaults help text: `"Replace all messages with \(party?.name ?? "this party")'s defaults (⇧⌘R)"`.

- [ ] **Step 6: Pass the status in from `MainView`**

At the `MessagesEditor(` call site in `MainView.swift`, add `voiceStatus: radio.voiceStatus` and `voiceBank: radio.voiceBank`.

- [ ] **Step 7: Rename the undo action name**

In `Sources/App/LogDocument.swift:239`: `undoManager?.setActionName("Edit Messages")`.

- [ ] **Step 8: Extend the manufacturer-name guard to the new strings**

`KeyerBackendLabelTests.testNoDisplayedLabelNamesAManufacturer` is the half of
Article 10 the grep cannot do — it checks strings an operator can actually see.
It currently enumerates keyer-backend labels only, and the new status text is
exactly the kind of sentence that could name a model. Append to
`Tests/App/KeyerBackendLabelTests.swift`:

```swift
    /// Article 10's other half: the grep over Sources/UI cannot see whether a
    /// *displayed* sentence names a model, so the strings are asserted here.
    func testVoiceStatusTextNamesNoManufacturer() {
        let banned = ["k3", "kx3", "kx2", "flex", "icom", "yaesu", "kenwood", "elecraft", "ci-v",
                      "kdvr", "dvr"]
        let texts = [
            MessagesEditor.voiceStatusText(.unsupported, bank: nil),
            MessagesEditor.voiceStatusText(.notInstalled, bank: nil),
            MessagesEditor.voiceStatusText(.available(count: 2), bank: nil),
            MessagesEditor.voiceStatusText(.available(count: 8), bank: 1),
            MessagesEditor.voiceStatusText(.available(count: 8), bank: 2),
        ]
        for text in texts {
            for term in banned {
                XCTAssertFalse(
                    text.lowercased().contains(term),
                    "voice status '\(text)' names '\(term)' — Article 10 keeps these neutral"
                )
            }
        }
    }

    /// One memory is a memory, not "1 memories".
    func testVoiceStatusTextPluralises() {
        XCTAssertTrue(MessagesEditor.voiceStatusText(.available(count: 1), bank: nil)
            .contains("1 voice memory"))
        XCTAssertTrue(MessagesEditor.voiceStatusText(.available(count: 8), bank: nil)
            .contains("8 voice memories"))
    }
```

- [ ] **Step 9: Build and run the guard**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/KeyerBackendLabelTests 2>&1 | tee /tmp/xcb.log | grep -E "Test Case|error:|\*\* TEST"
```

Expected: all pass. If `dvr` trips, reword — "voice recorder option" is the
neutral form and is what the strings above already use.

---

### Task 14: Wire `MainView` — context, keys, enablement, repeat CQ

**Files:**
- Modify: `Sources/UI/MainView.swift`

- [ ] **Step 1: Feed the memory count into the context**

In `operatingContext`, add after `keying: settings.keying`:

```swift
            voiceMemoryCount: radio.voiceStatus.memoryCount
```

- [ ] **Step 2: Add the message-keys seam**

A separate computed property, not an inline expression — the left pane's body has a type-checker budget and must only grow through named seams:

```swift
    /// What the messages row draws for F1–F8 right now. Built here rather than
    /// in the row so the row never has to know which mode class is live.
    private var messageKeys: [MessagesRow.MessageKey] {
        let context = operatingContext
        return (0..<8).map { index in
            switch flow.transmission(at: index, context: context) {
            case .cw(let text):
                MessagesRow.MessageKey(caption: text, isActive: true)
            case .voice(_, let caption):
                MessagesRow.MessageKey(caption: caption, isActive: true)
            case .silent:
                MessagesRow.MessageKey(caption: context.modeClass == .phone ? "—" : "",
                                       isActive: false)
            }
        }
    }
```

- [ ] **Step 3: Update the `MessagesRow` call site**

Replace the `messages:` and `expand:` arguments with `keys: messageKeys`, and widen `enabled:`:

```swift
                keys: messageKeys,
                onSend: sendMessageAt,
                enabled: radio.isConnected
                    && (currentModeClass == .cw
                        || (currentModeClass == .phone && radio.voiceStatus.isReady)),
```

- [ ] **Step 4: Widen repeat CQ**

Replace `startRepeat()`:

```swift
    private func startRepeat() {
        repeatTask?.cancel()
        let voiceReady = currentModeClass == .phone && radio.voiceStatus.isReady
        guard radio.isConnected, currentModeClass == .cw || voiceReady else {
            repeatCQ = false
            return
        }
        // F1 in Run is the CQ, in whichever mode class is live.
        let transmission = flow.transmission(at: 0, context: operatingContext)
        guard transmission != .silent else {
            repeatCQ = false
            return
        }
        captureCQFrequency()
        repeatTask = Task {
            while !Task.isCancelled && repeatCQ {
                // Re-resolve each pass: the CW macros expand against live entry
                // state, and the mapping may have been edited between repeats.
                let outgoing = flow.transmission(at: 0, context: operatingContext)
                transmit(outgoing)
                await waitForEndOfTransmission(outgoing)
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(settings.repeatIntervalSeconds * 1_000_000_000))
                } catch {
                    break
                }
            }
        }
    }

    /// How long to hold before the next repeat. CW is estimated from the text
    /// and the speed; voice is not estimated at all — the radio reports when a
    /// message stops, which is exactly what N1MM cannot do for a radio's own
    /// recorder and why its repeat interval has to be hand-tuned.
    private func waitForEndOfTransmission(_ transmission: EntryFlow.Transmission) async {
        switch transmission {
        case .cw(let text):
            let onAir = radio.estimatedSendDuration(text, settings: settings)
            try? await Task.sleep(nanoseconds: UInt64(onAir * 1_000_000_000))
        case .voice:
            await waitForVoicePlaybackToFinish()
        case .silent:
            break
        }
    }

    /// Wait for the radio to start, then finish, playing. Bounded at both ends:
    /// `IC` is polled every 0.5 s, so a short message can begin and end between
    /// polls — in which case fall through to the interval rather than stall the
    /// repeat forever.
    private func waitForVoicePlaybackToFinish() async {
        let startDeadline = Date().addingTimeInterval(2)
        while !radio.isVoicePlaying, Date() < startDeadline, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard radio.isVoicePlaying else { return }
        while radio.isVoicePlaying, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
```

- [ ] **Step 5: Stop the repeat when the mode leaves its class**

In `modeChanged()`, add before `flow.modeChanged(operatingContext)`:

```swift
        // A repeat started on CW must not keep running after a switch to phone,
        // where F1 means a different thing entirely.
        if repeatCQ { stopRepeat() }
```

- [ ] **Step 6: Build and run the full suite**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | tee /tmp/xcb-full.log | grep -E "error:|failed|\*\* TEST|Executed [0-9]+ test"
```

Expected: `** TEST SUCCEEDED **`. Note the executed-test count for Task 15.

---

### Task 15: Docs, Article 10 check, and the commit

**Files:**
- Modify: `README.md`, `docs/PROVENANCE.md`

- [ ] **Step 1: README — the radio feature bullet**

Extend the Elecraft paragraph near `README.md:298` and the keying section near `:318`:

```markdown
**Voice keying** plays the radio's own recorded memories — never audio from the
Mac. The app asks the radio what it has: 8 memories on a K3 with the KDVR3
recorder, 2 on a KX3 or KX2, and an inline note when the recorder isn't fitted.
On phone, F1–F8 map to memories you choose, ESM works exactly as it does on CW,
`Esc` aborts playback instantly, and Repeat CQ times itself off the radio's own
end-of-message signal rather than a guess.

Record the memories from the radio's front panel — the app only plays them.
Three things it cannot see: whether a memory actually holds a recording (an
empty one is simply silent), whether you have re-recorded one since naming it
here, and whether an M1–M4 button has been reassigned as a programmable
function switch, which makes that memory unavailable for playback.
```

- [ ] **Step 2: README — keyboard table**

Find the rows for the F-keys and `Esc`:

```bash
grep -n "^| \`F1\|^| \`Esc\|^| \`F1–F8" README.md
```

Replace each row's description with these exact texts, keeping the existing
table's column layout:

- F1–F8: ``Send the message in that slot — CW text on CW, and the radio's voice memory on phone. The button shows what it will send: the expanded text, or `M4 AGN?`.``
- Esc: `Abort instantly — a CW message mid-character, or a voice memory mid-playback.`

- [ ] **Step 3: README — test count**

Read the count from the last full run rather than guessing it:

```bash
grep -oE "Executed [0-9]+ tests" /tmp/xcb-full.log | tail -1
grep -n "tests" README.md | grep -iE "[0-9]{3} test"
```

Replace the number in the README with the one the run reported.

- [ ] **Step 4: `docs/PROVENANCE.md`**

Append this section:

```markdown
## Radio protocols — Elecraft voice memories

Extracted and reasoned about in
[`docs/research/k3_voice_keyer.md`](research/k3_voice_keyer.md). All fetched
2026-08-09.

- **K3S/K3/KX3/KX2 Programmer's Reference, Rev. G5, Feb. 20 2019** —
  <https://ftp.elecraft.com/KX2/Manuals%20Downloads/K3S&K3&KX3&KX2%20Pgmrs%20Ref,%20G5.pdf>
  Authority for every command byte and switch code: `SWT`/`SWH` Tables 7, 8 and
  8A, `RX`, `IC` Table 4, `OM`. The same revision the driver already cited for
  `IF`/`FA`/`MD`/`KS`/`KY`.
- **K3 Owner's Manual, Rev. D10** —
  <https://ftp.elecraft.com/K3/Manuals%20Downloads/E740107%20K3%20Owner's%20man%20D10.pdf>
  Front-panel semantics: what M1–M4 mean, and the `CONFIG:KDVR3` note that
  message play asserts PTT by itself.
- **KDVR3 Option Installation, Rev. C** —
  <https://ftp.elecraft.com/K3S/Manuals%20Downloads/E740130%20KDVR3%20Option%20Installation%20Rev%20C.pdf>
  Authority for the K3's count: 2 banks of 4.
- **KX3 Owner's Manual, Rev. C5** —
  <https://ftp.elecraft.com/KX3/Manuals%20Downloads/E740163%20KX3%20Owner's%20man%20Rev%20C5.pdf>
  Two memories; play by tapping MSG then the digit.
- **KX2 Owner's Manual, Rev. B2** —
  <https://ftp.elecraft.com/KX2/Manuals%20Downloads/KX2%20owner's%20man%20B2.pdf>
  Identical two-memory behaviour.

The N1MM Logger+ manual was read for interaction precedent and is cited in the
research file. Per Article 1 it is authority for nothing here, and no byte in
the driver comes from it.
```

- [ ] **Step 5: Verify Article 10**

```bash
grep -rniE "k3|kx3|kx2|flex|icom|yaesu|kenwood|elecraft|ci-v" Sources/App Sources/UI | grep -vE ':[0-9]+: *(//|\*)' | grep -vE ':[0-9]+: *case [A-Za-z]+ = "'
```

Expected: no output. Also confirm no memory count leaked into the app layer:

```bash
grep -rnE "\b(8|2) voice|memoryCount = [0-9]|count: 8" Sources/App Sources/UI
```

Expected: no output — every count comes from `voiceStatus`.

- [ ] **Step 6: Full suite, one last time**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | tee /tmp/xcb-full.log | grep -E "error:|failed|\*\* TEST|Executed [0-9]+ test"
```

- [ ] **Step 7: Commit Phase B**

```bash
git add -A
git commit -m "$(cat <<'EOF'
radio(elecraft): play the radio's own voice memories from the F-keys

Phone messages now play the recorder in the radio, per Article 11. The count
is discovered from OM; at connect -- 8 on a K3 with the KDVR3, 2 on a KX3 or
KX2, none when the option is absent -- so the app reports what the radio has
rather than assuming.

What N1MM gives up on a radio's own recorder, this does not: RX; aborts on
Esc, IC; byte a bit B2 reports the real end of a message so Repeat CQ times
itself, and the radio asserts PTT during message play so no VOX is needed.

Reaching memories 5-8 changes the message bank first, and confirms it before
tapping: an unconfirmed bank drops the transmission rather than play the
wrong recording. The bank is stored per mode group, so this cannot disturb
the operator's CW memories.

Verified by test and build only. No K3 was on the desk -- the OM letter
position, RX; on a voice message, and bank settling all want a bench check.

Sources: Programmer's Reference G5, K3 Owner's Manual D10, KDVR3 Rev C,
KX3 Owner's Manual C5, KX2 Owner's Manual B2, all fetched 2026-08-09.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Verification summary

At the end, these must all hold — report the command and its output for each (Article 8):

1. `** TEST SUCCEEDED **` on the full suite, with the count recorded in the README.
2. The Article 10 grep returns nothing.
3. `testAnUnconfirmedBankTransmitsNothingAndReports` has been seen to fail with the bank check removed, and to pass with it restored.
4. `testDecodingAPreVoiceLogFillsInPhoneDefaults` passes — no existing log changes shape.
5. `git log --oneline` shows exactly two implementation commits on top of the four docs commits.

**Not verifiable here, and must be said plainly in the report:** no Elecraft radio was connected. The `OM;` letter position for `D`, whether `RX;` cuts a voice message as cleanly as it cuts CW, and whether the bank change settles before the tap are all bench checks.
