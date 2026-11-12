import SwiftUI

struct ConnectionSheet: View {
    @EnvironmentObject private var remote: RemoteModel

    @State private var scanning = false
    @State private var scanned = false
    @State private var androidHits: [String] = []
    @State private var samsungHits: [String] = []
    @State private var confirmSamsungReset = false

    private func scan() {
        guard !scanning else { return }
        scanning = true
        Task {
            async let android = remote.discover(port: 5555)
            async let samsung = remote.discover(port: 8002)
            let results = await (android, samsung)
            androidHits = results.0
            samsungHits = results.1
            scanning = false
            scanned = true
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if remote.isFirstRun && !remote.connected {
                    Section {
                        Text("Welcome. Turn on network debugging (ADB) on your Android TV box, keep it and this iPhone on the same Wi-Fi, then pick it below.")
                            .font(.footnote)
                    }
                }

                Section("Find devices") {
                    Button {
                        scan()
                    } label: {
                        HStack {
                            Text(scanning ? "Scanning your Wi-Fi…" : "Scan Wi-Fi for devices")
                            if scanning { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(scanning)
                    ForEach(androidHits, id: \.self) { ip in
                        Button("Use \(ip) as Android TV box") {
                            remote.host = ip
                            remote.port = "5555"
                        }
                    }
                    ForEach(samsungHits, id: \.self) { ip in
                        Button("Use \(ip) as Samsung TV") {
                            remote.samsungHost = ip
                            remote.tvVolumeEnabled = true
                        }
                    }
                    if scanned && androidHits.isEmpty && samsungHits.isEmpty {
                        Text("Nothing answered. Check that ADB network debugging is on and both devices share this Wi-Fi, or enter the address by hand.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

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
                    Picker("Volume goes to", selection: $remote.volumeOutput) {
                        ForEach(VolumeOutput.allCases) { output in
                            Text(output.label).tag(output)
                        }
                    }
                    Text(remote.volumeRouteSummary).font(.footnote).foregroundStyle(.secondary)
                    Toggle("Samsung TV link", isOn: $remote.tvVolumeEnabled)
                    if remote.tvVolumeEnabled {
                        TextField("Samsung TV IP address", text: $remote.samsungHost)
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit { remote.reconnectTV() }
                        Button("Connect to Samsung TV") { remote.reconnectTV() }
                        Text(remote.samsungStatus).font(.footnote).foregroundStyle(.secondary)
                        Text("Remote (WebSocket): \(remote.samsungState.label)").font(.footnote).foregroundStyle(.secondary)
                        Text("Volume link (UPnP): \(remote.samsungVolumeReady ? "Ready" : "Not available") · the two work independently")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text(remote.samsungDiagnostics).font(.footnote).foregroundStyle(.secondary)
                        if !remote.samsungPairingDiagnostics.isEmpty {
                            Text(remote.samsungPairingDiagnostics).font(.footnote).foregroundStyle(.secondary)
                        }
                        Button("Reconnect remote only") { remote.reconnectTV() }
                        Button("Reset Samsung pairing…", role: .destructive) { confirmSamsungReset = true }
                            .accessibilityHint("Forgets only the Samsung TV approval, then asks the TV again")
                        Button("Reconnect volume link only") { remote.reconnectVolumeLink() }
                        Button("Test hold: Right arrow, Press then Release (experimental)") { remote.samsungHoldTest() }
                        Text("Open a menu on the TV first. If focus moves once, Press/Release behaves like a click on this model; if it keeps moving while held, it is a real hold. Normal buttons keep using repeated clicks either way.")
                            .font(.footnote).foregroundStyle(.secondary)
                        SamsungTrackpadSettings()
                        Text("TV volume range used by the slider: \(remote.volumeCalibration.lo)–\(remote.volumeCalibration.hi) (default 0–100; narrowed only if the TV repeatedly stops short of a commanded end)")
                            .font(.footnote).foregroundStyle(.secondary)
                        if remote.volumeCalibration != .standard {
                            Button("Reset volume range to 0–100") { remote.resetVolumeCalibration() }
                            if remote.volumeCalibration.lo > 0 {
                                Text("0 % on the slider means this TV's minimum (\(remote.volumeCalibration.lo)), which is not mute. Use Mute to silence it.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        Text(remote.volumeStatus).font(.footnote).textSelection(.enabled)
                        Stepper("Soundbar max volume: \(remote.tvVolumeMax)", value: $remote.tvVolumeMax, in: 5...200)
                        Text("Set this to the highest number your soundbar shows. The slider spans this whole range, so full slider = soundbar maximum.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("Volume goes only to the Samsung TV. Its remote keys reach whatever is playing, including a soundbar or receiver. The TV's own level (UPnP) is used for an exact 0–100 slider only when it is the output that is playing. When this is off, or the TV cannot be reached, volume is shown as unavailable; it is never sent to the Android box. The app connects to the Samsung TV automatically and retries if it is unreachable.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Pointer") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sensitivity: \(String(format: "%.1f", remote.mouseSensitivity))×")
                        Slider(value: $remote.mouseSensitivity, in: 0.5...4.0, step: 0.1)
                    }
                    Toggle("Faster swipes move further", isOn: $remote.mouseAcceleration)
                    Text("Touch and hold for half a second, then move, to drag. Tap with two fingers for Back.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Status") {
                    Text(remote.status).font(.footnote).textSelection(.enabled)
                    Text(remote.keyboardStatus).font(.footnote).textSelection(.enabled)
                    Text(remote.cursorStatus).font(.footnote).textSelection(.enabled)
                    Button("Retry cursor helper") { remote.retryCursorHelper() }
                        .disabled(!remote.connected)
                }

                Section("Playback diagnostics") {
                    Button("Capture TV playback diagnostics") { remote.capturePlaybackDiagnostics() }
                        .disabled(!remote.connected)
                    Text("After Nuvio stops or reloads, capture this before manually reconnecting. It records recent app/activity events and whether the persistent input helpers are still alive.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(remote.playbackDiagnostics)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxHeight: 240, alignment: .topLeading)
                }

                Section {
                    Text("The first connection may show an ADB authorization prompt on the TV. Approve the Glass Remote host key. Keep the TV and iPhone on the same trusted Wi-Fi network.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackdrop() }
            .task {
                if remote.isFirstRun && !scanned { scan() }
            }
            .navigationTitle("Connection")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Reset Samsung pairing?", isPresented: $confirmSamsungReset, titleVisibility: .visible) {
                Button("Reset Samsung pairing", role: .destructive) { remote.resetSamsungPairing() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(SamsungPairingPolicy.resetExplanation)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { remote.showConnection = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .themedSheet()
    }
}


/// Samsung trackpad tuning (experimental mode on the Remote page).
private struct SamsungTrackpadSettings: View {
    @AppStorage(SamsungTrackpad.sensitivityKey) private var sensitivity = 1.5
    @AppStorage(SamsungTrackpad.accelerationKey) private var acceleration = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Samsung trackpad sensitivity").font(.footnote.weight(.semibold))
            Slider(value: $sensitivity, in: 0.5...3, step: 0.1)
            Toggle("Acceleration", isOn: $acceleration).font(.footnote)
        }
    }
}
