import SwiftUI
import UIKit

// Phase 9 §A: every decision behind the Player page, kept pure so it can be unit tested
// (Phase9PlayerTests). Nothing here talks to ADB, the model or the network: the page reads these to
// lay itself out, choose its controls and draw its background.

// MARK: - Artwork

/// What the Player shows as artwork. Each kind keeps its own proportions, so nothing is stretched.
enum PlayerArtworkKind: Equatable {
    /// A 2:3 catalogue poster (Cinemeta, or remembered from Discover).
    case poster
    /// 16:9 key art remembered from Discover, used only when there is no poster.
    case landscape
    /// No title artwork: the app's own artwork (or a symbol) on a square card.
    case appIcon

    var aspect: CGFloat {
        switch self {
        case .poster: return 2.0 / 3.0
        case .landscape: return 16.0 / 9.0
        case .appIcon: return 1
        }
    }

    static func resolve(posterURL: URL?, landscapeURL: URL?) -> PlayerArtworkKind {
        if posterURL != nil { return .poster }
        if landscapeURL != nil { return .landscape }
        return .appIcon
    }
}

// MARK: - Layout

enum PlayerLayoutPolicy {
    /// Portrait side margin.
    static let portraitMargin: CGFloat = 24
    /// Portrait gap between the artwork and the controls below it.
    static let portraitGap: CGFloat = 18
    /// Gap between the rows of controls (title, time, transport, volume).
    static let controlSpacing: CGFloat = 14
    /// App artwork is a smaller square: a logo filling the page would read as a placeholder.
    static let iconShare: CGFloat = 0.62
    /// Landscape: app artwork inside the square artwork region.
    static let landscapeIconShare: CGFloat = 0.8
    static let landscapeSpacing: CGFloat = 32
    static let landscapeMargin: CGFloat = 24
    static let landscapeVerticalPadding: CGFloat = 14
    /// The control column needs room for the transport bar and the volume slider.
    static let landscapeMinColumn: CGFloat = 280
    static let landscapeMaxColumn: CGFloat = 460

    /// The largest frame with `aspect` that fits in `bounds`: a uniform scale only, never stretched.
    static func fit(aspect: CGFloat, in bounds: CGSize) -> CGSize {
        guard aspect > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let width = min(bounds.width, bounds.height * aspect)
        return CGSize(width: width, height: width / aspect)
    }

    /// Portrait: the artwork takes everything above the controls (`region` is what is left once the
    /// controls, the margins and the dock clearance are measured), so it is the dominant element.
    static func portraitArtwork(kind: PlayerArtworkKind, region: CGSize) -> CGSize {
        switch kind {
        case .appIcon:
            let side = min(region.width * iconShare, region.height)
            return fit(aspect: 1, in: CGSize(width: side, height: side))
        case .poster, .landscape:
            return fit(aspect: kind.aspect, in: region)
        }
    }

    struct Landscape: Equatable {
        /// Side of the square artwork region on the leading side.
        var artSide: CGFloat
        /// Width of the control column on the trailing side.
        var column: CGFloat
        var spacing: CGFloat
    }

    /// Landscape split: a square artwork region as tall as the page allows, beside a control column
    /// that always keeps room for the transport and the volume slider. `page` is the page's size
    /// after the rail; `bottomClearance` is the dock clearance.
    static func landscape(page: CGSize, bottomClearance: CGFloat) -> Landscape {
        let height = max(page.height - landscapeVerticalPadding * 2 - bottomClearance, 0)
        let width = max(page.width - landscapeMargin * 2 - landscapeSpacing, 0)
        let wanted = min(max(width - height, landscapeMinColumn), landscapeMaxColumn)
        let artSide = max(min(height, width - wanted), 0)
        let column = min(max(width - artSide, 0), landscapeMaxColumn)
        return Landscape(artSide: artSide, column: column, spacing: landscapeSpacing)
    }

    /// The artwork's frame inside the landscape square region.
    static func landscapeArtwork(kind: PlayerArtworkKind, side: CGFloat) -> CGSize {
        switch kind {
        case .appIcon:
            let icon = side * landscapeIconShare
            return fit(aspect: 1, in: CGSize(width: icon, height: icon))
        case .poster, .landscape:
            return fit(aspect: kind.aspect, in: CGSize(width: side, height: side))
        }
    }

    // MARK: v5 §3 (Now Playing, Apple Music style)

