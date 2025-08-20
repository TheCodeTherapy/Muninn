#version 300 es
precision highp float;
precision highp int;
precision highp sampler2D;

// common uniforms
uniform float time;
uniform int frame;
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

in vec2 fragTexCoord;

out vec4 FragColor;

const float optThreshold = 1e-12;
vec4 preventOptimizationToDebugUniformLoc(vec2 uv) {
  if (uv.x < optThreshold || uv.y < optThreshold) return vec4(0.0);
  vec4 hack = vec4(0.0);
  hack += texture(prgm0Texture, vec2(uv)) * optThreshold;
  hack += texture(prgm1Texture, vec2(uv)) * optThreshold;
  hack += texture(prgm2Texture, vec2(uv)) * optThreshold;
  hack += texture(prgm3Texture, vec2(uv)) * optThreshold;
  hack += texture(font_atlas, vec2(uv)) * optThreshold;
  hack += vec4(float(frame) * optThreshold);
  hack += vec4(time * optThreshold);
  hack += vec4(resolution * optThreshold, 0.0, 0.0);
  hack += vec4(mouse * optThreshold, 0.0, 0.0);
  hack += vec4(mouselerp * optThreshold, 0.0, 0.0);
  hack += vec4(ship_world_position * optThreshold, 0.0, 0.0);
  hack += vec4(ship_screen_position * optThreshold, 0.0, 0.0);
  hack += vec4(camera_position * optThreshold, 0.0, 0.0);
  hack += vec4(ship_direction * optThreshold, 0.0, 0.0);
  hack += vec4(ship_velocity * optThreshold, 0.0, 0.0);
  hack += vec4(ship_speed * optThreshold);
  hack *= optThreshold;
  return hack;
}

void main() {
  vec2 uv = fragTexCoord;
  vec2 mp = ((mouselerp + 1.0) * 0.5) * resolution;
  vec3 e = vec3(vec2(1.0) / resolution.xy, 0.0);
  vec2 q = uv;
  vec4 c = texture(prgm2Texture, q);
  float p11 = c.x;
  float p10 = texture(prgm1Texture, q - e.zy).x;
  float p01 = texture(prgm1Texture, q - e.xz).x;
  float p21 = texture(prgm1Texture, q + e.xz).x;
  float p12 = texture(prgm1Texture, q + e.zy).x;
  float d = 0.0;

  d = smoothstep(21.0, 0.0, length(mp.xy - gl_FragCoord.xy) * resolution.x);

  d += -(p11 - 0.5) * 2.0 + (p10 + p01 + p21 + p12 - 2.0);

  d *= 0.999;
  d *= max(min(1.0, float(frame)), 0.0) * clamp(time - 1.0, 0.0, 1.0);
  d = d * 0.5 + 0.5;

  vec4 result = vec4(d, 0.0, 0.0, 1.0);

  // if (frame < 0) result += preventOptimizationToDebugUniformLoc(uv);

  FragColor = result;
}
