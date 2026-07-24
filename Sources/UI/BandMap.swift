import SwiftUI
import AppKit

/// Data feed for the band map panel — owned by the contest window (MainView)
/// and kept in sync with its band / worked-calls / CQ state.
@MainActor
@Observable
final class BandMapModel {
    var band: Band = .m20
    var workedCalls: Set<String> = []
    var cqKHz: Double?
    var onTuneSpot: ((Spot) -> Void)?
    var onTuneKHz: ((Double) -> Void)?

    private let radio: RadioController
    private let spotStore: SpotStore

    init(radio: RadioController, spotStore: SpotStore) {
        self.radio = radio
        self.spotStore = spotStore
    }

    var vfoKHz: Double? {
        radio.radioState.map { Double($0.frequencyHz) / 1000 }
    }

    var spots: [Spot] {
        spotStore.spots(band: band)
    }
}

/// N1MM-style band map: vertical frequency ruler for the current band, spots
/// plotted at their frequency, red VFO marker, dashed CQ-frequency marker.
/// Click a spot to tune + pre-fill the call; click empty map to QSY there.
struct BandMapView: View {
    let model: BandMapModel
    @AppStorage("bandMapSpanKHz") private var spanKHz: Double = 50

    private static let spanChoices: [(label: String, kHz: Double)] = [
        ("25", 25), ("50", 50), ("100", 100), ("All", 10_000),
    ]
    private let rulerWidth: CGFloat = 46

    var body: some View {
        VStack(spacing: 6) {
            header
            GeometryReader { geo in
                map(size: geo.size)
            }
        }
        .padding(10)
        .frame(minWidth: 190, minHeight: 280)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(model.band.rawValue)
                .font(.headline)
            if let vfo = model.vfoKHz {
                Text(String(format: "%.1f", vfo))
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.red)
            } else {
                Text("no radio")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $spanKHz) {
                ForEach(Self.spanChoices, id: \.kHz) { choice in
                    Text(choice.label).tag(choice.kHz)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 160)
            .help("Visible span in kHz, centered on the VFO")
        }
    }

    private func map(size: CGSize) -> some View {
        let scale = BandMapScale(
            band: model.band,
            centerKHz: model.vfoKHz ?? model.cqKHz,
            spanKHz: spanKHz
        )
        let h = Double(size.height)

        return ZStack(alignment: .topLeading) {
            // Background doubles as click-to-QSY surface.
            Rectangle()
                .fill(.background.secondary)
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture().onEnded { value in
                        let kHz = (scale.kHz(atY: Double(value.location.y), height: h) * 10).rounded() / 10
                        model.onTuneKHz?(kHz)
                    }
                )

            // Frequency gridlines + ruler labels.
            ForEach(scale.tickKHz(), id: \.self) { tick in
                let y = scale.y(forKHz: tick, height: h)
                Path { p in
                    p.move(to: CGPoint(x: rulerWidth, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }
                .stroke(.quaternary, lineWidth: 1)
                Text(String(Int(tick)))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .position(x: rulerWidth / 2 - 2, y: y)
            }

            // CQ frequency marker (dashed blue).
            if let cq = model.cqKHz, cq >= scale.lowKHz, cq <= scale.highKHz {
                let y = scale.y(forKHz: cq, height: h)
                Path { p in
                    p.move(to: CGPoint(x: rulerWidth, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }
                .stroke(.blue, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                Text("CQ")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.blue)
                    .position(x: size.width - 12, y: y - 6)
            }

            // VFO marker (solid red) — where the radio is right now.
            if let vfo = model.vfoKHz, vfo >= scale.lowKHz - 0.001, vfo <= scale.highKHz + 0.001 {
                let y = scale.y(forKHz: vfo, height: h)
                Path { p in
                    p.move(to: CGPoint(x: rulerWidth - 6, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }
                .stroke(.red, lineWidth: 1.5)
                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(.red)
                    .position(x: rulerWidth - 10, y: y)
            }

            // Spots, de-collided so labels never overlap.
            ForEach(spotRows(scale: scale, height: h)) { row in
                Button {
                    model.onTuneSpot?(row.spot)
                } label: {
                    HStack(spacing: 3) {
                        Circle().frame(width: 5, height: 5)
                        Text(row.spot.call)
                            .font(.system(size: 10, design: .monospaced).weight(.semibold))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.workedCalls.contains(row.spot.call) ? Color.secondary : Color.primary)
                .offset(x: rulerWidth + 8, y: CGFloat(row.y) - 6)
                .help(String(format: "%.1f de %@%@ — click to tune",
                             row.spot.freqKHz, row.spot.spotter,
                             row.spot.comment.isEmpty ? "" : " (\(row.spot.comment))"))
            }
        }
        .clipped()
    }

    private struct SpotRow: Identifiable {
        let spot: Spot
        let y: Double
        var id: String { spot.id }
    }

    /// Spots in view, top→bottom, nudged apart so labels stay readable.
    private func spotRows(scale: BandMapScale, height: Double) -> [SpotRow] {
        let visible = model.spots
            .filter { $0.freqKHz >= scale.lowKHz && $0.freqKHz <= scale.highKHz }
            .sorted { $0.freqKHz > $1.freqKHz }
        var rows: [SpotRow] = []
        var lastY = -Double.infinity
        for spot in visible {
            let y = max(scale.y(forKHz: spot.freqKHz, height: height), lastY + 13)
            lastY = y
            rows.append(SpotRow(spot: spot, y: y))
        }
        return rows
    }
}

/// Floating utility panel hosting the band map, one per contest window.
@MainActor
enum BandMapPanel {
    static func make(model: BandMapModel, near window: NSWindow?) -> NSPanel {
        let width: CGFloat = 230
        let height: CGFloat = 560
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Band Map"
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true  // spot clicks don't steal typing focus
        panel.level = .floating
        panel.contentView = NSHostingView(rootView: BandMapView(model: model))

        if !panel.setFrameUsingName("BandMapPanel"), let win = window, let screen = win.screen {
            // First open: dock just right of the contest window.
            var x = win.frame.maxX + 8
            if x + width > screen.visibleFrame.maxX {
                x = screen.visibleFrame.maxX - width - 8
            }
            let y = max(win.frame.maxY - height, screen.visibleFrame.minY)
            panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: false)
        }
        panel.setFrameAutosaveName("BandMapPanel")
        return panel
    }
}
