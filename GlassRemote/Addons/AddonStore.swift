import Foundation
import SwiftUI

/// One installed add-on. `installID` is the identity of this install and `manifest.id` is the
/// add-on's own id. They are kept apart so the same add-on can be installed more than once with
/// different configured links (for example two Torrentio configurations), each with its own enabled
/// state, position and Keychain item.
struct InstalledAddon: Codable, Identifiable, Equatable {
    var installID: UUID
    var manifest: AddonManifest
    /// Redacted link for display. The full link lives only in the Keychain.
    var displayURL: String
    var enabled: Bool
    var installedAt: Date
    var refreshedAt: Date
    var lastError: String?
    /// Only set on records saved before install ids existed: the Keychain account suffix they used,
    /// which was the manifest id. AddonStore.load moves the link to the install id and clears this.
    /// Never saved.
    var legacySecretKey: String?

    var id: String { installID.uuidString }
    var manifestID: String { manifest.id }

    init(installID: UUID = UUID(), manifest: AddonManifest, displayURL: String, enabled: Bool,
         installedAt: Date, refreshedAt: Date, lastError: String? = nil) {
        self.installID = installID
        self.manifest = manifest
        self.displayURL = displayURL
        self.enabled = enabled
        self.installedAt = installedAt
        self.refreshedAt = refreshedAt
        self.lastError = lastError
        self.legacySecretKey = nil
    }

    private enum CodingKeys: String, CodingKey {
        case installID, manifest, displayURL, enabled, installedAt, refreshedAt, lastError
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        manifest = try c.decode(AddonManifest.self, forKey: .manifest)
        displayURL = try c.decode(String.self, forKey: .displayURL)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        installedAt = try c.decode(Date.self, forKey: .installedAt)
        refreshedAt = try c.decode(Date.self, forKey: .refreshedAt)
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
        if let saved = try c.decodeIfPresent(UUID.self, forKey: .installID) {
            installID = saved
            legacySecretKey = nil
        } else {
            installID = UUID()
            legacySecretKey = manifest.id
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(installID, forKey: .installID)
        try c.encode(manifest, forKey: .manifest)
        try c.encode(displayURL, forKey: .displayURL)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(installedAt, forKey: .installedAt)
        try c.encode(refreshedAt, forKey: .refreshedAt)
        try c.encodeIfPresent(lastError, forKey: .lastError)
    }
}

/// Where an add-on's full link is kept. Production uses the Keychain; tests use memory.
struct AddonSecrets {
    var read: (String) -> String?
    var write: (String, String) -> Void
    var remove: (String) -> Void

    static let keychain = AddonSecrets(
        read: { KeychainStore.string(for: $0) },
        write: { account, value in KeychainStore.set(value, for: account) },
        remove: { KeychainStore.remove($0) })

    static func memory() -> AddonSecrets {
        final class Box { var values: [String: String] = [:] }
        let box = Box()
        return AddonSecrets(read: { box.values[$0] },
                            write: { box.values[$0] = $1 },
                            remove: { box.values[$0] = nil })
    }
}

/// An enabled add-on install that can be asked for streams.
struct StreamSource: Equatable, Sendable {
    /// The install id (not the manifest id), so two installs of one add-on stay apart.
    let addonID: String
    let name: String
    let base: URL
}

/// Installed add-ons of the active profile. The list (manifest, enabled state, order) is stored per
/// profile in Application Support; each install's full link, which may include a personal token, is
/// stored in the Keychain under `addon.<profile>.<install id>`.
@MainActor
final class AddonStore: ObservableObject {
    static let shared = AddonStore()

    @Published private(set) var addons: [InstalledAddon] = []
    @Published private(set) var profileID: UUID?
    @Published private(set) var refreshing: Set<String> = []

    private let directory: URL
    private let client: AddonClient
    private let secrets: AddonSecrets

