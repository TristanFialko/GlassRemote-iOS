import XCTest
@testable import GlassRemote

/// Phase 9 gap fix: volume must reach the soundbar, not the TV's built-in speakers.
///
/// What these prove: the route decision and the evidence rule (pure logic). What they cannot prove:
/// that a given TV forwards its volume keys to a given soundbar, or what its UPnP level addresses.
/// That needs the real TV and soundbar.
final class Phase9SoundbarVolumeTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    // MARK: Route

    func testAnUnverifiedUPnPLevelIsNeverTheSliderRoute() {
        // The regression: UPnP answered, so the slider set the TV's own level while the soundbar played.
        XCTAssertEqual(VolumeRoutePolicy.route(enabled: true, remoteReady: true, upnpReady: true,
                                               output: .automatic, evidence: .unknown), .keys)
        XCTAssertEqual(VolumeRoutePolicy.route(enabled: true, remoteReady: true, upnpReady: true,
                                               output: .automatic, evidence: .ignoresKeys), .keys)
        // No paired remote and no proof about UPnP: nothing is sent.
        XCTAssertEqual(VolumeRoutePolicy.route(enabled: true, remoteReady: false, upnpReady: true,
                                               output: .automatic, evidence: .unknown), .unavailable)
        XCTAssertEqual(VolumeRoutePolicy.route(enabled: true, remoteReady: false, upnpReady: true,
                                               output: .automatic, evidence: .ignoresKeys), .unavailable)
    }

    func testAbsoluteVolumeOnlyWhenUPnPAddressesThePlayingOutput() {
        XCTAssertEqual(VolumeRoutePolicy.route(enabled: true, remoteReady: true, upnpReady: true,
                                               output: .automatic, evidence: .tracksKeys), .absolute)
        XCTAssertEqual(VolumeRoutePolicy.route(enabled: true, remoteReady: false, upnpReady: true,
                                               output: .automatic, evidence: .tracksKeys), .absolute)
        XCTAssertEqual(VolumeRoutePolicy.route(enabled: true, remoteReady: true, upnpReady: false,
                                               output: .automatic, evidence: .tracksKeys), .keys, "the link is down: keys")
        for evidence in [VolumeOutputEvidence.unknown, .tracksKeys, .ignoresKeys] {
            XCTAssertEqual(VolumeRoutePolicy.route(enabled: true, remoteReady: true, upnpReady: true,
                                                   output: .tvSpeakers, evidence: evidence), .absolute, "the user said TV speakers")
            XCTAssertEqual(VolumeRoutePolicy.route(enabled: true, remoteReady: true, upnpReady: true,
                                                   output: .external, evidence: evidence), .keys, "the user said soundbar")
            XCTAssertEqual(VolumeRoutePolicy.route(enabled: true, remoteReady: false, upnpReady: true,
                                                   output: .external, evidence: evidence), .unavailable,
                           "a soundbar is never driven through the TV's own level")
        }
    }

    func testSamsungOffSendsNothing() {
        for output in SamsungAudioOutput.allCases {
            for evidence in [VolumeOutputEvidence.unknown, .tracksKeys, .ignoresKeys] {
                for remote in [false, true] {
                    for upnp in [false, true] {
                        XCTAssertEqual(VolumeRoutePolicy.route(enabled: false, remoteReady: remote, upnpReady: upnp,
                                                               output: output, evidence: evidence), .unavailable)
                    }
                }
            }
        }
    }

    func testTheSummaryNamesTheRouteInUse() {
        let keys = VolumeRoutePolicy.summary(route: .keys, output: .automatic, evidence: .ignoresKeys, upnpReady: true)
        XCTAssertTrue(keys.contains("remote keys"))
        XCTAssertTrue(keys.contains("soundbar"))
        let unavailable = VolumeRoutePolicy.summary(route: .unavailable, output: .automatic, evidence: .unknown, upnpReady: true)
        XCTAssertTrue(unavailable.contains("unavailable"))
        XCTAssertFalse(unavailable.lowercased().contains("android"))
    }

    // MARK: Evidence

    func testKeysThatMoveTheUPnPLevelProveItIsThePlayingOutput() {
        var probe = VolumeOutputProbe()
        probe.keySent(direction: 1, lastReading: 20, at: t0)
        XCTAssertNil(probe.reading(21, at: t0.addingTimeInterval(0.3)), "too soon: the TV has not settled")
        XCTAssertEqual(probe.reading(21, at: t0.addingTimeInterval(1.2)), .tracksKeys)
        XCTAssertFalse(probe.isCollecting)

        probe.keySent(direction: -1, lastReading: 21, at: t0)
        probe.keySent(direction: -1, lastReading: 21, at: t0.addingTimeInterval(0.1))
        XCTAssertEqual(probe.reading(19, at: t0.addingTimeInterval(1.5)), .tracksKeys)
    }

    func testKeysThatLeaveTheUPnPLevelAloneRuleItOutOnlyAfterSeveralPresses() {
        var probe = VolumeOutputProbe()
        probe.keySent(direction: 1, lastReading: 20, at: t0)
        XCTAssertNil(probe.reading(20, at: t0.addingTimeInterval(1.2)), "one press could have been lost")
        XCTAssertTrue(probe.isCollecting)
        probe.keySent(direction: 1, lastReading: 20, at: t0.addingTimeInterval(2))
        XCTAssertNil(probe.reading(20, at: t0.addingTimeInterval(3.2)))
        probe.keySent(direction: 1, lastReading: 20, at: t0.addingTimeInterval(4))
        XCTAssertEqual(probe.reading(20, at: t0.addingTimeInterval(5.2)), .ignoresKeys,
                       "three presses up, the TV's own level never moved: a soundbar took them")
    }

    func testInconclusiveSamplesTeachNothing() {
        // No UPnP reading before the key: nothing to compare with.
        var probe = VolumeOutputProbe()
        probe.keySent(direction: 1, lastReading: nil, at: t0)
        XCTAssertFalse(probe.isCollecting)
        XCTAssertNil(probe.reading(30, at: t0.addingTimeInterval(2)))

        // Already at the top: the level could not have risen.
        probe.keySent(direction: 1, lastReading: 100, at: t0)
        probe.keySent(direction: 1, lastReading: 100, at: t0)
        probe.keySent(direction: 1, lastReading: 100, at: t0)
        XCTAssertNil(probe.reading(100, at: t0.addingTimeInterval(1.5)))
        XCTAssertFalse(probe.isCollecting)

        // At the bottom, pressing down.
        for _ in 0..<4 { probe.keySent(direction: -1, lastReading: 0, at: t0) }
        XCTAssertNil(probe.reading(0, at: t0.addingTimeInterval(1.5)))

        // Presses that cancel out.
        probe.keySent(direction: 1, lastReading: 40, at: t0)
        probe.keySent(direction: -1, lastReading: 40, at: t0)
        XCTAssertNil(probe.reading(40, at: t0.addingTimeInterval(1.5)))
        XCTAssertFalse(probe.isCollecting)

        // The level moved against the keys: something else changed it.
        for _ in 0..<3 { probe.keySent(direction: 1, lastReading: 40, at: t0) }
        XCTAssertNil(probe.reading(35, at: t0.addingTimeInterval(1.5)))

        // A reading long after the keys says nothing about them.
        for _ in 0..<3 { probe.keySent(direction: 1, lastReading: 40, at: t0) }
        XCTAssertNil(probe.reading(40, at: t0.addingTimeInterval(VolumeOutputProbe.window + 5)))
        XCTAssertFalse(probe.isCollecting)
    }

    func testAResetVoidsTheSample() {
        var probe = VolumeOutputProbe()
        for _ in 0..<3 { probe.keySent(direction: 1, lastReading: 40, at: t0) }
        probe.reset()   // e.g. a UPnP set moved the level by itself
        XCTAssertNil(probe.reading(60, at: t0.addingTimeInterval(1.5)))
    }

    func testOldKeysAreForgottenBeforeNewOnesAreCounted() {
        var probe = VolumeOutputProbe()
        probe.keySent(direction: 1, lastReading: 40, at: t0)
        probe.keySent(direction: 1, lastReading: 40, at: t0)
        let later = t0.addingTimeInterval(VolumeOutputProbe.window + 10)
        probe.keySent(direction: 1, lastReading: 55, at: later)
        XCTAssertNil(probe.reading(55, at: later.addingTimeInterval(1.5)), "one fresh press, not three")
        XCTAssertEqual(probe.reading(56, at: later.addingTimeInterval(2)), .tracksKeys)
    }

    // MARK: Per-TV memory

    func testEvidenceIsRememberedPerTV() throws {
        let name = "Phase9SoundbarVolumeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(VolumeOutputEvidenceStore.load(host: "192.168.1.20", defaults: defaults), .unknown)
        VolumeOutputEvidenceStore.save(.ignoresKeys, host: " 192.168.1.20 ", defaults: defaults)
        XCTAssertEqual(VolumeOutputEvidenceStore.load(host: "192.168.1.20", defaults: defaults), .ignoresKeys)
        XCTAssertEqual(VolumeOutputEvidenceStore.load(host: "192.168.1.99", defaults: defaults), .unknown, "another TV starts over")
        XCTAssertEqual(VolumeOutputEvidenceStore.load(host: "", defaults: defaults), .unknown)
    }

    // MARK: Source guards

    private func source(_ file: String) throws -> String {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard let text = try? String(contentsOf: repo.appendingPathComponent(file), encoding: .utf8) else {
            throw XCTSkip("app sources are not readable from the test run")
        }
        return text
    }

    func testTheSliderNoLongerUsesUPnPJustBecauseItAnswered() throws {
        let features = try source("GlassRemote/RemoteModel+Features.swift")
        XCTAssertFalse(features.contains("if tvVolumeEnabled, volumeLinkReady { return .samsungAbsolute"),
                       "UPnP answering is not proof that it is the playing output")
        XCTAssertFalse(features.contains("if tvVolumeEnabled, volumeLinkReady {\n            let raw"))
        XCTAssertTrue(features.contains("if volumeCommandRoute == .absolute {"))
        XCTAssertTrue(features.contains("volumeOutputProbe.keySent("))
        XCTAssertFalse(features.contains("input keyevent 24"), "no Android volume key")
        XCTAssertFalse(features.contains("input keyevent 25"), "no Android volume key")
    }
}
