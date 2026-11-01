import SwiftUI

struct ConnectionSheet: View {
    @EnvironmentObject private var remote: RemoteModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Android TV") {
                    TextField("IP address", text: $remote.host)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                    TextField("ADB port", text: $remote.port).keyboardType(.numberPad)
                    Button(remote.connected ? "Disconnect" : "Connect directly") {
                        if remote.connected { remote.disconnect() } else { remote.connect() }
                    }
                }

                Section("Volume") {
                    Toggle("Route volume through Samsung TV", isOn: $remote.tvVolumeEnabled)
                    if remote.tvVolumeEnabled {
                        TextField("Samsung TV IP address", text: $remote.samsungHost)
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit { remote.reconnectTV() }
                        Button("Connect to Samsung TV") { remote.reconnectTV() }
                        Text(remote.samsungStatus).font(.footnote).foregroundStyle(.secondary)
                        Text(remote.volumeStatus).font(.footnote).textSelection(.enabled)
                        Stepper("Soundbar max volume: \(remote.tvVolumeMax)", value: $remote.tvVolumeMax, in: 5...200)
                        Text("Set this to the highest number your soundbar shows. The slider spans this whole range, so full slider = soundbar maximum.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("When this is off, or the TV cannot be reached, the volume buttons use ADB as before. The app connects to the Samsung TV automatically and retries if it is unreachable.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Status") {
                    Text(remote.status).font(.footnote).textSelection(.enabled)
                    Text(remote.keyboardStatus).font(.footnote).textSelection(.enabled)
                    Text(remote.cursorStatus).font(.footnote).textSelection(.enabled)
                }

                Section {
                    Text("The first connection may show an ADB authorization prompt on the TV. Approve the Glass Remote host key. Keep the TV and iPhone on the same trusted Wi-Fi network.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackdrop() }
            .navigationTitle("Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { remote.showConnection = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}
