import Foundation

/// Which radio in the Elecraft family answered. The one place a per-model
/// difference lives, because the memory count, the play sequence and the CW
/// keying path all depend on it.
enum ElecraftModel: Equatable, Sendable {
    case k3
    case kx3
    case kx2

    /// Whether this is one of the two portables. They share a switch map, a
    /// memory count and a keying path, so almost every decision is this
    /// question rather than which of the two answered.
    var isKX: Bool { self == .kx2 || self == .kx3 }
}

/// The Elecraft CAT protocol itself: the byte strings the family speaks, and
/// the parsers for what it says back. ASCII commands terminated with `;`,
/// 38400-8N1 by default.
///
/// Verified against the Elecraft **Programmer's Reference revisions F2 and G5**
/// (identical for these commands), banked as
/// `docs/research/k3_programmers_reference_g5.txt`.
///
/// Pure and stateless on purpose. Two drivers speak this protocol over the same
/// wire and differ only in what they do with it — a K3/K3S is keyed on its own
/// control lines, a KX3/KX2 through the radio's keyer (Article 11, and
/// `docs/research/kx_cw_keying.md` for why) — so everything neither of them
/// owns exclusively lives here, where one test proves it for both.
enum ElecraftProtocol {

    static let baudRates = [4800, 9600, 19200, 38400]

    // MARK: Commands (pure builders — unit tested)

    static let cmdPollIF = "IF;"
    static let cmdPollKS = "KS;"
    static let cmdAutoInfoOff = "AI0;"
    static let cmdExtendedMode = "K31;"
    static let cmdPollOptions = "OM;"
    static let cmdPollIcons = "IC;"

    /// Sent once when the link opens. AI0 = deterministic polling; K31 = K3
    /// extended response mode; OM = which model answered and which option
    /// modules are fitted.
    static let setupCommands = cmdAutoInfoOff + cmdExtendedMode + cmdPollOptions

    /// IF = freq/mode/TX; KS = keyer speed; IC = icons, which carry the voice
    /// playback flag and the message bank.
    static let pollCommands = cmdPollIF + cmdPollKS + cmdPollIcons

    /// `RX` — "Terminates transmit in all modes, including message play and
    /// repeating messages" (Pgmrs Ref G5). One command, three jobs: it stops a
    /// voice memory playing, it unkeys after a recording from the Mac, and on a
    /// radio keyed through its own keyer it aborts CW.
    static let cmdReceive = "RX;"
    /// `TX` — "Same as activating PTT or using the XMIT switch. Applies to all
    /// modes except direct data, i.e. FSK-D and PSK-D" (Pgmrs Ref G5). Sent by
    /// the sound-card player before a recording, never at connect.
    static let cmdTransmit = "TX;"

    static func cmdSetFrequency(hz: Int) -> String {
        String(format: "FA%011d;", max(0, hz))
    }

    /// `KSnnn;` — "nnn is 008-050 (8-50 WPM)" (Pgmrs Ref G5), which is exactly
    /// the clamp.
    static func cmdSetKeyerSpeed(wpm: Int) -> String {
        String(format: "KS%03d;", min(50, max(8, wpm)))
    }

    /// MD command for an app mode; "SSB" resolves to the conventional
    /// sideband for the frequency (USB at/above 10 MHz, LSB below).
    ///
    /// `model` decides exactly one thing. G5's `MD` entry says "FM mode does
    /// not apply to the KX2", so a KX2 is never sent `MD4` — the same shape as
    /// the QMX driver refusing to emit a mode digit its radio does not have.
    /// It defaults to the model that has every mode, so the K3's callers and
    /// their tests are unaffected.
    static func cmdSetMode(rawMode: String, frequencyHz: Int, model: ElecraftModel = .k3) -> String? {
        let digit: Character? = switch rawMode.uppercased() {
        case "CW": "3"
        case "USB": "2"
        case "LSB": "1"
        case "SSB": frequencyHz >= 10_000_000 ? "2" : "1"
        case "RTTY", "DIGI": "6"
        case "AM": "5"
        case "FM": model == .kx2 ? nil : "4"
        default: nil
        }
        return digit.map { "MD\($0);" }
    }

