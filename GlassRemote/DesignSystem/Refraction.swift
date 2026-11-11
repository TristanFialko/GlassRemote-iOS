import SwiftUI

/// Phase 9 refraction. Native Liquid Glass already lenses its backdrop at the rim, but over the app's
/// smooth canvas that bending is all but invisible (a displaced gradient looks like the same gradient).
/// Where a control needs a visible optical response, the content directly beneath its glass gets this
/// bounded lens: the `glassRefraction` shader in `Refraction.metal`, limited to the glass shape.
///
/// Continuation §B: the lens no longer magnifies. The interior samples itself (fixed centre, text at
/// its real size); a stronger, smooth outward bend lives only in the rim band, and a restrained
/// colour spread only at the very edge.
///
/// Rules (PHASE-7-NOTES.md, Phase 9 §0 and continuation §B):
/// - Apply it to the content UNDER a glass element, never to the glass element itself (a layer
///   effect cannot see behind its own view). For the same reason the Apps folder's edge cannot
///   refract the Remote behind it without rasterising the whole page every frame; it keeps native
///   glass.
/// - Only small, moving lenses use it (the scrub selector bubble of the dock, rail and segmented
///   controls, the volume thumb). Large surfaces keep native glass alone.
/// - Reduce Motion (system or in-app), Increase Contrast and Reduce Transparency turn it off; the
///   native glass stays, so the control looks and works the same without the bending.
struct RefractionStyle: Equatable, Sendable {
    /// Width of the rim band where light bends, in points (capped per lens, see `RefractionGeometry.rimWidth`).
    var rim: CGFloat
    /// How far the rim reaches outward at the glass edge, in points.
    var bend: CGFloat
    /// Per-channel spread at the glass edge, in points (0 = none).
    var dispersion: CGFloat

    /// Scrub selector bubble (dock, rail, Mouse / D-pad, segmented controls).
    static let selector = RefractionStyle(rim: 12, bend: 9, dispersion: 1.2)
    /// Volume thumb: a rounder, stronger edge over the track.
    static let thumb = RefractionStyle(rim: 14, bend: 11, dispersion: 1.4)

    /// Phase 9 checkpoint values (before continuation §B), kept so tests prove the rim got stronger.
    static let previousSelectorBend: CGFloat = 5
    static let previousThumbBend: CGFloat = 6
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
    /// With no magnification term this no longer grows with the lens size.
    static func maxSampleOffset(lens: CGRect, style: RefractionStyle) -> CGSize {
        let reach = max(style.bend, 0) + max(style.dispersion, 0) + 1
        return CGSize(width: reach, height: reach)
    }
}

/// Swift mirror of `Refraction.metal` (green channel for `samplePoint`, the red/blue offset for
/// `spread`), so the optics can be unit tested.
enum RefractionGeometry {
    /// The rim band may cover at most this share of the half short side, so a centre always stays fixed.
    static let maxRimShare: CGFloat = 0.75

    static func clampedRadius(_ radius: CGFloat, lens: CGRect) -> CGFloat {
        max(0, min(radius, min(lens.width, lens.height) / 2))
    }

    static func rimWidth(lens: CGRect, style: RefractionStyle) -> CGFloat {
        max(0, min(style.rim, min(lens.width, lens.height) / 2 * maxRimShare))
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

    /// Rim position for `position`: nil outside the shape or in the interior, otherwise
    /// t (0 at the inner edge of the rim, 1 at the glass edge) and the outward normal.
    private static func rim(for position: CGPoint, lens: CGRect, cornerRadius: CGFloat,
                            style: RefractionStyle) -> (t: CGFloat, normal: CGPoint)? {
        let half = CGSize(width: lens.width / 2, height: lens.height / 2)
        guard half.width > 0, half.height > 0 else { return nil }
        let radius = clampedRadius(cornerRadius, lens: lens)
        let p = CGPoint(x: position.x - lens.midX, y: position.y - lens.midY)
        let d = distance(p, halfSize: half, radius: radius)
        guard d < 0 else { return nil }
        let band = rimWidth(lens: lens, style: style)
        guard band > 0 else { return nil }
        let depth = min(max(-d / band, 0), 1)
        guard depth < 1 else { return nil }
        return (1 - depth, normal(p, halfSize: half, radius: radius))
    }

    /// The smoothstep rim profile: 0 at the inner edge of the band, 1 at the glass edge.
    static func edgeWeight(_ t: CGFloat) -> CGFloat {
        let c = min(max(t, 0), 1)
        return c * c * (3 - 2 * c)
    }

    /// Where the shader samples for `position`. Outside the lens shape, and anywhere deeper than the
    /// rim band, this is `position` itself (no magnification).
    static func samplePoint(for position: CGPoint, lens: CGRect, cornerRadius: CGFloat, style: RefractionStyle) -> CGPoint {
        guard let r = rim(for: position, lens: lens, cornerRadius: cornerRadius, style: style) else { return position }
        let edge = edgeWeight(r.t)
        return CGPoint(x: position.x + r.normal.x * style.bend * edge,
                       y: position.y + r.normal.y * style.bend * edge)
    }

    /// The red / blue channels' extra offset from the green sample (points). Zero away from the edge.
    static func spread(for position: CGPoint, lens: CGRect, cornerRadius: CGFloat, style: RefractionStyle) -> CGFloat {
        guard let r = rim(for: position, lens: lens, cornerRadius: cornerRadius, style: style) else { return 0 }
        let chroma = style.dispersion * r.t * r.t * r.t
        return chroma <= 0.001 ? 0 : chroma
    }
}

extension View {
    /// Bends the pixels of this view that sit inside `lens` (a rounded rectangle in this view's own
    /// coordinates) like the edge of thick glass. Apply it to the content beneath a glass element. The
    /// lens animates with the surrounding transaction, so it tracks a springing glass bubble frame by frame.
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
            .float(style.rim),
            .float(style.bend),
            .float(style.dispersion))
        return content.layerEffect(shader,
                                   maxSampleOffset: RefractionPolicy.maxSampleOffset(lens: lens, style: style),
                                   isEnabled: enabled)
    }
}
