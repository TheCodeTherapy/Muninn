package gamelogic

import "core:math"
import rl "vendor:raylib"
import "core:fmt"

MAX_PROJECTILES :: 10000

MAX_SHIP_SPEED :: 1000.0
MAX_WARP_MULTIPLIER :: 3.0
WARP_SPEED_THRESHOLD :: 997.0

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
	velocity:       rl.Vector2,
	rotation:       f32,
	acceleration:   f32,
	friction:       f32,
	shoot_cooldown: f32,
	shoot_interval: f32,
	projectiles:    [MAX_PROJECTILES]Projectile,
	ship_speed:     f32,            // Current speed magnitude
	warp_speed:     f32,            // Warp speed multiplier (1.0 to MAX_WARP_MULTIPLIER)
	trail:          Ship_Trail,     // Ship trail system
}

init_ship :: proc(window_width: f32, window_height: f32) -> Ship {
	start_pos := rl.Vector2{window_width / 2, window_height / 2}
	ship := Ship {
		scale = 30,
		position = start_pos,
		world_position = start_pos, // Start at same position as screen
		arena_position = start_pos, // Initialize arena position
		velocity = rl.Vector2{0.0, 0.0},
		rotation = 0.0,
		acceleration = 500.0,
		friction = 0.39346,
		shoot_cooldown = 0.0,
		shoot_interval = 0.0125,
		projectiles = [MAX_PROJECTILES]Projectile{},
		ship_speed = 0.0,
		warp_speed = 1.0,
		trail = Ship_Trail{},
	}

	// Initialize the trail system
	init_ship_trail(&ship.trail, ship.scale * 0.25) // Use half the ship scale as radius
	reset_ship_trail(&ship.trail, ship.world_position, 0.0) // Initialize with world position

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
	// ship rotation
	if rl.IsKeyDown(rl.KeyboardKey.RIGHT) || rl.IsKeyDown(rl.KeyboardKey.D) {
		ship.rotation += 180.0 * delta_time
	}
	if rl.IsKeyDown(rl.KeyboardKey.LEFT) || rl.IsKeyDown(rl.KeyboardKey.A) {
		ship.rotation -= 180.0 * delta_time
	}

	// ship thrust
	if rl.IsKeyDown(rl.KeyboardKey.UP) || rl.IsKeyDown(rl.KeyboardKey.W) {
		radians := ship.rotation * rl.DEG2RAD
		ship.velocity.x += math.cos(radians) * ship.acceleration * delta_time
		ship.velocity.y += math.sin(radians) * ship.acceleration * delta_time
	}

	// apply friction (exponential decay - frame rate independent)
	friction_factor := math.pow(1.0 - ship.friction, delta_time)
	ship.velocity.x *= friction_factor
	ship.velocity.y *= friction_factor

	// calculate ship speed from velocity magnitude
	ship.ship_speed = math.sqrt(ship.velocity.x * ship.velocity.x + ship.velocity.y * ship.velocity.y)

	// calculate warp speed multiplier based on ship speed
	if ship.ship_speed >= WARP_SPEED_THRESHOLD && ship.ship_speed <= MAX_SHIP_SPEED {
		ship.warp_speed = remap(ship.ship_speed, WARP_SPEED_THRESHOLD, MAX_SHIP_SPEED, 1.0, MAX_WARP_MULTIPLIER)
	} else if ship.ship_speed > MAX_SHIP_SPEED {
		ship.warp_speed = MAX_WARP_MULTIPLIER
	} else {
		ship.warp_speed = 1.0
	}

	// ALWAYS update world position accurately - no more freezing!
	ship.world_position.x += ship.velocity.x * ship.warp_speed * delta_time
	ship.world_position.y += ship.velocity.y * ship.warp_speed * delta_time

	// Keep arena position synced with world position
	ship.arena_position = ship.world_position

	// update screen/local position based on camera mode
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

	// update ship trail - distance-based sampling in WORLD SPACE with thruster offset!
	add_trail_position(&ship.trail, ship.world_position, ship.rotation, ship.ship_speed, MAX_SHIP_SPEED, g_state.global_time)
}

