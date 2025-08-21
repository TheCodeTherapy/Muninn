package gamelogic

import "core:fmt"
import rl "vendor:raylib"

// suppress unused import warning in release builds
_ :: fmt

PIXEL_WINDOW_HEIGHT :: 180

// camera modes for different gameplay scenarios
Camera_Mode :: enum {
	FOLLOW_SHIP,    // normal exploration - camera follows ship
	FIXED_BOUNDS,   // boss fights - camera shows fixed area with screen wrapping
	FREE_EXPLORE,   // camera can move independently
}

// Camera state for the game world
Camera_State :: struct {
	mode:           Camera_Mode,
	position:       rl.Vector2,    // current camera position in world space
	target:         rl.Vector2,    // target position (ship + offset based on movement)
	zoom:           f32,

	smooth_factor:  f32,           // how smoothly camera follows (lerped)
	smooth_factor_target: f32,     // how smoothly camera follows (0.1 = smooth, 1.0 = instant)

	// camera offset system for looking ahead
	offset_multiplier: f32,        // how far ahead to look (0 = no offset, 1 = full offset)
	max_velocity:      f32,        // maximum velocity for normalization (clamp velocity to this)

	// for fixed bounds mode (boss fights, etc.)
	fixed_bounds:   rl.Rectangle,  // fixed area bounds
	enable_wrapping: bool,         // whether ship should wrap around screen edges
}

init_camera :: proc() -> Camera_State {
	return Camera_State {
		mode = .FOLLOW_SHIP,
		position = {0, 0},
		target = {0, 0},
		zoom = 1.0,

		smooth_factor = 0.12,
		smooth_factor_target = 0.12,

		offset_multiplier = 30.0, // look-ahead distance
		max_velocity = 1000.0,
		fixed_bounds = {0, 0, 0, 0},
		enable_wrapping = false,
	}
}

update_camera :: proc(camera: ^Camera_State, ship_world_pos: rl.Vector2, ship_velocity: rl.Vector2, ship_rotation: f32, delta_time: f32) {
	camera.smooth_factor += ease(
		camera.smooth_factor_target,
		camera.smooth_factor,
		camera.mode <= .FOLLOW_SHIP ? 0.01 : 0.05,
		delta_time,
		f32(rl.GetFPS()),
	)

	switch camera.mode {
	case .FOLLOW_SHIP:
		// look-ahead offset based on ship's movement
		camera.smooth_factor_target = 0.12

		velocity_magnitude := vector_magnitude(ship_velocity)
		clamped_velocity := clamp(velocity_magnitude, 0, camera.max_velocity)
		velocity_factor := camera.max_velocity > 0 ? clamped_velocity / camera.max_velocity : 0.0 // 0 to 1

		direction := direction_from_angle(ship_rotation) // direction vector from ship's rotation

		// scale direction by velocity factor and multiplier to get offset
		offset := rl.Vector2{
			direction.x * velocity_factor * camera.offset_multiplier,
			direction.y * velocity_factor * camera.offset_multiplier,
		}

		// camera target is ship position + look-ahead offset
		camera.target = rl.Vector2{
			ship_world_pos.x + offset.x,
			ship_world_pos.y + offset.y,
		}

		// smooth camera movement
		camera.position.x += ease(camera.target.x, camera.position.x, camera.smooth_factor, delta_time, f32(rl.GetFPS()))
		camera.position.y += ease(camera.target.y, camera.position.y, camera.smooth_factor, delta_time, f32(rl.GetFPS()))

	case .FIXED_BOUNDS:
		camera.smooth_factor_target = 0.001
		// camera target is centered on the fixed bounds area
		camera.target.x = camera.fixed_bounds.x + camera.fixed_bounds.width / 2
		camera.target.y = camera.fixed_bounds.y + camera.fixed_bounds.height / 2

		// smooth camera movement
		camera.position.x += ease(camera.target.x, camera.position.x, camera.smooth_factor, delta_time, f32(rl.GetFPS()))
		camera.position.y += ease(camera.target.y, camera.position.y, camera.smooth_factor, delta_time, f32(rl.GetFPS()))

	case .FREE_EXPLORE:
		// camera can move independently (for future use)
		// for now it just follow the ship
		camera.target = ship_world_pos
		camera.position = camera.target
	}
}

set_camera_mode :: proc(camera: ^Camera_State, mode: Camera_Mode, bounds: rl.Rectangle = {}) {
	previous_mode := camera.mode
	camera.mode = mode

	switch mode {
	case .FOLLOW_SHIP:
		camera.enable_wrapping = false
		// if transitioning from arena mode, sync world position to current arena position
		if previous_mode == .FIXED_BOUNDS {
			// TODO: I'll probably add some visual effect here
		}

	case .FIXED_BOUNDS:
		camera.fixed_bounds = bounds
		camera.enable_wrapping = true

	case .FREE_EXPLORE:
		camera.enable_wrapping = false
	}
}

game_camera :: proc() -> rl.Camera2D {
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())

	return {
		zoom = (h / PIXEL_WINDOW_HEIGHT) * g_state.camera.zoom,
		target = g_state.camera.position, // Use current smoothly interpolated position
		offset = { w/2, h/2 },
	}
}

// debug visualization for camera look-ahead system
debug_draw_camera_lookahead :: proc(ship_screen_pos: rl.Vector2, ship_velocity: rl.Vector2, ship_rotation: f32) {
	when #config(ODIN_DEBUG, false) {
		if !g_state.debug_ui_enabled do return

		camera := &g_state.camera

		// calculate the same offset as in update_camera
		velocity_magnitude := vector_magnitude(ship_velocity)
		clamped_velocity := clamp(velocity_magnitude, 0, camera.max_velocity)
		velocity_factor := camera.max_velocity > 0 ? clamped_velocity / camera.max_velocity : 0.0

		direction := direction_from_angle(ship_rotation)

		// scale the offset for screen display (convert world units to screen pixels)
		game_cam := game_camera()
		screen_offset := rl.Vector2{
			direction.x * velocity_factor * camera.offset_multiplier * game_cam.zoom,
			direction.y * velocity_factor * camera.offset_multiplier * game_cam.zoom,
		}

		// draw red line from ship center to look-ahead target
		target_screen_pos := rl.Vector2{
			ship_screen_pos.x + screen_offset.x,
			ship_screen_pos.y + screen_offset.y,
		}

		rl.DrawLineV(ship_screen_pos, target_screen_pos, rl.RED)
		rl.DrawCircleV(target_screen_pos, 3.0, rl.RED) // small circle at the end of the vector

		// draw velocity factor as text near ship
		velocity_text := fmt.ctprintf("Vel: %.1f (%.2f%%)", velocity_magnitude, velocity_factor * 100)
		rl.DrawText(velocity_text, i32(ship_screen_pos.x + 40), i32(ship_screen_pos.y - 20), 12, rl.WHITE)
	}
}

// for hot-reloading
camera_hot_reload :: proc(camera: ^Camera_State) {
	// store current position to maintain continuity
	current_pos := camera.position
	current_target := camera.target
	current_mode := camera.mode

	// completely reinitialize camera with fresh defaults
	camera^ = init_camera()

	// restore position/target/mode to maintain gameplay continuity
	camera.position = current_pos
	camera.target = current_target
	camera.mode = current_mode
}

ui_camera :: proc() -> rl.Camera2D {
	return {
		zoom = f32(rl.GetScreenHeight())/PIXEL_WINDOW_HEIGHT,
	}
}
