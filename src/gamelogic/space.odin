package gamelogic

import "core:fmt"
import "core:math"
import rl "vendor:raylib"

Space_System :: struct {
	shader_manager:      Shader_Manager,
	background_texture:  rl.Texture2D,
	initialized:         bool,
}

space_system_init :: proc(space: ^Space_System, width, height: f32, file_reader: File_Reader) -> bool {
	// get shader paths based on WebGL version
	space_vertex_path := "shaders/v100/default.vert"
	space_shader_0_fragment_path := "shaders/v100/space-shader-0.frag"
	space_shader_1_fragment_path := "shaders/v100/space-shader-1.frag"
	space_shader_2_fragment_path := "shaders/v100/space-shader-2.frag"
	space_shader_3_fragment_path := "shaders/v100/space-shader-3.frag"

	when #config(USE_WEBGL2, false) {
		space_vertex_path = "shaders/v300es/default.vert"
		space_shader_0_fragment_path = "shaders/v300es/space-shader-0.frag"
		space_shader_1_fragment_path = "shaders/v300es/space-shader-1.frag"
		space_shader_2_fragment_path = "shaders/v300es/space-shader-2.frag"
		space_shader_3_fragment_path = "shaders/v300es/space-shader-3.frag"
	}

	// define all the uniforms that the space shaders need
	space_shader_uniforms := []Uniform_Definition{
		{"time", f32(0.0)},
		{"delta_time", f32(0.0)},
		{"frame", i32(0)},
		{"fps", f32(0.0)},
		{"resolution", rl.Vector2{width, height}},
		{"mouse", rl.Vector2{0, 0}},
		{"mouselerp", rl.Vector2{0, 0}},
		{"font_atlas", rl.Texture2D{}},
		{"ship_world_position", rl.Vector2{0, 0}},
		{"ship_screen_position", rl.Vector2{0, 0}},
		{"camera_position", rl.Vector2{0, 0}},
		{"ship_direction", rl.Vector2{0, 0}},
		{"ship_velocity", rl.Vector2{0, 0}},
		{"ship_speed", f32(0.0)},
	}

	shader_manager, shader_manager_initialized := shader_manager_init_from_paths(
		"Space Shaders",
		space_vertex_path,
		{
			space_shader_0_fragment_path,
			space_shader_1_fragment_path,
			space_shader_2_fragment_path,
			space_shader_3_fragment_path,
		},
		space_shader_uniforms,
		i32(width), i32(height),
		file_reader,
	)

	if !shader_manager_initialized {
		fmt.printf("Failed to initialize space shader manager\n")
		return false
	}

	space.shader_manager = shader_manager
	space.initialized = true
	fmt.printf("Space system initialized successfully\n")
	return true
}

space_system_update :: proc(space: ^Space_System, game_state: ^Game_State) {
	if !space.initialized || space.shader_manager.shader_count == 0 {
		return
	}
  screen_width := f32(space.shader_manager.screen_width)
  screen_height := f32(space.shader_manager.screen_height)
  resolution := rl.Vector2{screen_width, screen_height}

  mouse_pos := rl.GetMousePosition()
	normalized_mouse := rl.Vector2{
		(mouse_pos.x / screen_width) * 2.0 - 1.0,  // normalizes [0,width] to [-1,1]
		1.0 - (mouse_pos.y / screen_height) * 2.0, // normalizes [0,height] to [1,-1], then flips Y
	}

	// update time-based uniforms
	shader_manager_set_uniform(&space.shader_manager, "time", game_state.global_time)
	shader_manager_set_uniform(&space.shader_manager, "delta_time", game_state.delta_time)
	shader_manager_set_uniform(&space.shader_manager, "frame", i32(game_state.frame))
	shader_manager_set_uniform(&space.shader_manager, "fps", f32(game_state.fps))
	shader_manager_set_uniform(&space.shader_manager, "resolution", resolution)

	// update mouse uniforms
	shader_manager_set_uniform(&space.shader_manager, "mouse", normalized_mouse)
	shader_manager_set_uniform(&space.shader_manager, "mouselerp", normalized_mouse)

	// set font atlas texture
	shader_manager_set_uniform(&space.shader_manager, "font_atlas", game_state.font_atlas_texture)

	// set ship position uniforms
	shader_manager_set_uniform(&space.shader_manager, "ship_world_position", game_state.ship.world_position)
	shader_manager_set_uniform(&space.shader_manager, "ship_screen_position", game_state.ship.position)
	shader_manager_set_uniform(&space.shader_manager, "camera_position", game_state.camera.position)

	// calculate ship direction from rotation
	ship_radians := game_state.ship.rotation * rl.DEG2RAD
	ship_direction := rl.Vector2{
		math.cos(ship_radians),
		math.sin(ship_radians),
	}

	// set new thruster uniforms
	shader_manager_set_uniform(&space.shader_manager, "ship_direction", ship_direction)
	shader_manager_set_uniform(&space.shader_manager, "ship_velocity", game_state.ship.velocity)
	warp_boost := math.clamp(game_state.ship.ship_speed - 997.75, 0.0, 1000.0) * 1.2
	shader_manager_set_uniform(
		&space.shader_manager,
		"ship_speed",
		game_state.ship.ship_speed + warp_boost,
	)
}

space_system_render :: proc(space: ^Space_System) -> rl.Texture2D {
	if !space.initialized || space.shader_manager.shader_count == 0 {
		return {}
	}

	space.background_texture = shader_manager_render(&space.shader_manager)
	return space.background_texture
}

space_system_resize :: proc(space: ^Space_System, width, height: i32) {
	if !space.initialized || space.shader_manager.shader_count == 0 {
		return
	}

	shader_manager_resize(&space.shader_manager, width, height)
}

space_system_reload_shaders :: proc(space: ^Space_System) {
	if !space.initialized || space.shader_manager.shader_count == 0 {
		return
	}

	shader_manager_reload_shaders(&space.shader_manager)
	fmt.printf("Space shaders reloaded\n")
}

space_system_destroy :: proc(space: ^Space_System) {
	if !space.initialized {
		return
	}

	if space.shader_manager.shader_count > 0 {
		shader_manager_destroy(&space.shader_manager)
	}

	space.initialized = false
	fmt.printf("Space system destroyed\n")
}

space_system_is_ready :: proc(space: ^Space_System) -> bool {
	return space.initialized && space.shader_manager.shader_count > 0
}
