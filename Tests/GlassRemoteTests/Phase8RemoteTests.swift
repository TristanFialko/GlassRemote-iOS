import SwiftUI
import XCTest
@testable import GlassRemote

/// Phase 8 Remote redesign: orientation compositions, the landscape stage, the D-pad size, the Apps
/// launcher rules, the slimmer Remote menu and the dedicated Samsung landscape key set.
final class Phase8RemoteLayoutTests: XCTestCase {
    func testCompositionCoversEveryTargetAndOrientation() {
        XCTAssertEqual(RemoteLayoutPolicy.composition(target: .android, isLandscape: false), .androidPortrait)
        XCTAssertEqual(RemoteLayoutPolicy.composition(target: .android, isLandscape: true), .androidLandscape)
        XCTAssertEqual(RemoteLayoutPolicy.composition(target: .samsung, isLandscape: false), .samsungPortrait)
        XCTAssertEqual(RemoteLayoutPolicy.composition(target: .samsung, isLandscape: true), .samsungLandscape)
    }

    func testCompactThresholdAndPadMinimums() {
        XCTAssertTrue(RemoteLayoutPolicy.isCompact(height: 568))
        XCTAssertFalse(RemoteLayoutPolicy.isCompact(height: 760))
        let regular = RemoteLayoutPolicy.padMinHeight(compact: false, isLandscape: false)
        let compact = RemoteLayoutPolicy.padMinHeight(compact: true, isLandscape: false)
        XCTAssertGreaterThan(regular, compact)
        XCTAssertGreaterThanOrEqual(compact, 200)
        XCTAssertGreaterThan(RemoteLayoutPolicy.selectorHeight(compact: false, isLandscape: false),
                             RemoteLayoutPolicy.selectorHeight(compact: false, isLandscape: true))
        // The selector's segment height (total minus the 4 pt inset on each side) stays touch-sized.
        XCTAssertGreaterThanOrEqual(RemoteLayoutPolicy.selectorHeight(compact: true, isLandscape: true) - 8, 32)
    }

    func testDpadDiameterBounds() {
        XCTAssertEqual(RemoteLayoutPolicy.dpadDiameter(for: CGSize(width: 100, height: 100)), 180)
        XCTAssertEqual(RemoteLayoutPolicy.dpadDiameter(for: CGSize(width: 1000, height: 900)), 440)
        XCTAssertEqual(RemoteLayoutPolicy.dpadDiameter(for: CGSize(width: 320, height: 400)), 300)
    }

    // Phase 9 gap fix: the 27 % / 23 % side columns became narrow key rails, so the pad takes about
    // three quarters of the stage (RemoteLandscapeLayoutTests covers the whole landscape stage).
    func testRailsAlwaysLeaveThePadRoom() {
        for width in [400, 568, 667, 740, 844, 932, 1200] as [CGFloat] {
            let rail = RemoteLayoutPolicy.railWidth(stageWidth: width)
            XCTAssertGreaterThanOrEqual(rail, 58)
            XCTAssertLessThanOrEqual(rail, 72)
            XCTAssertGreaterThanOrEqual(RemoteLayoutPolicy.landscapePadWidth(stageWidth: width), width * 0.6, "width \(width)")
        }
        XCTAssertEqual(RemoteLayoutPolicy.railWidth(stageWidth: 2000), 72)
        XCTAssertEqual(RemoteLayoutPolicy.landscapePadWidth(stageWidth: 0), 0)
    }

    func testStageFramesKeepRailsBesideThePad() throws {
        let f = RemoteStageLayout.frames(width: 844, height: 360, topTrailingWidth: 160,
                                         leading: [176], trailing: [114, 52],
                                         spacing: 10, columnSpacing: 14)
        let pad = try XCTUnwrap(f.pad)
        XCTAssertGreaterThan(pad.width, 0)
        XCTAssertEqual(pad.minY, RemoteLayoutPolicy.topBarHeight + 10, accuracy: 0.5, "under the top bar")
        for rect in f.leading + f.trailing { XCTAssertFalse(rect.intersects(pad), "\(rect) overlaps the pad") }
        // Groups keep their order on a rail, one group gap apart.
        XCTAssertEqual(f.trailing[0].maxY + RemoteLayoutPolicy.railGroupSpacing, f.trailing[1].minY, accuracy: 0.5)
        XCTAssertLessThan(f.leading[0].maxX, pad.minX)
        XCTAssertGreaterThan(f.trailing[0].minX, pad.maxX)
    }

