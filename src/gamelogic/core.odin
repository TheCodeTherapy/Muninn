package gamelogic

import "core:math"
import rl "vendor:raylib"
import mu "vendor:microui"

// Feature flag: Use WebGL2 context and shaders (false = WebGL1, true = WebGL2)
// WebGL2 has known vertex attribute issues with Raylib (GitHub issue #4330)
// TODO: I should figure this shit out.
USE_WEBGL2 :: false

// file reader function that will be set by the game package
file_reader_func: proc(filename: string, allocator := context.allocator, loc := #caller_location) -> (data: []byte, success: bool)

// set the file reader function (called from game package)
set_file_reader :: proc(reader: proc(filename: string, allocator := context.allocator, loc := #caller_location) -> (data: []byte, success: bool)) {
  file_reader_func = reader
}

Game_State :: struct {
	// display and timing
	resolution:       rl.Vector2,
	fps:              int,
	delta_time:       f32,
	global_time:      f32,
	frame:            int,

	// game objects/systems
	ship:             Ship,
	camera:           Camera_State,
	space_shaders:    Shader_Manager, // Background space shaders (multi-pass)

	// textures
	font_atlas_texture: rl.Texture2D, // font atlas texture for shaders

	// debug UI (only in debug builds)
	debug_ui_ctx:     ^mu.Context,
	debug_ui_enabled: bool,
	debug_atlas_texture: rl.RenderTexture2D, // font atlas for debug UI

	// game state
	run:              bool,
}

g_state: ^Game_State

init :: proc() {
	g_state = new(Game_State)

	width := f32(rl.GetScreenWidth())
	height := f32(rl.GetScreenHeight())

	// initialize debug UI context first
	debug_ui_ctx: ^mu.Context = nil
	debug_enabled := false
	debug_atlas_texture: rl.RenderTexture2D
	when #config(ODIN_DEBUG, false) {
		debug_ui_ctx = new(mu.Context)
		mu.init(debug_ui_ctx)

		// use MicroUI's default atlas text callbacks (proper font rendering)
		debug_ui_ctx.text_width = mu.default_atlas_text_width
		debug_ui_ctx.text_height = mu.default_atlas_text_height

		// create font atlas texture from MicroUI's default atlas
		debug_atlas_texture = rl.LoadRenderTexture(i32(mu.DEFAULT_ATLAS_WIDTH), i32(mu.DEFAULT_ATLAS_HEIGHT))

		image := rl.GenImageColor(i32(mu.DEFAULT_ATLAS_WIDTH), i32(mu.DEFAULT_ATLAS_HEIGHT), rl.Color{0, 0, 0, 0})
		defer rl.UnloadImage(image)

		for alpha, i in mu.default_atlas_alpha {
			x := i % mu.DEFAULT_ATLAS_WIDTH
			y := i / mu.DEFAULT_ATLAS_WIDTH
			color := rl.Color{255, 255, 255, alpha}
			rl.ImageDrawPixel(&image, i32(x), i32(y), color)
		}

		rl.BeginTextureMode(debug_atlas_texture)
		rl.UpdateTexture(debug_atlas_texture.texture, rl.LoadImageColors(image))
		rl.EndTextureMode()

		debug_enabled = false // start with debug UI disabled
	}

	space_vertex_path := "shaders/v100/default.vert"
	space_shader_0_fragment_path := "shaders/v100/space-shader-0.frag"
	space_shader_1_fragment_path := "shaders/v100/space-shader-1.frag"
	space_shader_2_fragment_path := "shaders/v100/space-shader-2.frag"
	space_shader_3_fragment_path := "shaders/v100/space-shader-3.frag"

	when USE_WEBGL2 {
		// WebGL2 requires shaders to be in the same directory as the executable
		space_vertex_path = "shaders/v300es/default.vert"
		space_shader_0_fragment_path = "shaders/v300es/space-shader-0.frag"
		space_shader_1_fragment_path = "shaders/v300es/space-shader-1.frag"
		space_shader_2_fragment_path = "shaders/v300es/space-shader-2.frag"
		space_shader_3_fragment_path = "shaders/v300es/space-shader-3.frag"
	}

	// initialize shader manager with shaders 0-3
	space_shaders, shader_manager_initialized := shader_manager_init_from_paths(
		"Space Shaders",
		space_vertex_path,
		{
			space_shader_0_fragment_path,
			space_shader_1_fragment_path,
			space_shader_2_fragment_path,
			space_shader_3_fragment_path,
		},
		i32(width), i32(height),
		file_reader_func,
		debug_ui_ctx,
	)
	// load font atlas texture
	font_atlas_image := rl.LoadImage("assets/font_atlas.png")
	font_atlas_texture: rl.Texture2D
	if font_atlas_image.data != nil {
		// flip the image vertically to correct for OpenGL coordinate system
		rl.ImageFlipVertical(&font_atlas_image)
		font_atlas_texture = rl.LoadTextureFromImage(font_atlas_image)
		rl.UnloadImage(font_atlas_image)
	} else {
		// fallback: create a simple white texture if font atlas is not found
		font_atlas_texture = rl.LoadTextureFromImage(rl.GenImageColor(1, 1, rl.WHITE))
		rl.SetTextureFilter(font_atlas_texture, .ANISOTROPIC_16X)

		// TODO: Add proper logging for missing font atlas
	}

	// load assets (including window icon)
	load_assets()

	g_state^ = Game_State {
		resolution = rl.Vector2{width, height},
		fps = 0,
		delta_time = 0,
		global_time = 0,
		frame = 1,
		ship = init_ship(width, height),
		camera = init_camera(),
		space_shaders = shader_manager_initialized ? space_shaders : {},
		font_atlas_texture = font_atlas_texture,
		debug_ui_ctx = debug_ui_ctx,
		debug_ui_enabled = debug_enabled,
		debug_atlas_texture = debug_atlas_texture,
		run = true,
	}

	// initialize camera position to match ship's starting position
	g_state.camera.position = g_state.ship.world_position
	g_state.camera.target = g_state.ship.world_position
}

shutdown :: proc() {
	// clean up shader manager
	if g_state.space_shaders.shader_count > 0 {
		shader_manager_destroy(&g_state.space_shaders)
	}

	// clean up font atlas texture
	if g_state.font_atlas_texture.id != 0 {
		rl.UnloadTexture(g_state.font_atlas_texture)
	}

	// clean up debug UI
	when #config(ODIN_DEBUG, false) {
		if g_state.debug_atlas_texture.id != 0 {
			rl.UnloadRenderTexture(g_state.debug_atlas_texture)
		}
		if g_state.debug_ui_ctx != nil {
			free(g_state.debug_ui_ctx)
		}
	}

	free(g_state)
}

