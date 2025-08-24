#version 100
precision highp float;
precision highp int;
precision highp sampler2D;

uniform vec3 color;
uniform float opacity;
uniform float time;
uniform float trail_aspect_ratio;

varying vec2 fragTexCoord;
varying vec4 fragColor;

const vec3 RED = vec3(128.0, 9.0, 9.0) / 255.0;
const vec3 YELLOW = vec3(253.0, 207.0, 88.0) / 255.0;
const vec3 ORANGE = vec3(242.0, 125.0, 12.0) / 255.0;

float hash12(vec2 p) {
  vec3 p3  = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float valueNoise(vec2 p) {
  vec2 gv = fract(p);
  vec2 id = floor(p);
  float tl = hash12(id + vec2(0.0, 0.0));
  float tr = hash12(id + vec2(1.0, 0.0));
  float bl = hash12(id + vec2(0.0, 1.0));
  float br = hash12(id + vec2(1.0, 1.0));
  vec2 sgv = smoothstep(0.0, 1.0, gv);
  float m1 = mix(tl, tr, sgv.x);
  float m2 = mix(bl, br, sgv.x);
  return mix(m1, m2, sgv.y);
}

float fbm(vec2 p) {
  vec2 n = normalize(p);
  float m = 0.0;
  float freq = 3.0;
  float amp = 0.4;
  for (int i = 0; i < 3; ++i) {
    m += amp * valueNoise(freq * p);
    freq *= 2.0;
    amp /= 2.0;
    p.y += time;
  }
  return m;
}

float f0(vec2 p) {
  return fbm(p + fbm(p + time));
}

float mask(vec2 p) {
  float m = 0.0;
  float x = p.x;
  float y = 1.5 * x * x - 0.8;
  m = smoothstep(0.0, 2.0, p.y - y);
  return m;
}

void main() {
  vec2 uv = fragTexCoord;
  vec2 centeredUV = uv * 2.0 - 1.0;

  vec2 fireUV = centeredUV.yx * 0.5;
  fireUV.y = 0.1 - fireUV.y;
  float m = mask(fireUV * 0.75);
  float fire = f0(fireUV * vec2(1.0, trail_aspect_ratio));
  vec3 fireCol = (2.0 * m * m * m) * YELLOW;
  fireCol += (m * m * m + m * m + m + 0.1) * RED;
  fireCol += (1.5 * m * m * m + m * m) * ORANGE;

  float timeMask = min(1.0, (time - 2.0));
  vec4 baseColor = vec4(color * opacity, 1.0) * timeMask;
  baseColor.a = 1.0 - centeredUV.x;

  float alpha = (1.3 - uv.x) * timeMask * opacity;
  vec3 finalColor = vec3(fire) * fireCol * 5.0;

  gl_FragColor = vec4(finalColor * finalColor * alpha, alpha) * 2.5;
}
