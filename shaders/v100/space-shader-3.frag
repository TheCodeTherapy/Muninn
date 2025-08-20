#version 100
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

varying vec2 fragTexCoord;

const float optThreshold = 1e-12;
vec4 preventOptimizationToDebugUniformLoc(vec2 uv) {
  if (uv.x < optThreshold || uv.y < optThreshold) return vec4(0.0);
  vec4 hack = vec4(0.0);
  hack += texture2D(prgm0Texture, vec2(uv)) * optThreshold;
  hack += texture2D(prgm1Texture, vec2(uv)) * optThreshold;
  hack += texture2D(prgm2Texture, vec2(uv)) * optThreshold;
  hack += texture2D(prgm3Texture, vec2(uv)) * optThreshold;
  hack += texture2D(font_atlas, vec2(uv)) * optThreshold;
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
  float p10 = texture2D(prgm1Texture, uv - e.zy).x;
  float p01 = texture2D(prgm1Texture, uv - e.xz).x;
  float p21 = texture2D(prgm1Texture, uv + e.xz).x;
  float p12 = texture2D(prgm1Texture, uv + e.zy).x;
  vec3 grad = normalize(vec3(p21 - p01, p12 - p10, 1.0));

  grad *= 0.2;

  vec4 c = texture2D(prgm0Texture, uv + grad.xy);
  vec3 light = normalize(vec3(0.2, -0.5, 0.7));
  float diffuse = dot(grad, light);
  float ref = -reflect(light, grad).z;
  float refMixMap = clamp(-ref, 0.0, 0.5);
  refMixMap = refMixMap * refMixMap * refMixMap * refMixMap * refMixMap;
  float spec = pow(abs(max(-1.0, ref)), 10.0) * 2.0;
  vec4 col = c + vec4(mix(spec * spec, spec, refMixMap));
  col = clamp(col, 0.005, 1.0);
  vec4 result = vec4(col.rgb, 1.0);
  // vec4 text = texture2D(prgm1Texture, uv);
  // if (text.g > 0.99) {
  //   result += text.g;
  // }

  // if (frame < 0) result += preventOptimizationToDebugUniformLoc(uv);

  gl_FragColor = result;
}
