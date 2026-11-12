import SwiftUI
import XCTest
@testable import GlassRemote

/// Phase 9 gap fix: the Now Playing layout against the Apple Music references.
final class Phase9PlayerGapTests: XCTestCase {

    // MARK: Portrait

    func testPortraitTitleArtworkRunsEdgeToEdgeAndUnderTheStatusBar() {
        let margin = PlayerLayoutPolicy.nowPlayingMargin
        let region = CGSize(width: 393 - 2 * margin, height: 420)
        let bleed = PlayerLayoutPolicy.portraitBleed(region: region, margin: margin, topInset: 59)
        XCTAssertEqual(bleed.width, 393, accuracy: 0.001, "the side margins are given back")
        XCTAssertEqual(bleed.height, 420 + 59 + PlayerLayoutPolicy.bleedOverlap, accuracy: 0.001)
        XCTAssertGreaterThan(bleed.height, bleed.width, "the artwork dominates the upper screen")
        XCTAssertEqual(PlayerLayoutPolicy.portraitBleed(region: .zero, margin: margin, topInset: 59), .zero)
        XCTAssertEqual(PlayerLayoutPolicy.portraitBleed(region: CGSize(width: 300, height: -4), margin: margin, topInset: 59), .zero)
        // A negative inset or margin never shrinks the artwork.
        let odd = PlayerLayoutPolicy.portraitBleed(region: region, margin: -8, topInset: -20)
        XCTAssertEqual(odd.width, region.width, accuracy: 0.001)
        XCTAssertEqual(odd.height, region.height + PlayerLayoutPolicy.bleedOverlap, accuracy: 0.001)
    }

    func testTheArtworkHasFadedOutBeforeTheTitle() {
        XCTAssertGreaterThan(PlayerLayoutPolicy.bleedFadeStart, 0.4, "most of the artwork stays fully visible")
        XCTAssertLessThan(PlayerLayoutPolicy.bleedFadeStart, 0.9, "the fade is gradual, not an edge")
        XCTAssertGreaterThanOrEqual(PlayerLayoutPolicy.bleedOverlap, 40, "the fade continues behind the title")
    }

    func testTheNoArtworkCardKeepsClearOfTheGrabberAndTheTitle() {
        let region = CGSize(width: 337, height: 420)
        let card = PlayerLayoutPolicy.nowPlayingArtwork(kind: .appIcon, region: PlayerLayoutPolicy.portraitCardRegion(region: region))
        XCTAssertEqual(card.width, card.height, accuracy: 0.001)
        XCTAssertLessThanOrEqual(card.height, region.height - 2 * PlayerLayoutPolicy.portraitCardInset + 0.001)
        XCTAssertEqual(PlayerLayoutPolicy.portraitCardRegion(region: CGSize(width: 337, height: 20)).height, 0)
    }

    // MARK: Landscape

    func testTheLandscapeColumnIsAsTallAsTheArtworkButNeverSqueezed() {
        XCTAssertEqual(PlayerLayoutPolicy.landscapeColumnHeight(artSide: 330), 330)
        XCTAssertEqual(PlayerLayoutPolicy.landscapeColumnHeight(artSide: 120), PlayerLayoutPolicy.landscapeMinColumnHeight)
        // Title (two lines), timeline with its captions, transport, volume and three gaps fit.
        let rows = 2 * (PlayerLayoutPolicy.titleSize + 5) + (PlayerLayoutPolicy.timelineHeight + 7 + 15)
            + PlayerLayoutPolicy.transportHeight + ThinVolumeMetrics.minimumTouchTarget
            + 3 * PlayerLayoutPolicy.landscapeMinRowGap
        XCTAssertGreaterThanOrEqual(PlayerLayoutPolicy.landscapeMinColumnHeight, rows)
    }

    func testLandscapeStillFitsEveryPhoneWithTheNewInsets() {
        for page in [CGSize(width: 568, height: 320), CGSize(width: 667, height: 354), CGSize(width: 780, height: 372),
                     CGSize(width: 852, height: 372), CGSize(width: 1100, height: 760)] {
            let split = PlayerLayoutPolicy.landscape(page: page, bottomClearance: 8)
            XCTAssertGreaterThanOrEqual(split.column, PlayerLayoutPolicy.landscapeMinColumn - 0.001)
            XCTAssertLessThanOrEqual(split.artSide + PlayerLayoutPolicy.landscapeTopInset + 8, page.height + 0.001,
                                     "the card, the grabber inset and the clearance fit the page (\(page))")
        }
    }

    // MARK: Controls

    func testTransportAndTitleProportions() {
        XCTAssertGreaterThanOrEqual(PlayerLayoutPolicy.transportHeight, 44)
        XCTAssertGreaterThan(PlayerLayoutPolicy.playGlyph, PlayerLayoutPolicy.secondaryGlyph)
        XCTAssertGreaterThanOrEqual(PlayerLayoutPolicy.secondaryGlyph, 28, "the glyphs read as the main controls")
        XCTAssertLessThanOrEqual(PlayerLayoutPolicy.timelineHeight, 6)
        XCTAssertLessThanOrEqual(PlayerLayoutPolicy.grabberSize.height, 6)
    }

