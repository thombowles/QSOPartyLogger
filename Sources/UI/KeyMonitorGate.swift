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
        /// `NSApp.modalWindow` — the app-modal dialog running, if one is
        /// (Contest Setup, `CenteredDialog`). It holds the keyboard exactly
        /// as a sheet does.
        var modal: Int?

        init(
            host: Int?,
            key: Int?,
            keySheetParent: Int? = nil,
            bandMap: Int? = nil,
            hostHasAttachedSheet: Bool = false,
            modal: Int? = nil
        ) {
            self.host = host
            self.key = key
            self.keySheetParent = keySheetParent
            self.bandMap = bandMap
            self.hostHasAttachedSheet = hostHasAttachedSheet
            self.modal = modal
        }
    }

    static func focus(_ windows: Windows) -> Focus {
        guard let host = windows.host, let key = windows.key else { return .elsewhere }

        // A sheet holds the keyboard. Ours to observe but never to consume;
        // anyone else's is not ours at all.
        if let parent = windows.keySheetParent {
            return parent == host ? .sheet : .elsewhere
        }

        // A modal dialog is a sheet that hangs from the screen instead of the
        // window: it owns the keyboard, and nothing is consumed while it does.
        if let modal = windows.modal, modal == key {
            return .sheet
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
        /// ⇧⌘B: fasten the band map to the side of its log window, or set it
        /// free — `BandMapBolt`.
        case toggleBandMapBolt
        case sendMessage(index: Int)
        /// ⌥F1–⌥F8, and the message buttons' own right-click menu: open the
        /// Messages editor on that slot instead of transmitting it.
        case editMessage(index: Int)
        case clearEntry
        case abortTransmission
        case exportADIF
        case exportCabrillo
        /// ⌥⌘E: one POTA submission file per own park (2026-08-25).
        case exportPota
        /// ⇧⌘← / ⇧⌘→: the VFO by this many hertz, sign and all.
        case nudgeVFO(byHz: Int)
        /// ⌘/: shortcut hints on every button, and the legend.
        case toggleShortcutHints
        /// ⇧⌘L: every row of the log to RUMlogNG again, oldest first — the
        /// catch-up for a log made before sending was on (2026-09-07). A
        /// second press stops it.
        case sendLogToRUMlog
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
    ///
    /// `option` is read for the F row — ⌥F2 edits message 2 rather than
    /// sending it — and for one command chord, ⌥⌘E (export for POTA); ⌥ on
    /// any other key leaves that key's meaning alone.
    static func action(
        keyCode: UInt16, command: Bool, shift: Bool = false, option: Bool = false
    ) -> Action? {
        if command, let chord = commandAction(keyCode: keyCode, shift: shift, option: option) {
            return chord
        }
        if let index = fKeyIndex[keyCode] {
            return option ? .editMessage(index: index) : .sendMessage(index: index)
        }
        switch keyCode {
        case 111: return .clearEntry  // F12: wipe the entry and start over
        case 53: return .abortTransmission  // Esc
        default: return nil
        }
    }

    /// Whether a keystroke is a shortcut — a key doing a job of its own —
    /// rather than the operator answering someone. A running repeat leaves
    /// these alone (2026-08-16: "make shortcuts allowed during calling CQ
    /// without canceling"); everything else pauses it.
    ///
    /// Shortcuts are every ⌘ chord — the gate's own (WPM, spots, band map,
    /// exports, hints, the VFO) and SwiftUI's (⌘R, ⇧⌘S, ⌘Z…) alike — and F12,
    /// which wipes an entry that is empty while the loop runs. Two ⌘ chords
    /// are not: ⌘Esc, because Esc means stop whatever rides with it, and a
    /// ⌘F-key, which falls through to the message table and must still take
    /// the CQ off the air before it sends. N1MM names only "a call-sign, or
    /// … Escape" as what stops a repeat, and this is that rule with the
    /// keys this app has.
    /// `.editMessage` counts as a shortcut for the same reason `.clearEntry`
    /// does: it opens an editor and transmits nothing, so there is no reason
    /// to take a CQ off the air for it. ⇧⌘V, which opens the same sheet, has
    /// always been treated this way.
    static func isShortcut(
        keyCode: UInt16, command: Bool, shift: Bool = false, option: Bool = false
    ) -> Bool {
        switch action(keyCode: keyCode, command: command, shift: shift, option: option) {
        case .abortTransmission, .sendMessage: return false
        case .clearEntry, .editMessage: return true
        default: return command
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
        /// Pause a running repeat-CQ loop. The mode stays armed — F1 starts
        /// it again (`RepeatCQPolicy`); only the toggle itself disengages.
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

    /// While a repeat-CQ loop is running, every key that is not a shortcut
    /// does what Esc does: the operator has started answering someone, and
    /// the half-sent CQ must come off the air mid-character rather than talk
    /// over him. A key that has its own job still does it afterwards, so F2
    /// replaces the CQ instead of queueing behind it, and a letter is left
    /// unconsumed so it still lands in the call field. A shortcut (`isShortcut`
    /// — ⌘= for the speed, ⌘B for the band map, ⌘R…) does its job and leaves
    /// the loop and the CQ alone.
    ///
    /// With no repeat running nothing is aborted but Esc — typing the next call
    /// while an F2 exchange goes out must let the exchange finish.
    static func response(
        keyCode: UInt16,
        command: Bool,
        shift: Bool = false,
        option: Bool = false,
        focus: Focus,
        repeatRunning: Bool
    ) -> Response {
        // Another document, the dashboard, or no window at all: not ours to
        // stop, abort, or consume.
        guard focus != .elsewhere else { return Response() }

        var response = Response()
        if repeatRunning,
           !isShortcut(keyCode: keyCode, command: command, shift: shift, option: option) {
            response.stopsRepeat = true
            response.abortsTransmission = true
        }

        let mapped = action(keyCode: keyCode, command: command, shift: shift, option: option)
        if mapped == .abortTransmission { response.abortsTransmission = true }

        // A sheet owns the keyboard: the abort above still stands, but the key
        // is never consumed and no action is dispatched, so Esc also closes the
        // sheet and F1–F8 cannot key a macro that is being edited.
        guard focus == .document else { return response }

        if let mapped, mapped != .abortTransmission { response.action = mapped }
        response.consumesEvent = mapped != nil
        return response
    }

    /// One press of ⌘= / ⌘-, in WPM; ⇧ makes it the coarse step.
    static let wpmStep = 1
    static let wpmCoarseStep = 2

    private static func commandAction(keyCode: UInt16, shift: Bool, option: Bool = false) -> Action? {
        switch keyCode {
        // '=' / keypad '+' and '-' / keypad '-': the speed by one, or by two
        // with ⇧ (⇧= is how '+' arrives) — 2026-08-16, asked for by name.
        case 24, 69: return .adjustWPM(by: shift ? wpmCoarseStep : wpmStep)
        case 27, 78: return .adjustWPM(by: shift ? -wpmCoarseStep : -wpmStep)
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
        // ⌘B shows and hides the map; ⇧⌘B bolts it to the window, or sets it
        // free (2026-08-22).
        case 11: return shift ? .toggleBandMapBolt : .toggleBandMap  // 'b'
        // ⇧ and ⌥ distinguish this chord. In the toolbar's Export menu these
        // are badge text; the gate is what actually fires them.
        case 14: return option ? .exportPota : (shift ? .exportCabrillo : .exportADIF)  // 'e'
        // ⌘/ — shortcut hints. Also Help › Keyboard Shortcut Hints, which is
        // what answers it from a sheet or the dashboard, where the gate does
        // not consume it. (⌘? is macOS's own Help-menu search.)
        case 44: return .toggleShortcutHints  // '/'
        // ⇧⌘L — the whole log to RUMlogNG again. Only with ⇧: ⌘L alone is
        // left free, and a plain L is a letter in a callsign.
        case 37 where shift: return .sendLogToRUMlog  // 'l'
        default: return nil
        }
    }
}
