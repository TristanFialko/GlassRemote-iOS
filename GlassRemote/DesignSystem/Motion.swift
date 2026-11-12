import SwiftUI
import UIKit

/// Phase 7 motion language, completed in continuation §E. Every animation in the app comes from here
/// so timing and easing stay consistent. SwiftUI springs retarget mid-flight, so all of these are
/// interruptible, and none of them gates an action: state changes immediately and the animation only
/// follows it (controls never wait for a curve, so remote input gains no lag).
enum Motion {
    /// A spring as plain numbers, so the whole language can be inspected and tested.
    struct SpringSpec: Equatable {
        let response: Double
        let damping: Double
        var animation: Animation { .spring(response: response, dampingFraction: damping) }
        /// For layers that follow a finger: the same spring, blended for continuous retargeting.
        var interactive: Animation { .interactiveSpring(response: response, dampingFraction: damping) }
    }

    /// The springs behind the tokens below. Controls settle fast and barely overshoot; larger, spatial
    /// moves (pages, hero, detail) take a little longer; washes of colour never overshoot.
    enum Springs {
        static let tracking = SpringSpec(response: 0.16, damping: 0.86)
        static let press = SpringSpec(response: 0.16, damping: 0.8)
        static let lensStretch = SpringSpec(response: 0.22, damping: 0.8)
        static let pressBounce = SpringSpec(response: 0.25, damping: 0.7)
        static let snappy = SpringSpec(response: 0.28, damping: 0.82)
        static let settle = SpringSpec(response: 0.28, damping: 0.86)
        static let lensLift = SpringSpec(response: 0.3, damping: 0.7)
        static let release = SpringSpec(response: 0.32, damping: 0.86)
        static let content = SpringSpec(response: 0.34, damping: 0.9)
        static let expand = SpringSpec(response: 0.36, damping: 0.88)
        static let lensSettle = SpringSpec(response: 0.38, damping: 0.8)
        static let page = SpringSpec(response: 0.42, damping: 0.86)
        static let poster = SpringSpec(response: 0.5, damping: 0.86)
        static let hero = SpringSpec(response: 0.5, damping: 0.9)
        static let ambient = SpringSpec(response: 0.9, damping: 1)

        /// Springs that move controls the finger is on (keys, lenses, sliders): must feel immediate.
        static let controls: [SpringSpec] = [tracking, press, lensStretch, pressBounce, snappy, settle, lensLift]
        static let all: [SpringSpec] = controls + [release, content, expand, lensSettle, page, poster, hero, ambient]
    }

    /// Page changes and the dock bubble settling on a tab.
    static let page = Springs.page.animation
    /// Small state flips: selection, toggles, chips, press release, mode switches.
    static let snappy = Springs.snappy.animation
    /// Expanding and collapsing content (synopsis, sections).
    static let expand = Springs.expand.animation
    /// Featured-title changes and card to detail expansion.
    static let hero = Springs.hero.animation
    /// Artwork cross-fades.
    static let artwork = Animation.easeInOut(duration: 0.45)
    /// Finger tracking (drags, scrubbing).
    static let tracking = Springs.tracking.interactive
    /// Theme and profile changes.
    static let theme = Animation.easeInOut(duration: 0.35)
    /// Replaces all of the above when motion should be reduced.
    static let reduced = Animation.easeOut(duration: 0.15)

    // Continuation §E: the tokens that replace the remaining one-off curves.

    /// A key or button going down (and the release, through `snappy`).
    static let press = Springs.press.animation
    /// The volume thumb's press bounce.
    static let pressBounce = Springs.pressBounce.animation
    /// A selection lens gliding to its segment after a tap or release.
    static let lensSettle = Springs.lensSettle.animation
    /// A selection lens lifting off and landing while dragged.
    static let lensLift = Springs.lensLift.animation
    /// A selection lens stretching with finger speed.
    static let lensStretch = Springs.lensStretch.interactive
    /// Fill and thumb catching up with a value set from elsewhere (volume read back from the TV).
    static let settle = Springs.settle.animation
    /// A released drag returning home (hero swipe, sheets).
    static let release = Springs.release.animation
    /// Titles and labels changing in place.
    static let content = Springs.content.animation
    /// Posters and now-playing artwork arriving.
    static let poster = Springs.poster.animation
    /// Ambient palette washes (no overshoot on colour).
    static let ambient = Springs.ambient.animation
    /// Opacity-only changes: loaded images, header backgrounds, readouts.
    static let fade = Animation.easeOut(duration: 0.22)

    // v6 §1: the dock's opacity-only curves. They were one-off curves in DockPolicy and the dock's
    // button style; they live here now so navigation stays inside the motion language. Each is a
    // plain fade (nothing moves), quicker than `fade` because it answers a tap on the dock.

    /// The durations behind the dock tokens, as plain numbers so policies and tests can read them.
    enum Durations {
        /// A page switch: short enough to feel instant, long enough not to flash.
        static let tabFade: Double = 0.16
        /// Now Playing opening and closing over the pages (with a slight rise, see `NowPlayingPresentation`).
        static let presentation: Double = 0.26
        /// A pressed dock or mini-player item dimming (no scale, no refraction).
        static let pressDim: Double = 0.12
    }

    /// A dock page switch. An opacity fade is already the reduced form of a page change, so it is
    /// kept under Reduce Motion.
    static let tabFade = Animation.easeOut(duration: Durations.tabFade)
    /// Now Playing presenting over the pages.
    static let presentation = Animation.easeOut(duration: Durations.presentation)
    /// A pressed dock or mini-player item dimming.
    static let pressDim = Animation.easeOut(duration: Durations.pressDim)

    /// Honours both the system Reduce Motion setting and the in-app preference (Profile > Appearance).
    static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation {
        (reduceMotion || MotionPreference.reduced) ? reduced : animation
    }

    /// For motion that only decorates a change (a bounce, a settle): none at all when motion is reduced.
    static func unlessReduced(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        (reduceMotion || MotionPreference.reduced) ? nil : animation
    }

    /// For places without a SwiftUI environment (stores, navigators, button actions): reads the
    /// system Reduce Motion setting at the moment the change happens.
    static func adaptive(_ animation: Animation) -> Animation {
        resolve(animation, reduceMotion: UIAccessibility.isReduceMotionEnabled)
    }
}

/// In-app "Reduce interface motion" preference. Stored per profile by `ProfileStore` and mirrored
/// here so any view can read it synchronously.
enum MotionPreference {
    static let key = "glassRemote.reduceInterfaceMotion"
    static var reduced: Bool { UserDefaults.standard.bool(forKey: key) }
}

/// Continuation §E: the only timed waits the interface keeps. None sequences an animation; each is
/// an input or idle rule with a reason, named here so they are not mistaken for timing hacks.
enum InteractionTiming {
    /// A selection lens relaxes its speed stretch once finger events stop arriving for this long.
    static let lensIdleNanos: UInt64 = 90_000_000
}
