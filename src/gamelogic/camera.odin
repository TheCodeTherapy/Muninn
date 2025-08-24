package gamelogic

import "core:fmt"
import rl "vendor:raylib"

// suppress unused import warning in release builds
_ :: fmt

PIXEL_WINDOW_HEIGHT :: 180

// camera modes for different gameplay scenarios
Camera_Mode :: enum {
	FOLLOW_SHIP,    // normal exploration - camera follows ship
	SCREEN_WRAP,    // boss fights - camera shows fixed area with screen wrapping
}

// Camera state for the game world
Camera_State :: struct {
	mode:                     Camera_Mode,  // follow mode or screen wrap mode
	position:                 rl.Vector2,   // current camera position in world space
	target:                   rl.Vector2,   // target position (ship position)
	zoom:                     f32,

	smooth_factor:            f32,          // how smoothly camera follows (lerped)
	smooth_factor_target:     f32,          // how smoothly camera follows (0.1 = smooth, 1.0 = instant)

	world_lookahead_position: rl.Vector2,   // ship position + lookahead offset
	offset_multiplier:        f32,          // how far ahead to look (0 = no offset, 1 = full offset)
	max_velocity:             f32,          // maximum velocity for normalization (clamp velocity to this)

	wrap_bounds:              rl.Rectangle, // screen wrap area bounds
}

init_camera :: proc() -> Camera_State {
	return Camera_State {
		mode = .FOLLOW_SHIP,
		position = {0, 0},
		target = {0, 0},
		zoom = 1.0,

		smooth_factor = 0.12,
		smooth_factor_target = 0.12,

		world_lookahead_position = {0, 0},
		offset_multiplier = 30.0,
		max_velocity = 1000.0,
		wrap_bounds = {0, 0, 0, 0},
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

	// calculate lookahead position (for now for debug vis)
	velocity_magnitude := vector_magnitude(ship_velocity)
	clamped_velocity := clamp(velocity_magnitude, 0, camera.max_velocity)
	velocity_factor := camera.max_velocity > 0 ? clamped_velocity / camera.max_velocity : 0.0
	direction := direction_from_angle(ship_rotation)

	// scale direction by velocity factor and multiplier to get offset
	offset := rl.Vector2{
		direction.x * velocity_factor * camera.offset_multiplier,
		direction.y * velocity_factor * camera.offset_multiplier,
	}

	// store lookahead position (ship + offset)
	camera.world_lookahead_position = rl.Vector2{
		ship_world_pos.x + offset.x,
		ship_world_pos.y + offset.y,
	}

	switch camera.mode {
	case .FOLLOW_SHIP:
		camera.smooth_factor_target = 0.12
		camera.target = ship_world_pos

		camera.position.x += ease(camera.target.x, camera.position.x, camera.smooth_factor, delta_time, f32(rl.GetFPS()))
		camera.position.y += ease(camera.target.y, camera.position.y, camera.smooth_factor, delta_time, f32(rl.GetFPS()))

	case .SCREEN_WRAP:
		camera.smooth_factor_target = 0.001
		camera.target.x = camera.wrap_bounds.x + camera.wrap_bounds.width / 2
		camera.target.y = camera.wrap_bounds.y + camera.wrap_bounds.height / 2

		camera.position.x += ease(camera.target.x, camera.position.x, camera.smooth_factor, delta_time, f32(rl.GetFPS()))
		camera.position.y += ease(camera.target.y, camera.position.y, camera.smooth_factor, delta_time, f32(rl.GetFPS()))
	}
}

set_camera_mode :: proc(camera: ^Camera_State, mode: Camera_Mode, bounds: rl.Rectangle = {}) {
	camera.mode = mode

	switch mode {
	case .FOLLOW_SHIP:
		// normal follow ship mode so no special setup needed

	case .SCREEN_WRAP:
		camera.wrap_bounds = bounds
	}
}

game_camera :: proc() -> rl.Camera2D {
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())

	return {
		zoom = (h / PIXEL_WINDOW_HEIGHT) * g_state.camera.zoom,
		target = g_state.camera.position, // smoothly interpolated position
		offset = { w / 2, h / 2 },
	}
}

// debug visualization for camera look-ahead system
debug_draw_camera_lookahead :: proc(ship_screen_pos: rl.Vector2, ship_velocity: rl.Vector2, ship_rotation: f32) {
	when #config(ODIN_DEBUG, false) {
		if !g_state.debug_ui_enabled do return

		camera := &g_state.camera

		// convert world lookahead position to screen-space	position
		lookahead_screen_pos := rl.Vector2{
			camera.world_lookahead_position.x - camera.position.x + f32(rl.GetScreenWidth()) / 2,
			camera.world_lookahead_position.y - camera.position.y + f32(rl.GetScreenHeight()) / 2,
		}

		// draw red line from ship center to look-ahead target
		rl.DrawLineV(ship_screen_pos, lookahead_screen_pos, rl.RED)
		rl.DrawCircleV(lookahead_screen_pos, 3.0, rl.RED) // small circle at the end of the vector

		// calculate velocity info for display
		velocity_magnitude := vector_magnitude(ship_velocity)
		clamped_velocity := clamp(velocity_magnitude, 0, camera.max_velocity)
		velocity_factor := camera.max_velocity > 0 ? clamped_velocity / camera.max_velocity : 0.0

		// draw velocity factor as text near ship
		velocity_text := fmt.ctprintf("Vel: %.1f (%.2f%%)", velocity_magnitude, velocity_factor * 100)
		rl.DrawText(velocity_text, i32(ship_screen_pos.x + 40), i32(ship_screen_pos.y - 20), 20, {255, 255, 255, 200})
	}
}

camera_hot_reload :: proc(camera: ^Camera_State) {
	// store current position to maintain continuity
	current_pos := camera.position
	current_target := camera.target
	current_lookahead := camera.world_lookahead_position
	current_mode := camera.mode

	// reinitialize camera with fresh defaults
	camera^ = init_camera()

	// restore position / target / lookahead / mode to maintain continuity
	camera.position = current_pos
	camera.target = current_target
	camera.world_lookahead_position = current_lookahead
	camera.mode = current_mode
}

ui_camera :: proc() -> rl.Camera2D {
	return {
		zoom = f32(rl.GetScreenHeight())/PIXEL_WINDOW_HEIGHT,
	}
}
