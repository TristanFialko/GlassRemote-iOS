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

    // MARK: Discrete media keys (androidKey / sendMedia)

    func testOnlyMediaTransportCodesMayUseRemoteV2() {
        for code in [85, 86, 87, 88, 89, 90, 126, 127] {
            XCTAssertEqual(RemoteV2KeyMap.discreteOperation(forAndroidCode: code), .media, "code \(code)")
        }
        // Volume, mute, microphone mute, SLEEP/WAKEUP (standby and wake), POWER, keyboard-sheet keys.
        for code in [24, 25, 164, 91, 223, 224, 26, 66, 67, 61, 0, -1, Int.max] {
            XCTAssertNil(RemoteV2KeyMap.discreteOperation(forAndroidCode: code), "code \(code) must stay on ADB")
        }
    }

    func testDiscreteMediaRoutesToExactlyOneTransport() {
        XCTAssertEqual(RemoteTransportPolicy.route(.media, v2Up), .remoteV2)
        XCTAssertEqual(RemoteTransportPolicy.route(.media, v2Down), .adb)
        XCTAssertNil(RemoteTransportPolicy.route(.media, nothing))

        var noKeyFeature = v2Up
        noKeyFeature.v2Features = [.appLink]
        XCTAssertEqual(RemoteTransportPolicy.route(.media, noKeyFeature), .adb,
                       "Media needs the negotiated key feature; otherwise it stays on ADB")

        var disabled = v2Up
        disabled.preferV2 = false
        XCTAssertEqual(RemoteTransportPolicy.route(.media, disabled), .adb)
    }

    func testVolumeNeverRoutesOverRemoteV2() {
        XCTAssertEqual(RemoteOperation.soundbarVolume.allowedTransports, [.adb])
        XCTAssertEqual(RemoteTransportPolicy.route(.soundbarVolume, v2Up), .adb)
        for name in ["VOLUME_UP", "VOLUME_DOWN", "MUTE", "VOL_UP", "VOL_DOWN"] {
            XCTAssertNil(RemoteV2KeyMap.code(for: name))
            XCTAssertNil(RemoteV2KeyMap.operation(for: name))
        }
        XCTAssertTrue(RemoteV2KeyMap.codes.values.allSatisfy { !RemoteV2KeyMap.forbidden.contains($0) })
    }

    func testMediaSessionDispatchRetryOnlyAfterAnADBSend() {
        XCTAssertTrue(MediaRetryPolicy.mayRetryViaDispatch(originalTransport: .adb))
        XCTAssertFalse(MediaRetryPolicy.mayRetryViaDispatch(originalTransport: .remoteV2),
                       "A key handed to Remote v2 is never re-sent on ADB")
        XCTAssertFalse(MediaRetryPolicy.mayRetryViaDispatch(originalTransport: nil))
    }
}

/// Final pass §2: supported media keys over Remote v2 while ADB is down, with no duplicate send and no
/// ADB retry, and UI availability that follows transport readiness.
final class RemoteV2MediaWithoutADBTests: XCTestCase {
    private let v2Only = RemoteTransportAvailability(v2Ready: true, v2Features: [.key], adbReady: false, preferV2: true)
    private let both = RemoteTransportAvailability(v2Ready: true, v2Features: [.key], adbReady: true, preferV2: true)
    private let adbOnly = RemoteTransportAvailability(v2Ready: false, v2Features: [], adbReady: true, preferV2: true)
    private let neither = RemoteTransportAvailability(v2Ready: false, v2Features: [], adbReady: false, preferV2: true)
    private let commands: [MediaCommand] = [.play, .pause, .playPause, .next, .previous, .rewind, .fastForward]
    private let forbiddenCodes = [24, 25, 164, 91, 26, 223, 224]

    private func everyLinkState() -> [RemoteTransportAvailability] {
        var out: [RemoteTransportAvailability] = []
        for v2Ready in [false, true] {
            for adbReady in [false, true] {
                for preferV2 in [false, true] {
                    for features in [RemoteV2Features(), [.key], RemoteV2Features.requested] {
                        out.append(RemoteTransportAvailability(v2Ready: v2Ready, v2Features: features,
                                                               adbReady: adbReady, preferV2: preferV2))
                    }
                }
            }
        }
        return out
    }

