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

    /// Network CAT (FlexRadio): host/IP and TCP port.
    var tcpHost: String {
        didSet { defaults.set(tcpHost, forKey: "tcpHost") }
    }

    var tcpPort: Int {
        didSet { defaults.set(tcpPort, forKey: "tcpPort") }
    }

    /// DX cluster (spots) connection.
    var clusterHost: String {
        didSet { defaults.set(clusterHost, forKey: "clusterHost") }
    }

    var clusterPort: Int {
        didSet { defaults.set(clusterPort, forKey: "clusterPort") }
    }

    /// Connect to the cluster automatically when a contest opens.
    var clusterAutoConnect: Bool {
        didSet { defaults.set(clusterAutoConnect, forKey: "clusterAutoConnect") }
    }

    /// Previously used nodes, most recent first ("host:port").
    var clusterHistory: [String] {
        didSet { defaults.set(clusterHistory, forKey: "clusterHistory") }
    }

    /// Commands sent right after login, one per line. `sh/dx` backfills the
    /// band map with recent spots instead of waiting for new ones.
    var clusterCommands: String {
        didSet { defaults.set(clusterCommands, forKey: "clusterCommands") }
    }

    /// Hide spots posted by non-North-American spotters — in a stateside QSO
    /// party, EU/JA skimmer spots are noise.
    var northAmericanSpottersOnly: Bool {
        didSet { defaults.set(northAmericanSpottersOnly, forKey: "northAmericanSpottersOnly") }
    }

    /// Hide spots *of* stations outside North America — DX isn't workable
    /// exchange in a state QSO party.
    var northAmericanStationsOnly: Bool {
        didSet { defaults.set(northAmericanStationsOnly, forKey: "northAmericanStationsOnly") }
    }

    /// Hide stations already worked on the current band and mode.
    var hideWorkedSpots: Bool {
        didSet { defaults.set(hideWorkedSpots, forKey: "hideWorkedSpots") }
    }

    /// Hide automated RBN / skimmer spots.
    var hideSkimmerSpots: Bool {
        didSet { defaults.set(hideSkimmerSpots, forKey: "hideSkimmerSpots") }
    }

    /// Drop spots older than this (minutes) — contest spots go stale fast.
    var spotMaxAgeMinutes: Int {
        didSet { defaults.set(spotMaxAgeMinutes, forKey: "spotMaxAgeMinutes") }
    }

    /// Mode classes to show; empty means every mode.
    var spotModes: Set<ModeClass> {
        didSet { defaults.set(spotModes.map(\.rawValue), forKey: "spotModes") }
    }

    /// Bands to show; empty means every band.
    var spotBands: Set<Band> {
        didSet { defaults.set(spotBands.map(\.rawValue), forKey: "spotBands") }
    }

    /// The spot filters as the engine wants them. `workedCalls` is supplied
    /// by the caller, which is the only part that isn't a stored preference.
    func spotFilterOptions(workedCalls: Set<String>) -> SpotFilter.Options {
        SpotFilter.Options(
            northAmericanSpottersOnly: northAmericanSpottersOnly,
            northAmericanStationsOnly: northAmericanStationsOnly,
            hideWorked: hideWorkedSpots,
            hideSkimmer: hideSkimmerSpots,
            modes: spotModes,
            bands: spotBands,
            workedCalls: workedCalls
        )
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

    /// Send cut numbers in the {RST} macro when keying CW (599 → 5NN).
    var cwCutNumbers: Bool {
        didSet { defaults.set(cwCutNumbers, forKey: "cwCutNumbers") }
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
        tcpHost = defaults.string(forKey: "tcpHost") ?? ""
        tcpPort = defaults.object(forKey: "tcpPort") as? Int ?? Int(FlexRadioDriver.defaultPort)
        clusterHost = defaults.string(forKey: "clusterHost") ?? ""
        clusterPort = defaults.object(forKey: "clusterPort") as? Int ?? 7300
        clusterAutoConnect = defaults.object(forKey: "clusterAutoConnect") as? Bool ?? false
        clusterHistory = defaults.stringArray(forKey: "clusterHistory") ?? []
        clusterCommands = defaults.string(forKey: "clusterCommands") ?? "sh/dx 30"
        northAmericanSpottersOnly = defaults.object(forKey: "northAmericanSpottersOnly") as? Bool ?? false
        northAmericanStationsOnly = defaults.object(forKey: "northAmericanStationsOnly") as? Bool ?? false
        hideWorkedSpots = defaults.object(forKey: "hideWorkedSpots") as? Bool ?? false
        hideSkimmerSpots = defaults.object(forKey: "hideSkimmerSpots") as? Bool ?? false
        spotMaxAgeMinutes = defaults.object(forKey: "spotMaxAgeMinutes") as? Int ?? 15
        spotModes = Set((defaults.stringArray(forKey: "spotModes") ?? []).compactMap(ModeClass.init(rawValue:)))
        spotBands = Set((defaults.stringArray(forKey: "spotBands") ?? []).compactMap(Band.init(rawValue:)))
        wpm = defaults.object(forKey: "wpm") as? Int ?? 22
        keyerBackend = KeyerBackend(rawValue: defaults.string(forKey: "keyerBackend") ?? "") ?? .direct
        keyerLineConfig = (defaults.data(forKey: "keyerLineConfig")
            .flatMap { try? JSONDecoder().decode(KeyerLineConfig.self, from: $0) })
            ?? KeyerLineConfig()
        esmEnabled = defaults.object(forKey: "esmEnabled") as? Bool ?? false
        cwCutNumbers = defaults.object(forKey: "cwCutNumbers") as? Bool ?? false
        repeatIntervalSeconds = defaults.object(forKey: "repeatIntervalSeconds") as? Double ?? 3.0
        lastStationProfile = defaults.data(forKey: "lastStationProfile")
            .flatMap { try? JSONDecoder().decode(StationProfile.self, from: $0) }
    }

    /// CW cut numbers for signal reports: 9→N, 0→T (599 → 5NN). Applied only
    /// to the {RST} value — callsigns and exchanges are never altered.
    static func applyCutNumbers(_ value: String) -> String {
        String(value.map { c -> Character in
            switch c {
            case "9": "N"
            case "0": "T"
            default: c
            }
        })
    }

    /// Expand message macros against current entry state.
    static func expandMacros(
        _ template: String,
        myCall: String,
        call: String,
        rst: String,
        exchange: String,
        cutNumbers: Bool = false
    ) -> String {
        template
            .replacingOccurrences(of: "{MYCALL}", with: myCall)
            .replacingOccurrences(of: "{CALL}", with: call)
            .replacingOccurrences(of: "{RST}", with: cutNumbers ? applyCutNumbers(rst) : rst)
            .replacingOccurrences(of: "{EXCH}", with: exchange)
            .trimmingCharacters(in: .whitespaces)
    }
}
