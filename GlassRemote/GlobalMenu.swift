import SwiftUI

/// Pure description of the header's power menu (unit tested). Power actions live ONLY here, so the
/// global menu never repeats them.
enum PowerMenu {
    enum Item: Equatable { case standby, wake, restartLauncher, tvPower, turnOffBoth, restartBox }

    /// Box actions first, then TV actions (only when the Samsung link is enabled), then the
    /// destructive restart last and visually separate.
    static func items(samsungEnabled: Bool) -> [Item] {
        var items: [Item] = [.standby, .wake, .restartLauncher]
        if samsungEnabled { items += [.tvPower, .turnOffBoth] }
        items.append(.restartBox)
        return items
    }

    static func powerAction(for item: Item) -> PowerAction? {
        switch item {
        case .standby: return .standby
        case .restartLauncher: return .restartLauncher
        case .restartBox: return .restartBox
        case .turnOffBoth: return .everythingOff
        case .wake, .tvPower: return nil   // no confirmation needed
        }
    }
}

/// Pure description of the global menu's sections (unit tested). Nothing in here duplicates a
/// control that is already on the Remote page or in the power menu.
enum GlobalMenuSpec {
    enum Section: Equatable { case device, samsung, advanced }
    enum Entry: Equatable {
        // Device
        case connection, reconnectBox, reconnectSamsung
        // Samsung TV
        case samsungKeys, routeVolume, setUpSamsung
        // Advanced
        case screenshot, deviceInfo
    }

    static func entries(in section: Section, boxOnline: Bool, samsungEnabled: Bool, samsungConnected: Bool) -> [Entry] {
        switch section {
        case .device:
            var list: [Entry] = [.connection]
            if !boxOnline { list.append(.reconnectBox) }
            if samsungEnabled && !samsungConnected { list.append(.reconnectSamsung) }
            return list
        case .samsung:
            return samsungEnabled ? [.samsungKeys, .routeVolume] : [.setUpSamsung]
        case .advanced:
            return [.screenshot, .deviceInfo]
        }
    }
}

/// The header's menu button (top left). Central place for connection management, Samsung-only
/// keys and advanced tools. The connection capsule next to it only shows status.
struct GlobalMenuButton: View {
    @EnvironmentObject private var remote: RemoteModel
    let boxOnline: Bool
    let onScreenshot: () -> Void
    let onDeviceInfo: () -> Void

    private var samsungOn: Bool { remote.tvVolumeEnabled }
    private var samsungConnected: Bool { remote.samsungState == .connected }

    var body: some View {
        Menu {
            Section("Device") {
                ForEach(entries(.device), id: \.self) { entry in view(for: entry) }
            }
            Section("Samsung TV") {
                ForEach(entries(.samsung), id: \.self) { entry in view(for: entry) }
            }
            Section("Advanced") {
                ForEach(entries(.advanced), id: \.self) { entry in view(for: entry) }
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .scaledFont(17, .medium)
                .frame(width: 44, height: 44)
                .glassSurface(Circle(), interactive: true)
        }
        .accessibilityLabel("Menu")
        .accessibilityHint("Connections, Samsung TV keys and advanced tools")
    }

    private func entries(_ section: GlobalMenuSpec.Section) -> [GlobalMenuSpec.Entry] {
        GlobalMenuSpec.entries(in: section, boxOnline: boxOnline,
                               samsungEnabled: samsungOn, samsungConnected: samsungConnected)
    }

    @ViewBuilder
    private func view(for entry: GlobalMenuSpec.Entry) -> some View {
        switch entry {
        case .connection:
            Button { remote.showConnection = true } label: {
                Label("Connections and devices", systemImage: "slider.horizontal.3")
            }
        case .reconnectBox:
            Button { remote.connect() } label: { Label("Reconnect Android TV", systemImage: "arrow.clockwise") }
        case .reconnectSamsung:
            Button { remote.reconnectTV() } label: { Label("Reconnect Samsung TV", systemImage: "arrow.clockwise") }
        case .samsungKeys:
            Menu {
                ForEach(SamsungRemoteLayout.menuKeys, id: \.key) { item in
                    Button { remote.samsungKey(item.key) } label: { Label(item.title, systemImage: item.symbol) }
                        .disabled(!remote.samsungRemoteReady)
                }
            } label: { Label("TV keys", systemImage: "tv") }
        case .routeVolume:
            Toggle(isOn: $remote.tvVolumeEnabled) { Label("Volume through Samsung TV", systemImage: "speaker.wave.2") }
        case .setUpSamsung:
            Button { remote.showConnection = true } label: { Label("Set up Samsung TV", systemImage: "tv.badge.wifi") }
        case .screenshot:
            Button(action: onScreenshot) { Label("TV screenshot", systemImage: "camera.viewfinder") }
                .disabled(!remote.connected)
        case .deviceInfo:
            Button(action: onDeviceInfo) { Label("Device information", systemImage: "info.circle") }
        }
    }
}

/// The header's power menu: the only place power actions appear.
struct PowerMenuButton: View {
    @EnvironmentObject private var remote: RemoteModel
    let onConfirm: (PowerAction) -> Void

    var body: some View {
        Menu {
            let items = PowerMenu.items(samsungEnabled: remote.tvVolumeEnabled)
            ForEach(items, id: \.self) { item in
                switch item {
                case .restartBox:
                    Divider()
                    Button(role: .destructive) { onConfirm(.restartBox) } label: { Label("Restart TV box", systemImage: "power") }
                case .tvPower:
                    Divider()
                    Button { remote.tvKey("TV_POWER") } label: { Label("TV power", systemImage: "tv") }
                case .turnOffBoth:
                    Button { onConfirm(.everythingOff) } label: { Label("Turn off box and TV", systemImage: "power.circle") }
                case .standby:
                    Button { onConfirm(.standby) } label: { Label("Standby", systemImage: "moon.zzz") }
                case .wake:
                    Button { remote.wake() } label: { Label("Wake", systemImage: "sun.max") }
                case .restartLauncher:
                    Button { onConfirm(.restartLauncher) } label: { Label("Restart launcher", systemImage: "arrow.clockwise") }
                }
            }
        } label: {
            Image(systemName: "power")
                .scaledFont(17, .medium)
                .frame(width: 44, height: 44)
                .glassSurface(Circle(), interactive: true)
        }
        .accessibilityLabel("Power")
    }
}

/// Connection details and diagnostics (moved here from the old Apps page).
struct DeviceInfoSheet: View {
    @EnvironmentObject private var remote: RemoteModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Android TV box") {
                    row("Address", "\(remote.host):\(remote.port)")
                    row("Link", remote.connected ? "Connected" : "Not connected")
                    row("Keyboard helper", remote.keyboardStatus)
                    row("Pointer helper", remote.cursorStatus)
                }
                Section("Samsung TV") {
                    row("Control", remote.tvVolumeEnabled ? "On" : "Off")
                    if remote.tvVolumeEnabled {
                        row("Address", remote.samsungHost)
                        row("Link", remote.samsungState.label)
                        row("Status", remote.samsungStatus)
                        row("Volume range", "\(remote.volumeCalibration.lo)–\(remote.volumeCalibration.hi)")
                    }
                }
                Section("Diagnostics") {
                    row("Last status", remote.status)
                    row("Samsung keys", remote.samsungDiagnostics)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AmbientBackdrop() }
            .navigationTitle("Device information")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .font(.footnote)
    }
}
