#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Phase 9 refraction: a bounded optical lens for the content directly beneath a Liquid Glass element.
//
// SwiftUI's layerEffect can only sample the layer it is applied to, never what lies behind a view, so
// this shader is applied to the content under the glass (labels, the volume fill) and bends only the
// pixels inside the glass element's rounded-rectangle shape. Every pixel outside that shape is
// returned untouched, so there is no rectangular shader bound and no seam beyond the glass edge.
//
// Inside the shape: a gentle magnification toward the lens centre, a rim band where light bends
// outward (a convex glass edge), and a small per-channel spread on that rim (dispersion).
//
// RefractionGeometry in Refraction.swift mirrors this maths for the unit tests; keep them in step.

static float lensDistance(float2 p, float2 halfSize, float radius) {
    float2 q = abs(p) - halfSize + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

static float2 lensNormal(float2 p, float2 halfSize, float radius) {
    const float e = 0.5;
    float dx = lensDistance(p + float2(e, 0.0), halfSize, radius) - lensDistance(p - float2(e, 0.0), halfSize, radius);
    float dy = lensDistance(p + float2(0.0, e), halfSize, radius) - lensDistance(p - float2(0.0, e), halfSize, radius);
    float2 g = float2(dx, dy);
    float l = length(g);
    return l > 0.0001 ? g / l : float2(0.0);
}

/// lens: x, y, width, height of the glass shape in the layer's coordinates (points).
/// radius: corner radius, already clamped to half the short side.
/// zoom: interior magnification (0 = none). rim: width of the bending band (pt).
/// bend: how far the rim reaches outward (pt). dispersion: per-channel spread on the rim (pt).
[[ stitchable ]] half4 glassRefraction(float2 position, SwiftUI::Layer layer,
                                      float4 lens, float radius, float zoom, float rim, float bend, float dispersion) {
    float2 halfSize = lens.zw * 0.5;
    if (halfSize.x <= 0.0 || halfSize.y <= 0.0) {
        return layer.sample(position);
    }
    float2 centre = lens.xy + halfSize;
    float2 p = position - centre;
    float d = lensDistance(p, halfSize, radius);
    if (d >= 0.0) {
        return layer.sample(position);
    }
    float depth = clamp(-d / max(rim, 0.001), 0.0, 1.0);
    float edge = (1.0 - depth) * (1.0 - depth);
    float2 n = lensNormal(p, halfSize, radius);
    float2 base = centre + p * (1.0 - zoom) + n * (bend * edge);
    half4 g = layer.sample(base);
    if (dispersion <= 0.0 || edge <= 0.0) {
        return g;
    }
    float2 spread = n * (dispersion * edge);
    half4 r = layer.sample(base + spread);
    half4 b = layer.sample(base - spread);
    // Premultiplied alpha: take the widest coverage so no channel exceeds its alpha.
    half a = max(max(r.a, g.a), b.a);
    return half4(r.r, g.g, b.b, a);
}
