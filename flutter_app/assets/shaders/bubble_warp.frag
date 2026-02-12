#include <flutter/runtime_effect.glsl>

precision mediump float;

uniform sampler2D uTexture;
uniform vec2 uResolution;
uniform float uTime;
uniform float uRotation;
uniform vec2 uParallax;
uniform float uOpacity;
uniform float uBubbleCount;
uniform float uStrengthGlobal;
uniform float uBubbleData[144];

out vec4 fragColor;

float hash21(vec2 p) {
  p = fract(p * vec2(123.34, 345.45));
  p += dot(p, p + 34.345);
  return fract(p.x * p.y);
}

float valueNoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);

  float a = hash21(i + vec2(0.0, 0.0));
  float b = hash21(i + vec2(1.0, 0.0));
  float c = hash21(i + vec2(0.0, 1.0));
  float d = hash21(i + vec2(1.0, 1.0));

  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float bubbleEase(float t) {
  float inPhase = smoothstep(0.0, 0.24, t);
  float outPhase = 1.0 - smoothstep(0.58, 1.0, t);
  return inPhase * outPhase;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uResolution;

  vec2 centered = uv - vec2(0.5);
  float c = cos(uRotation);
  float s = sin(uRotation);
  mat2 rot = mat2(c, -s, s, c);

  vec2 uvRot = (rot * centered) + vec2(0.5);
  uvRot += uParallax * 0.016;

  vec2 warp = vec2(0.0);

  const int kMaxBubbles = 24;
  for (int i = 0; i < kMaxBubbles; i++) {
    if (float(i) >= uBubbleCount) {
      continue;
    }

    int base = i * 6;
    vec2 bubblePos = vec2(uBubbleData[base], uBubbleData[base + 1]);
    float radius = uBubbleData[base + 2];
    float strength = uBubbleData[base + 3];
    float age = uBubbleData[base + 4];
    float life = max(uBubbleData[base + 5], 0.001);

    vec2 delta = uvRot - bubblePos;
    float d = length(delta);
    float influence = smoothstep(radius, 0.0, d);

    float phase = clamp(age / life, 0.0, 1.0);
    influence *= bubbleEase(phase);

    vec2 dir = d > 0.0001 ? (delta / d) : vec2(0.0, 0.0);
    vec2 perp = vec2(-dir.y, dir.x);

    float swirl = sin((uTime * 0.6) + (float(i) * 1.47));
    vec2 localDisplacement = (dir + (perp * swirl * 0.19));

    warp += localDisplacement * influence * strength * uStrengthGlobal * 0.055;
  }

  float n = valueNoise((uvRot * 3.0) + vec2(uTime * 0.08, -uTime * 0.06));
  vec2 livingNoise = vec2(n - 0.5, 0.5 - n) * (0.008 * uStrengthGlobal);

  vec2 uvWarped = clamp(uvRot + warp + livingNoise, vec2(0.0), vec2(1.0));
  vec4 color = texture(uTexture, uvWarped);
  color.a *= uOpacity;

  fragColor = color;
}
