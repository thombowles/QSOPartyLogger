import Foundation

/// The pure half of the key trace: names for what the monitor saw, the
/// decoding of a media key, and the one notice the messages row raises when
/// an F-key arrives as something else.
///
/// Why this exists: on 2026-08-15, mid-NAQP SSB, "the F-keys do nothing but
/// the buttons work". The app's own path from key down to the radio was
/// proven sound in isolation, which left the keyboard — a Keychron whose F
/// row is multimedia by default (brightness, Mission Control, backlight…) —
/// as the likeliest cause, and no way for the operator to *see* that. So
/// every decision the monitor makes is logged, and a media key that lands
/// where F1–F8 were expected says so, inline, with the fix.
///
/// Everything here is a pure function of numbers the monitor already has;
/// `KeyMonitorGate` decides, this describes.
enum KeyDiagnostics {

    // MARK: Names

    /// What a key down is called — F-keys, arrows, punctuation, the letters —
    /// so a trace or a readout says "F1", not "122". Unknown codes are still
    /// named, by number, rather than dropped.
    static func keyName(keyCode: UInt16) -> String {
        if let name = names[keyCode] { return name }
        return "key \(keyCode)"
    }

    /// "⇧⌘E" — modifiers in the menu bar's order, then the key.
    static func chordName(keyCode: UInt16, command: Bool, shift: Bool) -> String {
        (shift ? "⇧" : "") + (command ? "⌘" : "") + keyName(keyCode: keyCode)
    }

