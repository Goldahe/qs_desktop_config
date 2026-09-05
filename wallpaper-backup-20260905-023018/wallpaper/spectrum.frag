#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float spectrum[1280];
    float timePhase;
    float levelScale;
    float heightLimit;
    float binCount;
} ubuf;

vec3 hsv2rgb(vec3 c) {
    vec3 rgb = clamp(abs(mod(c.x * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0,
                     0.0, 1.0);
    return c.z * mix(vec3(1.0), rgb, c.y);
}

void main() {
    vec2 uv = qt_TexCoord0;
    float bin = min(floor(uv.x * ubuf.binCount), ubuf.binCount - 1.0);
    float strength = ubuf.spectrum[int(bin)] * ubuf.levelScale;
    float barTop = 1.0 - strength * ubuf.heightLimit;
    float line = 1.0 - smoothstep(barTop - 0.0025, barTop + 0.0025, uv.y);
    float body = step(barTop, uv.y);

    // Full hue sweep left-to-right, with a restrained vertical glow.
    vec3 color = hsv2rgb(vec3(uv.x, 0.88, 1.0));
    float glow = body * (0.34 + 0.66 * smoothstep(barTop, 1.0, uv.y));
    float alpha = clamp(body * 0.64 + line * 0.98 + glow * 0.18, 0.0, 1.0);
    fragColor = vec4(color * alpha, alpha) * ubuf.qt_Opacity;
}