    func testV2ReadyADBDownSendsExactlyOnceOverV2AndReportsUnconfirmed() {
        for command in commands {
            let plan = MediaCommandPlan.make(command, links: v2Only)
            XCTAssertEqual(plan.transport, .remoteV2, "\(command)")
            XCTAssertEqual(plan.verification, .unconfirmed, "\(command)")
            XCTAssertFalse(plan.mayRetryViaDispatch, "\(command)")
        }
        XCTAssertEqual(MediaControlMode.resolve(v2Only), .remoteV2Only)
        let note = MediaFailureReport.sentUnconfirmed(.pause, via: .remoteV2, at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(note.text, "Pause sent over Remote v2 · not confirmed")
    }

    func testNeitherTransportSendsNothingAndReportsUnavailable() {
        for command in commands {
            let plan = MediaCommandPlan.make(command, links: neither)
            XCTAssertNil(plan.transport, "\(command)")
            XCTAssertEqual(plan.verification, .unavailable)
            XCTAssertFalse(plan.mayRetryViaDispatch)
        }
        XCTAssertEqual(MediaControlMode.resolve(neither), .unavailable)
        XCTAssertEqual(MediaCommandPlan.verification(carrier: nil, sessionReadable: true), .unavailable)

        var noKeyFeature = v2Only
        noKeyFeature.v2Features = [.appLink]
        XCTAssertNil(MediaCommandPlan.make(.play, links: noKeyFeature).transport, "v2 without the key feature cannot carry media")
        XCTAssertEqual(MediaControlMode.resolve(noKeyFeature), .unavailable)

        var disabled = v2Only
        disabled.preferV2 = false
        XCTAssertNil(MediaCommandPlan.make(.play, links: disabled).transport, "Remote v2 off + ADB down: nothing sent, as before")
        XCTAssertEqual(MediaControlMode.resolve(disabled), .unavailable)
    }

    func testV2SendWithoutADBNeverGetsTheMediaSessionDispatchRetry() {
        for command in [MediaCommand.play, .pause] {
            XCTAssertNotNil(command.dispatchName, "play / pause are the only commands with a dispatch retry")
            XCTAssertFalse(MediaCommandPlan.make(command, links: v2Only).mayRetryViaDispatch)
        }
        XCTAssertFalse(MediaRetryPolicy.mayRetryViaDispatch(originalTransport: .remoteV2))
        // ADB dropping while a v2 key is in flight: reported unconfirmed, never "not accepted", never retried.
        XCTAssertEqual(MediaCommandPlan.verification(carrier: .remoteV2, sessionReadable: false), .unconfirmed)
    }

    func testV2SendWithADBUpKeepsVerificationWithoutCrossTransportRetry() {
        for command in commands {
            let plan = MediaCommandPlan.make(command, links: both)
            XCTAssertEqual(plan.transport, .remoteV2, "\(command)")
            XCTAssertEqual(plan.verification, .readSession, "\(command): the ADB session still checks the result")
            XCTAssertFalse(plan.mayRetryViaDispatch, "\(command): a v2 key is never re-sent on ADB")
        }
        XCTAssertEqual(MediaControlMode.resolve(both), .session)
        XCTAssertEqual(MediaCommandPlan.verification(carrier: .remoteV2, sessionReadable: true), .readSession)
    }

    func testRemoteV2OffLeavesTheADBPathUnchanged() {
        for v2Ready in [false, true] {
            let links = RemoteTransportAvailability(v2Ready: v2Ready, v2Features: [.key], adbReady: true, preferV2: false)
            for command in commands {
                let plan = MediaCommandPlan.make(command, links: links)
                XCTAssertEqual(plan.transport, .adb, "\(command)")
                XCTAssertEqual(plan.verification, .readSession)
                XCTAssertEqual(plan.mayRetryViaDispatch, command.dispatchName != nil, "\(command)")
            }
            XCTAssertEqual(MediaControlMode.resolve(links), .session)
        }
        XCTAssertEqual(MediaCommandPlan.make(.pause, links: adbOnly).transport, .adb)
        XCTAssertTrue(MediaCommandPlan.make(.pause, links: adbOnly).mayRetryViaDispatch)
        XCTAssertEqual(MediaCommandPlan.verification(carrier: .adb, sessionReadable: true), .readSession)
    }

    func testUIAvailabilityFollowsTransportReadinessUnderEveryLinkState() {
        for links in everyLinkState() {
            let mode = MediaControlMode.resolve(links)
            let routable = RemoteTransportPolicy.route(.media, links) != nil
            XCTAssertEqual(mode != .unavailable, routable, "\(links)")
            for command in commands {
                XCTAssertEqual(MediaCommandPlan.make(command, links: links).transport != nil, mode != .unavailable,
                               "\(command) \(links)")
            }
            if mode == .remoteV2Only {
                XCTAssertFalse(links.adbReady)
                XCTAssertEqual(RemoteTransportPolicy.route(.media, links), .remoteV2)
            }
            if mode == .session { XCTAssertTrue(links.adbReady) }
        }
    }

    func testForbiddenCodesNeverGetAMediaSendUnderAnyLinkState() {
        for links in everyLinkState() {
            for code in forbiddenCodes {
                let plan = MediaCommandPlan.make(keycode: code, hasDispatchRetry: true, links: links)
                XCTAssertNil(plan.transport, "\(code) \(links)")
                XCTAssertFalse(plan.mayRetryViaDispatch, "\(code) \(links)")
                XCTAssertNil(RemoteV2KeyMap.discreteOperation(forAndroidCode: code), "\(code)")
            }
        }
        for command in commands {
            XCTAssertFalse(forbiddenCodes.contains(command.keycode), "\(command)")
            XCTAssertTrue(RemoteV2KeyMap.discreteMediaCodes.contains(Int32(command.keycode)), "\(command)")
        }
        XCTAssertEqual(MediaCommand.playPause.keycode, 85)
        XCTAssertNil(MediaCommand.playPause.dispatchName, "the toggle has no dispatch retry")
        XCTAssertNil(MediaCommand.playPause.satisfied(by: .idle), "the toggle has no checkable result")
        XCTAssertEqual(MediaCommand.playPause.displayName, "Play/Pause")
    }
}
