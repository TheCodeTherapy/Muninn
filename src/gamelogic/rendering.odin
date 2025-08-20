package gamelogic

import "core:fmt"
import rl "vendor:raylib"
import mu "vendor:microui"

render_game :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	// render space using shader manager (multi-pass rendering)
	if g_state.space_shaders.shader_count > 0 {
		final_texture := shader_manager_render(&g_state.space_shaders)
		// draw the final texture to screen
		rl.DrawTextureRec(
			final_texture,
			rl.Rectangle{
				0, 0,
				f32(final_texture.width),
				-f32(final_texture.height), // negative height to flip
			},
			{0, 0},
			rl.WHITE,
		)
	}

	// draw the ship on top of the background
	draw_ship(&g_state.ship)

	// draw camera debug visualization if debug UI is enabled
	when #config(ODIN_DEBUG, false) {
		if g_state.debug_ui_enabled {
			debug_draw_camera_lookahead(g_state.ship.position, g_state.ship.velocity, g_state.ship.rotation)
		}
	}

	// render debug UI on top
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
