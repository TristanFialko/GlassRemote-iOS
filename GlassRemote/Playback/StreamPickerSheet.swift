import SwiftUI

/// Play flow (Phase 7). Asks the profile's enabled stream add-ons for this title (or episode),
/// groups the results by add-on with quality filters, and sends the chosen stream to the TV.
/// "Open in Nuvio" always comes first: Nuvio has no stream-URL deep link (see
/// RemoteModel+Handoff.swift), so the title-level handoff is how playback goes through Nuvio itself.
/// Every action ends in a visible result line; nothing fails silently.
struct StreamPickerSheet: View {
    let title: MediaTitle
    var episodes: [CinemetaCatalog.Episode] = []
    var initialSeason: Int = 1
    /// The episode the user tapped (or is resuming). Nil keeps the season's first episode.
    var initialEpisode: Int? = nil
    var onHandoff: ((HandoffResult) -> Void)? = nil

    @EnvironmentObject private var remote: RemoteModel
    @ObservedObject private var addons = AddonStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.glassTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var season = 1
    @State private var episode: Int?
    @State private var lookup = StreamLookup()
    @State private var loading = false
    @State private var quality: StreamQuality?
    @State private var sending: String?
    @State private var result: String?
    @State private var started = false

    private struct StreamGroup: Identifiable {
        let name: String
        let options: [StreamOption]
        var id: String { name }
    }

    private var isSeries: Bool { title.kind == .series }
    private var seasons: [Int] { Array(Set(episodes.map(\.season))).filter { $0 > 0 }.sorted() }
    private var seasonEpisodes: [CinemetaCatalog.Episode] {
        episodes.filter { $0.season == season }.sorted { $0.number < $1.number }
    }
    private var videoID: String? {
        guard isSeries else { return title.id }
        guard let episode else { return nil }
        return "\(title.id):\(season):\(episode)"
    }
    private var lookupKey: String { "\(videoID ?? "-")|\(addons.streamAddonCount)|\(addons.profileID?.uuidString ?? "")" }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    nuvioCard
                    if isSeries && !seasonEpisodes.isEmpty { episodePicker }
                    streams
                    if let result {
                        Label(result, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(Color.inkAlpha(0.75))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(18)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .foregroundStyle(Color.ink)
            .background { AmbientBackdrop() }
            .navigationTitle(title.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .themedSheet()
        .onAppear {
            guard !started else { return }
            started = true
            season = seasons.contains(initialSeason) ? initialSeason : (seasons.first ?? initialSeason)
            if isSeries { episode = EpisodeSelection.start(in: episodes, season: season, requested: initialEpisode) }
        }
        .task(id: lookupKey) { await runLookup() }
    }

    // MARK: Sections

    private var nuvioCard: some View {
        Button {
            send("nuvio") { await remote.openInNuvioResult(title) }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "arrow.up.forward.app.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Open in Nuvio").font(.body.weight(.semibold))
                    Text("Opens the title in Nuvio on the TV, where Nuvio's own sources play it.")
                        .font(.caption)
                        .foregroundStyle(Color.inkAlpha(0.6))
                }
                Spacer(minLength: 8)
                if sending == "nuvio" { ProgressView() } else { Image(systemName: "chevron.right").foregroundStyle(Color.inkAlpha(0.4)) }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: true)
        }
        .buttonStyle(GlassPressStyle())
        .disabled(sending != nil)
    }

    private var episodePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionHeader(title: "Episode")
            if seasons.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(seasons, id: \.self) { s in
                            chip("Season \(s)", selected: s == season) {
                                season = s
                                episode = episodes.filter { $0.season == s }.map(\.number).min()
                            }
                        }
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(seasonEpisodes, id: \.number) { ep in
                        chip("E\(ep.number)", selected: ep.number == episode) { episode = ep.number }
                            .accessibilityLabel("Episode \(ep.number), \(ep.title)")
                    }
                }
            }
            if let ep = seasonEpisodes.first(where: { $0.number == episode }), !ep.title.isEmpty {
                Text(ep.title).font(.footnote).foregroundStyle(Color.inkAlpha(0.6))
            }
        }
    }

    @ViewBuilder
    private var streams: some View {
        GlassSectionHeader(title: "Streams from your add-ons", subtitle: streamSubtitle)
        if addons.streamAddonCount == 0 && addons.linkMissingStreamAddonCount > 0 {
            emptyCard("Add-on links missing", "Your stream add-ons' links weren't restored on this device. Open Profile > Add-ons and use Replace link on each one. Open in Nuvio works meanwhile.")
        } else if addons.streamAddonCount == 0 {
            emptyCard("No stream add-ons yet", "Add a Stremio-compatible stream add-on in Profile > Add-ons and its streams appear here. Open in Nuvio works without one.")
        } else if isSeries && videoID == nil {
            emptyCard("Pick an episode", "Streams are found per episode.")
        } else if loading && lookup.options.isEmpty {
            HStack(spacing: 10) {
                ProgressView()
                Text("Asking your add-ons…").font(.footnote).foregroundStyle(Color.inkAlpha(0.6))
            }
            .padding(.vertical, 8)
        } else if lookup.options.isEmpty {
            emptyCard("No streams found", lookup.failures.isEmpty ? "Your add-ons have nothing for this title." : lookup.failures.joined(separator: "\n"))
        } else {
            if availableQualities.count > 1 { qualityChips }
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.name).font(.footnote.weight(.semibold)).foregroundStyle(Color.inkAlpha(0.6))
                    ForEach(group.options) { option in
                        StreamRow(option: option, sending: sending == option.id) {
                            send(option.id) { await remote.playOnTVResult(option.stream) }
                        }
                        .disabled(sending != nil && sending != option.id)
                    }
                }
            }
            if !lookup.failures.isEmpty {
                Text(lookup.failures.joined(separator: "\n")).font(.caption).foregroundStyle(Color.inkAlpha(0.5))
            }
        }
    }

    private var streamSubtitle: String? {
        guard addons.streamAddonCount > 0, !lookup.options.isEmpty else { return nil }
        let playable = lookup.options.filter { $0.stream.canSendToTV }.count
        return "\(lookup.options.count) found · \(playable) can be sent to the TV"
    }

    private var availableQualities: [StreamQuality] {
        Array(Set(lookup.options.map { $0.stream.quality })).filter { $0 != .unknown }.sorted(by: >)
    }

    private var qualityChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", selected: quality == nil) { quality = nil }
                ForEach(availableQualities, id: \.self) { q in
                    chip(q.badge ?? "Other", selected: quality == q) { quality = q }
                }
            }
        }
    }

    private var groups: [StreamGroup] {
        let filtered = lookup.options.filter { quality == nil || $0.stream.quality == quality }
        var order: [String] = []
        var map: [String: [StreamOption]] = [:]
        for option in filtered {
            if map[option.addonName] == nil { order.append(option.addonName) }
            map[option.addonName, default: []].append(option)
        }
        return order.map { StreamGroup(name: $0, options: map[$0] ?? []) }
    }

    private func emptyCard(_ heading: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(heading).font(.subheadline.weight(.semibold))
            Text(text).font(.footnote).foregroundStyle(Color.inkAlpha(0.6))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.soft()
            withAnimation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion)) { action() }
        } label: {
            Text(label)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(selected ? Color.white : Color.ink)
                .background { if selected { Capsule().fill(theme.accent) } }
                .glassSurface(Capsule(), interactive: true)
        }
        .buttonStyle(GlassPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Actions

    private func runLookup() async {
        guard let videoID else {
            lookup = StreamLookup()
            return
        }
        let sources = addons.streamSources(type: title.kind.rawValue, id: videoID)
        guard !sources.isEmpty else {
            lookup = StreamLookup()
            loading = false
            return
        }
        loading = true
        lookup = StreamLookup()
        quality = nil
        let found = await StreamResolver.lookup(type: title.kind.rawValue, id: videoID, sources: sources)
        guard !Task.isCancelled else { return }
        withAnimation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion)) {
            lookup = found
            loading = false
        }
    }

    private func send(_ id: String, _ action: @escaping () async -> HandoffResult) {
        guard sending == nil else { return }
        Haptics.soft()
        sending = id
        Task {
            let outcome = await action()
            withAnimation(Motion.resolve(Motion.snappy, reduceMotion: reduceMotion)) {
                result = outcome.message
                sending = nil
            }
            onHandoff?(outcome)
        }
    }
}

