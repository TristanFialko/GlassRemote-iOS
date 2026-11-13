import XCTest
@testable import GlassRemote

/// Regression tests for the Remote v2 final hardening: transport policy at the dispatch boundary,
/// volume exclusion under every link state, held-key pinning, and the TV-key pin record.
final class RemoteV2HardeningTests: XCTestCase {
    private let allFeatures = RemoteV2Features.requested

    private func availabilities() -> [RemoteTransportAvailability] {
        var out: [RemoteTransportAvailability] = []
        for v2Ready in [false, true] {
            for adbReady in [false, true] {
                for preferV2 in [false, true] {
                    for features in [RemoteV2Features(), [.key], allFeatures] {
                        out.append(RemoteTransportAvailability(v2Ready: v2Ready, v2Features: features,
                                                               adbReady: adbReady, preferV2: preferV2))
                    }
                }
            }
        }
        return out
    }

    func testPowerAndAppLaunchAreADBOnlyUnderEveryLinkState() {
        for operation in [RemoteOperation.power, .appLaunch] {
            XCTAssertEqual(operation.allowedTransports, [.adb], "\(operation)")
            XCTAssertNil(operation.requiredV2Feature, "\(operation)")
            for links in availabilities() {
                XCTAssertEqual(RemoteTransportPolicy.route(operation, links), links.adbReady ? RemoteTransportKind.adb : nil,
                               "\(operation) \(links)")
            }
        }
        XCTAssertNil(RemoteV2KeyMap.code(for: "POWER"))
        XCTAssertNil(RemoteV2KeyMap.operation(for: "POWER"))
        for code in RemoteV2KeyMap.adbOnlyCodes {
            XCTAssertNil(RemoteV2KeyMap.discreteOperation(forAndroidCode: Int(code)), "\(code)")
        }
    }

    func testVolumeAndMuteNeverRouteOverRemoteV2UnderAnyLinkState() {
        for links in availabilities() {
            XCTAssertNotEqual(RemoteTransportPolicy.route(.soundbarVolume, links), .remoteV2, "\(links)")
        }
        for key in ["VOLUME_UP", "VOLUME_DOWN", "MUTE", "VOLUME_MUTE", "24", "25", "164"] {
            XCTAssertNil(RemoteV2KeyMap.code(for: key), key)
            XCTAssertNil(RemoteV2KeyMap.operation(for: key), key)
        }
        for code in [24, 25, 164, 91] {
            XCTAssertNil(RemoteV2KeyMap.discreteOperation(forAndroidCode: code), "\(code)")
        }
        XCTAssertFalse(MediaRetryPolicy.mayRetryViaDispatch(originalTransport: .remoteV2))
    }

    func testOnlyNavigationAndMediaKeysExistOnRemoteV2() {
        let allowed: Set<Int32> = [19, 20, 21, 22, 23, 4, 3, 82, 85, 86, 87, 88, 89, 90, 126, 127]
        for (key, code) in RemoteV2KeyMap.codes {
            XCTAssertTrue(allowed.contains(code), "\(key) -> \(code)")
            XCTAssertFalse(RemoteV2KeyMap.forbidden.contains(code), key)
            XCTAssertFalse(RemoteV2KeyMap.adbOnlyCodes.contains(code), key)
        }
        for code in -1...400 {
            let expected = RemoteV2KeyMap.discreteMediaCodes.contains(Int32(code))
            XCTAssertEqual(RemoteV2KeyMap.discreteOperation(forAndroidCode: code) != nil, expected, "\(code)")
        }
    }

    func testRemoteV2OffKeepsEveryOperationOnADB() {
        let ops: [RemoteOperation] = [.dpad, .select, .back, .home, .menu, .media, .power, .appLaunch,
                                      .text, .mouse, .scroll, .appDiscovery, .diagnostics, .helpers,
                                      .soundbarVolume]
        let off = RemoteTransportAvailability(v2Ready: true, v2Features: allFeatures, adbReady: true, preferV2: false)
        for operation in ops {
            XCTAssertEqual(RemoteTransportPolicy.route(operation, off), .adb, "\(operation)")
        }
    }

