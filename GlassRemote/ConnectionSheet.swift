import SwiftUI

struct ConnectionSheet: View {
    @EnvironmentObject private var remote: RemoteModel
    @State private var scanning = false
    @State private var scanned = false
    @State private var androidHits: [String] = []
    @State private var samsungHits: [String] = []

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
            GeometryReader { proxy in
                if proxy.size.width > proxy.size.height {
                    HStack(spacing: 0) {
                        deviceForm
                        operationsForm
                    }
                } else {
                    Form { deviceSections; operationsSections }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackdrop() }
            .task { if remote.isFirstRun && !scanned { scan() } }
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

    private var deviceForm: some View { Form { deviceSections } }
    private var operationsForm: some View { Form { operationsSections } }

    @ViewBuilder
    private var deviceSections: some View {
        if remote.isFirstRun && !remote.connected {
            Section { Text("Welcome. Turn on network debugging on the Android TV box, keep it and this iPhone on the same Wi-Fi, then pick it below.").font(.footnote) }
        }
        Section("Find devices") {
            Button { scan() } label: {
                HStack { Text(scanning ? "Scanning your Wi-Fi…" : "Scan Wi-Fi for devices"); if scanning { Spacer(); ProgressView() } }
            }
            .disabled(scanning)
            ForEach(androidHits, id: \.self) { ip in
                Button("Use \(ip) as Android TV box") { remote.host = ip; remote.port = "5555" }
            }
            ForEach(samsungHits, id: \.self) { ip in
                Button("Use \(ip) as Samsung TV") { remote.samsungHost = ip; remote.tvVolumeEnabled = true }
            }
            if scanned && androidHits.isEmpty && samsungHits.isEmpty {
                Text("Nothing answered. Check ADB network debugging and shared Wi-Fi, or enter the address by hand.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        Section("Android TV") {
            TextField("IP address", text: $remote.host).keyboardType(.numbersAndPunctuation).textInputAutocapitalization(.never)
            TextField("ADB port", text: $remote.port).keyboardType(.numberPad)
            Button(remote.connected ? "Disconnect" : "Connect directly") { if remote.connected { remote.disconnect() } else { remote.connect() } }
        }
        Section("Pointer") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sensitivity: \(String(format: "%.1f", remote.mouseSensitivity))×")
                Slider(value: $remote.mouseSensitivity, in: 0.5...4.0, step: 0.1)
            }
            Toggle("Faster swipes move further", isOn: $remote.mouseAcceleration)
            Text("Touch and hold for half a second, then move, to drag. Tap with two fingers for Back.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var operationsSections: some View {
        Section("Volume") {
            Toggle("Route volume through Samsung TV", isOn: $remote.tvVolumeEnabled)
            if remote.tvVolumeEnabled {
                TextField("Samsung TV IP address", text: $remote.samsungHost).keyboardType(.numbersAndPunctuation).textInputAutocapitalization(.never).autocorrectionDisabled().onSubmit { remote.reconnectTV() }
                Button("Connect to Samsung TV") { remote.reconnectTV() }
                Text(remote.samsungStatus).font(.footnote).foregroundStyle(.secondary)
                Text(remote.volumeStatus).font(.footnote).textSelection(.enabled)
                Stepper("Soundbar max volume: \(remote.tvVolumeMax)", value: $remote.tvVolumeMax, in: 5...200)
                Text("Set this to the highest number your soundbar shows. The slider spans this whole range.").font(.footnote).foregroundStyle(.secondary)
            }
            Text("When this is off, or the TV cannot be reached, volume uses ADB as before.").font(.footnote).foregroundStyle(.secondary)
        }
        Section("Status") {
            Text(remote.status).font(.footnote).textSelection(.enabled)
            Text(remote.keyboardStatus).font(.footnote).textSelection(.enabled)
            Text(remote.cursorStatus).font(.footnote).textSelection(.enabled)
            Button("Retry cursor helper") { remote.retryCursorHelper() }.disabled(!remote.connected)
        }
        Section("Playback diagnostics") {
            Button("Capture TV playback diagnostics") { remote.capturePlaybackDiagnostics() }.disabled(!remote.connected)
            Text("Capture this after Stremio stops or reloads to record app/activity events and helper health.").font(.footnote).foregroundStyle(.secondary)
            Text(remote.playbackDiagnostics).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxHeight: 240, alignment: .topLeading)
        }
        Section { Text("The first connection may show an ADB authorization prompt on the TV. Approve the Glass Remote host key on trusted Wi-Fi.").font(.footnote).foregroundStyle(.secondary) }
    }
}
