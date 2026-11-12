import XCTest
@testable import GlassRemote

/// v5 §5: Samsung is the only volume source. The Android TV volume path is gone, the unavailable
/// state is explicit, and the thin slider keeps a full touch target with rate-limited haptics.
final class Phase9VolumeV5Tests: XCTestCase {

    // MARK: Routing: never the Android box

    func testVolumeNeverRoutesToTheAndroidBox() {
        for target in [RemoteTarget.android, .samsung] {
            for androidUp in [false, true] {
                for samsungUp in [false, true] {
                    let device = RemoteRouting.device(for: .volume, target: target,
                                                      androidConnected: androidUp, samsungRemoteReady: samsungUp)
                    let label = "target \(target) android \(androidUp) samsung \(samsungUp)"
                    XCTAssertNotEqual(device, .android, label)
                    if samsungUp { XCTAssertEqual(device, .samsung, label) } else { XCTAssertNil(device, label) }
                }
            }
        }
    }

    func testVolumeKeyPolicyCoversEveryVolumeCommand() {
        XCTAssertEqual(VolumeKeyPolicy.keys, ["VOLUME_UP", "VOLUME_DOWN", "MUTE"])
        for key in [SamsungKey.volUp, .volDown, .mute] {
            XCTAssertTrue(VolumeKeyPolicy.isVolumeKey(key.legacyVolumeName ?? ""), "\(key)")
        }
        for name in ["UP", "DOWN", "OK", "BACK", "HOME", "POWER", ""] {
            XCTAssertFalse(VolumeKeyPolicy.isVolumeKey(name), name)
        }
    }

    @MainActor
    func testTheVirtualKeyboardHasNoVolumeUsages() {
        for name in VolumeKeyPolicy.keys {
            XCTAssertNil(VirtualKeyboard.usages[name], name)
            XCTAssertFalse(VirtualKeyboard.routedKeys.contains(name), name)
        }
    }

    func testUnavailableScaleIsExplicit() {
        XCTAssertFalse(VolumeScale.unavailable.isAvailable)
        XCTAssertEqual(VolumeScale.unavailable.route, .unavailable)
        XCTAssertTrue(VolumeScale.samsungAbsolute(.standard).isAvailable)
        XCTAssertTrue(VolumeScale.samsungKeys(max: 60).isAvailable)
        XCTAssertNotEqual(VolumeScale.samsungKeys(max: 100), VolumeScale.unavailable)
    }

