import XCTest
@testable import GlassRemote

// Phase 9 continuation §B: profiles and add-ons audit. Phase 7 and 7.1 already cover install,
// duplicates, several Torrentio configurations side by side, replace, purge and a single migration.
// These tests close the remaining gaps: migration is idempotent, mixed lists migrate only what is
// legacy, a legacy record without a Keychain item never invents a link, purge reaches records that
// were never loaded, Keychain accounts are scoped by profile and install, and the transport-security
// baseline (no arbitrary-loads exception; plain http only on the local network).

@MainActor
final class Phase9AddonAuditTests: XCTestCase {
    private let legacyLink = "https://legacy.example.com/token=abc/manifest.json"
    private let secondLink = "https://second.example.com/config=xyz/manifest.json"

    private func tempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("p9b-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func listURL(_ dir: URL, _ profile: UUID) -> URL {
        dir.appendingPathComponent("addons-\(profile.uuidString).json")
    }

    private func makeStore(_ dir: URL, _ secrets: AddonSecrets) -> AddonStore {
        // No network is used by these tests; an ephemeral session keeps them off the shared one.
        AddonStore(directory: dir, client: AddonClient(session: URLSession(configuration: .ephemeral)), secrets: secrets)
    }

    private func manifest(_ id: String, _ name: String) -> String {
        #"{"id":"\#(id)","version":"1.0.0","name":"\#(name)","types":["movie"],"catalogs":[],"resources":["stream"]}"#
    }

    /// A record saved before install ids existed (no `installID`).
    private func legacyRecord(_ manifest: String, display: String, enabled: Bool) -> String {
        #"{"manifest":\#(manifest),"displayURL":"\#(display)","enabled":\#(enabled),"installedAt":700000000,"refreshedAt":700000000}"#
    }

    /// A current record with its own install id.
    private func modernRecord(_ manifest: String, id: UUID, display: String) -> String {
        #"{"installID":"\#(id.uuidString)","manifest":\#(manifest),"displayURL":"\#(display)","enabled":true,"installedAt":700000001,"refreshedAt":700000001}"#
    }

    private func write(_ records: [String], to url: URL) throws {
        try Data(("[" + records.joined(separator: ",") + "]").utf8).write(to: url)
    }

    private var legacyManifest: String { manifest("org.legacy", "Legacy") }
    private var secondManifest: String { manifest("org.second", "Second") }

    func testMigrationRunsOnceAndRepeatedLoadsChangeNothing() throws {
        let dir = try tempDirectory()
        let profile = UUID()
        let file = listURL(dir, profile)
        try write([legacyRecord(legacyManifest, display: "legacy.example.com/\u{2026}", enabled: true)], to: file)
        let secrets = AddonSecrets.memory()
        secrets.write(AddonStore.account(profile, "org.legacy"), legacyLink)

        let store = makeStore(dir, secrets)
        store.load(profile: profile)
        let id = try XCTUnwrap(store.addons.first?.id)
        let afterFirst = try Data(contentsOf: file)

        // Loading again (same store) keeps the id and does not rewrite a clean list.
        store.load(profile: profile)
        XCTAssertEqual(store.addons.map(\.id), [id])
        XCTAssertEqual(try Data(contentsOf: file), afterFirst)

        // A relaunch keeps the id, the link and the file.
        let relaunched = makeStore(dir, secrets)
        relaunched.load(profile: profile)
        XCTAssertEqual(relaunched.addons.map(\.id), [id])
        XCTAssertNil(relaunched.addons.first?.legacySecretKey)
        XCTAssertEqual(relaunched.addons.first.flatMap { relaunched.transportURL(for: $0) }?.absoluteString, legacyLink)
        XCTAssertEqual(try Data(contentsOf: file), afterFirst)

        XCTAssertNil(secrets.read(AddonStore.account(profile, "org.legacy")), "The old Keychain item stays gone")
        XCTAssertEqual(secrets.read(AddonStore.account(profile, id)), legacyLink)

        let saved = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(saved.contains("token=abc"), "The full link is never written to the list")
        XCTAssertFalse(saved.contains("legacySecretKey"))
        XCTAssertTrue(saved.contains(id))
    }

    func testMixedListMigratesOnlyTheLegacyRecordAndKeepsOrder() throws {
        let dir = try tempDirectory()
        let profile = UUID()
        let modernID = UUID()
        try write([
            modernRecord(secondManifest, id: modernID, display: "second.example.com/\u{2026}"),
            legacyRecord(legacyManifest, display: "legacy.example.com/\u{2026}", enabled: false),
        ], to: listURL(dir, profile))
        let secrets = AddonSecrets.memory()
        secrets.write(AddonStore.account(profile, modernID.uuidString), secondLink)
        secrets.write(AddonStore.account(profile, "org.legacy"), legacyLink)

        let store = makeStore(dir, secrets)
        store.load(profile: profile)
        XCTAssertEqual(store.addons.map(\.manifestID), ["org.second", "org.legacy"], "Order is kept")
        XCTAssertEqual(store.addons[0].id, modernID.uuidString, "A current record keeps its install id")
        XCTAssertNotEqual(store.addons[1].id, "org.legacy")
        XCTAssertTrue(store.addons[0].enabled)
        XCTAssertFalse(store.addons[1].enabled, "Settings carry over")
        XCTAssertEqual(store.transportURL(for: store.addons[0])?.absoluteString, secondLink)
        XCTAssertEqual(store.transportURL(for: store.addons[1])?.absoluteString, legacyLink)
        XCTAssertEqual(secrets.read(AddonStore.account(profile, modernID.uuidString)), secondLink, "The current link is untouched")
        XCTAssertNil(secrets.read(AddonStore.account(profile, "org.legacy")))

        let relaunched = makeStore(dir, secrets)
        relaunched.load(profile: profile)
        XCTAssertEqual(relaunched.addons.map(\.id), store.addons.map(\.id))
    }

