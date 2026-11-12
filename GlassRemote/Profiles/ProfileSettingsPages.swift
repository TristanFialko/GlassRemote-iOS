import SwiftUI
import UIKit

/// Shared chrome for Profile sub-pages: themed backdrop, inline title and room for the dock.
struct ProfileSubpage: ViewModifier {
    let title: String
    @Environment(\.dockClearance) private var clearance

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background { ContinuousBackdrop() }
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: clearance) }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

extension View {
    func profileSubpage(_ title: String) -> some View { modifier(ProfileSubpage(title: title)) }
}

enum AppInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?" }
}

struct ConnectionStatusRow: View {
    let symbol: String
    let title: String
    let detail: String
    let good: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 40, height: 40)
                .background(Circle().fill((good ? Color.green : Color.orange).opacity(0.16)))
                .foregroundStyle(good ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// TV connections. A TV is shared hardware, so pairing belongs to the iPhone, not to a profile:
/// every profile uses the same TV box and Samsung TV links (and the same Keychain pairing keys).
/// The detailed pairing flows stay on the existing, proven Connection screen; this page shows
/// status first and offers one clear action per device.
struct TVConnectionsPage: View {
    @EnvironmentObject private var remote: RemoteModel
    @State private var showPairing = false

    var body: some View {
        List {
            Section {
                ConnectionStatusRow(symbol: "tv.and.mediabox", title: "Android TV box",
                                    detail: remote.connected ? "Connected to \(remote.host):\(remote.port)" : "Saved: \(remote.host):\(remote.port), not connected",
                                    good: remote.connected)
                if remote.connected {
                    Button("Disconnect", role: .destructive) { remote.disconnect() }
                } else {
                    Button { remote.connect() } label: { Label("Reconnect", systemImage: "arrow.clockwise") }
                }
                Button { showPairing = true } label: { Label("Pair a TV box or change address", systemImage: "plus.circle") }
            } header: {
                Text("TV box")
            } footer: {
                Text("Remote, trackpad, keyboard and Nuvio handoff use this ADB connection. Pairing keys stay in this iPhone's Keychain.")
            }

            Section {
                ConnectionStatusRow(symbol: "tv", title: "Samsung TV",
                                    detail: remote.tvVolumeEnabled ? "\(remote.samsungState.label) · \(remote.samsungHost)" : "Volume and power control is off",
                                    good: remote.tvVolumeEnabled && remote.samsungState == .connected)
                if remote.tvVolumeEnabled {
                    Button { remote.reconnectTV() } label: { Label("Reconnect TV control", systemImage: "arrow.clockwise") }
                    Button { remote.reconnectVolumeLink() } label: { Label("Restart volume link", systemImage: "speaker.wave.2") }
                    Text(remote.samsungStatus).font(.footnote).foregroundStyle(.secondary)
                }
                Button { showPairing = true } label: { Label("Samsung TV settings", systemImage: "slider.horizontal.3") }
            } header: {
                Text("Samsung TV")
            } footer: {
                Text("The TV asks you to allow GlassRemote the first time; the token it issues is stored in the Keychain.")
            }

            Section {
                Text("TVs are shared by every profile, so switching profile never disconnects or re-pairs a TV.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .profileSubpage("TV Connections")
        .sheet(isPresented: $showPairing) { ConnectionSheet().environmentObject(remote) }
    }
}

/// Device information (moved here from the Remote's menu, which still offers it too).
struct DevicesPage: View {
    var body: some View {
        DeviceInfoList {
            Section("This iPhone") {
                DeviceInfoRow("Model", UIDevice.current.model)
                DeviceInfoRow("System", "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
                DeviceInfoRow("GlassRemote", "\(AppInfo.version) (\(AppInfo.build))")
            }
        }
        .profileSubpage("Devices")
    }
}

struct AppearancePage: View {
    @ObservedObject private var profiles = ProfileStore.shared
    @ObservedObject private var themes = ThemeStore.shared
    @State private var showThemes = false

    var body: some View {
        List {
            Section {
                Button {
                    showThemes = true
                } label: {
                    HStack {
                        Label("Theme", systemImage: "paintpalette")
                        Spacer()
                        Text(themes.selected.title).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Theme")
            } footer: {
                Text("Each profile remembers its own theme. Adaptive follows the artwork on screen; Auto follows the system appearance.")
            }
            Section {
                Picker("Artwork", selection: Binding(
                    get: { profiles.active.settings.posterOrientation },
                    set: { value in profiles.updateSettings { $0.posterOrientation = value } })) {
                    ForEach(PosterOrientation.allCases) { option in Text(option.title).tag(option) }
                }
                .pickerStyle(.segmented)
                Toggle("Show Continue Watching", isOn: Binding(
                    get: { profiles.active.settings.showContinueWatching },
                    set: { value in profiles.updateSettings { $0.showContinueWatching = value } }))
            } header: {
                Text("Discover")
            } footer: {
                Text("Automatic uses posters for catalogues and wide artwork for titles in progress. Artwork is never stretched; when the chosen shape is missing, the other image is used.")
            }
            Section {
                Toggle("Reduce interface motion", isOn: Binding(
                    get: { profiles.active.settings.reduceInterfaceMotion },
                    set: { value in profiles.updateSettings { $0.reduceInterfaceMotion = value } }))
            } header: {
                Text("Motion")
            } footer: {
                Text("Replaces springs and slides with quick fades for this profile. The system Reduce Motion setting always applies as well.")
            }
        }
        .profileSubpage("Appearance")
        .sheet(isPresented: $showThemes) { ThemePickerSheet() }
    }
}

struct GeneralSettingsPage: View {
    @State private var showNuvio = false

    var body: some View {
        List {
            Section("Nuvio") {
                Button { showNuvio = true } label: { Label("Nuvio account", systemImage: "person.badge.key") }
            }
            Section {
                Text("Profiles, photos and add-on lists are stored only on this iPhone. Add-on links (which can contain personal tokens) and TV pairing keys are kept in the Keychain, and add-on links are never written to logs.")
                    .font(.footnote)
            } header: {
                Text("Privacy")
            }
            Section {
                Text("Text follows Dynamic Type and animations follow the system Reduce Motion setting. Appearance has an extra switch to reduce interface motion.")
                    .font(.footnote)
            } header: {
                Text("Accessibility")
            }
            Section("About") {
                DeviceInfoRow("Version", AppInfo.version)
                DeviceInfoRow("Build", AppInfo.build)
            }
        }
        .profileSubpage("General")
        .sheet(isPresented: $showNuvio) { NuvioAccountSheet() }
    }
}
