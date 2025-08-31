package gamelogic

import "core:fmt"
import mu "vendor:microui"
import rl "vendor:raylib"

_ :: fmt
_ :: rl

init_debug_gui :: proc() {
	when #config(ODIN_DEBUG, true) {
		if g_state == nil {
			fmt.printf("ERROR: g_state is nil in init_debug_gui\n")
			return
		}

		if g_state.debug_ui_ctx == nil {
			g_state.debug_ui_ctx = new(mu.Context, context.allocator)
			mu.init(g_state.debug_ui_ctx)

			g_state.debug_ui_ctx.text_width = mu.default_atlas_text_width
			g_state.debug_ui_ctx.text_height = mu.default_atlas_text_height

			g_state.debug_atlas_texture = rl.LoadRenderTexture(i32(mu.DEFAULT_ATLAS_WIDTH), i32(mu.DEFAULT_ATLAS_HEIGHT))
			image := rl.GenImageColor(i32(mu.DEFAULT_ATLAS_WIDTH), i32(mu.DEFAULT_ATLAS_HEIGHT), rl.Color{0, 0, 0, 0})
			defer rl.UnloadImage(image)

			for alpha, i in mu.default_atlas_alpha {
				x := i % mu.DEFAULT_ATLAS_WIDTH
				y := i / mu.DEFAULT_ATLAS_WIDTH
				color := rl.Color{255, 255, 255, alpha}
				rl.ImageDrawPixel(&image, i32(x), i32(y), color)
			}

			rl.BeginTextureMode(g_state.debug_atlas_texture)
			rl.UpdateTexture(g_state.debug_atlas_texture.texture, rl.LoadImageColors(image))
			rl.EndTextureMode()
		}

		debug_sys := &g_state.debug_system

		for i in 0..<MAX_DEBUG_PANELS {
			debug_sys.panels[i] = {}
		}

		debug_sys.panel_count = 0
		debug_sys.initialized = true
		debug_sys.enabled = true

		debug_register_panel_with_config("PostFX Settings", debug_postfx_panel, true)
		debug_register_panel_with_config("Space Shaders", debug_space_shaders_panel, false)

		fmt.printf("Debug GUI initialized with MicroUI\n")
		fmt.printf("Atlas texture ID: %d, size: %dx%d\n",
			g_state.debug_atlas_texture.id,
			g_state.debug_atlas_texture.texture.width,
			g_state.debug_atlas_texture.texture.height)
	}
}

destroy_debug_gui :: proc() {
	when #config(ODIN_DEBUG, true) {
		if g_state == nil do return

		if g_state.debug_atlas_texture.id != 0 {
			rl.UnloadRenderTexture(g_state.debug_atlas_texture)
			g_state.debug_atlas_texture = {}
		}

		if g_state.debug_ui_ctx != nil {
			free(g_state.debug_ui_ctx)
			g_state.debug_ui_ctx = nil
		}

		debug_sys := &g_state.debug_system
		for i in 0..<MAX_DEBUG_PANELS {
			debug_sys.panels[i] = {}
		}
		debug_sys.panel_count = 0
		debug_sys.initialized = false

		fmt.printf("Debug GUI destroyed\n")
	}
}

update_debug_gui :: proc() {
	when #config(ODIN_DEBUG, true) {
		if g_state == nil || g_state.debug_ui_ctx == nil do return

		ctx := g_state.debug_ui_ctx

		if g_state.debug_ui_enabled {
			mouse_x := rl.GetMouseX()
			mouse_y := rl.GetMouseY()

			mu.input_mouse_move(ctx, mouse_x, mouse_y)

			wheel := rl.GetMouseWheelMove()
			if wheel != 0 {
				mu.input_scroll(ctx, 0, i32(wheel * -30))
			}

			if rl.IsMouseButtonPressed(.LEFT) do mu.input_mouse_down(ctx, mouse_x, mouse_y, .LEFT)
			if rl.IsMouseButtonReleased(.LEFT) do mu.input_mouse_up(ctx, mouse_x, mouse_y, .LEFT)
			if rl.IsMouseButtonPressed(.RIGHT) do mu.input_mouse_down(ctx, mouse_x, mouse_y, .RIGHT)
			if rl.IsMouseButtonReleased(.RIGHT) do mu.input_mouse_up(ctx, mouse_x, mouse_y, .RIGHT)
		}

		if rl.IsKeyPressed(.P) {
			g_state.debug_ui_enabled = !g_state.debug_ui_enabled
		}

		if g_state.debug_ui_enabled {
			mu.begin(ctx)
			debug_system_render(ctx)
			mu.end(ctx)
		}
	}
}

