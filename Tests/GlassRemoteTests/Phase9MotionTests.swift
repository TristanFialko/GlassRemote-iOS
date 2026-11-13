import SwiftUI
import XCTest
@testable import GlassRemote

/// Continuation §E: one shared motion language. These pin the tokens, Reduce Motion handling and
/// the rule that the interface has no one-off curves and no animation-sequencing sleeps.
final class Phase9MotionTests: XCTestCase {

    private var savedPreference: Any?

    override func setUp() {
        super.setUp()
        savedPreference = UserDefaults.standard.object(forKey: MotionPreference.key)
        UserDefaults.standard.set(false, forKey: MotionPreference.key)
    }

    override func tearDown() {
        if let savedPreference { UserDefaults.standard.set(savedPreference, forKey: MotionPreference.key) }
        else { UserDefaults.standard.removeObject(forKey: MotionPreference.key) }
        super.tearDown()
    }

    func testExistingTokensKeepTheirCurves() {
        XCTAssertEqual(Motion.page, Animation.spring(response: 0.42, dampingFraction: 0.86))
        XCTAssertEqual(Motion.snappy, Animation.spring(response: 0.28, dampingFraction: 0.82))
        XCTAssertEqual(Motion.expand, Animation.spring(response: 0.36, dampingFraction: 0.88))
        XCTAssertEqual(Motion.hero, Animation.spring(response: 0.5, dampingFraction: 0.9))
        XCTAssertEqual(Motion.tracking, Animation.interactiveSpring(response: 0.16, dampingFraction: 0.86))
    }

    func testControlsFeelImmediateAndNeverWobble() {
        for spring in Motion.Springs.controls {
            XCTAssertLessThanOrEqual(spring.response, 0.3, "\(spring) is too slow for a control under the finger")
            XCTAssertGreaterThanOrEqual(spring.damping, 0.7, "\(spring) would wobble")
        }
        for spring in Motion.Springs.all {
            XCTAssertGreaterThan(spring.response, 0)
            XCTAssertGreaterThan(spring.damping, 0)
            XCTAssertLessThanOrEqual(spring.damping, 1)
        }
    }

    func testSpatialMovesAreSlowerThanControls() {
        let fastestSpatial = [Motion.Springs.page, Motion.Springs.hero, Motion.Springs.poster].map(\.response).min() ?? 0
        let slowestControl = Motion.Springs.controls.map(\.response).max() ?? 1
        XCTAssertGreaterThan(fastestSpatial, slowestControl)
        XCTAssertLessThan(Motion.Springs.press.response, Motion.Springs.snappy.response, "a key goes down faster than it settles")
        XCTAssertEqual(Motion.Springs.ambient.damping, 1, "colour washes never overshoot")
    }

    func testReduceMotionReplacesOrRemovesMotion() {
        XCTAssertEqual(Motion.resolve(Motion.lensSettle, reduceMotion: true), Motion.reduced)
        XCTAssertEqual(Motion.resolve(Motion.ambient, reduceMotion: true), Motion.reduced)
        XCTAssertEqual(Motion.resolve(Motion.page, reduceMotion: false), Motion.page)
        XCTAssertNil(Motion.unlessReduced(Motion.pressBounce, reduceMotion: true))
        XCTAssertEqual(Motion.unlessReduced(Motion.pressBounce, reduceMotion: false), Motion.pressBounce)
    }

    func testInAppPreferenceAlsoReducesMotion() {
        UserDefaults.standard.set(true, forKey: MotionPreference.key)
        XCTAssertEqual(Motion.resolve(Motion.page, reduceMotion: false), Motion.reduced)
        XCTAssertNil(Motion.unlessReduced(Motion.settle, reduceMotion: false))
        XCTAssertEqual(Motion.adaptive(Motion.hero), Motion.reduced)
    }

    // MARK: Source audits

    private func sources() throws -> [(name: String, text: String)] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("GlassRemote")
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            throw XCTSkip("sources not readable from the test host")
        }
        var found: [(String, String)] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            if let text = try? String(contentsOf: url, encoding: .utf8) { found.append((url.lastPathComponent, text)) }
        }
        if found.isEmpty { throw XCTSkip("sources not readable from the test host") }
        return found
    }

    func testNoOneOffCurvesOutsideTheMotionLanguage() throws {
        // Only Motion.swift defines curves; the Apps folder keeps its own tuned, tested springs (§A).
        let allowed: Set<String> = ["Motion.swift", "AppsFolder.swift"]
        let patterns = [".spring(response:", "interactiveSpring(", "easeInOut(duration:", "easeOut(duration:",
                        "easeIn(duration:", ".linear(duration:"]
        for file in try sources() where !allowed.contains(file.name) {
            for pattern in patterns {
                XCTAssertFalse(file.text.contains(pattern), "\(file.name) defines its own curve (\(pattern)); use a Motion token")
            }
        }
    }

    func testNoSleepsInNavigationOrTransitions() throws {
        // Timed waits stay only where they are protocol, polling, input or idle rules (ADB/Samsung
        // transport, Android TV Remote v2 pairing step/code timeouts and control-link idle timeout and
        // reconnect backoff, network scans, account polling, key repeat, hold-to-drag and click release,
        // search debounce, palette settle, hero auto-advance, lens idle). Nothing sequences an animation.
        let allowed: Set<String> = [
            "CinemetaCatalog.swift", "Concurrency.swift", "DiscoverHero.swift", "GlassStyle.swift",
            "NetworkScanner.swift", "NuvioAccount.swift", "RemoteModel+Cursor.swift", "RemoteModel+Features.swift",
            "RemoteModel+Playback.swift", "RemoteModel.swift", "RemoteV2ControlConnection.swift",
            "RemoteV2PairingSession.swift", "RemoteView.swift", "RepeatKey.swift",
            "SamsungTV.swift", "SamsungVolume.swift", "TVShell.swift", "Theme.swift",
        ]
        for file in try sources() where !allowed.contains(file.name) {
            XCTAssertFalse(file.text.contains("Task.sleep("), "\(file.name) sleeps; drive it from state or a settle callback")
            XCTAssertFalse(file.text.contains("asyncAfter("), "\(file.name) uses a fixed delay")
        }
    }
}
