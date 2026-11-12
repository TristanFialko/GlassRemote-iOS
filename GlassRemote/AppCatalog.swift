import Foundation

/// One launchable TV app found on the box: its package and the activity component to start.
struct LaunchableActivity: Equatable, Hashable {
    let package: String
    /// `pkg/.Activity` or `pkg/full.Activity`, exactly as Android printed it (always validated).
    let component: String
    /// Found through `LEANBACK_LAUNCHER` (a real TV app) rather than the phone `LAUNCHER` category.
    let isLeanback: Bool
}

/// Pure rules for the Apps launcher's catalogue (UX-004): discovery parsing, the curated/discovered
/// merge, launch command construction and launch-outcome parsing. Unit tested in RemediationAppsTests.
enum AppCatalog {
    // MARK: Settings tile

    /// Not a valid Android package name (it has dashes), so it can never collide with a real app
    /// or reach the `monkey -p` fallback.
    static let settingsPackage = "glassremote-android-tv-settings"
    static let settingsApp = TVApp(name: "Android TV Settings", package: settingsPackage, asset: "")

    /// Discovered apps have no bundled artwork; their tiles draw a generic icon.
    static func hasArtwork(_ app: TVApp) -> Bool { !app.asset.isEmpty }
    static func isSettings(_ app: TVApp) -> Bool { app.package == settingsPackage }

    // MARK: Discovery

    static let leanbackMarker = "GLASSREMOTE_SECTION_LEANBACK"
    static let launcherMarker = "GLASSREMOTE_SECTION_LAUNCHER"

    /// One shell round trip: installed packages, then TV (leanback) launch activities, then phone
    /// launcher activities, separated by marker lines.
    static let discoveryCommand = [
        "pm list packages 2>&1",
        "echo \(leanbackMarker)",
        "cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LEANBACK_LAUNCHER 2>&1",
        "echo \(launcherMarker)",
        "cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER 2>&1"
    ].joined(separator: "; ")

    struct Scan: Equatable {
        var packages: Set<String> = []
        var leanback: [String] = []
        var launcher: [String] = []
    }