    init(directory: URL? = nil, client: AddonClient = .shared, secrets: AddonSecrets = .keychain) {
        self.directory = directory ?? ProfileStore.defaultDirectory()
        self.client = client
        self.secrets = secrets
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    /// Enabled stream add-ons that can actually be asked (their link is in the Keychain).
    var streamAddonCount: Int { addons.filter { isStreamAddon($0) && !linkMissing($0) }.count }
    /// Enabled stream add-ons whose Keychain link is gone (e.g. after restoring to a new device).
    var linkMissingStreamAddonCount: Int { addons.filter { isStreamAddon($0) && linkMissing($0) }.count }

    private func isStreamAddon(_ addon: InstalledAddon) -> Bool {
        addon.enabled && addon.manifest.capabilities.contains(.stream)
    }

    /// The install is listed but its full link isn't in the Keychain (Keychain items don't always come
    /// back with a restore). Nothing is deleted; the user re-adds the link with Replace link.
    func linkMissing(_ addon: InstalledAddon) -> Bool {
        transportURL(for: addon) == nil
    }

    /// Loads a profile's list. Records saved before install ids existed get one, and their Keychain
    /// item moves from the manifest-id account to the install-id account.
    func load(profile: UUID) {
        profileID = profile
        var list = Self.read(fileURL(profile))
        var migrated = false
        for i in list.indices {
            guard let legacy = list[i].legacySecretKey else { continue }
            let old = Self.account(profile, legacy)
            if let link = secrets.read(old) {
                secrets.write(Self.account(profile, list[i].id), link)
                secrets.remove(old)
            }
            list[i].legacySecretKey = nil
            migrated = true
        }
        addons = list
        if migrated { save() }
    }

    /// Looks an install up by its install id.
    func addon(_ id: String) -> InstalledAddon? { addons.first { $0.id == id } }

    /// The add-on's name, numbered by install order when the same add-on is installed more than once
    /// ("Torrentio 1", "Torrentio 2"), so rows, the Play sheet and error lines can be told apart.
    func displayName(for addon: InstalledAddon) -> String {
        let copies = addons.filter { $0.manifest.id == addon.manifest.id }
            .sorted { ($0.installedAt, $0.id) < ($1.installedAt, $1.id) }
        guard copies.count > 1, let n = copies.firstIndex(where: { $0.id == addon.id }) else { return addon.manifest.name }
        return "\(addon.manifest.name) \(n + 1)"
    }

    func transportURL(for addon: InstalledAddon) -> URL? {
        guard let profileID, let text = secrets.read(Self.account(profileID, addon.id)) else { return nil }
        return URL(string: text)
    }

    func configureURL(for addon: InstalledAddon) -> URL? {
        guard addon.manifest.isConfigurable, let url = transportURL(for: addon), let base = AddonURL.base(of: url) else { return nil }
        return AddonURL.configure(base: base)
    }

    /// Validates the link, fetches and checks the manifest, then installs it as a new install. A
    /// link that is already installed is a duplicate; a different link for an add-on that is already
    /// installed (another configuration) becomes a second install. Pass `replacing` to swap the
    /// link of one install in place (after reconfiguring it), keeping its position and enabled state.
    @discardableResult
    func install(from input: String, replacing installID: String? = nil) async throws -> InstalledAddon {
        guard let profile = profileID else { throw AddonError.noProfile }
        let url: URL
        do {
            url = try AddonURL.normalise(input)
        } catch let problem as AddonURLProblem {
            throw AddonError.url(problem)
        }
        if let existing = installed(withLink: url) { throw AddonError.duplicate(displayName(for: existing)) }
        if let installID, addon(installID) == nil { throw AddonError.notInstalled }
        let manifest = try await client.manifest(at: url)
        guard profileID == profile else { throw CancellationError() }
        // The list may have changed while the manifest was loading.
        if let existing = installed(withLink: url) { throw AddonError.duplicate(displayName(for: existing)) }
        let now = Date()
        if let installID {
            guard let i = addons.firstIndex(where: { $0.id == installID }) else { throw AddonError.notInstalled }
            guard addons[i].manifest.id == manifest.id else { throw AddonError.differentAddon(addons[i].manifest.name) }
            secrets.write(Self.account(profile, installID), url.absoluteString)
            addons[i].manifest = manifest
            addons[i].displayURL = AddonURL.display(url)
            addons[i].refreshedAt = now
            addons[i].lastError = nil
            save()
            return addons[i]
        }
        let addon = InstalledAddon(manifest: manifest, displayURL: AddonURL.display(url), enabled: true,
                                   installedAt: now, refreshedAt: now)
        secrets.write(Self.account(profile, addon.id), url.absoluteString)
        addons.append(addon)
        save()
        return addon
    }

    func remove(_ id: String) {
        guard let profileID else { return }
        addons.removeAll { $0.id == id }
        secrets.remove(Self.account(profileID, id))
        save()
    }

    func setEnabled(_ id: String, _ enabled: Bool) {
        guard let i = addons.firstIndex(where: { $0.id == id }), addons[i].enabled != enabled else { return }
        addons[i].enabled = enabled
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        addons.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// Re-fetches the manifest (picks up new versions, resources and catalogues).
    func refresh(_ id: String) async {
        guard let profile = profileID, let addon = addon(id), let url = transportURL(for: addon) else { return }
        refreshing.insert(id)
        defer { refreshing.remove(id) }
        do {
            let manifest = try await client.manifest(at: url)
            guard profileID == profile, let i = addons.firstIndex(where: { $0.id == id }) else { return }
            if manifest.id != addons[i].manifest.id {
                addons[i].lastError = "The add-on now reports a different id. Remove it and add it again."
            } else {
                addons[i].manifest = manifest
                addons[i].refreshedAt = Date()
                addons[i].lastError = nil
            }
        } catch is CancellationError {
            return
        } catch {
            guard profileID == profile, let i = addons.firstIndex(where: { $0.id == id }) else { return }
            addons[i].lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        save()
    }

    func refreshAll() async {
        for id in addons.map(\.id) { await refresh(id) }
    }

    /// Enabled installs that offer streams for this title, in the user's order.
    func streamSources(type: String, id: String) -> [StreamSource] {
        addons.compactMap { addon in
            guard addon.enabled, addon.manifest.supports("stream", type: type, id: id),
                  let url = transportURL(for: addon), let base = AddonURL.base(of: url) else { return nil }
            return StreamSource(addonID: addon.id, name: displayName(for: addon), base: base)
        }
    }

    /// Removes a deleted profile's add-on list and Keychain items.
    func purge(profile: UUID) {
        let url = fileURL(profile)
        for addon in Self.read(url) {
            secrets.remove(Self.account(profile, addon.id))
            if let legacy = addon.legacySecretKey { secrets.remove(Self.account(profile, legacy)) }
        }
        try? FileManager.default.removeItem(at: url)
        if profileID == profile {
            addons = []
            profileID = nil
        }
    }

    /// Keychain account for one install's full link.
    nonisolated static func account(_ profile: UUID, _ installID: String) -> String {
        "addon.\(profile.uuidString).\(installID)"
    }

    private func installed(withLink url: URL) -> InstalledAddon? {
        addons.first { candidate in transportURL(for: candidate).map { Self.sameLink($0, url) } ?? false }
    }

    /// Links are the same install when they match apart from scheme and host case (both are
    /// case-insensitive); the path and query may carry case-sensitive tokens, so they must match exactly.
    nonisolated static func sameLink(_ a: URL, _ b: URL) -> Bool {
        func folded(_ url: URL) -> String {
            guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
            parts.scheme = parts.scheme?.lowercased()
            parts.host = parts.host?.lowercased()
            return parts.string ?? url.absoluteString
        }
        return folded(a) == folded(b)
    }

    private func fileURL(_ profile: UUID) -> URL {
        directory.appendingPathComponent("addons-\(profile.uuidString).json")
    }

    private func save() {
        guard let profileID, let data = try? JSONEncoder().encode(addons) else { return }
        try? data.write(to: fileURL(profileID), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static func read(_ url: URL) -> [InstalledAddon] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([InstalledAddon].self, from: data)) ?? []
    }
}