    /// Source guard: the ADB volume keycodes, HID volume usages and Android read-back must not return.
    func testNoAndroidVolumeCodeRemains() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let files = ["GlassRemote/RemoteModel.swift", "GlassRemote/RemoteModel+Features.swift",
                     "GlassRemote/VolumeScale.swift", "GlassRemote/VirtualKeyboard.swift",
                     "GlassRemote/RemoteRouting.swift", "GlassRemote/RemoteView.swift"]
        let banned = ["\"VOLUME_UP\": \"24\"", "\"VOLUME_DOWN\": \"25\"", "\"MUTE\": \"164\"",
                      "AndroidVolumeReading", "refreshAndroidVolume", "androidKeys",
                      ".consumer(0xE9)", ".consumer(0xEA)", ".consumer(0xE2)"]
        var checked = 0
        for file in files {
            guard let source = try? String(contentsOf: repo.appendingPathComponent(file), encoding: .utf8) else { continue }
            checked += 1
            for word in banned {
                XCTAssertFalse(source.contains(word), "\(file) still contains \(word)")
            }
        }
        if checked == 0 { throw XCTSkip("app sources are not readable from the test run") }
    }

    // MARK: Thin slider

    func testThinSliderKeepsAFullTouchTarget() {
        XCTAssertEqual(ThinVolumeMetrics.controlHeight(20), 44)
        XCTAssertEqual(ThinVolumeMetrics.controlHeight(58), 58)
        XCTAssertGreaterThanOrEqual(ThinVolumeMetrics.controlHeight(RemoteLayoutPolicy.portraitVolumeThickness), 44)
        XCTAssertLessThanOrEqual(ThinVolumeMetrics.trackHeight(dragging: false), 8, "the visible track is thin")
        XCTAssertGreaterThan(ThinVolumeMetrics.trackHeight(dragging: true), ThinVolumeMetrics.trackHeight(dragging: false))
        XCTAssertLessThan(ThinVolumeMetrics.trackHeight(dragging: true, large: true), ThinVolumeMetrics.minimumTouchTarget)
        XCTAssertEqual(ThinVolumeMetrics.fillWidth(value: 0, width: 300), 0)
        XCTAssertEqual(ThinVolumeMetrics.fillWidth(value: 0.5, width: 300), 150)
        XCTAssertEqual(ThinVolumeMetrics.fillWidth(value: 1.4, width: 300), 300)
        XCTAssertEqual(ThinVolumeMetrics.fillWidth(value: -1, width: 300), 0)
        XCTAssertEqual(ThinVolumeMetrics.fillWidth(value: .nan, width: 300), 0)
        XCTAssertEqual(ThinVolumeMetrics.fillWidth(value: 0.5, width: 0), 0)
    }

    func testHapticsAreRateLimitedButTheEndsAlwaysTick() {
        var throttle = VolumeHapticThrottle()
        let gap = VolumeHapticThrottle.minimumInterval
        let t0 = Date(timeIntervalSinceReferenceDate: 5_000)
        func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
        XCTAssertTrue(throttle.shouldTick(previousStep: 50, newStep: 51, steps: 100, userInitiated: true, at: t0))
        XCTAssertFalse(throttle.shouldTick(previousStep: 51, newStep: 52, steps: 100, userInitiated: true, at: at(gap / 4)),
                       "a fast sweep does not buzz")
        XCTAssertTrue(throttle.shouldTick(previousStep: 52, newStep: 53, steps: 100, userInitiated: true, at: at(gap + 0.01)))
        XCTAssertTrue(throttle.shouldTick(previousStep: 99, newStep: 100, steps: 100, userInitiated: true, at: at(gap + 0.02)),
                      "the top always ticks")
        XCTAssertTrue(throttle.shouldTick(previousStep: 1, newStep: 0, steps: 100, userInitiated: true, at: at(gap + 0.03)),
                      "the floor always ticks")
        XCTAssertFalse(throttle.shouldTick(previousStep: 40, newStep: 40, steps: 100, userInitiated: true, at: at(1)),
                       "no level change, no tick")
        XCTAssertFalse(throttle.shouldTick(previousStep: 40, newStep: 41, steps: 100, userInitiated: false, at: at(2)),
                       "TV readings never tick")
        XCTAssertFalse(throttle.shouldTick(previousStep: nil, newStep: 41, steps: 100, userInitiated: true, at: at(3)),
                       "a drag's first callback has no previous level")
        throttle.reset()
        XCTAssertNil(throttle.lastTick)
        XCTAssertTrue(throttle.shouldTick(previousStep: 10, newStep: 11, steps: 100, userInitiated: true, at: at(3)))
    }

    func testReversingMidDragStillKeepsReadingsOut() {
        var sync = VolumeSync()
        let t0 = Date(timeIntervalSinceReferenceDate: 9_000)
        sync.dragBegan(at: t0)
        sync.userChanged(at: t0.addingTimeInterval(0.1))
        sync.userChanged(at: t0.addingTimeInterval(0.2))   // the finger reverses: still the finger's value
        XCTAssertNil(sync.reading(0.2, showing: 0.6, at: t0.addingTimeInterval(0.5)),
                     "a reading never moves the level under a finger")
        sync.dragEnded(at: t0.addingTimeInterval(1))
        XCTAssertNil(sync.reading(0.2, showing: 0.6, at: t0.addingTimeInterval(1.5)), "still inside the hold-off")
        XCTAssertEqual(sync.reading(0.2, showing: 0.6, at: t0.addingTimeInterval(1 + sync.holdoff + 0.01)), 0.2,
                       "after the hold-off the device's settled value is shown")
    }
}
