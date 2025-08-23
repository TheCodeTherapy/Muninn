package gamelogic

import "core:math"
import rl "vendor:raylib"

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
}

init_ship :: proc(window_width: f32, window_height: f32) -> Ship {
	start_pos := rl.Vector2{window_width / 2, window_height / 2}
	return Ship {
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
	}
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

	// update world position based on camera mode
	if camera.mode == .FIXED_BOUNDS && camera.enable_wrapping {
		// In wrapping mode: update arena position, keep world position fixed at bounds center
		ship.arena_position.x += ship.velocity.x * delta_time
		ship.arena_position.y += ship.velocity.y * delta_time

		// Keep world position at the center of the bounds for static space background
		ship.world_position = {
			camera.fixed_bounds.x + camera.fixed_bounds.width / 2,
			camera.fixed_bounds.y + camera.fixed_bounds.height / 2,
		}
	} else {
		// Check if we just transitioned from arena mode - if so, restore world position from arena position
		if ship.world_position.x == camera.fixed_bounds.x + camera.fixed_bounds.width / 2 &&
		   ship.world_position.y == camera.fixed_bounds.y + camera.fixed_bounds.height / 2 {
			// We were in arena mode, transfer arena position back to world position
			ship.world_position = ship.arena_position
		}

		// Normal exploration mode - world position tracks ship movement through space
		ship.world_position.x += ship.velocity.x * ship.warp_speed * delta_time
		ship.world_position.y += ship.velocity.y * ship.warp_speed * delta_time
		// Keep arena position synced with world position in exploration
		ship.arena_position = ship.world_position
	}

	// update screen/local position based on camera mode
	switch camera.mode {
	case .FOLLOW_SHIP:
		// In exploration mode, ship position relative to camera
		ship.position.x = ship.world_position.x - camera.position.x + window_width / 2
		ship.position.y = ship.world_position.y - camera.position.y + window_height / 2

	case .FIXED_BOUNDS:
		if camera.enable_wrapping {
			// In wrapping mode, use arena position for screen positioning
			ship.position.x = ship.arena_position.x - camera.position.x + window_width / 2
			ship.position.y = ship.arena_position.y - camera.position.y + window_height / 2

			// Apply screen wrapping - wrap arena position, not world position
			if ship.position.x > window_width {
				ship.arena_position.x -= window_width
				ship.position.x = 0
			} else if ship.position.x < 0 {
				ship.arena_position.x += window_width
				ship.position.x = window_width
			}
			if ship.position.y > window_height {
				ship.arena_position.y -= window_height
				ship.position.y = 0
			} else if ship.position.y < 0 {
				ship.arena_position.y += window_height
				ship.position.y = window_height
			}
		} else {
			// Fixed bounds without wrapping - use world position
			ship.position.x = ship.world_position.x - camera.position.x + window_width / 2
			ship.position.y = ship.world_position.y - camera.position.y + window_height / 2
		}

	case .FREE_EXPLORE:
		// Free exploration mode - ship can move anywhere on screen
		ship.position.x = ship.world_position.x - camera.position.x + window_width / 2
		ship.position.y = ship.world_position.y - camera.position.y + window_height / 2
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

	// draw ship triangle
	rl.DrawLine(i32(tip.x), i32(tip.y), i32(left.x), i32(left.y), rl.WHITE)
	rl.DrawLine(i32(tip.x), i32(tip.y), i32(right.x), i32(right.y), rl.WHITE)
	rl.DrawLine(i32(left.x), i32(left.y), i32(right.x), i32(right.y), rl.WHITE)

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

	// Safety check: ensure render target is valid
	if g_state.ship_render_target.id == 0 {
		// Return empty texture if render target is not initialized
		return rl.Texture2D{}
	}

	rl.BeginTextureMode(g_state.ship_render_target)
	rl.ClearBackground(rl.Color{0, 0, 0, 0})
	draw_ship(ship)
	rl.EndTextureMode()

	return g_state.ship_render_target.texture
}