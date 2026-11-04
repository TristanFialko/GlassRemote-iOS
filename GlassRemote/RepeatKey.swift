import SwiftUI

/// A D-pad key that fires once on a quick tap and auto-repeats (accelerating) while held.
/// A drag of more than a few points cancels the key so the surrounding swipe gesture can take over.
struct RepeatKey<Content: View>: View {
    let onFire: () -> Void
    @ViewBuilder let label: () -> Content

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
            .animation(.easeOut(duration: 0.12), value: pressed)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !box.began {
                            box.began = true
                            box.cancelled = false
                            box.repeating = false
                            pressed = true
                            startHoldTimer()
                        }
                        let moved = max(abs(value.translation.width), abs(value.translation.height))
                        if moved > Self.moveLimit && !box.repeating && !box.cancelled {
                            box.cancelled = true
                            box.task?.cancel()
                            pressed = false
                        }
                    }
                    .onEnded { _ in
                        box.task?.cancel()
                        // A short, still touch is a tap. (A hold already fired and repeated.)
                        if box.began && !box.cancelled && !box.repeating { fire() }
                        box.began = false
                        box.repeating = false
                        pressed = false
                    }
            )
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
