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

const float PI = acos(-1.0);

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

float remap(float value, float minValue, float maxValue, float minScaledValue, float maxScaledValue) {
  return (
    minScaledValue +
    ((maxScaledValue - minScaledValue) * (value - minValue)) / (maxValue - minValue)
  );
}

float thrustersDist(vec2 uv) {
  const float distribution = 0.05;
  const float speed = 0.1;
  const float overdraw = 5.0;
  const float shapeK = 0.25;
  float size = 1.7;

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

  float speed_map = remap(ship_speed, 0.0, 1000.0, 20.0, 5.0);
  float offset_map = remap(ship_speed, 0.0, 1000.0, 0.0, 70.0);
  float alpha_map = remap(ship_speed, 0.0, 2000.0, 0.0, 1.0) * 2.0;
  uv = (rotated_pos - vec2(offset_map, 0.0)) / resolution.y * speed_map;
  float r = -(uv.x * uv.x + uv.y * uv.y);
  float z = 0.5 + 0.5 * sin((r + time * speed) / distribution);
  float a = clamp(smoothstep(-0.1, 0.2, size - length(uv * 2.0)), 0.0, 0.5);
  float h = clamp(sdHyperbola(uv, shapeK, 1.0), 0.0, 1.0) * overdraw;
  float alpha = clamp(a * h, 0.0, 1.0) * alpha_map;
  return z * alpha;
}

float randomValue(vec2 p) {
  return fract(sin(dot(p, vec2(13.337, 61.998))) * 48675.75647);
}

vec2 rotateVector(vec2 p, float angle) {
  return vec2(p.y * cos(angle) + p.x * sin(angle), p.x * cos(angle) - p.y * sin(angle));
}

vec2 randomVector2D(vec2 p) {
  return vec2(randomValue(p), randomValue(-p));
}

vec3 randomVector3D(vec2 p) {
  return vec3(randomValue(p), randomValue(-p), randomValue(vec2(-p.x - 5.0, p.y + 1.0)));
}

// single-octave Perlin noise with time animation
float perlinNoise(vec2 p, float timeOffset) {
  vec2 cellIndex = floor(p);
  vec2 localPosition = fract(p);
  vec2 smoothPosition = smoothstep(0.0, 1.0, localPosition);
  return mix(
    mix(
      dot(localPosition, rotateVector(vec2(1.0), randomValue(cellIndex) * (PI * 2.0 + timeOffset))),
      dot(localPosition - vec2(1.0, 0.0), rotateVector(vec2(1.0), randomValue(cellIndex + vec2(1.0, 0.0)) * (PI * 2.0 + timeOffset))),
      smoothPosition.x
    ),
    mix(
      dot(localPosition - vec2(0.0, 1.0), rotateVector(vec2(1.0), randomValue(cellIndex + vec2(0.0, 1.0)) * (PI * 2.0 + timeOffset))),
      dot(localPosition - vec2(1.0, 1.0), rotateVector(vec2(1.0), randomValue(cellIndex + vec2(1.0, 1.0)) * (PI * 2.0 + timeOffset))),
      smoothPosition.x
    ),
    smoothPosition.y
  );
}

// fractal Perlin noise with multiple octaves
float fractalPerlinNoise2(vec2 p, float timeOffset) {
  float noiseValue = 0.0, normalizationFactor = 0.0, frequency = 1.0;
  for (float i = 0.0; i < 2.0; i++) {
    noiseValue += perlinNoise(p * frequency, timeOffset * frequency) / frequency;
    normalizationFactor += 1.0 / frequency;
    frequency *= 2.0;
  }
  return noiseValue / normalizationFactor;
}

float fractalPerlinNoise6(vec2 p, float timeOffset) {
  float noiseValue = 0.0, normalizationFactor = 0.0, frequency = 1.0;
  for (float i = 0.0; i < 6.0; i++) {
    noiseValue += perlinNoise(p * frequency, timeOffset * frequency) / frequency;
    normalizationFactor += 1.0 / frequency;
    frequency *= 2.0;
  }
  return noiseValue / normalizationFactor;
}

// voronoi distance field for creating cellular patterns
float voronoiDistance(vec2 p) {
  vec2 cellIndex = floor(p);
  vec2 localPosition = fract(p);
  float minDistance = 100.0;
  for (float x = -1.0; x <= 1.0; x++) {
    for (float y = -1.0; y <= 1.0; y++) {
      minDistance = min(
        minDistance,
        distance(
          sin(2.5 * PI * randomVector2D(cellIndex + vec2(x, y))) * 0.8 + 0.2,
          localPosition - vec2(x, y)
        )
      );
    }
  }
  return minDistance;
}

// Voronoi with cell identification - returns color of nearest cell
vec3 voronoiCellColor(vec2 p) {
  vec2 cellIndex = floor(p);
  vec2 localPosition = fract(p);
  float minDistance = 1000.0;
  vec3 cellColor = vec3(0.0);
  for (float x = -1.0; x <= 1.0; x++) {
    for (float y = -1.0; y <= 1.0; y++) {
      float dist = distance(
        sin(2.5 * PI * randomVector2D(cellIndex + vec2(x, y))) * 0.8 + 0.2,
        localPosition - vec2(x, y)
      );
      if (minDistance > dist) {
        minDistance = dist;
        cellColor = randomVector3D(cellIndex + vec2(x, y));
      }
    }
  }
  return cellColor;
}

