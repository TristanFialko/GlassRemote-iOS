import SwiftUI

/// Page 4: Google Play. Search from the phone, then Google Play opens on the TV with the results
/// or the app's listing, so installation is finished with the TV remote. See `GooglePlay` for what
/// is and is not possible (no public search API, no remote install).
struct GooglePlayPage: View {
    @EnvironmentObject private var remote: RemoteModel
    @FocusState private var searching: Bool
    @State private var query = ""
    @State private var busyID: String?
    @State private var message: Message?
    @State private var recents: [String] = UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []

    private static let recentsKey = "glassRemote.playSearches.v1"
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    private struct Message: Equatable { let symbol: String; let text: String; let isError: Bool }

    private var typed: String? { GooglePlay.normalisedQuery(query) }
    private var matches: [GooglePlay.Suggestion] { GooglePlay.matches(query) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                titleRow
                searchField
                if !remote.connected { connectionNote }
                if let message { messageCard(message) }
                if let typed { searchOnTVButton(typed) }
                if query.isEmpty && !recents.isEmpty { recentsList }
                suggestionsSection
                limitsFootnote
            }
            .padding(.horizontal, 16).padding(.top, 10)
            .padding(.bottom, DockMetrics.clearance + 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(.white)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    // MARK: Header and search

    private var titleRow: some View {
        HStack(spacing: 12) {
            PlayMark().frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("Google Play").scaledFont(24, .bold)
                Text("Find an app, finish installing on the TV").scaledFont(12).foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").scaledFont(16, .medium).foregroundStyle(.white.opacity(0.65))
            TextField("Search Google Play", text: $query)
                .focused($searching)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { if let typed { searchOnTV(typed) } }
            if !query.isEmpty {
                Button { query = ""; searching = true } label: {
                    Image(systemName: "xmark.circle.fill").scaledFont(17).foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .scaledFont(16)
        .padding(.horizontal, 16).frame(height: 52)
        .glassBar(Capsule())
    }

    private func searchOnTVButton(_ text: String) -> some View {
        Button { searchOnTV(text) } label: {
            HStack(spacing: 10) {
                if busyID == "search" { ProgressView().tint(.white) } else { Image(systemName: "tv").scaledFont(16, .medium) }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Search on the TV").scaledFont(15, .semibold)
                    Text("“\(text)” in Google Play").scaledFont(12).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").scaledFont(14, .semibold).foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 18).frame(height: 62)
            .glassSurface(RoundedRectangle(cornerRadius: 26, style: .continuous), interactive: true, elevated: true)
        }
        .buttonStyle(PressStyle())
        .disabled(!remote.connected || busyID != nil)
        .opacity(remote.connected ? 1 : 0.5)
        .accessibilityLabel("Search Google Play on the TV for \(text)")
    }

    // MARK: Sections

    private var recentsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent").scaledFont(16, .bold)
                Spacer()
                Button("Clear") {
                    recents = []
                    UserDefaults.standard.removeObject(forKey: Self.recentsKey)
                }.scaledFont(13, .semibold).foregroundStyle(.white.opacity(0.7))
            }
            GlassGroup(spacing: 8) {
                VStack(spacing: 8) {
                    ForEach(recents, id: \.self) { text in
                        Button { query = text } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.white.opacity(0.55))
                                Text(text).scaledFont(15).lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 16).frame(height: 44)
                            .glassSurface(Capsule(), interactive: true)
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(query.isEmpty ? "Popular on Android TV" : "Suggestions").scaledFont(18, .bold)
                Text("curated").scaledFont(12).foregroundStyle(.white.opacity(0.45))
            }
            if matches.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").scaledFont(26, .light).foregroundStyle(.white.opacity(0.4))
                    Text("No suggestion matches “\(query)”").scaledFont(14, .semibold)
                    Text("Use “Search on the TV” to look it up in Google Play.")
                        .scaledFont(12).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 22)
            } else {
                GlassGroup(spacing: 10) {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(matches) { app in suggestionTile(app) }
                    }
                }
            }
        }
    }

    private func suggestionTile(_ app: GooglePlay.Suggestion) -> some View {
        Button { openListing(app) } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.08))
                    if busyID == app.package { ProgressView().tint(.white) }
                    else { Image(systemName: app.symbol).scaledFont(16, .medium) }
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name).scaledFont(14, .semibold).lineLimit(1)
                    Text(app.blurb).scaledFont(11).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).frame(height: 56)
            .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true)
        }
        .buttonStyle(PressStyle())
        .disabled(!remote.connected || busyID != nil)
        .opacity(remote.connected ? 1 : 0.5)
        .accessibilityLabel("Open \(app.name) in Google Play on the TV")
    }

    private var connectionNote: some View {
        messageRow(Message(symbol: "wifi.exclamationmark",
                           text: "Not connected to the Android TV box. Connect it from the menu to open Google Play on the TV.",
                           isError: true))
    }

    private func messageCard(_ message: Message) -> some View { messageRow(message) }

    private func messageRow(_ message: Message) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: message.symbol).scaledFont(15, .medium)
                .foregroundStyle(message.isError ? Color.orange : Color.green)
            Text(message.text).scaledFont(13).foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var limitsFootnote: some View {
        Text("Google Play has no public search or remote-install service, so results appear on the TV and you press Install there. Suggestions are a fixed list, not live search results.")
            .scaledFont(11).foregroundStyle(.white.opacity(0.42))
            .padding(.top, 2)
    }

    // MARK: Actions

    private func searchOnTV(_ text: String) {
        guard busyID == nil else { return }
        searching = false
        busyID = "search"
        Task { @MainActor in
            let outcome = await remote.openPlaySearch(text)
            busyID = nil
            report(outcome, success: "Google Play search sent to the TV for “\(text)”.")
            if outcome == .accepted {
                recents = RecentSearches.adding(recents, text)
                UserDefaults.standard.set(recents, forKey: Self.recentsKey)
            }
        }
    }

    private func openListing(_ app: GooglePlay.Suggestion) {
        guard busyID == nil else { return }
        searching = false
        busyID = app.package
        Task { @MainActor in
            let outcome = await remote.openPlayListing(package: app.package)
            busyID = nil
            report(outcome, success: "Asked the TV to open \(app.name) in Google Play. Press Install there if it isn't installed.")
        }
    }

    private func report(_ outcome: GooglePlay.Outcome?, success: String) {
        switch outcome {
        case .accepted:
            Haptics.light()
            message = Message(symbol: "checkmark.circle", text: success, isError: false)
        case .storeUnavailable:
            message = Message(symbol: "exclamationmark.triangle",
                              text: "This box didn't find the Google Play Store app, or it can't open that link.", isError: true)
        case .rejected(let reason):
            message = Message(symbol: "exclamationmark.triangle", text: "The TV didn't accept the request: \(reason)", isError: true)
        case nil:
            message = Message(symbol: "exclamationmark.triangle", text: "That can't be searched. Use at least two characters.", isError: true)
        }
    }
}

/// Simple four-colour play mark: a rounded triangle in Google Play's colours (drawn, no bitmap).
private struct PlayMark: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.08))
            Triangle()
                .fill(LinearGradient(colors: [Color(red: 0.0, green: 0.82, blue: 0.84), Color(red: 0.2, green: 0.85, blue: 0.4),
                                              Color(red: 1.0, green: 0.8, blue: 0.1), Color(red: 0.95, green: 0.3, blue: 0.3)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(9)
        }
        .accessibilityHidden(true)
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.1, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}
