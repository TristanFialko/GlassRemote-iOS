import SwiftUI

/// A D-pad key that fires once on a quick tap and auto-repeats (accelerating) while held.
/// A drag of more than a few points cancels the key so the surrounding swipe gesture can take over.
///
/// `hitShape` limits where the key can be touched (the D-pad's wedges use it so diagonals reach
/// the nearest arrow). `onPressChange` reports finger down/up so the owner can light the key; it
/// never delays or changes when the key fires. `repeats: false` (OK) fires exactly once per touch:
/// holding OK must never become a stream of Enter presses.
///
/// Cancellation (audit BUG-007/015): SwiftUI does not always call `onEnded` when the system takes
/// the touch (Control Center, a call, a notification). The key therefore also stops and unlights
/// when its gesture state resets without an end, when the app leaves the foreground, when the app
/// posts `.glassRemoteCancelTouches` (page change, Now Playing), and after
/// `InputCancellation.maximumRepeatDuration` of continuous repeat.
struct RepeatKey<Content: View, HitShape: Shape>: View {
    let onFire: () -> Void
    let onPressChange: ((Bool) -> Void)?
    let hitShape: HitShape
    let repeats: Bool
    let label: () -> Content

    init(hitShape: HitShape, repeats: Bool = true, onFire: @escaping () -> Void,
         onPressChange: ((Bool) -> Void)? = nil, @ViewBuilder label: @escaping () -> Content) {
        self.hitShape = hitShape
        self.repeats = repeats
        self.onFire = onFire
        self.onPressChange = onPressChange
        self.label = label
    }

    private final class Box {
        var began = false
        var cancelled = false
        var repeating = false
        var touchID = 0
        var task: Task<Void, Never>?
    }

    @State private var box = Box()
    @State private var pressed = false
    @GestureState private var touching = false
    @Environment(\.scenePhase) private var scenePhase

    private static var holdDelay: UInt64 { 350_000_000 }
    private static var moveLimit: CGFloat { 14 }

    var body: some View {
        label()
            .scaleEffect(pressed ? 0.96 : 1)
            .opacity(pressed ? 0.88 : 1)
            .animation(Motion.adaptive(pressed ? Motion.press : Motion.snappy), value: pressed)
            .contentShape(hitShape)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($touching) { _, state, _ in state = true }
                    .onChanged { value in
                        if !box.began {
                            box.began = true
                            box.cancelled = false
                            box.repeating = false
                            box.touchID &+= 1
                            setPressed(true)
                            if repeats { startHoldTimer() }
                        }
                        let moved = max(abs(value.translation.width), abs(value.translation.height))
                        if moved > Self.moveLimit && !box.repeating && !box.cancelled {
                            box.cancelled = true
                            box.task?.cancel()
                            setPressed(false)
                        }
                    }
                    .onEnded { _ in
                        box.task?.cancel()
                        // A short, still touch is a tap. (A hold already fired and repeated.)
                        if box.began && !box.cancelled && !box.repeating { fire() }
                        box.began = false
                        box.repeating = false
                        setPressed(false)
                    }
            )
            .onChange(of: touching) { _, isTouching in
                // The gesture state reset. A normal end also resets it, so give `onEnded` a moment;
                // if the same touch is still open afterwards, the system cancelled it.
                guard !isTouching, box.began else { return }
                let id = box.touchID
                let box = self.box
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: InputCancellation.lostEndGrace)
                    guard box.began, box.touchID == id else { return }
                    cancelTouch()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { cancelTouch() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .glassRemoteCancelTouches)) { _ in
                cancelTouch()
            }
            // Phase 7.3: a key that leaves the screen mid-touch (mode switch, rotation) must not keep
            // repeating or stay lit; its gesture's end may never arrive.
            .onDisappear { cancelTouch() }
    }

    private func cancelTouch() {
        box.task?.cancel()
        box.task = nil
        // A cancelled touch is never a tap, even if a late `onEnded` arrives.
        box.cancelled = box.began
        box.began = false
        box.repeating = false
        setPressed(false)
    }

    private func setPressed(_ value: Bool) {
        guard pressed != value else { return }
        pressed = value
        onPressChange?(value)
    }

    private func fire() {
        Haptics.soft()
        onFire()
    }

    private func startHoldTimer() {
        let box = self.box
        box.task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.holdDelay)
            guard !Task.isCancelled, !box.cancelled else { return }
            box.repeating = true
            let started = Date()
            var interval = 0.16
            var count = 0
            while !Task.isCancelled, InputCancellation.repeatMayContinue(startedAt: started, now: Date()) {
                // One haptic per few repeats keeps a long hold from buzzing continuously.
                if count % 4 == 0 { Haptics.soft() }
                onFire()
                count += 1
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                interval = max(0.06, interval * 0.92)   // speeds up the longer it is held
            }
            if !Task.isCancelled { cancelTouch() }   // the cap was reached: stop and unlight
        }
    }
}

extension RepeatKey where HitShape == Rectangle {
    /// The original rectangular key.
    init(repeats: Bool = true, onFire: @escaping () -> Void, onPressChange: ((Bool) -> Void)? = nil,
         @ViewBuilder label: @escaping () -> Content) {
        self.init(hitShape: Rectangle(), repeats: repeats, onFire: onFire, onPressChange: onPressChange, label: label)
    }
}
