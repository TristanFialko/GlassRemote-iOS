import CoreGraphics
import XCTest
@testable import GlassRemote

/// Phase 9 continuation §C: the volume slider shows a true 0–100 % of each target's own range,
/// readings never fight the finger, haptics mark real steps, and landscape gives volume its own deck.
final class Phase9VolumeTests: XCTestCase {

    private let checkpoints = [0, 1, 25, 50, 75, 99, 100]
    private let stageWidths: [CGFloat] = [454, 520, 568, 640, 700, 812, 932, 1100]

    // MARK: C2 per-target percentages

    func testSamsungAbsoluteStandardRangeIsExact() {
        let scale = VolumeScale.samsungAbsolute(.standard)
        XCTAssertEqual(scale.route, .samsungAbsolute)
        XCTAssertEqual(scale.steps, 100)
        XCTAssertTrue(scale.floorIsMute)
        for p in checkpoints {
            let f = scale.fraction(forPercent: p)
            XCTAssertEqual(scale.raw(forFraction: f), p, "raw at \(p) %")
            XCTAssertEqual(scale.percent(forFraction: f), p, "shown at \(p) %")
        }
    }

    func testCalibratedSamsungRangeStillReachesBothEnds() {
        let scale = VolumeScale.samsungAbsolute(VolumeCalibration(lo: 2, hi: 98))
        XCTAssertFalse(scale.floorIsMute, "a floor above raw 0 is a minimum, not mute")
        let expectedRaw = [0: 2, 1: 3, 25: 26, 50: 50, 75: 74, 99: 97, 100: 98]
        for p in checkpoints {
            let f = scale.fraction(forPercent: p)
            XCTAssertEqual(scale.raw(forFraction: f), expectedRaw[p], "raw at \(p) %")
            XCTAssertEqual(scale.percent(forFraction: f), p, "shown at \(p) %")
        }
    }

    func testSamsungKeysUseTheSoundbarScaleSeparately() {
        let keys = VolumeScale.samsungKeys(max: 60)
        XCTAssertEqual(keys.route, .samsungKeys)
        XCTAssertEqual(keys.steps, 60)
        XCTAssertEqual(keys.percent(forFraction: 0.5), 50)
        XCTAssertEqual(keys.percent(forFraction: 1), 100)
        XCTAssertEqual(keys.step(forFraction: 1), 60)
        XCTAssertNotEqual(keys, VolumeScale.unavailable)
    }

    func testOnlyTheEndsShowZeroAndOneHundred() {
        let scales: [VolumeScale] = [.samsungAbsolute(.standard), .samsungAbsolute(VolumeCalibration(lo: 3, hi: 96)),
                                     .samsungKeys(max: 200), .samsungKeys(max: 15),
                                     .samsungKeys(max: 7)]
        for scale in scales {
            for raw in (scale.lo + 1)..<scale.hi {
                let p = scale.percent(forRaw: raw)
                XCTAssertTrue((1...99).contains(p), "\(scale) raw \(raw) shows \(p)")
            }
            XCTAssertEqual(scale.percent(forRaw: scale.lo), 0)
            XCTAssertEqual(scale.percent(forRaw: scale.hi), 100)
            XCTAssertEqual(scale.raw(forFraction: 0.001), scale.lo + 1, "any non-zero drag is above the floor")
            XCTAssertEqual(scale.raw(forFraction: 0.999), scale.hi - 1, "anything short of full is below the top")
        }
    }

    func testMuteAndMinimumAreDistinct() {
        XCTAssertEqual(VolumeReadout.symbol(percent: 0, floorIsMute: true), "speaker.slash.fill")
        XCTAssertEqual(VolumeReadout.symbol(percent: 0, floorIsMute: false), "speaker.fill")
        XCTAssertEqual(VolumeReadout.accessibilityValue(percent: 0, floorIsMute: true), "Muted, 0 percent")
        XCTAssertEqual(VolumeReadout.accessibilityValue(percent: 0, floorIsMute: false), "Minimum, 0 percent")
        XCTAssertEqual(VolumeReadout.accessibilityValue(percent: 100, floorIsMute: false), "100 percent")
        XCTAssertEqual(VolumeReadout.symbol(percent: 1, floorIsMute: true), "speaker.wave.1.fill")
        XCTAssertEqual(VolumeReadout.symbol(percent: 50, floorIsMute: true), "speaker.wave.2.fill")
        XCTAssertEqual(VolumeReadout.symbol(percent: 100, floorIsMute: true), "speaker.wave.3.fill")
        XCTAssertEqual(VolumeReadout.text(percent: 100), "100%")
        XCTAssertEqual(VolumeReadout.text(percent: 0), "0%")
    }

    // MARK: C2 echoes and reconcile

