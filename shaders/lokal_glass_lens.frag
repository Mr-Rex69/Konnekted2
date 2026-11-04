// Liquid glass lens for LokalGlass.
//
// The refraction and dispersion are ported from Kyant0/backdrop
// (https://github.com/Kyant0/AndroidLiquidGlass, Copyright 2025 Kyant,
// Apache License 2.0): the backdrop is bent toward the centre near the
// rounded edge of the shape, following a circular profile, which is what
// makes the glass read as a solid lens rather than frosted plastic.

#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

// Set by the engine: the size of the filter input, in physical pixels.
uniform vec2 u_size;
// The glass shape in physical pixels, and its top-left in screen space (used
// only when the input is the whole backdrop rather than the shape's clip).
uniform vec2 u_shape_size;
uniform vec2 u_shape_offset;
uniform float u_radius;
// How far in from the edge the lens bends, and by how much.
uniform float u_height;
uniform float u_amount;
// 1 bulges the whole face toward its centre (a magnifier), 0 bends only
// the edge.
uniform float u_depth;
// Strength of the rainbow fringe at the rim (0 = none).
uniform float u_dispersion;
// 1 opts into the physical squircle profile; 0 keeps existing circle.
uniform float u_profile;

uniform sampler2D u_texture;

out vec4 frag_color;

float sdRoundedRect(vec2 coord, vec2 halfSize, float radius) {
    vec2 cornerCoord = abs(coord) - (halfSize - vec2(radius));
    float outside = length(max(cornerCoord, 0.0)) - radius;
    float inside = min(max(cornerCoord.x, cornerCoord.y), 0.0);
    return outside + inside;
}

vec2 gradSdRoundedRect(vec2 coord, vec2 halfSize, float radius) {
    vec2 cornerCoord = abs(coord) - (halfSize - vec2(radius));
    if (cornerCoord.x >= 0.0 || cornerCoord.y >= 0.0) {
        return sign(coord) * normalize(max(cornerCoord, 0.0) + 1e-5);
    }
    float gradX = step(cornerCoord.y, cornerCoord.x);
    return sign(coord) * vec2(gradX, 1.0 - gradX);
}

float circleMap(float x) {
    return 1.0 - sqrt(max(1.0 - x * x, 0.0));
}

// Convex squircle surface: h(x)=(1-(1-x)^4)^(1/4). Its slope determines
// refraction via Snell's law, n_air=1, n_glass=1.5. A single-interface
// estimate is sufficient for the lightweight footer lens.
float squircleBend(float x) {
    float q = 1.0 - clamp(x, 0.0, 1.0);
    float q2 = q * q;
    float slope = (q2 * q) / pow(max(1.0 - q2 * q2, 1e-5), 0.75);
    float cosI = inversesqrt(1.0 + slope * slope);
    float sinI = slope * cosI;
    float sinT = sinI / 1.5;
    float cosT = sqrt(max(1.0 - sinT * sinT, 0.0));
    float sinD = sinI * cosT - cosI * sinT;
    float cosD = cosI * cosT + sinI * sinT;
    // tan(90deg-asin(1/1.5)) = 1.11803399 at the outer edge.
    return clamp((sinD / max(cosD, 1e-5)) / 1.11803399, 0.0, 1.0);
}

vec4 sampleAt(vec2 coord) {
    vec2 uv = clamp(coord / u_size, vec2(0.0), vec2(1.0));
#ifdef IMPELLER_TARGET_OPENGLES
    uv.y = 1.0 - uv.y;
#endif
    return texture(u_texture, uv);
}

void main() {
    vec2 coord = FlutterFragCoord().xy;

    // Most backends hand the filter the backdrop inside the glass's own clip;
    // some hand it the whole screen. Tell them apart by size.
    bool clipLocal = u_size.x <= u_shape_size.x + 8.0 &&
        u_size.y <= u_shape_size.y + 8.0;
    vec2 origin = clipLocal ? vec2(0.0) : u_shape_offset;

    vec2 halfSize = u_shape_size * 0.5;
    vec2 centered = coord - origin - halfSize;
    float radius = min(u_radius, min(halfSize.x, halfSize.y));

    float sd = sdRoundedRect(centered, halfSize, radius);
    if (u_amount <= 0.0 || u_height <= 0.0 || -sd >= u_height) {
        frag_color = sampleAt(coord);
        return;
    }
    sd = min(sd, 0.0);

    // Keep the opt-in footer effect smooth without changing existing glass.
    float inset = clamp(-sd / u_height, 0.0, 1.0);
    float bend = u_profile > 0.5
        ? squircleBend(inset)
        : circleMap(1.0 - inset);
    float d = -u_amount * bend;
    float gradRadius = min(radius * 1.5, min(halfSize.x, halfSize.y));
    vec2 toCentre = length(centered) > 1e-3 ? normalize(centered) : vec2(0.0);
    vec2 grad = normalize(
        gradSdRoundedRect(centered, halfSize, gradRadius) + u_depth * toCentre
    );
    vec2 refracted = coord + d * grad;

    if (u_dispersion <= 0.0) {
        frag_color = sampleAt(refracted);
        return;
    }

    float intensity = u_dispersion *
        ((centered.x * centered.y) / (halfSize.x * halfSize.y));
    vec2 dispersed = d * grad * intensity;

    vec4 color = vec4(0.0);
    vec4 red = sampleAt(refracted + dispersed);
    color.r += red.r / 3.5;
    color.a += red.a / 7.0;
    vec4 orange = sampleAt(refracted + dispersed * (2.0 / 3.0));
    color.r += orange.r / 3.5;
    color.g += orange.g / 7.0;
    color.a += orange.a / 7.0;
    vec4 yellow = sampleAt(refracted + dispersed * (1.0 / 3.0));
    color.r += yellow.r / 3.5;
    color.g += yellow.g / 3.5;
    color.a += yellow.a / 7.0;
    vec4 green = sampleAt(refracted);
    color.g += green.g / 3.5;
    color.a += green.a / 7.0;
    vec4 cyan = sampleAt(refracted - dispersed * (1.0 / 3.0));
    color.g += cyan.g / 3.5;
    color.b += cyan.b / 3.0;
    color.a += cyan.a / 7.0;
    vec4 blue = sampleAt(refracted - dispersed * (2.0 / 3.0));
    color.b += blue.b / 3.0;
    color.a += blue.a / 7.0;
    vec4 purple = sampleAt(refracted - dispersed);
    color.r += purple.r / 7.0;
    color.b += purple.b / 3.0;
    color.a += purple.a / 7.0;
    frag_color = color;
}
