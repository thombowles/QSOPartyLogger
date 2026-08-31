import SwiftUI

/// Lookup credentials — QRZ and HamQTH, each with a Check button that makes
/// one live session request and reports inline by the control (never a
/// modal, and the button claims nothing before it has been pressed).
/// Passwords go to the login keychain the moment Check is pressed —
/// usernames and toggles to defaults; a password never lands in defaults.
struct CallbookSettingsPane: View {
    let client: CallbookClient
    @State private var settings = AppSettings.shared
    @State private var qrzPassword = ""
    @State private var hamqthPassword = ""
    @State private var qrzStatus: String?
    @State private var hamqthStatus: String?
    // The shared caching store, not a fresh KeychainStore: the pane's saves
    // must feed the same cache the lookup client reads, or a new password
    // would sit behind a stale miss until relaunch.
    private let credentials: CredentialStore = CachingCredentialStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Callsign Lookup")
                .font(.headline)
            Text("Shows who a call is — name, state, grid, distance — under "
                 + "the entry row. Advisory only: a lookup never fills an "
                 + "exchange field. In a POTA log the record is also saved "
                 + "into the QSO for richer ADIF.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            servicePane(.qrz, enabled: $settings.qrzEnabled,
                        username: $settings.qrzUsername,
                        password: $qrzPassword, status: qrzStatus,
                        note: "Free accounts return limited fields; the XML "
                            + "subscription returns the full record.")
            servicePane(.hamqth, enabled: $settings.hamqthEnabled,
                        username: $settings.hamqthUsername,
                        password: $hamqthPassword, status: hamqthStatus,
                        note: "Free — register at hamqth.com.")

            if settings.qrzEnabled && settings.hamqthEnabled {
                Picker("Try first", selection: primaryBinding) {
                    ForEach(CallbookService.allCases, id: \.self) {
                        Text($0.label).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            Text("Checking saves the password to your login keychain. "
                 + "Answers are cached for a month per call.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 360)
        .onAppear {
            qrzPassword = credentials.password(
                service: CallbookService.qrz.keychainService,
                account: settings.qrzUsername) ?? ""
            hamqthPassword = credentials.password(
                service: CallbookService.hamqth.keychainService,
                account: settings.hamqthUsername) ?? ""
        }
    }

    private var primaryBinding: Binding<CallbookService> {
        Binding(
            get: { settings.callbookPrimary ?? .hamqth },
            set: { settings.callbookPrimaryRaw = $0.rawValue }
        )
    }

    @ViewBuilder
    private func servicePane(_ service: CallbookService, enabled: Binding<Bool>,
                             username: Binding<String>, password: Binding<String>,
                             status: String?, note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(service.label, isOn: enabled)
            if enabled.wrappedValue {
                HStack(spacing: 6) {
                    TextField("Username", text: username)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                    SecureField("Password", text: password)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                    Button("Check") {
                        credentials.set(password.wrappedValue,
                                        service: service.keychainService,
                                        account: username.wrappedValue)
                        Task {
                            let verdict = await client.checkCredentials(service)
                            switch service {
                            case .qrz: qrzStatus = verdict
                            case .hamqth: hamqthStatus = verdict
                            }
                        }
                    }
                    .disabled(username.wrappedValue.isEmpty
                              || password.wrappedValue.isEmpty)
                }
                if let status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(status.contains("accepted")
                                         ? AnyShapeStyle(Color.green)
                                         : AnyShapeStyle(Color.orange))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
