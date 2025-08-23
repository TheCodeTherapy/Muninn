package gamelogic

import "core:log"
import "core:time"
import rl "vendor:raylib"
import mu "vendor:microui"


_ :: log

render_game :: proc() {
	total_start := time.now()

	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	// step 1: render the space background into a texture
	step1_start := time.now()
	if g_state.space_shaders.shader_count > 0 {
		g_state.space_background_texture = shader_manager_render(&g_state.space_shaders)

		// apply BCS effect to space background if enabled
		if g_state.bcs_enabled && g_state.bcs_effect.initialized && g_state.bcs_target.id != 0 {
			bcs_effect_apply(&g_state.bcs_effect, g_state.space_background_texture, &g_state.bcs_target)
		}
	}
	g_state.render_timing.step1_space_background = f32(time.duration_milliseconds(time.since(step1_start)))

	// step 2: render the ship and related objects into a texture
	step2_start := time.now()
	ship_texture := draw_ship_to_texture(&g_state.ship)
	g_state.render_timing.step2_ship_render = f32(time.duration_milliseconds(time.since(step2_start)))

	// safety check: ensure render target is valid
	if g_state.final_render_target.id == 0 {
		// fallback: render directly to screen if render target is not initialized
		if g_state.space_shaders.shader_count > 0 {
			// use BCS target if BCS is enabled, otherwise use original space background
			texture_to_draw: rl.Texture2D
			if g_state.bcs_enabled && g_state.bcs_effect.initialized && g_state.bcs_target.id != 0 {
				texture_to_draw = g_state.bcs_target.texture
			} else {
				texture_to_draw = g_state.space_background_texture
			}

			rl.DrawTextureRec(
				texture_to_draw,
				rl.Rectangle{
					0, 0,
					f32(texture_to_draw.width),
					-f32(texture_to_draw.height),
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

	// step 3: draw the space background texture to the final render target
	step3_start := time.now()
	if g_state.space_shaders.shader_count > 0 {
		// Use BCS target if BCS is enabled, otherwise use original space background
		texture_to_draw: rl.Texture2D
		if g_state.bcs_enabled && g_state.bcs_effect.initialized && g_state.bcs_target.id != 0 {
			texture_to_draw = g_state.bcs_target.texture
		} else {
			texture_to_draw = g_state.space_background_texture
		}

		rl.DrawTextureRec(
			texture_to_draw,
			rl.Rectangle{
				0, 0,
				f32(texture_to_draw.width),
				-f32(texture_to_draw.height), // negative height to flip
			},
			{0, 0},
			rl.WHITE,
		)
	}
	g_state.render_timing.step3_background_draw = f32(time.duration_milliseconds(time.since(step3_start)))

	// step 4: draw the ship texture to the final render target
	step4_start := time.now()
	rl.DrawTextureRec(
		ship_texture,
		rl.Rectangle{ 0, 0, f32(ship_texture.width), -f32(ship_texture.height) },
		{0, 0},
		rl.WHITE,
	)
	g_state.render_timing.step4_ship_draw = f32(time.duration_milliseconds(time.since(step4_start)))

	// draw camera debug visualization if debug UI is enabled
	when #config(ODIN_DEBUG, false) {
		if g_state.debug_ui_enabled {
			debug_draw_camera_lookahead(g_state.ship.position, g_state.ship.velocity, g_state.ship.rotation)
		}
	}

	rl.EndTextureMode()

	// step 5: apply bloom if enabled
	step5_start := time.now()
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
		// alternative step 5: draw final result to screen without bloom
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
	g_state.render_timing.step5_bloom_or_final = f32(time.duration_milliseconds(time.since(step5_start)))

	// step 6: render debug UI on top (always after everything)
	step6_start := time.now()
	when #config(ODIN_DEBUG, false) {
		if g_state.debug_ui_enabled && g_state.debug_ui_ctx != nil {
			render_microui(g_state.debug_ui_ctx)
		}
	}
	g_state.render_timing.step6_debug_ui = f32(time.duration_milliseconds(time.since(step6_start)))

	// calculate total render time
	g_state.render_timing.total_render_time = f32(time.duration_milliseconds(time.since(total_start)))

	// update averaging (circular buffer)
	timing := &g_state.render_timing
	timing.total_time_history[timing.history_index] = timing.total_render_time
	timing.history_index = (timing.history_index + 1) % 1000
	if timing.history_count < 1000 {
		timing.history_count += 1
	}

	// calculate average
	sum: f32 = 0
	for i in 0..<timing.history_count {
		sum += timing.total_time_history[i]
	}
	timing.average_render_time = sum / f32(timing.history_count)

	when #config(ODIN_DEBUG, true) && ODIN_OS == .JS {
		if !g_state.debug_ui_enabled {
			rl.DrawText("debug build: Press <p> to open debug UI", 13, 13, 20, {210, 210, 210, 210})
		}
	}

	rl.EndDrawing()
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