    private static let names: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N",
        46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Esc",
        69: "keypad +", 76: "keypad Enter", 78: "keypad -",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        109: "F10", 111: "F12", 118: "F4", 120: "F2", 122: "F1",
        115: "Home", 116: "Page Up", 117: "Forward Delete", 119: "End", 121: "Page Down",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        // The system's own function-row keys. An Apple keyboard with the
        // standard-function-keys switch off, or a third-party board in its
        // multimedia mode, sends these where F3/F4 would be.
        160: "Mission Control", 131: "Launchpad",
    ]

    /// Which F-key position a system key down sits on, when it is one of the
    /// two that arrive as ordinary key downs rather than media keys.
    private static let systemKeyFRow: [UInt16: String] = [160: "F3", 131: "F4"]

    // MARK: Media keys

    /// One press of a key the system treats as an auxiliary control —
    /// brightness, backlight, transport, volume. These arrive as
    /// `NSEvent.systemDefined` events with subtype 8, never as key downs.
    struct MediaKey: Equatable {
        enum Kind: Equatable {
            case soundUp, soundDown, mute
            case brightnessUp, brightnessDown
            case illuminationUp, illuminationDown, illuminationToggle
            case play, next, previous, fast, rewind
            case other(Int)

            /// IOKit's `NX_KEYTYPE_*` values (ev_keymap.h).
            init(auxKeyType: Int) {
                switch auxKeyType {
                case 0: self = .soundUp
                case 1: self = .soundDown
                case 2: self = .brightnessUp
                case 3: self = .brightnessDown
                case 7: self = .mute
                case 16: self = .play
                case 17: self = .next
                case 18: self = .previous
                case 19: self = .fast
                case 20: self = .rewind
                case 21: self = .illuminationUp
                case 22: self = .illuminationDown
                case 23: self = .illuminationToggle
                default: self = .other(auxKeyType)
                }
            }

            var name: String {
                switch self {
                case .soundUp: "Volume ▲"
                case .soundDown: "Volume ▼"
                case .mute: "Mute"
                case .brightnessUp: "Brightness ▲"
                case .brightnessDown: "Brightness ▼"
                case .illuminationUp: "Keyboard backlight ▲"
                case .illuminationDown: "Keyboard backlight ▼"
                case .illuminationToggle: "Keyboard backlight"
                case .play: "Play/Pause"
                case .next: "Next track"
                case .previous: "Previous track"
                case .fast: "Fast forward"
                case .rewind: "Rewind"
                case .other(let type): "media key \(type)"
                }
            }

            /// Where the key sits on an Apple-layout F row (which Keychron and
            /// most Mac-mode third-party boards copy). Only the positions the
            /// app's own keys occupy — F1–F8 — matter; volume is F10–F12 and
            /// gets no position, so no notice.
            var fRowPosition: String? {
                switch self {
                case .brightnessDown: "F1"
                case .brightnessUp: "F2"
                case .illuminationDown: "F5"
                case .illuminationUp: "F6"
                case .previous, .rewind: "F7"
                case .play: "F8"
                default: nil
                }
            }
        }

        var kind: Kind
        var isDown: Bool

        var name: String { kind.name }
    }

    /// Decode a `.systemDefined` event's `subtype`/`data1`. Subtype 8 is the
    /// aux-control-buttons subtype; `data1` carries the key type in the high
    /// 16 bits and the state (0xA down, 0xB up) in bits 8–15.
    static func mediaKey(subtype: Int, data1: Int) -> MediaKey? {
        guard subtype == 8 else { return nil }
        let type = (data1 & 0xFFFF_0000) >> 16
        let state = (data1 & 0x0000_FF00) >> 8
        return MediaKey(kind: .init(auxKeyType: type), isDown: state == 0xA)
    }

    // MARK: The F-row notice

    /// The line under the messages row when an F-key position arrives as a
    /// media key. Nil for a key up, and for keys off the F1–F8 positions.
    static func fRowNotice(for key: MediaKey) -> String? {
        guard key.isDown, let position = key.kind.fRowPosition else { return nil }
        return fRowNotice(position: position, arrivedAs: key.name)
    }

    /// The same, for the two system keys that arrive as key downs.
    static func fRowNotice(forKeyCode keyCode: UInt16) -> String? {
        guard let position = systemKeyFRow[keyCode] else { return nil }
        return fRowNotice(position: position, arrivedAs: keyName(keyCode: keyCode))
    }

    private static func fRowNotice(position: String, arrivedAs name: String) -> String {
        "\(position) arrived as \(name) — the keyboard's F row is in multimedia mode, so F1–F12 "
            + "never reach the logger. Keychron and similar boards: hold fn + X + L for 4 s "
            + "(older firmware: fn + K + C for 3 s), or press fn with the F-key. Apple keyboards: "
            + "System Settings › Keyboard › Keyboard Shortcuts… › Function Keys."
    }

    // MARK: Trace and readout

    /// One line per key down the monitor ruled on, for the unified log:
    /// `log show --predicate 'subsystem == "org.b5n.QSOPartyLogger"' --last 10m`.
    static func traceLine(
        keyCode: UInt16, command: Bool, shift: Bool,
        focus: KeyMonitorGate.Focus, response: KeyMonitorGate.Response
    ) -> String {
        let action = response.action.map { String(describing: $0) } ?? "—"
        let fate = response.consumesEvent ? "consumed" : "passed on"
        let extras = (response.stopsRepeat ? " stops repeat" : "")
            + (response.abortsTransmission ? " aborts TX" : "")
        return "\(chordName(keyCode: keyCode, command: command, shift: shift)) (\(keyCode)) "
            + "focus=\(focus) → \(action) \(fate)\(extras)"
    }

    /// The legend's "last key" line: the chord and what it did, in words.
    static func lastKeyReadout(
        keyCode: UInt16, command: Bool, shift: Bool, action: KeyMonitorGate.Action?
    ) -> String {
        "\(chordName(keyCode: keyCode, command: command, shift: shift)) — \(describe(action))"
    }

    static func describe(_ action: KeyMonitorGate.Action?) -> String {
        guard let action else { return "not a shortcut" }
        switch action {
        case .adjustWPM(let delta): return "WPM \(delta > 0 ? "+" : "")\(delta)"
        case .previousSpot: return "previous spot"
        case .nextSpot: return "next spot"
        case .jumpToCQFrequency: return "CQ frequency"
        case .toggleBandMap: return "band map"
        case .sendMessage(let index): return "message F\(index + 1)"
        case .clearEntry: return "clear entry"
        case .abortTransmission: return "abort"
        case .exportADIF: return "export ADIF"
        case .exportCabrillo: return "export Cabrillo"
        case .nudgeVFO(let hz): return "VFO \(hz > 0 ? "+" : "")\(hz) Hz"
        }
    }
}
