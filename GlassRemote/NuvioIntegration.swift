import Foundation

/// Boundary for Nuvio/Stremio ecosystem integration.
///
/// Installed addons are configured inside Nuvio on the TV. They are not automatically addressable
/// from an iPhone: addon manifests, per-addon configuration URLs and debrid credentials are private
/// inputs. Glass Remote therefore enriches titles through the verified Cinemeta protocol and hands
/// off to the existing TV app, but never guesses stream endpoints or exposes credentials.
enum NuvioIntegration {
    static let limitation = "Nuvio addons remain configured on the TV; source and subtitle availability is not shown unless Nuvio exposes a documented companion API."
    static let providerNote = "Source integrations stay provider-agnostic, so Real-Debrid and Torbox remain the addon's responsibility."

    static var hasVerifiedCompanionAPI: Bool { false }

    static func handoffDescription(for title: StremioTitle) -> String {
        "Open \(title.name) in Nuvio to use your configured catalog, sources and subtitles."
    }
}