vec3 nebulaCellColor(vec2 p) {
  vec2 cellIndex = floor(p);
  vec2 localPosition = fract(p);
  vec3 colorAccum = vec3(0.0);
  float weightAccum = 0.0;

  for (float x = -1.0; x <= 1.0; x++) {
    for (float y = -1.0; y <= 1.0; y++) {
      float dist = distance(
        sin(2.5 * PI * randomVector2D(cellIndex + vec2(x, y))) * 0.8 + 0.2,
        localPosition - vec2(x, y)
      );

      // Create smooth weight based on distance
      float weight = 1.0 / (1.0 + dist * 15.0);
      weightAccum += weight;
      colorAccum += randomVector3D(cellIndex + vec2(x, y)) * weight;
    }
  }
  colorAccum.g *= 0.8;
  colorAccum.b *= 1.0;

  return colorAccum / weightAccum;
}

// single star using Voronoi pattern
vec3 generateStar(vec2 p) {
  float starBrightness = voronoiDistance(p * 3.0);
  starBrightness = 0.01 / starBrightness;
  starBrightness = pow(starBrightness, 1.7);

  // Color variation based on position
  vec3 baseColor = voronoiCellColor(p * 3.0);
  vec3 starColor = vec3(starBrightness) * baseColor;

  // Add subtle temperature variation (blue-white to orange-red)
  float temperature = randomValue(p * 7.0);
  vec3 tempColor = mix(
    vec3(0.8, 0.9, 1.2),  // cool blue-white
    vec3(1.2, 0.8, 0.6),  // warm orange-red
    temperature
  );

  starColor *= tempColor;
  return clamp(starColor * fractalPerlinNoise2(p / 2.0, 0.0), 0.0, 1.0);
}

// layered starfield with broad parallax depth
vec3 generateStarfield(vec2 p, vec2 parallax_offset) {
  vec3 starfieldColor = vec3(0.0);
  float scale = 5.0;
  for (float i = 0.0; i < 5.0; i++) {
    // Much broader parallax range: closest stars move 10x faster than distant ones
    // Use exponential falloff: 1.0 → 0.5 → 0.25 → 0.125 → 0.0625
    float depth_factor = 1.0 / pow(2.0, i); // Each layer half as fast as previous
    vec2 layer_offset = parallax_offset * depth_factor;
    starfieldColor += generateStar(rotateVector(p + layer_offset, i) * scale);
    scale *= 1.2;
  }
  return starfieldColor;
}

// nebula using fractal noise with its own parallax layers
vec3 generateNebulaColor(vec2 p, vec2 parallax_offset) {
  float nebula = 0.0;
  float scale = 3.0;
  vec3 colorAccum = vec3(0.0);

  for (float i = 0.0; i < 5.0; i++) {
    // Nebula has its own parallax layers, but generally deeper than stars
    // Start from 0.3 (slower than closest stars) down to 0.05 (slower than furthest stars)
    float depth_factor = 0.3 / pow(1.8, i); // 0.3 → 0.17 → 0.09 → 0.05 → 0.03
    vec2 layer_offset = parallax_offset * depth_factor;

    vec2 rotatedP = rotateVector(p + layer_offset, i) * scale / 2.0;
    float noiseValue = fractalPerlinNoise6(rotatedP, 0.0);
    nebula += noiseValue;

    // Add color variation per octave - using smooth blending for same colors
    vec3 octaveColor = nebulaCellColor(abs(smoothstep(0.0, 2.0, (rotatedP * 10.5) * noiseValue)));
    octaveColor *= octaveColor * octaveColor * 3.0;
    colorAccum += octaveColor * abs(noiseValue) / scale;
    scale *= 1.2;
  }

  return colorAccum;
}

void main() {
  vec2 uv = fragTexCoord;
  vec2 ouv = uv;

  float layers = 5.0;

  // Create parallax offset from ship's world position
  vec2 parallax_offset = vec2(camera_position.x, -camera_position.y) * 0.001;

  // Generate starfield and nebula with parallax effect
  vec3 stars = generateStarfield(uv * vec2(resolution.x / resolution.y, 1.0), parallax_offset);
  stars *= 20.0;
  stars = pow(stars, vec3(1.0));
  float starsLumance = dot(stars, vec3(0.2126, 0.7152, 0.0722));

  // base color and clamp starfield
  stars = vec3(0.0, 0.0, 0.05) + clamp(vec3(0.0, 0.0, 0.03) + stars, vec3(0.0), vec3(1.0));

  // nebula effect with color - moves at background depth (same as furthest stars)
  vec3 nebulaColor = generateNebulaColor(uv * 3.0, parallax_offset) * 3.0;

  // nebulaColor = nebulaColor * (fragTexCoord.y - 0.25);

  // combine nebula and starfield
  vec3 color = nebulaColor * 3.5 + stars * stars * starsLumance;
  float nebulaLuminance = dot(nebulaColor, vec3(0.299, 0.587, 0.114));

  vec4 result = vec4(color * color, starsLumance + nebulaLuminance * 0.5) * 1.2;

  // if (frame < 0) result += preventOptimizationToDebugUniformLoc(uv);

  gl_FragColor = result;

  // float thrusters = thrustersDist(uv);
  // gl_FragColor += vec4(thrusters);

  const bool debug = false;

  if (debug) {
    const float thickness = 3.0;
    bool isBorder = (
      fragTexCoord.x < thickness / resolution.x ||
      fragTexCoord.x > 1.0 - thickness / resolution.x ||
      fragTexCoord.y < thickness / resolution.y ||
      fragTexCoord.y > 1.0 - thickness / resolution.y
    );
    if (isBorder) {
      gl_FragColor = vec4(1.0, 0.0, 0.0, 1.0); // red border for debugging
    }
  }
}
