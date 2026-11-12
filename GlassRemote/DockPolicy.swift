import SwiftUI
import UIKit

/// v5 §2: how the app moves between dock pages. There is no swipe paging and no sliding strip: the
/// outgoing page fades out and the incoming page fades in, briefly. Every page stays mounted (only
/// opacity, hit testing and accessibility change), so a switch never rebuilds a page, never touches
/// ADB, the helpers or polling, and never sends TV input.
enum TabSwitchPolicy {
    /// Short enough to feel instant, long enough not to flash.
    static let fadeDuration: Double = Motion.Durations.tabFade
    static let animation = Motion.tabFade

    /// An opacity fade is already the reduced-motion form of a page change, so Reduce Motion keeps it
    /// (nothing moves either way).
    static func switchAnimation(reduceMotion: Bool) -> Animation { animation }
    static var adaptiveAnimation: Animation { animation }

    /// Pages never move when switching.
    static let pageOffset: CGSize = .zero

    /// Whether `item` is the page on screen (and the only one that takes touches and accessibility).
    static func isVisible(_ item: AppPage, current: AppPage, playerPresented: Bool) -> Bool {
        item == current && !playerPresented
    }

    static func opacity(of item: AppPage, current: AppPage, playerPresented: Bool) -> Double {
        isVisible(item, current: current, playerPresented: playerPresented) ? 1 : 0
    }
}

/// v5 §2: the full Now Playing presentation over the current page. A restrained fade with a slight
/// rise from the dock; with Reduce Motion it is a fade only.
enum NowPlayingPresentation {
    static let duration: Double = Motion.Durations.presentation
    static let animation = Motion.presentation
    /// How far the player rises while it fades in (points). Zero with Reduce Motion.
    static let rise: CGFloat = 18

    static func presentationAnimation(reduceMotion: Bool) -> Animation {
        (reduceMotion || MotionPreference.reduced) ? TabSwitchPolicy.animation : animation
    }

    @MainActor static var adaptiveAnimation: Animation { presentationAnimation(reduceMotion: UIAccessibility.isReduceMotionEnabled) }

    static func offset(presented: Bool, reduceMotion: Bool) -> CGFloat {
        (presented || reduceMotion || MotionPreference.reduced) ? 0 : rise
    }
}

/// v5 §2: when the compact Now Playing bar appears above the dock. Only for a session that is
/// genuinely active: playing, paused or buffering. Idle, stale (the box stopped reporting it),
/// connecting and disconnected sessions hide it. It also hides while the full player is open.
enum MiniPlayerPolicy {
    /// v6 §1: how long after a session's stale point the visibility is re-evaluated. Nothing sleeps
    /// or polls: the probe's timeline schedules exactly one re-check for that moment
    /// (`recheckSchedule`), and every new sample or connection change re-evaluates immediately. So a
    /// session that stops reporting disappears within this margin of going stale
    /// (`PlayerSessionPhase.staleAfter`).
    static let recheckNanos: UInt64 = 500_000_000

    static var recheckMargin: TimeInterval { TimeInterval(recheckNanos) / 1_000_000_000 }

    /// The only moment the visibility can change without new input: just after the current sample
    /// goes stale. Nil when there is no active session to expire.
    static func staleRecheckDate(media: MediaState) -> Date? {
        guard media.isActive else { return nil }
        return media.sampledAt.addingTimeInterval(PlayerSessionPhase.staleAfter + recheckMargin)
    }

    /// The probe's timeline: the stale re-check while it is still ahead, else nothing (the next
    /// sample, a connection change or a new session drives the next evaluation).
    static func recheckSchedule(media: MediaState, now: Date) -> [Date] {
        guard let date = staleRecheckDate(media: media), date > now else { return [] }
        return [date]
    }

    static func isVisible(phase: PlayerSessionPhase) -> Bool {
        switch phase {
        case .playing, .paused, .buffering: return true
        case .disconnected, .connecting, .idle, .stale: return false
        }
    }

    static func isVisible(media: MediaState, connected: Bool, connecting: Bool, now: Date) -> Bool {
        isVisible(phase: PlayerSessionPhase.resolve(media: media, connected: connected, connecting: connecting, now: now))
    }

    /// Shown over the pages only while the full player is closed.
    static func isShown(sessionVisible: Bool, playerPresented: Bool) -> Bool {
        sessionVisible && !playerPresented
    }
}

/// v5 §2 / §9, Phase 9 recovery §2: the dock's selected state. The selected icon takes the theme
/// accent, the others stay muted ink; the glass bubble above it stays clear (it is never filled with
/// the accent) and its bounded refraction bends only what it covers. When an accent would be too faint
/// on the dock (WCAG 1.4.11, 3:1 for UI components) the selected icon falls back to full-strength dock
/// ink, so the state is readable in every theme and in light and dark.
enum DockStyle {
    static let minimumContrast: Double = 3.0

    /// Approximate luminance of the dock surface: its scrim over typical content.
    static func backdropLuminance(light: Bool) -> Double { light ? 0.80 : 0.03 }

    static func usesAccent(accentLuminance: Double, light: Bool) -> Bool {
        ColorMath.contrast(accentLuminance, backdropLuminance(light: light)) >= minimumContrast
    }

    static func selectedInk(_ theme: GlassTheme) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(theme.accent).getRed(&r, green: &g, blue: &b, alpha: &a) else { return theme.dockInk }
        let luminance = ColorMath.luminance(r: Double(r), g: Double(g), b: Double(b))
        return usesAccent(accentLuminance: luminance, light: theme.isLight) ? theme.accent : theme.dockInk
    }

    /// Ink for one dock icon.
    static func iconInk(selected: Bool, theme: GlassTheme) -> Color {
        selected ? selectedInk(theme) : theme.dockInkInactive
    }

    /// The icon under the bubble (resting, or following the finger) is the selected one, except while
    /// the full player covers the pages: then no page is marked selected.
    static func showsSelection(highlighted: Bool, playerPresented: Bool) -> Bool {
        highlighted && !playerPresented
    }

    /// Pressed buttons that share the dock's look (the mini-player) dim slightly instead of scaling.
    static let pressedOpacity: Double = 0.55
}

/// v5 §2: what the mini-player shows for a session (pure, unit tested). The title is the session's
/// headline or title, else the app's name; the detail is the subtitle, else the app's name, and is
/// dropped when it would only repeat the title.
struct MiniPlayerSummary: Equatable {
    let sessionTitle: String
    let title: String
    let detail: String

    var accessibilityLabel: String { detail.isEmpty ? "Now playing: \(title)" : "Now playing: \(title), \(detail)" }

    static func resolve(media: MediaState, appName: String?) -> MiniPlayerSummary {
        let session = (media.headline.isEmpty ? media.title : media.headline).trimmingCharacters(in: .whitespacesAndNewlines)
        let app = (appName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = session.isEmpty ? (app.isEmpty ? "Now Playing" : app) : session
        let subtitle = media.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        var detail = subtitle.isEmpty ? app : subtitle
        if detail == title { detail = "" }
        return MiniPlayerSummary(sessionTitle: session, title: title, detail: detail)
    }
}
