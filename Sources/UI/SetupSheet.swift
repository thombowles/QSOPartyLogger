import SwiftUI

/// Contest setup: party, station profile, category pickers, and my location
/// (state or 1–4 counties for county-line operation).
struct SetupSheet: View {
    let document: LogDocument
    /// The download client, for the party section's call history row. `nil`
    /// in previews; the row simply hides.
    var callHistory: CallHistoryClient?
    /// The MASTER.SCP client, for the super check partial row. `nil` in
    /// previews; the row still renders, minus status and Refresh.
    var scp: SCPClient? = nil
    /// The park directory client, for the POTA section's picker. `nil` in
    /// previews; the picker still takes typed references.
    var parks: PotaParkClient? = nil
    /// One-shot location for the grid square and the nearest-parks sort.
    /// `nil` in previews; the Locate button simply hides. Named
    /// `locationProvider` because `save()` already has a `location` local of
    /// an entirely different type.
    var locationProvider: (any LocationProviding)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager

    @State private var settings = AppSettings.shared

    @State private var partyID = "ksqp"
    @State private var station = StationProfile()
    @State private var isInState = false
    @State private var stateToken = ""
    @State private var selectedCounties: [String] = []
    @State private var countySearch = ""
    @State private var exchangeName = ""
    @State private var exchangeMember = ""
    @State private var entryClassID = ""
    @State private var selectedParks: [String] = []
    @State private var locating = false
    @State private var locationNote: String?
    @State private var locatedFix: (latitude: Double, longitude: Double)?

    @FocusState private var focused: Field?

