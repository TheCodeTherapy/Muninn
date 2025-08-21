package gamelogic

import "core:math"
import rl "vendor:raylib"

round :: proc(n: f32, digits: int) -> f32 {
  multiplier := math.pow(10.0, f32(digits))
  return math.round(n * multiplier) / multiplier
}

ease :: proc(target, n, factor, dt: f32, fps: f32 = 60.0) -> f32 {
  // Continuous-time rate (s^-1) that would yield `f` per frame at fps
  // Derivation: f = 1 - exp(-k * (1/fps))  =>  k = -ln(1 - f) * fps
  k := -math.ln_f32(1 - factor) * fps
  factor_dt := 1 - math.exp_f32(-k * math.max(dt, 0))
  return round((target - n) * factor_dt, 5)
}

// Vector2 version of the ease function
ease_vec2 :: proc(target: rl.Vector2, current: rl.Vector2, factor: f32, delta_time: f32, fps: f32) -> rl.Vector2 {
  return rl.Vector2{
    ease(target.x, current.x, factor, delta_time, fps),
    ease(target.y, current.y, factor, delta_time, fps),
  }
}

// Clamp a value between min and max
clamp :: proc(value: f32, min_val: f32, max_val: f32) -> f32 {
  return math.max(min_val, math.min(max_val, value))
}

// Get the magnitude (length) of a vector
vector_magnitude :: proc(v: rl.Vector2) -> f32 {
  return math.sqrt(v.x * v.x + v.y * v.y)
}

// Normalize a vector to unit length
vector_normalize :: proc(v: rl.Vector2) -> rl.Vector2 {
  mag := vector_magnitude(v)
  if mag == 0 {
    return {0, 0}
  }
  return {v.x / mag, v.y / mag}
}

// Create a direction vector from an angle in degrees
direction_from_angle :: proc(angle_degrees: f32) -> rl.Vector2 {
  radians := angle_degrees * rl.DEG2RAD
  return {math.cos(radians), math.sin(radians)}
}

remap :: proc(value: f32, min_value: f32, max_value: f32, min_scaled_value: f32, max_scaled_value: f32) -> f32 {
	return min_scaled_value + ((max_scaled_value - min_scaled_value) * (value - min_value)) / (max_value - min_value)
}
