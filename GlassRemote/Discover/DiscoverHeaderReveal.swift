import SwiftUI

/// v6 §8: whether Discover's floating search/filter header is showing. Pure and unit tested.
///
/// Scrolling the content down hides it once the content has travelled `hideAfter` points in that
/// direction; scrolling up reveals it after `revealAfter` points. Rubber-band overscroll at either end
/// is clamped away (a bounce never flips it), a direction reversal restarts the count, and jitter below
/// the thresholds never toggles it. It stays pinned visible near the top, while the content is too
/// short to scroll past the header, while the search field is focused and while VoiceOver runs.
/// Portrait and landscape use the same rule; only the header's own height differs.
struct DiscoverHeaderReveal: Equatable {
    /// Downward travel before the header hides: a deliberate scroll, not a nudge.
    static let hideAfter: CGFloat = 28
    /// Upward travel before it comes back: shorter, so search is quick to reach again.
    static let revealAfter: CGFloat = 14

    private(set) var hidden = false
    private(set) var lastOffset: CGFloat?
    /// Signed travel in the current direction (positive: content moving up, i.e. scrolling down).
    private(set) var travel: CGFloat = 0

    /// The zone at the top of the content where the header always shows.
    static func topZone(headerHeight: CGFloat) -> CGFloat { max(headerHeight, 44) }

    /// Vertical offset for the header: slides up out of view, or (Reduce Motion) stays put and only fades.
    static func offset(hidden: Bool, travel: CGFloat, reduceMotion: Bool) -> CGFloat {
        hidden && !reduceMotion ? -max(travel, 0) : 0
    }

    /// Feeds one scroll sample. `offset` is the content offset from the top, `maxOffset` the largest
    /// offset the content can rest at. Returns true when `hidden` changed.
    @discardableResult
    mutating func update(offset rawOffset: CGFloat, maxOffset: CGFloat, topZone: CGFloat, pinned: Bool) -> Bool {
        let before = hidden
        let limit = max(maxOffset, 0)
        let offset = min(max(rawOffset, 0), limit)
        let last = lastOffset
        lastOffset = offset
        guard !pinned, offset > topZone, limit > topZone + Self.hideAfter else {
            hidden = false
            travel = 0
            return hidden != before
        }
        guard let last else { return false }
        let delta = offset - last
        guard delta != 0 else { return false }
        if travel != 0 && (delta > 0) != (travel > 0) { travel = 0 }
        travel += delta
        if !hidden && travel >= Self.hideAfter {
            hidden = true
            travel = 0
        } else if hidden && travel <= -Self.revealAfter {
            hidden = false
            travel = 0
        }
        return hidden != before
    }

    /// Shows the header at once (focus, a new search, the filter changing, VoiceOver starting).
    mutating func reveal() {
        hidden = false
        travel = 0
    }
}

/// Holds the reveal state outside SwiftUI's state, so scroll frames never re-render the page; only
/// the header's hidden flag flipping does.
final class DiscoverHeaderTracker {
    var state = DiscoverHeaderReveal()
}

/// One scroll sample for `DiscoverHeaderReveal`.
struct DiscoverScrollSample: Equatable {
    var offset: CGFloat
    var maxOffset: CGFloat
}

extension DiscoverScrollSample {
    init(geometry: ScrollGeometry) {
        offset = geometry.contentOffset.y + geometry.contentInsets.top
        maxOffset = geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom
            - geometry.containerSize.height
    }
}

/// v6 §8: Discover keeps its layout when the search keyboard comes up. The page ignores the keyboard
/// safe area (so the hero and header never resize or jump, and the dock stays where it is), and the
/// scroll content gains only the bottom margin the keyboard actually covers beyond the dock's space,
/// so every result can still be scrolled into view.
enum DiscoverKeyboardPolicy {
    /// How much of the screen the keyboard covers, measured from the bottom.
    static func overlap(keyboardFrame: CGRect, screenHeight: CGFloat) -> CGFloat {
        guard keyboardFrame.height > 0 else { return 0 }
        return max(0, screenHeight - keyboardFrame.minY)
    }

    /// Extra bottom margin for the scroll content: the overlap beyond the dock clearance it already keeps.
    static func contentMargin(keyboardOverlap: CGFloat, dockClearance: CGFloat) -> CGFloat {
        max(0, keyboardOverlap - dockClearance)
    }
}
