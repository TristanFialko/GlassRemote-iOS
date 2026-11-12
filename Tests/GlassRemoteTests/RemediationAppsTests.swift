import XCTest
@testable import GlassRemote

/// Audit remediation: UX-004 app discovery/launch, BUG-019/020/023 keyboard, SEC-002 text history.
final class RemediationAppDiscoveryTests: XCTestCase {
    private let briefFixture = """
    2 activities found:
      Activity #0:
        priority=0 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=false
        com.google.android.youtube.tv/com.google.android.apps.youtube.tv.activity.ShellActivity

      Activity #1:
        com.stremio.one/.MainActivity

    """

    func testParsesBothComponentFormsAndSkipsHeadersAndBlankLines() {
        XCTAssertEqual(AppCatalog.parseComponents(briefFixture), [
            "com.google.android.youtube.tv/com.google.android.apps.youtube.tv.activity.ShellActivity",
            "com.stremio.one/.MainActivity"
        ])
    }

    func testNoActivitiesFoundParsesToNothing() {
        XCTAssertEqual(AppCatalog.parseComponents("No activities found\n"), [])
        XCTAssertEqual(AppCatalog.parseComponents(""), [])
        XCTAssertEqual(AppCatalog.parseComponents("\n\n   \n"), [])
    }

    func testDuplicateComponentsAreListedOnce() {
        XCTAssertEqual(AppCatalog.parseComponents("com.a.b/.Main\ncom.a.b/.Main\n"), ["com.a.b/.Main"])
    }

    func testScanSplitsPackagesLeanbackAndLauncherSections() {
        let output = """
        package:com.netflix.ninja
        package:com.stremio.one
        \(AppCatalog.leanbackMarker)
        \(briefFixture)
        \(AppCatalog.launcherMarker)
        1 activities found:
          Activity #0:
            org.videolan.vlc/.StartActivity
        """
        let scan = AppCatalog.parseScan(output)
        XCTAssertEqual(scan.packages, ["com.netflix.ninja", "com.stremio.one"])
        XCTAssertEqual(scan.leanback.count, 2)
        XCTAssertEqual(scan.launcher, ["org.videolan.vlc/.StartActivity"])
    }

    func testDiscoveryIsOneCommandForBothCategories() {
        let command = AppCatalog.discoveryCommand
        XCTAssertTrue(command.contains("pm list packages"))
        XCTAssertTrue(command.contains("cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LEANBACK_LAUNCHER"))
        XCTAssertTrue(command.contains("cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER"))
    }

    func testLeanbackActivityWinsOverLauncherForTheSamePackage() {
        let apps = AppCatalog.resolve(leanback: ["com.stremio.one/.TvActivity"],
                                      launcher: ["com.stremio.one/.PhoneActivity"])
        XCTAssertEqual(apps, [LaunchableActivity(package: "com.stremio.one", component: "com.stremio.one/.TvActivity",
                                                 isLeanback: true)])
    }

    func testSystemPackagesNeedALeanbackActivity() {
        let apps = AppCatalog.resolve(
            leanback: ["com.google.android.youtube.tv/com.google.android.apps.youtube.tv.activity.ShellActivity"],
            launcher: ["com.android.documentsui/.LauncherActivity", "com.droidlogic.otaupgrade/.Main",
                       "com.google.android.gms/.Settings", "org.videolan.vlc/.StartActivity"])
        XCTAssertEqual(apps.map(\.package), ["com.google.android.youtube.tv", "org.videolan.vlc"])
        XCTAssertTrue(AppCatalog.isSystemPackage("com.android.vending"))
        XCTAssertFalse(AppCatalog.isSystemPackage("com.stremio.one"))
    }

    func testSettingsPackagesAreLeftToTheSettingsTile() {
        let apps = AppCatalog.resolve(leanback: ["com.android.tv.settings/.MainSettings"], launcher: [])
        XCTAssertTrue(apps.isEmpty)
    }