    func testStageWithoutTopBarOrDeckGivesThePadTheFullHeight() throws {
        let f = RemoteStageLayout.frames(width: 700, height: 300, topBar: false, leading: [], trailing: [],
                                         deck: false, spacing: 10, columnSpacing: 14)
        let pad = try XCTUnwrap(f.pad)
        let rail = RemoteLayoutPolicy.railWidth(stageWidth: 700)
        XCTAssertEqual(pad, CGRect(x: rail + 14, y: 0, width: 700 - 2 * (rail + 14), height: 300))
        XCTAssertNil(f.topLeading)
        XCTAssertNil(RemoteStageLayout.frames(width: 700, height: 300, leading: [40], trailing: [], hasPad: false,
                                              spacing: 10, columnSpacing: 14).pad)
    }
}

final class Phase8LauncherTests: XCTestCase {
    private let apps = [
        TVApp(name: "Netflix", package: "com.netflix.ninja", asset: "netflix"),
        TVApp(name: "Disney+", package: "com.disney.disneyplus", asset: "disney"),
        TVApp(name: "YouTube", package: "com.google.android.youtube.tv", asset: "youtube")
    ]

    func testBannerStates() {
        XCTAssertEqual(AppLauncherPolicy.banner(connected: false, installedCount: 12, status: "Connected"), .offline)
        XCTAssertEqual(AppLauncherPolicy.banner(connected: true, installedCount: 0, status: "Connected"), .scanning)
        XCTAssertEqual(AppLauncherPolicy.banner(connected: true, installedCount: 0, status: "App scan failed: timeout"), .scanFailed)
        XCTAssertEqual(AppLauncherPolicy.banner(connected: true, installedCount: 12, status: "Connected"),
                       AppLauncherPolicy.Banner.none)
    }

    func testFavouritesComeFirstInStarOrder() {
        let ordered = AppLauncherPolicy.ordered(apps, favourites: ["com.google.android.youtube.tv", "missing.pkg", "com.netflix.ninja"])
        XCTAssertEqual(ordered.map(\.name), ["YouTube", "Netflix", "Disney+"])
        XCTAssertEqual(AppLauncherPolicy.ordered(apps, favourites: []).map(\.name), apps.map(\.name))
    }

    func testFilterIsCaseAndDiacriticInsensitive() {
        XCTAssertEqual(AppLauncherPolicy.filtered(apps, query: "NET").map(\.name), ["Netflix"])
        XCTAssertEqual(AppLauncherPolicy.filtered(apps, query: "d\u{00ED}sney").map(\.name), ["Disney+"])
        XCTAssertEqual(AppLauncherPolicy.filtered(apps, query: "   ").count, apps.count)
        XCTAssertTrue(AppLauncherPolicy.filtered(apps, query: "zzz").isEmpty)
    }

    func testGridColumnsFollowWidth() {
        // Phase 9 continuation §A3: a fixed three-column grid at every width (tiles scale instead).
        for width: CGFloat in [280, 320, 393, 600, 932, 1366] {
            XCTAssertEqual(AppLauncherPolicy.columns(for: width), 3, "\(width)")
        }
    }
}

final class Phase8RemoteChromeTests: XCTestCase {
    func testNavClusterHasEachKeyOnce() {
        for landscape in [false, true] {
            for linked in [false, true] {
                let keys = RemoteNavKey.cluster(isLandscape: landscape, samsungLinked: linked)
                XCTAssertEqual(Set(keys).count, keys.count)
                XCTAssertTrue(keys.contains(.back) && keys.contains(.home) && keys.contains(.search) && keys.contains(.keyboard))
                XCTAssertEqual(keys.contains(.sources), linked)
            }
        }
    }

    // Phase 9 gap fix: the landscape launcher card became the Apps key on the leading rail.
    func testLauncherKeyIsInBothOrientations() {
        XCTAssertTrue(RemoteNavKey.cluster(isLandscape: false, samsungLinked: false).contains(.apps))
        XCTAssertTrue(RemoteNavKey.cluster(isLandscape: true, samsungLinked: false).contains(.apps))
        XCTAssertTrue(RemoteNavKey.landscapeRails(samsungLinked: false).leading.contains(.apps))
    }

