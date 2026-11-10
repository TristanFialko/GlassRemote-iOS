import SwiftUI

/// Phase 7 motion language. Every animation in the app should come from here so timing and easing
/// stay consistent. SwiftUI springs retarget mid-flight, so all of these are interruptible, and none of
/// them gates an action: state changes immediately and the animation only follows it.
enum Motion {
    /// Page changes and the dock bubble settling on a tab.
    static let page = Animation.spring(response: 0.42, dampingFraction: 0.86)
    /// Small state flips: selection, toggles, chips, press release.
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.82)
    /// Expanding and collapsing content (synopsis, sections).
    static let expand = Animation.spring(response: 0.36, dampingFraction: 0.88)
    /// Featured-title changes and card to detail expansion.
    static let hero = Animation.spring(response: 0.5, dampingFraction: 0.9)
    /// Artwork cross-fades.
    static let artwork = Animation.easeInOut(duration: 0.45)
    /// Finger tracking (drags, scrubbing).
    static let tracking = Animation.interactiveSpring(response: 0.16, dampingFraction: 0.86)
    /// Theme and profile changes.
    static let theme = Animation.easeInOut(duration: 0.35)
    /// Replaces all of the above when motion should be reduced.
    static let reduced = Animation.easeOut(duration: 0.15)

    /// Honours both the system Reduce Motion setting and the in-app preference (Profile > Appearance).
    static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation {
        (reduceMotion || MotionPreference.reduced) ? reduced : animation
    }
}

/// In-app "Reduce interface motion" preference. Stored per profile by `ProfileStore` and mirrored
/// here so any view can read it synchronously.
enum MotionPreference {
    static let key = "glassRemote.reduceInterfaceMotion"
    static var reduced: Bool { UserDefaults.standard.bool(forKey: key) }
}
