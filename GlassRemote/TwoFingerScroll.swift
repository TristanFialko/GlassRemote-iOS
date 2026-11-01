import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Shared flag so the existing one-finger trackpad ignores pointer motion and taps
/// while two fingers are scrolling.
@MainActor
final class TwoFingerScrollState {
    private(set) var isActive = false
    private var lastActivity = Date.distantPast

    /// True while two fingers are down, and briefly after, so a finger lift cannot tap.
    var suppressesClicks: Bool {
        isActive || Date().timeIntervalSince(lastActivity) < 0.25
    }

    func set(active: Bool) {
        isActive = active
        lastActivity = Date()
    }
}

/// Two-finger scrolling for the trackpad. It sends standard mouse wheel (vertical) and
/// AC Pan (horizontal) values through the existing `RemoteModel.mouse` report path.
/// It never touches one-finger movement or clicking.
struct TwoFingerScroll: UIViewRepresentable {
    let state: TwoFingerScrollState
    let onScroll: @MainActor (_ wheel: Int, _ hscroll: Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, onScroll: onScroll)
    }

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.backgroundColor = .clear

        let coordinator = context.coordinator
        let recognizer = TwoFingerScrollRecognizer()
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = coordinator
        recognizer.onMove = { [weak coordinator] dx, dy in
            coordinator?.handle(dx: dx, dy: dy)
        }
        recognizer.onEngagedChanged = { [weak coordinator] engaged in
            coordinator?.engagedChanged(engaged)
        }

        coordinator.trackView = view
        view.recognizer = recognizer
        return view
    }

    func updateUIView(_ uiView: AnchorView, context: Context) {
        context.coordinator.onScroll = onScroll
    }

    static func dismantleUIView(_ uiView: AnchorView, coordinator: Coordinator) {
        uiView.detach()
    }

    // MARK: - Coordinator (finger travel -> wheel notches)

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        // Tuning. Smaller pointsPerNotch = faster scrolling. Flip a sign if a direction
        // feels backwards. maxPerReport caps speed so scrolling never accelerates wildly.
        static let pointsPerNotch: CGFloat = 28
        static let maxPerReport = 3
        static let verticalSign = 1      // finger moves down -> content moves down
        static let horizontalSign = -1   // finger moves left  -> content moves left
        static let lockDistance: CGFloat = 10

        private enum Axis { case vertical, horizontal }

        let state: TwoFingerScrollState
        var onScroll: @MainActor (Int, Int) -> Void
        weak var trackView: UIView?

        private var lock: Axis?
        private var travelX: CGFloat = 0
        private var travelY: CGFloat = 0
        private var accumulatedX: CGFloat = 0
        private var accumulatedY: CGFloat = 0

        init(state: TwoFingerScrollState, onScroll: @escaping @MainActor (Int, Int) -> Void) {
            self.state = state
            self.onScroll = onScroll
        }

        func engagedChanged(_ engaged: Bool) {
            if engaged {
                lock = nil
                travelX = 0; travelY = 0
                accumulatedX = 0; accumulatedY = 0
            }
            state.set(active: engaged)
        }

        func handle(dx: CGFloat, dy: CGFloat) {
            // Decide the dominant axis from the first few points of travel, then stay on it.
            guard let axis = lock else {
                travelX += abs(dx)
                travelY += abs(dy)
                if max(travelX, travelY) >= Self.lockDistance {
                    lock = travelY >= travelX ? .vertical : .horizontal
                }
                return
            }

            switch axis {
            case .vertical:
                accumulatedY += dy
                let steps = Int(accumulatedY / Self.pointsPerNotch)
                if steps != 0 {
                    let applied = max(-Self.maxPerReport, min(Self.maxPerReport, steps))
                    accumulatedY -= CGFloat(applied) * Self.pointsPerNotch
                    onScroll(applied * Self.verticalSign, 0)
                }
            case .horizontal:
                accumulatedX += dx
                let steps = Int(accumulatedX / Self.pointsPerNotch)
                if steps != 0 {
                    let applied = max(-Self.maxPerReport, min(Self.maxPerReport, steps))
                    accumulatedX -= CGFloat(applied) * Self.pointsPerNotch
                    onScroll(0, applied * Self.horizontalSign)
                }
            }
        }

        // Only react to touches that land on the trackpad itself.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let trackView else { return false }
            return trackView.bounds.contains(touch.location(in: trackView))
        }

        // Run alongside SwiftUI's own gestures; never block or cancel them.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

/// Zero-interaction view that sits behind the trackpad. It exists only to attach the
/// recogniser to the hosting view, so one-finger touches keep reaching SwiftUI untouched.
final class AnchorView: UIView {
    var recognizer: TwoFingerScrollRecognizer?
    private weak var attachedTo: UIView?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        detach()
        guard window != nil, let recognizer, let host = hostView() else { return }
        host.addGestureRecognizer(recognizer)
        attachedTo = host
    }

    func detach() {
        if let recognizer {
            attachedTo?.removeGestureRecognizer(recognizer)
        }
        attachedTo = nil
    }

    private func hostView() -> UIView? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController { return controller.view }
            responder = current.next
        }
        return nil
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }
}

/// Tracks the first two touches and reports how far their midpoint moved.
/// It stays "engaged" until every finger is lifted, so the remaining finger cannot
/// nudge the cursor as the other one leaves.
final class TwoFingerScrollRecognizer: UIGestureRecognizer {
    var onMove: ((CGFloat, CGFloat) -> Void)?
    var onEngagedChanged: ((Bool) -> Void)?

    private var tracked: [UITouch] = []
    private var lastCentroid: CGPoint?
    private var engaged = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches where !tracked.contains(where: { $0 === touch }) {
            tracked.append(touch)
        }

        if tracked.count >= 2 {
            if !engaged {
                engaged = true
                onEngagedChanged?(true)
            }
            lastCentroid = centroid()
            if state == .possible { state = .began }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard engaged, tracked.count >= 2, let previous = lastCentroid else { return }
        let current = centroid()
        lastCentroid = current
        onMove?(current.x - previous.x, current.y - previous.y)
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(touches, cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(touches, cancelled: true)
    }

    override func reset() {
        tracked.removeAll()
        lastCentroid = nil
        if engaged {
            engaged = false
            onEngagedChanged?(false)
        }
    }

    private func finish(_ touches: Set<UITouch>, cancelled: Bool) {
        tracked.removeAll { touches.contains($0) }
        if tracked.count < 2 { lastCentroid = nil }

        if tracked.isEmpty {
            if engaged {
                state = cancelled ? .cancelled : .ended
            } else {
                state = .failed
            }
        }
    }

    private func centroid() -> CGPoint {
        let points = tracked.prefix(2).map { $0.location(in: view) }
        let count = CGFloat(max(points.count, 1))
        let x = points.map { $0.x }.reduce(0, +) / count
        let y = points.map { $0.y }.reduce(0, +) / count
        return CGPoint(x: x, y: y)
    }
}
