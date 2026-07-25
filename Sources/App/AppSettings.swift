import Foundation
import Observation

/// Machine-level preferences (radio wiring, messages, last profile) —
/// contest data lives in the document.
@Observable
final class AppSettings {
    @MainActor static let shared = AppSettings()

    private let defaults: UserDefaults

    var radioID: String {
        didSet { defaults.set(radioID, forKey: "radioID") }
    }

    var portPath: String {
        didSet { defaults.set(portPath, forKey: "portPath") }
    }

    var baudRate: Int {
        didSet { defaults.set(baudRate, forKey: "baudRate") }
    }

    /// Network CAT (radios reached over TCP): host/IP and port.
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

    /// Drop cluster spots older than this (minutes) — they go stale fast.
    var spotMaxAgeMinutes: Int {
        didSet { defaults.set(spotMaxAgeMinutes, forKey: "spotMaxAgeMinutes") }
    }

    /// The same for hub spots, which are hand-posted rather than skimmer-fed
    /// and stay useful much longer. The hub itself keeps them an hour, and at
    /// the cluster's 15 minutes a typical hub table empties on arrival.
    var hubSpotMaxAgeMinutes: Int {
        didSet { defaults.set(hubSpotMaxAgeMinutes, forKey: "hubSpotMaxAgeMinutes") }
    }

    /// Poll qsopartyhub.com for the active party, when the hub serves it.
    var hubSpotsEnabled: Bool {
        didSet { defaults.set(hubSpotsEnabled, forKey: "hubSpotsEnabled") }
    }

    /// Offer a hub spot's county in the exchange field when tuning to it.
    /// The value arrives marked unconfirmed — it is a spotter's claim, not
    /// something copied off the air.
    var prefillExchangeFromSpots: Bool {
        didSet { defaults.set(prefillExchangeFromSpots, forKey: "prefillExchangeFromSpots") }
    }

    /// Feeds to show on the band map; empty means every feed.
    var spotSources: Set<SpotSource> {
        didSet { defaults.set(spotSources.map(\.rawValue), forKey: "spotSources") }
    }

    /// Switch the radio between CW and SSB to match the band plan when the app
    /// moves the frequency. Never applies to the VFO knob — see
    /// `BandPlan` and `MainView.applyBandPlanMode`.
    var followBandPlan: Bool {
        didSet { defaults.set(followBandPlan, forKey: "followBandPlan") }
    }

    /// Mode classes to show; empty means every mode.
    var spotModes: Set<ModeClass> {
        didSet { defaults.set(spotModes.map(\.rawValue), forKey: "spotModes") }
    }

    /// Bands to show; empty means every band.
    var spotBands: Set<Band> {
        didSet { defaults.set(spotBands.map(\.rawValue), forKey: "spotBands") }
    }

    /// The spot filters as the engine wants them. `workedCalls` and
    /// `allowedModes` are supplied by the caller — they come from the log and
    /// the active party, not from stored preferences.
    func spotFilterOptions(
        workedCalls: Set<String>,
        allowedModes: [ModeClass] = [],
        workedCallCounties: Set<String> = []
    ) -> SpotFilter.Options {
        SpotFilter.Options(
            northAmericanSpottersOnly: northAmericanSpottersOnly,
            northAmericanStationsOnly: northAmericanStationsOnly,
            hideWorked: hideWorkedSpots,
            hideSkimmer: hideSkimmerSpots,
            modes: spotModes,
            bands: spotBands,
            allowedModes: allowedModes,
            sources: spotSources,
            workedCalls: workedCalls,
            workedCallCounties: workedCallCounties
        )
    }

    var wpm: Int {
        didSet { defaults.set(wpm, forKey: "wpm") }
    }

    enum KeyerBackend: String, Codable, CaseIterable {
        // The raw values are the persisted `keyerBackend` tokens in
        // UserDefaults, frozen verbatim from when they doubled as labels.
        // They are storage, never display: changing one silently resets an
        // existing operator's keyer choice to `.direct` on next launch.
        // Labels come from `displayName(for:)`.
        case direct = "Direct DTR/RTS"
        case radioInternal = "K3 internal (KY)"

        /// Shown when the internal keyer's owner isn't known yet — no radio
        /// connected, so nothing can name its command.
        static let neutralRadioKeyerLabel = "Radio keyer"

        /// Label for the keyer picker. The internal-keyer case takes its name
        /// from the connected radio's descriptor, so the setting never claims
        /// one manufacturer's command while another radio is sending
        /// (Article 11).
        func displayName(for descriptor: RadioDescriptor?) -> String {
            switch self {
            case .direct: "Direct DTR/RTS"
            case .radioInternal: descriptor?.keyerLabel ?? Self.neutralRadioKeyerLabel
            }
        }
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

    /// Send cut numbers when keying CW: 0→T and 9→N, in both the {RST} and
    /// {SERIAL} macros (599 → 5NN, 40 → 4T). (See `cwCutNumberOne`.)
    var cwCutNumbers: Bool {
        didSet { defaults.set(cwCutNumbers, forKey: "cwCutNumbers") }
    }

