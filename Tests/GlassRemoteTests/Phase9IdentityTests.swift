import XCTest
import SwiftUI
@testable import GlassRemote

/// Continuation §G: continuous backdrop, profile avatar in the dock and rail, per-profile appearance.
final class Phase9IdentityTests: XCTestCase {
    // MARK: §G2 continuous backdrop

    func testPageBackdropLinesUpWithTheWindow() {
        // A landscape Profile page that starts after the rail.
        let page = CGRect(x: 119, y: 0, width: 754, height: 430)
        let canvas = CGSize(width: 932, height: 430)
        let rect = BackdropAlignment.placement(pageFrame: page, canvas: canvas)
        XCTAssertEqual(rect, CGRect(x: -119, y: 0, width: 932, height: 430))
        // The canvas origin lands on the window origin, exactly where the root backdrop starts.
        if let rect {
            XCTAssertEqual(page.minX + rect.minX, 0)
            XCTAssertEqual(page.minY + rect.minY, 0)
        }
    }

    func testPagingPageKeepsTheBackdropFixed() {
        let canvas = CGSize(width: 932, height: 430)
        for y: CGFloat in [-430, -120, 0, 215, 430] {
            let page = CGRect(x: 119, y: y, width: 754, height: 430)
            let rect = BackdropAlignment.placement(pageFrame: page, canvas: canvas)
            XCTAssertEqual((rect?.minY ?? .nan) + y, 0, accuracy: 0.001)
        }
    }

    func testUnknownWindowFallsBackToFillingThePage() {
        let page = CGRect(x: 0, y: 0, width: 393, height: 852)
        XCTAssertNil(BackdropAlignment.placement(pageFrame: page, canvas: .zero))
        XCTAssertNil(BackdropAlignment.placement(pageFrame: CGRect(x: CGFloat.nan, y: 0, width: 393, height: 852), canvas: CGSize(width: 393, height: 852)))
    }

    func testWindowCanvasIsTheSizePlusEveryInset() {
        let size = CGSize(width: 814, height: 409)
        let insets = EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59)
        XCTAssertEqual(BackdropAlignment.canvasSize(size: size, insets: insets), CGSize(width: 932, height: 430))
        XCTAssertEqual(BackdropAlignment.canvasSize(size: .zero, insets: EdgeInsets()), .zero)
    }

    // MARK: §G3 per-profile appearance

    private func decode(_ json: String) throws -> ProfileSettings {
        try JSONDecoder().decode(ProfileSettings.self, from: Data(json.utf8))
    }

    func testLegacySettingsKeepTheCurrentAmbient() throws {
        let settings = try decode(#"{"themeID":"defaultDark","posterOrientation":"portrait"}"#)
        XCTAssertNil(settings.ambientID)
        XCTAssertNil(settings.ambient)
        XCTAssertEqual(settings.posterOrientation, .portrait)
    }

    func testStoredAmbientMigratesMountainsToDusk() throws {
        XCTAssertEqual(try decode(#"{"ambientID":"mountains"}"#).ambient, .dusk)
        XCTAssertEqual(try decode(#"{"ambientID":"aurora"}"#).ambient, .aurora)
        XCTAssertEqual(try decode(#"{"ambientID":"nonsense"}"#).ambient, AmbientStyle.none)
    }

    func testAmbientSurvivesARoundTrip() throws {
        var settings = ProfileSettings()
        settings.themeID = "defaultDark"
        settings.ambientID = AmbientStyle.nebula.rawValue
        let data = try JSONEncoder().encode(settings)
        let back = try JSONDecoder().decode(ProfileSettings.self, from: data)
        XCTAssertEqual(back, settings)
        XCTAssertEqual(back.ambient, .nebula)
    }

    @MainActor
    func testEachProfileKeepsItsOwnAmbientAndANewOneStartsFromTheActive() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Phase9Identity-\(UUID().uuidString)")
        let suite = "Phase9IdentityTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: folder)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = ProfileStore(directory: folder, defaults: defaults, appliesGlobally: false)
        store.updateSettings { $0.ambientID = AmbientStyle.aurora.rawValue }
        let second = try XCTUnwrap(store.create(name: "Guest"))
        XCTAssertEqual(second.settings.ambientID, AmbientStyle.aurora.rawValue)

        store.switchTo(second.id)
        store.updateSettings { $0.ambientID = AmbientStyle.mist.rawValue }
        XCTAssertEqual(store.active.settings.ambient, .mist)
        XCTAssertEqual(store.profiles.first { $0.id != second.id }?.settings.ambient, .aurora)

        // Persisted per profile.
        let reloaded = ProfileStore(directory: folder, defaults: defaults, appliesGlobally: false)
        XCTAssertEqual(reloaded.active.id, second.id)
        XCTAssertEqual(reloaded.active.settings.ambient, .mist)
    }

    func testDockAvatarRedrawsForAnotherProfileANewNameOrANewPhoto() {
        let id = UUID()
        let base = DockAvatarIdentity(id: id, initials: "ME", revision: 0)
        XCTAssertEqual(base, DockAvatarIdentity(id: id, initials: "ME", revision: 0))
        XCTAssertNotEqual(base, DockAvatarIdentity(id: UUID(), initials: "ME", revision: 0))
        XCTAssertNotEqual(base, DockAvatarIdentity(id: id, initials: "MA", revision: 0))
        XCTAssertNotEqual(base, DockAvatarIdentity(id: id, initials: "ME", revision: 1))
    }

    // MARK: Source audits

    private func source(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("GlassRemote")
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            throw XCTSkip("sources not readable from the test host")
        }
        for case let url as URL in walker where url.lastPathComponent == name {
            if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        }
        throw XCTSkip("\(name) not readable from the test host")
    }

    func testProfilePagesUseTheContinuousBackdrop() throws {
        for name in ["ProfilePage.swift", "ProfileSettingsPages.swift"] {
            let text = try source(name)
            XCTAssertTrue(text.contains("ContinuousBackdrop()"), name)
            XCTAssertFalse(text.contains("AmbientBackdrop()"), "\(name) would restart the backdrop at the rail")
        }
        XCTAssertTrue(try source("RootPagerView.swift").contains("\\.windowCanvasSize"))
    }

    func testDockShowsTheProfileAvatar() throws {
        XCTAssertTrue(try source("RootPagerView.swift").contains("DockProfileAvatar("))
    }

    func testProfileSwitchingNeverTouchesConnections() throws {
        let text = try source("ProfileStore.swift")
        for forbidden in ["RemoteModel", "ADBClient", "SamsungTV", "disconnect(", "reconnect("] {
            XCTAssertFalse(text.contains(forbidden), "ProfileStore must not reach \(forbidden)")
        }
    }
}
