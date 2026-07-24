import SwiftUI

/// Editor for the F1–F8 CW messages.
struct MessagesEditor: View {
    @Bindable var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CW Messages")
                .font(.title3.weight(.semibold))
            Text("Macros: {MYCALL}  {CALL}  {RST}  {EXCH} — prosigns: ( KN   + AR   = BT   * SK")
                .font(.caption)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                ForEach(0..<8, id: \.self) { index in
                    GridRow {
                        Text("F\(index + 1)")
                            .font(.callout.weight(.bold))
                            .frame(width: 30, alignment: .trailing)
                        TextField("", text: binding(index))
                            .font(.body.monospaced())
                            .frame(width: 360)
                    }
                }
            }

            HStack {
                Button("Restore Defaults") {
                    settings.messages = AppSettings.defaultMessages
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private func binding(_ index: Int) -> Binding<String> {
        Binding(
            get: { settings.messages.indices.contains(index) ? settings.messages[index] : "" },
            set: { newValue in
                var messages = settings.messages
                while messages.count < 8 { messages.append("") }
                messages[index] = newValue
                settings.messages = messages
            }
        )
    }
}