debug_register_panel_with_config :: proc(name: string, panel_proc: Debug_Panel_Proc, start_unfolded: bool) {
	when #config(ODIN_DEBUG, true) {
		if g_state == nil do return

		debug_sys := &g_state.debug_system

		if debug_sys.panel_count >= MAX_DEBUG_PANELS {
			fmt.printf("ERROR: Maximum debug panels reached (%d)\n", MAX_DEBUG_PANELS)
			return
		}

		for i in 0..<MAX_DEBUG_PANELS {
			if !debug_sys.panels[i].active {
				debug_sys.panels[i] = Debug_Panel{
					name = name,
					render_proc = panel_proc,
					enabled = true,
					active = true,
					start_unfolded = start_unfolded,
				}
				debug_sys.panel_count += 1
				fmt.printf("Registered debug panel: %s\n", name)
				return
			}
		}
	}
}

debug_system_render :: proc(ctx: ^mu.Context) {
	when #config(ODIN_DEBUG, true) {
		if g_state == nil || !g_state.debug_ui_enabled do return

		debug_sys := &g_state.debug_system
		if !debug_sys.initialized || !debug_sys.enabled do return

		ctx.style.colors[.WINDOW_BG] =    {  0,   0,   0, 200} // Window background
		ctx.style.colors[.BUTTON] =       { 60,  60,  60, 180} // Header normal
		ctx.style.colors[.BUTTON_HOVER] = { 80,  80,  80, 200} // Header hover
		ctx.style.colors[.BUTTON_FOCUS] = {100, 100, 100, 220} // Header focus

		if mu.begin_window(ctx, "Debug System", {12, 12, 500, i32(g_state.resolution.y) - 24}, {.NO_CLOSE}) {
			mu.layout_row(ctx, {-1}, 0)
			mu.label(ctx, fmt.tprintf("Panels: %d/%d", debug_sys.panel_count, MAX_DEBUG_PANELS))

			for i in 0..<MAX_DEBUG_PANELS {
				panel := &debug_sys.panels[i]
				if panel.active && panel.enabled && panel.render_proc != nil {
					mu.layout_row(ctx, {-1}, 0)
					panel.render_proc(ctx)
				}
			}
		}
		mu.end_window(ctx)
	}
}