/// Which episode the picker starts on (pure, unit tested).
enum EpisodeSelection {
    /// The requested episode when this season lists it, otherwise the season's lowest episode.
    static func start(in episodes: [CinemetaCatalog.Episode], season: Int, requested: Int?) -> Int? {
        let numbers = episodes.filter { $0.season == season }.map(\.number)
        if let requested, numbers.contains(requested) { return requested }
        return numbers.min()
    }

    /// The watched episode, when the page's selected season is the one being watched.
    static func resume(season: Int, watching: (season: Int, episode: Int)?) -> Int? {
        guard let watching, watching.season == season else { return nil }
        return watching.episode
    }
}

struct StreamRow: View {
    let option: StreamOption
    let sending: Bool
    let action: () -> Void
    @Environment(\.glassTheme) private var theme

    var body: some View {
        let stream = option.stream
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if let badge = stream.quality.badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(theme.accent.opacity(0.22)))
                        }
                        Text(stream.headline).font(.subheadline.weight(.semibold)).lineLimit(1)
                    }
                    if !stream.details.isEmpty {
                        Text(stream.details).font(.caption).foregroundStyle(Color.inkAlpha(0.65)).lineLimit(3)
                    }
                    HStack(spacing: 10) {
                        if let size = stream.sizeText { Label(size, systemImage: "internaldrive") }
                        if let reason = stream.unavailableReason { Label(reason, systemImage: "exclamationmark.circle") }
                    }
                    .font(.caption2)
                    .foregroundStyle(Color.inkAlpha(0.5))
                }
                Spacer(minLength: 8)
                if sending {
                    ProgressView()
                } else {
                    Image(systemName: stream.canSendToTV ? "play.fill" : "nosign")
                        .foregroundStyle(stream.canSendToTV ? theme.accent : Color.inkAlpha(0.35))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Color.ink)
            .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
        }
        .buttonStyle(GlassPressStyle())
        .disabled(!stream.canSendToTV)
        .opacity(stream.canSendToTV ? 1 : 0.6)
        .accessibilityElement(children: .combine)
        .accessibilityHint(stream.canSendToTV ? "Sends this stream to the TV" : "")
    }
}
