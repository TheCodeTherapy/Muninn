package gamelogic

import "core:fmt"
import rl "vendor:raylib"
import mu "vendor:microui"

debug :: #config(ODIN_DEBUG, false)

// Feature flag: Use WebGL2 context and shaders (false = WebGL1, true = WebGL2)
// WebGL2 has known vertex attribute issues with Raylib + Emscripten (GitHub issue #4330)
// TODO: I should figure this shit out.
// Note: For now controlled via -define:USE_WEBGL2=true/false compiler flag

file_reader_func: proc(filename: string, allocator := context.allocator, loc := #caller_location) -> (data: []byte, success: bool)

set_file_reader :: proc(reader: proc(filename: string, allocator := context.allocator, loc := #caller_location) -> (data: []byte, success: bool)) {
  file_reader_func = reader
}

File_Reader :: proc(filename: string, allocator := context.allocator, loc := #caller_location) -> (data: []byte, success: bool)

MAX_DEBUG_PANELS :: 16
MAX_RENDER_TARGETS :: 0

Debug_Panel_Proc :: proc(ctx: ^mu.Context)

Debug_Panel :: struct {
	name:           string,
	render_proc:    Debug_Panel_Proc,
	enabled:        bool,
	active:         bool, // whether this slot is used
	start_unfolded: bool, // whether this panel starts expanded
}

Debug_System :: struct {
	panels:      [MAX_DEBUG_PANELS]Debug_Panel, // fixed size arrays
	panel_count: int,
	initialized: bool,
	enabled:     bool,
}

Game_State :: struct {
	// display and timing
	resolution:                rl.Vector2,             // viewport resolution
	fps:                       int,                    // frames per second
	delta_time:                f32,                    // time since last frame
	global_time:               f32,                    // total time since start
	frame:                     int,                    // frame count

	// game objects/systems
	ship:                      Ship,                   // player ship
	ship_trail:                Ship_Trail,             // ship trail system
	camera:                    Camera_State,           // camera state
	space:                     Space_System,           // space background system

	// post-processing effects
	bloom_effect:              Bloom_Effect,           // Global bloom post-processing
	space_bloom_effect:        Bloom_Effect,           // Space bloom post-processing
	trail_bloom_effect:        Bloom_Effect,           // Trail bloom post-processing
	ship_bloom_effect:         Bloom_Effect,           // Ship bloom post-processing

	bcs_effect:                BCS_Effect,             // Background BCS post-processing
	ship_render_target:        rl.RenderTexture2D,     // ship and projectiles with transparent background
	trail_render_target:       rl.RenderTexture2D,     // ship trail with transparent background
	final_render_target:       rl.RenderTexture2D,     // Final composited output

	// render targets pool and post-fx settings
	render_targets:            [MAX_RENDER_TARGETS]rl.RenderTexture2D, // Render target pool
	current_rt_index:          int,                    // Current render target index
	post_fx:                   Post_FX_Settings,       // Post-processing settings

	// postfx instances
	postfx_instances:          [5]PostFX_Effect_Instance,

	// textures
	font_atlas_texture:        rl.Texture2D,           // font atlas texture for shaders

	// debug UI (only in debug builds)
	debug_ui_ctx:              ^mu.Context,            // MicroUI context
	debug_ui_enabled:          bool,                   // Debug UI toggle
	debug_atlas_texture:       rl.RenderTexture2D,     // Font atlas for debug UI
	debug_system:              Debug_System,           // Debug system state

	// game state
	run:                       bool,                   // gotta keep running
}

g_state: ^Game_State

init :: proc() {
	g_state = new(Game_State)

	width := f32(rl.GetScreenWidth())
	height := f32(rl.GetScreenHeight())

	font_atlas_texture := load_font_atlas_texture()
	load_assets()

	// initialize space system
	space_system: Space_System
	space_initialized := space_system_init(&space_system, width, height, file_reader_func)

	bloom_effect: Bloom_Effect
	bloom_initialized := bloom_effect_init_default(&bloom_effect, i32(width), i32(height), file_reader_func)
	if !bloom_initialized {
		fmt.printf("Failed to initialize bloom effect, continuing without bloom")
	}

	space_bloom_effect: Bloom_Effect
	space_bloom_initialized := bloom_effect_init_default(&space_bloom_effect, i32(width), i32(height), file_reader_func)
	if !space_bloom_initialized {
		fmt.printf("Failed to initialize space bloom effect")
	}

	trail_bloom_effect: Bloom_Effect
	trail_bloom_initialized := bloom_effect_init_default(&trail_bloom_effect, i32(width), i32(height), file_reader_func)
	if !trail_bloom_initialized {
		fmt.printf("Failed to initialize trail bloom effect")
	}

	ship_bloom_effect: Bloom_Effect
	ship_bloom_initialized := bloom_effect_init_default(&ship_bloom_effect, i32(width), i32(height), file_reader_func)
	if !ship_bloom_initialized {
		fmt.printf("Failed to initialize ship bloom effect")
	}

	bcs_effect: BCS_Effect
	bcs_initialized := bcs_effect_init_default(&bcs_effect, i32(width), i32(height), file_reader_func)
	if !bcs_initialized {
		fmt.printf("Failed to initialize BCS effect, continuing without BCS")
	}

	final_render_target := create_render_target(i32(width), i32(height), .UNCOMPRESSED_R32G32B32A32)
	ship_render_target := create_render_target(i32(width), i32(height), .UNCOMPRESSED_R32G32B32A32)
	trail_render_target := create_render_target(i32(width), i32(height), .UNCOMPRESSED_R32G32B32A32)

	ship_trail: Ship_Trail
	init_ship_trail(&ship_trail, SHIP_SCALE * 0.25) // Use quarter of ship scale as radius

	rt_width := i32(rl.GetScreenWidth())
	rt_height := i32(rl.GetScreenHeight())

	render_targets: [MAX_RENDER_TARGETS]rl.RenderTexture2D
	for &target in render_targets {
		target = create_render_target(rt_width, rt_height, rl.PixelFormat.UNCOMPRESSED_R32G32B32A32)
	}

	post_fx_settings := DEFAULT_POST_FX_SETTINGS

	g_state^ = Game_State {
		// display and timing
		resolution = rl.Vector2{width, height},
		fps = 0,
		delta_time = 0,
		global_time = 0,
		frame = 1,

		// game objects/systems
		ship = init_ship(width, height),
		ship_trail = ship_trail,
		camera = init_camera(),
		space = space_initialized ? space_system : {},

		// rendering and post-processing
		bloom_effect = bloom_initialized ? bloom_effect : {},
		space_bloom_effect = space_bloom_initialized ? space_bloom_effect : {},
		trail_bloom_effect = trail_bloom_initialized ? trail_bloom_effect : {},
		ship_bloom_effect = ship_bloom_initialized ? ship_bloom_effect : {},

		bcs_effect = bcs_initialized ? bcs_effect : {},

		final_render_target = final_render_target,
		ship_render_target = ship_render_target,
		trail_render_target = trail_render_target,
		font_atlas_texture = font_atlas_texture,

		render_targets = render_targets,
		current_rt_index = 0,
		post_fx = post_fx_settings,
		postfx_instances = {},

		debug_ui_ctx = nil,
		debug_ui_enabled = false,
		debug_atlas_texture = {},
		debug_system = {},

		run = true,
	}

	// initialize postfx instances
	g_state.postfx_instances = {
		{"BCS", .BCS, nil, &g_state.bcs_effect, nil, &g_state.post_fx.space_bcs, &g_state.post_fx.space_bcs.enabled},
		{"Space Bloom", .BLOOM_SPACE, &g_state.space_bloom_effect, nil, &g_state.post_fx.space_bloom, nil, &g_state.post_fx.space_bloom.enabled},
		{"Trail Bloom", .BLOOM_TRAIL, &g_state.trail_bloom_effect, nil, &g_state.post_fx.trail_bloom, nil, &g_state.post_fx.trail_bloom.enabled},
		{"Ship Bloom", .BLOOM_SHIP, &g_state.ship_bloom_effect, nil, &g_state.post_fx.ship_bloom, nil, &g_state.post_fx.ship_bloom.enabled},
		{"Final Bloom", .BLOOM_FINAL, &g_state.bloom_effect, nil, &g_state.post_fx.composite_bloom, nil, &g_state.post_fx.composite_bloom.enabled},
	}

	// initialize camera position to match ship's starting position
	g_state.camera.position = g_state.ship.world_position
	g_state.camera.target = g_state.ship.world_position

	// initialize ship trail with ship's starting position
	reset_ship_trail(&g_state.ship_trail, g_state.ship.world_position, g_state.global_time)
}

shutdown :: proc() {
	cleanup_ship(&g_state.ship) // clean up ship resources
	destroy_ship_trail(&g_state.ship_trail) // clean up ship trail
	space_system_destroy(&g_state.space) // clean up space system

	// clean up bloom effects
	if g_state.bloom_effect.initialized {
		bloom_effect_destroy(&g_state.bloom_effect)
	}

	// clean up bloom effects
	if g_state.space_bloom_effect.initialized {
		bloom_effect_destroy(&g_state.space_bloom_effect)
	}

	// clean up bloom effects
	if g_state.trail_bloom_effect.initialized {
		bloom_effect_destroy(&g_state.trail_bloom_effect)
	}

	// clean up bloom effects
	if g_state.ship_bloom_effect.initialized {
		bloom_effect_destroy(&g_state.ship_bloom_effect)
	}

	// clean up BCS effect
	if g_state.bcs_effect.initialized {
		bcs_effect_destroy(&g_state.bcs_effect)
	}

	// clean up final render target
	if g_state.final_render_target.id != 0 {
		rl.UnloadRenderTexture(g_state.final_render_target)
	}

	// clean up ship render target
	if g_state.ship_render_target.id != 0 {
		rl.UnloadRenderTexture(g_state.ship_render_target)
	}

	// clean up trail render target
	if g_state.trail_render_target.id != 0 {
		rl.UnloadRenderTexture(g_state.trail_render_target)
	}

	// clean up render target pool
	for &target in g_state.render_targets {
		if target.id != 0 {
			rl.UnloadRenderTexture(target)
		}
	}

	// clean up font atlas texture
	if g_state.font_atlas_texture.id != 0 {
		rl.UnloadTexture(g_state.font_atlas_texture)
	}

	// clean up debug GUI
	destroy_debug_gui()

	free(g_state)
}

update :: proc() {
	width := f32(rl.GetScreenWidth())
	height := f32(rl.GetScreenHeight())
	delta_time := rl.GetFrameTime()
	g_state.delta_time = delta_time
	g_state.global_time += delta_time
	g_state.fps = int(rl.GetFPS())

	// handle window resizing
	if g_state.resolution.x != width || g_state.resolution.y != height {
		g_state.resolution = rl.Vector2{width, height}

		// resize space system
		space_system_resize(&g_state.space, i32(width), i32(height))

		// resize bloom effects if initialized
		if g_state.bloom_effect.initialized {
			bloom_effect_resize(&g_state.bloom_effect, i32(width), i32(height))
		}
		if g_state.space_bloom_effect.initialized {
			bloom_effect_resize(&g_state.space_bloom_effect, i32(width), i32(height))
		}
		if g_state.trail_bloom_effect.initialized {
			bloom_effect_resize(&g_state.trail_bloom_effect, i32(width), i32(height))
		}
		if g_state.ship_bloom_effect.initialized {
			bloom_effect_resize(&g_state.ship_bloom_effect, i32(width), i32(height))
		}

		// resize BCS effect if initialized
		if g_state.bcs_effect.initialized {
			bcs_effect_resize(&g_state.bcs_effect, i32(width), i32(height))
		}

		// resize final render target
		if g_state.final_render_target.id != 0 {
			rl.UnloadRenderTexture(g_state.final_render_target)
			g_state.final_render_target = create_render_target(i32(width), i32(height), rl.PixelFormat.UNCOMPRESSED_R32G32B32A32)
		}

		// resize ship render target
		if g_state.ship_render_target.id != 0 {
			rl.UnloadRenderTexture(g_state.ship_render_target)
			g_state.ship_render_target = create_render_target(i32(width), i32(height), rl.PixelFormat.UNCOMPRESSED_R32G32B32A32)
		}

		// resize trail render target
		if g_state.trail_render_target.id != 0 {
			rl.UnloadRenderTexture(g_state.trail_render_target)
			g_state.trail_render_target = create_render_target(i32(width), i32(height), rl.PixelFormat.UNCOMPRESSED_R32G32B32A32)
		}

		// resize render target pool
		for &target in g_state.render_targets {
			if target.id != 0 {
				rl.UnloadRenderTexture(target)
				target = create_render_target(i32(width), i32(height), rl.PixelFormat.UNCOMPRESSED_R32G32B32A32)
			}
		}
		g_state.current_rt_index = 0
	}

	// update ship
	update_ship(&g_state.ship, &g_state.camera, delta_time, width, height)

	// update ship trail - distance-based sampling in WORLD SPACE with thruster offset!
	add_trail_position(&g_state.ship_trail, g_state.ship.world_position, g_state.ship.rotation, g_state.ship.ship_speed, MAX_SHIP_SPEED, g_state.global_time)

	// update camera
	update_camera(&g_state.camera, g_state.ship.world_position, g_state.ship.velocity, g_state.ship.rotation, delta_time)

	// test key bindings for camera modes (temporary for testing)
	if rl.IsKeyPressed(.F1) {
		set_camera_mode(&g_state.camera, .FOLLOW_SHIP)
	}
	if rl.IsKeyPressed(.F2) {
		// set up a boss fight area (screen wrap mode)
		bounds := rl.Rectangle{
			x = g_state.ship.world_position.x - 400,
			y = g_state.ship.world_position.y - 300,
			width = 800,
			height = 600,
		}
		set_camera_mode(&g_state.camera, .SCREEN_WRAP, bounds)
	}

	// update shader manager
	space_system_update(&g_state.space, g_state)

	// handle hot reload for shaders (F7 key)
	// TODO: this is currently being done automatically by the build system
	// Not sure if I'll need this in the future for something else
	if rl.IsKeyPressed(.F7) {
		space_system_reload_shaders(&g_state.space)
	}

	if rl.IsKeyPressed(.B) {
		// initialize bloom on first press if not initialized
		if !g_state.bloom_effect.initialized {
			bloom_initialized := bloom_effect_init_default(&g_state.bloom_effect, i32(width), i32(height), file_reader_func)
			if bloom_initialized {
				fmt.printf("Bloom effect initialized via B key")
			} else {
				fmt.printf("Failed to initialize bloom effect")
			}
		}

		// toggle all bloom effects
		new_state := !g_state.post_fx.space_bloom.enabled
		g_state.post_fx.space_bloom.enabled = new_state
		g_state.post_fx.trail_bloom.enabled = new_state
		g_state.post_fx.ship_bloom.enabled = new_state
		g_state.post_fx.composite_bloom.enabled = new_state
		fmt.printf("Bloom %s", new_state ? "enabled" : "disabled")
	}

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
	width := i32(rl.GetScreenWidth())
	height := i32(rl.GetScreenHeight())

	// Recreate render target pool
	for &target in g_state.render_targets {
		if target.id == 0 || target.texture.width != width || target.texture.height != height {
			if target.id != 0 {
				rl.UnloadRenderTexture(target)
			}
			target = create_render_target(width, height, rl.PixelFormat.UNCOMPRESSED_R32G32B32A32)
		}
	}

	g_state.current_rt_index = 0

	// recreate render targets if they don't exist or have wrong size
	if g_state.final_render_target.id == 0 ||
	   g_state.final_render_target.texture.width != width ||
	   g_state.final_render_target.texture.height != height {

		// clean up old render target if it exists
		if g_state.final_render_target.id != 0 {
			rl.UnloadRenderTexture(g_state.final_render_target)
		}

		g_state.final_render_target = create_render_target(width, height, rl.PixelFormat.UNCOMPRESSED_R32G32B32A32)
		fmt.printf("Hot reload: Recreated final_render_target (%dx%d)\n", width, height)
	}

	if g_state.ship_render_target.id == 0 ||
	   g_state.ship_render_target.texture.width != width ||
	   g_state.ship_render_target.texture.height != height {

		if g_state.ship_render_target.id != 0 {
			rl.UnloadRenderTexture(g_state.ship_render_target)
		}

		g_state.ship_render_target = create_render_target(width, height, rl.PixelFormat.UNCOMPRESSED_R32G32B32A32)
		fmt.printf("Hot reload: Recreated ship_render_target (%dx%d)\n", width, height)
	}

	if g_state.trail_render_target.id == 0 ||
	   g_state.trail_render_target.texture.width != width ||
	   g_state.trail_render_target.texture.height != height {

		if g_state.trail_render_target.id != 0 {
			rl.UnloadRenderTexture(g_state.trail_render_target)
		}

		g_state.trail_render_target = create_render_target(width, height, rl.PixelFormat.UNCOMPRESSED_R32G32B32A32)
		fmt.printf("Hot reload: Recreated trail_render_target (%dx%d)\n", width, height)
	}
}
