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
///
/// Phase 8: TV connections, device information and themes moved to Profile pages (see
/// `movedToProfile`). The menu keeps only live actions plus one shortcut into Profile.
enum GlobalMenuSpec {
    enum Section: Equatable { case device, samsung, advanced }
    enum Entry: Equatable {
        // Device
        case reconnectBox, reconnectSamsung
        // Samsung TV
        case samsungKeys, routeVolume, setUpSamsung
        // Advanced
        case screenshot, profileSettings
    }

    /// Settings that used to live in this menu and the Profile pages that own them now.
    static let movedToProfile: [ProfileRoute] = [.connections, .devices, .appearance]

    static func entries(in section: Section, boxOnline: Bool, samsungEnabled: Bool, samsungConnected: Bool) -> [Entry] {
        switch section {
        case .device:
            var list: [Entry] = []
            if !boxOnline { list.append(.reconnectBox) }
            if samsungEnabled && !samsungConnected { list.append(.reconnectSamsung) }
            return list
        case .samsung:
            return samsungEnabled ? [.samsungKeys, .routeVolume] : [.setUpSamsung]
        case .advanced:
            return [.screenshot, .profileSettings]
        }
    }
}

/// Phase 8: the Remote header's status pill. It shows the selected device and its live link state
/// and opens the menu of live actions (reconnect, TV keys, volume routing, screenshot). Settings
/// (connections, devices, themes) open in Profile.
struct RemoteStatusMenu: View {
    @EnvironmentObject private var remote: RemoteModel
    @EnvironmentObject private var navigator: PageNavigator
    /// Phase 9 §1.2: how much of the device name fits (set by the Remote header).
    var pillStyle: RemoteLayoutPolicy.PillStyle = .full
    let onScreenshot: () -> Void

    // Audit UX-001: a box whose input helpers are down still offers Reconnect.
    private var boxOnline: Bool { remote.linkState == .connected }
    private var samsungOn: Bool { remote.tvVolumeEnabled }
    private var samsungConnected: Bool { remote.samsungState == .connected }

    var body: some View {
        Menu {
            if !entries(.device).isEmpty {
                Section {
                    ForEach(entries(.device), id: \.self) { entry in view(for: entry) }
                } header: {
                    Text("Device")
                } footer: {
                    if let guidance = remote.readiness.guidance { Text(guidance) }
                }
            }
            Section("Samsung TV") {
                ForEach(entries(.samsung), id: \.self) { entry in view(for: entry) }
            }
            Section {
                ForEach(entries(.advanced), id: \.self) { entry in view(for: entry) }
            }
        } label: {
            RemoteStatusPill(style: pillStyle)
        }
        .accessibilityHint("Reconnect, Samsung TV keys and tools")
    }

    private func entries(_ section: GlobalMenuSpec.Section) -> [GlobalMenuSpec.Entry] {
        GlobalMenuSpec.entries(in: section, boxOnline: boxOnline,
                               samsungEnabled: samsungOn, samsungConnected: samsungConnected)
    }

    @ViewBuilder
    private func view(for entry: GlobalMenuSpec.Entry) -> some View {
        switch entry {
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
            Toggle(isOn: $remote.tvVolumeEnabled) { Label("Samsung TV link", systemImage: "tv") }
        case .setUpSamsung:
            Button { navigator.openProfile(.connections) } label: { Label("Set up Samsung TV", systemImage: "tv.badge.wifi") }
        case .screenshot:
            Button(action: onScreenshot) { Label("TV screenshot", systemImage: "camera.viewfinder") }
                .disabled(!remote.connected)
        case .profileSettings:
            Button { navigator.openProfile(.connections) } label: {
                Label("Connections, devices & themes", systemImage: "person.crop.circle")
            }
        }
    }
}

/// The pill itself: device glyph, name and a live status dot (plus a TV dot when volume goes
/// through the Samsung TV). Status only; actions live in the menu it opens.
struct RemoteStatusPill: View {
    @EnvironmentObject private var remote: RemoteModel
    @Environment(\.glassTheme) private var theme
    var style: RemoteLayoutPolicy.PillStyle = .full

    private var boxOnline: Bool { remote.connected && !remote.requiresUserReconnect }

    private var status: (text: String, color: Color) {
        if remote.target == .samsung {
            return (remote.samsungState.label, Self.samsungColor(remote.samsungState))
        }
        switch remote.linkState {
        case .reconnectNeeded: return ("Reconnect needed", .orange)
        case .degraded: return ("Connected · input not ready", .yellow)
        case .connected: return ("Connected", .green)
        case .connecting: return ("Connecting…", .yellow)
        case .offline: return ("Offline", .orange)
        }
    }

    static func samsungColor(_ state: SamsungLinkState) -> Color {
        switch state {
        case .connected: return .green
        case .connecting, .pairing: return .yellow
        case .denied, .unreachable: return .orange
        case .off: return Color.inkFaint(0.35)
        }
    }

    var body: some View {
        let status = self.status
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(theme.accent.opacity(0.22))
                Image(systemName: remote.target.symbol).scaledFont(14, .semibold)
            }
            .frame(width: 32, height: 32)
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(status.color)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1.5))
                    .shadow(color: status.color.opacity(0.8), radius: 4)
                    .offset(x: 2, y: 2)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(style == .full ? remote.target.title : remote.target.shortTitle)
                    .scaledFont(14, .semibold)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(status.text).lineLimit(1)
                    if remote.target == .android && remote.tvVolumeEnabled {
                        HStack(spacing: 3) {
                            Circle().fill(Self.samsungColor(remote.samsungState)).frame(width: 6, height: 6)
                            Text("TV")
                        }
                    }
                }
                .scaledFont(11, .medium)
                .foregroundStyle(Color.inkAlpha(0.62))
            }
            .minimumScaleFactor(0.75)
            .layoutPriority(1)
            Spacer(minLength: 0)
            if style != .compact {
                Image(systemName: "chevron.down")
                    .scaledFont(11, .bold)
                    .foregroundStyle(Color.inkAlpha(0.5))
            }
        }
        .foregroundStyle(Color.ink)
        .padding(.leading, 6)
        .padding(.trailing, style == .compact ? 10 : 14)
        .frame(height: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(Capsule(), interactive: true)
        .contentShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(remote.target.title), \(status.text)"
                            + (remote.target == .android && remote.tvVolumeEnabled ? ", Samsung \(remote.samsungState.label)" : ""))
        .accessibilityAddTraits(.isButton)
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
