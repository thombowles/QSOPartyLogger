import Foundation
import Observation

/// Machine-level preferences (radio wiring, messages, last profile) —
/// contest data lives in the document.
@Observable
final class AppSettings {
    @MainActor static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    var radioID: String {
        didSet { defaults.set(radioID, forKey: "radioID") }
    }

    var portPath: String {
        didSet { defaults.set(portPath, forKey: "portPath") }
    }

    var baudRate: Int {
        didSet { defaults.set(baudRate, forKey: "baudRate") }
    }

    var wpm: Int {
        didSet { defaults.set(wpm, forKey: "wpm") }
    }

    enum KeyerBackend: String, Codable, CaseIterable {
        case direct = "Direct DTR/RTS"
        case radioInternal = "K3 internal (KY)"
    }

    var keyerBackend: KeyerBackend {
        didSet { defaults.set(keyerBackend.rawValue, forKey: "keyerBackend") }
    }

    var keyerLineConfig: KeyerLineConfig {
        didSet {
            if let data = try? JSONEncoder().encode(keyerLineConfig) {
                defaults.set(data, forKey: "keyerLineConfig")
            }
        }
    }

    /// Enter Sends Message (N1MM-style ESM): Return sends the contextually
    /// next message instead of only logging.
    var esmEnabled: Bool {
        didSet { defaults.set(esmEnabled, forKey: "esmEnabled") }
    }

    /// Gap between repeat-CQ transmissions, in seconds.
    var repeatIntervalSeconds: Double {
        didSet { defaults.set(repeatIntervalSeconds, forKey: "repeatIntervalSeconds") }
    }

    var lastStationProfile: StationProfile? {
        didSet {
            if let profile = lastStationProfile,
               let data = try? JSONEncoder().encode(profile) {
                defaults.set(data, forKey: "lastStationProfile")
            }
        }
    }

    init() {
        radioID = defaults.string(forKey: "radioID") ?? "elecraft-k3"
        portPath = defaults.string(forKey: "portPath") ?? ""
        baudRate = defaults.object(forKey: "baudRate") as? Int ?? 38400
        wpm = defaults.object(forKey: "wpm") as? Int ?? 22
        keyerBackend = KeyerBackend(rawValue: defaults.string(forKey: "keyerBackend") ?? "") ?? .direct
        keyerLineConfig = (defaults.data(forKey: "keyerLineConfig")
            .flatMap { try? JSONDecoder().decode(KeyerLineConfig.self, from: $0) })
            ?? KeyerLineConfig()
        esmEnabled = defaults.object(forKey: "esmEnabled") as? Bool ?? false
        repeatIntervalSeconds = defaults.object(forKey: "repeatIntervalSeconds") as? Double ?? 3.0
        lastStationProfile = defaults.data(forKey: "lastStationProfile")
            .flatMap { try? JSONDecoder().decode(StationProfile.self, from: $0) }
    }

    /// Expand message macros against current entry state.
    static func expandMacros(
        _ template: String,
        myCall: String,
        call: String,
        rst: String,
        exchange: String
    ) -> String {
        template
            .replacingOccurrences(of: "{MYCALL}", with: myCall)
            .replacingOccurrences(of: "{CALL}", with: call)
            .replacingOccurrences(of: "{RST}", with: rst)
            .replacingOccurrences(of: "{EXCH}", with: exchange)
            .trimmingCharacters(in: .whitespaces)
    }
}
