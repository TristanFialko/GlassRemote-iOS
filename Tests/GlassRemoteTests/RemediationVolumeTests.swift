import XCTest
@testable import GlassRemote

/// Audit remediation, Priority A (volume correctness and safety). Logic only: these prove which
/// commands are planned and which route is chosen, not which speakers move. Hardware still required.
final class RemediationVolumeTests: XCTestCase {

    // MARK: BUG-003: no silent output fallback

    func testNoOutputEverFallsBackToAnotherRoute() {
        for box in [false, true] {
            for samsung in [false, true] {
                for remote in [false, true] {
                    for upnp in [false, true] {
                        let tv = VolumeRoutePolicy.route(output: .tvSpeakers, boxConnected: box, samsungEnabled: samsung,
                                                         remoteReady: remote, upnpReady: upnp)
                        XCTAssertTrue(tv == .absolute || tv == .unavailable, "TV speakers used \(tv)")
                        let soundbarTV = VolumeRoutePolicy.route(output: .soundbarViaTV, boxConnected: box, samsungEnabled: samsung,
                                                                 remoteReady: remote, upnpReady: upnp)
                        XCTAssertTrue(soundbarTV == .tvKeys || soundbarTV == .unavailable)
                        let soundbarBox = VolumeRoutePolicy.route(output: .soundbarViaBox, boxConnected: box, samsungEnabled: samsung,
                                                                  remoteReady: remote, upnpReady: upnp)
                        XCTAssertEqual(soundbarBox, box ? .boxKeys : .unavailable)
                    }
                }
            }
        }
    }

    func testTVSpeakersUnavailableReasonSaysWhichLinkIsDown() {
        XCTAssertEqual(VolumeRoutePolicy.unavailableReason(output: .tvSpeakers, samsungEnabled: false), "Samsung TV is off")
        XCTAssertEqual(VolumeRoutePolicy.unavailableReason(output: .tvSpeakers, samsungEnabled: true, remoteReady: true),
                       "TV volume link not answering")
        XCTAssertEqual(VolumeRoutePolicy.unavailableReason(output: .tvSpeakers, samsungEnabled: true, remoteReady: false),
                       "Samsung TV not connected")
        XCTAssertEqual(VolumeRoutePolicy.unavailableReason(output: .soundbarViaTV, samsungEnabled: true), "Samsung TV not connected")
    }

    // MARK: UX-003: every row names its output

    func testEveryOutputHasADistinctShortLabel() {
        let labels = VolumeOutput.allCases.map(\.shortLabel)
        XCTAssertEqual(Set(labels).count, labels.count)
        XCTAssertTrue(VolumeOutput.soundbarViaBox.shortLabel.contains("box"))
        XCTAssertTrue(labels.allSatisfy { !$0.isEmpty && $0.count <= 16 }, "fits the row")
    }

    // MARK: UX-002: an estimate never looks measured

    func testOnlyKeyRoutesAreEstimates() {
        XCTAssertTrue(VolumeRowReadout.resolve(scale: .boxKeys(max: 20), fraction: 0.4, reason: nil).isEstimate)
        XCTAssertTrue(VolumeRowReadout.resolve(scale: .samsungKeys(max: 60), fraction: 0.4, reason: nil).isEstimate)
        XCTAssertFalse(VolumeRowReadout.resolve(scale: .samsungAbsolute(.standard), fraction: 0.4, reason: nil).isEstimate)
        XCTAssertFalse(VolumeRowReadout.resolve(scale: .unavailable, fraction: 0.4, reason: "Connect the TV box").isEstimate)
    }

    // MARK: UX-008: bounded key bursts

    func testGoingUpFromAnUnknownPositionNeverFiresAFullSweep() {
        // Thumb at 50 % of a 100-level soundbar, dragged to the top: only the visible distance.
        let plan = VolumeStepPlan.plan(target: 100, assumed: 50, levels: 100, levelKnown: false)
        XCTAssertEqual(plan.delta, 50)
        XCTAssertFalse(plan.levelKnown, "the top is not a known level until the soundbar confirms it")
        // Box route, small nudge to the top from 90 %.
        XCTAssertEqual(VolumeStepPlan.plan(target: 20, assumed: 18, levels: 20, levelKnown: false).delta, 2)
    }

    func testReachingZeroFromUnknownPressesTheFullRangeDownOnce() {
        let plan = VolumeStepPlan.plan(target: 0, assumed: 10, levels: 20, levelKnown: false)
        XCTAssertEqual(plan.delta, -20, "the soundbar clamps at its minimum, so the estimate becomes exact")
        XCTAssertTrue(plan.levelKnown)
        // Once known, the bottom is an exact press count.
        XCTAssertEqual(VolumeStepPlan.plan(target: 0, assumed: 3, levels: 20, levelKnown: true).delta, -3)
    }