    func testComponentValidationRejectsShellSyntax() {
        for bad in ["com.a/.B;reboot", "com.a/.B C", "com.a/'B'", "com.a/\"B\"", "com.a/$(reboot)", "com.a/`id`",
                    "com.a/.B\n", "com.a/.B|sh", "com.a/.B&", "", "/x", "com.a/", "com.a/b/c", "com.a"] {
            XCTAssertFalse(AppCatalog.isValidComponent(bad), "accepted \(bad)")
        }
        XCTAssertTrue(AppCatalog.isValidComponent("com.a/.Main"))
        XCTAssertTrue(AppCatalog.isValidComponent("com.a/com.a.Main$Inner"))
        XCTAssertNil(AppCatalog.package(ofComponent: "nodot/.Main"))
        XCTAssertEqual(AppCatalog.package(ofComponent: "com.a.b/.Main"), "com.a.b")
        XCTAssertFalse(AppCatalog.isValidPackage("com.a;reboot"))
        XCTAssertFalse(AppCatalog.isValidPackage(AppCatalog.settingsPackage))
    }

    func testDisplayNameFromPackage() {
        XCTAssertEqual(AppCatalog.displayName(forPackage: "com.stremio.one"), "Stremio One")
        XCTAssertEqual(AppCatalog.displayName(forPackage: "org.videolan.vlc"), "Videolan VLC")
        XCTAssertFalse(AppCatalog.displayName(forPackage: "com.android.tv").isEmpty)
    }

    func testActivityManagerOutcomes() {
        let component = AppCatalog.LaunchMethod.component("com.a/.B")
        XCTAssertEqual(AppCatalog.launchOutcome("Starting: Intent { cmp=com.a/.B }\nGLASSREMOTE_LAUNCH_EXIT:0", method: component),
                       .accepted)
        XCTAssertEqual(AppCatalog.launchOutcome(
            "Starting: Intent { cmp=com.a/.B }\nWarning: Activity not started, its current task has been brought to the front\nGLASSREMOTE_LAUNCH_EXIT:0",
            method: component), .accepted)
        XCTAssertEqual(AppCatalog.launchOutcome(
            "Starting: Intent { cmp=com.a/.B }\nError type 3\nError: Activity class {com.a/com.a.B} does not exist.\nGLASSREMOTE_LAUNCH_EXIT:0",
            method: component), .failed("Error type 3"))
        if case .accepted = AppCatalog.launchOutcome(
            "java.lang.SecurityException: Permission Denial: starting Intent\nGLASSREMOTE_LAUNCH_EXIT:255", method: component) {
            XCTFail("an exception must fail the launch")
        }
        if case .accepted = AppCatalog.launchOutcome("Unable to resolve Intent { act=android.settings.SETTINGS }\nGLASSREMOTE_LAUNCH_EXIT:0",
                                                     method: .settings) {
            XCTFail("an unresolved intent must fail the launch")
        }
        if case .accepted = AppCatalog.launchOutcome("Starting: Intent { cmp=com.a/.B }", method: component) {
            XCTFail("a missing exit marker is not success")
        }
    }

    func testMonkeyOutcomes() {
        let monkey = AppCatalog.LaunchMethod.monkey("com.a.b")
        XCTAssertEqual(AppCatalog.launchOutcome("Events injected: 1\nGLASSREMOTE_LAUNCH_EXIT:0", method: monkey), .accepted)
        if case .accepted = AppCatalog.launchOutcome("** No activities found to run, monkey aborted.\nGLASSREMOTE_LAUNCH_EXIT:252",
                                                     method: monkey) {
            XCTFail("monkey abort must fail the launch")
        }
    }
}

@MainActor
final class RemediationAppLaunchTests: XCTestCase {
    func testLaunchCommandsAreQuotedAndMarked() {
        XCTAssertEqual(AppCatalog.launchCommand(.component("com.stremio.one/.MainActivity")),
                       "am start -n 'com.stremio.one/.MainActivity' 2>&1; rc=$?; echo GLASSREMOTE_LAUNCH_EXIT:$rc")
        XCTAssertEqual(AppCatalog.launchCommand(.monkey("com.netflix.ninja")),
                       "monkey -p 'com.netflix.ninja' 1 2>&1; rc=$?; echo GLASSREMOTE_LAUNCH_EXIT:$rc")
        XCTAssertEqual(AppCatalog.launchCommand(.settings),
                       "am start -a android.settings.SETTINGS 2>&1; rc=$?; echo GLASSREMOTE_LAUNCH_EXIT:$rc")
        XCTAssertEqual(AppCatalog.forceStopCommand(for: TVApp(name: "Netflix", package: "com.netflix.ninja", asset: "netflix")),
                       "am force-stop 'com.netflix.ninja'; sleep 1")
        XCTAssertNil(AppCatalog.forceStopCommand(for: AppCatalog.settingsApp))
    }