draw_ship :: proc(ship: ^Ship) {
	g_state := get_state()
	render_ship_trail(&ship.trail, g_state.global_time, &g_state.camera, g_state.resolution.x, g_state.resolution.y, ship.rotation)

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

	// rl.DrawLine(i32(tip.x), i32(tip.y), i32(left.x), i32(left.y), rl.BLACK)
	// rl.DrawLine(i32(tip.x), i32(tip.y), i32(right.x), i32(right.y), rl.BLACK)
	// rl.DrawLine(i32(left.x), i32(left.y), i32(right.x), i32(right.y), rl.BLACK)

	// draw ship's tringle filled
	rl.DrawTriangle(tip, right, left, {0, 0, 0, 150})

	// thrust indicator
	if rl.IsKeyDown(rl.KeyboardKey.UP) || rl.IsKeyDown(rl.KeyboardKey.W) {
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
draw_ship_to_texture :: proc(ship: ^Ship) -> rl.Texture2D {
	g_state := get_state()

	if g_state.ship_render_target.id == 0 {
		return rl.Texture2D{}
	}

	rl.BeginTextureMode(g_state.ship_render_target)
	rl.ClearBackground(rl.Color{0, 0, 0, 0})
	draw_ship(ship)
	rl.EndTextureMode()

	return g_state.ship_render_target.texture
}

// cleanup ship resources
// Hot reload ship system
ship_hot_reload :: proc(ship: ^Ship) -> bool {
	fmt.printf("=== HOT RELOADING SHIP SYSTEM ===\n")

	// Store current state for continuity
	current_scale := ship.scale
	current_position := ship.position
	current_world_position := ship.world_position
	current_arena_position := ship.arena_position
	current_velocity := ship.velocity
	current_rotation := ship.rotation
	current_acceleration := ship.acceleration
	current_friction := ship.friction
	current_shoot_cooldown := ship.shoot_cooldown
	current_shoot_interval := ship.shoot_interval
	current_projectiles := ship.projectiles
	current_ship_speed := ship.ship_speed
	current_warp_speed := ship.warp_speed

	fmt.printf("Ship state preserved: pos=(%.2f,%.2f), world_pos=(%.2f,%.2f), vel=(%.2f,%.2f), rot=%.2f\n",
		current_position.x, current_position.y,
		current_world_position.x, current_world_position.y,
		current_velocity.x, current_velocity.y,
		current_rotation)

	// Hot reload the ship trail
	if ship.trail.initialized {
		fmt.printf("Hot reloading ship trail...\n")
		if !ship_trail_hot_reload(&ship.trail) {
			fmt.printf("ERROR: Ship hot reload: Failed to reload trail\n")
			return false
		}
		fmt.printf("Ship trail hot reload successful\n")
	} else {
		fmt.printf("Ship trail not initialized, skipping trail hot reload\n")
	}

	// Restore all state
	ship.scale = current_scale
	ship.position = current_position
	ship.world_position = current_world_position
	ship.arena_position = current_arena_position
	ship.velocity = current_velocity
	ship.rotation = current_rotation
	ship.acceleration = current_acceleration
	ship.friction = current_friction
	ship.shoot_cooldown = current_shoot_cooldown
	ship.shoot_interval = current_shoot_interval
	ship.projectiles = current_projectiles
	ship.ship_speed = current_ship_speed
	ship.warp_speed = current_warp_speed

	fmt.printf("Ship state restored successfully\n")
	fmt.printf("=== SHIP HOT RELOAD COMPLETE ===\n")
	return true
}

cleanup_ship :: proc(ship: ^Ship) {
	destroy_ship_trail(&ship.trail)
}