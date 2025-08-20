package gamelogic

import "core:math"
import "core:fmt"
import "core:log"
import "core:strings"
import rl "vendor:raylib"
import mu "vendor:microui"

DEBUG_FRAME_INTERVAL :: 200

// file reader function type
File_Reader :: proc(filename: string, allocator := context.allocator, loc := #caller_location) -> (data: []byte, success: bool)

// uniform value types that can be passed to the shaders
Uniform_Value :: union {
  f32,
  i32,
  rl.Vector2,
  rl.Vector3,
  rl.Vector4,
  rl.Texture2D,
}

// pair of render targets for ping-pong rendering
Render_Target_Pair :: struct {
  read_buffer:  rl.RenderTexture2D,
  write_buffer: rl.RenderTexture2D,
}

// shader Manager for multi-pass rendering with ping-pong buffers
Shader_Manager :: struct {
  name: string, //                                  unique identifier for this shader manager instance
  render_targets: []Render_Target_Pair, //          render targets for each shader (double-buffered)
  shaders: []rl.Shader, //                          fragment shaders

  uniform_locations: []map[string]i32, //           uniform locations for each shader
  time: f32, //                                     common uniform values
  frame: i32, //                                    common uniform values
  fps: f32, //                                      current FPS (updated every frame)
  resolution: rl.Vector2, //                        common uniform values
  mouse_pos: rl.Vector2, //                         mouse position uniform
  mouse_target: rl.Vector2, //                      mouse target for interpolation
  mouse_lerp: rl.Vector2, //                        interpolated mouse position uniform
  mouse_lerp_factor: f32, //                        mouse interpolation factor
  additional_uniforms: map[string]Uniform_Value, // common uniform values

  debug_ui_ctx: ^mu.Context, //                     optional debug UI context
  debug_to_console: bool, //                        whether to output debug logs to console

  screen_width, screen_height: i32, //              screen dimensions

  vertex_shader_path: string, //                    vertex shader path (reused for all frag shaders)
  fragment_shader_paths: []string, //               fragment shader paths
  shader_count: int, //                             number of fragment shaders

  // previous frame state for debug comparison
  prev_frame: i32, //                               previous frame number
  prev_render_targets: []Render_Target_Pair, //     previous frame render target state

  // stable frame pair display (updates every 2 frames)
  display_frame_a: i32, //                          stable frame A for display
  display_frame_b: i32, //                          stable frame B for display
  display_targets_a: []Render_Target_Pair, //       stable targets A for display
  display_targets_b: []Render_Target_Pair, //       stable targets B for display
  display_pair_ready: bool, //                      whether we have a stable pair to display

  // file reader function for shader preprocessing
  file_reader: File_Reader, //                      function to read files cross-platform
}

// initialize the shader manager with fragment shader paths
shader_manager_init :: proc(sm: ^Shader_Manager, name: string, vertex_shader_path: string, fragment_shader_paths: []string, width, height: i32, file_reader: File_Reader) -> bool {
  sm.name = name
  sm.vertex_shader_path = vertex_shader_path
  sm.fragment_shader_paths = make([]string, len(fragment_shader_paths))
  copy(sm.fragment_shader_paths, fragment_shader_paths)
  sm.file_reader = file_reader

  sm.shader_count = len(fragment_shader_paths)
  sm.screen_width = width
  sm.screen_height = height
  sm.resolution = rl.Vector2{f32(width), f32(height)}
  sm.frame = 0
  sm.time = 0.0
  sm.mouse_pos = rl.Vector2{0, 0}
  sm.mouse_target = rl.Vector2{0, 0}
  sm.mouse_lerp = rl.Vector2{0, 0}
  sm.mouse_lerp_factor = 0.05 // framerate-independent lerp factor (0.03 = smooth, 0.2 = snappy)
  sm.debug_ui_ctx = nil
  sm.debug_to_console = false // start with console debugging disabled

  // initialize additional uniforms map
  sm.additional_uniforms = make(map[string]Uniform_Value)

  // create render targets
  sm.render_targets = make([]Render_Target_Pair, sm.shader_count)

  // create previous frame render targets for debug comparison
  sm.prev_render_targets = make([]Render_Target_Pair, sm.shader_count)
  sm.prev_frame = -1

  // create stable display frame pairs
  sm.display_targets_a = make([]Render_Target_Pair, sm.shader_count)
  sm.display_targets_b = make([]Render_Target_Pair, sm.shader_count)
  sm.display_frame_a = -1
  sm.display_frame_b = -1
  sm.display_pair_ready = false

  for i in 0..<sm.shader_count {
    // use 32-bit float render textures for better precision
    sm.render_targets[i].read_buffer = LoadRT_WithFallback(width, height, .UNCOMPRESSED_R32G32B32A32)
    sm.render_targets[i].write_buffer = LoadRT_WithFallback(width, height, .UNCOMPRESSED_R32G32B32A32)

    if sm.render_targets[i].read_buffer.id == 0 || sm.render_targets[i].write_buffer.id == 0 {
      log.errorf("Failed to create render targets for shader %d", i)
      shader_manager_destroy(sm)
      return false
    }

    rl.SetTextureWrap(sm.render_targets[i].read_buffer.texture, .CLAMP)
    rl.SetTextureWrap(sm.render_targets[i].write_buffer.texture, .CLAMP)
    rl.SetTextureFilter(sm.render_targets[i].read_buffer.texture, .POINT)
    rl.SetTextureFilter(sm.render_targets[i].write_buffer.texture, .POINT)

    rl.BeginTextureMode(sm.render_targets[i].read_buffer)
    rl.ClearBackground(rl.Color{0, 0, 0, 255})
    rl.EndTextureMode()

    rl.BeginTextureMode(sm.render_targets[i].write_buffer)
    rl.ClearBackground(rl.Color{0, 0, 0, 255})
    rl.EndTextureMode()
  }

  // load shaders
  sm.shaders = make([]rl.Shader, sm.shader_count)
  sm.uniform_locations = make([]map[string]i32, sm.shader_count)

  for i in 0..<sm.shader_count {
    vertex_cstr := strings.clone_to_cstring(vertex_shader_path)
    defer delete(vertex_cstr)

    if !rl.FileExists(vertex_cstr) {
      log.errorf("Vertex shader file not found: %s", vertex_shader_path)
      shader_manager_destroy(sm)
      return false
    }

    fragment_cstr := strings.clone_to_cstring(fragment_shader_paths[i])
    defer delete(fragment_cstr)

    if !rl.FileExists(fragment_cstr) {
      log.errorf("Fragment shader file not found: %s", fragment_shader_paths[i])
      shader_manager_destroy(sm)
      return false
    }

    sm.shaders[i] = load_shader_with_preprocessing(sm, vertex_shader_path, fragment_shader_paths[i])

    if sm.shaders[i].id == 0 {
      log.errorf("Failed to load shader %d: vertex=%s, fragment=%s", i, vertex_shader_path, fragment_shader_paths[i])
      shader_manager_destroy(sm)
      return false
    }

    // initialize uniform location map for this shader
    sm.uniform_locations[i] = make(map[string]i32)

    // get locations for common uniforms
    sm.uniform_locations[i]["time"] = rl.GetShaderLocation(sm.shaders[i], "time")
    sm.uniform_locations[i]["frame"] = rl.GetShaderLocation(sm.shaders[i], "frame")
    sm.uniform_locations[i]["resolution"] = rl.GetShaderLocation(sm.shaders[i], "resolution")
    sm.uniform_locations[i]["mouse"] = rl.GetShaderLocation(sm.shaders[i], "mouse")
    sm.uniform_locations[i]["mouselerp"] = rl.GetShaderLocation(sm.shaders[i], "mouselerp")
    sm.uniform_locations[i]["ship_world_position"] = rl.GetShaderLocation(sm.shaders[i], "ship_world_position")
    sm.uniform_locations[i]["ship_screen_position"] = rl.GetShaderLocation(sm.shaders[i], "ship_screen_position")
    sm.uniform_locations[i]["camera_position"] = rl.GetShaderLocation(sm.shaders[i], "camera_position")
    sm.uniform_locations[i]["ship_direction"] = rl.GetShaderLocation(sm.shaders[i], "ship_direction")
    sm.uniform_locations[i]["ship_velocity"] = rl.GetShaderLocation(sm.shaders[i], "ship_velocity")
    sm.uniform_locations[i]["ship_speed"] = rl.GetShaderLocation(sm.shaders[i], "ship_speed")

    log.infof("Shader %d common uniforms: time=%d, frame=%d, resolution=%d, mouse=%d, mouselerp=%d",
      i,
      sm.uniform_locations[i]["time"],
      sm.uniform_locations[i]["frame"],
      sm.uniform_locations[i]["resolution"],
      sm.uniform_locations[i]["mouse"],
      sm.uniform_locations[i]["mouselerp"],
    )

    // get locations for all prgm*Texture uniforms (every shader gets all texture uniforms)
    for j in 0..<sm.shader_count {
      // create a persistent string for the uniform name
      uniform_name := fmt.aprintf("prgm%dTexture", j)
      cstr_name := strings.clone_to_cstring(uniform_name)
      defer delete(cstr_name) // Clean up C string
      location := rl.GetShaderLocation(sm.shaders[i], cstr_name)
      sm.uniform_locations[i][uniform_name] = location
      log.infof("Shader %d: %s location = %d (stored as key: '%s')", i, uniform_name, location, uniform_name)
    }
  }

  log.infof("Shader manager '%s' initialized with %d shaders", sm.name, sm.shader_count)
  return true
}

// high-level initialization helper that handles file existence checking
shader_manager_init_from_paths :: proc(
    name: string,
    vertex_path: string,
    fragment_paths: []string,
    width, height: i32,
    file_reader: File_Reader,
    debug_ctx: ^mu.Context = nil
) -> (Shader_Manager, bool) {
  shader_manager: Shader_Manager

  // Check if all shader files exist
  vertex_cstr := strings.clone_to_cstring(vertex_path)
  defer delete(vertex_cstr)
  all_shaders_exist := rl.FileExists(vertex_cstr)

  if all_shaders_exist {
    for path in fragment_paths {
      path_cstr := strings.clone_to_cstring(path)
      defer delete(path_cstr)
      if !rl.FileExists(path_cstr) {
        all_shaders_exist = false
        break
      }
    }
  }

  if !all_shaders_exist {
    log.errorf("Shader manager '%s': some shader files not found", name)
    return shader_manager, false
  }

  // Initialize the shader manager
  success := shader_manager_init(&shader_manager, name, vertex_path, fragment_paths, width, height, file_reader)

  if success && debug_ctx != nil {
    shader_manager.debug_ui_ctx = debug_ctx
  }

  if !success {
    shader_manager_destroy(&shader_manager)
    return shader_manager, false
  }

  return shader_manager, true
}

// hot reload shaders
shader_manager_reload_shaders :: proc(sm: ^Shader_Manager) -> bool {
  log.infof("=== HOT RELOADING SHADERS (%s) ===", sm.name)

  // unload existing shaders
  for i in 0..<sm.shader_count {
    if sm.shaders[i].id != 0 {
      log.infof("Unloading old shader %d (ID: %d)", i, sm.shaders[i].id)
      rl.UnloadShader(sm.shaders[i])
    }
    // clear old uniform locations and clean up string keys
    for key, _ in sm.uniform_locations[i] {
      // Only delete keys that were dynamically allocated (prgm*Texture keys)
      if strings.has_prefix(key, "prgm") && strings.has_suffix(key, "Texture") {
        delete(key)
      }
    }
    delete(sm.uniform_locations[i])
    sm.uniform_locations[i] = make(map[string]i32)
  }

  // reload all shaders
  for i in 0..<sm.shader_count {
    log.infof("Reloading shader %d: vertex=%s, fragment=%s",
      i, sm.vertex_shader_path, sm.fragment_shader_paths[i],
    )

    vertex_cstr := strings.clone_to_cstring(sm.vertex_shader_path)
    defer delete(vertex_cstr)
    fragment_cstr := strings.clone_to_cstring(sm.fragment_shader_paths[i])
    defer delete(fragment_cstr)

    sm.shaders[i] = load_shader_with_preprocessing(sm, sm.vertex_shader_path, sm.fragment_shader_paths[i])

    if sm.shaders[i].id == 0 {
      log.errorf(
        "RELOAD FAILED: Shader %d failed to compile: vertex=%s, fragment=%s",
        i, sm.vertex_shader_path, sm.fragment_shader_paths[i],
      )
      return false
    }

    log.infof("Shader %d reloaded successfully (new ID: %d)", i, sm.shaders[i].id)

    // get locations for common uniforms
    sm.uniform_locations[i]["time"] = rl.GetShaderLocation(sm.shaders[i], "time")
    sm.uniform_locations[i]["frame"] = rl.GetShaderLocation(sm.shaders[i], "frame")
    sm.uniform_locations[i]["resolution"] = rl.GetShaderLocation(sm.shaders[i], "resolution")
    sm.uniform_locations[i]["mouse"] = rl.GetShaderLocation(sm.shaders[i], "mouse")
    sm.uniform_locations[i]["mouselerp"] = rl.GetShaderLocation(sm.shaders[i], "mouselerp")
    sm.uniform_locations[i]["ship_world_position"] = rl.GetShaderLocation(sm.shaders[i], "ship_world_position")
    sm.uniform_locations[i]["ship_screen_position"] = rl.GetShaderLocation(sm.shaders[i], "ship_screen_position")
    sm.uniform_locations[i]["camera_position"] = rl.GetShaderLocation(sm.shaders[i], "camera_position")
    sm.uniform_locations[i]["ship_direction"] = rl.GetShaderLocation(sm.shaders[i], "ship_direction")
    sm.uniform_locations[i]["ship_velocity"] = rl.GetShaderLocation(sm.shaders[i], "ship_velocity")
    sm.uniform_locations[i]["ship_speed"] = rl.GetShaderLocation(sm.shaders[i], "ship_speed")

    log.infof(
      "RELOADED Shader %d common uniforms: time=%d, frame=%d, resolution=%d, mouse=%d, mouselerp=%d",
      i,
      sm.uniform_locations[i]["time"],
      sm.uniform_locations[i]["frame"],
      sm.uniform_locations[i]["resolution"],
      sm.uniform_locations[i]["mouse"],
      sm.uniform_locations[i]["mouselerp"],
    )

    // get locations for all prgm*Texture uniforms
    for j in 0..<sm.shader_count {
      uniform_name := fmt.aprintf("prgm%dTexture", j)

      cstr_name := strings.clone_to_cstring(uniform_name)
      defer delete(cstr_name)

      location := rl.GetShaderLocation(sm.shaders[i], cstr_name)
      sm.uniform_locations[i][uniform_name] = location
      log.infof("RELOADED Shader %d: %s location = %d", i, uniform_name, location)
    }
  }

  log.infof("=== SHADER HOT RELOAD COMPLETE (%s) ===", sm.name)
  return true
}

// destroy the shader manager and clean up resources
shader_manager_destroy :: proc(sm: ^Shader_Manager) {
  // unload shaders
  for shader in sm.shaders {
    if shader.id != 0 {
      rl.UnloadShader(shader)
    }
  }
  delete(sm.shaders)

  // unload render targets
  for target in sm.render_targets {
    if target.read_buffer.id != 0 {
      rl.UnloadRenderTexture(target.read_buffer)
    }
    if target.write_buffer.id != 0 {
      rl.UnloadRenderTexture(target.write_buffer)
    }
  }

  delete(sm.render_targets) // cleanup render targets
  delete(sm.prev_render_targets) // clean up previous frame render targets
  delete(sm.display_targets_a) // clean up stable display frame pairs
  delete(sm.display_targets_b) // clean up stable display frame pairs

  // clean up uniform locations
  for locations in sm.uniform_locations {
    // clean up the string keys that were allocated with fmt.aprintf
    for key, _ in locations {
      // only delete keys that were dynamically allocated (prgm*Texture keys)
      if strings.has_prefix(key, "prgm") && strings.has_suffix(key, "Texture") {
        delete(key)
      }
    }
    delete(locations)
  }
  delete(sm.uniform_locations)

  // clean up additional uniforms
  delete(sm.additional_uniforms)

  // clean up shader paths
  delete(sm.fragment_shader_paths)

  log.infof("Shader manager '%s' destroyed", sm.name)
}

// write debug information to terminal
write_debug_log :: proc(sm: ^Shader_Manager, append_mode := false) {
  fmt.printf("=== SHADER MANAGER DEBUG (Frame %d) ===\n", sm.frame)
  fmt.printf("Shader count: %d\n", sm.shader_count)
  fmt.printf("Screen size: %dx%d\n", sm.screen_width, sm.screen_height)
  fmt.printf("Time: %.3f\n", sm.time)

  for i in 0..<sm.shader_count {
    fmt.printf("--- Shader %d Uniform Locations ---\n", i)
    fmt.printf("  time: %d\n", sm.uniform_locations[i]["time"] if "time" in sm.uniform_locations[i] else -999)
    fmt.printf("  frame: %d\n", sm.uniform_locations[i]["frame"] if "frame" in sm.uniform_locations[i] else -999)
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

// update common uniforms (time, frame, resolution, mouse)
shader_manager_update :: proc(sm: ^Shader_Manager, delta_time: f32) {
  // capture previous frame state before updating
  if sm.frame >= 0 {
    sm.prev_frame = sm.frame
    // copy current render target state to previous frame state
    for i in 0..<sm.shader_count {
      sm.prev_render_targets[i] = sm.render_targets[i]
    }
  }

  sm.fps = f32(rl.GetFPS())
  sm.time += delta_time
  sm.frame += 1

  // update mouse input for shaders
  mouse_pos := rl.GetMousePosition()
  width := f32(sm.screen_width)
  height := f32(sm.screen_height)

  // normalize mouse coordinates to [-1,1]
  normalized_mouse := rl.Vector2{
    (mouse_pos.x / width) * 2.0 - 1.0,  // Convert [0,width] to [-1,1]
    1.0 - (mouse_pos.y / height) * 2.0, // Convert [0,height] to [1,-1], then flip Y
  }

  sm.mouse_pos = normalized_mouse
  sm.mouse_target = normalized_mouse

  // smoothly interpolate towards the stable target
  sm.mouse_lerp.x += ease(sm.mouse_target.x, sm.mouse_lerp.x, sm.mouse_lerp_factor, delta_time, sm.fps)
  sm.mouse_lerp.y += ease(sm.mouse_target.y, sm.mouse_lerp.y, sm.mouse_lerp_factor, delta_time, sm.fps)

  // logs 2 consecutive frames (N and N+1) when N is divisible by DEBUG_FRAME_INTERVAL
  // only if console debugging is enabled
  if sm.debug_to_console && (sm.frame % DEBUG_FRAME_INTERVAL == 0 || sm.frame % DEBUG_FRAME_INTERVAL == 1) {
    write_debug_log(sm, sm.frame % DEBUG_FRAME_INTERVAL == 1) // append = true for second frame
  }

  // handle window resizing
  current_width := i32(rl.GetScreenWidth())
  current_height := i32(rl.GetScreenHeight())

  if current_width != sm.screen_width || current_height != sm.screen_height {
    shader_manager_resize(sm, current_width, current_height)
  }
}

// resize render targets when screen size changes
shader_manager_resize :: proc(sm: ^Shader_Manager, new_width, new_height: i32) {
  sm.screen_width = new_width
  sm.screen_height = new_height
  sm.resolution = rl.Vector2{f32(new_width), f32(new_height)}

  // resize all render targets
  for &target in sm.render_targets {
    rl.UnloadRenderTexture(target.read_buffer)
    rl.UnloadRenderTexture(target.write_buffer)
    target.read_buffer = LoadRT_WithFallback(new_width, new_height, .UNCOMPRESSED_R32G32B32A32)
    target.write_buffer = LoadRT_WithFallback(new_width, new_height, .UNCOMPRESSED_R32G32B32A32)

    rl.SetTextureWrap(target.read_buffer.texture, .CLAMP)
    rl.SetTextureWrap(target.write_buffer.texture, .CLAMP)
    rl.SetTextureFilter(target.read_buffer.texture, .POINT)
    rl.SetTextureFilter(target.write_buffer.texture, .POINT)
  }

  log.infof("Shader manager '%s' resized to %dx%d", sm.name, new_width, new_height)
}

// render debug UI if context is available
shader_manager_debug_ui :: proc(sm: ^Shader_Manager) {
  if sm.debug_ui_ctx == nil do return

  ctx := sm.debug_ui_ctx
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
      mu.label(ctx, "Frame:")
      mu.label(ctx, fmt.tprintf("%d", sm.frame))
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
      uniform_names[1] = "frame"
      uniform_names[2] = "resolution"
      uniform_names[3] = "mouse"
      uniform_names[4] = "mouselerp"
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
      mu.label(ctx, "Frame:")
      mu.label(ctx, fmt.tprintf("%d", sm.frame))
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

    // Debug console toggle (after all sections)
    mu.layout_row(ctx, {-1}, 10) // add some spacing
    mu.label(ctx, "")
    mu.layout_row(ctx, {200, -1}, 0)
    mu.checkbox(ctx, "Output debug logs to console", &sm.debug_to_console)
  }

  mu.end_window(ctx)
}

// set an additional uniform value
shader_manager_set_uniform :: proc(sm: ^Shader_Manager, name: string, value: Uniform_Value) {
  sm.additional_uniforms[name] = value

  // update uniform locations for all shaders if not already cached
  for i in 0..<sm.shader_count {
    if name not_in sm.uniform_locations[i] {
      name_cstr := strings.clone_to_cstring(name)
      defer delete(name_cstr)
      sm.uniform_locations[i][name] = rl.GetShaderLocation(sm.shaders[i], name_cstr)
    }
  }
}

// get an additional uniform value
shader_manager_get_uniform :: proc(sm: ^Shader_Manager, name: string) -> (Uniform_Value, bool) {
  value, ok := sm.additional_uniforms[name]
  return value, ok
}

// apply a uniform value to a shader
shader_manager_apply_uniform :: proc(shader: rl.Shader, location: i32, value: Uniform_Value) {
  if location == -1 do return // uniform not found or optimized out

  switch v in value {
  case f32:
    temp := v
    rl.SetShaderValue(shader, location, &temp, .FLOAT)
  case i32:
    temp := v
    rl.SetShaderValue(shader, location, &temp, .INT)
  case rl.Vector2:
    temp := v
    rl.SetShaderValue(shader, location, &temp, .VEC2)
  case rl.Vector3:
    temp := v
    rl.SetShaderValue(shader, location, &temp, .VEC3)
  case rl.Vector4:
    temp := v
    rl.SetShaderValue(shader, location, &temp, .VEC4)
  case rl.Texture2D:
    if v.id != 0 {
      rl.SetShaderValueTexture(shader, location, v)
    }
  }
}

// main rendering function - performs simple linear multi-pass rendering
shader_manager_render :: proc(sm: ^Shader_Manager) -> rl.Texture2D {
  if sm.shader_count == 0 do return rl.Texture2D{}

  // render all shaders in order 0 to N-1 (simple linear pipeline)
  for i in 0..<sm.shader_count {
    shader_manager_render_pass(sm, i, &sm.render_targets[i].write_buffer)

    // swap buffers after each shader
    temp := sm.render_targets[i].read_buffer
    sm.render_targets[i].read_buffer = sm.render_targets[i].write_buffer
    sm.render_targets[i].write_buffer = temp
  }

  // capture stable frame pairs after all swapping is complete
  shader_manager_capture_stable_pairs(sm)

  // return final output texture (from last shader's read buffer)
  return shader_manager_get_output_texture(sm)
}

// capture stable frame pairs after rendering/swapping is complete
shader_manager_capture_stable_pairs :: proc(sm: ^Shader_Manager) {
  // update stable display pairs every 2 frames after buffer swaps
  // safety check: make sure we have valid previous frame data
  if sm.frame >= 1 && sm.frame % 2 == 1 && sm.prev_frame >= 0 {
    // we're on an odd frame, so capture the stable pair
    sm.display_frame_a = sm.prev_frame
    sm.display_frame_b = sm.frame

    for i in 0..<sm.shader_count {
      sm.display_targets_a[i] = sm.prev_render_targets[i]
      sm.display_targets_b[i] = sm.render_targets[i]  // current state after swapping
    }

    sm.display_pair_ready = true
  }
}

// render a single shader pass
shader_manager_render_pass :: proc(sm: ^Shader_Manager, shader_index: int, target: ^rl.RenderTexture2D) {
  if shader_index < 0 || shader_index >= sm.shader_count do return

  shader := sm.shaders[shader_index]
  locations := sm.uniform_locations[shader_index]

  // set render target
  if target != nil {
    rl.BeginTextureMode(target^)
    // clear render target to black for proper compositing
    rl.ClearBackground(rl.BLACK)
  }

  rl.BeginShaderMode(shader)

  // set common uniforms
  shader_manager_apply_uniform(shader, locations["time"], sm.time)
  shader_manager_apply_uniform(shader, locations["frame"], sm.frame)
  shader_manager_apply_uniform(shader, locations["resolution"], sm.resolution)
  shader_manager_apply_uniform(shader, locations["mouse"], sm.mouse_pos)
  shader_manager_apply_uniform(shader, locations["mouselerp"], sm.mouse_lerp)

  // set additional uniforms
  for name, value in sm.additional_uniforms {
    if location, ok := locations[name]; ok {
      shader_manager_apply_uniform(shader, location, value)
    }
  }

  // set texture uniforms (all prgm*Texture uniforms)
  for j in 0..<sm.shader_count {
    uniform_name := fmt.tprintf("prgm%dTexture", j)
    if location, ok := locations[uniform_name]; ok && location != -1 {
      // use the read buffer texture of shader j
      texture := sm.render_targets[j].read_buffer.texture
      // bind texture to texture unit j and set uniform to that unit
      rl.SetShaderValueTexture(shader, location, texture)
    }
  }

  dummy_shader_index := (shader_index + 1) % sm.shader_count
  dummy_texture := sm.render_targets[dummy_shader_index].read_buffer.texture

  // draw the texture to fill the screen - this generates proper fragTexCoord (0,0) to (1,1)
  // use negative height to match the flipping done in draw_to_screen
  rl.DrawTextureRec(
    dummy_texture,
    rl.Rectangle{0, 0, f32(dummy_texture.width), -f32(dummy_texture.height)}, // negative height for consistency
    rl.Vector2{0, 0},
    rl.WHITE,
  )

  // end shader mode
  rl.EndShaderMode()

  // end texture mode if we were rendering to a target
  if target != nil {
    rl.EndTextureMode()
  }
}

// get the final output texture (from last shader's read buffer)
shader_manager_get_output_texture :: proc(sm: ^Shader_Manager) -> rl.Texture2D {
  if sm.shader_count > 0 {
    last_shader_index := sm.shader_count - 1
    texture := sm.render_targets[last_shader_index].read_buffer.texture
    return texture
  }
  return rl.Texture2D{}
}

// load and preprocess shaders - replaces // #include text-system with actual text-system.frag content
load_shader_with_preprocessing :: proc(sm: ^Shader_Manager, vertex_path: string, fragment_path: string) -> rl.Shader {
  // Load vertex shader content
  vertex_data, vertex_ok := sm.file_reader(vertex_path)
  if !vertex_ok {
    log.errorf("Failed to read vertex shader: %s", vertex_path)
    return rl.Shader{}
  }
  defer delete(vertex_data)

  // Load fragment shader content
  fragment_data, fragment_ok := sm.file_reader(fragment_path)
  if !fragment_ok {
    log.errorf("Failed to read fragment shader: %s", fragment_path)
    return rl.Shader{}
  }
  defer delete(fragment_data)

  // Load text system chunk
  text_system_frag_path := "shaders/v100/text-system.frag"
  when USE_WEBGL2 {
    text_system_frag_path = "shaders/v300es/text-system.frag"
  }
  text_system_data, text_system_ok := sm.file_reader(text_system_frag_path)
  if !text_system_ok {
    log.errorf("Failed to read text-system.frag")
    return rl.Shader{}
  }
  defer delete(text_system_data)

  // Convert to strings
  vertex_source := string(vertex_data)
  fragment_source := string(fragment_data)
  text_system_source := string(text_system_data)

  // Replace // #include text-system with actual content
  processed_fragment, _ := strings.replace_all(fragment_source, "// #include text-system", text_system_source)

  // Convert to C strings for Raylib
  vertex_cstr := strings.clone_to_cstring(vertex_source)
  defer delete(vertex_cstr)

  fragment_cstr := strings.clone_to_cstring(processed_fragment)
  defer delete(fragment_cstr)

  return rl.LoadShaderFromMemory(vertex_cstr, fragment_cstr)
}

// convenience function to render the final output to screen
shader_manager_draw_to_screen :: proc(sm: ^Shader_Manager, position: rl.Vector2 = {0, 0}, tint: rl.Color = rl.WHITE) {
  if sm.shader_count == 0 do return

  texture := shader_manager_get_output_texture(sm)

  if texture.id != 0 {
    // draw texture flipped vertically (Raylib render texture convention)
    rl.DrawTextureRec(
      texture,
      rl.Rectangle{
        0, 0,
        f32(texture.width),
        -f32(texture.height), // negative height to flip
      },
      position,
      tint,
    )
  }
}
