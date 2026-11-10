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
    func frames(in host: UIView) -> [CGRect] {
        views.allObjects.compactMap { view in
            guard let window = view.window, window === host.window, !view.isHidden else { return nil }
            return view.convert(view.bounds, to: host)
        }
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
