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