    func testReadingsNeverFightTheFingerAndSettleOnceAfterADrag() {
        var sync = VolumeSync()
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
        func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
        XCTAssertEqual(sync.reading(0.4, showing: 0.5, at: t0), 0.4, "idle: the device wins")
        sync.dragBegan(at: at(1))
        XCTAssertNil(sync.reading(0.2, showing: 0.6, at: at(1.5)), "mid-drag echo ignored")
        sync.userChanged(at: at(2))
        sync.dragEnded(at: at(2.2))
        XCTAssertNil(sync.reading(0.3, showing: 0.6, at: at(3)), "stale reading inside the hold-off")
        XCTAssertFalse(sync.reconcileDue(at: at(3)))
        XCTAssertTrue(sync.reconcileDue(at: at(4.3)))
        XCTAssertFalse(sync.reconcileDue(at: at(4.4)), "only once")
        XCTAssertEqual(sync.reading(0.62, showing: 0.6, at: at(4.5)), 0.62, "settled value shown")
        XCTAssertNil(sync.reading(0.6, showing: 0.6, at: at(4.6)), "a reading that would not move the thumb")
    }

    func testAReadingAfterTheHoldoffSatisfiesTheReconcile() {
        var sync = VolumeSync()
        let t0 = Date(timeIntervalSinceReferenceDate: 5_000)
        sync.dragBegan(at: t0)
        sync.dragEnded(at: t0.addingTimeInterval(0.5))
        XCTAssertEqual(sync.reading(0.3, showing: 0.4, at: t0.addingTimeInterval(3)), 0.3)
        XCTAssertFalse(sync.reconcileDue(at: t0.addingTimeInterval(3.1)))
    }

    func testVoiceOverIncrementsAlsoReconcile() {
        var sync = VolumeSync()
        let t0 = Date(timeIntervalSinceReferenceDate: 9_000)
        sync.userChanged(at: t0)
        XCTAssertFalse(sync.acceptsReading(at: t0.addingTimeInterval(1)))
        XCTAssertTrue(sync.reconcileDue(at: t0.addingTimeInterval(sync.holdoff + 0.1)))
    }

    // MARK: C1 haptics and accessibility

    func testHapticsTickOncePerRealStepOfAUserDrag() {
        XCTAssertFalse(VolumeHapticPolicy.shouldTick(previousStep: nil, newStep: 3, userInitiated: true))
        XCTAssertFalse(VolumeHapticPolicy.shouldTick(previousStep: 3, newStep: 3, userInitiated: true))
        XCTAssertTrue(VolumeHapticPolicy.shouldTick(previousStep: 3, newStep: 4, userInitiated: true))
        XCTAssertFalse(VolumeHapticPolicy.shouldTick(previousStep: 3, newStep: 9, userInitiated: false),
                       "TV readings never tick")
        let scales: [VolumeScale] = [.samsungKeys(max: 15), .samsungAbsolute(.standard)]
        for scale in scales {
            var previous: Int? = scale.step(forFraction: 0)
            var ticks = 0
            for i in 0...1000 {
                let step = scale.step(forFraction: Double(i) / 1000)
                if VolumeHapticPolicy.shouldTick(previousStep: previous, newStep: step, userInitiated: true) { ticks += 1 }
                previous = step
            }
            XCTAssertEqual(ticks, scale.steps, "one tick per level on a full sweep of \(scale)")
        }
    }

    func testVoiceOverStepsLandOnRealLevels() {
        let short = VolumeScale.samsungKeys(max: 15)
        XCTAssertEqual(short.accessibilityStep, 1)
        XCTAssertEqual(short.adjusted(short.fraction(forRaw: 8), up: true), short.fraction(forRaw: 9), accuracy: 1e-9)
        XCTAssertEqual(short.adjusted(1, up: true), 1, accuracy: 1e-9)
        XCTAssertEqual(short.adjusted(0, up: false), 0, accuracy: 1e-9)
        let long = VolumeScale.samsungAbsolute(.standard)
        XCTAssertEqual(long.accessibilityStep, 5)
        XCTAssertEqual(long.percent(forFraction: long.adjusted(0.5, up: true)), 55)
        XCTAssertEqual(long.adjusted(0.03, up: false), 0, accuracy: 1e-9)
    }

    // MARK: C3 landscape volume deck

    private func androidStage(width: CGFloat, height: CGFloat) -> RemoteStageLayout.Frames {
        RemoteStageLayout.frames(width: width, height: height,
                                 leading: [96, 40, 58], leadingBottom: [false, false, true],
                                 trailing: [114], trailingBottom: [false],
                                 hasPad: true, spacing: 10, columnSpacing: 14,
                                 reservesColumns: true, deck: true)
    }

    private func samsungStage(width: CGFloat, height: CGFloat) -> RemoteStageLayout.Frames {
        RemoteStageLayout.frames(width: width, height: height,
                                 leading: [96, 52], leadingBottom: [false, true],
                                 trailing: [52, 52], trailingBottom: [false, true],
                                 hasPad: true, spacing: 10, columnSpacing: 14,
                                 reservesColumns: true, deck: true)
    }

