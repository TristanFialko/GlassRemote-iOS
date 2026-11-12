import SwiftUI

/// A D-pad key that fires once on a quick tap and auto-repeats (accelerating) while held.
/// A drag of more than a few points cancels the key so the surrounding swipe gesture can take over.
///
/// `hitShape` limits where the key can be touched (the D-pad's wedges use it so diagonals reach
/// the nearest arrow). `onPressChange` reports finger down/up so the owner can light the key; it
/// never delays or changes when the key fires.
struct RepeatKey<Content: View, HitShape: Shape>: View {
    let onFire: () -> Void
    let onPressChange: ((Bool) -> Void)?
    let hitShape: HitShape
    let label: () -> Content

    init(hitShape: HitShape, onFire: @escaping () -> Void, onPressChange: ((Bool) -> Void)? = nil,
         @ViewBuilder label: @escaping () -> Content) {
        self.hitShape = hitShape
        self.onFire = onFire
        self.onPressChange = onPressChange
        self.label = label
    }

    private final class Box {
        var began = false
        var cancelled = false
        var repeating = false
        var task: Task<Void, Never>?
    }

    @State private var box = Box()
    @State private var pressed = false

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
                    .onChanged { value in
                        if !box.began {
                            box.began = true
                            box.cancelled = false
                            box.repeating = false
                            setPressed(true)
                            startHoldTimer()
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
            // Phase 7.3: a key that leaves the screen mid-touch (mode switch, rotation) must not keep
            // repeating or stay lit; its gesture's end may never arrive.
            .onDisappear { cancelTouch() }
    }

    private func cancelTouch() {
        box.task?.cancel()
        box.task = nil
        box.began = false
        box.cancelled = false
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
            var interval = 0.16
            while !Task.isCancelled {
                fire()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                interval = max(0.06, interval * 0.92)   // speeds up the longer it is held
            }
        }
    }
}

extension RepeatKey where HitShape == Rectangle {
    /// The original rectangular key.
    init(onFire: @escaping () -> Void, onPressChange: ((Bool) -> Void)? = nil,
         @ViewBuilder label: @escaping () -> Content) {
        self.init(hitShape: Rectangle(), onFire: onFire, onPressChange: onPressChange, label: label)
    }
}
