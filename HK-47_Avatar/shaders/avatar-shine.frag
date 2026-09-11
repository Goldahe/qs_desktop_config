#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float scanPhase;
    float refreshPhase;
    float activationLevel;
    vec4 shineColor;
    float shineStrength;
    float hologramOpacity;
    float glowStrength;
    float audioAmplitude;
    float silhouetteOpacity;
    float silhouetteScale;
    float silhouetteOffsetY;
    float silhouetteFeatherPixels;
} ubuf;

layout(binding = 1) uniform sampler2D portraitTexture;
layout(binding = 2) uniform sampler2D crtTexture;

void main()
{
    vec2 uv = qt_TexCoord0;
    vec4 portrait = texture(portraitTexture, uv);
    vec4 scanline = texture(crtTexture, vec2(uv.x, fract(uv.y - ubuf.scanPhase)));

    float portraitLuma = dot(portrait.rgb, vec3(0.2126, 0.7152, 0.0722));
    float scanlineLuma = dot(scanline.rgb, vec3(0.2126, 0.7152, 0.0722));
    float brightScanline = smoothstep(0.55, 0.95, scanlineLuma) * scanline.a;
    float brightPortrait = smoothstep(0.34, 0.86, portraitLuma) * portrait.a;

    // Four nearby alpha samples produce a restrained two-pixel projection halo.
    vec2 px = vec2(1.0 / 256.0);
    float nearAlpha = max(texture(portraitTexture, uv + vec2(px.x * 2.0, 0.0)).a,
                          texture(portraitTexture, uv - vec2(px.x * 2.0, 0.0)).a);
    nearAlpha = max(nearAlpha,
                    max(texture(portraitTexture, uv + vec2(0.0, px.y * 2.0)).a,
                        texture(portraitTexture, uv - vec2(0.0, px.y * 2.0)).a));
    float halo = max(nearAlpha - portrait.a * 0.72, 0.0) * ubuf.glowStrength;

    // Slow scan movement, a traveling refresh band, and subtle coherent flicker.
    float lineModulation = mix(0.56, 1.12, brightScanline);
    float sweep = max(1.0 - abs(uv.y - ubuf.refreshPhase) / 0.12, 0.0);
    float flicker = 0.965 + 0.035 * sin(ubuf.scanPhase * 559.203 + uv.y * 11.0);

    // Power transitions reveal or collapse the projection vertically toward
    // its base, with a bright unstable frontier instead of moving the image.
    float revealCoord = 1.0 - uv.y;
    float reveal = smoothstep(revealCoord - 0.035, revealCoord + 0.035,
                              ubuf.activationLevel);
    float powered = smoothstep(0.0, 0.055, ubuf.activationLevel);
    float frontier = 1.0 - smoothstep(0.0, 0.055,
                                     abs(revealCoord - ubuf.activationLevel));
    frontier *= 1.0 - smoothstep(0.92, 1.0, ubuf.activationLevel);
    float startupStability = mix(0.72 + 0.28 * sin(ubuf.activationLevel * 65.0
                                                   + uv.y * 19.0),
                                 1.0,
                                 smoothstep(0.34, 0.90, ubuf.activationLevel));

    float voicePulse = smoothstep(0.0, 1.0, ubuf.audioAmplitude);
    float body = portrait.a * (0.20 + 0.80 * portraitLuma)
               * lineModulation * ubuf.hologramOpacity * flicker
               * startupStability;
    float intersection = brightPortrait * brightScanline * ubuf.shineStrength;
    float projection = (body * (1.0 + voicePulse * 0.55)
                        + intersection * 0.34
                        + halo * (0.30 + voicePulse * 0.24)
                        + sweep * portrait.a * 0.10) * reveal * powered;
    float powerSurge = frontier * portrait.a * powered * 0.34;
    float alpha = clamp(projection + powerSurge, 0.0, 0.98);

    // Derive a larger, slightly lowered black silhouette from the portrait's
    // alpha mask. This gives the hologram a deliberate mechanical backing
    // while leaving the rectangular window transparent.
    vec2 silhouetteUv = (uv - vec2(0.5)) / ubuf.silhouetteScale
                      + vec2(0.5, 0.5 + ubuf.silhouetteOffsetY);
    vec2 silhouetteInside = step(vec2(0.0), silhouetteUv)
                          * step(silhouetteUv, vec2(1.0));
    // A compact nine-tap alpha feather makes the silhouette edge transparent
    // across the configured pixel width while keeping its nominal size equal
    // to the source portrait.
    vec2 feather = vec2(ubuf.silhouetteFeatherPixels / 256.0);
    float silhouetteMask = texture(portraitTexture, silhouetteUv).a * 0.28;
    silhouetteMask += texture(portraitTexture, silhouetteUv + vec2(feather.x, 0.0)).a * 0.09;
    silhouetteMask += texture(portraitTexture, silhouetteUv - vec2(feather.x, 0.0)).a * 0.09;
    silhouetteMask += texture(portraitTexture, silhouetteUv + vec2(0.0, feather.y)).a * 0.09;
    silhouetteMask += texture(portraitTexture, silhouetteUv - vec2(0.0, feather.y)).a * 0.09;
    silhouetteMask += texture(portraitTexture, silhouetteUv + feather).a * 0.09;
    silhouetteMask += texture(portraitTexture, silhouetteUv - feather).a * 0.09;
    silhouetteMask += texture(portraitTexture, silhouetteUv + vec2(feather.x, -feather.y)).a * 0.09;
    silhouetteMask += texture(portraitTexture, silhouetteUv + vec2(-feather.x, feather.y)).a * 0.09;
    float silhouette = silhouetteMask
                     * silhouetteInside.x * silhouetteInside.y
                     * ubuf.silhouetteOpacity * reveal * powered;

    float energy = clamp(0.55 + portraitLuma * 0.38
                         + intersection * 0.32 + sweep * 0.12
                         + frontier * 0.28 + voicePulse * 0.16, 0.0, 1.0);
    vec3 color = ubuf.shineColor.rgb * energy;

    // Qt Quick expects premultiplied-alpha fragment output. Composite the
    // hologram over the black silhouette; black contributes no RGB value.
    float compositedAlpha = alpha + silhouette * (1.0 - alpha);
    fragColor = vec4(color * alpha, compositedAlpha) * ubuf.qt_Opacity;
}
