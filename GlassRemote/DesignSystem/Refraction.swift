import SwiftUI

/// Phase 9 refraction. Native Liquid Glass already lenses its backdrop at the rim, but over the app's
/// smooth canvas that bending is all but invisible (a displaced gradient looks like the same gradient).
/// Where a control needs a visible optical response, the content directly beneath its glass gets this
/// bounded lens: the `glassRefraction` shader in `Refraction.metal`, limited to the glass shape.
///
/// Rules (PHASE-7-NOTES.md, Phase 9 §0):
/// - Apply it to the content UNDER a glass element, never to the glass element itself (a layer
///   effect cannot see behind its own view).
/// - Only small, moving lenses use it (the scrub selector bubble, the volume thumb). Large surfaces
///   keep native glass alone: a layer shader over a whole page would rasterise the page every frame.
/// - Reduce Motion (system or in-app), Increase Contrast and Reduce Transparency turn it off; the
///   native glass stays, so the control looks and works the same without the bending.
struct RefractionStyle: Equatable, Sendable {
    /// Interior magnification toward the lens centre (0 = none).
    var zoom: CGFloat
    /// Width of the rim band where light bends, in points.
    var rim: CGFloat
    /// How far the rim reaches outward, in points.
    var bend: CGFloat
    /// Per-channel spread on the rim, in points (0 = none).
    var dispersion: CGFloat

    /// Scrub selector bubble (dock, Mouse / D-pad, segmented controls): text stays readable.
    static let selector = RefractionStyle(zoom: 0.10, rim: 9, bend: 5, dispersion: 0.8)
    /// Volume thumb: a rounder, stronger lens over the fill edge.
    static let thumb = RefractionStyle(zoom: 0.14, rim: 10, bend: 6, dispersion: 1.0)
}

/// When the lens runs and how far it may sample (pure, unit tested).
enum RefractionPolicy {
    /// Lenses smaller than this on either side are skipped: the bending would be sub-pixel noise.
    static let minimumSide: CGFloat = 12

    static func isEnabled(reduceMotion: Bool, increaseContrast: Bool, reduceTransparency: Bool, lens: CGRect) -> Bool {
        guard !reduceMotion, !increaseContrast, !reduceTransparency else { return false }
        guard lens.minX.isFinite, lens.minY.isFinite, lens.width.isFinite, lens.height.isFinite else { return false }
        return lens.width >= minimumSide && lens.height >= minimumSide
    }

    /// The furthest any pixel samples from itself, per axis (SwiftUI must rasterise that margin).
    static func maxSampleOffset(lens: CGRect, style: RefractionStyle) -> CGSize {
        let reach = style.bend + style.dispersion + 1
        return CGSize(width: max(style.zoom, 0) * max(lens.width, 0) / 2 + reach,
                      height: max(style.zoom, 0) * max(lens.height, 0) / 2 + reach)
    }
}

/// Swift mirror of `Refraction.metal` (green channel), so the optics can be unit tested.
enum RefractionGeometry {
    static func clampedRadius(_ radius: CGFloat, lens: CGRect) -> CGFloat {
        max(0, min(radius, min(lens.width, lens.height) / 2))
    }

    /// Signed distance to a rounded rectangle centred on the origin: negative inside.
    static func distance(_ p: CGPoint, halfSize: CGSize, radius: CGFloat) -> CGFloat {
        let qx = abs(p.x) - halfSize.width + radius
        let qy = abs(p.y) - halfSize.height + radius
        return hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - radius
    }

    static func normal(_ p: CGPoint, halfSize: CGSize, radius: CGFloat) -> CGPoint {
        let e: CGFloat = 0.5
        let dx = distance(CGPoint(x: p.x + e, y: p.y), halfSize: halfSize, radius: radius)
            - distance(CGPoint(x: p.x - e, y: p.y), halfSize: halfSize, radius: radius)
        let dy = distance(CGPoint(x: p.x, y: p.y + e), halfSize: halfSize, radius: radius)
            - distance(CGPoint(x: p.x, y: p.y - e), halfSize: halfSize, radius: radius)
        let length = hypot(dx, dy)
        return length > 0.0001 ? CGPoint(x: dx / length, y: dy / length) : .zero
    }

    /// Where the shader samples for `position`. Outside the lens shape this is `position` itself.
    static func samplePoint(for position: CGPoint, lens: CGRect, cornerRadius: CGFloat, style: RefractionStyle) -> CGPoint {
        let half = CGSize(width: lens.width / 2, height: lens.height / 2)
        guard half.width > 0, half.height > 0 else { return position }
        let radius = clampedRadius(cornerRadius, lens: lens)
        let centre = CGPoint(x: lens.midX, y: lens.midY)
        let p = CGPoint(x: position.x - centre.x, y: position.y - centre.y)
        let d = distance(p, halfSize: half, radius: radius)
        guard d < 0 else { return position }
        let depth = min(max(-d / max(style.rim, 0.001), 0), 1)
        let edge = (1 - depth) * (1 - depth)
        let n = normal(p, halfSize: half, radius: radius)
        return CGPoint(x: centre.x + p.x * (1 - style.zoom) + n.x * style.bend * edge,
                       y: centre.y + p.y * (1 - style.zoom) + n.y * style.bend * edge)
    }
}

extension View {
    /// Bends the pixels of this view that sit inside `lens` (a rounded rectangle in this view's own
    /// coordinates) like thick glass. Apply it to the content beneath a glass element. The lens
    /// animates with the surrounding transaction, so it tracks a springing glass bubble frame by frame.
    func refractiveLens(_ lens: CGRect, cornerRadius: CGFloat, style: RefractionStyle = .selector, active: Bool = true) -> some View {
        modifier(RefractiveLensModifier(lens: lens, cornerRadius: cornerRadius, style: style, active: active))
    }
}

private struct RefractiveLensModifier: ViewModifier, Animatable {
    var lens: CGRect
    var cornerRadius: CGFloat
    let style: RefractionStyle
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(lens.origin.x, lens.origin.y), AnimatablePair(lens.size.width, lens.size.height)) }
        set {
            lens = CGRect(x: newValue.first.first, y: newValue.first.second,
                          width: newValue.second.first, height: newValue.second.second)
        }
    }

    func body(content: Content) -> some View {
        let enabled = active && RefractionPolicy.isEnabled(
            reduceMotion: reduceMotion || MotionPreference.reduced,
            increaseContrast: contrast == .increased,
            reduceTransparency: reduceTransparency,
            lens: lens)
        let radius = RefractionGeometry.clampedRadius(cornerRadius, lens: lens)
        let shader = ShaderLibrary.glassRefraction(
            .float4(lens.minX, lens.minY, lens.width, lens.height),
            .float(radius),
            .float(style.zoom),
            .float(style.rim),
            .float(style.bend),
            .float(style.dispersion))
        return content.layerEffect(shader,
                                   maxSampleOffset: RefractionPolicy.maxSampleOffset(lens: lens, style: style),
                                   isEnabled: enabled)
    }
}
