import XCTest
@testable import GlassRemote

/// Held-key pinning on top of RemoteTransportPolicy.
final class RemoteV2KeyRoutingTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let v2Up = RemoteTransportAvailability(v2Ready: true, v2Features: [.key, .appLink], adbReady: true, preferV2: true)
    private let v2Down = RemoteTransportAvailability(v2Ready: false, v2Features: [], adbReady: true, preferV2: true)
    private let nothing = RemoteTransportAvailability(v2Ready: false, v2Features: [], adbReady: false, preferV2: true)

    func testHoldStartedOnV2IsDroppedNotMovedWhenV2Fails() {
        var router = RemoteV2KeyGestureRouter()
        XCTAssertEqual(router.route("UP", operation: .dpad, links: v2Up, now: t0), .remoteV2)
        XCTAssertEqual(router.route("UP", operation: .dpad, links: v2Up, now: t0 + 0.1), .remoteV2)
        XCTAssertEqual(router.route("UP", operation: .dpad, links: v2Down, now: t0 + 0.2), .droppedHold)
        XCTAssertEqual(router.route("UP", operation: .dpad, links: v2Down, now: t0 + 0.3), .droppedHold,
                       "The rest of the hold stays dropped even though ADB is ready")
        XCTAssertEqual(router.route("UP", operation: .dpad, links: v2Down, now: t0 + 1.5), .adb,
                       "A new press after a pause takes the available transport")
    }

    func testHoldStartedOnADBStaysOnADBWhenV2Appears() {
        var router = RemoteV2KeyGestureRouter()
        XCTAssertEqual(router.route("LEFT", operation: .dpad, links: v2Down, now: t0), .adb)
        XCTAssertEqual(router.route("LEFT", operation: .dpad, links: v2Up, now: t0 + 0.15), .adb)
        XCTAssertEqual(router.route("LEFT", operation: .dpad, links: v2Up, now: t0 + 1), .remoteV2)
    }

    func testTransportLossDropsTheHeldKeysOfThatTransport() {
        var router = RemoteV2KeyGestureRouter()
        XCTAssertEqual(router.route("RIGHT", operation: .dpad, links: v2Up, now: t0), .remoteV2)
        router.transportLost(.remoteV2)
        XCTAssertEqual(router.route("RIGHT", operation: .dpad, links: v2Up, now: t0 + 0.1), .droppedHold)
        XCTAssertTrue(router.ledger.heldKeys.isEmpty)
    }

    func testDifferentKeysAreIndependentAndNothingReadyIsUnavailable() {
        var router = RemoteV2KeyGestureRouter()
        XCTAssertEqual(router.route("UP", operation: .dpad, links: v2Up, now: t0), .remoteV2)
        XCTAssertEqual(router.route("BACK", operation: .back, links: v2Down, now: t0 + 0.05), .adb)
        XCTAssertEqual(router.route("OK", operation: .select, links: nothing, now: t0 + 0.1), .unavailable)
    }

    func testPreferV2OffKeepsEverythingOnADB() {
        var router = RemoteV2KeyGestureRouter()
        var links = v2Up
        links.preferV2 = false
        XCTAssertEqual(router.route("HOME", operation: .home, links: links, now: t0), .adb)
    }

    func testCancelAllForgetsGestures() {
        var router = RemoteV2KeyGestureRouter()
        _ = router.route("UP", operation: .dpad, links: v2Up, now: t0)
        router.cancelAll()
        XCTAssertFalse(router.ledger.hasHeldKeys)
        XCTAssertEqual(router.route("UP", operation: .dpad, links: v2Down, now: t0 + 0.1), .adb)
    }
}
