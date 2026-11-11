import XCTest
import SwiftUI
@testable import GlassRemote

/// Continuation §F: Discover landscape header, hero artwork policy, full-bleed artwork and the
/// full-width landscape detail presentation.
final class Phase9DiscoverTests: XCTestCase {
    private let regions: [CGSize] = [CGSize(width: 932, height: 400), CGSize(width: 393, height: 560),
                                     CGSize(width: 844, height: 520), CGSize(width: 1194, height: 640),
                                     CGSize(width: 568, height: 300)]
    private let images: [CGSize] = [CGSize(width: 1920, height: 1080), CGSize(width: 680, height: 1000),
                                    CGSize(width: 3000, height: 1000), CGSize(width: 500, height: 500)]
    private let focals: [CGPoint] = [HeroArtworkPolicy.backdropFocal, HeroArtworkPolicy.posterFocal,
                                     CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: -3, y: 4)]

    // MARK: §F2 artwork policy

    func testFillAlwaysCoversTheRegion() {
        for region in regions { for image in images { for focal in focals {
            let r = HeroArtworkPolicy.fillRect(image: image, region: region, focal: focal)
            XCTAssertLessThanOrEqual(r.minX, 0.001, "\(image) in \(region)")
            XCTAssertLessThanOrEqual(r.minY, 0.001, "\(image) in \(region)")
            XCTAssertGreaterThanOrEqual(r.maxX, region.width - 0.001, "\(image) in \(region)")
            XCTAssertGreaterThanOrEqual(r.maxY, region.height - 0.001, "\(image) in \(region)")
        } } }
    }

    func testFillNeverStretches() {
        for region in regions { for image in images {
            let r = HeroArtworkPolicy.fillRect(image: image, region: region, focal: HeroArtworkPolicy.backdropFocal)
            XCTAssertEqual(r.width / r.height, image.width / image.height, accuracy: 0.001)
        } }
    }

    func testCropKeepsTheUpperPartAndStaysCentredSideways() {
        let region = CGSize(width: 932, height: 300)
        let image = CGSize(width: 1920, height: 1080)
        let r = HeroArtworkPolicy.fillRect(image: image, region: region, focal: HeroArtworkPolicy.backdropFocal)
        let hidden = r.height - region.height
        XCTAssertGreaterThan(hidden, 0)
        XCTAssertEqual(-r.minY, hidden * 0.3, accuracy: 0.01)
        XCTAssertLessThan(-r.minY, hidden / 2, "more is cut from the bottom than from the top")
        XCTAssertEqual(r.midX, region.width / 2, accuracy: 0.01)
    }

    func testPosterInAWideRegionIsShownWholeOnTheTrailingSide() {
        let region = CGSize(width: 932, height: 400)
        let poster = CGSize(width: 680, height: 1000)
        XCTAssertGreaterThan(HeroArtworkPolicy.cropShare(image: poster, region: region), HeroArtworkPolicy.maxPosterCrop)
        guard case .posterInset(let inset) = HeroArtworkPolicy.crop(image: poster, region: region) else {
            return XCTFail("a poster in a wide hero must not be cut to a band")
        }
        XCTAssertEqual(inset.size.width / inset.size.height, poster.width / poster.height, accuracy: 0.001)
        XCTAssertLessThanOrEqual(inset.topMargin + inset.size.height, region.height)
        XCTAssertLessThanOrEqual(inset.trailingMargin + inset.size.width, region.width)
        // Clear of the leading text column (46 % of the width at most).
        XCTAssertGreaterThan(region.width - inset.trailingMargin - inset.size.width, region.width * 0.46)
    }

    func testPosterInAPortraitRegionFillsWithTheTopKept() {
        let crop = HeroArtworkPolicy.crop(image: CGSize(width: 680, height: 1000), region: CGSize(width: 393, height: 560))
        XCTAssertEqual(crop, .fill(focal: HeroArtworkPolicy.posterFocal))
    }

    func testWideArtFillsWithTheBackdropFocal() {
        XCTAssertEqual(HeroArtworkPolicy.crop(image: CGSize(width: 1920, height: 1080), region: CGSize(width: 932, height: 400)),
                       .fill(focal: HeroArtworkPolicy.backdropFocal))
        XCTAssertEqual(HeroArtworkPolicy.crop(image: CGSize(width: 500, height: 500), region: CGSize(width: 932, height: 400)),
                       .fill(focal: HeroArtworkPolicy.backdropFocal))
    }

    func testPosterInsetCanBeTurnedOff() {
        let crop = HeroArtworkPolicy.crop(image: CGSize(width: 680, height: 1000), region: CGSize(width: 932, height: 400),
                                          allowsPosterInset: false)
        XCTAssertEqual(crop, .fill(focal: HeroArtworkPolicy.posterFocal))
    }

    func testMissingOrEmptySizesAreSafe() {
        let region = CGSize(width: 932, height: 400)
        XCTAssertEqual(HeroArtworkPolicy.crop(image: .zero, region: region), .fill(focal: HeroArtworkPolicy.backdropFocal))
        XCTAssertEqual(HeroArtworkPolicy.crop(image: CGSize(width: 680, height: 1000), region: .zero),
                       .fill(focal: HeroArtworkPolicy.posterFocal))
        for focal in focals {
            XCTAssertEqual(HeroArtworkPolicy.fillRect(image: .zero, region: region, focal: focal), CGRect(origin: .zero, size: region),
                           "a missing image falls back to the region whatever the focal point")
        }
        XCTAssertEqual(HeroArtworkPolicy.cropShare(image: .zero, region: region), 0)
    }

    // MARK: §F2 full-bleed artwork

    func testBleedOnlyAppliesInLandscape() {
        XCTAssertEqual(HorizontalBleed.resolve(isLandscape: false, safeLeading: 59, safeTrailing: 59), .zero)
        let bleed = HorizontalBleed.resolve(isLandscape: true, safeLeading: 59, safeTrailing: 47)
        XCTAssertEqual(bleed, HorizontalBleed(leading: 59, trailing: 47))
        XCTAssertEqual(bleed.total, 106)
        XCTAssertEqual(bleed.symmetric, 59)
        XCTAssertEqual(HorizontalBleed.resolve(isLandscape: true, safeLeading: -4, safeTrailing: -1), .zero)
    }

    func testBleedClipWidensSidewaysOnly() {
        let rect = CGRect(x: 0, y: 0, width: 800, height: 390)
        XCTAssertEqual(HorizontalBleed.clipRect(rect, bleed: 59), CGRect(x: -59, y: 0, width: 918, height: 390))
        XCTAssertEqual(HorizontalBleed.clipRect(rect, bleed: 0), rect)
        XCTAssertEqual(HorizontalBleed.clipRect(rect, bleed: -10), rect)
    }

    // MARK: §F3 detail presentation

    func testLandscapeDetailIsFullScreenAndPortraitKeepsTheSheet() {
        XCTAssertEqual(DetailPresentation.style(isLandscape: true), .fullScreen)
        XCTAssertEqual(DetailPresentation.style(isLandscape: false), .sheet)
    }

    func testRotatingWhilePresentedKeepsThePresentation() {
        XCTAssertEqual(DetailPresentation.next(current: .sheet, isPresenting: true, isLandscape: true), .sheet)
        XCTAssertEqual(DetailPresentation.next(current: .fullScreen, isPresenting: true, isLandscape: false), .fullScreen)
        XCTAssertEqual(DetailPresentation.next(current: .sheet, isPresenting: false, isLandscape: true), .fullScreen)
        XCTAssertEqual(DetailPresentation.next(current: .fullScreen, isPresenting: false, isLandscape: false), .sheet)
    }

    // MARK: §F1 header

    private func assertNoOverlap(_ f: DiscoverHeaderLayout.Frames, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(f.search.intersects(f.account), file: file, line: line)
        XCTAssertFalse(f.search.intersects(f.filter), file: file, line: line)
        XCTAssertFalse(f.filter.intersects(f.account), file: file, line: line)
    }

    func testPortraitHeaderKeepsSearchAndAccountAboveAFullWidthFilter() {
        for width: CGFloat in [343, 361, 398] {
            let f = DiscoverHeaderLayout.frames(width: width, isLandscape: false)
            assertNoOverlap(f)
            XCTAssertEqual(f.search.minX, 0)
            XCTAssertEqual(f.account.maxX, width)
            XCTAssertEqual(f.account.minX - f.search.maxX, DiscoverHeaderLayout.spacing, accuracy: 0.001)
            XCTAssertEqual(f.search.minY, f.account.minY)
            XCTAssertEqual(f.filter.width, width)
            XCTAssertGreaterThanOrEqual(f.filter.minY, f.search.maxY)
            XCTAssertEqual(f.height, f.filter.maxY)
        }
    }

    func testLandscapeHeaderIsOneGroupedRow() {
        for width: CGFloat in [480, 600, 700, 760, 1000] {
            let f = DiscoverHeaderLayout.frames(width: width, isLandscape: true)
            assertNoOverlap(f)
            XCTAssertEqual(f.height, DiscoverHeaderLayout.controlHeight)
            XCTAssertEqual(f.search.minX, 0)
            XCTAssertEqual(f.account.maxX, width, "account shortcut sits at the trailing edge")
            XCTAssertLessThan(f.search.maxX, f.filter.minX)
            XCTAssertLessThan(f.filter.maxX, f.account.minX)
            XCTAssertEqual(f.account.minX - f.filter.maxX, DiscoverHeaderLayout.groupSpacing, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(f.filter.minX - f.search.maxX, DiscoverHeaderLayout.groupSpacing)
            XCTAssertEqual(f.filter.midY, f.search.midY, accuracy: 0.001)
            XCTAssertLessThanOrEqual(f.search.width, DiscoverHeaderLayout.landscapeSearchMax)
            XCTAssertGreaterThan(f.search.width, 150)
            XCTAssertGreaterThanOrEqual(f.filter.width, DiscoverHeaderLayout.landscapeFilterMin)
            XCTAssertLessThanOrEqual(f.filter.width, DiscoverHeaderLayout.landscapeFilterMax)
        }
    }
}
