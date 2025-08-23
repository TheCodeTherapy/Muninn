package gamelogic

import "core:fmt"
import "core:log"
import rl "vendor:raylib"
import mu "vendor:microui"

_ :: log

render_game :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	space_background_texture: rl.Texture2D
	if g_state.space_shaders.shader_count > 0 {
		space_background_texture = shader_manager_render(&g_state.space_shaders)
	}

	ship_texture := draw_ship_to_texture(&g_state.ship)

	// Safety check: ensure render target is valid
	if g_state.final_render_target.id == 0 {
		// Fallback: render directly to screen if render target is not initialized
		if g_state.space_shaders.shader_count > 0 {
			rl.DrawTextureRec(
				space_background_texture,
				rl.Rectangle{
					0, 0,
					f32(space_background_texture.width),
					-f32(space_background_texture.height),
				},
				{0, 0},
				rl.WHITE,
			)
		}
		draw_ship(&g_state.ship)
		return
	}

	rl.BeginTextureMode(g_state.final_render_target)
	rl.ClearBackground(rl.BLACK)

	if g_state.space_shaders.shader_count > 0 {
		rl.DrawTextureRec(
			space_background_texture,
			rl.Rectangle{
				0, 0,
				f32(space_background_texture.width),
				-f32(space_background_texture.height), // negative height to flip
			},
			{0, 0},
			rl.WHITE,
		)
	}

	rl.DrawTextureRec(
		ship_texture,
		rl.Rectangle{ 0, 0, f32(ship_texture.width), -f32(ship_texture.height) },
		{0, 0},
		rl.WHITE,
	)

	// draw camera debug visualization if debug UI is enabled
	when #config(ODIN_DEBUG, false) {
		if g_state.debug_ui_enabled {
			debug_draw_camera_lookahead(g_state.ship.position, g_state.ship.velocity, g_state.ship.rotation)
		}
	}

	rl.EndTextureMode()

	// Apply bloom if enabled, otherwise draw final result directly
	if g_state.bloom_enabled && g_state.bloom_effect.initialized && g_state.bloom_composite_target.id != 0 {
		bloom_texture := bloom_effect_apply(&g_state.bloom_effect, g_state.final_render_target.texture)
		bloom_effect_composite(&g_state.bloom_effect, g_state.final_render_target.texture, bloom_texture, &g_state.bloom_composite_target)
		rl.DrawTextureRec(
			g_state.bloom_composite_target.texture,
			rl.Rectangle{
				0, 0,
				f32(g_state.bloom_composite_target.texture.width),
				-f32(g_state.bloom_composite_target.texture.height), // negative height to flip
			},
			{0, 0},
			rl.WHITE,
		)
	} else {
		// Draw final result to screen without bloom
		rl.DrawTextureRec(
			g_state.final_render_target.texture,
			rl.Rectangle{
				0, 0,
				f32(g_state.final_render_target.texture.width),
				-f32(g_state.final_render_target.texture.height), // negative height to flip
			},
			{0, 0},
			rl.WHITE,
		)
	}

	// render debug UI on top (always after everything)
	when #config(ODIN_DEBUG, false) {
		if g_state.debug_ui_enabled && g_state.debug_ui_ctx != nil {
			render_microui(g_state.debug_ui_ctx)
		}
	}

	rl.EndDrawing()
}

