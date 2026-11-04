import Foundation

/// Local-only favourite app packages (UserDefaults). Pure ordering helper is unit tested.
@MainActor
final class AppFavourites: ObservableObject {
    static let shared = AppFavourites()
    private let key = "glassRemote.favouriteApps.v1"

    @Published private(set) var packages: [String]

    init(defaults: UserDefaults = .standard) {
        packages = defaults.stringArray(forKey: "glassRemote.favouriteApps.v1") ?? []
    }

    func contains(_ package: String) -> Bool { packages.contains(package) }

    func toggle(_ package: String) {
        packages = Self.toggled(packages, package)
        UserDefaults.standard.set(packages, forKey: key)
    }

    nonisolated static func toggled(_ list: [String], _ package: String) -> [String] {
        list.contains(package) ? list.filter { $0 != package } : list + [package]
    }
}
