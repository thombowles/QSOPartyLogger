import SwiftUI

/// Contest Setup's park chooser: removable chips for what is selected, one
/// search field over the cached directory (by name, number, or state), the
/// nearest parks when that field is empty, and Return-to-add for a typed
/// reference.
///
/// Its own view so `SetupSheet` stays inside its type-checker budget and the
/// park directory never leaks past this seam.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            selectedChips
            TextField("Search by park name or number — or type a reference and press Return",
                      text: $query)
                .font(.body.monospaced())
                .onSubmit(addTypedReference)
            results
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
    }

    @ViewBuilder
    private var selectedChips: some View {
        if !selected.isEmpty {
            HStack(spacing: 6) {
                ForEach(selected, id: \.self) { ref in
                    HStack(spacing: 4) {
                        Text(ref).font(.caption.monospaced().weight(.bold))
                        Button {
                            selected.removeAll { $0 == ref }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .help("Remove \(ref)")
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

    /// Search results for a query; the nearest parks for none.
    @ViewBuilder
    private var results: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if let directory = client?.directory {
            if trimmed.isEmpty {
                if let origin {
                    Text("Nearest \(originLabel):")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    parkList(directory.nearest(latitude: origin.latitude,
                                               longitude: origin.longitude)
                        .map { (park: $0.park,
                                detail: String(format: "%.0f mi", $0.km * 0.621371)) })
                }
            } else {
                parkList(directory.search(trimmed).map { (park: $0, detail: "") })
            }
        } else if !trimmed.isEmpty {
            Text("No park list downloaded — press Return to add a full reference "
                 + "like US-3315.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func parkList(_ rows: [(park: PotaPark, detail: String)]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(rows, id: \.park.id) { row in
                    let isSelected = selected.contains(row.park.reference)
                    Button {
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
                            Text(row.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isSelected ? Color.accentColor.opacity(0.3)
                                               : Color.gray.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 150)
    }

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

    private func toggle(_ ref: String) {
        if let index = selected.firstIndex(of: ref) {
            selected.remove(at: index)
        } else {
            selected.append(ref)
        }
    }

    /// Return in the search field: a string the grammar accepts is added
    /// directly. This is the keyboard-only path, and the whole path for a
    /// park the directory does not carry — another program, a brand-new
    /// park, or no download yet.
    private func addTypedReference() {
        guard let ref = PotaRef.normalize(query) else { return }
        if !selected.contains(ref) { selected.append(ref) }
        query = ""
    }
}