// game state debug UI
render_debug_gui :: proc(ctx: ^mu.Context) {
	// game State window
	if mu.begin_window(ctx, "Game State", {10, 10, 300, 260}) {
		mu.layout_row(ctx, {80, -1}, 0)

		// FPS
		mu.label(ctx, "FPS:")
		mu.label(ctx, fmt.tprintf("%d", g_state.fps))

		// dt
		mu.label(ctx, "Delta time:")
		mu.label(ctx, fmt.tprintf("%.5f", g_state.delta_time))

		// frame
		mu.label(ctx, "Frame:")
		mu.label(ctx, fmt.tprintf("%d", g_state.frame))

		// ship screen pos
		mu.label(ctx, "Screen X:")
		mu.label(ctx, fmt.tprintf("%.1f", g_state.ship.position.x))

		mu.label(ctx, "Screen Y:")
		mu.label(ctx, fmt.tprintf("%.1f", g_state.ship.position.y))

		// ship world pos
		mu.label(ctx, "World X:")
		mu.label(ctx, fmt.tprintf("%.1f", g_state.ship.world_position.x))

		mu.label(ctx, "World Y:")
		mu.label(ctx, fmt.tprintf("%.1f", g_state.ship.world_position.y))

		// ship vel
		mu.label(ctx, "Velocity X:")
		mu.label(ctx, fmt.tprintf("%.2f", g_state.ship.velocity.x))

		mu.label(ctx, "Velocity Y:")
		mu.label(ctx, fmt.tprintf("%.2f", g_state.ship.velocity.y))

		// ship rot
		mu.label(ctx, "Rotation:")
		mu.label(ctx, fmt.tprintf("%.1f°", g_state.ship.rotation))

		// cam info
		mu.label(ctx, "Camera Mode:")
		camera_mode_str := ""
		switch g_state.camera.mode {
		case .FOLLOW_SHIP:    camera_mode_str = "Follow Ship"
		case .FIXED_BOUNDS:   camera_mode_str = "Fixed Bounds"
		case .FREE_EXPLORE:   camera_mode_str = "Free Explore"
		}
		mu.label(ctx, camera_mode_str)

		mu.label(ctx, "Wrapping:")
		mu.label(ctx, g_state.camera.enable_wrapping ? "Enabled" : "Disabled")

		mu.end_window(ctx)
	}

	// Bloom controls window
	if mu.begin_window(ctx, "Bloom Effect", {320, 10, 250, 200}) {
		mu.layout_row(ctx, {-1}, 0)

		// Bloom toggle
		prev_enabled := g_state.bloom_enabled
		mu.checkbox(ctx, "Enabled", &g_state.bloom_enabled)

		// Initialize bloom if enabling for the first time
		if g_state.bloom_enabled && !prev_enabled && !g_state.bloom_effect.initialized {
			bloom_initialized := bloom_effect_init_default(&g_state.bloom_effect, i32(g_state.resolution.x), i32(g_state.resolution.y), file_reader_func)
			if !bloom_initialized {
				g_state.bloom_enabled = false // Turn it back off if initialization failed
			}
		}

		// Status
		mu.layout_row(ctx, {-1}, 0)
		status_text := g_state.bloom_effect.initialized ? "Status: Initialized" : "Status: Not Initialized"
		mu.label(ctx, status_text)

		mu.layout_row(ctx, {80, -1}, 0)

		// Threshold slider
		mu.label(ctx, "Threshold:")
		mu.slider(ctx, &g_state.bloom_effect.config.threshold, 0.0, 1.0)

		// Intensity slider
		mu.label(ctx, "Intensity:")
		mu.slider(ctx, &g_state.bloom_effect.config.intensity, 0.0, 1.0)

		// Strength slider
		mu.label(ctx, "Strength:")
		mu.slider(ctx, &g_state.bloom_effect.config.strength, 0.0, 3.0)

		// Exposure slider
		mu.label(ctx, "Exposure:")
		mu.slider(ctx, &g_state.bloom_effect.config.exposure, 0.1, 5.0)

		// Radius slider
		mu.label(ctx, "Radius:")
		mu.slider(ctx, &g_state.bloom_effect.config.radius, 0.1, 3.0)

		mu.end_window(ctx)
	}
}

// MicroUI rendering function
render_microui :: proc(ctx: ^mu.Context) {
	render_texture :: proc(dst: ^rl.Rectangle, src: mu.Rect, color: rl.Color) {
		dst.width = f32(src.w)
		dst.height = f32(src.h)

		rl.DrawTextureRec(
			texture  = g_state.debug_atlas_texture.texture,
			source   = {f32(src.x), f32(src.y), f32(src.w), f32(src.h)},
			position = {dst.x, dst.y},
			tint     = color,
		)
	}

	to_rl_color :: proc(in_color: mu.Color) -> rl.Color {
		return {in_color.r, in_color.g, in_color.b, in_color.a}
	}

	command_backing: ^mu.Command
	for variant in mu.next_command_iterator(ctx, &command_backing) {
		switch cmd in variant {
		case ^mu.Command_Text:
			dst := rl.Rectangle{f32(cmd.pos.x), f32(cmd.pos.y), 0, 0}
			for ch in cmd.str {
				if ch&0xc0 != 0x80 {
					r := min(int(ch), 127)
					src := mu.default_atlas[mu.DEFAULT_ATLAS_FONT + r]
					render_texture(&dst, src, to_rl_color(cmd.color))
					dst.x += dst.width
				}
			}

		case ^mu.Command_Rect:
			rl.DrawRectangle(
				i32(cmd.rect.x), i32(cmd.rect.y),
				i32(cmd.rect.w), i32(cmd.rect.h),
				to_rl_color(cmd.color),
			)

		case ^mu.Command_Icon:
			src := mu.default_atlas[cmd.id]
			x := cmd.rect.x + (cmd.rect.w - src.w)/2
			y := cmd.rect.y + (cmd.rect.h - src.h)/2
			dst := rl.Rectangle{f32(x), f32(y), 0, 0}
			render_texture(&dst, src, to_rl_color(cmd.color))

		case ^mu.Command_Clip:
			rl.BeginScissorMode(
				i32(cmd.rect.x), i32(cmd.rect.y),
				i32(cmd.rect.w), i32(cmd.rect.h),
			)

		case ^mu.Command_Jump:
			unreachable()
		}
	}
	rl.EndScissorMode()
}
