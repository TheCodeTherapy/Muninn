package gamelogic

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import mu "vendor:microui"

// Feature flag: Use WebGL2 context and shaders (false = WebGL1, true = WebGL2)
// WebGL2 has known vertex attribute issues with Raylib (GitHub issue #4330)
// TODO: I should figure this shit out.
// Note: For now controlled via -define:USE_WEBGL2=true/false compiler flag

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

	// post-processing effects
	bloom_effect:     Bloom_Effect, // Global bloom post-processing
	bloom_enabled:    bool, // Toggle for bloom effect
	final_render_target: rl.RenderTexture2D, // Final composited output
	bloom_composite_target: rl.RenderTexture2D, // Dedicated target for bloom compositing
	ship_render_target: rl.RenderTexture2D, // Ship and projectiles with transparent background

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

	when #config(USE_WEBGL2, false) {
		space_vertex_path = "shaders/v300es/default.vert"
		space_shader_0_fragment_path = "shaders/v300es/space-shader-0.frag"
		space_shader_1_fragment_path = "shaders/v300es/space-shader-1.frag"
		space_shader_2_fragment_path = "shaders/v300es/space-shader-2.frag"
		space_shader_3_fragment_path = "shaders/v300es/space-shader-3.frag"
	}

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

	bloom_effect: Bloom_Effect
	bloom_initialized := bloom_effect_init_default(&bloom_effect, i32(width), i32(height), file_reader_func)
	if !bloom_initialized {
		fmt.printf("Failed to initialize bloom effect, continuing without bloom")
	}

	final_render_target := LoadRT_WithFallback(i32(width), i32(height), .UNCOMPRESSED_R32G32B32A32)
	bloom_composite_target := LoadRT_WithFallback(i32(width), i32(height), .UNCOMPRESSED_R32G32B32A32)
	ship_render_target := LoadRT_WithFallback(i32(width), i32(height), .UNCOMPRESSED_R32G32B32A32)

	g_state^ = Game_State {
		// display and timing
		resolution = rl.Vector2{width, height},
		fps = 0,
		delta_time = 0,
		global_time = 0,
		frame = 1,

		// game objects/systems
		ship = init_ship(width, height),
		camera = init_camera(),
		space_shaders = shader_manager_initialized ? space_shaders : {},

		// rendering and post-processing
		bloom_effect = bloom_initialized ? bloom_effect : {},
		bloom_enabled = true, // Start with bloom enabled
		final_render_target = final_render_target,
		bloom_composite_target = bloom_composite_target,
		ship_render_target = ship_render_target,
		font_atlas_texture = font_atlas_texture,

		// debug UI
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

	// clean up bloom effect
	if g_state.bloom_effect.initialized {
		bloom_effect_destroy(&g_state.bloom_effect)
	}

	// clean up final render target
	if g_state.final_render_target.id != 0 {
		rl.UnloadRenderTexture(g_state.final_render_target)
	}

	// clean up bloom composite target
	if g_state.bloom_composite_target.id != 0 {
		rl.UnloadRenderTexture(g_state.bloom_composite_target)
	}

	// clean up ship render target
	if g_state.ship_render_target.id != 0 {
		rl.UnloadRenderTexture(g_state.ship_render_target)
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
				when #config(ODIN_DEBUG, false) {
					shader_debug_render_ui(&g_state.space_shaders, g_state.debug_ui_ctx)
				}
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

		// resize bloom effect if initialized
		if g_state.bloom_effect.initialized {
			bloom_effect_resize(&g_state.bloom_effect, i32(width), i32(height))
		}

		// resize final render target
		if g_state.final_render_target.id != 0 {
			rl.UnloadRenderTexture(g_state.final_render_target)
			g_state.final_render_target = rl.LoadRenderTexture(i32(width), i32(height))
		}

		// resize bloom composite target
		if g_state.bloom_composite_target.id != 0 {
			rl.UnloadRenderTexture(g_state.bloom_composite_target)
			g_state.bloom_composite_target = rl.LoadRenderTexture(i32(width), i32(height))
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

		// update debug system (check for console logging triggers)
		when #config(ODIN_DEBUG, false) {
			shader_debug_update(&g_state.space_shaders)
		}

		// handle hot reload for shaders (F7 key)
		// TODO: this is currently being done automatically by the build system. Not sure if I'll need this in the future
		if rl.IsKeyPressed(.F7) {
			shader_manager_reload_shaders(&g_state.space_shaders)
		}
	}	// test key bindings
	if rl.IsKeyPressed(.B) {
		// Initialize bloom on first press if not initialized
		if !g_state.bloom_effect.initialized {
			bloom_initialized := bloom_effect_init_default(&g_state.bloom_effect, i32(width), i32(height), file_reader_func)
			if bloom_initialized {
				fmt.printf("Bloom effect initialized via B key")
			} else {
				fmt.printf("Failed to initialize bloom effect")
			}
		}
		// Toggle bloom
		g_state.bloom_enabled = !g_state.bloom_enabled
		fmt.printf("Bloom %s", g_state.bloom_enabled ? "enabled" : "disabled")
	}

	// update timing
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

// Hot reload render targets (called during hot reload)
hot_reload_render_targets :: proc() {
	width := f32(rl.GetScreenWidth())
	height := f32(rl.GetScreenHeight())

	// Recreate render targets if they don't exist or have wrong size
	if g_state.final_render_target.id == 0 ||
	   g_state.final_render_target.texture.width != i32(width) ||
	   g_state.final_render_target.texture.height != i32(height) {

		// Clean up old render target if it exists
		if g_state.final_render_target.id != 0 {
			rl.UnloadRenderTexture(g_state.final_render_target)
		}

		g_state.final_render_target = LoadRT_WithFallback(i32(width), i32(height), .UNCOMPRESSED_R32G32B32A32)
		fmt.printf("Hot reload: Recreated final_render_target (%dx%d)\n", i32(width), i32(height))
	}

	if g_state.bloom_composite_target.id == 0 ||
	   g_state.bloom_composite_target.texture.width != i32(width) ||
	   g_state.bloom_composite_target.texture.height != i32(height) {

		if g_state.bloom_composite_target.id != 0 {
			rl.UnloadRenderTexture(g_state.bloom_composite_target)
		}

		g_state.bloom_composite_target = LoadRT_WithFallback(i32(width), i32(height), .UNCOMPRESSED_R32G32B32A32)
		fmt.printf("Hot reload: Recreated bloom_composite_target (%dx%d)\n", i32(width), i32(height))
	}

	if g_state.ship_render_target.id == 0 ||
	   g_state.ship_render_target.texture.width != i32(width) ||
	   g_state.ship_render_target.texture.height != i32(height) {

		if g_state.ship_render_target.id != 0 {
			rl.UnloadRenderTexture(g_state.ship_render_target)
		}

		g_state.ship_render_target = LoadRT_WithFallback(i32(width), i32(height), .UNCOMPRESSED_R32G32B32A32)
		fmt.printf("Hot reload: Recreated ship_render_target (%dx%d)\n", i32(width), i32(height))
	}
}