    /// Portrait side margin of the controls (the title artwork itself runs edge to edge).
    static let nowPlayingMargin: CGFloat = 28
    static let artworkCornerRadius: CGFloat = 14
    /// Thin, display-only timeline.
    static let timelineHeight: CGFloat = 6
    /// Transport row: plain glyphs, the play glyph largest; every glyph keeps a full touch target.
    static let transportHeight: CGFloat = 68
    static let playGlyph: CGFloat = 46
    /// The transport sits a little inside the timeline's ends, as in Apple Music.
    static let transportInset: CGFloat = 12
    static let secondaryGlyph: CGFloat = 32
    /// Title and artist line share one size, as in Apple Music; the second line is only lighter.
    static let titleSize: CGFloat = 20
    /// The grabber at the top of the sheet.
    static let grabberSize = CGSize(width: 38, height: 5)
    /// Portrait: room between the volume row and the dock.
    static let portraitBottomGap: CGFloat = 10

    // MARK: Gap fixes (Apple Music references)

    /// Portrait title artwork reaches this far below the artwork region, behind the title, where it
    /// has already faded out.
    static let bleedOverlap: CGFloat = 64
    /// The artwork is fully opaque down to this share of its height, then fades to nothing.
    static let bleedFadeStart: CGFloat = 0.62

    /// Portrait title artwork: the full page width (the side margins are given back), from the top
    /// of the screen (`topInset` is the status bar's safe area) to `bleedOverlap` below the region.
    static func portraitBleed(region: CGSize, margin: CGFloat, topInset: CGFloat) -> CGSize {
        guard region.width > 0, region.height > 0 else { return .zero }
        return CGSize(width: region.width + 2 * max(margin, 0),
                      height: region.height + max(topInset, 0) + bleedOverlap)
    }

    /// Portrait without title artwork: the card keeps clear of the grabber above it and of the
    /// title below it.
    static func portraitCardRegion(region: CGSize) -> CGSize {
        CGSize(width: max(region.width, 0), height: max(region.height - 2 * portraitCardInset, 0))
    }
    static let portraitCardInset: CGFloat = 28

    /// Landscape: the grabber sits above the artwork card.
    static let landscapeTopInset: CGFloat = 10
    /// Landscape: the least room between the rows of the control column.
    static let landscapeMinRowGap: CGFloat = 8
    /// Landscape: what the column's rows need at their natural sizes (title, timeline, transport,
    /// volume and the least gaps), so a short artwork card never squeezes them.
    static let landscapeMinColumnHeight: CGFloat = 236

    /// Landscape: the control column is as tall as the artwork card, so the title lines up with the
    /// card's top edge and the volume row with its bottom edge.
    static func landscapeColumnHeight(artSide: CGFloat) -> CGFloat {
        max(artSide, landscapeMinColumnHeight)
    }
    /// The artwork eases back to this scale while paused, as Apple Music does.
    static let pausedArtworkScale: CGFloat = 0.9

    /// Near-square proportions for the Now Playing card: a 2:3 poster is shown 4:5 and 16:9 key art
    /// 4:3, filled and centre-cropped (never stretched); app artwork is square.
    static func nowPlayingAspect(kind: PlayerArtworkKind) -> CGFloat {
        switch kind {
        case .poster: return 4.0 / 5.0
        case .landscape: return 4.0 / 3.0
        case .appIcon: return 1
        }
    }

    /// The Now Playing card: the largest near-square frame that fits `region` (portrait: the space
    /// above the controls; landscape: the square artwork region).
    static func nowPlayingArtwork(kind: PlayerArtworkKind, region: CGSize) -> CGSize {
        fit(aspect: nowPlayingAspect(kind: kind), in: region)
    }

    static func artworkScale(isPlaying: Bool, reduceMotion: Bool) -> CGFloat {
        (isPlaying || reduceMotion) ? 1 : pausedArtworkScale
    }
}

/// v5 §3: the line under the title (Apple Music's artist line): the episode subtitle and the app,
/// skipping anything empty or repeating the title.
enum PlayerTitlePolicy {
    static func secondaryLine(subtitle: String, appName: String, title: String) -> String {
        var parts: [String] = []
        for part in [subtitle, appName] {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  trimmed.caseInsensitiveCompare(title) != .orderedSame,
                  !parts.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { continue }
            parts.append(trimmed)
        }
        return parts.joined(separator: " · ")
    }
}

/// The small caption centred under the timeline (where Apple Music shows "Mixing" or the audio
/// format): the last seek the TV confirmed, else the session state when it is not simply playing.
enum PlayerCaptionPolicy {
    static func caption(phase: PlayerSessionPhase, seek: String?) -> String {
        if let seek, !seek.isEmpty { return seek }
        switch phase {
        case .playing: return ""
        case .paused, .buffering, .stale: return phase.label
        case .disconnected, .connecting, .idle: return ""
        }
    }

