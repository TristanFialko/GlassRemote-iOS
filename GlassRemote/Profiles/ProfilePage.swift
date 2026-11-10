import SwiftUI

enum ProfileRoute: Hashable {
    case connections, addons, devices, appearance, general
}

/// Profile tab (Phase 7): who is using the app, plus TV connections, device information, add-ons,
/// appearance and general settings, each on its own page instead of one crowded settings sheet.
struct ProfilePage: View {
    @ObservedObject private var profiles = ProfileStore.shared
    @ObservedObject private var addons = AddonStore.shared
    @ObservedObject private var themes = ThemeStore.shared
    @EnvironmentObject private var remote: RemoteModel
    @Environment(\.dockClearance) private var dockClearance
    @Environment(\.layoutContext) private var layout
    @State private var editor: ProfileEditorTarget?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                Group {
                    if layout.isLandscape {
                        // Landscape: identity on the leading side, the sections beside it.
                        HStack(alignment: .top, spacing: 20) {
                            ProfileHeaderCard(editor: $editor).frame(width: 320)
                            sections
                        }
                    } else {
                        VStack(spacing: 18) {
                            ProfileHeaderCard(editor: $editor)
                            sections
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, dockClearance + 8)
                .frame(maxWidth: 920)
                .frame(maxWidth: .infinity)
            }
            .background { AmbientBackdrop() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ProfileRoute.self) { route in
                destination(route).environmentObject(remote)
            }
        }
        .sheet(item: $editor) { target in ProfileEditorSheet(target: target) }
    }

    private var sections: some View {
        VStack(spacing: 14) {
            GlassCard(padding: 6) {
                VStack(spacing: 0) {
                    NavigationLink(value: ProfileRoute.connections) {
                        ProfileRow(symbol: "tv", title: "TV Connections", detail: connectionSummary,
                                   status: remote.connected ? .green : .orange)
                    }
                    ProfileDivider()
                    NavigationLink(value: ProfileRoute.addons) {
                        ProfileRow(symbol: "puzzlepiece.extension", title: "Add-ons", detail: addonSummary)
                    }
                    ProfileDivider()
                    NavigationLink(value: ProfileRoute.devices) {
                        ProfileRow(symbol: "info.circle", title: "Devices", detail: "TV box, Samsung TV and this iPhone")
                    }
                }
            }
            GlassCard(padding: 6) {
                VStack(spacing: 0) {
                    NavigationLink(value: ProfileRoute.appearance) {
                        ProfileRow(symbol: "paintpalette", title: "Appearance", detail: themes.selected.title)
                    }
                    ProfileDivider()
                    NavigationLink(value: ProfileRoute.general) {
                        ProfileRow(symbol: "gearshape", title: "General", detail: "Nuvio account, privacy, about")
                    }
                }
            }
        }
        .buttonStyle(GlassPressStyle())
    }

    private var connectionSummary: String {
        var parts = [remote.connected ? "TV box connected" : "TV box not connected"]
        if remote.tvVolumeEnabled { parts.append(remote.samsungState == .connected ? "Samsung TV linked" : "Samsung TV not linked") }
        return parts.joined(separator: " · ")
    }

    private var addonSummary: String {
        if addons.addons.isEmpty { return "Add Stremio-compatible add-ons" }
        let enabled = addons.addons.filter(\.enabled).count
        return "\(enabled) of \(addons.addons.count) enabled"
    }

    @ViewBuilder
    private func destination(_ route: ProfileRoute) -> some View {
        switch route {
        case .connections: TVConnectionsPage()
        case .addons: AddonsPage()
        case .devices: DevicesPage()
        case .appearance: AppearancePage()
        case .general: GeneralSettingsPage()
        }
    }
}

private struct ProfileHeaderCard: View {
    @ObservedObject private var profiles = ProfileStore.shared
    @Binding var editor: ProfileEditorTarget?

    var body: some View {
        GlassCard(padding: 20) {
            VStack(spacing: 14) {
                ProfileAvatar(profile: profiles.active, size: 92, ring: true)
                    .id(profiles.activeID)
                    .transition(.scale(scale: 0.88).combined(with: .opacity))
                VStack(spacing: 4) {
                    Text(profiles.active.name)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    Text(profiles.profiles.count == 1 ? "Only profile on this iPhone" : "\(profiles.profiles.count) profiles on this iPhone")
                        .font(.footnote)
                        .foregroundStyle(Color.inkAlpha(0.6))
                }
                Button {
                    editor = .edit(profiles.activeID)
                } label: {
                    Label("Edit profile", systemImage: "pencil")
                }
                .buttonStyle(GlassCapsuleButtonStyle())
                ProfileSwitcher(onAdd: { editor = .create })
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ProfileSwitcher: View {
    @ObservedObject private var profiles = ProfileStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onAdd: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(profiles.profiles) { profile in
                    let active = profile.id == profiles.activeID
                    Button {
                        guard !active else { return }
                        Haptics.soft()
                        withAnimation(Motion.resolve(Motion.theme, reduceMotion: reduceMotion)) { profiles.switchTo(profile.id) }
                    } label: {
                        VStack(spacing: 6) {
                            ProfileAvatar(profile: profile, size: 50, ring: active)
                                .frame(width: 60, height: 60)
                            Text(profile.name)
                                .font(.caption)
                                .lineLimit(1)
                                .frame(maxWidth: 72)
                                .foregroundStyle(Color.ink.opacity(active ? 1 : 0.65))
                        }
                    }
                    .buttonStyle(GlassPressStyle())
                    .accessibilityLabel(profile.name)
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
                if profiles.canAddProfile {
                    Button(action: onAdd) {
                        VStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .semibold))
                                .frame(width: 50, height: 50)
                                .glassSurface(Circle(), interactive: true)
                                .frame(width: 60, height: 60)
                            Text("Add").font(.caption)
                        }
                        .foregroundStyle(Color.ink)
                    }
                    .buttonStyle(GlassPressStyle())
                    .accessibilityLabel("Add profile")
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

struct ProfileRow: View {
    let symbol: String
    let title: String
    var detail: String? = nil
    var status: Color? = nil
    @Environment(\.glassTheme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 36, height: 36)
                .background(Circle().fill(theme.accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(Color.ink)
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(Color.inkAlpha(0.6)).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let status {
                Circle().fill(status).frame(width: 8, height: 8).accessibilityHidden(true)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.inkAlpha(0.35))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

private struct ProfileDivider: View {
    var body: some View {
        Rectangle().fill(Color.inkAlpha(0.08)).frame(height: 0.5).padding(.leading, 62)
    }
}
