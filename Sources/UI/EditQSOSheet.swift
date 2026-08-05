import SwiftUI

/// Edit a single logged row with the same validation as the entry bar.
struct EditQSOSheet: View {
    let original: QSO
    let party: PartyDefinition?
    /// Where the log says this station is operating from — the edit sheet
    /// validates against exactly what the entry bar accepts.
    let role: ExchangeParser.Role
    let onSave: (QSO) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var call = ""
    @State private var rstSent = ""
    @State private var rstRcvd = ""
    @State private var serialSent = ""
    @State private var serialRcvd = ""
    @State private var nameSent = ""
    @State private var nameRcvd = ""
    @State private var memberSent = ""
    @State private var memberRcvd = ""
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
                    TextField("", text: $call.uppercasing)
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
                            ForEach(RadioBar.rawModes(for: party), id: \.self) { Text($0).tag($0) }
                        }
                        .frame(width: 90)
                    }
                }
                if party?.exchangeIncludesRST ?? true {
                    GridRow {
                        Text("RST sent / rcvd")
                        HStack {
                            TextField("", text: $rstSent).frame(width: 60)
                            TextField("", text: $rstRcvd).frame(width: 60)
                        }
                    }
                }
                // A mistyped QSO number is the one thing an operator must be
                // able to correct after the fact, since the log checker cross-
                // references it against the other station's log.
                if party?.exchangeIncludesSerial ?? false {
                    GridRow {
                        Text("QSO nr sent / rcvd")
                        HStack {
                            TextField("", text: $serialSent).frame(width: 60)
                            TextField("", text: $serialRcvd).frame(width: 60)
                        }
                    }
                }
                // A miscopied name costs the contact at log checking exactly
                // as a serial does, so it is editable the same way.
                if party?.exchangeIncludesName ?? false {
                    GridRow {
                        Text("Name sent / rcvd")
                        HStack {
                            TextField("", text: $nameSent.uppercasing).frame(width: 90)
                            TextField("", text: $nameRcvd.uppercasing).frame(width: 90)
                        }
                    }
                }
                // The member element decides the QSO's points (Skeeter 3 /
                // QRP 2 / QRO 1), so a miscopied one moves the score — it
                // must be correctable after the fact.
                if let member = party?.memberExchange {
                    GridRow {
                        Text("\(member.shortTerm) sent / rcvd")
                        HStack {
                            TextField("", text: $memberSent.uppercasing).frame(width: 90)
                            TextField("", text: $memberRcvd.uppercasing).frame(width: 90)
                        }
                    }
                }
                GridRow {
                    Text("My exchange")
                    TextField("", text: $myLoc.uppercasing)
                        .font(.body.monospaced())
                        .frame(width: 100)
                }
                GridRow {
                    Text("Their exchange")
                    TextField("", text: $theirLoc.uppercasing)
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
            serialSent = original.serialSent.map(String.init) ?? ""
            serialRcvd = original.serialRcvd.map(String.init) ?? ""
            nameSent = original.nameSent ?? ""
            nameRcvd = original.nameRcvd ?? ""
            memberSent = original.memberSent ?? ""
            memberRcvd = original.memberRcvd ?? ""
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
            let parsed = ExchangeParser.parse(theirTrimmed, party: party, role: role)
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
        updated.serialSent = Int(serialSent.trimmingCharacters(in: .whitespaces))
        updated.serialRcvd = Int(serialRcvd.trimmingCharacters(in: .whitespaces))
        let sentName = nameSent.trimmingCharacters(in: .whitespaces).uppercased()
        let rcvdName = nameRcvd.trimmingCharacters(in: .whitespaces).uppercased()
        updated.nameSent = sentName.isEmpty ? nil : sentName
        updated.nameRcvd = rcvdName.isEmpty ? nil : rcvdName
        let sentMember = memberSent.trimmingCharacters(in: .whitespaces).uppercased()
        let rcvdMember = memberRcvd.trimmingCharacters(in: .whitespaces).uppercased()
        updated.memberSent = sentMember.isEmpty ? nil : sentMember
        updated.memberRcvd = rcvdMember.isEmpty ? nil : rcvdMember
        updated.theirLoc = theirTrimmed
        updated.myLoc = myLoc.trimmingCharacters(in: .whitespaces).uppercased()
        updated.band = band
        updated.rawMode = rawMode
        updated.modeClass = ModeClass.classify(rawMode: rawMode)
        onSave(updated)
        dismiss()
    }
}
