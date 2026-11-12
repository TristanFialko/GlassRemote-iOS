import XCTest
import SwiftUI
@testable import GlassRemote

/// v5 §6: the Remote shows icons instead of "Mouse" / "D-pad" captions and no instructions inside the
/// trackpad surfaces; the instructions are kept for VoiceOver.
final class Phase9RemoteV5Tests: XCTestCase {
    func testSelectedModeIconTakesTheThemeAccent() {
        XCTAssertEqual(ModeSelectorStyle.iconColor(selected: true, accent: .red), .red)
        XCTAssertNotEqual(ModeSelectorStyle.iconColor(selected: false, accent: .red), .red)
        XCTAssertLessThan(ModeSelectorStyle.unselectedOpacity, 1)
        XCTAssertGreaterThanOrEqual(ModeSelectorStyle.unselectedOpacity, 0.6, "the unselected icon stays legible")
    }

    func testTrackpadInstructionsAreKeptForVoiceOver() {
        let android = RemoteSurfaceHints.androidTrackpad
        XCTAssertTrue(android.contains("click"))
        XCTAssertTrue(android.contains("drag"))
        XCTAssertTrue(android.contains("scroll"))
        XCTAssertTrue(android.contains("Back"))
        let samsung = RemoteSurfaceHints.samsungTrackpad
        XCTAssertTrue(samsung.contains("focus"))
        XCTAssertTrue(samsung.contains("select"))
        XCTAssertTrue(samsung.contains("Back"))
        XCTAssertFalse(samsung.contains("click"), "the Samsung pad is not a pointer")
    }

    /// Source guard: the captions and in-surface instructions are gone from the drawn UI.
    func testNoVisibleModeCaptionsOrSurfaceInstructions() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("GlassRemote")
        func read(_ name: String) -> String? { try? String(contentsOf: root.appendingPathComponent(name), encoding: .utf8) }
        guard let style = read("GlassStyle.swift"), let remote = read("RemoteView.swift"),
              let samsung = read("DirectionalTrackpad.swift") else {
            throw XCTSkip("app sources are not readable from the test run")
        }
        XCTAssertFalse(style.contains("Text(mouse ? \"Mouse\" : \"D-pad\")"), "no Mouse / D-pad captions")
        XCTAssertFalse(remote.contains("Text(\"Tap to click"), "no instructions inside the Android trackpad")
        XCTAssertFalse(samsung.contains("Text(\"Slide to move focus"), "no instructions inside the Samsung trackpad")
        XCTAssertTrue(remote.contains("RemoteSurfaceHints.androidTrackpad"))
        XCTAssertTrue(samsung.contains("RemoteSurfaceHints.samsungTrackpad"))
    }
}