    static func parseScan(_ output: String) -> Scan {
        enum Section { case packages, leanback, launcher }
        var section = Section.packages
        var scan = Scan()
        var leanbackText = ""
        var launcherText = ""
        for raw in output.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == leanbackMarker { section = .leanback; continue }
            if line == launcherMarker { section = .launcher; continue }
            switch section {
            case .packages:
                if line.hasPrefix("package:") {
                    let name = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { scan.packages.insert(name) }
                }
            case .leanback: leanbackText += line + "\n"
            case .launcher: launcherText += line + "\n"
            }
        }
        scan.leanback = parseComponents(leanbackText)
        scan.launcher = parseComponents(launcherText)
        return scan
    }

    /// Valid components from `query-activities --brief` output, in order, without duplicates.
    /// Headers ("2 activities found:", "Activity #0:"), "priority=… match=…" detail lines,
    /// "No activities found" and blank lines all fail validation and are skipped.
    static func parseComponents(_ output: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in output.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard isValidComponent(line), seen.insert(line).inserted else { continue }
            result.append(line)
        }
        return result
    }

    /// One activity per package. A leanback activity always wins; a phone-launcher-only package is
    /// shown only when it does not look like part of the system image.
    static func resolve(leanback: [String], launcher: [String]) -> [LaunchableActivity] {
        var result: [LaunchableActivity] = []
        var packages = Set<String>()
        for (components, isLeanback) in [(leanback, true), (launcher, false)] {
            for component in components {
                guard let package = Self.package(ofComponent: component),
                      !packages.contains(package),
                      !hiddenPackages.contains(package),
                      isLeanback || !isSystemPackage(package) else { continue }
                packages.insert(package)
                result.append(LaunchableActivity(package: package, component: component, isLeanback: isLeanback))
            }
        }
        return result
    }

    /// Already covered by the fixed Settings tile.
    static let hiddenPackages: Set<String> = ["com.android.tv.settings", "com.android.settings"]

    static let systemPrefixes = [
        "android.", "com.android.", "com.google.android.", "com.mediatek.", "com.amlogic.", "com.droidlogic.",
        "com.realtek.", "com.rockchip.", "com.hisilicon.", "com.qualcomm.", "com.qti.", "org.codeaurora.",
        "com.nvidia.", "com.sec.", "com.samsung.", "com.sony.", "com.xiaomi.", "com.mitv.", "com.huawei."
    ]

    static func isSystemPackage(_ package: String) -> Bool {
        package == "android" || systemPrefixes.contains { package.hasPrefix($0) }
    }

    // MARK: Merge

    /// The nine curated apps first (unchanged, whether or not they were found), then discovered
    /// apps that are not curated, by name, then the Settings tile.
    static func launcherApps(curated: [TVApp], discovered: [LaunchableActivity]) -> [TVApp] {
        let curatedPackages = Set(curated.map(\.package))
        let extras = discovered
            .filter { !curatedPackages.contains($0.package) && $0.package != settingsPackage }
            .map { TVApp(name: displayName(forPackage: $0.package), package: $0.package, asset: "") }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return curated + extras + [settingsApp]
    }

    static func component(for package: String, in discovered: [LaunchableActivity]) -> String? {
        discovered.first { $0.package == package }?.component
    }

    private static let labelNoise: Set<String> = [
        "com", "org", "net", "io", "tv", "co", "me", "de", "uk", "app", "apps", "android", "androidtv", "atv",
        "leanback", "launcher", "client", "mobile", "release"
    ]

    /// `query-activities --brief` gives no labels, so discovered tiles use a cleaned package name:
    /// "com.stremio.one" → "Stremio One", "org.videolan.vlc" → "Videolan VLC".
    static func displayName(forPackage package: String) -> String {
        let parts = package.split(separator: ".").map(String.init)
        var words = parts.filter { !labelNoise.contains($0.lowercased()) }
        if words.isEmpty { words = [parts.last ?? package] }
        return words.map { word in
            // Short vowel-less words are acronyms ("vlc", "mx"); everything else is capitalised.
            if word.count <= 3, !word.lowercased().contains(where: { "aeiouy".contains($0) }) { return word.uppercased() }
            return word.prefix(1).uppercased() + String(word.dropFirst())
        }.joined(separator: " ")
    }

    // MARK: Launch

    private static let nameCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.")

    /// Strict allow-list equivalent to `^[A-Za-z0-9_.]+/[A-Za-z0-9_.$]+$` (checked character by
    /// character, so a trailing newline can't slip past a regex anchor). Rejects spaces, quotes, `;`,
    /// `$(`, `&`, `|` and anything else a shell would act on.
    static func isValidComponent(_ value: String) -> Bool {
        let halves = value.split(separator: "/", omittingEmptySubsequences: false)
        guard halves.count == 2, !halves[0].isEmpty, !halves[1].isEmpty else { return false }
        return halves[0].allSatisfy { nameCharacters.contains($0) }
            && halves[1].allSatisfy { nameCharacters.contains($0) || $0 == "$" }
    }

    /// `^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$`: at least two non-empty dot-separated segments.
    static func isValidPackage(_ value: String) -> Bool {
        let segments = value.split(separator: ".", omittingEmptySubsequences: false)
        return segments.count >= 2 && segments.allSatisfy { segment in
            !segment.isEmpty && segment.allSatisfy { nameCharacters.contains($0) }
        }
    }

    static func package(ofComponent component: String) -> String? {
        guard isValidComponent(component), let slash = component.firstIndex(of: "/") else { return nil }
        let package = String(component[..<slash])
        return isValidPackage(package) ? package : nil
    }

    enum LaunchMethod: Equatable {
        case settings
        case component(String)
        case monkey(String)

        var usesActivityManager: Bool {
            if case .monkey = self { return false }
            return true
        }
    }

    static let exitMarker = "GLASSREMOTE_LAUNCH_EXIT:"

    /// How to start `app`: Settings by intent, a resolved component with `am start -n`, else the
    /// old `monkey -p` path. Nil when neither the component nor the package is safe to put in a shell.
    static func launchMethod(for app: TVApp, component: String?) -> LaunchMethod? {
        if isSettings(app) { return .settings }
        if let component, package(ofComponent: component) == app.package { return .component(component) }
        return isValidPackage(app.package) ? .monkey(app.package) : nil
    }

    /// The `sh -c` script for `method`. Every value is validated and quoted with `TVShell.quote`.
    @MainActor
    static func launchCommand(_ method: LaunchMethod) -> String {
        let start: String
        switch method {
        case .settings: start = "am start -a android.settings.SETTINGS"
        case .component(let component): start = "am start -n \(TVShell.quote(component))"
        case .monkey(let package): start = "monkey -p \(TVShell.quote(package)) 1"
        }
        return "\(start) 2>&1; rc=$?; echo \(exitMarker)$rc"
    }

    /// Force-stop half of Restart. Nil for Settings, which is simply relaunched.
    @MainActor
    static func forceStopCommand(for app: TVApp) -> String? {
        guard !isSettings(app), isValidPackage(app.package) else { return nil }
        return "am force-stop \(TVShell.quote(app.package)); sleep 1"
    }

    enum LaunchOutcome: Equatable {
        case accepted
        case failed(String)
    }

    static func launchOutcome(_ output: String, method: LaunchMethod) -> LaunchOutcome {
        var exitCode: Int?
        var lines: [String] = []
        for raw in output.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix(exitMarker) {
                exitCode = Int(line.dropFirst(exitMarker.count))
            } else if !line.isEmpty {
                lines.append(line)
            }
        }
        let body = lines.joined(separator: " ")
        let detail = String((body.isEmpty ? "exit code \(exitCode.map { String($0) } ?? "missing")" : body).prefix(200))

        if method.usesActivityManager {
            // `am start` can exit 0 and still print an error, so its output decides first.
            if let error = lines.first(where: { line in
                line.hasPrefix("Error") || line.contains("Exception")
                    || line.localizedCaseInsensitiveContains("unable to resolve")
            }) {
                return .failed(String(error.prefix(200)))
            }
            return exitCode == 0 ? .accepted : .failed(detail)
        }
        // Monkey: trust the exit marker, but its abort messages always mean failure.
        if exitCode == 0,
           !body.localizedCaseInsensitiveContains("monkey aborted"),
           !body.localizedCaseInsensitiveContains("no activities found") {
            return .accepted
        }
        return .failed(detail)
    }
}
