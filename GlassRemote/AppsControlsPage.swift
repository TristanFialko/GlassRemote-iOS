import SwiftUI

/// Apps and device controls use a two-column console in landscape so grids and diagnostics do not
/// become a long, stretched portrait list.
struct AppsControlsPage: View {
    @EnvironmentObject private var remote: RemoteModel
    @ObservedObject private var quick = QuickActionStore.shared
    @ObservedObject private var favourites = AppFavourites.shared
    @State private var showQuickEditor = false
    @State private var pendingPower: PowerAction?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    private var favouriteApps: [TVApp] {
        favourites.packages.compactMap { pkg in remote.apps.first { $0.package == pkg } }
    }

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width > proxy.size.height {
                landscape(proxy)
            } else {
                portrait
            }
        }
        .foregroundStyle(.white)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .background { AmbientBackdrop() }
        .sheet(isPresented: $showQuickEditor) { QuickActionEditor(store: quick) }
        .confirmationDialog(
            pendingPower?.title ?? "",
            isPresented: Binding(get: { pendingPower != nil }, set: { if !$0 { pendingPower = nil } }),
            titleVisibility: .visible, presenting: pendingPower
        ) { action in
            Button(action.confirmLabel, role: .destructive) { remote.turnEverythingOff() }
        } message: { action in Text(action.message) }
    }

    private var portrait: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !favouriteApps.isEmpty { section("Favourites") { grid(favouriteApps) } }
                section("Apps") { grid(remote.apps); helperText }
                section("Quick Actions", trailing: { editButton }) { quickActions }
                section("Samsung TV") { samsung }
                section("Device") { device }
            }
            .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 24)
        }
    }

    private func landscape(_ proxy: GeometryProxy) -> some View {
        HStack(alignment: .top, spacing: 18) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !favouriteApps.isEmpty { section("Favourites") { grid(favouriteApps) } }
                    section("Apps") { grid(remote.apps); helperText }
                }
                .padding(.leading, 18).padding(.vertical, 10)
            }
            .frame(width: proxy.size.width * 0.56)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Quick Actions", trailing: { editButton }) { quickActions }
                    section("Samsung TV") { samsung }
                    section("Device") { device }
                }
                .padding(.trailing, 18).padding(.vertical, 10)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var editButton: some View { Button("Edit") { showQuickEditor = true }.scaledFont(14, .semibold) }
    private var helperText: some View { Text("Touch and hold an app for favourite and restart options.").scaledFont(12).foregroundStyle(.white.opacity(0.5)) }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        section(title, trailing: { EmptyView() }, content: content)
    }

    private func section<Content: View, Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing,
                                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(title).scaledFont(18, .bold); Spacer(); trailing() }
            content()
        }
    }

    private func grid(_ apps: [TVApp]) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(apps) { app in
                Button { remote.launch(app) } label: {
                    Image("\(app.asset)_dark").resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                        .shadow(color: .black.opacity(0.34), radius: 6, y: 3)
                        .overlay(alignment: .topTrailing) {
                            if favourites.contains(app.package) { Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.yellow).padding(5) }
                        }
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(app.name)
                .contextMenu {
                    Button { favourites.toggle(app.package) } label: {
                        Label(favourites.contains(app.package) ? "Remove favourite" : "Favourite", systemImage: favourites.contains(app.package) ? "star.slash" : "star")
                    }
                    Button(role: .destructive) { remote.restartApp(app) } label: { Label("Restart \(app.name)", systemImage: "arrow.clockwise") }
                }
            }
        }
    }

    private var quickActions: some View {
        VStack(spacing: 8) {
            if quick.actions.isEmpty { Text("No Quick Actions yet.").scaledFont(14).foregroundStyle(.white.opacity(0.6)) }
            ForEach(quick.actions) { action in
                Button { remote.runQuickAction(action) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.name).scaledFont(15, .semibold)
                            Text(action.summary { pkg in remote.apps.first { $0.package == pkg }?.name ?? pkg }).scaledFont(12).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                        }
                        Spacer()
                        if remote.runningQuickActionID == action.id { ProgressView().tint(.white) } else { Image(systemName: "play.fill").scaledFont(13) }
                    }
                    .padding(.horizontal, 16).frame(minHeight: 54)
                    .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
                }
                .buttonStyle(PressStyle()).disabled(!remote.connected)
            }
        }
    }

    private var samsung: some View {
        VStack(spacing: 8) {
            if remote.tvVolumeEnabled {
                HStack(spacing: 8) {
                    pill("TV power", "tv") { remote.tvKey("TV_POWER") }
                    pill("Input menu", "rectangle.on.rectangle") { remote.tvKey("TV_SOURCE") }
                }
                pill("Turn off box and TV", "power.circle") { pendingPower = .everythingOff }
            }
            Toggle("Route volume through Samsung TV", isOn: $remote.tvVolumeEnabled)
                .scaledFont(14).padding(.horizontal, 16).frame(minHeight: 48)
                .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous))
            Text(remote.samsungStatus).scaledFont(12).foregroundStyle(.white.opacity(0.55)).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pill(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).scaledFont(14, .semibold).lineLimit(1)
                .frame(maxWidth: .infinity).frame(height: 46)
                .glassSurface(Capsule(), interactive: true)
        }
        .buttonStyle(PressStyle())
    }

    private var device: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Android TV box", "\(remote.host):\(remote.port)")
            row("Link", remote.connected ? "Connected" : "Not connected")
            row("Samsung TV", remote.tvVolumeEnabled ? remote.samsungHost : "Off")
            row("Keyboard helper", remote.keyboardStatus)
            row("Pointer helper", remote.cursorStatus)
            HStack(spacing: 8) {
                pill("Find devices", "wifi") { remote.showConnection = true }
                pill("Connection", "slider.horizontal.3") { remote.showConnection = true }
            }
            .padding(.top, 4)
        }
        .padding(16).glassSurface(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).scaledFont(13).foregroundStyle(.white.opacity(0.6))
            Spacer(minLength: 12)
            Text(value).scaledFont(13, .medium).multilineTextAlignment(.trailing).lineLimit(2)
        }
    }
}
