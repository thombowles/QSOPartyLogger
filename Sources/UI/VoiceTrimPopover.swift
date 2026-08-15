import SwiftUI

/// The ✂ popover: the whole file's waveform with the kept region highlighted,
/// two sliders for the trim points, Auto-trim, Normalize, and a preview of
/// what will go on the air. Trim and gain are written to the sidecar as the
/// sliders settle — non-destructive, so a trim can be widened again later.
struct VoiceTrimPopover: View {
    @Bindable var store: VoiceStore
    let memory: Int
    @Environment(\.dismiss) private var dismiss

    @State private var full: VoiceAudio?
    @State private var bins: [Float] = []
    @State private var start: Double = 0
    @State private var end: Double = 0
    @State private var gainDB: Double = 0

    /// The gain slider's range. Normalize can land anywhere inside it; the
    /// slider is for nudging by ear after that.
    static let gainRange: ClosedRange<Double> = -20...20

    private var duration: Double { full?.duration ?? store.set[memory]?.duration ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("M\(memory) — trim")
                .font(.headline)
            TrimWaveform(bins: bins, start: duration > 0 ? start / duration : 0,
                         end: duration > 0 ? end / duration : 1)
                .frame(width: 420, height: 72)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text("Start").frame(width: 40, alignment: .trailing)
                    Slider(value: $start, in: 0...max(duration, 0.001)) { _ in commit() }
                        .frame(width: 320)
                    Text(String(format: "%.2f s", start)).font(.caption.monospacedDigit()).frame(width: 52)
                }
                GridRow {
                    Text("End").frame(width: 40, alignment: .trailing)
                    Slider(value: $end, in: 0...max(duration, 0.001)) { _ in commit() }
                        .frame(width: 320)
                    Text(String(format: "%.2f s", end)).font(.caption.monospacedDigit()).frame(width: 52)
                }
                GridRow {
                    Text("Gain").frame(width: 40, alignment: .trailing)
                    Slider(value: $gainDB, in: Self.gainRange, step: 0.5) { editing in
                        if !editing { store.setGain(memory: memory, dB: Float(gainDB)) }
                    }
                    .frame(width: 320)
                    .help("Level of this recording, in dB — Normalize sets it so the peak sits at −1 dBFS; nudge by ear from there")
                    Text(String(format: "%+.1f dB", gainDB)).font(.caption.monospacedDigit()).frame(width: 52)
                }
            }
            HStack(spacing: 8) {
                Button(store.previewingMemory == memory ? "Stop" : "Play") {
                    if store.previewingMemory == memory { store.stopPreview() } else { store.preview(memory: memory) }
                }
                .keyboardShortcut(.space, modifiers: [])
                .help("Play the trimmed clip on this Mac (Space)")
                Button("Auto-trim") {
                    store.autoTrim(memory: memory)
                    reload()
                }
                .help("Find the voice again and keep 120 ms each side")
                Button("Normalize") {
                    store.normalize(memory: memory)
                    gainDB = Double(store.set[memory]?.gainDB ?? 0)
                }
                .help("Set the gain so the peak sits at −1 dBFS")
                Button("Reset gain") {
                    store.setGain(memory: memory, dB: 0)
                    gainDB = 0
                }
                .disabled(gainDB == 0)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            Text(String(format: "Kept: %.2f s of %.2f s", max(0, end - start), duration))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .onAppear(perform: reload)
        .onDisappear { store.stopPreview() }
    }

    private func reload() {
        full = store.fullAudio(memory: memory)
        bins = full?.waveform(bins: 140) ?? []
        start = store.set[memory]?.trimStart ?? 0
        end = store.set[memory]?.trimEnd ?? duration
        gainDB = Double(store.set[memory]?.gainDB ?? 0)
    }

    private func commit() {
        if end < start { end = start }
        store.setTrim(memory: memory, start: start, end: end)
    }
}

/// The whole clip, with the kept region drawn strong and the trimmed ends
/// faded. `start` and `end` are fractions of the width.
struct TrimWaveform: View {
    let bins: [Float]
    let start: Double
    let end: Double

    var body: some View {
        Canvas { context, size in
            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4),
                         with: .color(.primary.opacity(0.06)))
            guard !bins.isEmpty else { return }
            let step = size.width / CGFloat(bins.count)
            for (i, peak) in bins.enumerated() {
                let x = CGFloat(i) * step
                let fraction = Double(i) / Double(bins.count)
                let kept = fraction >= start && fraction <= end
                let h = max(1, CGFloat(min(1, peak)) * (size.height - 4))
                let rect = CGRect(x: x, y: (size.height - h) / 2, width: max(1, step - 1), height: h)
                context.fill(Path(rect), with: .color(kept ? .accentColor : .secondary.opacity(0.35)))
            }
            for fraction in [start, end] {
                let x = size.width * CGFloat(min(1, max(0, fraction)))
                context.stroke(Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) },
                               with: .color(.orange), lineWidth: 2)
            }
        }
    }
}
