import SwiftUI
import XCTest
@testable import GlassRemote

/// Phase 9 gap fix: the landscape Remote is a console built around the pad (top bar, a key rail under
/// each thumb, the pad in the middle, volume along its foot), not the portrait stack split into columns.
final class RemoteLandscapeLayoutTests: XCTestCase {

    // MARK: Real iPhone stages

    struct Device {
        let name: String
        let screen: CGSize
        let safeLeading: CGFloat
        let safeTrailing: CGFloat
        let safeBottom: CGFloat
    }

    /// Landscape screens and safe areas, smallest to largest.
    static let devices: [Device] = [
        Device(name: "SE 667×375", screen: CGSize(width: 667, height: 375), safeLeading: 0, safeTrailing: 0, safeBottom: 0),
        Device(name: "844×390", screen: CGSize(width: 844, height: 390), safeLeading: 47, safeTrailing: 47, safeBottom: 21),
        Device(name: "852×393", screen: CGSize(width: 852, height: 393), safeLeading: 59, safeTrailing: 59, safeBottom: 21),
        Device(name: "Pro Max 956×440", screen: CGSize(width: 956, height: 440), safeLeading: 62, safeTrailing: 62, safeBottom: 21)
    ]

    /// The Remote's stage on a landscape screen, as RootPagerView (rail clearance, bottom clearance) and
    /// RemoteView (stage insets) lay it out.
    static func stage(_ device: Device) -> CGSize {
        let insets = RemoteLayoutPolicy.stageInsets
        let pageWidth = device.screen.width - device.safeLeading - device.safeTrailing
            - DockMetrics.railClearance(safeLeading: device.safeLeading)
        let pageHeight = device.screen.height - device.safeBottom - DockMetrics.landscapeBottomClearance
        return CGSize(width: pageWidth - insets.leading - insets.trailing,
                      height: pageHeight - insets.top - insets.bottom)
    }

    /// Natural height of a rail group of `keys` keys.
    static func group(_ keys: Int, stageHeight: CGFloat) -> CGFloat {
        let key = RemoteLayoutPolicy.railKeyHeight(stageHeight: stageHeight)
        return CGFloat(keys) * key + CGFloat(max(keys - 1, 0)) * 10
    }

    /// The device switch (108 pt) and power (44 pt) with their 8 pt gap.
    static let topTrailingWidth: CGFloat = 160

    static func android(_ size: CGSize, linked: Bool = true) -> RemoteStageLayout.Frames {
        RemoteStageLayout.frames(width: size.width, height: size.height, topTrailingWidth: topTrailingWidth,
                                 leading: [group(3, stageHeight: size.height)],
                                 trailing: [group(linked ? 3 : 2, stageHeight: size.height)])
    }

    static func samsung(_ size: CGSize, banner: CGFloat? = nil) -> RemoteStageLayout.Frames {
        RemoteStageLayout.frames(width: size.width, height: size.height, topTrailingWidth: topTrailingWidth,
                                 leading: [group(2, stageHeight: size.height), group(2, stageHeight: size.height)],
                                 trailing: [group(3, stageHeight: size.height), group(1, stageHeight: size.height)],
                                 overPad: banner.map { [$0] } ?? [])
    }

    func testStageSizesMatchTheScreens() {
        let standard = Self.stage(Self.devices[2])
        XCTAssertEqual(standard.width, 631.8, accuracy: 0.05)
        XCTAssertEqual(standard.height, 350, accuracy: 0.05)
        let se = Self.stage(Self.devices[0])
        XCTAssertEqual(se.width, 553, accuracy: 0.05)
        XCTAssertEqual(se.height, 353, accuracy: 0.05)
    }

    // MARK: The pad dominates

    func testTrackpadDominatesEveryLandscapeIPhone() throws {
        for device in Self.devices {
            let size = Self.stage(device)
            let pad = try XCTUnwrap(Self.android(size).pad, device.name)
            XCTAssertGreaterThanOrEqual(pad.width, size.width * 0.72, "\(device.name): pad takes most of the width")
            XCTAssertGreaterThanOrEqual(pad.width, 400, device.name)
            XCTAssertGreaterThanOrEqual(pad.height, RemoteLayoutPolicy.padMinHeight(compact: false, isLandscape: true), device.name)
            XCTAssertGreaterThanOrEqual(pad.width * pad.height, size.width * size.height * 0.45,
                                        "\(device.name): the pad is the largest thing on the stage")
            // Wider than tall, like the TV it drives.
            XCTAssertGreaterThan(pad.width / pad.height, 1.6, device.name)
        }
    }

