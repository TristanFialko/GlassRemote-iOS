import SwiftUI
import UIKit

/// Continuation §F2: how hero artwork fills its region. Art is always scaled uniformly (never
/// stretched) and always covers the region (no side strips). Where it has to be cropped, the crop keeps
/// the upper part of the frame, where faces and title treatments usually sit, instead of the centre.
/// A portrait poster in a wide landscape region would be cut to a thin band of its middle, so it is
/// shown whole on the trailing side over a soft wash made from its own colours.
enum HeroArtworkPolicy {
    enum Crop: Equatable {
        case fill(focal: CGPoint)
        case posterInset(PosterInset)
    }

    struct PosterInset: Equatable {
        let size: CGSize
        let trailingMargin: CGFloat
        let topMargin: CGFloat
    }

    /// Wide key art: keep the upper third in frame.
    static let backdropFocal = CGPoint(x: 0.5, y: 0.3)
    /// Posters: faces and titles sit high, keep the top in frame.
    static let posterFocal = CGPoint(x: 0.5, y: 0.2)
    /// Art narrower than this is treated as a poster.
    static let posterAspect: CGFloat = 0.9
    /// A poster is shown whole when filling would cut away more than this share of its height.
    static let maxPosterCrop: CGFloat = 0.45
    static let posterInsetHeight: CGFloat = 0.74

    static func focal(forImage image: CGSize) -> CGPoint {
        guard image.width > 0, image.height > 0 else { return backdropFocal }
        return image.width / image.height < posterAspect ? posterFocal : backdropFocal
    }

    /// Share of the image (along the cropped axis) that a uniform fill throws away.
    static func cropShare(image: CGSize, region: CGSize) -> CGFloat {
        guard image.width > 0, image.height > 0, region.width > 0, region.height > 0 else { return 0 }
        let scale = max(region.width / image.width, region.height / image.height)
        let shownWidth = region.width / (image.width * scale)
        let shownHeight = region.height / (image.height * scale)
        return 1 - min(shownWidth, shownHeight)
    }

    static func crop(image: CGSize, region: CGSize, allowsPosterInset: Bool = true, focal: CGPoint? = nil) -> Crop {
        let resolvedFocal = focal ?? Self.focal(forImage: image)
        guard allowsPosterInset, image.width > 0, image.height > 0, region.width > 0, region.height > 0,
              image.width / image.height < posterAspect,
              cropShare(image: image, region: region) > maxPosterCrop else { return .fill(focal: resolvedFocal) }
        let height = region.height * posterInsetHeight
        let width = min(height * image.width / image.height, region.width * 0.42)
        let fitted = CGSize(width: width, height: width * image.height / image.width)
        return .posterInset(PosterInset(size: fitted,
                                        trailingMargin: max(region.width * 0.07, 16),
                                        topMargin: max((region.height - fitted.height) * 0.4, 0)))
    }

    /// Frame of the uniformly scaled image relative to the region's origin (it covers the region).
    static func fillRect(image: CGSize, region: CGSize, focal: CGPoint) -> CGRect {
        guard image.width > 0, image.height > 0 else { return CGRect(origin: .zero, size: region) }
        let scale = max(region.width / image.width, region.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        let fx = min(max(focal.x, 0), 1), fy = min(max(focal.y, 0), 1)
        return CGRect(x: (region.width - size.width) * fx, y: (region.height - size.height) * fy,
                      width: size.width, height: size.height)
    }
}

/// A tiny copy of the artwork, drawn enlarged as a soft colour wash. Smoothing a 24 px image gives
/// the look of a heavy blur for free: no live blur filter, nothing re-rendered while scrolling.
enum ArtworkWash {
    static let width: CGFloat = 24

    static func make(from image: UIImage) -> UIImage? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let size = CGSize(width: width, height: max((width * image.size.height / image.size.width).rounded(), 1))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

/// Hero artwork following `HeroArtworkPolicy`. Loads through `ArtworkCache` like `CachedArtwork`.
struct FocalArtwork<Placeholder: View>: View {
    let url: URL?
    var fallbackURL: URL? = nil
    var allowsPosterInset = true
    var focal: CGPoint? = nil
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var wash: UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let image {
                    render(image, in: geo.size).transition(.opacity)
                } else {
                    placeholder().frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .task(id: [url, fallbackURL]) {
            image = nil; wash = nil
            for candidate in [url, fallbackURL].compactMap({ $0 }) {
                if let hit = ArtworkCache.shared.cached(candidate) { show(hit, animated: false); return }
                if let loaded = await ArtworkCache.shared.image(for: candidate) {
                    if Task.isCancelled { return }
                    show(loaded, animated: true)
                    return
                }
            }
        }
    }

    private func show(_ loaded: UIImage, animated: Bool) {
        let needsWash = loaded.size.width / max(loaded.size.height, 1) < HeroArtworkPolicy.posterAspect
        let newWash = needsWash && allowsPosterInset ? ArtworkWash.make(from: loaded) : nil
        if animated {
            withAnimation(Motion.adaptive(Motion.fade)) { image = loaded; wash = newWash }
        } else {
            image = loaded; wash = newWash
        }
    }

    @ViewBuilder
    private func render(_ image: UIImage, in size: CGSize) -> some View {
        switch HeroArtworkPolicy.crop(image: image.size, region: size, allowsPosterInset: allowsPosterInset, focal: focal) {
        case .fill(let focal):
            let rect = HeroArtworkPolicy.fillRect(image: image.size, region: size, focal: focal)
            Image(uiImage: image).resizable()
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
                .frame(width: size.width, height: size.height)
        case .posterInset(let inset):
            ZStack(alignment: .topTrailing) {
                Group {
                    if let wash {
                        Image(uiImage: wash).resizable().interpolation(.high)
                    } else {
                        Image(uiImage: image).resizable()
                    }
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .overlay(Color.black.opacity(0.18))
                .clipped()
                Image(uiImage: image).resizable()
                    .frame(width: inset.size.width, height: inset.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
                    .padding(.trailing, inset.trailingMargin)
                    .padding(.top, inset.topMargin)
            }
            .frame(width: size.width, height: size.height)
        }
    }
}
