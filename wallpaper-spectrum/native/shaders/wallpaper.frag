#version 440

layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float effectAmount;
    float binCount;
    float hueOffset;
};

layout(binding = 1) uniform sampler2D wallpaperTexture;
layout(binding = 2) uniform sampler2D spectrumTexture;

float rgbHue(vec3 color, float maximum, float delta)
{
    if (delta < 0.00001)
        return 0.0;
    float hue;
    if (maximum == color.r)
        hue = mod((color.g - color.b) / delta, 6.0);
    else if (maximum == color.g)
        hue = (color.b - color.r) / delta + 2.0;
    else
        hue = (color.r - color.g) / delta + 4.0;
    return fract(hue / 6.0);
}

void main()
{
    vec4 source = texture(wallpaperTexture, vTexCoord);
    vec3 rgb = source.rgb;
    float maximum = max(rgb.r, max(rgb.g, rgb.b));
    float minimum = min(rgb.r, min(rgb.g, rgb.b));
    float delta = maximum - minimum;
    float saturation = maximum > 0.00001 ? delta / maximum : 0.0;
    float hue = fract(rgbHue(rgb, maximum, delta) - hueOffset);

    // Hue traverses the same ascending-then-mirrored bin order as the bars.
    float phase = hue * 2.0;
    float mirroredBin = phase <= 1.0
        ? phase * (binCount - 1.0)
        : (2.0 - phase) * (binCount - 1.0);
    float spectrumU = (mirroredBin + 0.5) / 640.0;
    float amplitude = texture(spectrumTexture, vec2(spectrumU, 0.5)).r;
    float hueConfidence = smoothstep(0.02, 0.12, saturation);
    // Master-specified response: x * 4, with x = amplitude.
    float amplifiedAmplitude = amplitude * 4.0;
    float strength = clamp(amplifiedAmplitude * hueConfidence, 0.0, 1.0);

    float luminance = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
    vec3 reactive = mix(vec3(luminance), rgb, strength);
    vec3 outputRgb = mix(rgb, reactive, clamp(effectAmount, 0.0, 1.0));
    float outputAlpha = clamp(qt_Opacity, 0.0, 1.0);
    fragColor = vec4(outputRgb * outputAlpha, outputAlpha);
}