    func testTrackpadSizeOnA852PointIPhone() throws {
        let size = Self.stage(Self.devices[2])
        let pad = try XCTUnwrap(Self.android(size).pad)
        XCTAssertEqual(pad.width, 477.4, accuracy: 0.5)
        XCTAssertEqual(pad.height, 220, accuracy: 0.5)
        XCTAssertEqual(pad.midX, size.width / 2, accuracy: 0.5, "the pad is centred between the rails")
    }

    func testSmallestAndLargestPads() throws {
        let se = try XCTUnwrap(Self.android(Self.stage(Self.devices[0])).pad)
        XCTAssertEqual(se.width, 409, accuracy: 0.5)
        XCTAssertEqual(se.height, 223, accuracy: 0.5)
        let largest = try XCTUnwrap(Self.android(Self.stage(Self.devices[3])).pad)
        XCTAssertEqual(largest.width, 558, accuracy: 0.5)
        XCTAssertEqual(largest.height, 267, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(RemoteLayoutPolicy.dpadDiameter(for: se.size), 200, "the D-pad stays large")
    }

    func testPadAndDeckDoNotDependOnTheTarget() {
        for device in Self.devices {
            let size = Self.stage(device)
            let android = Self.android(size, linked: false)
            let samsung = Self.samsung(size, banner: 52)
            XCTAssertEqual(android.pad, samsung.pad, device.name)
            XCTAssertEqual(android.deck, samsung.deck, device.name)
            XCTAssertEqual(android.topCenter, samsung.topCenter, device.name)
            XCTAssertEqual(RemoteStageLayout.padRect(width: size.width, height: size.height), android.pad, device.name)
        }
    }

    // MARK: Nothing overlaps, everything is on the stage

    private func assertTidy(_ frames: RemoteStageLayout.Frames, in size: CGSize, _ label: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        var rects: [(String, CGRect)] = []
        if let r = frames.topLeading { rects.append(("status", r)) }
        if let r = frames.topCenter { rects.append(("mode", r)) }
        if let r = frames.topTrailing { rects.append(("device and power", r)) }
        rects += frames.leading.enumerated().map { ("leading group \($0.offset)", $0.element) }
        rects += frames.trailing.enumerated().map { ("trailing group \($0.offset)", $0.element) }
        if let r = frames.pad { rects.append(("pad", r)) }
        if let r = frames.deck { rects.append(("deck", r)) }
        for (name, rect) in rects {
            XCTAssertGreaterThanOrEqual(rect.minX, -0.5, "\(label): \(name) leaves the stage", file: file, line: line)
            XCTAssertGreaterThanOrEqual(rect.minY, -0.5, "\(label): \(name) leaves the stage", file: file, line: line)
            XCTAssertLessThanOrEqual(rect.maxX, size.width + 0.5, "\(label): \(name) leaves the stage", file: file, line: line)
            XCTAssertLessThanOrEqual(rect.maxY, size.height + 0.5, "\(label): \(name) leaves the stage", file: file, line: line)
        }
        for i in rects.indices {
            for j in rects.indices where j > i {
                XCTAssertFalse(rects[i].1.intersects(rects[j].1),
                               "\(label): \(rects[i].0) overlaps \(rects[j].0)", file: file, line: line)
            }
        }
        // The banner floats over the pad only.
        if let pad = frames.pad {
            for banner in frames.overPad {
                XCTAssertTrue(pad.contains(banner), "\(label): banner leaves the pad", file: file, line: line)
            }
        }
        // Swipe areas are free space.
        for gap in [frames.leadingGap, frames.trailingGap].compactMap({ $0 }) {
            XCTAssertGreaterThanOrEqual(gap.height, RemoteStageLayout.swipeAreaMinHeight, file: file, line: line)
            for (name, rect) in rects {
                XCTAssertFalse(gap.intersects(rect), "\(label): swipe area overlaps \(name)", file: file, line: line)
            }
        }
    }

    func testNothingOverlapsOnAnyIPhone() {
        for device in Self.devices {
            let size = Self.stage(device)
            assertTidy(Self.android(size), in: size, "Android \(device.name)")
            assertTidy(Self.android(size, linked: false), in: size, "Android unlinked \(device.name)")
            assertTidy(Self.samsung(size), in: size, "Samsung \(device.name)")
            assertTidy(Self.samsung(size, banner: 52), in: size, "Samsung banner \(device.name)")
        }
    }

    // MARK: Reach and balance

    func testKeyRailsSitUnderTheThumbs() {
        for device in Self.devices {
            let size = Self.stage(device)
            for frames in [Self.android(size), Self.samsung(size)] {
                let rail = RemoteLayoutPolicy.railWidth(stageWidth: size.width)
                XCTAssertGreaterThanOrEqual(rail, 58, "a full-size key")
                XCTAssertLessThanOrEqual(rail, 72)
                let band = RemoteLayoutPolicy.topBarHeight + 10
                for rect in frames.leading {
                    XCTAssertEqual(rect.minX, 0, accuracy: 0.5, device.name)
                    XCTAssertEqual(rect.width, rail, accuracy: 0.5)
                    XCTAssertGreaterThanOrEqual(rect.minY, band - 0.5, "\(device.name): keys stay below the top bar")
                }
                for rect in frames.trailing {
                    XCTAssertEqual(rect.maxX, size.width, accuracy: 0.5, device.name)
                    XCTAssertGreaterThanOrEqual(rect.minY, band - 0.5, device.name)
                }
            }
        }
    }

    func testSamsungRailsBalance() throws {
        for device in Self.devices {
            let frames = Self.samsung(Self.stage(device))
            let leadingTop = try XCTUnwrap(frames.leading.first).minY
            let trailingTop = try XCTUnwrap(frames.trailing.first).minY
            let leadingBottom = try XCTUnwrap(frames.leading.last).maxY
            let trailingBottom = try XCTUnwrap(frames.trailing.last).maxY
            XCTAssertEqual(leadingTop, trailingTop, accuracy: 0.5, "four keys a side: the rails line up")
            XCTAssertEqual(leadingBottom, trailingBottom, accuracy: 0.5)
        }
        XCTAssertEqual(SamsungRemoteLayout.landscapeLeadingRail.flatMap { $0 }.count,
                       SamsungRemoteLayout.landscapeTrailingRail.flatMap { $0 }.count)
    }

    func testTopBarHoldsStatusModeAndPower() throws {
        for device in Self.devices {
            let size = Self.stage(device)
            let frames = Self.android(size)
            let status = try XCTUnwrap(frames.topLeading)
            let mode = try XCTUnwrap(frames.topCenter)
            let power = try XCTUnwrap(frames.topTrailing)
            let pad = try XCTUnwrap(frames.pad)
            XCTAssertEqual(status.height, RemoteLayoutPolicy.topBarHeight)
            XCTAssertEqual(mode.midX, pad.midX, accuracy: 0.5, "\(device.name): the mode selector is centred over the pad")
            XCTAssertGreaterThanOrEqual(mode.minX - status.maxX, 10 - 0.5, device.name)
            XCTAssertGreaterThanOrEqual(power.minX - mode.maxX, 10 - 0.5, device.name)
            XCTAssertEqual(power.width, Self.topTrailingWidth)
            XCTAssertEqual(RemoteLayoutPolicy.pillStyle(width: status.width), .full,
                           "\(device.name): the device name is never shortened")
            XCTAssertGreaterThanOrEqual(mode.width, 132, "two touch-sized segments")
        }
    }

    func testVolumeDeckRunsUnderThePad() throws {
        for device in Self.devices {
            let size = Self.stage(device)
            let frames = Self.android(size)
            let pad = try XCTUnwrap(frames.pad)
            let deck = try XCTUnwrap(frames.deck)
            XCTAssertEqual(deck.minX, pad.minX, accuracy: 0.5, device.name)
            XCTAssertEqual(deck.width, pad.width, accuracy: 0.5, device.name)
            XCTAssertEqual(deck.minY, pad.maxY + 10, accuracy: 0.5, device.name)
            XCTAssertEqual(deck.maxY, size.height, accuracy: 0.5, "\(device.name): bottom-aligned, in thumb reach")
            XCTAssertEqual(deck.height, RemoteLayoutPolicy.landscapeVolumeThickness, device.name)
            XCTAssertEqual(deck.height, RemoteLayoutPolicy.landscapeDeckHeight(stageHeight: size.height), device.name)
            XCTAssertGreaterThanOrEqual(deck.width, RemoteLayoutPolicy.landscapeVolumeMinLength, device.name)
        }
    }

    func testBannerFloatsOverTheTopOfThePad() throws {
        let size = Self.stage(Self.devices[2])
        let frames = Self.samsung(size, banner: 52)
        let pad = try XCTUnwrap(frames.pad)
        let banner = try XCTUnwrap(frames.overPad.first)
        XCTAssertEqual(banner.minY, pad.minY + RemoteLayoutPolicy.overPadInset, accuracy: 0.5)
        XCTAssertEqual(banner.minX, pad.minX + RemoteLayoutPolicy.overPadInset, accuracy: 0.5)
        XCTAssertEqual(banner.width, pad.width - 2 * RemoteLayoutPolicy.overPadInset, accuracy: 0.5)
        XCTAssertEqual(frames.pad, Self.samsung(size).pad, "the banner never shrinks the pad")
    }

    // MARK: Keys

    func testAndroidRailsHoldEveryNavKeyOnce() {
        for linked in [false, true] {
            let rails = RemoteNavKey.landscapeRails(samsungLinked: linked)
            let all = rails.leading + rails.trailing
            XCTAssertEqual(Set(all).count, all.count)
            XCTAssertEqual(Set(all), Set(RemoteNavKey.cluster(isLandscape: false, samsungLinked: linked)),
                           "landscape offers the same keys as portrait")
            XCTAssertEqual(rails.leading, [.back, .home, .apps])
            XCTAssertEqual(rails.trailing.contains(.sources), linked)
        }
    }

    func testRailKeysFitEvenAVeryShortStage() {
        XCTAssertEqual(RemoteLayoutPolicy.railKeyHeight(stageHeight: 350), 52)
        XCTAssertEqual(RemoteLayoutPolicy.railKeyHeight(stageHeight: 300), 46)
        for height: CGFloat in [300, 320, 350, 397] {
            let band = RemoteLayoutPolicy.landscapeBandHeight(stageHeight: height)
            let samsung = Self.group(2, stageHeight: height) * 2 + RemoteLayoutPolicy.railGroupSpacing
            XCTAssertLessThanOrEqual(samsung, band, "\(height)")
            XCTAssertGreaterThanOrEqual(RemoteLayoutPolicy.railKeyHeight(stageHeight: height), 44)
        }
    }

    // MARK: Rendering

    /// Renders the real Remote page to /tmp/glassremote-snapshots for visual review: portrait, the
    /// 852×393 and SE landscape stages, the Samsung target and D-pad mode in landscape.
    @MainActor
    func testRenderRemoteScreens() async throws {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw XCTSkip("no window scene in this test host")
        }
        let folder = URL(fileURLWithPath: "/tmp/glassremote-snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // A saved host means this is not a first run, so no connection sheet opens over the page.
        let defaults = UserDefaults.standard
        let savedHost = defaults.object(forKey: "tvHost")
        let savedTarget = defaults.object(forKey: "glassRemote.target")
        defaults.set("192.0.2.10", forKey: "tvHost")
        let remote = RemoteModel()
        if let savedHost { defaults.set(savedHost, forKey: "tvHost") } else { defaults.removeObject(forKey: "tvHost") }
        defer {
            if let savedTarget { defaults.set(savedTarget, forKey: "glassRemote.target") }
            else { defaults.removeObject(forKey: "glassRemote.target") }
        }
        remote.connected = true
        let navigator = PageNavigator()

        let standard = Self.devices[2]
        let se = Self.devices[0]
        let portraitBottom = 34 + DockMetrics.clearance(safeBottom: 34, miniPlayer: false)
        let cases: [(name: String, screen: CGSize, landscape: Bool, insets: EdgeInsets, target: RemoteTarget, mouse: Bool)] = [
            ("remote-portrait", CGSize(width: 393, height: 852), false,
             EdgeInsets(top: 59, leading: 0, bottom: portraitBottom, trailing: 0), .android, true),
            ("remote-landscape", standard.screen, true, Self.landscapeInsets(standard), .android, true),
            ("remote-landscape-se", se.screen, true, Self.landscapeInsets(se), .android, true),
            ("remote-landscape-dpad", standard.screen, true, Self.landscapeInsets(standard), .android, false),
            ("remote-landscape-samsung", standard.screen, true, Self.landscapeInsets(standard), .samsung, true)
        ]
        for item in cases {
            remote.target = item.target
            remote.isTrackpad = item.mouse
            let pageSize = CGSize(width: item.screen.width - item.insets.leading - item.insets.trailing,
                                  height: item.screen.height - item.insets.top - item.insets.bottom)
            let page = RemoteView()
                .environment(\.layoutContext, LayoutContext(isLandscape: item.landscape, size: pageSize))
                .padding(item.insets)
                .ignoresSafeArea()
            let root = ZStack {
                AmbientBackdrop()
                page
            }
            .environmentObject(remote)
            .environmentObject(navigator)
            .preferredColorScheme(.dark)

            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: item.screen)
            let host = UIHostingController(rootView: root)
            window.rootViewController = host
            window.isHidden = false
            host.view.frame = window.bounds
            host.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 1_000_000_000)

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
        remote.isTrackpad = true
    }

    /// The page's insets on a landscape screen: the safe areas, the rail's clearance on the leading
    /// side and the landscape bottom clearance.
    static func landscapeInsets(_ device: Device) -> EdgeInsets {
        EdgeInsets(top: 0,
                   leading: device.safeLeading + DockMetrics.railClearance(safeLeading: device.safeLeading),
                   bottom: device.safeBottom + DockMetrics.landscapeBottomClearance,
                   trailing: device.safeTrailing)
    }
}