    func testHeldKeyIsDroppedNotMovedWhenV2DropsMidHold() {
        var router = RemoteV2KeyGestureRouter()
        let up = RemoteTransportAvailability(v2Ready: true, v2Features: allFeatures, adbReady: true, preferV2: true)
        var down = up
        down.v2Ready = false
        let t0 = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(router.route("UP", operation: .dpad, links: up, now: t0), .remoteV2)
        XCTAssertEqual(router.route("UP", operation: .dpad, links: up, now: t0 + 0.1), .remoteV2)
        XCTAssertEqual(router.route("UP", operation: .dpad, links: down, now: t0 + 0.2), .droppedHold)
        XCTAssertEqual(router.route("UP", operation: .dpad, links: up, now: t0 + 0.3), .droppedHold,
                       "The rest of the hold stays dropped even if v2 returns")
        XCTAssertEqual(router.route("UP", operation: .dpad, links: down, now: t0 + 2), .adb,
                       "A fresh press after a pause may use ADB")
    }

    func testFingerprintIsStableDistinctAndUnambiguous() {
        let a = RemoteV2RSAPublicKey(modulus: [0x01, 0x02], exponent: [0x03])
        let b = RemoteV2RSAPublicKey(modulus: [0x01], exponent: [0x02, 0x03])
        XCTAssertEqual(a.fingerprint, RemoteV2RSAPublicKey(modulus: [0x00, 0x01, 0x02], exponent: [0x03]).fingerprint,
                       "Leading zero bytes do not change the key")
        XCTAssertNotEqual(a.fingerprint, b.fingerprint, "Length prefixes keep modulus/exponent boundaries")
        XCTAssertEqual(a.fingerprint.count, 64)
        XCTAssertTrue(a.fingerprint.allSatisfy { "0123456789abcdef".contains($0) })
    }

    func testPairingRecordNeedsAPinnedKeyAndForgetClearsIt() throws {
        let suite = "GlassRemoteTests.RemoteV2Record"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let tv = RemoteV2RSAPublicKey(modulus: [0xAB, 0xCD], exponent: [0x01, 0x00, 0x01])
        let other = RemoteV2RSAPublicKey(modulus: [0xAB, 0xCE], exponent: [0x01, 0x00, 0x01])

        defaults.set(["10.0.0.5"], forKey: RemoteV2PairingRecord.defaultsKey) // record from an earlier build
        XCTAssertFalse(RemoteV2PairingRecord.isPaired("10.0.0.5", defaults: defaults), "No pinned key, not paired")

        RemoteV2PairingRecord.markPaired("10.0.0.5", tvKey: tv, defaults: defaults)
        RemoteV2PairingRecord.markPaired("10.0.0.6", tvKey: other, defaults: defaults)
        XCTAssertTrue(RemoteV2PairingRecord.isPaired("10.0.0.5", defaults: defaults))
        XCTAssertEqual(RemoteV2PairingRecord.tvKeyFingerprint(for: "10.0.0.5", defaults: defaults), tv.fingerprint)

        RemoteV2PairingRecord.markPaired("10.0.0.5", tvKey: other, defaults: defaults) // pairing again
        XCTAssertEqual(RemoteV2PairingRecord.tvKeyFingerprint(for: "10.0.0.5", defaults: defaults), other.fingerprint)
        XCTAssertEqual(defaults.stringArray(forKey: RemoteV2PairingRecord.defaultsKey), ["10.0.0.5", "10.0.0.6"])

        RemoteV2PairingRecord.forget("10.0.0.5", defaults: defaults)
        XCTAssertFalse(RemoteV2PairingRecord.isPaired("10.0.0.5", defaults: defaults))
        XCTAssertNil(RemoteV2PairingRecord.tvKeyFingerprint(for: "10.0.0.5", defaults: defaults))
        XCTAssertTrue(RemoteV2PairingRecord.isPaired("10.0.0.6", defaults: defaults), "Other TVs are unaffected")
    }

    func testIdentityMismatchHasAnHonestStatus() {
        XCTAssertEqual(RemoteV2LinkState.identityMismatch.label, "Remote v2 blocked · TV identity changed, pair again")
    }
}
