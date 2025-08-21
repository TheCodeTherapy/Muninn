package gamelogic

import "core:math"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"
import mu "vendor:microui"

DEBUG_FRAME_INTERVAL :: 200

debug_to_console: bool = false

// check if debug logging should be triggered and call write log
shader_debug_update :: proc(sm: ^Shader_Manager) {
  // logs 2 consecutive frames (N and N+1) when N is divisible by DEBUG_FRAME_INTERVAL
  // only if console debugging is enabled
  if debug_to_console && (sm.frame % DEBUG_FRAME_INTERVAL == 0 || sm.frame % DEBUG_FRAME_INTERVAL == 1) {
    shader_debug_write_log(sm, sm.frame % DEBUG_FRAME_INTERVAL == 1) // append = true for second frame
  }
}

shader_debug_write_log :: proc(sm: ^Shader_Manager, append_mode := false) {
  fmt.printf("=== SHADER MANAGER DEBUG (Frame %d) ===\n", sm.frame)
  fmt.printf("Shader count: %d\n", sm.shader_count)
  fmt.printf("Screen size: %dx%d\n", sm.screen_width, sm.screen_height)
  fmt.printf("Time: %.3f\n", sm.time)
  fmt.printf("Delta time: %.3f\n", sm.delta_time)
  fmt.printf("Frame: %d\n", sm.frame)
  fmt.printf("FPS: %.3f\n", sm.fps)

  for i in 0..<sm.shader_count {
    fmt.printf("--- Shader %d Uniform Locations ---\n", i)
    fmt.printf("  time: %d\n", sm.uniform_locations[i]["time"] if "time" in sm.uniform_locations[i] else -999)
    fmt.printf("  delta_time: %d\n", sm.uniform_locations[i]["delta_time"] if "delta_time" in sm.uniform_locations[i] else -999)
    fmt.printf("  frame: %d\n", sm.uniform_locations[i]["frame"] if "frame" in sm.uniform_locations[i] else -999)
    fmt.printf("  fps: %d\n", sm.uniform_locations[i]["fps"] if "fps" in sm.uniform_locations[i] else -999)
    fmt.printf("  resolution: %d\n", sm.uniform_locations[i]["resolution"] if "resolution" in sm.uniform_locations[i] else -999)

    for j in 0..<sm.shader_count {
      uniform_key := fmt.tprintf("prgm%dTexture", j)
      location := sm.uniform_locations[i][uniform_key] if uniform_key in sm.uniform_locations[i] else -999
      fmt.printf("  %s: %d\n", uniform_key, location)
    }

    fmt.printf("  mouse: %d\n", sm.uniform_locations[i]["mouse"] if "mouse" in sm.uniform_locations[i] else -999)
    fmt.printf("  mouselerp: %d\n", sm.uniform_locations[i]["mouselerp"] if "mouselerp" in sm.uniform_locations[i] else -999)
  }

  fmt.printf("--- Additional Uniform Values ---\n")
  for name, value in sm.additional_uniforms {
    switch v in value {
    case f32:
      fmt.printf("  %s: %.3f (f32)\n", name, v)
    case i32:
      fmt.printf("  %s: %d (i32)\n", name, v)
    case rl.Vector2:
      fmt.printf("  %s: (%.3f, %.3f) (Vector2)\n", name, v.x, v.y)
    case rl.Vector3:
      fmt.printf("  %s: (%.3f, %.3f, %.3f) (Vector3)\n", name, v.x, v.y, v.z)
    case rl.Vector4:
      fmt.printf("  %s: (%.3f, %.3f, %.3f, %.3f) (Vector4)\n", name, v.x, v.y, v.z, v.w)
    case rl.Texture2D:
      fmt.printf("  %s: Texture ID: %d (%dx%d) (Texture2D)\n", name, v.id, v.width, v.height)
    }
  }

  fmt.printf("--- Common Uniform Values ---\n")
  fmt.printf("  resolution: (%.3f, %.3f) (Vector2)\n", sm.resolution.x, sm.resolution.y)

  fmt.printf("--- Render Target Status ---\n")
  for i in 0..<sm.shader_count {
    fmt.printf(
      "  Target %d: read_buffer.id=%d, write_buffer.id=%d\n",
      i,
      sm.render_targets[i].read_buffer.id,
      sm.render_targets[i].write_buffer.id,
    )
    fmt.printf(
      "  Target %d: read_buffer.texture.id=%d, write_buffer.texture.id=%d\n",
      i,
      sm.render_targets[i].read_buffer.texture.id,
      sm.render_targets[i].write_buffer.texture.id,
    )
  }

  fmt.printf("--- Texture Binding Information (Current Frame State) ---\n")
  for shader_i in 0..<sm.shader_count {
    fmt.printf("  Shader %d texture bindings:\n", shader_i)
    for target_j in 0..<sm.shader_count {
      texture_id := sm.render_targets[target_j].read_buffer.texture.id
      uniform_key := fmt.tprintf("prgm%dTexture", target_j)
      location := sm.uniform_locations[shader_i][uniform_key] if uniform_key in sm.uniform_locations[shader_i] else -999
      fmt.printf(
        "    %s (loc=%d) -> texture.id=%d (from target[%d].read_buffer)\n",
        uniform_key, location, texture_id, target_j,
      )
    }
  }

  fmt.printf("=== END SHADER MANAGER DEBUG ===\n")
}