    /// "+10 s" / "−10 s": the jump the TV's session confirmed.
    static func seekText(seconds: Double) -> String {
        "\(seconds < 0 ? "−" : "+")\(Int(abs(seconds).rounded())) s"
    }
}

// MARK: - Capabilities

/// Whether a session plays audio tracks (where previous / next means a track) or video.
enum PlayerSessionKind: Equatable {
    case video
    case audio

    /// Explicit music apps only. Anything not listed is treated as video, and Nuvio always is: its
    /// previous / next would be episode navigation, which the Player never offers.
    static let audioPackages: Set<String> = [
        "com.spotify.tv.android",
        "com.spotify.music",
        "com.google.android.youtube.tvmusic",
        "com.apple.android.music",
        "deezer.android.tv",
        "com.aspiro.tidal",
    ]

    static func resolve(package: String) -> PlayerSessionKind {
        let normalised = package.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if PlayerArtworkStore.usesCatalogue(package: normalised) { return .video }   // Nuvio
        return audioPackages.contains(normalised) ? .audio : .video
    }
}

/// The Player's controls for a session: only what the session really supports. Controls that would do
/// nothing are not shown at all.
struct PlayerControls: Equatable {
    /// The primary control. Enabled only when the session advertises play / pause.
    var playPause = false
    /// Relative seek through the app's own step (the confirmed path, see SEEKING_REPORT.md).
    var rewind = false
    var fastForward = false
    /// Track skip: explicit audio-track sessions only, never video and never Nuvio.
    var previousTrack = false
    var nextTrack = false
    /// A progress bar needs a real total length; the box does not report one today.
    var progress = false

    static let none = PlayerControls()

    static func resolve(media: MediaState) -> PlayerControls {
        guard media.isActive else { return PlayerControls.none }
        let audio = PlayerSessionKind.resolve(package: media.package) == .audio
        return PlayerControls(playPause: media.canPlayPause,
                              rewind: media.canRewind,
                              fastForward: media.canFastForward,
                              previousTrack: audio && media.canPrevious,
                              nextTrack: audio && media.canNext,
                              progress: hasReliableDuration(media.durationMs))
    }

    static func hasReliableDuration(_ durationMs: Int64?) -> Bool { (durationMs ?? 0) > 0 }

    /// True when anything besides play / pause is shown (the transport then gets its glass bar).
    var hasSecondary: Bool { rewind || fastForward || previousTrack || nextTrack }

    /// Explicit Play or Pause, never a toggle: buffering counts as playing, so it pauses.
    static func playPauseCommand(for media: MediaState) -> MediaCommand { media.isPlaying ? .pause : .play }
}

// MARK: - Session state

enum PlayerSessionPhase: Equatable {
    case disconnected
    case connecting
    case idle
    case playing
    case paused
    case buffering
    /// The last sample is too old to trust (polling paused, app was in the background, link trouble).
    case stale

    /// The poll runs every 8 to 10 s; three missed polls means the sample can no longer be trusted.
    static let staleAfter: TimeInterval = 30

    static func resolve(media: MediaState, connected: Bool, connecting: Bool, now: Date) -> PlayerSessionPhase {
        guard connected else { return connecting ? .connecting : .disconnected }
        guard media.isActive else { return .idle }
        if now.timeIntervalSince(media.sampledAt) > staleAfter { return .stale }
        switch media.state {
        case 3: return .playing
        case 6: return .buffering
        default: return .paused
        }
    }

    /// A session is on screen (title, time, transport) rather than a hint.
    var showsSession: Bool {
        switch self {
        case .playing, .paused, .buffering, .stale: return true
        case .disconnected, .connecting, .idle: return false
        }
    }

    var label: String {
        switch self {
        case .disconnected: return "Not connected"
        case .connecting: return "Connecting"
        case .idle: return "Nothing playing"
        case .playing: return "Playing"
        case .paused: return "Paused"
        case .buffering: return "Buffering"
        case .stale: return "Waiting for the TV"
        }
    }

    var hint: String {
        switch self {
        case .disconnected: return "Connect to your TV box to see what's playing."
        case .connecting: return "Connecting to your TV box…"
        default: return "Start something in Nuvio and it appears here."
        }
    }
}

/// Position updates, throttled: the elapsed time redraws once a second only while it really moves.
/// Otherwise the page re-checks slowly, just enough to notice a session going stale.
enum PlayerTimeline {
    static let playingInterval: TimeInterval = 1
    static let idleInterval: TimeInterval = 5

    static func refreshInterval(isPlaying: Bool) -> TimeInterval { isPlaying ? playingInterval : idleInterval }

