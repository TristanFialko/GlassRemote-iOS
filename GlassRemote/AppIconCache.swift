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

/// Tile artwork for an app without bundled art (discovered TV apps, Android TV Settings):
/// an SF Symbol when given, otherwise the name's first letter.
struct GenericAppIcon: View {
    let name: String
    var symbol: String?

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                LinearGradient(colors: [Color.ink.opacity(0.22), Color.ink.opacity(0.08)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: side * 0.42, weight: .semibold))
                } else {
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: side * 0.46, weight: .semibold, design: .rounded))
                }
            }
            .foregroundStyle(Color.inkAlpha(0.86))
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }
}
