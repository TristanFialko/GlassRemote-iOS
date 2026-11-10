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
    let onThemes: () -> Void

    private var samsungOn: Bool { remote.tvVolumeEnabled }
    private var samsungConnected: Bool { remote.samsungState == .connected }

    var body: some View {
        Menu {
            Button(action: onThemes) { Label("Themes", systemImage: "paintpalette") }
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
            Image("BrandIcon")
                .resizable().scaledToFill()
                .frame(width: 30, height: 30)
                .clipShape(Circle())
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DeviceInfoList()
                .navigationTitle("Device information")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.large])
        .themedSheet()
    }
}

/// TV box, Samsung TV and diagnostics information. Shown by the Remote menu's sheet and by
/// Profile > Devices, which appends a section about this iPhone and the app.
struct DeviceInfoList<Extra: View>: View {
    @EnvironmentObject private var remote: RemoteModel
    private let extra: Extra

    init(@ViewBuilder extra: () -> Extra) { self.extra = extra() }

    var body: some View {
        List {
            Section("Android TV box") {
                DeviceInfoRow("Address", "\(remote.host):\(remote.port)")
                DeviceInfoRow("Link", remote.connected ? "Connected" : "Not connected")
                DeviceInfoRow("Keyboard helper", remote.keyboardStatus)
                DeviceInfoRow("Pointer helper", remote.cursorStatus)
            }
            Section("Samsung TV") {
                DeviceInfoRow("Control", remote.tvVolumeEnabled ? "On" : "Off")
                if remote.tvVolumeEnabled {
                    DeviceInfoRow("Address", remote.samsungHost)
                    DeviceInfoRow("Link", remote.samsungState.label)
                    DeviceInfoRow("Status", remote.samsungStatus)
                    DeviceInfoRow("Volume range", "\(remote.volumeCalibration.lo)–\(remote.volumeCalibration.hi)")
                }
            }
            Section("Diagnostics") {
                DeviceInfoRow("Last status", remote.status)
                DeviceInfoRow("Samsung keys", remote.samsungDiagnostics)
            }
            extra
        }
        .scrollContentBackground(.hidden)
        .background { AmbientBackdrop() }
    }
}

extension DeviceInfoList where Extra == EmptyView {
    init() { self.init { EmptyView() } }
}

struct DeviceInfoRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .font(.footnote)
    }
}
