import SwiftUI

/// The RUMlog toolbar popover: send every QSO to RUMlogNG as it is logged
/// (N1MM's UDP contact packets), where to, what has left this Mac, and the
/// whole-log resend. Status is inline and never a modal; *sent* means the
/// datagram left, since UDP carries no reply.
struct QSOBroadcastPane: View {
    let broadcaster: QSOBroadcaster
    /// ⇧⌘L's action, so the button and the key do exactly the same thing.
    let sendWholeLog: () -> Void
    @State private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send QSOs to RUMlogNG")
                .font(.headline)
            Text("Every contact you log, edit or delete goes to RUMlogNG the "
                 + "moment it happens, in the UDP packets N1MM Logger+ "
                 + "broadcasts — so the contest never needs importing.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Send QSOs as they are logged", isOn: $settings.qsoBroadcastEnabled)

            HStack(spacing: 6) {
                Text("Host")
                    .font(.callout)
                TextField(AppSettings.defaultQSOBroadcastHost, text: $settings.qsoBroadcastHost)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                Text("Port")
                    .font(.callout)
                TextField("Port", value: $settings.qsoBroadcastPort, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
            }

            Text(broadcaster.status.text)
                .font(.caption)
                .foregroundStyle(broadcaster.status.isFailure
                                 ? AnyShapeStyle(Color.orange)
                                 : AnyShapeStyle(.secondary))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Button(broadcaster.isSendingWholeLog ? "Stop" : "Send Whole Log Now") {
                    sendWholeLog()
                }
                .disabled(!settings.qsoBroadcastEnabled)
                .shortcutHint("⇧⌘L")
                Text("Every row again, oldest first — for a log made before this "
                     + "was on, or a RUMlogNG that wasn't running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("In RUMlogNG: Preferences › UDP › QSOs received from N1MM — "
                 + "Save QSO, port 12060. Sent means the packet left this Mac; "
                 + "UDP carries no reply, so RUMlogNG's log is the check. "
                 + "Another Mac's address works too — macOS asks for Local "
                 + "Network permission the first time.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 360)
    }
}
