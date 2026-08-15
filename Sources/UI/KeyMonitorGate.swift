import Foundation

/// The decision layer behind `MainView`'s app-wide key monitor.
///
/// `NSEvent.addLocalMonitorForEvents` is *application*-wide, not window-scoped.
/// A monitor installed by one document window fires for every key down in the
/// process: while a sheet owns the keyboard, and while a different document is
/// focused. Both are wrong for keys that transmit. F1–F8 would key CW out of a
/// modal editor using the *saved* macros rather than the ones on screen, and
/// swallowing Esc stops the sheet from closing at all. Monitors also run
/// newest-installed first and the first one to return `nil` consumes the event,
/// so with two logs open the F-keys act on whichever was opened last rather
/// than on the window the operator is typing in.
///
/// The event plumbing itself is not unit-testable — an `NSEvent` built in a test
/// and dispatched by hand never traverses a local monitor — so every decision the
/// monitor makes is a pure function here, and the closure in `MainView` does
/// nothing but read the window state, ask this type, and dispatch. `response` is
/// the whole of it; `focus` and `action` are the two halves it is built from,
/// tested on their own because their key tables are worth pinning directly.
enum KeyMonitorGate {

    // MARK: Which window the keystroke belongs to

    /// Where a key down is going, relative to the document that installed the
    /// monitor.
    enum Focus: Equatable {
        /// This document's own window — or its band map panel — has the
        /// keyboard. The monitor may act and may consume the key.
        case document
        /// A sheet this document is presenting has the keyboard. The sheet owns
        /// the key: it is never consumed, so Esc still reaches Cancel and an
        /// F-key never transmits from a modal editor.
        case sheet
        /// Another document, the dashboard, or no window at all. Not ours to
        /// handle.
        case elsewhere
    }

    /// The window state the gate reasons about, as plain window numbers so the
    /// decision can be tested without an `NSWindow` or a screen.
    struct Windows: Equatable {
        /// `MainView`'s own window; nil until it is on screen.
        var host: Int?
        /// `NSApp.keyWindow`; nil when no window in the app has the keyboard.
        var key: Int?
        /// `NSApp.keyWindow?.sheetParent` — set only when the key window is a
        /// sheet, and identifies the window it is attached to.
        var keySheetParent: Int?
        /// This document's band map panel, when open.
        var bandMap: Int?
        /// `hostWindow.attachedSheet != nil`.
        var hostHasAttachedSheet: Bool

        init(
            host: Int?,
            key: Int?,
            keySheetParent: Int? = nil,
            bandMap: Int? = nil,
            hostHasAttachedSheet: Bool = false
        ) {
            self.host = host
            self.key = key
            self.keySheetParent = keySheetParent
            self.bandMap = bandMap
            self.hostHasAttachedSheet = hostHasAttachedSheet
        }
    }

    static func focus(_ windows: Windows) -> Focus {
        guard let host = windows.host, let key = windows.key else { return .elsewhere }

        // A sheet holds the keyboard. Ours to observe but never to consume;
        // anyone else's is not ours at all.
        if let parent = windows.keySheetParent {
            return parent == host ? .sheet : .elsewhere
        }

        let isOurs = key == host || (windows.bandMap.map { $0 == key } ?? false)
        guard isOurs else { return .elsewhere }

        // The band map is a `becomesKeyOnlyIfNeeded` panel, so it can hold focus
        // while a sheet is up on the document window behind it. Belt and braces:
        // an attached sheet means the sheet owns the keyboard regardless.
        return windows.hostHasAttachedSheet ? .sheet : .document
    }

    // MARK: Which key does what

    /// Everything the monitor can do. One case per key it consumes — nothing
    /// else in the app reaches this table.
    enum Action: Equatable {
        case adjustWPM(by: Int)
        case previousSpot
        case nextSpot
        case jumpToCQFrequency
        case toggleBandMap
        case sendMessage(index: Int)
        case clearEntry
        case abortTransmission
        case exportADIF
        case exportCabrillo
        /// ⇧⌘← / ⇧⌘→: the VFO by this many hertz, sign and all.
        case nudgeVFO(byHz: Int)
    }

    /// One press of ⇧⌘← / ⇧⌘→, in hertz.
    static let vfoNudgeHz = 100

    /// F1–F8 → message index 0–7.
    private static let fKeyIndex: [UInt16: Int] = [
        122: 0, 120: 1, 99: 2, 118: 3, 96: 4, 97: 5, 98: 6, 100: 7,
    ]

