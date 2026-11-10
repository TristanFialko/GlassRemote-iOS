import Foundation
import SwiftUI

struct InstalledAddon: Codable, Identifiable, Equatable {
    var id: String { manifest.id }
    var manifest: AddonManifest
    /// Redacted link for display. The full link lives only in the Keychain.
    var displayURL: String
    var enabled: Bool
    var installedAt: Date
    var refreshedAt: Date
    var lastError: String?
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

/// An enabled add-on that can be asked for streams.
struct StreamSource: Equatable, Sendable {
    let addonID: String
    let name: String
    let base: URL
}

/// Installed add-ons of the active profile. The list (manifest, enabled state, order) is stored per
/// profile in Application Support; each add-on's full link, which may include a personal token, is
/// stored in the Keychain under `addon.<profile>.<manifest id>`.
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

    var streamAddonCount: Int { addons.filter { $0.enabled && $0.manifest.capabilities.contains(.stream) }.count }

    func load(profile: UUID) {
        profileID = profile
        addons = Self.read(fileURL(profile))
    }

    func addon(_ id: String) -> InstalledAddon? { addons.first { $0.id == id } }

    func transportURL(for addon: InstalledAddon) -> URL? {
        guard let profileID, let text = secrets.read(Self.account(profileID, addon.id)) else { return nil }
        return URL(string: text)
    }

    func configureURL(for addon: InstalledAddon) -> URL? {
        guard addon.manifest.isConfigurable, let url = transportURL(for: addon), let base = AddonURL.base(of: url) else { return nil }
        return AddonURL.configure(base: base)
    }

    /// Validates the link, fetches and checks the manifest, then installs. Installing an add-on that
    /// is already present with a different link (for example after reconfiguring it) updates it in
    /// place and keeps its position and enabled state.
    @discardableResult
    func install(from input: String) async throws -> InstalledAddon {
        guard let profile = profileID else { throw AddonError.noProfile }
        let url: URL
        do {
            url = try AddonURL.normalise(input)
        } catch let problem as AddonURLProblem {
            throw AddonError.url(problem)
        }
        let manifest = try await client.manifest(at: url)
        guard profileID == profile else { throw CancellationError() }
        let account = Self.account(profile, manifest.id)
        let now = Date()
        if let i = addons.firstIndex(where: { $0.id == manifest.id }) {
            if transportURL(for: addons[i]) == url { throw AddonError.duplicate(manifest.name) }
            secrets.write(account, url.absoluteString)
            addons[i].manifest = manifest
            addons[i].displayURL = AddonURL.display(url)
            addons[i].refreshedAt = now
            addons[i].lastError = nil
            save()
            return addons[i]
        }
        let addon = InstalledAddon(manifest: manifest, displayURL: AddonURL.display(url), enabled: true,
                                   installedAt: now, refreshedAt: now, lastError: nil)
        secrets.write(account, url.absoluteString)
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
            if manifest.id != id {
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

    /// Enabled add-ons that offer streams for this title, in the user's order.
    func streamSources(type: String, id: String) -> [StreamSource] {
        addons.compactMap { addon in
            guard addon.enabled, addon.manifest.supports("stream", type: type, id: id),
                  let url = transportURL(for: addon), let base = AddonURL.base(of: url) else { return nil }
            return StreamSource(addonID: addon.id, name: addon.manifest.name, base: base)
        }
    }

    /// Removes a deleted profile's add-on list and Keychain items.
    func purge(profile: UUID) {
        let url = fileURL(profile)
        for addon in Self.read(url) { secrets.remove(Self.account(profile, addon.id)) }
        try? FileManager.default.removeItem(at: url)
        if profileID == profile {
            addons = []
            profileID = nil
        }
    }

    nonisolated static func account(_ profile: UUID, _ addonID: String) -> String {
        "addon.\(profile.uuidString).\(addonID)"
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
