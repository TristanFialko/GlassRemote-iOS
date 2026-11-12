import XCTest
@testable import GlassRemote

/// Restores the Phase 7.2 soundbar route (VolumeOutput.swift). Logic only: these tests prove which
/// command each control sends, not which speakers move. Only the real TV box, TV and soundbar can.
final class VolumeRouteRestoreTests: XCTestCase {

    // MARK: Output setting

    func testTheBoxRouteIsTheDefaultAndPhase9SettingsAreNotCarriedOver() {
        XCTAssertEqual(VolumeOutput.default, .soundbarViaBox)
        // The Phase 9 "Sound comes from" values only chose among Samsung routes.
        for old in [nil, "", "automatic", "external", "garbage"] {
            XCTAssertEqual(VolumeOutput.restored(from: old), .soundbarViaBox, old ?? "nil")
        }
        for output in VolumeOutput.allCases {
            XCTAssertEqual(VolumeOutput.restored(from: output.rawValue), output)
        }
        XCTAssertNotEqual(VolumeOutput.defaultsKey, "glassRemote.samsungAudioOutput")
        XCTAssertFalse(VolumeOutput.soundbarViaBox.usesSamsung)
        XCTAssertTrue(VolumeOutput.soundbarViaTV.usesSamsung)
        XCTAssertTrue(VolumeOutput.tvSpeakers.usesSamsung)
    }

    // MARK: Route selection

    func testTheSoundbarRouteUsesTheBoxWheneverItIsConnected() {
        for samsung in [false, true] {
            for remote in [false, true] {
                for upnp in [false, true] {
                    let label = "samsung \(samsung) remote \(remote) upnp \(upnp)"
                    XCTAssertEqual(VolumeRoutePolicy.route(output: .soundbarViaBox, boxConnected: true, samsungEnabled: samsung,
                                                           remoteReady: remote, upnpReady: upnp), .boxKeys, label)
                }
            }
        }
    }

    /// The regression: with the box down, the old code moved the TV's own speakers instead.
    func testABoxThatIsDownNeverFallsBackToTheTVsSpeakers() {
        for remote in [false, true] {
            for upnp in [false, true] {
                XCTAssertEqual(VolumeRoutePolicy.route(output: .soundbarViaBox, boxConnected: false, samsungEnabled: true,
                                                       remoteReady: remote, upnpReady: upnp), .unavailable,
                               "remote \(remote) upnp \(upnp)")
            }
        }
    }

    func testTheSamsungKeyRouteNeverUsesTheTVsOwnLevel() {
        XCTAssertEqual(VolumeRoutePolicy.route(output: .soundbarViaTV, boxConnected: true, samsungEnabled: true,
                                               remoteReady: true, upnpReady: true), .tvKeys)
        XCTAssertEqual(VolumeRoutePolicy.route(output: .soundbarViaTV, boxConnected: true, samsungEnabled: true,
                                               remoteReady: false, upnpReady: true), .unavailable,
                       "UPnP answering is not a soundbar route")
        XCTAssertEqual(VolumeRoutePolicy.route(output: .soundbarViaTV, boxConnected: true, samsungEnabled: false,
                                               remoteReady: true, upnpReady: true), .unavailable)
    }

    func testTVSpeakersUseTheExactLevelThenTheTVsKeys() {
        XCTAssertEqual(VolumeRoutePolicy.route(output: .tvSpeakers, boxConnected: false, samsungEnabled: true,
                                               remoteReady: true, upnpReady: true), .absolute)
        XCTAssertEqual(VolumeRoutePolicy.route(output: .tvSpeakers, boxConnected: true, samsungEnabled: true,
                                               remoteReady: true, upnpReady: false), .tvKeys)
        XCTAssertEqual(VolumeRoutePolicy.route(output: .tvSpeakers, boxConnected: true, samsungEnabled: true,
                                               remoteReady: false, upnpReady: false), .unavailable,
                       "never the box for TV speakers")
        XCTAssertEqual(VolumeRoutePolicy.route(output: .tvSpeakers, boxConnected: true, samsungEnabled: false,
                                               remoteReady: true, upnpReady: true), .unavailable)
    }

    // MARK: Commands

    func testBoxButtonsSendPhase72sAndroidKeycodes() {
        XCTAssertEqual(VolumeButtonPolicy.route(for: "VOLUME_UP", command: .boxKeys), .boxKey("24"))
        XCTAssertEqual(VolumeButtonPolicy.route(for: "VOLUME_DOWN", command: .boxKeys), .boxKey("25"))
        XCTAssertEqual(VolumeButtonPolicy.route(for: "MUTE", command: .boxKeys), .boxKey("164"))
    }