debug_postfx_panel :: proc(ctx: ^mu.Context) {
	when #config(ODIN_DEBUG, true) {
		if mu.header(ctx, "PostFX Settings", {.EXPANDED}) != {} {
			for &instance in g_state.postfx_instances {
				mu.layout_row(ctx, {120, -1}, 0)
				mu.label(ctx, instance.name)
				mu.checkbox(ctx, "Enabled", instance.enabled)

				switch instance.type {
				case .BCS:
					if instance.bcs_settings != nil {
						mu.layout_row(ctx, {100, -1}, 0)
						mu.label(ctx, "Brightness:")
						mu.slider(ctx, &instance.bcs_settings.brightness, -1.0, 1.0)

						mu.layout_row(ctx, {100, -1}, 0)
						mu.label(ctx, "Contrast:")
						mu.slider(ctx, &instance.bcs_settings.contrast, 0.0, 2.0)

						mu.layout_row(ctx, {100, -1}, 0)
						mu.label(ctx, "Saturation:")
						mu.slider(ctx, &instance.bcs_settings.saturation, 0.0, 2.0)
					}

				case .BLOOM_SPACE, .BLOOM_TRAIL, .BLOOM_SHIP, .BLOOM_FINAL:
					if instance.bloom_settings != nil {
						mu.layout_row(ctx, {100, -1}, 0)
						mu.label(ctx, "Threshold:")
						mu.slider(ctx, &instance.bloom_settings.threshold, 0.0, 1.0)

						mu.layout_row(ctx, {100, -1}, 0)
						mu.label(ctx, "Intensity:")
						mu.slider(ctx, &instance.bloom_settings.intensity, 0.0, 3.0)

						mu.layout_row(ctx, {100, -1}, 0)
						mu.label(ctx, "Strength:")
						mu.slider(ctx, &instance.bloom_settings.strength, 0.0, 3.0)

						mu.layout_row(ctx, {100, -1}, 0)
						mu.label(ctx, "Exposure:")
						mu.slider(ctx, &instance.bloom_settings.exposure, 0.0, 5.0)
					}
				}

				mu.layout_row(ctx, {-1}, 5) // small spacer
				mu.label(ctx, "")
			}
		}
	}
}

debug_render_microui_commands :: proc(ctx: ^mu.Context) {
	when #config(ODIN_DEBUG, true) {
		render_texture :: proc(dst: ^rl.Rectangle, src: mu.Rect, color: rl.Color) {
			dst.width = f32(src.w)
			dst.height = f32(src.h)
			rl.DrawTextureRec(
				g_state.debug_atlas_texture.texture,
				{f32(src.x), f32(src.y), f32(src.w), f32(src.h)},
				{dst.x, dst.y},
				color,
			)
		}

		to_rl_color :: proc(in_color: mu.Color) -> rl.Color {
			return {in_color.r, in_color.g, in_color.b, in_color.a}
		}

		rl.BeginBlendMode(.ALPHA)
		defer rl.EndBlendMode()

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
}

debug_space_shaders_panel :: proc(ctx: ^mu.Context) {
	when #config(ODIN_DEBUG, true) {
		if g_state == nil || !g_state.space.initialized {
			mu.label(ctx, "Space system not initialized")
			return
		}
		debug_shader_manager_panel(ctx, &g_state.space.shader_manager, "Space Shaders")
	}
}

