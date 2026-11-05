import SwiftUI
import UIKit

/// Decoded, downsampled app icons.
///
/// The icon assets are 1024 px PNGs. Showing the Apps grid used to decode every one of them on
/// the main thread at the moment the grid expanded, which is the small hitch. They are now
/// decoded once, off the main thread, at ~200 px and kept in memory; the grid just draws bitmaps.
@MainActor
final class AppIconCache {
    static let shared = AppIconCache()
    private var images: [String: UIImage] = [:]
    private var warming = false

    func image(_ assetName: String) -> UIImage? { images[assetName] }

    /// Call once at launch with every asset name the UI can show.
    func prewarm(_ names: [String]) {
        guard !warming else { return }
        warming = true
        Task.detached(priority: .utility) {
            for name in names {
                guard let original = UIImage(named: name) else { continue }
                let size = CGSize(width: 200, height: 200 * original.size.height / max(original.size.width, 1))
                let thumb = await original.byPreparingThumbnail(ofSize: size) ?? original
                await MainActor.run { AppIconCache.shared.images[name] = thumb }
            }
        }
    }
}

/// App tile artwork: the cached bitmap when ready, otherwise the catalogue image.
struct AppIconImage: View {
    let asset: String
    @State private var cached: UIImage?

    var body: some View {
        Group {
            if let image = cached ?? AppIconCache.shared.image(asset) {
                Image(uiImage: image).resizable().interpolation(.medium)
            } else {
                Image(asset).resizable()
            }
        }
        .scaledToFit()
    }
}
