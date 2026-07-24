import SwiftUI

/// Contest setup: party, station profile, category pickers, and my location
/// (state or 1–4 counties for county-line operation).
struct SetupSheet: View {
    let document: LogDocument
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager

    @State private var partyID = "ksqp"
    @State private var station = StationProfile()
    @State private var isInState = false
    @State private var stateToken = ""
    @State private var selectedCounties: [String] = []
    @State private var countySearch = ""

    private var parties: [PartyDefinition] {
        PartyCatalog.allParties()
    }

    private var party: PartyDefinition? {
        parties.first { $0.id == partyID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Contest Setup")
                .font(.title2.weight(.semibold))
                .padding()

            Form {
                Section("QSO Party") {
                    Picker("Party", selection: $partyID) {
                        ForEach(parties) { party in
                            Text(party.name).tag(party.id)
                        }
                    }
                    if let windows = party?.schedule, !windows.isEmpty {
                        Text(scheduleText(windows))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let notes = party?.notes, notes.lowercased().contains("partial") {
                        Label(notes, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section("Station") {
                    TextField("Callsign", text: $station.callsign)
                        .textCase(.uppercase)
                        .font(.body.monospaced())
                    TextField("Name", text: $station.name)
                    TextField("Email", text: $station.email)
                    TextField("Address", text: $station.address)
                    HStack {
                        TextField("City", text: $station.city)
                        TextField("State", text: $station.stateProvince).frame(width: 70)
                        TextField("ZIP", text: $station.postalCode).frame(width: 90)
                    }
                    TextField("Club (optional)", text: $station.club)
                }

                Section("Category") {
                    Picker("Operator", selection: $station.categoryOperator) {
                        ForEach(StationProfile.CategoryOperator.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    Picker("Power", selection: $station.categoryPower) {
                        ForEach(StationProfile.CategoryPower.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    Picker("Station", selection: $station.categoryStation) {
                        ForEach(StationProfile.CategoryStation.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                }

                Section("My Location") {
                    if let party {
                        Picker("Operating from", selection: $isInState) {
                            Text("Outside \(party.homeState)").tag(false)
                            Text("Inside \(party.homeState)").tag(true)
                        }
                        .pickerStyle(.segmented)

                        if isInState {
                            countyPicker(party)
                        } else {
                            TextField("State / Province / DX", text: $stateToken)
                                .textCase(.uppercase)
                                .frame(width: 160)
                            Text("Two-letter state or province, or DX.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding()
        }
        .frame(width: 560, height: 640)
        .onAppear(perform: load)
    }

    @ViewBuilder
    private func countyPicker(_ party: PartyDefinition) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(countyCapText(party))
                    .font(.caption)
                Spacer()
                if !selectedCounties.isEmpty {
                    Text(selectedCounties.joined(separator: "/"))
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(.blue)
                }
            }
            TextField("Search counties…", text: $countySearch)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 4)], spacing: 4) {
                    ForEach(filteredCounties(party)) { county in
                        let selected = selectedCounties.contains(county.abbr)
                        Button {
                            toggle(county.abbr)
                        } label: {
                            HStack(spacing: 4) {
                                Text(county.abbr).font(.caption.monospaced().weight(.bold))
                                Text(county.name).font(.caption2).lineLimit(1)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                selected ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 4)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 160)
        }
    }

    private func countyCapText(_ party: PartyDefinition) -> String {
        let cap = min(ExchangeParser.maxCounties, party.maxSimultaneousCounties)
        return cap == 1
            ? "County (this party does not permit county-line operation):"
            : "Counties (1–\(cap); more than one = county line):"
    }

    private func scheduleText(_ windows: [PartyDefinition.ScheduleWindow]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d HHmm'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return windows
            .map { "\(formatter.string(from: $0.start)) – \(formatter.string(from: $0.end))" }
            .joined(separator: "  ·  ")
    }

    private func filteredCounties(_ party: PartyDefinition) -> [County] {
        let query = countySearch.trimmingCharacters(in: .whitespaces).uppercased()
        guard !query.isEmpty else { return party.counties }
        return party.counties.filter {
            $0.abbr.contains(query) || $0.name.uppercased().contains(query)
        }
    }

    private func toggle(_ abbr: String) {
        let cap = min(ExchangeParser.maxCounties, party?.maxSimultaneousCounties ?? ExchangeParser.maxCounties)
        if let idx = selectedCounties.firstIndex(of: abbr) {
            selectedCounties.remove(at: idx)
        } else if selectedCounties.count < cap {
            selectedCounties.append(abbr)
        }
    }

    private var canSave: Bool {
        guard !station.callsign.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if isInState {
            return !selectedCounties.isEmpty
        }
        guard let party else { return false }
        return party.validOutStateTokens.contains(stateToken.trimmingCharacters(in: .whitespaces).uppercased())
    }

    private func load() {
        partyID = document.log.partyID
        station = document.log.station
        switch document.log.myLocation {
        case .inState(let counties):
            isInState = true
            selectedCounties = counties
        case .outOfState(let location):
            isInState = false
            stateToken = location
        }
        if stateToken.isEmpty {
            stateToken = station.stateProvince.uppercased()
        }
    }

    private func save() {
        station.callsign = station.callsign.trimmingCharacters(in: .whitespaces).uppercased()
        let location: MyLocation = isInState
            ? .inState(counties: selectedCounties)
            : .outOfState(location: stateToken.trimmingCharacters(in: .whitespaces).uppercased())
        document.updateStation(station, location: location, partyID: partyID, undoManager: undoManager)
        dismiss()
    }
}
