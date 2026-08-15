import Foundation
import Observation

/// Machine-level preferences (radio wiring, messages, last profile) —
/// contest data lives in the document.
@Observable
final class AppSettings {
    @MainActor static let shared = AppSettings()

    private let defaults: UserDefaults

    /// Whether this settings object persists into `store`. Read-only, so the
    /// test bundle can prove `shared` was built on the redirected store —
    /// i.e. that nothing touched `AppSettings.shared` at app launch, before
    /// `TestBundleSetup` ran — without writing a byte anywhere.
    func isBacked(by store: UserDefaults) -> Bool { defaults === store }

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

    /// The networks the spot sheet opens ticked — remembered from the last
    /// post, per network, so a park weekend and a home weekend each keep
    /// their own habit. Every network by default.
    var spotNetworks: Set<SpotNetwork> {
        didSet { defaults.set(spotNetworks.map(\.rawValue).sorted(), forKey: "spotNetworks") }
    }

    /// Download the active party's N1MM community call history file and offer
    /// what it says a station sends. On by default, like the hub: the file is
    /// fetched at party selection and at most once a day, never mid-contact.
    var callHistoryEnabled: Bool {
        didSet { defaults.set(callHistoryEnabled, forKey: "callHistoryEnabled") }
    }

    /// Super check partial: download MASTER.SCP automatically and show the
    /// known contest calls matching what is typed in the call field. On by
    /// default, like the hub and the call history file — the strip costs
    /// nothing until a fragment is typed.
    var superCheckEnabled: Bool {
        didSet { defaults.set(superCheckEnabled, forKey: "superCheckEnabled") }
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

    /// How big spot labels are drawn on the band map. Eyesight and display
    /// density, so machine-level like the rest of this file rather than saved
    /// into a log. Deliberately outside the funnel popover's **Reset All**,
    /// which is about filters — clearing a band filter should not resize
    /// anyone's text.
    var spotLabelSize: SpotLabelSize {
        didSet { defaults.set(spotLabelSize.rawValue, forKey: "spotLabelSize") }
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

    // There is no keyer-backend preference. Every radio has exactly one way to
    // send CW — its key lines if it has them, its own keyer if it does not
    // (Article 11) — so there was never a second option to pick. The stored
    // `keyerBackend` token is left in UserDefaults, unread and harmless.

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

    // MARK: Voice messages recorded on this Mac

    /// Where phone keys get their audio on a radio that offers both sources.
    /// Recordings by default (Article 11 as amended 2026-08-15); the radio's
    /// own memories are the option, offered only when it reports some.
    var phoneMessageSource: PhoneMessageSource {
        didSet { defaults.set(phoneMessageSource.rawValue, forKey: "phoneMessageSource") }
    }

    /// Microphone for recording; nil = the system default input.
    var voiceInputDeviceUID: String? {
        didSet { defaults.set(voiceInputDeviceUID, forKey: "voiceInputDeviceUID") }
    }

    /// The radio's audio input, for the sound-card path; nil = not chosen,
    /// which leaves that path not ready rather than guessing a device — the
    /// Mac's speakers are never the radio.
    var voiceOutputDeviceUID: String? {
        didSet { defaults.set(voiceOutputDeviceUID, forKey: "voiceOutputDeviceUID") }
    }

    /// Transmit audio level, 0…1, applied to both paths.
    var voiceLevel: Double {
        didSet { defaults.set(voiceLevel, forKey: "voiceLevel") }
    }

    /// How the sound-card path keys the radio.
    var voicePTT: VoicePTTMode {
        didSet { defaults.set(voicePTT.rawValue, forKey: "voicePTT") }
    }

    /// Milliseconds between keying the radio and the first sample, 0…500.
    var voicePTTLeadMs: Int {
        didSet { defaults.set(voicePTTLeadMs, forKey: "voicePTTLeadMs") }
    }

    /// Multiplier roster sections the operator has collapsed, keyed
    /// `"<partyID>.<multClass>"`. Absent means expanded, so a party seen for
    /// the first time shows its whole checklist rather than hiding it.
    var collapsedMultSections: Set<String> {
        didSet { defaults.set(Array(collapsedMultSections), forKey: "collapsedMultSections") }
    }

    /// Show the Advisor section in the score sidebar. On by default: it is
    /// silent until it has something true to say, so an operator who never
    /// wants it never sees it either way.
    var advisorEnabled: Bool {
        didSet { defaults.set(advisorEnabled, forKey: "advisorEnabled") }
    }

    /// Advisor section collapsed to its header (⇧⌘A).
    var advisorCollapsed: Bool {
        didSet { defaults.set(advisorCollapsed, forKey: "advisorCollapsed") }
    }

    /// Advisory kinds the operator never wants to hear from, by raw value.
    var advisorMutedKinds: Set<Advisor.Advisory.Kind> {
        didSet {
            defaults.set(advisorMutedKinds.map(\.rawValue).sorted(), forKey: "advisorMutedKinds")
        }
    }

    /// What the advisor is optimising for (⌥⌘A).
    ///
    /// Global rather than per-log on purpose: a State QSO Party Challenge
    /// season is a season, not a log, and an operator chasing it is chasing it
    /// every weekend. Per-log would mean a `ContestLog` field — revisit only
    /// if the global setting proves wrong in practice.
    var advisorGoal: Advisor.Goal {
        didSet { defaults.set(advisorGoal.rawValue, forKey: "advisorGoal") }
    }

    var lastStationProfile: StationProfile? {
        didSet {
            if let profile = lastStationProfile,
               let data = try? JSONEncoder().encode(profile) {
                defaults.set(data, forKey: "lastStationProfile")
            }
        }
    }

    /// Shortcut hints (⌘/, Help › Keyboard Shortcut Hints): every button
    /// wears its key, and the legend under the messages row lists the keys
    /// that have no button. Global, like the advisor goal — a preference
    /// about the operator, not the log. Off by default: hints are for
    /// learning the keys, not for keeping.
    var showShortcutHints: Bool {
        didSet { defaults.set(showShortcutHints, forKey: "showShortcutHints") }
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
        spotNetworks = defaults.stringArray(forKey: "spotNetworks")
            .map { Set($0.compactMap(SpotNetwork.init(rawValue:))) } ?? Set(SpotNetwork.allCases)
        callHistoryEnabled = defaults.object(forKey: "callHistoryEnabled") as? Bool ?? true
        superCheckEnabled = defaults.object(forKey: "superCheckEnabled") as? Bool ?? true
        spotSources = Set((defaults.stringArray(forKey: "spotSources") ?? [])
            .compactMap(SpotSource.init(rawValue:)))
        collapsedMultSections = Set(defaults.stringArray(forKey: "collapsedMultSections") ?? [])
        advisorEnabled = defaults.object(forKey: "advisorEnabled") as? Bool ?? true
        advisorCollapsed = defaults.object(forKey: "advisorCollapsed") as? Bool ?? false
        advisorMutedKinds = Set(
            (defaults.stringArray(forKey: "advisorMutedKinds") ?? [])
                .compactMap(Advisor.Advisory.Kind.init(rawValue:))
        )
        // An unreadable token falls back to Score rather than to nothing: a
        // hand-edited preference file must never leave the advisor with no
        // yardstick, since every weighting reads one.
        advisorGoal = Advisor.Goal(rawValue: defaults.string(forKey: "advisorGoal") ?? "") ?? .score
        followBandPlan = defaults.object(forKey: "followBandPlan") as? Bool ?? true
        spotModes = Set((defaults.stringArray(forKey: "spotModes") ?? []).compactMap(ModeClass.init(rawValue:)))
        spotBands = Set((defaults.stringArray(forKey: "spotBands") ?? []).compactMap(Band.init(rawValue:)))
        // An unreadable token falls back to the default rather than to nothing:
        // a hand-edited or downgraded preference file must never leave the band
        // map with no label size at all.
        spotLabelSize = SpotLabelSize(rawValue: defaults.string(forKey: "spotLabelSize") ?? "")
            ?? .small
        wpm = defaults.object(forKey: "wpm") as? Int ?? 22
        keyerLineConfig = (defaults.data(forKey: "keyerLineConfig")
            .flatMap { try? JSONDecoder().decode(KeyerLineConfig.self, from: $0) })
            ?? KeyerLineConfig()
        esmEnabled = defaults.object(forKey: "esmEnabled") as? Bool ?? false
        cwCutNumbers = defaults.object(forKey: "cwCutNumbers") as? Bool ?? false
        cwCutNumberOne = defaults.object(forKey: "cwCutNumberOne") as? Bool ?? false
        repeatIntervalSeconds = defaults.object(forKey: "repeatIntervalSeconds") as? Double ?? 3.0
        // Unreadable tokens fall back to the defaults, and out-of-range numbers
        // are clamped rather than trusted — a hand-edited preference file must
        // never leave the phone keys with no source or the level at 700%.
        phoneMessageSource = PhoneMessageSource(rawValue: defaults.string(forKey: "phoneMessageSource") ?? "")
            ?? .recordings
        voiceInputDeviceUID = defaults.string(forKey: "voiceInputDeviceUID")
        voiceOutputDeviceUID = defaults.string(forKey: "voiceOutputDeviceUID")
        voiceLevel = min(1, max(0, defaults.object(forKey: "voiceLevel") as? Double ?? 0.6))
        voicePTT = VoicePTTMode(rawValue: defaults.string(forKey: "voicePTT") ?? "") ?? .radioCommand
        voicePTTLeadMs = min(500, max(0, defaults.object(forKey: "voicePTTLeadMs") as? Int ?? 120))
        lastStationProfile = defaults.data(forKey: "lastStationProfile")
            .flatMap { try? JSONDecoder().decode(StationProfile.self, from: $0) }
        showShortcutHints = defaults.object(forKey: "showShortcutHints") as? Bool ?? false
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
        name: String = "",
        member: String = "",
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
            // The sent name, for parties whose exchange carries one (NAQP,
            // MNQP). Never cut — it is not a number.
            case .name: name
            case .exchange: exchange
            // The member-number-or-power element, already in its on-air form
            // ("NR 13" or "5W" — the caller shapes it). Never cut: cutting
            // would turn "NR 13" into "NR A3" for a value the other station
            // has to log verbatim, and half the values are powers anyway.
            case .member: member
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
