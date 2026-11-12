import SwiftUI

extension Notification.Name {
    /// Posted when every in-flight touch on the remote surfaces must end now: a page change, the
    /// Now Playing overlay opening, or the app leaving the foreground. Keys stop repeating and unlight,
    /// the trackpad releases any held mouse button. Gesture ends from SwiftUI are not guaranteed after
    /// a system interruption (Control Center, a call, a notification), so this is the backstop.
    static let glassRemoteCancelTouches = Notification.Name("GlassRemote.cancelTouches")
}

enum InputCancellation {
    /// The longest a held key may auto-repeat before it stops on its own (a lost touch end must not
    /// keep moving focus on the TV indefinitely).
    static let maximumRepeatDuration: TimeInterval = 30

    /// After SwiftUI resets a gesture's state, wait this long for its `onEnded`; if it never comes,
    /// the touch was cancelled by the system and is cleaned up.
    static let lostEndGrace: UInt64 = 120_000_000

    @MainActor
    static func cancelAllTouches(reason: String) {
        GRLog.note("input", "cancel touches: \(reason)")
        NotificationCenter.default.post(name: .glassRemoteCancelTouches, object: nil)
    }

    /// Whether a repeat that started at `start` should keep firing at `now` (pure, unit tested).
    static func repeatMayContinue(startedAt start: Date, now: Date) -> Bool {
        now.timeIntervalSince(start) < maximumRepeatDuration
    }
}

/// Keeps a cancelled key from restarting within the same touch (pure, unit tested). A touch that is
/// cancelled while the finger stays down (repeat cap, page change) keeps delivering drag events; those
/// must not begin a new press and repeat. The key may begin again only after the finger lifts.
struct HeldTouchGate: Equatable {
    private var fingerDown = false
    private var blocked = false

    /// A drag event of the current touch. Returns whether the key may (re)begin a press.
    mutating func touched() -> Bool {
        fingerDown = true
        return !blocked
    }

    /// The key was cancelled; if the finger is still down, ignore the rest of this touch.
    mutating func cancelled() { blocked = fingerDown }

    /// The touch ended or its gesture state was reset.
    mutating func lifted() {
        fingerDown = false
        blocked = false
    }
}

private struct RemoteSurfaceActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether the Remote page's touch surfaces are the visible, active UI (audit BUG-006). Hidden
    /// pages stay mounted (opacity 0), so UIKit recognisers attached above them must check this.
    var remoteSurfaceActive: Bool {
        get { self[RemoteSurfaceActiveKey.self] }
        set { self[RemoteSurfaceActiveKey.self] = newValue }
    }
}

/// VoiceOver actions on the mouse trackpad (audit A11Y-001).
enum TrackpadAccessibility {
    /// Wheel notches per "Scroll up / down" action.
    static let scrollNotches = 3
    /// Pointer travel per "Move pointer" action, in helper units (about one list row on the TV).
    static let nudge = 40
}

/// The mouse trackpad's VoiceOver actions (audit A11Y-001): click, Back, scroll and pointer nudges.
struct TrackpadAccessibilityActions: ViewModifier {
    let remote: RemoteModel

    func body(content: Content) -> some View {
        content
            .accessibilityAction { remote.mouseClick() }
            .accessibilityAction(.escape) { remote.key("BACK") }
            .accessibilityAction(named: "Back") { remote.key("BACK") }
            .accessibilityAction(named: "Scroll up") { scroll(TrackpadAccessibility.scrollNotches) }
            .accessibilityAction(named: "Scroll down") { scroll(-TrackpadAccessibility.scrollNotches) }
            .accessibilityAction(named: "Move pointer left") { move(dx: -TrackpadAccessibility.nudge, dy: 0) }
            .accessibilityAction(named: "Move pointer right") { move(dx: TrackpadAccessibility.nudge, dy: 0) }
            .accessibilityAction(named: "Move pointer up") { move(dx: 0, dy: -TrackpadAccessibility.nudge) }
            .accessibilityAction(named: "Move pointer down") { move(dx: 0, dy: TrackpadAccessibility.nudge) }
    }

    private func scroll(_ notches: Int) { remote.mouse(wheel: notches, hscroll: 0) }
    private func move(dx: Int, dy: Int) { remote.mouseMove(dx: dx, dy: dy) }
}
