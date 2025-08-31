package gamelogic

import "core:math"
import rl "vendor:raylib"
import "core:fmt"

MAX_PROJECTILES :: 1000

MAX_SHIP_SPEED :: 1000.0
MAX_WARP_MULTIPLIER :: 70.0
WARP_SPEED_THRESHOLD :: 997.45

SHIP_ACCELERATION :: 997.5
SHIP_SCALE :: 30.0
SHIP_FRICTION :: 0.39346
SHIP_SHOOT_INTERVAL :: 0.0125

ROTATION_DEGREES_PER_SECOND :: 360.0

// Movement inertia control (0.0 = instant, 1.0 = never reaches target)
// For ease function: 0.1 = very responsive, 0.5 = balanced, 0.9 = very smooth
MOVEMENT_INERTIA :: 0.021
WARP_INERTIA :: 0.05

Projectile :: struct {
	position: rl.Vector2,
	velocity: rl.Vector2,
	active:   bool,
	traveled: f32,
}

Ship :: struct {
	scale:          f32,
	position:       rl.Vector2,     // Screen/local position (for rendering and collision)
	world_position: rl.Vector2,     // World position (for exploration and camera)
	arena_position: rl.Vector2,     // Position within arena bounds (for wrapping mode)
	velocity:       rl.Vector2,     // Current velocity (with inertia)
	target_velocity: rl.Vector2,    // Target velocity from WASD input
	rotation:       f32,
	acceleration:   f32,
	friction:       f32,
	shoot_cooldown: f32,
	shoot_interval: f32,
	projectiles:    [MAX_PROJECTILES]Projectile,
	ship_speed:     f32,            // Current speed magnitude
	warp_speed_target: f32,         // Target warp speed (1.0 to MAX_WARP_MULTIPLIER)
	warp_speed:     f32,            // Warp speed multiplier (1.0 to MAX_WARP_MULTIPLIER)
}

init_ship :: proc(window_width: f32, window_height: f32) -> Ship {
	start_pos := rl.Vector2{window_width / 2, window_height / 2}
	ship := Ship {
		scale = SHIP_SCALE,
		position = start_pos,
		world_position = start_pos, // Start at same position as screen
		arena_position = start_pos, // Initialize arena position
		velocity = rl.Vector2{0.0, 0.0},
		target_velocity = rl.Vector2{0.0, 0.0},
		rotation = 0.0,
		acceleration = SHIP_ACCELERATION,
		friction = SHIP_FRICTION,
		shoot_cooldown = 0.0,
		shoot_interval = SHIP_SHOOT_INTERVAL,
		projectiles = [MAX_PROJECTILES]Projectile{},
		ship_speed = 0.0,
		warp_speed_target = 1.0,
		warp_speed = 1.0,
	}

	return ship
}

shoot_projectile :: proc(ship: ^Ship) {
	if ship.shoot_cooldown > 0.0 {
		return
	}
	for &projectile in &ship.projectiles {
		if !projectile.active {
			radians := ship.rotation * rl.DEG2RAD

			projectile.position = rl.Vector2 {
				ship.position.x + math.cos(radians) * ship.scale,
				ship.position.y + math.sin(radians) * ship.scale,
			}
			projectile_velocity := rl.Vector2{math.cos(radians), math.sin(radians)} * 250.0
			projectile.velocity = projectile_velocity + ship.velocity

			projectile.active = true
			projectile.traveled = 0.0
			ship.shoot_cooldown = ship.shoot_interval
			break
		}
	}
}

update_projectiles :: proc(ship: ^Ship, delta_time: f32, window_width: f32, window_height: f32) {
	for &projectile in &ship.projectiles {
		if projectile.active {
			// store previous position to calculate distance traveled
			prev_position := projectile.position

			projectile.position.x += projectile.velocity.x * delta_time
			projectile.position.y += projectile.velocity.y * delta_time

			// calculate distance traveled this frame
			dx := projectile.position.x - prev_position.x
			dy := projectile.position.y - prev_position.y
			distance_this_frame := math.sqrt(dx * dx + dy * dy)
			projectile.traveled += distance_this_frame

			// wrap around screen edges
			if projectile.position.x < 0 {
				projectile.position.x = window_width
			} else if projectile.position.x > window_width {
				projectile.position.x = 0
			}

			if projectile.position.y < 0 {
				projectile.position.y = window_height
			} else if projectile.position.y > window_height {
				projectile.position.y = 0
			}

			// deactivate projectiles after they've traveled far enough
			if projectile.traveled > 10000.0 {
				projectile.active = false
			}
		}
	}
}

draw_projectiles :: proc(ship: ^Ship) {
	for projectile in &ship.projectiles {
		if projectile.active {
			rl.DrawCircleV(projectile.position, 3.0, {0, 120, 255, 255})
		}
	}
}

