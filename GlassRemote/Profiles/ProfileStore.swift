import Combine
import Foundation
import ImageIO
import SwiftUI
import UIKit

/// Multiple local profiles. Persisted to Application Support/GlassRemote/Profiles/profiles.json
/// (file protected); the last active profile is remembered in UserDefaults so a relaunch restores it.
/// Switching applies the profile's theme, motion preference and add-ons immediately, without a restart.
/// TV pairing is shared by every profile (see `ProfileSettings`).
@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()
    static let activeKey = "glassRemote.activeProfile.v1"
    static let maxProfiles = 8
    private static let fileName = "profiles.json"

    @Published private(set) var profiles: [UserProfile]
    @Published private(set) var activeID: UUID
    /// Bumped whenever a profile photo changes so avatar views redraw.
    @Published private(set) var imageRevision = 0

    let directory: URL
    private let defaults: UserDefaults
    /// False in tests: the store then never touches the shared theme, add-on store or motion flag.
    private let appliesGlobally: Bool
    private var images: [UUID: UIImage] = [:]
    private var themeWatch: AnyCancellable?
    private var ambientWatch: AnyCancellable?

    init(directory: URL? = nil, defaults: UserDefaults = .standard, appliesGlobally: Bool = true) {
        let folder = directory ?? Self.defaultDirectory()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stored = Self.read(folder.appendingPathComponent(Self.fileName))
        var initial = stored
        if initial.isEmpty {
            var settings = ProfileSettings()
            if appliesGlobally {
                settings.themeID = ThemeStore.shared.selected.rawValue
                settings.ambientID = ThemeStore.shared.ambient.rawValue
            }
            initial = [UserProfile(name: "Me", settings: settings)]
        }
        let saved = defaults.string(forKey: Self.activeKey).flatMap(UUID.init(uuidString:))
        self.directory = folder
        self.defaults = defaults
        self.appliesGlobally = appliesGlobally
        self.profiles = initial
        self.activeID = initial.first(where: { $0.id == saved })?.id ?? initial[0].id
        if stored.isEmpty { save() }
        guard appliesGlobally else { return }
        apply(active, animated: false)
        // Theme changes made anywhere (theme sheet, Appearance) are remembered for the active profile.
        themeWatch = ThemeStore.shared.$selected
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] theme in
                Task { @MainActor [weak self] in self?.recordTheme(theme) }
            }
        // §G3: so are ambient changes; each profile keeps its own.
        ambientWatch = ThemeStore.shared.$ambient
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] style in
                Task { @MainActor [weak self] in self?.recordAmbient(style) }
            }
    }

    var active: UserProfile { profiles.first { $0.id == activeID } ?? profiles[0] }
    var canAddProfile: Bool { profiles.count < Self.maxProfiles }

    // MARK: - Editing

    @discardableResult
    func create(name raw: String) -> UserProfile? {
        guard canAddProfile, let name = UserProfile.cleanedName(raw) else { return nil }
        var settings = ProfileSettings()
        settings.themeID = active.settings.themeID
        settings.ambientID = active.settings.ambientID
        settings.posterOrientation = active.settings.posterOrientation
        let profile = UserProfile(name: name, tint: nextTint(), settings: settings)
        profiles.append(profile)
        save()
        return profile
    }

    func rename(_ id: UUID, to raw: String) {
        guard let name = UserProfile.cleanedName(raw), let i = index(of: id), profiles[i].name != name else { return }
        profiles[i].name = name
        save()
    }

    /// Deletes a profile with its photo, add-ons and add-on secrets. The last profile can't be deleted.
    func delete(_ id: UUID) {
        guard profiles.count > 1, let i = index(of: id) else { return }
        profiles.remove(at: i)
        images[id] = nil
        try? FileManager.default.removeItem(at: imageURL(for: id))
        if appliesGlobally { AddonStore.shared.purge(profile: id) }
        if activeID == id { activate(profiles[0].id) }
        save()
        imageRevision += 1
    }

    func switchTo(_ id: UUID) {
        guard id != activeID, index(of: id) != nil else { return }
        activate(id)
    }

    func updateSettings(_ change: (inout ProfileSettings) -> Void) {
        guard let i = index(of: activeID) else { return }
        var settings = profiles[i].settings
        change(&settings)
        guard settings != profiles[i].settings else { return }
        profiles[i].settings = settings
        save()
        if appliesGlobally { defaults.set(settings.reduceInterfaceMotion, forKey: MotionPreference.key) }
    }

    // MARK: - Photos

    func image(for id: UUID) -> UIImage? {
        if let cached = images[id] { return cached }
        guard profiles.first(where: { $0.id == id })?.hasImage == true,
              let data = try? Data(contentsOf: imageURL(for: id)),
              let image = UIImage(data: data) else { return nil }
        images[id] = image
        return image
    }

    /// Stores (or, with nil, removes) a profile photo. The picked image is downscaled off the main
    /// thread with ImageIO (max 512 px, orientation applied) and saved as a file-protected JPEG.
    @discardableResult
    func setImage(_ data: Data?, for id: UUID) async -> Bool {
        guard index(of: id) != nil else { return false }
        let url = imageURL(for: id)
        guard let data else {
            try? FileManager.default.removeItem(at: url)
            images[id] = nil
            if let i = index(of: id) { profiles[i].hasImage = false }
            save()
            imageRevision += 1
            return true
        }
        let jpeg = await Task.detached(priority: .userInitiated) { ProfileImageProcessing.avatarJPEG(from: data) }.value
        guard let jpeg, let image = UIImage(data: jpeg) else { return false }
        do {
            try jpeg.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            return false
        }
        guard let i = index(of: id) else {
            try? FileManager.default.removeItem(at: url)
            return false
        }
        images[id] = image
        profiles[i].hasImage = true
        save()
        imageRevision += 1
        return true
    }

    // MARK: - Internals

    private func activate(_ id: UUID) {
        activeID = id
        defaults.set(id.uuidString, forKey: Self.activeKey)
        if appliesGlobally { apply(active, animated: true) }
    }

    private func apply(_ profile: UserProfile, animated: Bool) {
        defaults.set(profile.settings.reduceInterfaceMotion, forKey: MotionPreference.key)
        if let raw = profile.settings.themeID, let theme = ThemeID(rawValue: raw), ThemeStore.shared.selected != theme {
            if animated && !MotionPreference.reduced {
                withAnimation(Motion.theme) { ThemeStore.shared.selected = theme }
            } else {
                ThemeStore.shared.selected = theme
            }
        }
        // §G3: the profile's ambient. Appearance only: TV connections, input and helpers live in
        // models above the themed views and are never touched here.
        if let style = profile.settings.ambient, ThemeStore.shared.ambient != style {
            if animated && !MotionPreference.reduced {
                withAnimation(Motion.theme) { ThemeStore.shared.ambient = style }
            } else {
                ThemeStore.shared.ambient = style
            }
        }
        AddonStore.shared.load(profile: profile.id)
    }

    private func recordTheme(_ theme: ThemeID) {
        guard let i = index(of: activeID), profiles[i].settings.themeID != theme.rawValue else { return }
        profiles[i].settings.themeID = theme.rawValue
        save()
    }

    private func recordAmbient(_ style: AmbientStyle) {
        guard let i = index(of: activeID), profiles[i].settings.ambientID != style.rawValue else { return }
        profiles[i].settings.ambientID = style.rawValue
        save()
    }

    private func index(of id: UUID) -> Int? { profiles.firstIndex { $0.id == id } }

    private func nextTint() -> Int {
        let used = Set(profiles.map(\.tint))
        return (0..<UserProfile.tintCount).first { !used.contains($0) } ?? profiles.count % UserProfile.tintCount
    }

    private func imageURL(for id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).jpg") }

    private func save() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        try? data.write(to: directory.appendingPathComponent(Self.fileName),
                        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static func read(_ url: URL) -> [UserProfile] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([UserProfile].self, from: data)) ?? []
    }

    nonisolated static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("GlassRemote/Profiles", isDirectory: true)
    }
}

/// Avatar downscaling. Uses an ImageIO thumbnail so a 48-megapixel photo is never fully decoded.
enum ProfileImageProcessing {
    static func avatarJPEG(from data: Data, maxPixel: Int = 512) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.85)
    }
}
