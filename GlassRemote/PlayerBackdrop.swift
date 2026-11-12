import SwiftUI
import UIKit

/// Phase 9 §A2: the artwork the Player's full-screen background is made from. The Player reports the
/// artwork it shows; the wash and its contrast profile are made once per artwork (and kept for a few
/// recent titles), never per frame or per poll.
@MainActor
final class PlayerBackdropStore: ObservableObject {
    static let shared = PlayerBackdropStore()

    struct Backdrop: Equatable {
        let url: URL
        let wash: UIImage
        let profile: PlayerBackdropPolicy.Profile

        static func == (lhs: Backdrop, rhs: Backdrop) -> Bool { lhs.url == rhs.url && lhs.profile == rhs.profile }
    }

    @Published private(set) var backdrop: Backdrop?

    private var url: URL?
    private var task: Task<Void, Never>?
    private var cache: [URL: Backdrop] = [:]
    private var order: [URL] = []
    private static let cacheLimit = 12

    /// Recomputes only when the artwork really changes; repeated reports of the same URL do nothing.
    func show(_ newURL: URL?) {
        guard newURL != url else { return }
        url = newURL
        task?.cancel()
        task = nil
        guard let newURL else { publish(nil); return }
        if let hit = cache[newURL] { publish(hit); return }
        task = Task { [weak self] in
            let image = await ArtworkCache.shared.image(for: newURL)
            guard let self, !Task.isCancelled, self.url == newURL else { return }
            // A wash is 24 px wide: making it and reading its luminance touches a few hundred pixels.
            guard let image, let wash = ArtworkWash.make(from: image) else { self.publish(nil); return }
            let made = Backdrop(url: newURL, wash: wash, profile: PlayerBackdropPolicy.profile(of: wash))
            self.remember(made)
            self.publish(made)
        }
    }

    private func publish(_ new: Backdrop?) {
        guard new != backdrop else { return }
        withAnimation(Motion.adaptive(Motion.artwork)) { backdrop = new }
    }

    private func remember(_ made: Backdrop) {
        cache[made.url] = made
        order.removeAll { $0 == made.url }
        order.append(made.url)
        while order.count > Self.cacheLimit { cache.removeValue(forKey: order.removeFirst()) }
    }
}

/// Phase 9 §A2: the Player's full-screen artwork background. `RootPagerView` draws it as part of the
/// one root canvas, under the dock, the landscape rail and every page, so there is no seam at the
/// rail's edge. It shows only while Now Playing is presented; without artwork it draws one continuous
/// full-screen wash of the theme accent over the theme's own canvas (v5 §3), not a small glow.
struct PlayerBackdrop: View {
    var visible: Bool
    @ObservedObject private var store = PlayerBackdropStore.shared
    @Environment(\.glassTheme) private var theme

    var body: some View {
        ZStack {
            if visible, let backdrop = store.backdrop {
                PlayerBackdropCanvas(backdrop: backdrop, light: theme.isLight)
                    .id(backdrop.url)
                    .transition(.opacity)
            } else if visible {
                PlayerFallbackCanvas(accent: theme.accent, adaptive: theme.id == .adaptive)
                    .transition(.opacity)
            }
        }
        .animation(Motion.adaptive(Motion.artwork), value: visible)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Enlarged, softened artwork (a tiny wash scaled up, no live blur filter), then a scrim from
/// `PlayerBackdropPolicy` that keeps the page's ink legible over it.
private struct PlayerBackdropCanvas: View {
    let backdrop: PlayerBackdropStore.Backdrop
    let light: Bool

    var body: some View {
        let scrim = PlayerBackdropPolicy.scrimOpacity(profile: backdrop.profile, light: light)
        let tone: Color = light ? .white : .black
        GeometryReader { geo in
            let rect = PlayerBackdropPolicy.cropRect(image: backdrop.wash.size, canvas: geo.size)
            Image(uiImage: backdrop.wash)
                .resizable()
                .interpolation(.high)
                .frame(width: rect.width, height: rect.height)
                .scaleEffect(PlayerBackdropPolicy.enlargement)
                .offset(x: rect.midX - geo.size.width / 2, y: rect.midY - geo.size.height / 2)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
        .overlay { tone.opacity(scrim) }
        .overlay {
            LinearGradient(colors: [tone.opacity(0), tone.opacity(PlayerBackdropPolicy.footShade)],
                           startPoint: .center, endPoint: .bottom)
        }
    }
}

/// v5 §3: the no-artwork background. One continuous full-screen wash of the theme accent, drawn in the
/// root canvas (under the dock and the rail). A gradient is already soft: no blur, nothing per tick.
private struct PlayerFallbackCanvas: View {
    let accent: Color
    let adaptive: Bool

    var body: some View {
        let opacity = PlayerBackdropPolicy.fallbackOpacity(adaptive: adaptive)
        LinearGradient(colors: [accent.opacity(opacity.top), accent.opacity(opacity.bottom)],
                       startPoint: .top, endPoint: .bottom)
    }
}