    /// The monitor's whole key table. `nil` means "not ours — pass it on".
    ///
    /// A ⌘ chord that isn't in the command table falls through to the plain
    /// keys, so ⌘F2 still sends message 2 exactly as it always has.
    static func action(keyCode: UInt16, command: Bool, shift: Bool = false) -> Action? {
        if command, let chord = commandAction(keyCode: keyCode, shift: shift) {
            return chord
        }
        if let index = fKeyIndex[keyCode] {
            return .sendMessage(index: index)
        }
        switch keyCode {
        case 111: return .clearEntry  // F12: wipe the entry and start over
        case 53: return .abortTransmission  // Esc
        default: return nil
        }
    }

    // MARK: The whole decision for one key down

    /// Everything the monitor does with a single key down, in the order it
    /// must happen: stop the loop, take the transmitter down, then dispatch.
    ///
    /// `abortsTransmission` is the only place an abort is decided —
    /// `Action.abortTransmission` never reaches `action`, so no caller can
    /// abort twice or abort *after* starting the message the same keystroke
    /// asked for.
    struct Response: Equatable {
        /// Cancel a running repeat-CQ loop.
        var stopsRepeat = false
        /// Force key/PTT up and stop any voice memory now playing, discarding
        /// whatever is on the air. Named for what it does, not for CW alone —
        /// it has covered voice too since the K3 voice keyer landed.
        var abortsTransmission = false
        /// The action to dispatch, once the transmitter is down.
        var action: Action?
        /// Swallow the event so it never reaches the focused control.
        var consumesEvent = false
    }

    /// While a repeat-CQ loop is running, *every* key does what Esc does: the
    /// operator has started answering someone, and the half-sent CQ must come
    /// off the air mid-character rather than talk over him. A key that has its
    /// own job still does it afterwards, so F2 replaces the CQ instead of
    /// queueing behind it, and a letter is left unconsumed so it still lands in
    /// the call field.
    ///
    /// With no repeat running nothing is aborted but Esc — typing the next call
    /// while an F2 exchange goes out must let the exchange finish.
    static func response(
        keyCode: UInt16,
        command: Bool,
        shift: Bool = false,
        focus: Focus,
        repeatRunning: Bool
    ) -> Response {
        // Another document, the dashboard, or no window at all: not ours to
        // stop, abort, or consume.
        guard focus != .elsewhere else { return Response() }

        var response = Response()
        if repeatRunning {
            response.stopsRepeat = true
            response.abortsTransmission = true
        }

        let mapped = action(keyCode: keyCode, command: command, shift: shift)
        if mapped == .abortTransmission { response.abortsTransmission = true }

        // A sheet owns the keyboard: the abort above still stands, but the key
        // is never consumed and no action is dispatched, so Esc also closes the
        // sheet and F1–F8 cannot key a macro that is being edited.
        guard focus == .document else { return response }

        if let mapped, mapped != .abortTransmission { response.action = mapped }
        response.consumesEvent = mapped != nil
        return response
    }

    private static func commandAction(keyCode: UInt16, shift: Bool) -> Action? {
        switch keyCode {
        case 24, 69: return .adjustWPM(by: 2)  // '=' / keypad '+' (⇧= is '+' too)
        case 27, 78: return .adjustWPM(by: -2)  // '-' / keypad '-'
        // Spot stepping is the vertical axis only: ⌘← / ⌘→ are macOS's own
        // beginning/end-of-line keys and stay with whatever has focus. The map
        // draws high frequency at the top, so up the map is up the band.
        case 126: return .nextSpot  // ↑
        case 125: return .previousSpot  // ↓
        // The horizontal axis is the VFO, and only with ⇧: ⇧⌘←/⇧⌘→ nudge it
        // 100 Hz (2026-08-15). The shifted pair was "select to line
        // start/end" in the entry fields, which a callsign never needs.
        case 123 where shift: return .nudgeVFO(byHz: -vfoNudgeHz)  // ←
        case 124 where shift: return .nudgeVFO(byHz: vfoNudgeHz)  // →
        case 38: return .jumpToCQFrequency  // 'j'
        case 11: return .toggleBandMap  // 'b'
        // The only chord ⇧ distinguishes. In the toolbar's Export menu these
        // are badge text; the gate is what actually fires them.
        case 14: return shift ? .exportCabrillo : .exportADIF  // 'e'
        default: return nil
        }
    }
}