    func testEveryOtherRouteSendsItsOwnCommandOnly() {
        for name in VolumeKeyPolicy.keys {
            XCTAssertEqual(VolumeButtonPolicy.route(for: name, command: .tvKeys), .samsungKey(name))
            XCTAssertEqual(VolumeButtonPolicy.route(for: name, command: .unavailable), .unavailable)
        }
        XCTAssertEqual(VolumeButtonPolicy.route(for: "VOLUME_UP", command: .absolute), .upnpStep(1))
        XCTAssertEqual(VolumeButtonPolicy.route(for: "VOLUME_DOWN", command: .absolute), .upnpStep(-1))
        XCTAssertEqual(VolumeButtonPolicy.route(for: "MUTE", command: .absolute), .upnpMuteToggle)
        for route in [VolumeCommandRoute.boxKeys, .tvKeys, .absolute] {
            for other in ["UP", "OK", "HOME", "POWER", ""] {
                XCTAssertEqual(VolumeButtonPolicy.route(for: other, command: route), .unavailable, "\(route) \(other)")
            }
        }
    }

    // MARK: Slider scale

    func testKeyRoutesAreRelativeAndShowNoLevel() {
        let box = VolumeScale.boxKeys(max: VolumeRoutePolicy.boxSteps)
        XCTAssertEqual(box.route, .boxKeys)
        XCTAssertEqual(box.steps, 20, "Phase 7.2 spanned 20 box key presses")
        XCTAssertTrue(box.isAvailable)
        XCTAssertFalse(box.readsLevel)
        XCTAssertFalse(VolumeScale.samsungKeys(max: 60).readsLevel)
        XCTAssertFalse(VolumeScale.unavailable.readsLevel)
        XCTAssertTrue(VolumeScale.samsungAbsolute(.standard).readsLevel)
    }

    func testTheSummaryAndReasonNameTheRoute() {
        XCTAssertTrue(VolumeRoutePolicy.summary(route: .boxKeys, output: .soundbarViaBox, samsungEnabled: true).contains("TV box"))
        XCTAssertTrue(VolumeRoutePolicy.summary(route: .unavailable, output: .soundbarViaBox, samsungEnabled: true)
            .contains("Nothing is sent to other speakers"))
        XCTAssertEqual(VolumeRoutePolicy.unavailableReason(output: .soundbarViaBox, samsungEnabled: true), "Connect the TV box")
        XCTAssertEqual(VolumeRoutePolicy.unavailableReason(output: .tvSpeakers, samsungEnabled: false), "Samsung TV is off")
    }

    // MARK: Model wiring

    @MainActor
    func testWithTheBoxDisconnectedTheModelSendsNothingAndSaysWhy() {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: VolumeOutput.defaultsKey)
        defer {
            if let saved { defaults.set(saved, forKey: VolumeOutput.defaultsKey) } else { defaults.removeObject(forKey: VolumeOutput.defaultsKey) }
        }
        let remote = RemoteModel()
        remote.volumeOutput = .soundbarViaBox
        remote.connected = true   // flag alone: no command shell is open in the test host
        XCTAssertFalse(remote.commandShellReady)
        XCTAssertEqual(remote.volumeCommandRoute, .unavailable)
        XCTAssertEqual(remote.volumeScale, .unavailable)
        XCTAssertFalse(remote.volumeButtonsAvailable)
        XCTAssertFalse(remote.volume("VOLUME_UP"))
        XCTAssertTrue(remote.status.contains("Connect the TV box"), remote.status)
    }

    /// Source guard: the box path is the Phase 7.2 one (the persistent ADB shell's `input keyevent`),
    /// and the Phase 9 evidence probe that could silently switch to the TV's own level is gone.
    func testTheRestoredPathIsWiredEndToEnd() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard let features = try? String(contentsOf: repo.appendingPathComponent("GlassRemote/RemoteModel+Features.swift"), encoding: .utf8),
              let output = try? String(contentsOf: repo.appendingPathComponent("GlassRemote/VolumeOutput.swift"), encoding: .utf8) else {
            throw XCTSkip("app sources are not readable from the test run")
        }
        XCTAssertTrue(features.contains("case .boxKey(let code):"))
        XCTAssertTrue(features.contains("sendPersistentCommand(\"input keyevent \\(code)\")"))
        XCTAssertTrue(features.contains("case .boxKeys: return .boxKeys(max: VolumeRoutePolicy.boxSteps)"))
        XCTAssertTrue(output.contains("[\"VOLUME_UP\": \"24\", \"VOLUME_DOWN\": \"25\", \"MUTE\": \"164\"]"))
        for gone in ["VolumeOutputProbe", "volumeOutputEvidence", "applyVolumeEvidence"] {
            XCTAssertFalse(features.contains(gone), gone)
            XCTAssertFalse(output.contains(gone), gone)
        }
    }
}
