#version 100
precision highp float;
precision highp int;
precision highp sampler2D;

// common uniforms
uniform float time;
uniform float delta_time;
uniform int frame;
uniform float fps;
uniform vec2 resolution;

// shader textures
uniform sampler2D prgm0Texture;
uniform sampler2D prgm1Texture;
uniform sampler2D prgm2Texture;
uniform sampler2D prgm3Texture;

// font atlas texture
uniform sampler2D font_atlas;

// additional uniforms
uniform vec2 mouse;
uniform vec2 mouselerp;
uniform vec2 ship_world_position;
uniform vec2 ship_screen_position;
uniform vec2 camera_position;
uniform vec2 ship_direction;
uniform vec2 ship_velocity;
uniform float ship_speed;

varying vec2 fragTexCoord;

#include chunks/prevent-optimization.chunk.frag
#include chunks/thruster-dist.chunk.frag

void main() {
  vec2 uv = fragTexCoord;
  vec2 ouv = uv;
  vec2 mp = ((mouselerp + 1.0) * 0.5) * resolution;
  vec3 e = vec3(vec2(1.0) / resolution.xy, 0.0);
  vec2 q = uv;
  vec4 c = texture2D(prgm2Texture, q);
  float p11 = c.x;
  float p10 = texture2D(prgm1Texture, q - e.zy).x;
  float p01 = texture2D(prgm1Texture, q - e.xz).x;
  float p21 = texture2D(prgm1Texture, q + e.xz).x;
  float p12 = texture2D(prgm1Texture, q + e.zy).x;
  float d = 0.0;

  // d = smoothstep(21.0, 0.0, length(mp.xy - gl_FragCoord.xy) * resolution.x);

  d = thrustersDist(uv);

  d += -(p11 - 0.5) * 2.0 + (p10 + p01 + p21 + p12 - 2.0);
  d *= pow(0.9965, delta_time * 120.0) * max(ship_speed / 995.0, 0.9965);
  d *= max(min(1.0, float(frame)), 0.0) * clamp(time - 1.0, 0.0, 1.0);
  d = d * 0.5 + 0.5;

  ouv *=  1.0 - ouv.yx;
  float vig = ouv.x * ouv.y * 20.0;
  vig = clamp(pow(vig, 0.125), 0.0, 1.0);
  d = mix(d, d * vig, 0.1);

  vec4 result = vec4(d, 0.0, 0.0, 1.0);

  // if (frame < 0) result += preventOptimizationToDebugUniformLoc(uv);

  gl_FragColor = result;
}