debug_shader_manager_panel :: proc(ctx: ^mu.Context, sm: ^Shader_Manager, panel_name: string) {
	when #config(ODIN_DEBUG, true) {
		if sm == nil || sm.shader_count == 0 {
			mu.label(ctx, "Shader manager not available")
			return
		}

		if mu.header(ctx, panel_name, {.EXPANDED}) != {} {
			mu.layout_row(ctx, {5, -1}, 0)
			mu.label(ctx, "")

			mu.layout_begin_column(ctx)
			defer mu.layout_end_column(ctx)

			// Uniform Locations Table
			if .ACTIVE in mu.header(ctx, "Uniform Locations (All Shaders)") {
				layout_widths := make([]i32, sm.shader_count + 1, context.temp_allocator)
				layout_widths[0] = 120 // uniform name column
				for i in 1..=sm.shader_count {
					layout_widths[i] = 50 // each shader column
				}

				mu.layout_row(ctx, layout_widths, 0)

				mu.label(ctx, "Uniform")
				for i in 0..<sm.shader_count {
					mu.label(ctx, fmt.tprintf("S%d", i))
				}

				// Show standard uniforms
				standard_uniforms := []string{"time", "delta_time", "frame", "fps", "resolution", "mouse", "mouselerp"}
				for uniform_name in standard_uniforms {
					mu.layout_row(ctx, layout_widths, 0)
					mu.label(ctx, uniform_name)
					for i in 0..<sm.shader_count {
						location := sm.uniform_locations[i][uniform_name] if uniform_name in sm.uniform_locations[i] else -999
						mu.label(ctx, fmt.tprintf("%d", location))
					}
				}

				// Show program texture uniforms (prgm0Texture, prgm1Texture, etc.)
				for j in 0..<sm.shader_count {
					uniform_key := fmt.tprintf("prgm%dTexture", j)
					mu.layout_row(ctx, layout_widths, 0)
					mu.label(ctx, uniform_key)
					for i in 0..<sm.shader_count {
						location := sm.uniform_locations[i][uniform_key] if uniform_key in sm.uniform_locations[i] else -999
						mu.label(ctx, fmt.tprintf("%d", location))
					}
				}
			}

			// Uniform Values
			if .ACTIVE in mu.header(ctx, "Uniform Values") {
				mu.layout_row(ctx, {120, 200}, 0)

				for name, value in sm.uniforms {
					mu.label(ctx, fmt.tprintf("%s:", name))
					switch v in value {
					case f32:
						mu.label(ctx, fmt.tprintf("%.3f", v))
					case i32:
						mu.label(ctx, fmt.tprintf("%d", v))
					case rl.Vector2:
						mu.label(ctx, fmt.tprintf("(%.3f, %.3f)", v.x, v.y))
					case rl.Vector3:
						mu.label(ctx, fmt.tprintf("(%.3f, %.3f, %.3f)", v.x, v.y, v.z))
					case rl.Vector4:
						mu.label(ctx, fmt.tprintf("(%.3f, %.3f, %.3f, %.3f)", v.x, v.y, v.z, v.w))
					case rl.Texture2D:
						mu.label(ctx, fmt.tprintf("Texture ID: %d (%dx%d)", v.id, v.width, v.height))
					}
				}
			}

			// Render Target Status - Stable Frame Pair
			if .ACTIVE in mu.header(ctx, "Render Target Status - Stable Frame Pair") {
				if sm.display_pair_ready {
					mu.layout_row(ctx, {-1}, 0)
					mu.label(ctx, fmt.tprintf("Stable Ping-Pong Buffer States (Frame %d ↔ Frame %d):", sm.display_frame_a, sm.display_frame_b))

					// Table header
					mu.layout_row(ctx, {40, 99, 99, 99, 99}, 0)
					mu.label(ctx, "Target")
					mu.label(ctx, fmt.tprintf("Frame %d Read", sm.display_frame_a))
					mu.label(ctx, fmt.tprintf("Frame %d Write", sm.display_frame_a))
					mu.label(ctx, fmt.tprintf("Frame %d Read", sm.display_frame_b))
					mu.label(ctx, fmt.tprintf("Frame %d Write", sm.display_frame_b))

					// Table rows for each target
					for i in 0..<sm.shader_count {
						mu.layout_row(ctx, {40, 99, 99, 99, 99}, 0)
						mu.label(ctx, fmt.tprintf("%d", i))
						mu.label(ctx, fmt.tprintf("Buf:%d Tex:%d", sm.display_targets_a[i].read_buffer.id, sm.display_targets_a[i].read_buffer.texture.id))
						mu.label(ctx, fmt.tprintf("Buf:%d Tex:%d", sm.display_targets_a[i].write_buffer.id, sm.display_targets_a[i].write_buffer.texture.id))
						mu.label(ctx, fmt.tprintf("Buf:%d Tex:%d", sm.display_targets_b[i].read_buffer.id, sm.display_targets_b[i].read_buffer.texture.id))
						mu.label(ctx, fmt.tprintf("Buf:%d Tex:%d", sm.display_targets_b[i].write_buffer.id, sm.display_targets_b[i].write_buffer.texture.id))
					}
				} else {
					current_frame := sm.frame

					mu.layout_row(ctx, {-1}, 0)
					mu.label(ctx, "Waiting for stable frame pair... (need frame 1+)")

					// Show current frame only
					mu.layout_row(ctx, {40, 99, 99}, 0)
					mu.label(ctx, "Target")
					mu.label(ctx, fmt.tprintf("Frame %d Read", current_frame))
					mu.label(ctx, fmt.tprintf("Frame %d Write", current_frame))

					for i in 0..<sm.shader_count {
						mu.layout_row(ctx, {40, 99, 99}, 0)
						mu.label(ctx, fmt.tprintf("%d", i))
						mu.label(ctx, fmt.tprintf("Buf:%d Tex:%d", sm.render_targets[i].read_buffer.id, sm.render_targets[i].read_buffer.texture.id))
						mu.label(ctx, fmt.tprintf("Buf:%d Tex:%d", sm.render_targets[i].write_buffer.id, sm.render_targets[i].write_buffer.texture.id))
					}
				}
			}

			// Texture Bindings
			if .ACTIVE in mu.header(ctx, "Texture Bindings") {
				if sm.display_pair_ready {
					mu.layout_row(ctx, {-1}, 0)
					mu.label(ctx, fmt.tprintf("Stable Texture Bindings (Frame %d ↔ Frame %d):", sm.display_frame_a, sm.display_frame_b))

					mu.layout_row(ctx, {130, 90, 90}, 0)
					mu.label(ctx, "Uniform")
					mu.label(ctx, fmt.tprintf("Frame %d", sm.display_frame_a))
					mu.label(ctx, fmt.tprintf("Frame %d", sm.display_frame_b))

					texture_names := make([]string, sm.shader_count, context.temp_allocator)
					for j in 0..<sm.shader_count {
						texture_names[j] = fmt.tprintf("prgm%dTexture", j)
					}

					for shader_i in 0..<sm.shader_count {
						mu.layout_row(ctx, {-1}, 0)
						mu.label(ctx, fmt.tprintf("--- Shader %d ---", shader_i))

						for target_j in 0..<sm.shader_count {
							uniform_key := texture_names[target_j]
							location := sm.uniform_locations[shader_i][uniform_key] if uniform_key in sm.uniform_locations[shader_i] else -999

							texture_id_a := sm.display_targets_a[target_j].read_buffer.texture.id
							texture_id_b := sm.display_targets_b[target_j].read_buffer.texture.id

							mu.layout_row(ctx, {130, 90, 90}, 0)
							mu.label(ctx, fmt.tprintf("%s (loc=%d)", uniform_key, location))
							mu.label(ctx, fmt.tprintf("tex.id=%d", texture_id_a))
							mu.label(ctx, fmt.tprintf("tex.id=%d", texture_id_b))
						}
					}
				} else {
					current_frame := sm.frame

					mu.layout_row(ctx, {-1}, 0)
					mu.label(ctx, "Waiting for stable frame pair...")

					for shader_i in 0..<sm.shader_count {
						mu.layout_row(ctx, {-1}, 0)
						mu.label(ctx, fmt.tprintf("--- Shader %d (Frame %d) ---", shader_i, current_frame))

						for target_j in 0..<sm.shader_count {
							texture_id := sm.render_targets[target_j].read_buffer.texture.id
							uniform_key := fmt.tprintf("prgm%dTexture", target_j)
							location := sm.uniform_locations[shader_i][uniform_key] if uniform_key in sm.uniform_locations[shader_i] else -999

							mu.layout_row(ctx, {120, 200}, 0)
							mu.label(ctx, fmt.tprintf("%s (loc=%d):", uniform_key, location))
							mu.label(ctx, fmt.tprintf("tex.id=%d (from target[%d].read_buffer)", texture_id, target_j))
						}
					}
				}
			}

			// Shader Manager Info
			if .ACTIVE in mu.header(ctx, "Shader Manager Info") {
				mu.layout_row(ctx, {120, 200}, 0)
				mu.label(ctx, "Name:")
				mu.label(ctx, sm.name)
				mu.label(ctx, "Shader Count:")
				mu.label(ctx, fmt.tprintf("%d", sm.shader_count))
				mu.label(ctx, "Screen Size:")
				mu.label(ctx, fmt.tprintf("%dx%d", sm.screen_width, sm.screen_height))
				mu.label(ctx, "Display Pair Ready:")
				mu.label(ctx, fmt.tprintf("%v", sm.display_pair_ready))
			}
		}
	}
}