    func testSettingsMovedOutOfTheRemoteMenu() {
        XCTAssertEqual(GlobalMenuSpec.movedToProfile, [.connections, .devices, .appearance])
        var all: [GlobalMenuSpec.Entry] = []
        for section in [GlobalMenuSpec.Section.device, .samsung, .advanced] {
            for box in [false, true] {
                for enabled in [false, true] {
                    all += GlobalMenuSpec.entries(in: section, boxOnline: box, samsungEnabled: enabled, samsungConnected: enabled)
                }
            }
        }
        XCTAssertTrue(all.contains(.profileSettings))
        XCTAssertEqual(GlobalMenuSpec.entries(in: .device, boxOnline: true, samsungEnabled: false, samsungConnected: false), [])
    }
}

final class Phase8SamsungLandscapeTests: XCTestCase {
    func testLandscapeSurfaceIsPrimaryKeysPlusChannel() {
        let keys = SamsungRemoteLayout.landscapeKeys
        XCTAssertEqual(Set(keys).count, keys.count, "a key appears twice in landscape")
        let primary = Set(SamsungRemoteLayout.primaryRows.flatMap { $0 }.map(\.key))
        XCTAssertEqual(Set(keys), primary.union([.channelUp, .channelDown]))
    }

    func testLandscapeKeysAreAllowlistedAndNeverRemovedOnes() {
        for key in SamsungRemoteLayout.landscapeKeys {
            XCTAssertTrue(SamsungKey.allowlist.contains(key.rawValue), "\(key)")
            XCTAssertFalse(SamsungRemoteLayout.removedFromSurface.contains(key), "\(key)")
            XCTAssertFalse(SamsungRemoteLayout.powerMenuKeys.contains(key), "\(key)")
        }
    }

    // Phase 9 gap fix: the keys moved onto two rails (four keys each); mute sits beside the deck.
    func testRailsHoldNavigationChannelTransportAndMute() {
        XCTAssertEqual(SamsungRemoteLayout.landscapeNavigation.map(\.key), [.back, .home])
        XCTAssertEqual(SamsungRemoteLayout.landscapeChannels.map(\.key), [.channelUp, .channelDown])
        XCTAssertEqual(SamsungRemoteLayout.landscapeMedia.map(\.key), [.rewind, .play, .fastForward])
        XCTAssertEqual(SamsungRemoteLayout.landscapeAudio.map(\.key), [.mute])
        XCTAssertEqual(SamsungRemoteLayout.landscapeLeadingRail.flatMap { $0 }.map(\.key), [.back, .home, .channelUp, .channelDown])
        XCTAssertEqual(SamsungRemoteLayout.landscapeTrailingRail.flatMap { $0 }.map(\.key), [.rewind, .play, .fastForward, .mute])
    }

    func testBannerShowsWheneverTheLinkIsNotUp() {
        XCTAssertTrue(SamsungRemoteLayout.showsBanner(enabled: false, state: .connected))
        XCTAssertFalse(SamsungRemoteLayout.showsBanner(enabled: true, state: .connected))
        for state in [SamsungLinkState.connecting, .pairing, .denied, .unreachable, .off] {
            XCTAssertTrue(SamsungRemoteLayout.showsBanner(enabled: true, state: state))
        }
    }
}

final class Phase8VolumeSliderTests: XCTestCase {
    func testFillHidesAtZeroAndCoversTheThumbOtherwise() {
        let thumb = VolumeSliderGeometry.thumbDiameter(height: 58)
        XCTAssertEqual(thumb, 48)
        XCTAssertEqual(VolumeSliderGeometry.fillWidth(value: 0, width: 300, thumb: thumb), 0)
        XCTAssertEqual(VolumeSliderGeometry.fillWidth(value: 0.01, width: 300, thumb: thumb), thumb + VolumeSliderGeometry.inset * 2)
        XCTAssertEqual(VolumeSliderGeometry.fillWidth(value: 0.5, width: 300, thumb: thumb), 150)
        XCTAssertEqual(VolumeSliderGeometry.fillWidth(value: 1, width: 300, thumb: thumb), 300)
        XCTAssertEqual(VolumeSliderGeometry.fillWidth(value: 1.4, width: 300, thumb: thumb), 300)
        XCTAssertEqual(VolumeSliderGeometry.fillWidth(value: 0.5, width: 0, thumb: thumb), 0)
    }
}
