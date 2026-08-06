import SwiftUI

/// Contest Setup's park chooser: removable chips for what is selected, a
/// search field over the cached directory (by name, number, or state), the
/// nearest parks while the field is empty and focused, and Return-to-add for
/// a typed reference.
///
/// Its own view so `SetupSheet` stays inside its type-checker budget and the
/// park directory never leaks past this seam. Every keyboard and disclosure
/// decision is `PotaPickerBehavior`'s, which is where they can be tested.
struct PotaParkPicker: View {
    @Binding var selected: [String]
    /// Where "nearest" measures from: the Locate button's fix, else the
    /// typed grid square's center. `nil` hides the nearest list — search and
    /// typed references still work.
    let origin: (latitude: Double, longitude: Double)?
    /// Names the origin in the caption: "your location" or "grid EM13LE".
    let originLabel: String
    var client: PotaParkClient?

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            selectedChips
            searchField
            if PotaPickerBehavior.showsResults(query: query, focused: searchFocused) {
                results
            }
            statusRow
        }
        .onAppear {
            client?.publishCached()
            // Weekly staleness only ever refreshes a cache that already
            // exists; the first download stays behind the button below.
            if let client {
                Task { await client.refreshIfStale() }
            }
        }
        // Typing narrows the list under the cursor, so a highlight left
        // pointing past the end comes back to the last row.
        .onChange(of: offered.count) { _, count in
            highlighted = PotaPickerBehavior.move(highlighted: highlighted, by: 0, count: count)
        }
    }

    // MARK: The field

    /// Looks like a search field, because it is one — a magnifying glass, a
    /// short prompt, and a filled well. It used to be a bare `TextField`
    /// carrying a sentence-long placeholder, which read as a paragraph of
    /// body text and was genuinely hard to find on a sheet this tall.
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.callout)
            TextField("Search parks", text: $query)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($searchFocused)
                .onSubmit(submit)
                .onKeyPress(.downArrow) { moveHighlight(by: 1) }
                .onKeyPress(.upArrow) { moveHighlight(by: -1) }
                .onKeyPress(.escape) { escape() }
            if !query.isEmpty {
                Button {
                    query = ""
                    highlighted = 0
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear the search (Esc)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        .help("Search by park name or number — US-3315, \"cedar hill\", or "
              + "\"lake tx\". ↑↓ to choose, Return to add, Esc to clear.")
    }

    @ViewBuilder
    private var selectedChips: some View {
        if !selected.isEmpty {
            HStack(spacing: 6) {
                ForEach(selected, id: \.self) { reference in
                    HStack(spacing: 4) {
                        Text(reference).font(.caption.monospaced().weight(.bold))
                        Button {
                            selected.removeAll { $0 == reference }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .help("Remove \(reference)")
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.3),
                                in: RoundedRectangle(cornerRadius: 4))
                }
                Spacer()
            }
        }
    }

    // MARK: The list

    /// Search results while there is a query; the nearest parks while the
    /// empty field holds focus.
    private var offered: [(park: PotaPark, detail: String)] {
        guard let directory = client?.directory else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            guard searchFocused, let origin else { return [] }
            return directory.nearest(latitude: origin.latitude, longitude: origin.longitude)
                .map { (park: $0.park,
                        detail: String(format: "%.0f mi", $0.km * 0.621371)) }
        }
        return directory.search(trimmed).map { (park: $0, detail: "") }
    }

    @ViewBuilder
    private var results: some View {
        let rows = offered
        if rows.isEmpty {
            emptyResultsNote
        } else {
            if query.trimmingCharacters(in: .whitespaces).isEmpty, !originLabel.isEmpty {
                Text("Nearest \(originLabel) — ↑↓ and Return to add:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(rows.enumerated()), id: \.element.park.id) { index, row in
                            parkRow(row, index: index)
                                .id(row.park.id)
                        }
                    }
                }
                .frame(height: min(CGFloat(rows.count) * 24 + 6, 150))
                .onChange(of: highlighted) { _, index in
                    guard rows.indices.contains(index) else { return }
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(rows[index].park.id, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyResultsNote: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if client?.directory == nil, !trimmed.isEmpty {
            Text("No park list downloaded — press Return to add a full reference "
                 + "like US-3315.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if !trimmed.isEmpty {
            Text(PotaRef.normalize(trimmed) == nil
                 ? "No park matches “\(trimmed)”."
                 : "Not in the list — press Return to add \(trimmed) anyway.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func parkRow(_ row: (park: PotaPark, detail: String), index: Int) -> some View {
        let isSelected = selected.contains(row.park.reference)
        let isHighlighted = index == highlighted && searchFocused
        return Button {
            toggle(row.park.reference)
        } label: {
            HStack(spacing: 6) {
                Text(row.park.reference)
                    .font(.caption.monospaced().weight(.bold))
                Text(row.park.name)
                    .font(.caption)
                    .lineLimit(1)
                if let location = row.park.locationDesc {
                    Text(location)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Text(row.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background(isSelected: isSelected, isHighlighted: isHighlighted),
                        in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    /// The keyboard highlight has to read as "this is what Return takes",
    /// which means it must outrank the already-selected tint.
    private func background(isSelected: Bool, isHighlighted: Bool) -> Color {
        if isHighlighted { return .accentColor.opacity(0.55) }
        if isSelected { return .accentColor.opacity(0.25) }
        return .gray.opacity(0.1)
    }

    // MARK: Status

    @ViewBuilder
    private var statusRow: some View {
        if let client {
            HStack(spacing: 8) {
                switch client.status {
                case .idle where client.cachedMeta() == nil:
                    Button("Download the park list (≈3 MB)") {
                        Task { await client.download() }
                    }
                    .font(.caption)
                    Text("Cached once, it searches offline — no signal needed at the park.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .idle:
                    EmptyView()
                case .downloading:
                    Text("Downloading the park list…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .ready(let parks):
                    Text("\(parks) parks — fetched "
                         + (client.cachedMeta()?.fetchedAt
                                .formatted(date: .abbreviated, time: .omitted) ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Refresh") {
                        Task { await client.refreshIfStale(force: true) }
                    }
                    .font(.caption)
                case .failed(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Keyboard

    private func moveHighlight(by delta: Int) -> KeyPress.Result {
        let count = offered.count
        guard count > 0 else { return .ignored }
        highlighted = PotaPickerBehavior.move(highlighted: highlighted, by: delta, count: count)
        return .handled
    }

    /// Esc empties the field and closes the list in one press. Handled here
    /// so it never reaches the sheet's Cancel button — closing the whole of
    /// Contest Setup is not what "clear the search" means.
    private func escape() -> KeyPress.Result {
        switch PotaPickerBehavior.escape(query: query) {
        case .clearAndCollapse:
            query = ""
        case .collapse:
            break
        }
        highlighted = 0
        searchFocused = false
        return .handled
    }

    private func submit() {
        let rows = offered
        switch PotaPickerBehavior.submit(query: query, highlighted: highlighted,
                                         offeredCount: rows.count) {
        case .addHighlighted(let index):
            toggle(rows[index].park.reference)
        case .addTyped(let reference):
            if !selected.contains(reference) { selected.append(reference) }
        case .nothing:
            return
        }
        query = ""
        highlighted = 0
    }

    private func toggle(_ reference: String) {
        if let index = selected.firstIndex(of: reference) {
            selected.remove(at: index)
        } else {
            selected.append(reference)
        }
    }
}
