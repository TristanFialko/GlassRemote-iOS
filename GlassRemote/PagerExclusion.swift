import SwiftUI
import UIKit

/// Phase 7.1: places where a page swipe may never start. Each scrub selector (Discover's
/// All / Movies / Series filter, the device selector, the Mouse / D-pad selector) puts an invisible
/// UIKit view behind itself. The pager checks these frames when a touch lands, before any movement,
/// so a sideways slide on a selector always belongs to the selector.
///
/// `ScrubTouch` alone was not enough: it is only set once the selector's SwiftUI gesture reports a
/// change, and inside a scroll view that report can arrive after the pager has already begun.
@MainActor
final class PagerExclusionRegistry {
    static let shared = PagerExclusionRegistry()
    private let views = NSHashTable<UIView>.weakObjects()

    func add(_ view: UIView) { views.add(view) }
    func remove(_ view: UIView) { views.remove(view) }

    /// Frames of every zone on the same window as `host`, in `host`'s coordinates.
    /// Phase 7.3: every page stays alive in the pager, so zones of off-screen pages (and hidden ones) are
    /// dropped; only zones that are on screen now can block a page swipe.
    func frames(in host: UIView) -> [CGRect] {
        let frames: [CGRect] = views.allObjects.compactMap { view in
            guard let window = view.window, window === host.window, Self.isShown(view) else { return nil }
            return view.convert(view.bounds, to: host)
        }
        return PagerGesturePolicy.visibleZones(frames, in: host.bounds)
    }

    static func isShown(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let candidate = current {
            if candidate.isHidden || candidate.alpha < 0.01 { return false }
            current = candidate.superview
        }
        return true
    }
}

/// Invisible marker for a no-page-swipe zone. Never takes touches.
struct PagerExclusionZone: UIViewRepresentable {
    func makeUIView(context: Context) -> PagerExclusionView {
        let view = PagerExclusionView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: PagerExclusionView, context: Context) {}
}

final class PagerExclusionView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { PagerExclusionRegistry.shared.add(self) } else { PagerExclusionRegistry.shared.remove(self) }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}

/// Continuation §D: the opposite of an exclusion zone. In landscape the Remote is almost all controls,
/// so a vertical page swipe may start on it only inside these areas: the free space in its side columns
/// (placed by `RemoteStageLayout`). Off-screen and hidden areas never count.
@MainActor
final class PagerSwipeAreaRegistry {
    static let shared = PagerSwipeAreaRegistry()
    private let views = NSHashTable<UIView>.weakObjects()

    func add(_ view: UIView) { views.add(view) }
    func remove(_ view: UIView) { views.remove(view) }

    /// Frames of every area on the same window as `host`, in `host`'s coordinates.
    func frames(in host: UIView) -> [CGRect] {
        let frames: [CGRect] = views.allObjects.compactMap { view in
            guard let window = view.window, window === host.window, PagerExclusionRegistry.isShown(view) else { return nil }
            return view.convert(view.bounds, to: host)
        }
        return PagerGesturePolicy.visibleZones(frames, in: host.bounds)
    }
}

/// Invisible marker for a page-swipe area. Never takes touches.
struct PagerSwipeArea: UIViewRepresentable {
    func makeUIView(context: Context) -> PagerSwipeAreaView {
        let view = PagerSwipeAreaView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: PagerSwipeAreaView, context: Context) {}
}

final class PagerSwipeAreaView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { PagerSwipeAreaRegistry.shared.add(self) } else { PagerSwipeAreaRegistry.shared.remove(self) }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}
