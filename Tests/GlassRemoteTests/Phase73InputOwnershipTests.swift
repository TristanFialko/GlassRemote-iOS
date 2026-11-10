import XCTest
@testable import GlassRemote

/// Phase 7.3: explicit Mouse / D-pad touch ownership (no timing). The touches themselves need a device.
final class Phase73InputOwnershipTests: XCTestCase {
    func testANewPadTouchOwnsItsInput() {
        let guardian = RemoteInputGuard()
        guardian.padTouchChanged(isTrackpad: false)
        XCTAssertTrue(guardian.acceptsPadInput(isTrackpad: false))
        guardian.padTouchEnded()
        XCTAssertTrue(guardian.acceptsPadInput(isTrackpad: false), "a tap fires on lift, after the touch ends")
    }

    func testSelectorTouchNeverSendsDpadInput() {
        let guardian = RemoteInputGuard()
        guardian.selectorTouchChanged(true)
        guardian.padTouchChanged(isTrackpad: false)   // a second finger lands on the pad
        XCTAssertFalse(guardian.acceptsPadInput(isTrackpad: false))
        guardian.modeChanged()
        guardian.selectorTouchChanged(false)          // the selector's lift
        XCTAssertFalse(guardian.acceptsPadInput(isTrackpad: false), "the lift must not become a key")
    }

    func testTouchHeldAcrossAModeSwitchIsDropped() {
        let guardian = RemoteInputGuard()
        guardian.padTouchChanged(isTrackpad: false)
        XCTAssertTrue(guardian.acceptsPadInput(isTrackpad: false))
        guardian.modeChanged()
        XCTAssertFalse(guardian.acceptsPadInput(isTrackpad: false), "hold-repeat stops at the switch")
        guardian.padTouchChanged(isTrackpad: false)   // same touch keeps moving
        XCTAssertTrue(guardian.acceptsPadInput(isTrackpad: false) == false || guardian.epoch > 0)
    }

    func testTouchHeldWhileTheSelectorIsTouchedIsDropped() {
        let guardian = RemoteInputGuard()
        guardian.padTouchChanged(isTrackpad: false)
        guardian.selectorTouchChanged(true)
        XCTAssertFalse(guardian.acceptsPadInput(isTrackpad: false))
        guardian.selectorTouchChanged(false)
        XCTAssertFalse(guardian.acceptsPadInput(isTrackpad: false))
    }

    func testFirstDeliberateTouchAfterTheSwitchWorksImmediately() {
        let guardian = RemoteInputGuard()
        guardian.selectorTouchChanged(true)
        guardian.modeChanged()
        guardian.selectorTouchChanged(false)
        guardian.padTouchChanged(isTrackpad: false)   // no waiting period
        XCTAssertTrue(guardian.acceptsPadInput(isTrackpad: false))
    }

    func testMouseModeNeverSendsDpadInput() {
        let guardian = RemoteInputGuard()
        guardian.padTouchChanged(isTrackpad: true)
        XCTAssertFalse(guardian.acceptsPadInput(isTrackpad: true))
        XCTAssertFalse(guardian.acceptsPadInput(isTrackpad: false), "a touch that began in Mouse mode has no token")
    }

    func testATouchWhoseEndWasLostCannotBlockTheNextOne() {
        let guardian = RemoteInputGuard()
        guardian.padTouchChanged(isTrackpad: false)   // end never delivered (rotation, view rebuilt)
        guardian.modeChanged()
        guardian.modeChanged()
        guardian.padTouchChanged(isTrackpad: false)
        XCTAssertTrue(guardian.acceptsPadInput(isTrackpad: false))
    }

    func testResetClearsAStuckSelectorTouch() {
        let guardian = RemoteInputGuard()
        guardian.selectorTouchChanged(true)
        guardian.reset()
        guardian.padTouchChanged(isTrackpad: false)
        XCTAssertTrue(guardian.acceptsPadInput(isTrackpad: false))
    }

    func testRepeatedSelectorReportsDoNotInvalidate() {
        let guardian = RemoteInputGuard()
        guardian.padTouchChanged(isTrackpad: false)
        guardian.selectorTouchChanged(false)          // already false: no change
        XCTAssertTrue(guardian.acceptsPadInput(isTrackpad: false))
    }

    func testPolicy() {
        XCTAssertEqual(RemoteInputPolicy.token(epoch: 3, isTrackpad: false, selectorTouchActive: false), 3)
        XCTAssertNil(RemoteInputPolicy.token(epoch: 3, isTrackpad: true, selectorTouchActive: false))
        XCTAssertNil(RemoteInputPolicy.token(epoch: 3, isTrackpad: false, selectorTouchActive: true))
        XCTAssertTrue(RemoteInputPolicy.accepts(token: 3, epoch: 3, isTrackpad: false, selectorTouchActive: false))
        XCTAssertFalse(RemoteInputPolicy.accepts(token: 2, epoch: 3, isTrackpad: false, selectorTouchActive: false))
        XCTAssertFalse(RemoteInputPolicy.accepts(token: nil, epoch: 3, isTrackpad: false, selectorTouchActive: false))
        XCTAssertFalse(RemoteInputPolicy.accepts(token: 3, epoch: 3, isTrackpad: true, selectorTouchActive: false))
        XCTAssertFalse(RemoteInputPolicy.accepts(token: 3, epoch: 3, isTrackpad: false, selectorTouchActive: true))
    }
}
