const float optThreshold = 1e-12;
vec4 preventOptimizationToDebugUniformLoc(vec2 uv) {
  if (uv.x < optThreshold || uv.y < optThreshold) return vec4(0.0);
  vec4 hack = vec4(0.0);
  hack += texture2D(prgm0Texture, vec2(uv)) * optThreshold;
  hack += texture2D(prgm1Texture, vec2(uv)) * optThreshold;
  hack += texture2D(prgm2Texture, vec2(uv)) * optThreshold;
  hack += texture2D(prgm3Texture, vec2(uv)) * optThreshold;
  hack += texture2D(font_atlas, vec2(uv)) * optThreshold;
  hack += vec4(time * optThreshold);
  hack += vec4(delta_time * optThreshold);
  hack += vec4(float(frame) * optThreshold);
  hack += vec4(fps * optThreshold);
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
