import SwiftUI
import UIKit

/// Phase 9 §A2: the artwork the Player's full-screen background is made from. The Player reports the
/// artwork it shows; its prominent colours are extracted once per artwork, off the main thread (and
/// kept for a few recent titles), never per frame or per poll.
@MainActor
final class PlayerBackdropStore: ObservableObject {
    static let shared = PlayerBackdropStore()

    struct Backdrop: Equatable {
        let url: URL
        /// Theme independent; the view turns them into a legible palette for the current theme.
        let swatches: [ArtworkSwatch]
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
            guard let image else { self.publish(nil); return }
            // A 32 x 48 sample: clustering it touches a few hundred histogram bins.
            let swatches = await Task.detached(priority: .userInitiated) {
                NowPlayingPaletteExtractor.swatches(from: image)
            }.value
            guard !Task.isCancelled, self.url == newURL else { return }
            guard !swatches.isEmpty else { self.publish(nil); return }
            let made = Backdrop(url: newURL, swatches: swatches)
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

/// Phase 9 §A2: the Player's full-screen background. `RootPagerView` draws it as part of the one root
/// canvas, under the dock, the landscape rail and every page, so there is no seam at the rail's edge.
/// It shows only while Now Playing is presented. With artwork it is a wash of the artwork's prominent
/// colours; without, the same wash made from the theme's accents (or GlassRemote's deep blue when the
/// theme is neutral). A new artwork's wash cross-fades over the old one.
struct PlayerBackdrop: View {
    var visible: Bool
    @ObservedObject private var store = PlayerBackdropStore.shared
    @Environment(\.glassTheme) private var theme

    var body: some View {
        ZStack {
            if visible, let backdrop = store.backdrop,
               let palette = NowPlayingPalette.make(swatches: backdrop.swatches, light: theme.isLight) {
                NowPlayingWash(palette: palette, light: theme.isLight)
                    .id(backdrop.url)
                    .transition(.opacity)
            } else if visible {
                NowPlayingWash(palette: NowPlayingPalette.fallback(accent: NowPlayingPalette.Tone(theme.accent),
                                                                   secondary: NowPlayingPalette.Tone(theme.accent2),
                                                                   light: theme.isLight),
                               light: theme.isLight)
                    .transition(.opacity)
            }
        }
        .animation(Motion.adaptive(Motion.artwork), value: visible)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