    func testTheCaptionUnderTheTimelineIsQuietWhilePlaying() {
        XCTAssertEqual(PlayerCaptionPolicy.caption(phase: .playing, seek: nil), "")
        XCTAssertEqual(PlayerCaptionPolicy.caption(phase: .paused, seek: nil), "Paused")
        XCTAssertEqual(PlayerCaptionPolicy.caption(phase: .buffering, seek: nil), "Buffering")
        XCTAssertEqual(PlayerCaptionPolicy.caption(phase: .stale, seek: nil), "Waiting for the TV")
        XCTAssertEqual(PlayerCaptionPolicy.caption(phase: .idle, seek: nil), "")
        XCTAssertEqual(PlayerCaptionPolicy.caption(phase: .playing, seek: "+10 s"), "+10 s", "a confirmed seek comes first")
        XCTAssertEqual(PlayerCaptionPolicy.caption(phase: .paused, seek: ""), "Paused")
        XCTAssertEqual(PlayerCaptionPolicy.seekText(seconds: 10.2), "+10 s")
        XCTAssertEqual(PlayerCaptionPolicy.seekText(seconds: -29.6), "−30 s")
    }

    func testNoDurationIsEverInvented() {
        let media = MediaState(package: "com.nuvio.app", title: "Title", state: 3, positionMs: 60_000, speed: 1,
                               sampledAt: Date(), actions: 2 | 4 | 8 | 64 | 512)
        XCTAssertNil(media.durationMs, "the box reports no duration")
        XCTAssertFalse(PlayerControls.resolve(media: media).progress, "so the timeline never fills")
    }

    // MARK: Rendered screens (for comparing with the references)

    /// Renders the real page, portrait and landscape, with and without title artwork, and writes the
    /// PNGs where CI collects them. A picture cannot be asserted on, so this only fails if the page
    /// cannot be rendered at all; the images are compared with the references by eye.
    @MainActor
    func testRenderNowPlayingScreens() async throws {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw XCTSkip("no window scene in this test host")
        }
        let folder = URL(fileURLWithPath: "/tmp/glassremote-snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let posterURL = folder.appendingPathComponent("sample-poster.png")
        try XCTUnwrap(Self.samplePoster().pngData()).write(to: posterURL)

        let remote = RemoteModel()
        remote.connected = true
        let navigator = PageNavigator()
        navigator.openPlayer(haptic: false)

        let cases: [(name: String, title: String, landscape: Bool, art: Bool)] = [
            ("nowplaying-portrait-art", "Girl Like Me", false, true),
            ("nowplaying-landscape-art", "Girl Like Me", true, true),
            ("nowplaying-portrait-noart", "No Artwork Title", false, false),
            ("nowplaying-landscape-noart", "No Artwork Title", true, false),
        ]
        for item in cases {
            PlayerArtworkStore.shared.remember(title: "Girl Like Me", posterURL: posterURL)
            remote.media = MediaState(package: "com.nuvio.app", title: item.title, state: 3, positionMs: 125_000, speed: 1,
                                      sampledAt: Date(), actions: 2 | 4 | 8 | 64 | 512, headline: "", subtitle: "Season 1 · Episode 4")
            PlayerBackdropStore.shared.show(item.art ? posterURL : nil)

            let size = item.landscape ? CGSize(width: 852, height: 393) : CGSize(width: 393, height: 852)
            // Landscape is drawn in a portrait-shaped host, so its insets are supplied by hand: the
            // rail's width on the leading side and the home indicator below.
            let page = PlayerPage()
                .environment(\.dockClearance, item.landscape ? 8 : 96)
                .environment(\.layoutContext, LayoutContext(isLandscape: item.landscape, size: size))
                .padding(.leading, item.landscape ? 96 : 0)
                .padding(.trailing, item.landscape ? 59 : 0)
                .padding(.bottom, item.landscape ? 21 : 0)
            let root = ZStack {
                Color.black
                PlayerBackdrop(visible: true)
                if item.landscape { page.ignoresSafeArea() } else { page }
            }
            .environmentObject(remote)
            .environmentObject(navigator)
            .preferredColorScheme(.dark)

            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: size)
            let host = UIHostingController(rootView: root)
            window.rootViewController = host
            window.isHidden = false
            host.view.frame = window.bounds
            host.view.layoutIfNeeded()
            // The artwork and the backdrop wash load asynchronously.
            try await Task.sleep(nanoseconds: 2_500_000_000)

            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let data = try XCTUnwrap(image.pngData())
            try data.write(to: folder.appendingPathComponent(item.name + ".png"))
            let attachment = XCTAttachment(image: image)
            attachment.name = item.name
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    /// A stand-in poster (2:3): bold shapes on a red field, so cropping and the fade are easy to judge.
    private static func samplePoster() -> UIImage {
        let size = CGSize(width: 600, height: 900)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let colours = [UIColor(red: 0.72, green: 0.08, blue: 0.12, alpha: 1).cgColor,
                           UIColor(red: 0.30, green: 0.02, blue: 0.06, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            UIColor(red: 0.98, green: 0.90, blue: 0.62, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: 330, y: 470, width: 220, height: 220))
            UIColor(white: 1, alpha: 0.92).setFill()
            cg.fillEllipse(in: CGRect(x: 60, y: 120, width: 200, height: 200))
            UIColor(red: 0.96, green: 0.62, blue: 0.70, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: 190, y: 250, width: 240, height: 320))
            UIColor(white: 1, alpha: 0.5).setStroke()
            cg.setLineWidth(6)
            cg.stroke(CGRect(x: 3, y: 3, width: size.width - 6, height: size.height - 6))
        }
    }
}