// render debug UI if context is available
shader_debug_render_ui :: proc(sm: ^Shader_Manager, ctx: ^mu.Context) {
  if ctx == nil do return

  window_title := fmt.tprintf("%s Debug", sm.name)
  if mu.begin_window(ctx, window_title, {10, 10, 850, 650}, {.NO_CLOSE}) {

    width := math.min(580, sm.screen_width - 20)
    maxHeight := math.min(1200, sm.screen_height - 20)

    // apply size constraints to the window
    win := mu.get_current_container(ctx)
    if win != nil {
      // minimum size constraints
      win.rect.w = max(win.rect.w, width)
      win.rect.h = max(win.rect.h, 400)

      // maximum size constraints
      win.rect.w = min(win.rect.w, width)
      win.rect.h = min(win.rect.h, maxHeight)
    }

    // system info
    if .ACTIVE in mu.header(ctx, "System Information") {
      mu.layout_row(ctx, {120, 200}, 0)
      mu.label(ctx, "Shader Count:")
      mu.label(ctx, fmt.tprintf("%d", sm.shader_count))
      mu.label(ctx, "Screen Size:")
      mu.label(ctx, fmt.tprintf("%.0fx%.0f", sm.resolution.x, sm.resolution.y))
      mu.label(ctx, "Time:")
      mu.label(ctx, fmt.tprintf("%.3f", sm.time))
      mu.label(ctx, "Delta Time:")
      mu.label(ctx, fmt.tprintf("%.3f", sm.delta_time))
      mu.label(ctx, "Frame:")
      mu.label(ctx, fmt.tprintf("%d", sm.frame))
      mu.label(ctx, "FPS:")
      mu.label(ctx, fmt.tprintf("%.3f", sm.fps))
    }

    // uniform locations
    if .ACTIVE in mu.header(ctx, "Uniform Locations (All Shaders)") {
      // create dynamic layout widths: 100 for uniform name + 50 for each shader
      layout_widths := make([]i32, sm.shader_count + 1)
      defer delete(layout_widths)
      layout_widths[0] = 100 // uniform name column
      for i in 1..=sm.shader_count {
        layout_widths[i] = 50 // each shader column
      }

      // table header: uniform names vertical, shaders horizontal
      mu.layout_row(ctx, layout_widths, 0)
      mu.label(ctx, "Uniform")
      for shader_idx in 0..<sm.shader_count {
        mu.label(ctx, fmt.tprintf("Shader %d", shader_idx))
      }

      // create dynamic uniform names list (persist for entire UI frame)
      uniform_names := make([]string, 5 + sm.shader_count) // 5 standard + N texture uniforms
      uniform_names[0] = "time"
      uniform_names[1] = "delta_time"
      uniform_names[2] = "frame"
      uniform_names[3] = "fps"
      uniform_names[4] = "resolution"
      uniform_names[5] = "mouse"
      uniform_names[6] = "mouselerp"
      texture_uniform_names := make([]string, sm.shader_count)
      for i in 0..<sm.shader_count {
        texture_uniform_names[i] = fmt.aprintf("prgm%dTexture", i)
        uniform_names[5 + i] = texture_uniform_names[i]
      }

      for uniform_name in uniform_names {
        mu.layout_row(ctx, layout_widths, 0)
        mu.label(ctx, uniform_name)

        // get location for each shader
        for shader_idx in 0..<sm.shader_count {
          uniform_cstr := strings.clone_to_cstring(uniform_name)
          defer delete(uniform_cstr)
          loc := rl.GetShaderLocation(sm.shaders[shader_idx], uniform_cstr)
          mu.label(ctx, fmt.tprintf("%d", loc))
        }
      }

      // clean up allocated uniform names
      for name in texture_uniform_names {
        delete(name)
      }
      delete(texture_uniform_names)
      delete(uniform_names)
    }

    // current Uniform Values
    if .ACTIVE in mu.header(ctx, "Current Uniform Values") {
      mu.layout_row(ctx, {120, 200}, 0)

      // Built-in uniform values
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

      // Additional uniform values from the map
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

    // render Targets
    if .ACTIVE in mu.header(ctx, "Render Target Status - Stable Frame Pair") {
      if sm.display_pair_ready {
        mu.layout_row(ctx, {-1}, 0)
        mu.label(ctx, fmt.tprintf("Stable Ping-Pong Buffer States (Frame %d ↔ Frame %d):", sm.display_frame_a, sm.display_frame_b))

        // table header
        mu.layout_row(ctx, {60, 120, 120, 120, 120}, 0)
        mu.label(ctx, "Target")
        mu.label(ctx, fmt.tprintf("Frame %d Read", sm.display_frame_a))
        mu.label(ctx, fmt.tprintf("Frame %d Write", sm.display_frame_a))
        mu.label(ctx, fmt.tprintf("Frame %d Read", sm.display_frame_b))
        mu.label(ctx, fmt.tprintf("Frame %d Write", sm.display_frame_b))

        // table rows for each target
        for i in 0..<sm.shader_count {
          mu.layout_row(ctx, {60, 120, 120, 120, 120}, 0)
          mu.label(ctx, fmt.tprintf("%d", i))
          mu.label(ctx, fmt.tprintf("Buf:%d Tex:%d", sm.display_targets_a[i].read_buffer.id, sm.display_targets_a[i].read_buffer.texture.id))
          mu.label(ctx, fmt.tprintf("Buf:%d Tex:%d", sm.display_targets_a[i].write_buffer.id, sm.display_targets_a[i].write_buffer.texture.id))
          mu.label(ctx, fmt.tprintf("Buf:%d Tex:%d", sm.display_targets_b[i].read_buffer.id, sm.display_targets_b[i].read_buffer.texture.id))
          mu.label(ctx, fmt.tprintf("Buf:%d Tex:%d", sm.display_targets_b[i].write_buffer.id, sm.display_targets_b[i].write_buffer.texture.id))
        }
      } else {
        mu.layout_row(ctx, {-1}, 0)
        mu.label(ctx, "Waiting for stable frame pair... (need frame 1+)")

        // show current frame only
        mu.layout_row(ctx, {60, 120, 120}, 0)
        mu.label(ctx, "Target")
        mu.label(ctx, fmt.tprintf("Frame %d Read", sm.frame))
        mu.label(ctx, fmt.tprintf("Frame %d Write", sm.frame))

        for i in 0..<sm.shader_count {
          mu.layout_row(ctx, {60, 120, 120}, 0)
          mu.label(ctx, fmt.tprintf("%d", i))
          mu.label(ctx, fmt.tprintf("Buf:%d Tex:%d", sm.render_targets[i].read_buffer.id, sm.render_targets[i].read_buffer.texture.id))
          mu.label(ctx, fmt.tprintf("Buf:%d Tex:%d", sm.render_targets[i].write_buffer.id, sm.render_targets[i].write_buffer.texture.id))
        }
      }
    }

    // texture bindings
    if .ACTIVE in mu.header(ctx, "Texture Bindings") {
      if sm.display_pair_ready {
        mu.layout_row(ctx, {-1}, 0)
        mu.label(ctx, fmt.tprintf("Stable Texture Bindings (Frame %d ↔ Frame %d):", sm.display_frame_a, sm.display_frame_b))

        // main binding table with stable frame comparison
        mu.layout_row(ctx, {100, 120, 120}, 0)
        mu.label(ctx, "Uniform")
        mu.label(ctx, fmt.tprintf("Frame %d", sm.display_frame_a))
        mu.label(ctx, fmt.tprintf("Frame %d", sm.display_frame_b))

        // create dynamic texture names (persist for entire UI frame)
        texture_names := make([]string, sm.shader_count)
        for j in 0..<sm.shader_count {
          texture_names[j] = fmt.aprintf("prgm%dTexture", j)
        }

        for j in 0..<sm.shader_count {
          mu.layout_row(ctx, {100, 120, 120}, 0)
          mu.label(ctx, texture_names[j])

          // frame A texture binding
          frame_a_texture_id := sm.display_targets_a[j].read_buffer.texture.id
          frame_a_buffer_id := sm.display_targets_a[j].read_buffer.id
          mu.label(ctx, fmt.tprintf("Tex:%d Buf:%d", frame_a_texture_id, frame_a_buffer_id))

          // frame B texture binding
          frame_b_texture_id := sm.display_targets_b[j].read_buffer.texture.id
          frame_b_buffer_id := sm.display_targets_b[j].read_buffer.id
          mu.label(ctx, fmt.tprintf("Tex:%d Buf:%d", frame_b_texture_id, frame_b_buffer_id))
        }

        // clean up texture names
        for name in texture_names {
          delete(name)
        }
        delete(texture_names)
      } else {
        mu.layout_row(ctx, {-1}, 0)
        mu.label(ctx, "Waiting for stable frame pair data...")

        mu.layout_row(ctx, {100, 120}, 0)
        mu.label(ctx, "Uniform")
        mu.label(ctx, fmt.tprintf("Frame %d", sm.frame))

        // create dynamic texture names for fallback case too
        fallback_texture_names := make([]string, sm.shader_count)
        for j in 0..<sm.shader_count {
          fallback_texture_names[j] = fmt.aprintf("prgm%dTexture", j)
        }

        for j in 0..<sm.shader_count {
          mu.layout_row(ctx, {100, 120}, 0)
          mu.label(ctx, fallback_texture_names[j])

          texture_id := sm.render_targets[j].read_buffer.texture.id
          buffer_id := sm.render_targets[j].read_buffer.id
          mu.label(ctx, fmt.tprintf("Tex:%d Buf:%d", texture_id, buffer_id))
        }

        // clean up fallback texture names
        for name in fallback_texture_names {
          delete(name)
        }
        delete(fallback_texture_names)
      }

      // uniform locations consistency check
      mu.layout_row(ctx, {-1}, 5)
      mu.label(ctx, "")
      mu.layout_row(ctx, {-1}, 0)
      mu.label(ctx, "Uniform Location Consistency:")

      // create dynamic layout based on shader count
      consistency_layout := make([]i32, sm.shader_count + 1)
      consistency_layout[0] = 100 // first column for texture name
      for j in 1..=sm.shader_count {
        consistency_layout[j] = 50
      }

      // dynamic header row
      mu.layout_row(ctx, consistency_layout, 0)
      mu.label(ctx, "Uniform")
      for shader_idx in 0..<sm.shader_count {
        mu.label(ctx, fmt.tprintf("Sh%d", shader_idx))
      }

      // create dynamic texture names for consistency check (persist for entire frame)
      consistency_texture_names := make([]string, sm.shader_count)
      for j in 0..<sm.shader_count {
        consistency_texture_names[j] = fmt.aprintf("prgm%dTexture", j)
      }

      for j in 0..<sm.shader_count {
        mu.layout_row(ctx, consistency_layout, 0)
        mu.label(ctx, consistency_texture_names[j])

        for shader_idx in 0..<sm.shader_count {
          uniform_cstr := strings.clone_to_cstring(consistency_texture_names[j])
          defer delete(uniform_cstr)
          loc := rl.GetShaderLocation(sm.shaders[shader_idx], uniform_cstr)
          mu.label(ctx, fmt.tprintf("%d", loc))
        }
      }

      // clean up allocated strings
      for name in consistency_texture_names {
        delete(name)
      }
      delete(consistency_texture_names)
      delete(consistency_layout)
    }

    mu.layout_row(ctx, {-1}, 10)
    mu.label(ctx, "")
    mu.layout_row(ctx, {200, -1}, 0)
    mu.checkbox(ctx, "Output debug logs to console", &debug_to_console)
  }

  mu.end_window(ctx)
}
