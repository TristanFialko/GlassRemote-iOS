import XCTest
import SwiftUI
@testable import GlassRemote

/// Audit remediation, Priority B (gesture cancellation). SwiftUI touch cancellation itself can only
/// be exercised on an iPhone (hardware acceptance checklist, rows 6–9). These tests pin the policy
/// values and the wiring so the backstops cannot silently disappear.
final class RemediationGestureTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard let text = try? String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8) else {
            throw XCTSkip("\(relative) not readable from the test host")
        }
        return text
    }

    func testARepeatStopsOnItsOwnAfterTheCap() {
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(InputCancellation.repeatMayContinue(startedAt: start, now: start.addingTimeInterval(5)))
        XCTAssertFalse(InputCancellation.repeatMayContinue(
            startedAt: start, now: start.addingTimeInterval(InputCancellation.maximumRepeatDuration)))
        XCTAssertLessThanOrEqual(InputCancellation.maximumRepeatDuration, 60)
    }

    func testTheLostEndGraceIsShortButLongerThanAFrame() {
        XCTAssertGreaterThan(InputCancellation.lostEndGrace, 33_000_000)
        XCTAssertLessThanOrEqual(InputCancellation.lostEndGrace, 250_000_000)
    }

    func testRemoteSurfaceIsActiveByDefault() {
        XCTAssertTrue(EnvironmentValues().remoteSurfaceActive, "other uses of the recogniser are unaffected")
    }

    // BUG-007 / BUG-015: a held key has a cancellation path besides onEnded / onDisappear.
    func testRepeatKeyCancelsOnGestureResetBackgroundAndAppSignal() throws {
        let text = try source("GlassRemote/RepeatKey.swift")
        XCTAssertTrue(text.contains(".updating($touching)"))
        XCTAssertTrue(text.contains(".onChange(of: scenePhase)"))
        XCTAssertTrue(text.contains(".glassRemoteCancelTouches"))
        XCTAssertTrue(text.contains("InputCancellation.repeatMayContinue"))
    }

    // BUG-009: OK fires once per touch; it never auto-repeats Enter.
    func testOKNeverAutoRepeats() throws {
        let dpad = try source("GlassRemote/Remote/GlassDpad.swift")
        XCTAssertTrue(dpad.contains("RepeatKey(hitShape: Circle(), repeats: false"))
    }

    // BUG-006: the two-finger recogniser follows the Remote surface's visibility.
    func testTwoFingerRecogniserIsScopedToTheVisibleRemote() throws {
        let scroll = try source("GlassRemote/TwoFingerScroll.swift")
        XCTAssertTrue(scroll.contains("context.environment.remoteSurfaceActive"))
        let pager = try source("GlassRemote/RootPagerView.swift")
        XCTAssertTrue(pager.contains(".environment(\\.remoteSurfaceActive, navigator.page == .remote && !navigator.playerPresented)"))
        let remote = try source("GlassRemote/RemoteView.swift")
        XCTAssertTrue(remote.contains("remoteSurfaceActive && !folder.isVisible"))
    }

    // BUG-008: the trackpad cleans up a lost touch and the model releases a held button.
    func testMousePadReleasesOnCancellation() throws {
        let remote = try source("GlassRemote/RemoteView.swift")
        XCTAssertTrue(remote.contains(".updating($mouseTouching)"))
        XCTAssertTrue(remote.contains("if phase != .active { cancelPointer() }"))
        let mouse = try source("GlassRemote/RemoteModel+Mouse.swift")
        XCTAssertTrue(mouse.contains("func releaseHeldMouseButton"))
        XCTAssertTrue(mouse.contains("guard mouseReady, mouseButtonsHeld != 0 else { return }"),
                      "leaving the app sends nothing unless a button is held")
        let model = try source("GlassRemote/RemoteModel.swift")
        XCTAssertTrue(model.contains("releaseHeldMouseButton(reason: \"app left the foreground\")"))
        XCTAssertTrue(model.contains("clearStaleMouseButtonOnTV()"))
    }

    // Page changes and Now Playing end every touch in flight.
    func testNavigationCancelsTouches() throws {
        let nav = try source("GlassRemote/PageNavigator.swift")
        XCTAssertTrue(nav.contains("InputCancellation.cancelAllTouches(reason: \"page change\")"))
        XCTAssertTrue(nav.contains("InputCancellation.cancelAllTouches(reason: \"Now Playing opened\")"))
    }

    // UX-012: the Mouse/D-pad selector commits on release; its bar is a full touch target.
    func testModeSelectorCommitsOnRelease() throws {
        let style = try source("GlassRemote/GlassStyle.swift")
        guard let start = style.range(of: "struct ModeSelector: View") else { return XCTFail("ModeSelector missing") }
        XCTAssertTrue(style[start.lowerBound...].contains("commitOnRelease: true"))
        for landscape in [false, true] {
            for compact in [false, true] {
                // Segment height plus the 4 pt inset on each side.
                XCTAssertGreaterThanOrEqual(RemoteLayoutPolicy.selectorHeight(compact: compact, isLandscape: landscape) + 8, 44)
            }
        }
    }

    // BUG-007: a key cancelled while the finger stays down (repeat cap, page change) must not
    // restart on that touch's next drag event; it may begin again after the finger lifts.
    func testCancelledKeyStaysStoppedUntilTheFingerLifts() {
        var gate = HeldTouchGate()
        XCTAssertTrue(gate.touched())
        gate.cancelled()
        XCTAssertFalse(gate.touched(), "the same touch keeps moving after the cap")
        XCTAssertFalse(gate.touched())
        gate.lifted()
        XCTAssertTrue(gate.touched(), "a new touch works")
    }

    func testCancellationAfterTheLiftDoesNotEatTheNextTap() {
        var gate = HeldTouchGate()
        XCTAssertTrue(gate.touched())
        gate.lifted()       // gesture state reset (lost end)
        gate.cancelled()    // the lost-end grace then cancels the key
        XCTAssertTrue(gate.touched())
    }

    func testRepeatKeyUsesTheGate() throws {
        let text = try source("GlassRemote/RepeatKey.swift")
        XCTAssertTrue(text.contains("guard box.gate.touched() else { return }"))
        XCTAssertTrue(text.contains("box.gate.cancelled()"))
        XCTAssertTrue(text.contains("box.gate.lifted()"))
    }
}
