import XCTest
@testable import GlassRemote

// Phase 7.1: add-on install identity. Each install has its own id, separate from the manifest id,
// so differently configured links of the same add-on can be installed side by side. Full links stay
// in the secrets store (the Keychain in the app) and never in the saved list.

private let torrentioManifest = Data(#"{"id":"com.stremio.torrentio.addon","name":"Torrentio","version":"0.0.14","types":["movie","series"],"resources":["stream"],"idPrefixes":["tt","kitsu"]}"#.utf8)
private let otherManifest = Data(#"{"id":"org.other","name":"Other","version":"1.0.0","types":["movie"],"resources":["stream"]}"#.utf8)
private let linkA = "https://torrentio.strem.fun/providers=yts,eztv/manifest.json"
private let linkB = "https://torrentio.strem.fun/qualityfilter=480p,scr,cam/manifest.json"
private let linkC = "https://torrentio.strem.fun/providers=yts/manifest.json"
private let otherLink = "https://other.example.com/manifest.json"

@MainActor
final class Phase71AddonIdentityTests: XCTestCase {
    private func stub() {
        Phase7StubURLProtocol.responses = [
            linkA: (200, torrentioManifest),
            linkB: (200, torrentioManifest),
            linkC: (200, torrentioManifest),
            otherLink: (200, otherManifest),
        ]
    }

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("p71-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeStore(_ dir: URL, _ secrets: AddonSecrets) -> AddonStore {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Phase7StubURLProtocol.self]
        return AddonStore(directory: dir, client: AddonClient(session: URLSession(configuration: config)), secrets: secrets)
    }

    func testTwoConfiguredLinksOfTheSameAddonInstallSideBySide() async throws {
        stub()
        let dir = tempDirectory()
        let secrets = AddonSecrets.memory()
        let store = makeStore(dir, secrets)
        let profile = UUID()
        store.load(profile: profile)

        let first = try await store.install(from: linkA)
        let second = try await store.install(from: linkB)
        XCTAssertEqual(store.addons.count, 2)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.manifestID, second.manifestID)
        XCTAssertEqual(store.addons.map { store.displayName(for: $0) }, ["Torrentio 1", "Torrentio 2"])

        // Each install keeps its own full link under its own install id.
        XCTAssertEqual(secrets.read(AddonStore.account(profile, first.id)), linkA)
        XCTAssertEqual(secrets.read(AddonStore.account(profile, second.id)), linkB)
        XCTAssertNil(secrets.read(AddonStore.account(profile, first.manifestID)))

        // Play asks both, under names that tell them apart.
        let sources = store.streamSources(type: "movie", id: "tt0133093")
        XCTAssertEqual(sources.map(\.addonID), [first.id, second.id])
        XCTAssertEqual(sources.map(\.name), ["Torrentio 1", "Torrentio 2"])
        XCTAssertEqual(Set(sources.map(\.base.absoluteString)).count, 2)

        // Enabled state is per install.
        store.setEnabled(first.id, false)
        XCTAssertEqual(store.streamSources(type: "movie", id: "tt0133093").map(\.addonID), [second.id])

        // The saved list never contains the configured links.
        let saved = try String(contentsOf: dir.appendingPathComponent("addons-\(profile.uuidString).json"), encoding: .utf8)
        XCTAssertFalse(saved.contains("providers"))
        XCTAssertFalse(saved.contains("qualityfilter"))
        XCTAssertTrue(saved.contains(first.id))

        // Removing one leaves the other and its link alone.
        store.remove(first.id)
        XCTAssertEqual(store.addons.map(\.id), [second.id])
        XCTAssertNil(secrets.read(AddonStore.account(profile, first.id)))
        XCTAssertEqual(secrets.read(AddonStore.account(profile, second.id)), linkB)
        XCTAssertEqual(store.displayName(for: store.addons[0]), "Torrentio")
    }

    func testTheSameLinkTwiceIsADuplicateAndIDsSurviveRelaunch() async throws {
        stub()
        let dir = tempDirectory()
        let secrets = AddonSecrets.memory()
        let store = makeStore(dir, secrets)
        let profile = UUID()
        store.load(profile: profile)

        let first = try await store.install(from: linkA)
        do {
            _ = try await store.install(from: "  " + linkA)
            XCTFail("The same link should be a duplicate")
        } catch {
            XCTAssertEqual(error as? AddonError, .duplicate("Torrentio"))
        }
        XCTAssertEqual(store.addons.count, 1)

        let relaunched = makeStore(dir, secrets)
        relaunched.load(profile: profile)
        XCTAssertEqual(relaunched.addons.map(\.id), [first.id], "Install ids are stable across launches")
        XCTAssertEqual(relaunched.addons.first.flatMap { relaunched.transportURL(for: $0) }?.absoluteString, linkA)
    }

    func testReplacingALinkUpdatesThatInstallOnly() async throws {
        stub()
        let store = makeStore(tempDirectory(), .memory())
        store.load(profile: UUID())

        let first = try await store.install(from: linkA)
        let second = try await store.install(from: linkB)
        let replaced = try await store.install(from: linkC, replacing: first.id)
        XCTAssertEqual(replaced.id, first.id)
        XCTAssertEqual(store.addons.map(\.id), [first.id, second.id])
        XCTAssertEqual(store.transportURL(for: replaced)?.absoluteString, linkC)
        XCTAssertEqual(store.addon(second.id).flatMap { store.transportURL(for: $0) }?.absoluteString, linkB)

        do {
            _ = try await store.install(from: otherLink, replacing: first.id)
            XCTFail("A link for another add-on can't replace this one")
        } catch {
            XCTAssertEqual(error as? AddonError, .differentAddon("Torrentio"))
        }
        do {
            _ = try await store.install(from: linkB, replacing: first.id)
            XCTFail("A link another install already uses is a duplicate")
        } catch {
            XCTAssertEqual(error as? AddonError, .duplicate("Torrentio 2"))
        }
        XCTAssertEqual(store.addons.count, 2)
    }

    func testRecordsSavedBeforeInstallIDsAreMigrated() throws {
        let dir = tempDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let profile = UUID()
        let legacy = #"[{"manifest":{"id":"org.legacy","version":"1.0.0","name":"Legacy","types":["movie"],"catalogs":[],"resources":["stream"]},"displayURL":"legacy.example.com","enabled":false,"installedAt":700000000,"refreshedAt":700000000}]"#
        try Data(legacy.utf8).write(to: dir.appendingPathComponent("addons-\(profile.uuidString).json"))
        let secrets = AddonSecrets.memory()
        let link = "https://legacy.example.com/token=abc/manifest.json"
        secrets.write(AddonStore.account(profile, "org.legacy"), link)

        let store = makeStore(dir, secrets)
        store.load(profile: profile)
        XCTAssertEqual(store.addons.count, 1)
        let addon = try XCTUnwrap(store.addons.first)
        XCTAssertEqual(addon.manifestID, "org.legacy")
        XCTAssertNotEqual(addon.id, "org.legacy")
        XCTAssertNil(addon.legacySecretKey)
        XCTAssertFalse(addon.enabled, "Settings carry over")
        XCTAssertEqual(store.transportURL(for: addon)?.absoluteString, link)
        XCTAssertNil(secrets.read(AddonStore.account(profile, "org.legacy")), "The old Keychain item is removed")

        let relaunched = makeStore(dir, secrets)
        relaunched.load(profile: profile)
        XCTAssertEqual(relaunched.addons.map(\.id), [addon.id], "The migrated id is saved")
    }
}
