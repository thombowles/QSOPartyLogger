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

    @FocusState private var focused: Field?

    private enum Field: Hashable { case callsign, stateToken, countySearch }

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
                        ForEach(PartyCatalog.pickerEntries()) { entry in
                            // NO VERIFICATION MARKER HERE. It used to carry
                            // "⚠︎" for every partially-verified party, which was
                            // 39 of 46 -- so the list read as a catalogue of
                            // broken things. Choosing a contest and knowing how
                            // the app handles it are different jobs, and the
                            // notice below re-renders with the selection, so it
                            // is already the before-you-commit surface.
                            //
                            // A party that is part of a combined entry is nested
                            // under it rather than listed on its own.
                            Text(entry.isMember
                                 ? "      ↳ \(entry.party.name)"
                                 : entry.party.name)
                                .tag(entry.party.id)
                        }
                    }
                    if let party, !party.combines.isEmpty {
                        Text("One log for all four. Use this only if you are outside "
                             + "all four regions — otherwise choose your own party below it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let windows = party?.schedule, !windows.isEmpty {
                        Text(scheduleText(windows))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let party {
                        verificationNotice(party)
                    }
                }

                Section("Station") {
                    TextField("Callsign", text: $station.callsign)
                        .textCase(.uppercase)
                        .font(.body.monospaced())
                        .focused($focused, equals: .callsign)
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
                            Text("Outside \(party.inStateLabel)").tag(false)
                            Text("Inside \(party.inStateLabel)").tag(true)
                        }
                        .pickerStyle(.segmented)

                        if isInState {
                            countyPicker(party)
                        } else {
                            // LabeledContent, not the TextField's own title. In
                            // a grouped Form the title is pulled out into the
                            // leading label column, so a .frame(width:) on the
                            // field sizes the label *and* the field together --
                            // which is what collapsed this row: "State /
                            // Province / DX" wrapped to three lines and left a
                            // borderless sliver with nothing on screen to aim
                            // at. Splitting them means the width applies to the
                            // control alone, and .textCase stops leaking into
                            // the label and shouting it in caps.
                            LabeledContent("State / DX") {
                                TextField("", text: $stateToken)
                                    .textFieldStyle(.roundedBorder)
                                    .textCase(.uppercase)
                                    .focused($focused, equals: .stateToken)
                                    .frame(width: 120)
                            }
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
        // Land on whatever still needs an answer, rather than opening with no
        // focus at all and making the operator hunt for the field with a mouse.
        .onAppear {
            load()
            focused = initialFocus
        }
        // Flipping to "Outside" reveals an empty field that Save is gated on;
        // flipping to "Inside" reveals a county list nobody can filter without
        // the cursor in the search box. Either way the work is in the field the
        // toggle just exposed, so put the cursor there.
        .onChange(of: isInState) { _, nowInState in
            if nowInState {
                focused = selectedCounties.isEmpty ? .countySearch : nil
            } else {
                focused = stateToken.isEmpty ? .stateToken : nil
            }
        }
    }

    /// Callsign first when it is missing — nothing can be saved without it.
    /// Otherwise the location token, which is the other half of `canSave` and
    /// the field most likely to be blank on a freshly opened log.
    private var initialFocus: Field {
        if station.callsign.trimmingCharacters(in: .whitespaces).isEmpty {
            return .callsign
        }
        if !isInState && stateToken.isEmpty {
            return .stateToken
        }
        return isInState ? .countySearch : .stateToken
    }

    /// What this app will and will not do for the selected party.
    ///
    /// **Orange is reserved for `blockingCaveats`** — the app will mis-score or
    /// mis-export this party, which is worth interrupting someone for. It is no
    /// longer keyed on `isPartiallyVerified`, which fired on 39 of 46 parties
    /// and so said nothing. Stale sources, inferred readings and cosmetic notes
    /// keep the informational tone; the full provenance paragraph stays behind
    /// the disclosure, and is offered for every party.
    ///
    /// Which group a line belongs to is decided by `PartyNotice`, and **every
    /// group it hands back is drawn with its own heading** — colour on its own
    /// never has to explain why one bullet is orange and the next is grey.
    ///
    /// **One `ForEach`, over `PartyNotice.rows`.** Drawing the two groups from
    /// two sibling `ForEach`es gave this section two rows identified `0`, and
    /// on a re-diff — opening *Rules provenance* — the first orange bullet
    /// came back carrying the grey line's text and colour. `Row.id` is
    /// namespaced by tone; there is nothing left for a row to collide with.
    @ViewBuilder
    private func verificationNotice(_ party: PartyDefinition) -> some View {
        ForEach(PartyNotice(party: party).rows) { row in
            noticeRow(row)
        }

        if let notes = party.notes {
            DisclosureGroup("Rules provenance") {
                Text(notes)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .font(.caption)
        }
    }

    /// A heading or a bullet — never both for one `Row.id`, so the branch a row
    /// takes is fixed for the life of its identity.
    @ViewBuilder
    private func noticeRow(_ row: PartyNotice.Row) -> some View {
        if let systemImage = row.systemImage {
            Label(row.text, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(row.tone.style)
        } else {
            Text("• \(row.text)")
                .font(row.tone.bulletFont)
                .foregroundStyle(row.tone.style)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
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
                .focused($focused, equals: .countySearch)
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
