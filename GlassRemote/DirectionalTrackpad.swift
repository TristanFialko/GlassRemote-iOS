import SwiftUI

/// Turns relative finger movement into Samsung D-pad keys. This is NOT a pointer: the Samsung
/// WebSocket remote API documents keys only, so movement is translated into
/// Up / Down / Left / Right presses. Pure and unit tested; the view feeds it deltas.
struct DirectionalTrackpad {
    /// 0.5 ... 3. Higher = fewer points of travel per key.
    var sensitivity: Double = 1.5
    /// Faster strokes use a smaller step, so a flick travels further.
    var acceleration = true
    /// Travel (points) before a touch counts as a swipe instead of a tap.
    var deadZone: CGFloat = 10
    var baseStep: CGFloat = 34
    var maxKeysPerEvent = 2

    private var ax: CGFloat = 0
    private var ay: CGFloat = 0
    private(set) var travel: CGFloat = 0

    mutating func begin() { ax = 0; ay = 0; travel = 0 }

    /// True once the touch has moved past the dead zone (so lifting it must not count as a tap).
    var didMove: Bool { travel >= deadZone }

    mutating func move(dx: CGFloat, dy: CGFloat) -> [SamsungKey] {
        travel += hypot(dx, dy)
        guard travel >= deadZone else { return [] }
        ax += dx; ay += dy

        var step = baseStep / CGFloat(max(sensitivity, 0.1))
        if acceleration {
            let speed = hypot(dx, dy)
            step *= 1 - 0.5 * min(1, max(0, (speed - 2) / 18))
        }
        var keys: [SamsungKey] = []
        while keys.count < maxKeysPerEvent {
            if abs(ax) >= step, abs(ax) >= abs(ay) {
                keys.append(ax > 0 ? .right : .left)
                ax -= (ax > 0 ? step : -step)
                ay = 0                                   // one direction at a time: no diagonal jitter
            } else if abs(ay) >= step {
                keys.append(ay > 0 ? .down : .up)
                ay -= (ay > 0 ? step : -step)
                ax = 0
            } else { break }
        }
        return keys
    }
}

/// Samsung trackpad surface: slide = arrow keys, tap = OK, two-finger tap = Back.
/// Settings live in Connection settings (UserDefaults keys below). Experimental: it is built on
/// repeated key presses, so speed is limited by how fast the TV accepts keys.
struct SamsungTrackpad: View {
    static let sensitivityKey = "glassRemote.samsungPadSensitivity"
    static let accelerationKey = "glassRemote.samsungPadAcceleration"

    @EnvironmentObject private var remote: RemoteModel
    @AppStorage(SamsungTrackpad.sensitivityKey) private var sensitivity = 1.5
    @AppStorage(SamsungTrackpad.accelerationKey) private var acceleration = true
    @State private var pad = DirectionalTrackpad()
    @State private var scrollState = TwoFingerScrollState()
    @State private var last: CGPoint?
    @State private var startedAt = Date()

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 36, style: .continuous)
        Color.clear
            .glassSurface(shape, elevated: true)
            .overlay(alignment: .bottom) {
                Text("Slide to move focus · tap to select · two-finger tap for Back")
                    .scaledFont(12).foregroundStyle(Color.inkFaint(0.42))
                    .padding(.bottom, 16).allowsHitTesting(false)
            }
            .contentShape(shape)
            .background {
                TwoFingerScroll(state: scrollState, onScroll: { _, _ in }, onTwoFingerTap: {
                    Haptics.light()
                    remote.samsungKey(.back)
                })
            }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard !scrollState.suppressesClicks else { last = value.location; return }
                    if last == nil {
                        pad.sensitivity = sensitivity
                        pad.acceleration = acceleration
                        pad.begin()
                        startedAt = Date()
                        last = value.location
                        return
                    }
                    let previous = last ?? value.location
                    last = value.location
                    let keys = pad.move(dx: value.location.x - previous.x, dy: value.location.y - previous.y)
                    if !keys.isEmpty { Haptics.soft() }
                    for key in keys { remote.samsungKey(key) }
                }
                .onEnded { _ in
                    defer { last = nil }
                    guard !scrollState.suppressesClicks, !pad.didMove,
                          Date().timeIntervalSince(startedAt) < 0.35 else { return }
                    Haptics.light()
                    remote.samsungKey(.enter)
                })
            .accessibilityLabel("Samsung trackpad")
            .accessibilityHint("Use the arrow buttons for precise control")
    }
}
