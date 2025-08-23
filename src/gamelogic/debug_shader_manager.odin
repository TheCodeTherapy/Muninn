package gamelogic

import "core:fmt"
import rl "vendor:raylib"
import mu "vendor:microui"

SHADER_PANEL_UNFOLDED :: false

shader_panel_name: string = "Shader Manager"

debug_shader_manager_panel :: proc(ctx: ^mu.Context) {
	if g_state == nil {
		mu.label(ctx, "Game state not available")
		return
	}

	sm := &g_state.space_shaders

	if .ACTIVE in mu.header(ctx, shader_panel_name, SHADER_PANEL_UNFOLDED ? {.EXPANDED} : {}) {
		mu.layout_row(ctx, {5, -1}, 0)
		mu.label(ctx, "")

		mu.layout_begin_column(ctx)
		defer mu.layout_end_column(ctx)

		// uniform locations
		if .ACTIVE in mu.header(ctx, "Uniform Locations (All Shaders)") {
			layout_widths := make([]i32, sm.shader_count + 1)
			defer delete(layout_widths)
			layout_widths[0] = 100 // uniform name column
			for i in 1..=sm.shader_count {
				layout_widths[i] = 50 // each shader column
			}

			mu.layout_row(ctx, layout_widths, 0)

			mu.label(ctx, "Uniform")
			for i in 0..<sm.shader_count {
				mu.label(ctx, fmt.tprintf("S%d", i))
			}

			standard_uniforms := []string{"time", "delta_time", "frame", "fps", "resolution", "mouse", "mouselerp"}
			for uniform_name in standard_uniforms {
				mu.layout_row(ctx, layout_widths, 0)
				mu.label(ctx, uniform_name)
				for i in 0..<sm.shader_count {
					location := sm.uniform_locations[i][uniform_name] if uniform_name in sm.uniform_locations[i] else -999
					mu.label(ctx, fmt.tprintf("%d", location))
				}
			}

			// program texture uniforms (prgm0Texture, prgm1Texture, etc.)
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

		if .ACTIVE in mu.header(ctx, "Uniform Values") {
			mu.layout_row(ctx, {120, 200}, 0)
			mu.label(ctx, "Resolution:")
			mu.label(ctx, fmt.tprintf("(%.3f, %.3f)", sm.resolution.x, sm.resolution.y))
			mu.label(ctx, "Time:")
			mu.label(ctx, fmt.tprintf("%.3f", sm.time))
			mu.label(ctx, "Delta Time:")
			mu.label(ctx, fmt.tprintf("%.3f", sm.delta_time))
			mu.label(ctx, "Frame:")
			mu.label(ctx, fmt.tprintf("%d", sm.frame))
			mu.label(ctx, "FPS:")
			mu.label(ctx, fmt.tprintf("%.3f", sm.fps))
			mu.label(ctx, "Mouse Pos:")
			mu.label(ctx, fmt.tprintf("(%.3f, %.3f)", sm.mouse_pos.x, sm.mouse_pos.y))
			mu.label(ctx, "Mouse Target:")
			mu.label(ctx, fmt.tprintf("(%.3f, %.3f)", sm.mouse_target.x, sm.mouse_target.y))
			mu.label(ctx, "Mouse Lerp:")
			mu.label(ctx, fmt.tprintf("(%.3f, %.3f)", sm.mouse_lerp.x, sm.mouse_lerp.y))

			// additional uniform values from the map
			if len(sm.additional_uniforms) > 0 {
				// Add some spacing
				mu.label(ctx, "")
				mu.label(ctx, "")

				for name, value in sm.additional_uniforms {
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
		}

		// Render Target Status (stable frame pair)
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
				mu.layout_row(ctx, {-1}, 0)
				mu.label(ctx, "Waiting for stable frame pair... (need frame 1+)")

				// Show current frame only
				mu.layout_row(ctx, {40, 99, 99}, 0)
				mu.label(ctx, "Target")
				mu.label(ctx, fmt.tprintf("Frame %d Read", sm.frame))
				mu.label(ctx, fmt.tprintf("Frame %d Write", sm.frame))

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

				texture_names := make([]string, sm.shader_count)
				defer delete(texture_names)
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
				mu.layout_row(ctx, {-1}, 0)
				mu.label(ctx, "Waiting for stable frame pair...")

				for shader_i in 0..<sm.shader_count {
					mu.layout_row(ctx, {-1}, 0)
					mu.label(ctx, fmt.tprintf("--- Shader %d (Frame %d) ---", shader_i, sm.frame))

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
	}
}

// this one takes a custom name cause shader_manager is reusable
debug_shader_manager_panel_config :: proc(name: string) -> (string, bool) {
	shader_panel_name = name
	return name, SHADER_PANEL_UNFOLDED
}