    func testLegacyRecordWithoutAKeychainItemMigratesWithoutInventingALink() throws {
        let dir = try tempDirectory()
        let profile = UUID()
        try write([legacyRecord(legacyManifest, display: "legacy.example.com", enabled: true)], to: listURL(dir, profile))
        let secrets = AddonSecrets.memory()

        let store = makeStore(dir, secrets)
        store.load(profile: profile)
        let addon = try XCTUnwrap(store.addons.first)
        XCTAssertNil(addon.legacySecretKey)
        XCTAssertNil(store.transportURL(for: addon), "No link is invented")
        XCTAssertNil(secrets.read(AddonStore.account(profile, addon.id)))
        XCTAssertTrue(store.streamSources(type: "movie", id: "tt0133093").isEmpty, "Play skips an install without a link")

        let relaunched = makeStore(dir, secrets)
        relaunched.load(profile: profile)
        XCTAssertEqual(relaunched.addons.map(\.id), [addon.id], "The new id is saved once")
    }

    func testPurgeRemovesEveryLinkIncludingRecordsThatWereNeverLoaded() throws {
        let dir = try tempDirectory()
        let deleted = UUID()
        let kept = UUID()
        let deletedModern = UUID()
        let keptModern = UUID()
        try write([
            modernRecord(secondManifest, id: deletedModern, display: "second.example.com/\u{2026}"),
            legacyRecord(legacyManifest, display: "legacy.example.com/\u{2026}", enabled: true),
        ], to: listURL(dir, deleted))
        try write([modernRecord(secondManifest, id: keptModern, display: "second.example.com/\u{2026}")], to: listURL(dir, kept))
        let secrets = AddonSecrets.memory()
        secrets.write(AddonStore.account(deleted, deletedModern.uuidString), secondLink)
        secrets.write(AddonStore.account(deleted, "org.legacy"), legacyLink)
        secrets.write(AddonStore.account(kept, keptModern.uuidString), secondLink)

        // The store has the other profile open; the deleted profile was never loaded (not migrated).
        let store = makeStore(dir, secrets)
        store.load(profile: kept)
        store.purge(profile: deleted)

        XCTAssertNil(secrets.read(AddonStore.account(deleted, deletedModern.uuidString)))
        XCTAssertNil(secrets.read(AddonStore.account(deleted, "org.legacy")), "An unmigrated legacy item is removed too")
        XCTAssertFalse(FileManager.default.fileExists(atPath: listURL(dir, deleted).path))

        XCTAssertEqual(secrets.read(AddonStore.account(kept, keptModern.uuidString)), secondLink, "Another profile's install of the same add-on is untouched")
        XCTAssertTrue(FileManager.default.fileExists(atPath: listURL(dir, kept).path))
        XCTAssertEqual(store.profileID, kept)
        XCTAssertEqual(store.addons.map(\.id), [keptModern.uuidString])
    }

    func testKeychainAccountsAreScopedByProfileAndInstall() {
        let a = UUID()
        let b = UUID()
        let install = UUID().uuidString
        XCTAssertEqual(AddonStore.account(a, install), "addon.\(a.uuidString).\(install)")
        XCTAssertNotEqual(AddonStore.account(a, install), AddonStore.account(b, install), "Profiles never share an item")
        XCTAssertNotEqual(AddonStore.account(a, install), AddonStore.account(a, UUID().uuidString), "Installs never share an item")
    }

    func testTransportSecurityHasNoArbitraryLoadsException() {
        // project.yml adds no ATS keys, so the defaults apply (local-network http is allowed by iOS).
        let ats = Bundle(for: AddonStore.self).infoDictionary?["NSAppTransportSecurity"] as? [String: Any]
        XCTAssertNotEqual(ats?["NSAllowsArbitraryLoads"] as? Bool, true)
        XCTAssertNotEqual(ats?["NSAllowsArbitraryLoadsInWebContent"] as? Bool, true)

        // Add-on links: https everywhere, plain http only for this device and the local network.
        XCTAssertThrowsError(try AddonURL.normalise("http://torrentio.strem.fun/manifest.json")) { error in
            XCTAssertEqual(error as? AddonURLProblem, .insecure)
        }
        XCTAssertThrowsError(try AddonURL.normalise("http://172.32.0.1/manifest.json")) { error in
            XCTAssertEqual(error as? AddonURLProblem, .insecure)
        }
        XCTAssertNoThrow(try AddonURL.normalise("http://localhost:11470/manifest.json"))
        XCTAssertNoThrow(try AddonURL.normalise("http://nas.local/manifest.json"))
    }
}
