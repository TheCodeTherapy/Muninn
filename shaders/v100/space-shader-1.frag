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

//(won't work in #version 100 because arrays and shit) #include text-system
//makeStrF(printDebug)   _d _e _b _u _g _COL __ _num_ __ _a _s __ _f _3 _2 _endNum

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

const float size = 1.7;
const float distribution = 0.05;
const float speed = 0.1;
const float overdraw = 5.0;
const float shapeK = 0.25;
float sdHyperbola(vec2 p, float k, float wi) {
  vec2 op = p;
  p = abs(p);
  float k2 = k * k;
  float a = p.x + p.y;
  float i = 0.5 * (a - k2 / a) > wi ? -1.0 : 1.0;
  float x = clamp(0.5 * (a - k2 / a), 0.0, wi);
  vec2 q = vec2(x, sqrt(x * x + k2));
  float s = sign(p.x * p.x - p.y * p.y + k2);
  return smoothstep(0.0, 0.3, s * length(p - q) * p.x * (op.x > 0.0 ? 0.0 : 1.0));
}

void main() {
  vec2 uv = fragTexCoord;
  vec2 ouv = uv;
  vec2 mp = ((mouse + 1.0) * 0.5) * resolution;
  vec3 e = vec3(vec2(1.0) / resolution.xy, 0.0);
  vec2 q = uv;
  vec4 c = texture2D(prgm1Texture, q);
  float p11 = c.x;
  float p10 = texture2D(prgm2Texture, q - e.zy).x;
  float p01 = texture2D(prgm2Texture, q - e.xz).x;
  float p21 = texture2D(prgm2Texture, q + e.xz).x;
  float p12 = texture2D(prgm2Texture, q + e.zy).x;
  float d = 0.0;

  // d = smoothstep(30.0, 0.5, length(mp.xy - gl_FragCoord.xy) * 1.5);

  float s = 0.0;
  float speed_factor = ship_speed / 50.0;
  vec2 flipped_fragcoord = vec2(gl_FragCoord.x, resolution.y - gl_FragCoord.y);
  float trail_length = speed_factor * 3.0;

  // relative to ship position and direction for thrusters
  vec2 relative_pos = flipped_fragcoord - ship_screen_position;
  float angle = atan(ship_direction.y, ship_direction.x);
  float cos_a = cos(-angle);
  float sin_a = sin(-angle);
  vec2 rotated_pos = vec2(
    relative_pos.x * cos_a - relative_pos.y * sin_a,
    relative_pos.x * sin_a + relative_pos.y * cos_a
  );

  uv = rotated_pos / resolution.y * 5.0;
  float r = -(uv.x * uv.x + uv.y * uv.y);
  float z = 0.5 + 0.5 * sin((r + time * speed) / distribution);
  float a = clamp(smoothstep(-0.1, 0.2, size - length(uv * 2.0)), 0.0, 0.5);
  float h = clamp(sdHyperbola(uv, shapeK, 1.0), 0.0, 1.0) * overdraw;
  float alpha = clamp(a * h, 0.0, 1.0);
  d = z * alpha;

  d += -(p11 - 0.5) * 2.0 + (p10 + p01 + p21 + p12 - 2.0);
  d *= 0.9965;
  d *= max(min(1.0, float(frame)), 0.0) * clamp(time - 1.0, 0.0, 1.0);
  d = d * 0.5 + 0.5;

  // d = clamp(d, -100.0, 100.0);

  d *= ship_speed / 991.5;

  vec4 result = vec4(d, 0.0, 0.0, 1.0);

  // if (frame < 0) result += preventOptimizationToDebugUniformLoc(uv);

  // ouv.y -= 0.1;
  // result.rgb += vec3(0.0, 1.0, 0.0) * printDebug(ouv * 2.0 + vec2(0.0, 0.18), d, 5) * 100.0;

  gl_FragColor = result;
}