update_ship :: proc(ship: ^Ship, camera: ^Camera_State, delta_time: f32, window_width: f32, window_height: f32) {
	// Direct WASD movement input (vampire survivors style)
	input_direction := rl.Vector2{0, 0}

	if rl.IsKeyDown(rl.KeyboardKey.LEFT) || rl.IsKeyDown(rl.KeyboardKey.A) {
		input_direction.x -= 1.0
	}
	if rl.IsKeyDown(rl.KeyboardKey.RIGHT) || rl.IsKeyDown(rl.KeyboardKey.D) {
		input_direction.x += 1.0
	}
	if rl.IsKeyDown(rl.KeyboardKey.UP) || rl.IsKeyDown(rl.KeyboardKey.W) {
		input_direction.y -= 1.0
	}
	if rl.IsKeyDown(rl.KeyboardKey.DOWN) || rl.IsKeyDown(rl.KeyboardKey.S) {
		input_direction.y += 1.0
	}

	input_direction = rl.Vector2Normalize(input_direction)
	ship.target_velocity = input_direction * ship.acceleration
	ship.velocity.x += ease(ship.target_velocity.x, ship.velocity.x, MOVEMENT_INERTIA, delta_time, f32(rl.GetFPS()))
	ship.velocity.y += ease(ship.target_velocity.y, ship.velocity.y, MOVEMENT_INERTIA, delta_time, f32(rl.GetFPS()))

	if rl.Vector2Length(input_direction) > 0.1 {
		target_rotation := math.atan2(input_direction.y, input_direction.x) * rl.RAD2DEG
		rotation_diff := target_rotation - ship.rotation

		// eliminates gimbal lock
		if rotation_diff > 180.0 {
			rotation_diff -= 360.0
		} else if rotation_diff < -180.0 {
			rotation_diff += 360.0
		}

		max_rotation_this_frame := ROTATION_DEGREES_PER_SECOND * delta_time

		if math.abs(rotation_diff) < max_rotation_this_frame {
			ship.rotation = target_rotation
		} else {
			if rotation_diff > 0 {
				ship.rotation += max_rotation_this_frame
			} else {
				ship.rotation -= max_rotation_this_frame
			}
		}
	}

	ship.ship_speed = math.sqrt(ship.velocity.x * ship.velocity.x + ship.velocity.y * ship.velocity.y)

	if ship.ship_speed >= WARP_SPEED_THRESHOLD && ship.ship_speed <= MAX_SHIP_SPEED {
		ship.warp_speed_target = remap(ship.ship_speed, WARP_SPEED_THRESHOLD, MAX_SHIP_SPEED, 1.0, MAX_WARP_MULTIPLIER)
	} else if ship.ship_speed > MAX_SHIP_SPEED {
		ship.warp_speed_target = MAX_WARP_MULTIPLIER
	} else {
		ship.warp_speed_target = 1.0
	}

	ship.warp_speed += ease(ship.warp_speed_target, ship.warp_speed, WARP_INERTIA, delta_time, f32(rl.GetFPS()))

	ship.world_position.x += ship.velocity.x * ship.warp_speed * delta_time
	ship.world_position.y += ship.velocity.y * ship.warp_speed * delta_time
	ship.arena_position = ship.world_position

	switch camera.mode {
	case .FOLLOW_SHIP:
		// In exploration mode, ship position relative to camera
		ship.position.x = ship.world_position.x - camera.position.x + window_width / 2
		ship.position.y = ship.world_position.y - camera.position.y + window_height / 2

	case .SCREEN_WRAP:
		// In screen wrap mode, ship position relative to camera
		ship.position.x = ship.world_position.x - camera.position.x + window_width / 2
		ship.position.y = ship.world_position.y - camera.position.y + window_height / 2

		// Apply screen wrapping - when ship goes off screen, teleport it to other side
		if ship.position.x > window_width {
			ship.world_position.x -= window_width
			ship.position.x = 0
		} else if ship.position.x < 0 {
			ship.world_position.x += window_width
			ship.position.x = window_width
		}
		if ship.position.y > window_height {
			ship.world_position.y -= window_height
			ship.position.y = 0
		} else if ship.position.y < 0 {
			ship.world_position.y += window_height
			ship.position.y = window_height
		}
	}

	// shooting
	if rl.IsKeyDown(rl.KeyboardKey.SPACE) {
		shoot_projectile(ship)
	}

	// update cooldown
	if ship.shoot_cooldown > 0.0 {
		ship.shoot_cooldown -= delta_time
	}

	// update projectiles
	update_projectiles(ship, delta_time, window_width, window_height)
}