    /// Also cut 1→A. Opt-in and off by default: 1→A has real currency in
    /// contest CW but is not universal, and a number cut in a way the
    /// receiving operator does not expect costs a repeat. A second Bool
    /// rather than folding both into an enum, because `cwCutNumbers` is a live
    /// UserDefaults token — migrating it would silently reset the choice of
    /// anyone who had already turned cut numbers on.
    var cwCutNumberOne: Bool {
        didSet { defaults.set(cwCutNumberOne, forKey: "cwCutNumberOne") }
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

    /// `defaults` is injected so a test can exercise settings against a scratch
    /// suite. It defaults to `Preferences.store`, which is `.standard` in the
    /// app — production behaviour is unchanged.
    init(defaults: UserDefaults = Preferences.store) {
        self.defaults = defaults
        radioID = defaults.string(forKey: "radioID") ?? RadioRegistry.defaultRadioID
        portPath = defaults.string(forKey: "portPath") ?? ""
        baudRate = defaults.object(forKey: "baudRate") as? Int ?? RadioRegistry.defaultBaud
        tcpHost = defaults.string(forKey: "tcpHost") ?? ""
        // 0 only in a serial-only catalog, where the host/port fields are never
        // shown; `RadioController.connect` substitutes the connected radio's
        // own port for any value outside 1...65535 regardless.
        tcpPort = defaults.object(forKey: "tcpPort") as? Int
            ?? RadioRegistry.defaultNetworkPort.map { Int($0) } ?? 0
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
        hubSpotMaxAgeMinutes = defaults.object(forKey: "hubSpotMaxAgeMinutes") as? Int ?? 60
        hubSpotsEnabled = defaults.object(forKey: "hubSpotsEnabled") as? Bool ?? true
        prefillExchangeFromSpots =
            defaults.object(forKey: "prefillExchangeFromSpots") as? Bool ?? true
        spotSources = Set((defaults.stringArray(forKey: "spotSources") ?? [])
            .compactMap(SpotSource.init(rawValue:)))
        followBandPlan = defaults.object(forKey: "followBandPlan") as? Bool ?? true
        spotModes = Set((defaults.stringArray(forKey: "spotModes") ?? []).compactMap(ModeClass.init(rawValue:)))
        spotBands = Set((defaults.stringArray(forKey: "spotBands") ?? []).compactMap(Band.init(rawValue:)))
        wpm = defaults.object(forKey: "wpm") as? Int ?? 22
        keyerBackend = KeyerBackend(rawValue: defaults.string(forKey: "keyerBackend") ?? "") ?? .direct
        keyerLineConfig = (defaults.data(forKey: "keyerLineConfig")
            .flatMap { try? JSONDecoder().decode(KeyerLineConfig.self, from: $0) })
            ?? KeyerLineConfig()
        esmEnabled = defaults.object(forKey: "esmEnabled") as? Bool ?? false
        cwCutNumbers = defaults.object(forKey: "cwCutNumbers") as? Bool ?? false
        cwCutNumberOne = defaults.object(forKey: "cwCutNumberOne") as? Bool ?? false
        repeatIntervalSeconds = defaults.object(forKey: "repeatIntervalSeconds") as? Double ?? 3.0
        lastStationProfile = defaults.data(forKey: "lastStationProfile")
            .flatMap { try? JSONDecoder().decode(StationProfile.self, from: $0) }
    }

    /// CW cut numbers: 0→T and 9→N always, 1→A when `cutOne` is set
    /// (599 → 5NN, 199 → ANN). Applied to the {RST} and {SERIAL} values only —
    /// callsigns and exchanges are never altered.
    static func applyCutNumbers(_ value: String, cutOne: Bool = false) -> String {
        String(value.map { c -> Character in
            switch c {
            case "9": "N"
            case "0": "T"
            case "1": cutOne ? "A" : c
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
        serial: String = "",
        cutNumbers: Bool = false,
        cutOne: Bool = false
    ) -> String {
        func cut(_ value: String) -> String {
            cutNumbers ? applyCutNumbers(value, cutOne: cutOne) : value
        }
        func value(for token: MacroToken) -> String {
            switch token {
            case .myCall: myCall
            case .call: call
            case .rst: cut(rst)
            // The QSO number, for parties that exchange one instead of a
            // report (CQP). Defaults to empty, so message sets that never
            // mention it expand exactly as before.
            case .serial: cut(serial)
            case .exchange: exchange
            }
        }
        // Iterating the cases rather than chaining one `replacingOccurrences`
        // per token: a new macro is then a new case, and this file stops
        // compiling until the switch above gives it a value — where a
        // forgotten link in a chain would silently key the token literally.
        // `allCases` order is expansion order.
        let expanded = MacroToken.allCases.reduce(template) {
            $0.replacingOccurrences(of: $1.rawValue, with: value(for: $1))
        }
        return expanded.trimmingCharacters(in: .whitespaces)
    }
}