    /// The position to show. A stale sample is frozen where the TV last reported it instead of being
    /// extrapolated into a guess.
    static func position(media: MediaState, phase: PlayerSessionPhase, at date: Date) -> TimeInterval {
        phase == .stale ? media.position(at: media.sampledAt) : media.position(at: date)
    }

    /// v5 §3: the clock stops entirely while Now Playing is hidden or the app is not active.
    static func isPaused(sceneActive: Bool, presented: Bool) -> Bool { !(sceneActive && presented) }

    /// Timeline fill, clamped to 0...1; 0 without a usable duration.
    static func fraction(position: TimeInterval, total: TimeInterval) -> CGFloat {
        guard total > 0, total.isFinite, position.isFinite else { return 0 }
        return CGFloat(min(max(position / total, 0), 1))
    }
}

/// Artwork and metadata change together: one key for both, so a new title never shows the old poster.
enum PlayerTransition {
    static func key(media: MediaState) -> String {
        guard media.isActive else { return "" }
        let title = media.headline.isEmpty ? media.title : media.headline
        return media.package + "|" + title + "|" + media.subtitle
    }
}

// MARK: - Background

/// Phase 9 §A2, refined: the full-screen background is a wash of the artwork's prominent colours
/// (NowPlayingPalette.swift), not a copy of the picture. Legibility is built into the colours
/// themselves: every tone is clamped into a luminance band where the page's ink keeps at least
/// 4.5:1, so no scrim is needed over bright, dark or highly saturated artwork.
enum PlayerBackdropPolicy {
    /// Dark themes: white ink keeps about 5:1 over the wash's fields...
    static let darkMaxLuminance = 0.16
    /// ...and at least 4.5:1 over its brightest glow.
    static let darkGlowLuminance = 0.18
    /// Under the controls the base is deepened to at most this.
    static let darkFootLuminance = 0.05
    /// Black artwork still gives a coloured, not an empty, background.
    static let darkMinLuminance = 0.012
    static let darkMaxSaturation = 0.9
    /// Light themes: pale enough for dark ink (about 7.8:1 at the floor), never glaring white.
    static let lightMinLuminance = 0.42
    static let lightFootLuminance = 0.62
    static let lightMaxLuminance = 0.86
    static let lightMaxSaturation = 0.42
    /// `Color.ink`: white on dark themes, 8 % grey on light ones.
    static let darkInkLuminance = 1.0
    static let lightInkLuminance = ColorMath.luminance(r: 0.08, g: 0.08, b: 0.08)
    static let minimumContrast = 4.5

    /// sRGB transfer (encoded 0...1 to linear luminance) and its inverse.
    static func linear(_ c: Double) -> Double {
        let v = min(max(c, 0), 1)
        return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    static func encoded(_ l: Double) -> Double {
        let v = min(max(l, 0), 1)
        return v <= 0.03928 / 12.92 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
    }

    /// 3 x 3 mesh control points. The outer points stay on the canvas edges so the wash always covers
    /// it; the inner ones lean by `lean` (0...1, from the accent's hue) so each artwork's wash has its
    /// own shape.
    static func meshPoints(lean: Double) -> [SIMD2<Float>] {
        let l = Float(lean.isFinite ? min(max(lean, 0), 1) : 0.5)
        return [
            SIMD2<Float>(0, 0), SIMD2<Float>(0.5, 0), SIMD2<Float>(1, 0),
            SIMD2<Float>(0, 0.38 + 0.12 * l), SIMD2<Float>(0.36 + 0.28 * l, 0.44), SIMD2<Float>(1, 0.5 - 0.12 * l),
            SIMD2<Float>(0, 1), SIMD2<Float>(0.5, 1), SIMD2<Float>(1, 1),
        ]
    }

    /// The mesh's nine colours, row by row: the accent glows at the top, the base fills the middle and
    /// the foot sits under the controls. Mixed colours are clamped again on light themes (a mix of two
    /// pale colours can be darker than either); on dark themes a mix is never brighter than its parts.
    static func meshColors(_ p: NowPlayingPalette, light: Bool) -> [NowPlayingPalette.Tone] {
        let tones = [
            p.accent, p.base.mixed(with: p.accent, 0.45), p.support,
            p.base, p.base.mixed(with: p.support, 0.35), p.base.mixed(with: p.accent, 0.2),
            p.foot, p.base.mixed(with: p.foot, 0.6), p.foot,
        ]
        guard light else { return tones }
        return tones.map { NowPlayingPalette.adjust($0, light: true, role: .field) }
    }

    /// Contrast of the page's ink over a wash colour.
    static func inkContrast(over tone: NowPlayingPalette.Tone, light: Bool) -> Double {
        ColorMath.contrast(light ? lightInkLuminance : darkInkLuminance, tone.luminance)
    }
}