    func testLaunchMethodPrefersAResolvedComponentThenMonkey() {
        let netflix = TVApp(name: "Netflix", package: "com.netflix.ninja", asset: "netflix")
        XCTAssertEqual(AppCatalog.launchMethod(for: netflix, component: "com.netflix.ninja/.MainActivity"),
                       .component("com.netflix.ninja/.MainActivity"))
        XCTAssertEqual(AppCatalog.launchMethod(for: netflix, component: nil), .monkey("com.netflix.ninja"))
        // A component for another package (or an unsafe one) is never used.
        XCTAssertEqual(AppCatalog.launchMethod(for: netflix, component: "com.evil.app/.Main"), .monkey("com.netflix.ninja"))
        XCTAssertEqual(AppCatalog.launchMethod(for: netflix, component: "com.netflix.ninja/.A;reboot"), .monkey("com.netflix.ninja"))
        XCTAssertEqual(AppCatalog.launchMethod(for: AppCatalog.settingsApp, component: nil), .settings)
        XCTAssertNil(AppCatalog.launchMethod(for: TVApp(name: "Bad", package: "bad;pkg", asset: ""), component: nil))
    }

    func testMergeKeepsTheNineCuratedTilesThenDiscoveredThenSettings() {
        let curated = RemoteModel().apps
        XCTAssertEqual(curated.count, 9)
        let discovered = AppCatalog.resolve(
            leanback: ["com.google.android.youtube.tv/com.google.android.apps.youtube.tv.activity.ShellActivity",
                       "com.stremio.one/.MainActivity"],
            launcher: ["org.videolan.vlc/.StartActivity"])
        let apps = AppCatalog.launcherApps(curated: curated, discovered: discovered)

        XCTAssertEqual(Array(apps.prefix(9)).map(\.package), curated.map(\.package))
        XCTAssertEqual(Array(apps.prefix(9)).map(\.asset), curated.map(\.asset))
        XCTAssertEqual(apps.filter { $0.package == "com.google.android.youtube.tv" }.count, 1, "curated tile reused")
        XCTAssertEqual(apps.dropFirst(9).dropLast().map(\.name), ["Stremio One", "Videolan VLC"])
        XCTAssertTrue(apps.dropFirst(9).allSatisfy { !AppCatalog.hasArtwork($0) })
        XCTAssertEqual(apps.last?.package, AppCatalog.settingsPackage)
        XCTAssertEqual(apps.last?.name, "Android TV Settings")
        XCTAssertEqual(Set(apps.map(\.id)).count, apps.count, "ids stay unique")
    }

    func testSettingsTileIsPresentWithoutDiscovery() {
        let apps = AppCatalog.launcherApps(curated: RemoteModel().apps, discovered: [])
        XCTAssertEqual(apps.count, 10)
        XCTAssertTrue(apps.contains { AppCatalog.isSettings($0) })
    }

    func testShortcutsStillResolveEveryCuratedApp() {
        let curated = RemoteModel().apps
        for choice in [TVAppChoice.netflix, .youtube, .nuvio, .retroarch, .primeVideo, .disney, .sunshine, .spotify, .rhenium] {
            XCTAssertNotNil(curated.first { $0.asset == choice.assetName }, "\(choice) lost its tile")
        }
    }
}

final class RemediationKeyboardTests: XCTestCase {
    func testLongLiveTypingIsSplitNotTruncated() {
        let long = String(repeating: "a", count: 1000)
        var sent = ""
        var writes: [Int] = []
        var guardCount = 0
        while sent != long, guardCount < 10 {
            guardCount += 1
            let step = LiveTypingDiff.step(from: sent, to: long)
            XCTAssertLessThanOrEqual(step.added.count, VirtualKeyboard.liveTypingLimit)
            writes.append(step.added.count)
            sent = step.delivered
        }
        XCTAssertEqual(sent, long)
        XCTAssertEqual(writes, [400, 400, 200])
    }

