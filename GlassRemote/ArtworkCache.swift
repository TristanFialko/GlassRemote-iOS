import SwiftUI
import UIKit

/// In-memory + URLCache-backed image loader for remote artwork (posters, backdrops).
/// Used by Discover and Player. Nothing is written to disk by this type itself; `URLCache`
/// handles HTTP caching. Requests are https-only and de-duplicated per URL.
@MainActor
final class ArtworkCache {
    static let shared = ArtworkCache()

    private let memory = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private let session: URLSession

    init() {
        memory.countLimit = 120
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 64 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 12
        session = URLSession(configuration: config)
    }

    func cached(_ url: URL) -> UIImage? { memory.object(forKey: url as NSURL) }

    func image(for url: URL) async -> UIImage? {
        guard url.scheme == "https" else { return nil }
        if let hit = cached(url) { return hit }
        if let task = inFlight[url] { return await task.value }
        let session = self.session
        let task = Task<UIImage?, Never> {
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return UIImage(data: data)
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { memory.setObject(image, forKey: url as NSURL) }
        return image
    }
}

/// AsyncImage-like view backed by `ArtworkCache`. Shows `placeholder` until (or unless) it loads.
struct CachedArtwork<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            if let hit = ArtworkCache.shared.cached(url) { image = hit; return }
            image = nil
            let loaded = await ArtworkCache.shared.image(for: url)
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
        }
    }
}

/// Artwork the media session does NOT provide (`dumpsys media_session` prints no bitmap or URL).
/// The only real poster the app can show is one it already knows: when the user launched a title
/// from Discover and the session's title matches it, that poster is used. Otherwise the Player
/// falls back to the app's own icon.
@MainActor
final class PlayerArtworkStore: ObservableObject {
    static let shared = PlayerArtworkStore()

    struct Hint: Equatable { var title: String; var posterURL: URL? }
    @Published private(set) var hint: Hint?

    func remember(title: String, posterURL: URL?) {
        hint = Hint(title: title, posterURL: posterURL)
    }

    /// Poster for the current session, only when the session title really matches the hint.
    func posterURL(forSessionTitle title: String) -> URL? {
        guard let hint, let url = hint.posterURL else { return nil }
        return Self.matches(session: title, hint: hint.title) ? url : nil
    }

    nonisolated static func matches(session: String, hint: String) -> Bool {
        let a = session.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let b = hint.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard a.count >= 3, b.count >= 3 else { return false }
        return a == b || a.hasPrefix(b) || b.hasPrefix(a)
    }
}


extension ArtworkCache {
    /// Average colour of an image (drawn into 1x1), for ambient lighting behind artwork.
    nonisolated static func averageColor(of image: UIImage) -> Color? {
        guard let cg = image.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return Color(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
    }
}
