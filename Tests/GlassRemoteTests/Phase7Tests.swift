import SwiftUI
import UIKit
import XCTest
@testable import GlassRemote

// Phase 7 unit tests: add-on links, manifests and streams, stream ranking, profiles (persistence,
// switching, photos), the per-profile add-on store and the TV handoff commands. UI, Liquid Glass
// rendering and real TV/Nuvio behaviour need a device; see PHASE-7-NOTES.md.

private func isInvalidManifest(_ error: Error) -> Bool {
    if case .invalidManifest? = error as? AddonError { return true }
    return false
}

final class Phase7AddonURLTests: XCTestCase {
    func testNormalisesCommonLinkForms() throws {
        XCTAssertEqual(try AddonURL.normalise("https://v3-cinemeta.strem.io/manifest.json").absoluteString, "https://v3-cinemeta.strem.io/manifest.json")
        XCTAssertEqual(try AddonURL.normalise("  stremio://torrentio.strem.fun/manifest.json \n").absoluteString, "https://torrentio.strem.fun/manifest.json")
        XCTAssertEqual(try AddonURL.normalise("example.com/abc").absoluteString, "https://example.com/abc/manifest.json")
        XCTAssertEqual(try AddonURL.normalise("https://example.com/").absoluteString, "https://example.com/manifest.json")
        XCTAssertEqual(try AddonURL.normalise("https://example.com").absoluteString, "https://example.com/manifest.json")
        XCTAssertEqual(try AddonURL.normalise("http://192.168.1.20:7000/manifest.json#frag").absoluteString, "http://192.168.1.20:7000/manifest.json")
    }

    func testRejectsUnsafeOrBrokenLinks() {
        func problem(_ text: String) -> AddonURLProblem? {
            do { _ = try AddonURL.normalise(text); return nil } catch { return error as? AddonURLProblem }
        }
        XCTAssertEqual(problem("   "), .empty)
        XCTAssertEqual(problem("ftp://x.example.com/manifest.json"), .malformed)
        XCTAssertEqual(problem("https://nodot/manifest.json"), .malformed)
        XCTAssertEqual(problem("http://example.com/manifest.json"), .insecure)
        XCTAssertEqual(problem("https://user:pw@example.com/manifest.json"), .credentials)
        XCTAssertNil(problem("http://localhost:7000/manifest.json"))
    }

    func testLocalHosts() {
        XCTAssertTrue(AddonURL.isLocal("192.168.0.4"))
        XCTAssertTrue(AddonURL.isLocal("10.1.2.3"))
        XCTAssertTrue(AddonURL.isLocal("172.20.0.1"))
        XCTAssertTrue(AddonURL.isLocal("nas.local"))
        XCTAssertFalse(AddonURL.isLocal("172.40.0.1"))
        XCTAssertFalse(AddonURL.isLocal("8.8.8.8"))
        XCTAssertFalse(AddonURL.isLocal("example.com"))
    }

    func testBaseResourceConfigureAndDisplay() throws {
        let manifest = try XCTUnwrap(URL(string: "https://a.example.com/cfg/manifest.json?y=1"))
        let base = try XCTUnwrap(AddonURL.base(of: manifest))
        XCTAssertEqual(base.absoluteString, "https://a.example.com/cfg")
        XCTAssertEqual(AddonURL.resource("stream", type: "series", id: "tt0944947:1:2", base: base)?.absoluteString,
                       "https://a.example.com/cfg/stream/series/tt0944947:1:2.json")
        XCTAssertEqual(AddonURL.configure(base: base)?.absoluteString, "https://a.example.com/cfg/configure")
        XCTAssertEqual(AddonURL.display(try XCTUnwrap(URL(string: "https://v3-cinemeta.strem.io/manifest.json"))), "v3-cinemeta.strem.io")
        // Personal tokens in the path are never shown.
        XCTAssertEqual(AddonURL.display(try XCTUnwrap(URL(string: "https://torrentio.strem.fun/token=secret/manifest.json"))), "torrentio.strem.fun/\u{2026}")
    }
}