    func testLongDeletionIsSplit() {
        let long = String(repeating: "a", count: 900)
        let first = LiveTypingDiff.step(from: long, to: "")
        XCTAssertEqual(first.backspaces, 400)
        XCTAssertTrue(first.partial)
        XCTAssertEqual(first.delivered.count, 500)
        let second = LiveTypingDiff.step(from: first.delivered, to: "")
        XCTAssertEqual(second.backspaces, 400)
        let third = LiveTypingDiff.step(from: second.delivered, to: "")
        XCTAssertEqual(third.backspaces, 100)
        XCTAssertFalse(third.partial)
        XCTAssertEqual(third.delivered, "")
    }

    func testShortEditIsOneCompleteStep() {
        let step = LiveTypingDiff.step(from: "ab", to: "abc")
        XCTAssertEqual(step, LiveTypingDiff.Step(backspaces: 0, added: "c", delivered: "abc", partial: false))
        XCTAssertEqual(VirtualKeyboard.liveTypingLimit, 400)
    }

    func testHistoryToggleClearsStoredText() throws {
        let suite = "RemediationAppsTests.history"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertTrue(KeyboardHistory.remembers(defaults), "on by default, as before")
        KeyboardHistory.save(["wifi password"], defaults)
        XCTAssertEqual(KeyboardHistory.load(defaults), ["wifi password"])

        KeyboardHistory.setRemembers(false, defaults)
        XCTAssertNil(defaults.stringArray(forKey: KeyboardHistory.itemsKey), "turning it off deletes stored text")
        XCTAssertEqual(KeyboardHistory.load(defaults), [])
        KeyboardHistory.save(["secret"], defaults)
        XCTAssertNil(defaults.stringArray(forKey: KeyboardHistory.itemsKey), "nothing is stored while off")
        XCTAssertEqual(KeyboardHistory.recording("secret", in: [], remembering: false), [])
    }

    func testHistoryRecordingIsMostRecentFirstWithoutDuplicates() {
        let items = (1...8).map { "t\($0)" }
        let recorded = KeyboardHistory.recording("t3", in: items, remembering: true)
        XCTAssertEqual(recorded.first, "t3")
        XCTAssertEqual(recorded.filter { $0 == "t3" }.count, 1)
        XCTAssertEqual(KeyboardHistory.recording("new", in: items, remembering: true).count, KeyboardHistory.limit)
    }
}

@MainActor
final class RemediationKeyOrderingTests: XCTestCase {
    private final class Recorder: @unchecked Sendable { var items: [Int] = [] }

    func testBarrierWaitsForEverythingQueuedBeforeIt() async {
        let queue = TaskQueue()
        let recorder = Recorder()
        queue.enqueue {
            await Task.yield()
            recorder.items.append(1)
        }
        queue.enqueue { recorder.items.append(2) }
        await queue.barrier().value
        XCTAssertEqual(recorder.items, [1, 2])
    }

    private func source(_ file: String) throws -> String {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard let text = try? String(contentsOf: repo.appendingPathComponent(file), encoding: .utf8) else {
            throw XCTSkip("app sources are not readable from the test run")
        }
        return text
    }

    /// BUG-023: BACK/HOME wait (bounded) for queued arrow reports; they stay on ADB keyevents (not UHID).
    func testBackAndHomeWaitForQueuedArrows() throws {
        let model = try source("GlassRemote/RemoteModel.swift")
        XCTAssertTrue(model.contains("keyboard.pendingWrites()"))
        XCTAssertTrue(model.contains("withDeadline(VirtualKeyboard.orderingDeadline)"))
        XCTAssertEqual(VirtualKeyboard.routedKeys, ["UP", "DOWN", "LEFT", "RIGHT", "OK"])
    }

    /// BUG-020: no status promises an ADB fallback, and live text never becomes a "TEXT" button press.
    func testKeyboardCopyNoLongerPromisesAnADBFallback() throws {
        let keyboard = try source("GlassRemote/VirtualKeyboard.swift")
        XCTAssertFalse(keyboard.contains("ADB fallback active"))
        XCTAssertFalse(keyboard.contains("key: \"TEXT\""))
        XCTAssertTrue(keyboard.contains("onWriteFailure"))
    }
}