    func testLandscapeVolumeDeckIsLongAndProminent() throws {
        for width in stageWidths {
            for height in [300, 340, 380] as [CGFloat] {
                let frames = androidStage(width: width, height: height)
                let deck = try XCTUnwrap(frames.deck)
                let pad = try XCTUnwrap(frames.pad)
                let label = "\(width)×\(height)"
                XCTAssertGreaterThanOrEqual(deck.width, RemoteLayoutPolicy.landscapeVolumeMinLength, label)
                XCTAssertGreaterThanOrEqual(deck.width, width * 0.6, label)
                XCTAssertGreaterThanOrEqual(deck.width, RemoteLayoutPolicy.columnWidths(for: width).trailing * 2,
                                            "at least twice the old trailing-column slider, \(label)")
                XCTAssertEqual(deck.height, RemoteLayoutPolicy.landscapeVolumeThickness, label)
                XCTAssertGreaterThan(VolumeSliderGeometry.thumbDiameter(height: deck.height),
                                     VolumeSliderGeometry.thumbDiameter(height: RemoteLayoutPolicy.portraitVolumeThickness), label)
                XCTAssertEqual(deck.maxY, height, accuracy: 0.5, label)
                XCTAssertEqual(deck.minX, pad.minX, accuracy: 0.5, label)
                XCTAssertEqual(deck.maxX, width, accuracy: 0.5, label)
                XCTAssertGreaterThanOrEqual(pad.width, RemoteLayoutPolicy.landscapePadMinWidth - 0.5, label)
                XCTAssertGreaterThanOrEqual(pad.height, RemoteLayoutPolicy.padMinHeight(compact: false, isLandscape: true), label)
                XCTAssertFalse(deck.intersects(pad), label)
                for rect in frames.leading + frames.trailing {
                    XCTAssertFalse(rect.intersects(deck), label)
                }
            }
        }
    }

    func testShortLandscapeStagesShrinkTheDeckBeforeThePad() {
        XCTAssertEqual(RemoteLayoutPolicy.volumeDeckHeight(stageHeight: 400), 66)
        XCTAssertEqual(RemoteLayoutPolicy.volumeDeckHeight(stageHeight: 276), 66)
        XCTAssertEqual(RemoteLayoutPolicy.volumeDeckHeight(stageHeight: 270), 60)
        XCTAssertEqual(RemoteLayoutPolicy.volumeDeckHeight(stageHeight: 266), 56)
        XCTAssertEqual(RemoteLayoutPolicy.volumeDeckHeight(stageHeight: 200), 56)
        for height in [266, 270, 280, 300] as [CGFloat] {
            for width in stageWidths {
                let frames = androidStage(width: width, height: height)
                XCTAssertGreaterThanOrEqual(frames.pad?.height ?? 0, 199.5, "\(width)×\(height)")
                XCTAssertGreaterThanOrEqual(frames.deck?.height ?? 0, 56)
                XCTAssertGreaterThanOrEqual(VolumeSliderGeometry.thumbDiameter(height: frames.deck?.height ?? 0), 46)
            }
        }
    }

    func testAndroidAndSamsungShareThePadAndTheDeck() throws {
        for width in [520, 640, 812, 932] as [CGFloat] {
            for height in [266, 300, 340, 380] as [CGFloat] {
                let android = androidStage(width: width, height: height)
                let samsung = samsungStage(width: width, height: height)
                XCTAssertEqual(android.pad, samsung.pad, "\(width)×\(height)")
                XCTAssertEqual(android.deck, samsung.deck, "\(width)×\(height)")
                XCTAssertEqual(RemoteStageLayout.padRect(width: width, height: height), android.pad)
                // The Samsung TV group sits directly above the deck, one spacing clear of it.
                let deck = try XCTUnwrap(samsung.deck)
                XCTAssertEqual(samsung.trailing[1].maxY + 10, deck.minY, accuracy: 0.5)
            }
        }
    }

    func testPortraitSliderStaysBalanced() {
        XCTAssertEqual(RemoteLayoutPolicy.volumeThickness(compact: false), 60)
        XCTAssertEqual(RemoteLayoutPolicy.volumeThickness(compact: true), 56)
        XCTAssertGreaterThanOrEqual(VolumeSliderGeometry.thumbDiameter(height: RemoteLayoutPolicy.volumeThickness(compact: true)),
                                    44, "thumb stays a full touch target")
    }

    func testStagesWithoutADeckAreUnchanged() {
        let frames = RemoteStageLayout.frames(width: 844, height: 360,
                                              leading: [96], leadingBottom: [false],
                                              trailing: [114], trailingBottom: [false],
                                              hasPad: true, spacing: 10, columnSpacing: 14)
        XCTAssertNil(frames.deck)
        XCTAssertEqual(frames.pad?.height, 360)
    }
}