draw_ship :: proc(ship: ^Ship) {
	radians := ship.rotation * rl.DEG2RAD

	tip := rl.Vector2 {
		ship.position.x + math.cos(radians) * ship.scale,
		ship.position.y + math.sin(radians) * ship.scale,
	}
	left := rl.Vector2 {
		ship.position.x + math.cos(radians + rl.DEG2RAD * 135.0) * ship.scale * 0.7,
		ship.position.y + math.sin(radians + rl.DEG2RAD * 135.0) * ship.scale * 0.7,
	}
	right := rl.Vector2 {
		ship.position.x + math.cos(radians - rl.DEG2RAD * 135.0) * ship.scale * 0.7,
		ship.position.y + math.sin(radians - rl.DEG2RAD * 135.0) * ship.scale * 0.7,
	}

	// DrawLineEx :: proc(startPos, endPos: Vector2, thick: f32, color: Color) // Draw a line (using triangles/quads)
	rl.DrawLineEx(tip, left, 5.0, rl.WHITE)
	rl.DrawLineEx(tip, right, 5.0, rl.WHITE)
	rl.DrawLineEx(left, right, 5.0, rl.WHITE)
	rl.DrawTriangle(tip, right, left, {0, 0, 0, 150})

	if ship.ship_speed > 10.0 { // Show thrust when ship has some velocity
		thrust_back := rl.Vector2 {
			ship.position.x - math.cos(radians) * ship.scale * 0.8,
			ship.position.y - math.sin(radians) * ship.scale * 0.8,
		}
		rl.DrawCircleV(thrust_back, 3.0, rl.ORANGE)
	}

	// draw projectiles
	draw_projectiles(ship)
}

// draw ship and projectiles to a texture with transparent background
render_ship_to_texture :: proc(ship: ^Ship, ship_render_target: rl.RenderTexture2D) -> rl.Texture2D {
	if ship_render_target.id == 0 {
		return rl.Texture2D{}
	}

	rl.BeginTextureMode(ship_render_target)
	rl.ClearBackground(rl.Color{0, 0, 0, 0})
	draw_ship(ship)
	rl.EndTextureMode()

	return ship_render_target.texture
}

ship_hot_reload :: proc(ship: ^Ship) -> bool {
	fmt.printf("=== HOT RELOADING SHIP SYSTEM ===\n")

	// Store current RUNTIME state (preserve continuity)
	current_position := ship.position
	current_world_position := ship.world_position
	current_arena_position := ship.arena_position
	current_velocity := ship.velocity
	current_target_velocity := ship.target_velocity
	current_rotation := ship.rotation
	current_shoot_cooldown := ship.shoot_cooldown
	current_projectiles := ship.projectiles
	current_ship_speed := ship.ship_speed
	current_warp_speed_target := ship.warp_speed_target
	current_warp_speed := ship.warp_speed

	fmt.printf("Ship state preserved: pos=(%.2f,%.2f), world_pos=(%.2f,%.2f), vel=(%.2f,%.2f), rot=%.2f\n",
		current_position.x, current_position.y,
		current_world_position.x, current_world_position.y,
		current_velocity.x, current_velocity.y,
		current_rotation)

	// Get updated constants directly (pick up code changes)
	new_scale := f32(SHIP_SCALE)
	new_acceleration := f32(SHIP_ACCELERATION)
	new_friction := f32(SHIP_FRICTION)
	new_shoot_interval := f32(SHIP_SHOOT_INTERVAL)

	// Restore RUNTIME state (preserve continuity)
	ship.position = current_position
	ship.world_position = current_world_position
	ship.arena_position = current_arena_position
	ship.velocity = current_velocity
	ship.target_velocity = current_target_velocity
	ship.rotation = current_rotation
	ship.shoot_cooldown = current_shoot_cooldown
	ship.projectiles = current_projectiles
	ship.ship_speed = current_ship_speed
	ship.warp_speed_target = current_warp_speed_target
	ship.warp_speed = current_warp_speed

	// Apply NEW configuration values (pick up code changes)
	ship.scale = new_scale
	ship.acceleration = new_acceleration
	ship.friction = new_friction
	ship.shoot_interval = new_shoot_interval

	fmt.printf("Hot reload: Updated acceleration: %.2f, friction: %.6f, scale: %.2f, shoot_interval: %.4f\n",
		ship.acceleration, ship.friction, ship.scale, ship.shoot_interval)

	fmt.printf("Ship state restored successfully\n")
	fmt.printf("=== SHIP HOT RELOAD COMPLETE ===\n")
	return true
}

cleanup_ship :: proc(ship: ^Ship) {
	// No cleanup needed for ship itself currently - projectiles are stack-allocated
}