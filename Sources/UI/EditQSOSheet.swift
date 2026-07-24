import SwiftUI

/// Edit a single logged row with the same validation as the entry bar.
struct EditQSOSheet: View {
    let original: QSO
    let party: PartyDefinition?
    let onSave: (QSO) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var call = ""
    @State private var rstSent = ""
    @State private var rstRcvd = ""
    @State private var theirLoc = ""
    @State private var myLoc = ""
    @State private var band: Band = .m20
    @State private var rawMode = "CW"
    @State private var validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Contact")
                .font(.title3.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Call")
                    TextField("", text: $call)
                        .font(.body.monospaced())
                        .frame(width: 140)
                }
                GridRow {
                    Text("Band / Mode")
                    HStack {
                        Picker("", selection: $band) {
                            ForEach(party?.validBands ?? Band.allCases) { band in
                                Text(band.rawValue).tag(band)
                            }
                        }
                        .frame(width: 90)
                        Picker("", selection: $rawMode) {
                            ForEach(["CW", "SSB", "RTTY"], id: \.self) { Text($0).tag($0) }
                        }
                        .frame(width: 90)
                    }
                }
                GridRow {
                    Text("RST sent / rcvd")
                    HStack {
                        TextField("", text: $rstSent).frame(width: 60)
                        TextField("", text: $rstRcvd).frame(width: 60)
                    }
                }
                GridRow {
                    Text("My exchange")
                    TextField("", text: $myLoc)
                        .font(.body.monospaced())
                        .frame(width: 100)
                }
                GridRow {
                    Text("Their exchange")
                    TextField("", text: $theirLoc)
                        .font(.body.monospaced())
                        .frame(width: 100)
                }
            }

            if let message = validationMessage {
                Label(message, systemImage: "xmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            call = original.call
            rstSent = original.rstSent
            rstRcvd = original.rstRcvd
            theirLoc = original.theirLoc
            myLoc = original.myLoc
            band = original.band
            rawMode = original.rawMode
        }
    }

    private func save() {
        let theirTrimmed = theirLoc.trimmingCharacters(in: .whitespaces).uppercased()
        if let party {
            // A row holds exactly one location per side.
            let parsed = ExchangeParser.parse(theirTrimmed, party: party)
            switch parsed {
            case .failure(let error):
                validationMessage = error.localizedDescription
                return
            case .success(let exchange) where exchange.locations.count != 1:
                validationMessage = "One location per row — use separate rows for county lines."
                return
            case .success:
                break
            }
        }
        var updated = original
        updated.call = call.trimmingCharacters(in: .whitespaces).uppercased()
        updated.rstSent = rstSent.trimmingCharacters(in: .whitespaces)
        updated.rstRcvd = rstRcvd.trimmingCharacters(in: .whitespaces)
        updated.theirLoc = theirTrimmed
        updated.myLoc = myLoc.trimmingCharacters(in: .whitespaces).uppercased()
        updated.band = band
        updated.rawMode = rawMode
        updated.modeClass = ModeClass.classify(rawMode: rawMode)
        onSave(updated)
        dismiss()
    }
}
