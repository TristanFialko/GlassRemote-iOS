import SwiftUI

/// Connection settings for Android TV Remote v2: enable, pair with the code the TV shows, forget.
struct RemoteV2SettingsSection: View {
    @EnvironmentObject private var remote: RemoteModel
    @ObservedObject private var v2 = RemoteV2Controller.shared
    @State private var code = ""

    private var codeComplete: Bool {
        code.trimmingCharacters(in: .whitespacesAndNewlines).count == 6
    }

    var body: some View {
        Section {
            Toggle("Use Android TV Remote v2", isOn: $v2.enabled)
            if v2.enabled {
                Text(RemoteV2StatusText.summary(v2: v2.link, adbReady: remote.connected))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if v2.pairingPhase == .awaitingCode && v2.pairingActive {
                    TextField("Code shown on the TV", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .onSubmit { if codeComplete { v2.submitCode(code) } }
                    Button("Pair") { v2.submitCode(code) }
                        .disabled(!codeComplete)
                    Button("Cancel pairing", role: .cancel) { v2.cancelPairing() }
                } else if v2.pairingActive {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Waiting for the TV…")
                    }
                    Button("Cancel pairing", role: .cancel) { v2.cancelPairing() }
                } else {
                    Button(v2.isPaired ? "Pair again" : "Pair with the TV box") {
                        code = ""
                        v2.startPairing()
                    }
                    if v2.isPaired {
                        Button("Forget Remote v2 pairing", role: .destructive) { v2.forgetPairing() }
                    }
                }
                if let message = v2.pairingMessage {
                    Text(message).font(.footnote)
                }
            }
        } header: {
            Text("Android TV Remote v2")
        } footer: {
            Text("When connected, D-pad, OK, Back and Home use the Android TV Remote protocol (the same one as Google's remote app) at the TV box address; otherwise they use ADB as before. Typing, trackpad, the app list, diagnostics and helpers always use ADB. Volume and mute always follow \"Volume goes to\" and are never sent over Remote v2.")
        }
    }
}