    // MARK: Response parsing (pure — unit tested)

    /// `IF[f]*****+yyyyrx*00tmvspbd1*;` — freq at [2..12], TX flag at 28, mode at 29.
    static func parseIF(_ response: String) -> RadioState? {
        let chars = Array(response)
        guard chars.count >= 31, chars[0] == "I", chars[1] == "F" else { return nil }
        guard let freq = Int(String(chars[2..<13])) else { return nil }
        guard let mode = K3Mode(rawValue: chars[29]) else { return nil }
        return RadioState(
            frequencyHz: freq,
            rawMode: mode.rawMode,
            isTransmitting: chars[28] == "1"
        )
    }

    /// `FAnnnnnnnnnnn;` → Hz.
    static func parseFA(_ response: String) -> Int? {
        guard response.hasPrefix("FA"), response.count >= 13 else { return nil }
        return Int(String(Array(response)[2..<13]))
    }

    /// `MDn;` → mode.
    static func parseMD(_ response: String) -> K3Mode? {
        guard response.hasPrefix("MD"), response.count >= 3 else { return nil }
        return K3Mode(rawValue: Array(response)[2])
    }

    /// `KSnnn;` → WPM.
    static func parseKS(_ response: String) -> Int? {
        guard response.hasPrefix("KS"), response.count >= 5 else { return nil }
        return Int(String(Array(response)[2..<5]))
    }

    /// `OM` — installed option modules, and on the KX models a product
    /// identifier. Both variants carry a 12-character field; the reference
    /// prints the K3 example with a space after `OM`, so one is tolerated.
    ///
    /// K3/K3S: `APXSDFfLVR--`, index 4 = `D` when the KDVR3 recorder is fitted.
    /// KX3/KX2: `APF---TBXI0n`, where `0n` is `01` for a KX2 and `02` for a KX3
    /// — neither has a `D` position, because the recorder is built in.
    ///
    /// **The KX branch also insists index 4 is not `D`, which the discriminator
    /// does not strictly need.** The reference reserves the K3's trailing dashes
    /// "for future module letters and product ID", so a later K3 could report an
    /// identifier where only a KX reports one today. The two families play a
    /// memory with different command sequences — and are now keyed by different
    /// drivers — so a K3 read as a KX would be sent bytes from the wrong table.
    /// No KX can carry a `D` at index 4 — it is a reserved dash there — so this
    /// rejects nothing real, and it keeps a recorder-equipped K3 resolving as a
    /// K3 whatever lands in 10–11.
    static func parseOM(_ response: String) -> (model: ElecraftModel, voice: VoiceKeyerStatus)? {
        guard response.hasPrefix("OM") else { return nil }
        var body = response.dropFirst(2)
        if body.hasSuffix(";") { body = body.dropLast() }
        let field = Array(body.trimmingCharacters(in: .whitespaces))
        guard field.count >= 12 else { return nil }

        if field[4] != "D", field[10] == "0" {
            if field[11] == "1" { return (.kx2, .available(count: 2)) }
            if field[11] == "2" { return (.kx3, .available(count: 2)) }
        }
        return (.k3, field[4] == "D" ? .available(count: 8) : .notInstalled)
    }

    /// `ICabcde;` — five 8-bit flag bytes. Byte a bit B2 is "MSG is playing"
    /// and bit B3 is the message bank (0 = bank 1). B7 is always 1 so that no
    /// control character reaches the host, which is why this reads unicode
    /// scalar values rather than `asciiValue`: the transport decodes ISO
    /// Latin-1, so every byte becomes exactly one scalar in 0x00...0xFF.
    ///
    /// The bank is meaningful only on a K3; a KX has no message banks and its
    /// caller ignores that half.
    static func parseIC(_ response: String) -> (playing: Bool, bank: Int)? {
        let scalars = Array(response.unicodeScalars)
        guard scalars.count >= 8, scalars[0] == "I", scalars[1] == "C" else { return nil }
        let a = scalars[2].value
        return (playing: (a >> 2) & 1 == 1, bank: (a >> 3) & 1 == 1 ? 2 : 1)
    }
}