    func testDeltasAndPendingPressesAreBoundedByOneRange() {
        XCTAssertEqual(VolumeStepPlan.plan(target: 500, assumed: -400, levels: 20, levelKnown: true).delta, 20)
        XCTAssertEqual(VolumeStepPlan.clampPending(75, levels: 20), 20)
        XCTAssertEqual(VolumeStepPlan.clampPending(-75, levels: 20), -20)
        XCTAssertEqual(VolumeStepPlan.clampPending(7, levels: 20), 7)
    }

    func testTheEstimateStartsWhereTheThumbIs() {
        XCTAssertEqual(VolumeStepPlan.seed(fraction: 0.9, levels: 20), 18)
        XCTAssertEqual(VolumeStepPlan.seed(fraction: 0, levels: 20), 0)
        XCTAssertEqual(VolumeStepPlan.seed(fraction: 2, levels: 20), 20)
    }

    // MARK: BUG-002: reset only on a real route change

    func testUnrelatedObservationsKeepTheAssumedPosition() {
        XCTAssertFalse(VolumeStatePolicy.shouldReset(stateRoute: .boxKeys, currentRoute: .boxKeys))
        XCTAssertTrue(VolumeStatePolicy.shouldReset(stateRoute: .boxKeys, currentRoute: .unavailable))
        XCTAssertTrue(VolumeStatePolicy.shouldReset(stateRoute: .tvKeys, currentRoute: .boxKeys))
        XCTAssertTrue(VolumeStatePolicy.shouldReset(stateRoute: nil, currentRoute: .boxKeys))
    }

    // MARK: BUG-005: no built-in Samsung address

    func testAFreshInstallHasNoSamsungAddressAndTheLinkIsOff() {
        let host = SamsungHostDefaults.restoredHost(saved: nil, tokenHost: nil)
        XCTAssertEqual(host, "")
        XCTAssertFalse(SamsungHostDefaults.restoredLinkEnabled(stored: nil, host: host))
    }

    func testAnExistingInstallKeepsOrRecoversItsTV() {
        XCTAssertEqual(SamsungHostDefaults.restoredHost(saved: " 10.0.0.5 ", tokenHost: "10.0.0.9"), "10.0.0.5")
        XCTAssertEqual(SamsungHostDefaults.restoredHost(saved: "", tokenHost: "10.0.0.9"), "10.0.0.9",
                       "the TV that issued the pairing token")
        XCTAssertTrue(SamsungHostDefaults.restoredLinkEnabled(stored: nil, host: "10.0.0.9"))
        XCTAssertFalse(SamsungHostDefaults.restoredLinkEnabled(stored: false, host: "10.0.0.9"), "user's choice kept")
        XCTAssertTrue(SamsungHostDefaults.restoredLinkEnabled(stored: true, host: ""), "user's choice kept")
    }

    /// BUG-005 is about the Samsung TV only: its address and link come from SamsungHostDefaults, never
    /// a literal. (The Android TV box's own saved-host default is a separate, pre-existing setting.)
    func testNoSamsungAddressIsHardCodedInTheModel() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("GlassRemote/RemoteModel.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.contains("defaultSamsungHost"))
        guard let start = text.range(of: "@Published var samsungHost"),
              let end = text.range(of: "samsungHostChangeTask", range: start.upperBound..<text.endIndex) else {
            return XCTFail("samsungHost declaration not found")
        }
        let declaration = text[start.lowerBound..<end.lowerBound]
        XCTAssertTrue(declaration.contains("SamsungHostDefaults.restoredHost("))
        XCTAssertNil(declaration.range(of: #""\d+\.\d+\.\d+\.\d+""#, options: .regularExpression))
    }

    // MARK: BUG-001: one shared slider position

    @MainActor
    func testBothRowsShareOneSliderPosition() throws {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: VolumeOutput.defaultsKey)
        defer {
            if let saved { defaults.set(saved, forKey: VolumeOutput.defaultsKey) } else { defaults.removeObject(forKey: VolumeOutput.defaultsKey) }
        }
        let remote = RemoteModel()
        remote.userMovedVolumeSlider(to: 0.9)
        XCTAssertEqual(remote.volumeSliderFraction, 0.9, accuracy: 0.0001,
                       "the Now Playing row reads the same value the Remote row set")
        remote.userMovedVolumeSlider(to: 1.7)
        XCTAssertEqual(remote.volumeSliderFraction, 1, accuracy: 0.0001)
    }

    func testViewsBindToTheSharedSliderNotTheirOwnState() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for file in ["GlassRemote/RemoteView.swift", "GlassRemote/PlayerPage.swift"] {
            let text = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            XCTAssertTrue(text.contains("remote.userMovedVolumeSlider(to: $0)"), file)
            XCTAssertTrue(text.contains("outputLabel: remote.volumeOutputLabel"), file)
        }
    }
}
