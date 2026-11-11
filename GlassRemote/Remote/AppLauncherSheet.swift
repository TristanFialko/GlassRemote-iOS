import SwiftUI

/// Phase 8: pure rules for the Apps launcher (unit tested in Phase8RemoteTests).
///
/// Package discovery stays informational (see `RemoteModel.refreshApps`): it never hides, dims or
/// disables a tile. The launcher only reports the scan's state in a banner.
enum AppLauncherPolicy {
    enum Banner: Equatable {
        /// Connected and the package scan finished.
        case none
        /// The box is not connected: tiles are shown, launching reports the failure, Reconnect offered.
        case offline
        /// Connected, the package scan has not reported yet.
        case scanning
        /// Connected, but the package scan failed.
        case scanFailed
    }

    static func banner(connected: Bool, installedCount: Int, status: String) -> Banner {
        guard connected else { return .offline }
        if status.localizedCaseInsensitiveContains("app scan failed") { return .scanFailed }
        return installedCount == 0 ? .scanning : .none
    }

    /// Favourites first (in the order they were starred), then the rest in catalogue order.
    static func ordered(_ apps: [TVApp], favourites: [String]) -> [TVApp] {
        let favs = favourites.compactMap { pkg in apps.first { $0.package == pkg } }
        let favSet = Set(favourites)
        return favs + apps.filter { !favSet.contains($0.package) }
    }

    /// Case- and diacritic-insensitive name filter; a blank query keeps everything.
    static func filtered(_ apps: [TVApp], query: String) -> [TVApp] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return apps }
        return apps.filter { $0.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// Grid columns for the sheet's width: 3 on a narrow phone, up to 6 in landscape.
    static func columns(for width: CGFloat) -> Int {
        let tile: CGFloat = 96
        return min(max(Int((width - 32) / tile), 3), 6)
    }
}

/// The designed Apps launcher that replaces the Remote's inline dropdown: a sheet with a searchable
/// grid of app icons and names, favourites first, plus honest offline / scanning / scan-failed
/// states. Launching dismisses it.
struct AppLauncherSheet: View {
    @EnvironmentObject private var remote: RemoteModel
    @ObservedObject private var favourites = AppFavourites.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.glassTheme) private var theme
    @State private var query = ""

    private var banner: AppLauncherPolicy.Banner {
        AppLauncherPolicy.banner(connected: remote.connected, installedCount: remote.installed.count,
                                 status: remote.status)
    }

    private var apps: [TVApp] {
        AppLauncherPolicy.filtered(AppLauncherPolicy.ordered(remote.apps, favourites: favourites.packages),
                                   query: query)
    }

    var body: some View {
        GeometryReader { geo in
            let count = AppLauncherPolicy.columns(for: geo.size.width)
            let grid = Array(repeating: GridItem(.flexible(), spacing: 14), count: count)
            VStack(spacing: 14) {
                header
                searchField
                bannerView
                if apps.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: grid, spacing: 18) {
                            ForEach(apps) { app in tile(app) }
                        }
                        .padding(.horizontal, 2)
                        .padding(.bottom, 24)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .background { AmbientBackdrop().ignoresSafeArea() }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .themedSheet()
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Apps").scaledFont(26, .bold)
                Text(remote.connected ? "Tap to open on the TV box" : "TV box offline")
                    .scaledFont(13)
                    .foregroundStyle(Color.inkAlpha(0.6))
            }
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .scaledFont(15, .semibold)
                    .frame(width: 40, height: 40)
                    .glassSurface(Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .foregroundStyle(Color.ink)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.inkAlpha(0.55))
            TextField("Search apps", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.inkAlpha(0.45))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .scaledFont(15)
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 14)
        .frame(height: 42)
        .glassSurface(Capsule())
    }

    @ViewBuilder
    private var bannerView: some View {
        switch banner {
        case .none:
            EmptyView()
        case .scanning:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Checking installed apps…").scaledFont(13)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.inkAlpha(0.72))
            .padding(.horizontal, 14)
            .frame(height: 40)
            .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous))
        case .scanFailed:
            noticeRow(symbol: "exclamationmark.triangle", text: "Couldn't list installed apps. Every app can still be opened.",
                      action: nil)
        case .offline:
            noticeRow(symbol: "wifi.exclamationmark", text: "The TV box isn't connected.",
                      action: ("Reconnect", { remote.connect() }))
        }
    }

    private func noticeRow(symbol: String, text: String, action: (String, () -> Void)?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.orange)
            Text(text).scaledFont(13).foregroundStyle(Color.inkAlpha(0.8)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let action {
                Button(action.0) { Haptics.soft(); action.1() }
                    .scaledFont(13, .semibold)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .glassSurface(Capsule(), interactive: true, accent: true)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2").scaledFont(34, .light)
            Text(query.isEmpty ? "No apps" : "No apps match “\(query)”").scaledFont(15, .semibold)
            if !query.isEmpty {
                Button("Clear search") { query = "" }.scaledFont(13)
            }
        }
        .foregroundStyle(Color.inkAlpha(0.7))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tile(_ app: TVApp) -> some View {
        let isFavourite = favourites.contains(app.package)
        return Button {
            remote.launch(app)
            dismiss()
        } label: {
            VStack(spacing: 7) {
                AppIconImage(asset: "\(app.asset)_dark")
                    .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .strokeBorder(
                                LinearGradient(colors: [Color.ink.opacity(0.42), Color.ink.opacity(0.08)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 1)
                    }
                    .background {
                        RoundedRectangle(cornerRadius: 19, style: .continuous).fill(Color.ink.opacity(0.07))
                    }
                    .shadow(color: .black.opacity(0.32), radius: 10, y: 6)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(alignment: .topTrailing) {
                        if isFavourite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.yellow)
                                .padding(4)
                                .background(Circle().fill(.black.opacity(0.45)))
                                .offset(x: 4, y: -4)
                        }
                    }
                Text(app.name)
                    .scaledFont(12, .medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(Color.inkAlpha(0.86))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(app.name + (isFavourite ? ", favourite" : ""))
        .contextMenu {
            Button { favourites.toggle(app.package) } label: {
                Label(isFavourite ? "Remove favourite" : "Favourite", systemImage: isFavourite ? "star.slash" : "star")
            }
            Button(role: .destructive) {
                remote.restartApp(app)
                dismiss()
            } label: {
                Label("Restart \(app.name)", systemImage: "arrow.clockwise")
            }
        }
    }
}
