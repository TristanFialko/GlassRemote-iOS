import SwiftUI
import XCTest
@testable import GlassRemote

/// v6 §1: the dock's curves are Motion tokens (no one-off curves), and the mini-player's stale
/// re-check is one scheduled timeline entry instead of a sleeping loop. Complements the source audits
/// in `Phase9MotionTests`.
final class Phase9V6MotionRepairTests: XCTestCase {

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

    private func media(sampledAt: Date, state: Int = 3) -> MediaState {
        MediaState(package: "com.example.player", title: "Title", state: state, positionMs: 0, speed: 1,
                   sampledAt: sampledAt, actions: 0)
    }

    // MARK: Dock curves

    func testDockCurvesComeFromTheMotionLanguage() {
        XCTAssertEqual(TabSwitchPolicy.animation, Motion.tabFade)
        XCTAssertEqual(TabSwitchPolicy.fadeDuration, Motion.Durations.tabFade)
        XCTAssertEqual(NowPlayingPresentation.animation, Motion.presentation)
        XCTAssertEqual(NowPlayingPresentation.duration, Motion.Durations.presentation)
    }

    func testDockDurationsStayQuickAndOrdered() {
        XCTAssertGreaterThan(Motion.Durations.pressDim, 0)
        XCTAssertLessThan(Motion.Durations.pressDim, Motion.Durations.tabFade, "a press answers faster than a page switch")
        XCTAssertLessThan(Motion.Durations.tabFade, Motion.Durations.presentation)
        XCTAssertLessThanOrEqual(Motion.Durations.tabFade, 0.2)
        XCTAssertLessThanOrEqual(Motion.Durations.presentation, 0.35)
    }

    func testReduceMotionKeepsOnlyTheFade() {
        XCTAssertEqual(TabSwitchPolicy.switchAnimation(reduceMotion: true), Motion.tabFade)
        XCTAssertEqual(TabSwitchPolicy.switchAnimation(reduceMotion: false), Motion.tabFade)
        XCTAssertEqual(NowPlayingPresentation.presentationAnimation(reduceMotion: true), Motion.tabFade)
        XCTAssertEqual(NowPlayingPresentation.presentationAnimation(reduceMotion: false), Motion.presentation)
    }

    // MARK: Mini-player stale re-check

    func testStaleRecheckIsScheduledJustAfterTheStalePoint() throws {
        let sampled = Date(timeIntervalSince1970: 1_000_000)
        let session = media(sampledAt: sampled)
        let date = try XCTUnwrap(MiniPlayerPolicy.staleRecheckDate(media: session))
        XCTAssertEqual(date, sampled.addingTimeInterval(PlayerSessionPhase.staleAfter + MiniPlayerPolicy.recheckMargin))

        let justBefore = sampled.addingTimeInterval(PlayerSessionPhase.staleAfter - 0.01)
        XCTAssertTrue(MiniPlayerPolicy.isVisible(media: session, connected: true, connecting: false, now: justBefore),
                      "still live until the stale point")
        XCTAssertFalse(MiniPlayerPolicy.isVisible(media: session, connected: true, connecting: false, now: date),
                       "the scheduled re-check lands after the stale point, so it hides the bar")
    }

    func testRecheckScheduleHasOneFutureEntryOrNone() throws {
        let sampled = Date(timeIntervalSince1970: 2_000_000)
        let session = media(sampledAt: sampled)
        let date = try XCTUnwrap(MiniPlayerPolicy.staleRecheckDate(media: session))
        XCTAssertEqual(MiniPlayerPolicy.recheckSchedule(media: session, now: sampled), [date])
        XCTAssertEqual(MiniPlayerPolicy.recheckSchedule(media: session, now: date), [], "nothing left once it is stale")
        XCTAssertEqual(MiniPlayerPolicy.recheckSchedule(media: session, now: date.addingTimeInterval(60)), [])
        XCTAssertNil(MiniPlayerPolicy.staleRecheckDate(media: .idle))
        XCTAssertEqual(MiniPlayerPolicy.recheckSchedule(media: .idle, now: sampled), [], "no session, nothing to expire")
    }

    func testRecheckMarginIsShort() {
        XCTAssertGreaterThan(MiniPlayerPolicy.recheckMargin, 0)
        XCTAssertLessThanOrEqual(MiniPlayerPolicy.recheckMargin, 1, "a stale bar disappears promptly")
        XCTAssertEqual(MiniPlayerPolicy.recheckMargin, TimeInterval(MiniPlayerPolicy.recheckNanos) / 1_000_000_000)
    }

    // MARK: Source guard

    func testMiniPlayerProbeIsDrivenByAnExplicitTimeline() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("GlassRemote/RootPagerView.swift")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            throw XCTSkip("sources not readable from the test host")
        }
        XCTAssertTrue(text.contains("TimelineView(.explicit(MiniPlayerPolicy.recheckSchedule("))
        XCTAssertTrue(text.contains("Motion.pressDim"), "the dock's press dim is a Motion token")
    }
}
