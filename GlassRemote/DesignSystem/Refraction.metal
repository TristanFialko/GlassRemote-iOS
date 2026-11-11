#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Phase 9 refraction: a bounded optical lens for the content directly beneath a Liquid Glass element.
//
// SwiftUI's layerEffect can only sample the layer it is applied to, never what lies behind a view, so
// this shader is applied to the content under the glass (labels, the volume track) and bends only the
// pixels inside the glass element's rounded-rectangle shape. Every pixel outside that shape is
// returned untouched, so there is no rectangular shader bound and no seam beyond the glass edge.
//
// Continuation §B: no magnification. The interior (everything deeper than the rim band) samples
// itself, so the centre stays still and text under the lens keeps its size. Only the rim bends:
// light is pulled outward along the edge normal with a smooth (smoothstep) profile that is zero at
// the inner edge of the band and strongest at the glass edge, like the thick convex edge of real
// glass. A restrained per-channel spread is confined to the outermost part of the rim.
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
/// rim: width of the bending band (pt); capped at 75 % of the half short side so a centre always
/// stays fixed. bend: how far the rim reaches outward at the edge (pt). dispersion: per-channel
/// spread at the very edge (pt).
[[ stitchable ]] half4 glassRefraction(float2 position, SwiftUI::Layer layer,
                                      float4 lens, float radius, float rim, float bend, float dispersion) {
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
    float band = min(rim, min(halfSize.x, halfSize.y) * 0.75);
    if (band <= 0.0) {
        return layer.sample(position);
    }
    float depth = clamp(-d / band, 0.0, 1.0);
    if (depth >= 1.0) {
        return layer.sample(position);          // interior: no magnification, no shift
    }
    float t = 1.0 - depth;                      // 0 at the inner edge of the rim, 1 at the glass edge
    float edge = t * t * (3.0 - 2.0 * t);       // smoothstep: no crease where the rim meets the interior
    float2 n = lensNormal(p, halfSize, radius);
    float2 base = position + n * (bend * edge);
    half4 g = layer.sample(base);
    float chroma = dispersion * t * t * t;      // only the outermost part of the rim separates colour
    if (chroma <= 0.001) {
        return g;
    }
    float2 spread = n * chroma;
    half4 r = layer.sample(base + spread);
    half4 b = layer.sample(base - spread);
    // Premultiplied alpha: take the widest coverage so no channel exceeds its alpha.
    half a = max(max(r.a, g.a), b.a);
    return half4(r.r, g.g, b.b, a);
}