update :: proc() {
	width := f32(rl.GetScreenWidth())
	height := f32(rl.GetScreenHeight())
	delta_time := rl.GetFrameTime()
	g_state.delta_time = delta_time
	g_state.global_time += delta_time
	g_state.fps = int(rl.GetFPS())

	// handle debug UI input (based on microui example)
	when #config(ODIN_DEBUG, false) {
		if g_state.debug_ui_enabled && g_state.debug_ui_ctx != nil {
			ctx := g_state.debug_ui_ctx

			// mouse input
			mouse_pos := rl.GetMousePosition()
			mouse_x, mouse_y := i32(mouse_pos.x), i32(mouse_pos.y)
			mu.input_mouse_move(ctx, mouse_x, mouse_y)

			mouse_wheel := rl.GetMouseWheelMoveV()
			mu.input_scroll(ctx, i32(mouse_wheel.x) * 30, i32(mouse_wheel.y) * -30)

			// mouse buttons
			if rl.IsMouseButtonPressed(.LEFT) do mu.input_mouse_down(ctx, mouse_x, mouse_y, .LEFT)
			if rl.IsMouseButtonReleased(.LEFT) do mu.input_mouse_up(ctx, mouse_x, mouse_y, .LEFT)
			if rl.IsMouseButtonPressed(.RIGHT) do mu.input_mouse_down(ctx, mouse_x, mouse_y, .RIGHT)
			if rl.IsMouseButtonReleased(.RIGHT) do mu.input_mouse_up(ctx, mouse_x, mouse_y, .RIGHT)

			// toggle debug UI with P
			if rl.IsKeyPressed(.P) {
				g_state.debug_ui_enabled = !g_state.debug_ui_enabled
			}

			mu.begin(ctx)
			// render game state debug UI
			render_debug_gui(ctx)
			// render shader manager debug UI
			if g_state.space_shaders.shader_count > 0 {
				shader_manager_debug_ui(&g_state.space_shaders)
			}
			mu.end(ctx)
		} else if rl.IsKeyPressed(.P) && g_state.debug_ui_ctx != nil {
			g_state.debug_ui_enabled = true
		}
	}

	// handle window resizing
	if g_state.resolution.x != width || g_state.resolution.y != height {
		g_state.resolution = rl.Vector2{width, height}

		// resize shader manager if initialized
		if g_state.space_shaders.shader_count > 0 {
			shader_manager_resize(&g_state.space_shaders, i32(width), i32(height))
		}
	}

	// ppdate ship
	update_ship(&g_state.ship, &g_state.camera, delta_time, width, height)

	// ppdate camera
	update_camera(&g_state.camera, g_state.ship.world_position, g_state.ship.velocity, g_state.ship.rotation, delta_time)

	// test key bindings for camera modes (temporary for testing)
	if rl.IsKeyPressed(.F1) {
		set_camera_mode(&g_state.camera, .FOLLOW_SHIP)
	}
	if rl.IsKeyPressed(.F2) {
		// set up a boss fight area (fixed bounds with wrapping)
		bounds := rl.Rectangle{
			x = g_state.ship.world_position.x - 400,
			y = g_state.ship.world_position.y - 300,
			width = 800,
			height = 600,
		}
		set_camera_mode(&g_state.camera, .FIXED_BOUNDS, bounds)
	}

	// update shader manager
	if g_state.space_shaders.shader_count > 0 {
		// set font atlas texture
		shader_manager_set_uniform(&g_state.space_shaders, "font_atlas", g_state.font_atlas_texture)

		// set ship position uniforms before updating
		shader_manager_set_uniform(&g_state.space_shaders, "ship_world_position", g_state.ship.world_position)
		shader_manager_set_uniform(&g_state.space_shaders, "ship_screen_position", g_state.ship.position)
		shader_manager_set_uniform(&g_state.space_shaders, "camera_position", g_state.camera.position)

		// calculate ship direction from rotation
		ship_radians := g_state.ship.rotation * rl.DEG2RAD
		ship_direction := rl.Vector2{
			math.cos(ship_radians),
			math.sin(ship_radians),
		}

		// set new thruster uniforms
		shader_manager_set_uniform(&g_state.space_shaders, "ship_direction", ship_direction)
		shader_manager_set_uniform(&g_state.space_shaders, "ship_velocity", g_state.ship.velocity)
		warp_boost := math.clamp(g_state.ship.ship_speed - 997.75, 0.0, 1000.0) * 1.2
		shader_manager_set_uniform(
			&g_state.space_shaders,
			"ship_speed",
			g_state.ship.ship_speed + warp_boost,
		)

		shader_manager_update(&g_state.space_shaders, delta_time)

		// handle hot reload for shaders (F7 key)
		// TODO: this is currently being done automatically by the build system. Not sure if I'll need this in the future
		if rl.IsKeyPressed(.F7) {
			shader_manager_reload_shaders(&g_state.space_shaders)
		}
	}	// update timing
	g_state.frame += 1

	if rl.IsKeyPressed(.ESCAPE) {
		g_state.run = false
	}
}

draw :: proc() {
	render_game()
}

should_run :: proc() -> bool {
	when ODIN_OS != .JS {
		if rl.WindowShouldClose() {
			return false
		}
	}
	return g_state.run
}

get_state :: proc() -> ^Game_State {
	return g_state
}

set_state :: proc(state: ^Game_State) {
	g_state = state
}

force_reload :: proc() -> bool {
	return rl.IsKeyPressed(.F5)
}

force_restart :: proc() -> bool {
	return rl.IsKeyPressed(.F6)
}