    private enum Field: Hashable {
        case callsign, stateToken, countySearch, exchangeName, exchangeMember
    }

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
                    if let party {
                        callHistoryRow(party)
                    }
                    superCheckRow
                }

                // Every field here folds to caps as it is typed — the binding,
                // not `.textCase(.uppercase)`, which restyles the drawn glyphs
                // and leaves the stored string in whatever case was typed. It
                // also styled the *label*, which is why this section used to
                // shout CALLSIGN and GRID SQUARE at an operator whose other
                // rows said Name and Email.
                //
                // Email is the exception: see `StationProfile.normalized()`.
                Section("Station") {
                    TextField("Callsign", text: $station.callsign.uppercasing)
                        .font(.body.monospaced())
                        .focused($focused, equals: .callsign)
                    TextField("Name", text: $station.name.uppercasing)
                    TextField("Email", text: $station.email)
                    TextField("Address", text: $station.address.uppercasing)
                    // One field per row, each with its own label, exactly like
                    // the five rows around them.
                    //
                    // These five used to share two rows. That packed three
                    // fields into a space sized for one, so `.frame(width: 70)`
                    // squeezed "State" into a two-line label beside a sliver of
                    // a field. Grouping them under a single `LabeledContent`
                    // fixed the squeeze and introduced a worse fault: a
                    // TextField's title renders *after* its field there, so the
                    // row read `[  ] City [ ] ST [  ] ZIP` and every label sat
                    // between two fields, belonging to neither.
                    //
                    // A `prompt:` would put the hint inside the box, but it
                    // disappears the moment the field is filled -- and "USA" in
                    // an unlabelled box is the same question all over again. A
                    // label that persists is the whole job here, and the Form's
                    // own label column is where one goes.
                    TextField("City", text: $station.city.uppercasing)
                    TextField("State / province", text: $station.stateProvince.uppercasing)
                    TextField("ZIP", text: $station.postalCode.uppercasing)
                    TextField("Country", text: $station.country.uppercasing)
                    // Free text, always — a Mac with no usable fix must still
                    // be able to say where it is. Locate only fills it in.
                    LabeledContent("Grid square") {
                        HStack(spacing: 6) {
                            TextField("", text: $station.gridLocator.uppercasing)
                                .textFieldStyle(.roundedBorder)
                                .font(.body.monospaced())
                                .frame(width: 100)
                            if locationProvider != nil {
                                Button {
                                    Task { await locate() }
                                } label: {
                                    if locating {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Label("Locate", systemImage: "location.fill")
                                    }
                                }
                                .disabled(locating)
                                .help("Fill the grid square from this Mac's location")
                            }
                        }
                    }
                    if let locationNote {
                        Text(locationNote)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    TextField("Club (optional)", text: $station.club.uppercasing)
                }

                Section("Category") {
                    Picker("Operator", selection: $station.categoryOperator) {
                        ForEach(StationProfile.CategoryOperator.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    // SO vs SOA is its own axis, not an operator class — NAQP
                    // rule 5A/5B is the canonical pair, and the sponsors that
                    // do not split on it simply ignore the header.
                    Picker("Assisted", selection: $station.categoryAssisted) {
                        ForEach(StationProfile.CategoryAssisted.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    // The consequence, stated by the control that causes it.
                    // Orange only once it actually bites — this log already
                    // has spots on the record that the claim now contradicts;
                    // otherwise it is a plain statement of what the default
                    // selection means.
                    if station.categoryAssisted == .nonAssisted {
                        Label(SpottingPolicy.setupCaution, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(document.log.usedSpots
                                             ? AnyShapeStyle(Color.orange)
                                             : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                            .fixedSize(horizontal: false, vertical: true)
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
                    Picker("Transmitters", selection: $station.categoryTransmitter) {
                        ForEach(StationProfile.CategoryTransmitter.allCases, id: \.self) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    // A party-declared class table (Skeeter Hunt X1–X4),
                    // shown only where one exists. The factor multiplies the
                    // whole score, so the label carries it.
                    if let party, !party.entryClasses.isEmpty {
                        Picker("Entry class", selection: $entryClassID) {
                            ForEach(party.entryClasses, id: \.id) { entryClass in
                                Text("\(entryClass.id) — \(entryClass.label)")
                                    .tag(entryClass.id)
                            }
                        }
                    }
                    TextField("Operators (multi-op)", text: $station.operators.uppercasing)
                        .font(.body.monospaced())
                    Text("Space-separated calls; @ marks the host station. Blank = your callsign.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Universal and party-agnostic: POTA rides any contest. The
                // selection is the *current* activation; each contact is
                // stamped as it is logged, so a mid-contest park change (or
                // a rove) affects later rows only.
                Section("POTA Activation") {
                    Text("Operating from a park? Pick it and every contact is stamped "
                         + "for the POTA upload. Leave empty otherwise.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    PotaParkPicker(selected: $selectedParks,
                                   origin: parkOrigin,
                                   originLabel: parkOriginLabel,
                                   client: parks)
                }

                Section("My Location") {
                    if let party {
                        // The other half of "what I send", for the parties
                        // whose exchange carries a name (NAQP, MNQP). One
                        // name for the whole contest — the sponsors' own
                        // rule — so it is set here, not per contact.
                        if party.exchangeIncludesName {
                            LabeledContent("Exchange name") {
                                TextField("", text: $exchangeName.uppercasing)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.body.monospaced())
                                    .focused($focused, equals: .exchangeName)
                                    .frame(width: 120)
                            }
                            Text("Sent in every exchange; the rules require one name for the whole contest.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        // The other contest-long sent element: a member's
                        // number, or an output power for everyone else
                        // (Skeeter Hunt: "NR 13" versus "5W").
                        if let member = party.memberExchange {
                            LabeledContent(member.term.sentenceCased) {
                                TextField("", text: $exchangeMember.uppercasing)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.body.monospaced())
                                    .focused($focused, equals: .exchangeMember)
                                    .frame(width: 120)
                            }
                            Text("Your \(member.term) — or your output power "
                                 + "(5W, 500MW) if you don't have one.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        // A party with no home region has no inside to be on
                        // one side of, so it is never asked: NAQP's entrants
                        // all send the same shape, and the old segmented
                        // picker made a Texan choose "Outside the other NA
                        // countries" and a Mexican choose "Inside" — after
                        // which the header exported as a pseudo-state the
                        // operator was told to hand-fix. One question now.
                        if party.hasHomeRegion {
                            Picker("Operating from", selection: $isInState) {
                                Text("Outside \(party.inStateLabel)").tag(false)
                                Text("Inside \(party.inStateLabel)").tag(true)
                            }
                            .pickerStyle(.segmented)
                        }

                        if isInState && party.hasHomeRegion {
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
                            // control alone, and the label keeps its own case.
                            // The field folds through the binding, so the token
                            // this log *stores* is upper case and not merely
                            // drawn that way.
                            LabeledContent(party.hasHomeRegion ? "State / DX" : "My location") {
                                TextField("", text: $stateToken.uppercasing)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($focused, equals: .stateToken)
                                    .frame(width: 120)
                            }
                            Text(locationHint(party))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
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
        .frame(width: 560, height: 700)
        // Land on whatever still needs an answer, rather than opening with no
        // focus at all and making the operator hunt for the field with a mouse.
        .onAppear {
            load()
            focused = initialFocus
            // After load(), never as a `.task` alongside it: the auto-fill
            // reads the grid square load() just populated, and racing it
            // would fill a field that was never empty.
            Task { await autoFillGrid() }
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
        // Landing on a name party seeds the name the moment the field
        // appears, not only when the sheet opened on one — and a class
        // party's picker must hold one of *its* ids, not a stale one from
        // whatever party the log was on before.
        .onChange(of: partyID) { _, _ in
            seedExchangeName()
            entryClassID = party?.resolvedEntryClass(id: entryClassID)?.id ?? ""
        }
    }

    /// Where the park picker measures "nearest" from. The Locate button's
    /// fix wins; the typed grid square is the offline answer; neither means
    /// no nearest list at all.
    private var parkOrigin: (latitude: Double, longitude: Double)? {
        locatedFix ?? Maidenhead.center(of: station.gridLocator)
    }

    private var parkOriginLabel: String {
        if locatedFix != nil { return "your location" }
        let grid = station.gridLocator.trimmingCharacters(in: .whitespaces).uppercased()
        return grid.isEmpty ? "" : "grid \(grid)"
    }

    /// The Locate button. A failure leaves the field exactly as it was —
    /// free text the operator can fill in themselves.
    private func locate() async {
        guard let locationProvider else { return }
        locating = true
        defer { locating = false }
        guard let fix = await locationProvider.currentLocation(),
              let grid = Maidenhead.locator(latitude: fix.latitude,
                                            longitude: fix.longitude) else {
            locationNote = "Couldn't get a location — type the grid square instead."
            return
        }
        station.gridLocator = grid
        locatedFix = fix
        locationNote = nil
    }

    /// Silent only when nothing will be asked of the operator: the
    /// permission dialog is reserved for the Locate button. An already-typed
    /// grid is never overwritten.
    private func autoFillGrid() async {
        guard let locationProvider, locationProvider.isAuthorized,
              station.gridLocator.trimmingCharacters(in: .whitespaces).isEmpty,
              let fix = await locationProvider.currentLocation(),
              let grid = Maidenhead.locator(latitude: fix.latitude,
                                            longitude: fix.longitude)
        else { return }
        station.gridLocator = grid
        locatedFix = fix
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

    /// The party's N1MM call history file: the toggle, what revision is
    /// cached, and a Refresh that overrides the once-a-day check. Hidden for
    /// the parties with no file upstream — there is nothing to control.
    @ViewBuilder
    private func callHistoryRow(_ party: PartyDefinition) -> some View {
        if party.callHistory != nil {
            Toggle("Download call history (what stations usually send)",
                   isOn: $settings.callHistoryEnabled)
                .font(.caption)
            if settings.callHistoryEnabled {
                HStack(spacing: 8) {
                    let status = callHistoryStatus(party)
                    Text(status.text)
                        .font(.caption)
                        .foregroundStyle(status.isError
                                         ? AnyShapeStyle(.orange)
                                         : AnyShapeStyle(.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                    if let callHistory {
                        Button("Refresh") {
                            Task {
                                await callHistory.refreshIfStale(
                                    party: party, force: true)
                            }
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    /// Super check partial: the toggle, what release is cached, and a
    /// Refresh that overrides the once-a-day check. Global — one
    /// MASTER.SCP serves every party — so unlike the call history row it
    /// never hides with the party.
    @ViewBuilder
    private var superCheckRow: some View {
        Toggle("Super check partial (known calls shown while you type)",
               isOn: $settings.superCheckEnabled)
            .font(.caption)
        if settings.superCheckEnabled {
            HStack(spacing: 8) {
                let status = superCheckStatus
                Text(status.text)
                    .font(.caption)
                    .foregroundStyle(status.isError
                                     ? AnyShapeStyle(.orange)
                                     : AnyShapeStyle(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
                if let scp {
                    Button("Refresh") {
                        Task { await scp.refreshIfStale(force: true) }
                    }
                    .font(.caption)
                }
            }
        }
    }

    private var superCheckStatus: (text: String, isError: Bool) {
        guard let scp else { return ("", false) }
        switch scp.status {
        case .checking:
            return ("Checking supercheckpartial.com…", false)
        case .downloading:
            return ("Downloading…", false)
        case .ready(let records, let release):
            return ("\(records) calls — release \(release)", false)
        case .failed(let message):
            return (message, true)
        case .idle:
            break
        }
        if let meta = scp.cachedMeta() {
            return ("Cached release — fetched "
                    + meta.fetchedAt.formatted(date: .abbreviated, time: .omitted),
                    false)
        }
        return ("Downloads automatically — nothing to set up.", false)
    }

    private func callHistoryStatus(_ party: PartyDefinition) -> (text: String, isError: Bool) {
        guard let callHistory else { return ("", false) }
        switch callHistory.status {
        case .checking:
            return ("Checking the community listing…", false)
        case .downloading:
            return ("Downloading…", false)
        case .ready(let partyID, let revision, let records) where partyID == party.id:
            return ("\(revision) — \(records) stations", false)
        case .failed(let message):
            return (message, true)
        default:
            break
        }
        if let meta = callHistory.cachedMeta(partyID: party.id) {
            return ("\(meta.sourceFileName) — updated \(meta.listedDate)", false)
        }
        return ("Downloads automatically when this contest starts.", false)
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
            TextField("Search \(party.countyTermPlural)…", text: $countySearch)
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

    /// What may be typed in the location field. A party with a home region
    /// asks only about the outside world; a party without one accepts its own
    /// code list too, so the hint names it and shows the shape of a code —
    /// an entrant in Bermuda should not have to guess between VP9 and BDA.
    private func locationHint(_ party: PartyDefinition) -> String {
        guard !party.hasHomeRegion else { return "Two-letter state or province, or DX." }
        // A no-home-region party may enumerate nothing at all (Skeeter Hunt:
        // its multipliers are the standard tables) — no code list to hint at.
        guard !party.counties.isEmpty else { return "Your state or province, or DX." }
        let examples = party.counties.prefix(3).map(\.abbr).joined(separator: ", ")
        return "Your state or province, DX, or one of this party's "
            + "\(party.counties.count) location codes (\(examples), …)."
    }

    private func countyCapText(_ party: PartyDefinition) -> String {
        let cap = min(ExchangeParser.maxCounties, party.maxSimultaneousCounties)
        let term = party.countyTerm
        return cap == 1
            ? "\(term.sentenceCased) (this party does not permit \(term)-line operation):"
            : "\(party.countyTermPlural.sentenceCased) (1–\(cap); more than one = \(term) line):"
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
        guard let party else { return false }
        // A name party without a name cannot produce one submittable line —
        // gated exactly as the location token is.
        if party.exchangeIncludesName,
           exchangeName.trimmingCharacters(in: .whitespaces).isEmpty {
            return false
        }
        // A member party's sent element must be readable — a number or a
        // power with its unit — because every exchange carries it and the
        // other stations score by what they copy.
        if party.memberExchange != nil,
           MemberExchange.parse(exchangeMember) == nil {
            return false
        }
        if isInState && party.hasHomeRegion {
            return !selectedCounties.isEmpty
        }
        return party.validEntrantTokens
            .contains(stateToken.trimmingCharacters(in: .whitespaces).uppercased())
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
        // A log written before this party dropped its inside/outside choice —
        // or one carried over from a party that has one — arrives as a county
        // selection there is no longer a control for. Its token *is* the
        // location, so it lands in the field the operator can see.
        if party?.hasHomeRegion == false, isInState {
            isInState = false
            stateToken = selectedCounties.first ?? ""
            selectedCounties = []
        }
        if stateToken.isEmpty {
            stateToken = station.stateProvince.uppercased()
        }
        exchangeName = document.log.exchangeName
        exchangeMember = document.log.exchangeMember
        entryClassID = party?.resolvedEntryClass(id: document.log.entryClassID)?.id ?? ""
        selectedParks = document.log.myPotaRefs
        seedExchangeName()
    }

    /// A name party with no name yet starts from the operator's own first
    /// name — the overwhelmingly common choice, and one keystroke to replace.
    private func seedExchangeName() {
        guard party?.exchangeIncludesName == true,
              exchangeName.trimmingCharacters(in: .whitespaces).isEmpty,
              let first = station.name.split(separator: " ").first
        else { return }
        exchangeName = first.uppercased()
    }

    private func save() {
        // Every field, not just the callsign. The bindings already fold what is
        // typed here; this is what catches a profile carried in from an older
        // log, where the fields were only styled upper case and stored whatever
        // was typed.
        station = station.normalized()
        // No home region, no in-state case: every entrant is a peer location,
        // and the token they typed is what the exports carry.
        let location: MyLocation = isInState && party?.hasHomeRegion != false
            ? .inState(counties: selectedCounties)
            : .outOfState(location: stateToken.trimmingCharacters(in: .whitespaces).uppercased())
        document.updateStation(
            station, location: location, partyID: partyID,
            exchangeName: exchangeName, exchangeMember: exchangeMember,
            entryClassID: entryClassID, myPotaRefs: selectedParks,
            undoManager: undoManager
        )
        dismiss()
    }
}