final class Phase7ManifestTests: XCTestCase {
    func testDecodesMixedResourcesAndSkipsBrokenEntries() throws {
        let json = #"""
        {"id":"org.test","version":"1.2.0","name":"Test","types":["movie","series"],
         "resources":["catalog",{"name":"stream","types":["movie"],"idPrefixes":["tt"]},{"bad":1}],
         "catalogs":[{"type":"movie","id":"top"},{"oops":true}],
         "behaviorHints":{"configurable":true}}
        """#
        let m = try AddonClient.parseManifest(Data(json.utf8))
        XCTAssertEqual(m.resources.map(\.name), ["catalog", "stream"])
        XCTAssertEqual(m.catalogs.count, 1)
        XCTAssertEqual(m.capabilities, [.stream, .catalog])
        XCTAssertTrue(m.supports("stream", type: "movie", id: "tt0133093"))
        XCTAssertFalse(m.supports("stream", type: "series", id: "tt0133093"))
        XCTAssertFalse(m.supports("stream", type: "movie", id: "kitsu:1"))
        XCTAssertTrue(m.supports("catalog", type: "series", id: "anything"))
        XCTAssertTrue(m.isConfigurable)
        let compat = m.compatibility
        XCTAssertTrue(compat.usable)
        XCTAssertTrue(compat.notes.contains("Finds streams for Discover titles."))
    }

    func testRejectsNonManifests() {
        XCTAssertThrowsError(try AddonClient.parseManifest(Data("<html></html>".utf8))) { XCTAssertTrue(isInvalidManifest($0)) }
        XCTAssertThrowsError(try AddonClient.parseManifest(Data("{}".utf8))) { XCTAssertTrue(isInvalidManifest($0)) }
        XCTAssertThrowsError(try AddonClient.parseManifest(Data(#"{"id":"a","version":"1","name":"A","resources":[]}"#.utf8))) {
            XCTAssertTrue(isInvalidManifest($0))
        }
    }

    func testSubtitleOnlyAddonIsNotUsedByPlay() throws {
        let json = #"{"id":"subs","version":"1.0.0","name":"Subs","types":["movie"],"resources":["subtitles"]}"#
        let compat = try AddonClient.parseManifest(Data(json.utf8)).compatibility
        XCTAssertFalse(compat.usable)
        XCTAssertEqual(compat.capabilities, [.subtitles])
    }
}

final class Phase7StreamTests: XCTestCase {
    private let json = #"""
    {"streams":[
      {"name":"Provider\n4K","title":"Movie.2160p.mkv 12.5 GB","url":"https://cdn.example.com/a.mkv"},
      {"name":"T","infoHash":"abcdef0123","fileIdx":1,"title":"1080p"},
      {"ytId":"dQw4w9WgXcQ"},
      {"externalUrl":"https://example.com/watch"},
      {"url":"https://h.example.com/b.m3u8","behaviorHints":{"proxyHeaders":{"request":{"Referer":"x"}}}},
      42
    ]}
    """#

    func testDecodesLossilyAndClassifies() throws {
        let streams = AddonClient.parseStreams(Data(json.utf8))
        XCTAssertEqual(streams.count, 5)
        XCTAssertEqual(streams[0].kind, .direct(try XCTUnwrap(URL(string: "https://cdn.example.com/a.mkv"))))
        XCTAssertEqual(streams[0].headline, "Provider")
        XCTAssertEqual(streams[0].quality, .uhd)
        XCTAssertEqual(streams[0].sizeText, "12.5 GB")
        XCTAssertTrue(streams[0].canSendToTV)
        XCTAssertEqual(streams[1].kind, .torrent)
        XCTAssertFalse(streams[1].canSendToTV)
        XCTAssertNotNil(streams[1].unavailableReason)
        XCTAssertEqual(streams[1].quality, .hd1080)
        XCTAssertEqual(streams[2].kind, .youtube("dQw4w9WgXcQ"))
        XCTAssertTrue(streams[2].canSendToTV)
        XCTAssertEqual(streams[3].kind, .external(try XCTUnwrap(URL(string: "https://example.com/watch"))))
        XCTAssertFalse(streams[4].canSendToTV, "Streams that need proxy headers can't be sent with a plain intent")
        XCTAssertTrue(AddonClient.parseStreams(Data("not json".utf8)).isEmpty)
    }

    func testQualityParsing() {
        XCTAssertEqual(StreamQuality.parse("4K HDR"), .uhd)
        XCTAssertEqual(StreamQuality.parse("WEB 720p"), .hd720)
        XCTAssertEqual(StreamQuality.parse("480p x264"), .sd)
        XCTAssertEqual(StreamQuality.parse("nothing useful"), .unknown)
        XCTAssertEqual(StreamQuality.uhd.badge, "4K")
        XCTAssertNil(StreamQuality.unknown.badge)
    }

    func testRankingPutsPlayableStreamsFirst() {
        let options = AddonClient.parseStreams(Data(json.utf8)).enumerated().map {
            StreamOption(id: "o\($0.offset)", addonName: "A", stream: $0.element)
        }
        let ranked = StreamResolver.rank(options)
        XCTAssertEqual(ranked.count, options.count)
        XCTAssertEqual(ranked.prefix(3).map(\.stream.canSendToTV), [true, true, true])
        XCTAssertEqual(ranked.suffix(2).map(\.stream.canSendToTV), [false, false])
    }
}

@MainActor
final class Phase7ProfileTests: XCTestCase {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("p7-\(UUID().uuidString)", isDirectory: true)
    }

    private func suite() -> UserDefaults {
        let name = "p7-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testCreateRenameSwitchAndRestoreAfterRelaunch() {
        let dir = tempDirectory()
        let defaults = suite()
        let store = ProfileStore(directory: dir, defaults: defaults, appliesGlobally: false)
        XCTAssertEqual(store.profiles.count, 1)
        let first = store.active
        let kid = store.create(name: "  Kids room  ")
        XCTAssertEqual(kid?.name, "Kids room")
        XCTAssertNotEqual(kid?.tint, first.tint)
        XCTAssertNil(store.create(name: "   "))
        guard let kid else { return XCTFail("profile not created") }
        store.rename(kid.id, to: "Kids")
        store.switchTo(kid.id)
        XCTAssertEqual(store.activeID, kid.id)
        store.updateSettings { $0.posterOrientation = .landscape }

        let relaunched = ProfileStore(directory: dir, defaults: defaults, appliesGlobally: false)
        XCTAssertEqual(relaunched.profiles.map(\.name), [first.name, "Kids"])
        XCTAssertEqual(relaunched.activeID, kid.id, "The last active profile is restored")
        XCTAssertEqual(relaunched.active.settings.posterOrientation, .landscape)
    }

    func testDeletingTheActiveProfileSwitchesAndTheLastOneStays() {
        let store = ProfileStore(directory: tempDirectory(), defaults: suite(), appliesGlobally: false)
        let first = store.activeID
        let second = store.create(name: "Guest")!
        store.switchTo(second.id)
        store.delete(second.id)
        XCTAssertEqual(store.activeID, first)
        XCTAssertEqual(store.profiles.count, 1)
        store.delete(first)
        XCTAssertEqual(store.profiles.count, 1, "The last profile can't be deleted")
    }

    func testNamesAndInitials() {
        XCTAssertEqual(UserProfile(name: "Ada Lovelace").initials, "AL")
        XCTAssertEqual(UserProfile(name: "zoë").initials, "Z")
        XCTAssertNil(UserProfile.cleanedName(" \n "))
        XCTAssertEqual(UserProfile.cleanedName(String(repeating: "x", count: 60))?.count, UserProfile.maxNameLength)
    }

    func testProfilePhotoIsDownscaledStoredAndRemoved() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let big = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 1000), format: format).image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 2000, height: 1000))
        }
        let data = try XCTUnwrap(big.jpegData(compressionQuality: 0.9))
        let small = try XCTUnwrap(ProfileImageProcessing.avatarJPEG(from: data).flatMap { UIImage(data: $0) })
        XCTAssertLessThanOrEqual(max(small.size.width, small.size.height) * small.scale, 512)

        let store = ProfileStore(directory: tempDirectory(), defaults: suite(), appliesGlobally: false)
        let id = store.activeID
        let stored = await store.setImage(data, for: id)
        XCTAssertTrue(stored)
        XCTAssertTrue(store.active.hasImage)
        XCTAssertNotNil(store.image(for: id))
        await store.setImage(nil, for: id)
        XCTAssertFalse(store.active.hasImage)
        XCTAssertNil(store.image(for: id))
    }
}

/// Serves canned responses so add-on installs can be tested without a network.
final class Phase7StubURLProtocol: URLProtocol {
    static var responses: [String: (Int, Data)] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let (code, data) = Self.responses[url.absoluteString] ?? (404, Data())
        let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class Phase7AddonStoreTests: XCTestCase {
    private func stubClient() -> AddonClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Phase7StubURLProtocol.self]
        return AddonClient(session: URLSession(configuration: config))
    }

    func testInstallDuplicateUpdateDisableIsolationAndRemove() async throws {
        let manifest = Data(#"{"id":"org.demo","name":"Demo","version":"1.0.0","types":["movie"],"resources":["stream"],"idPrefixes":["tt"]}"#.utf8)
        Phase7StubURLProtocol.responses = [
            "https://demo.example.com/manifest.json": (200, manifest),
            "https://demo.example.com/cfg/manifest.json": (200, manifest),
            "https://locked.example.com/manifest.json": (401, Data()),
        ]
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("p7a-\(UUID().uuidString)", isDirectory: true)
        let store = AddonStore(directory: dir, client: stubClient(), secrets: .memory())
        let a = UUID()
        let b = UUID()
        store.load(profile: a)

        let installed = try await store.install(from: "demo.example.com")
        XCTAssertEqual(installed.manifestID, "org.demo")
        XCTAssertNotEqual(installed.id, "org.demo", "Installs have their own id, separate from the manifest id")
        XCTAssertEqual(store.addons.count, 1)

        do {
            _ = try await store.install(from: "https://demo.example.com/manifest.json")
            XCTFail("Duplicate install should fail")
        } catch {
            XCTAssertEqual(error as? AddonError, .duplicate("Demo"))
        }

        // Replacing the link (after reconfiguring) updates that install in place.
        _ = try await store.install(from: "https://demo.example.com/cfg/manifest.json", replacing: installed.id)
        XCTAssertEqual(store.addons.count, 1)
        XCTAssertEqual(store.addons.first?.displayURL, "demo.example.com/\u{2026}")
        XCTAssertEqual(store.streamSources(type: "movie", id: "tt0133093").first?.base.absoluteString, "https://demo.example.com/cfg")
        XCTAssertTrue(store.streamSources(type: "series", id: "tt0133093:1:1").isEmpty)

        do {
            _ = try await store.install(from: "https://locked.example.com/manifest.json")
            XCTFail("401 should fail")
        } catch {
            XCTAssertEqual(error as? AddonError, .unauthorized)
        }

        store.setEnabled(installed.id, false)
        XCTAssertTrue(store.streamSources(type: "movie", id: "tt0133093").isEmpty)
        store.setEnabled(installed.id, true)

        store.load(profile: b)
        XCTAssertTrue(store.addons.isEmpty, "Add-ons belong to one profile")
        store.load(profile: a)
        XCTAssertEqual(store.addons.count, 1)

        store.remove(installed.id)
        XCTAssertTrue(store.addons.isEmpty)
        _ = try await store.install(from: "demo.example.com")
        store.purge(profile: a)
        store.load(profile: a)
        XCTAssertTrue(store.addons.isEmpty)
    }
}

final class Phase7HandoffTests: XCTestCase {
    func testShellSafety() throws {
        XCTAssertEqual(RemoteModel.shellSafeURL(try XCTUnwrap(URL(string: "https://cdn.example.com/a.mkv?t=1"))), "https://cdn.example.com/a.mkv?t=1")
        XCTAssertNil(RemoteModel.shellSafeURL(try XCTUnwrap(URL(string: "https://cdn.example.com/it's.mkv"))))
        XCTAssertNil(RemoteModel.shellSafeURL(try XCTUnwrap(URL(string: "file:///etc/hosts"))))
        XCTAssertNil(RemoteModel.shellSafeURL(try XCTUnwrap(URL(string: "intent://example.com"))))
    }

    func testIntentCommands() {
        let video = RemoteModel.videoIntentCommand(url: "https://a.example.com/c.mkv")
        XCTAssertTrue(video.contains("-t 'video/*'"))
        XCTAssertTrue(video.contains("-d 'https://a.example.com/c.mkv'"))
        XCTAssertFalse(video.contains(" -p "), "Direct streams go to the TV's default player, not a fixed package")
        XCTAssertFalse(RemoteModel.viewIntentCommand(url: "https://a.example.com").contains("video/*"))
    }

    func testNuvioAddonInstallLinkAndYouTube() throws {
        XCTAssertEqual(RemoteModel.nuvioAddonInstallLink(manifestURL: try XCTUnwrap(URL(string: "https://torrentio.strem.fun/manifest.json"))),
                       "stremio://torrentio.strem.fun/manifest.json")
        XCTAssertNil(RemoteModel.nuvioAddonInstallLink(manifestURL: try XCTUnwrap(URL(string: "http://192.168.1.2/manifest.json"))))
        XCTAssertEqual(RemoteModel.youTubeURL(id: "dQw4w9WgXcQ")?.absoluteString, "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        XCTAssertNil(RemoteModel.youTubeURL(id: "bad id!"))
    }
}

@MainActor
final class Phase7MotionTests: XCTestCase {
    func testReduceMotionUsesTheShortFade() {
        XCTAssertEqual(Motion.resolve(Motion.page, reduceMotion: true), Motion.reduced)
        XCTAssertEqual(Motion.resolve(Motion.hero, reduceMotion: true), Motion.reduced)
    }
}
