package gamelogic

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

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
  delta_time: f32, //                               time since last frame
  frame: i32, //                                    common uniform values
  fps: f32, //                                      current FPS (updated every frame)
  resolution: rl.Vector2, //                        common uniform values
  mouse_pos: rl.Vector2, //                         mouse position uniform
  mouse_target: rl.Vector2, //                      mouse target for interpolation
  mouse_lerp: rl.Vector2, //                        interpolated mouse position uniform
  mouse_lerp_factor: f32, //                        mouse interpolation factor
  additional_uniforms: map[string]Uniform_Value, // common uniform values



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
  sm.time = 0.0
  sm.delta_time = 0.0
  sm.frame = 0
  sm.fps = 0.0
  sm.mouse_pos = rl.Vector2{0, 0}
  sm.mouse_target = rl.Vector2{0, 0}
  sm.mouse_lerp = rl.Vector2{0, 0}
  sm.mouse_lerp_factor = 0.05 // framerate-independent lerp factor (0.03 = smooth, 0.2 = snappy)


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
      fmt.printf("Failed to create render targets for shader %d", i)
      shader_manager_destroy(sm)
      return false
    }

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
      fmt.printf("Vertex shader file not found: %s", vertex_shader_path)
      shader_manager_destroy(sm)
      return false
    }

    fragment_cstr := strings.clone_to_cstring(fragment_shader_paths[i])
    defer delete(fragment_cstr)

    if !rl.FileExists(fragment_cstr) {
      fmt.printf("Fragment shader file not found: %s", fragment_shader_paths[i])
      shader_manager_destroy(sm)
      return false
    }

    sm.shaders[i] = load_shader_with_preprocessing(sm, vertex_shader_path, fragment_shader_paths[i])

    if sm.shaders[i].id == 0 {
      fmt.printf("Failed to load shader %d: vertex=%s, fragment=%s", i, vertex_shader_path, fragment_shader_paths[i])
      shader_manager_destroy(sm)
      return false
    }

    // initialize uniform location map for this shader
    sm.uniform_locations[i] = make(map[string]i32)

    // get locations for common uniforms
    sm.uniform_locations[i]["time"] = rl.GetShaderLocation(sm.shaders[i], "time")
    sm.uniform_locations[i]["delta_time"] = rl.GetShaderLocation(sm.shaders[i], "delta_time")
    sm.uniform_locations[i]["frame"] = rl.GetShaderLocation(sm.shaders[i], "frame")
    sm.uniform_locations[i]["fps"] = rl.GetShaderLocation(sm.shaders[i], "fps")
    sm.uniform_locations[i]["resolution"] = rl.GetShaderLocation(sm.shaders[i], "resolution")
    sm.uniform_locations[i]["mouse"] = rl.GetShaderLocation(sm.shaders[i], "mouse")
    sm.uniform_locations[i]["mouselerp"] = rl.GetShaderLocation(sm.shaders[i], "mouselerp")
    sm.uniform_locations[i]["ship_world_position"] = rl.GetShaderLocation(sm.shaders[i], "ship_world_position")
    sm.uniform_locations[i]["ship_screen_position"] = rl.GetShaderLocation(sm.shaders[i], "ship_screen_position")
    sm.uniform_locations[i]["camera_position"] = rl.GetShaderLocation(sm.shaders[i], "camera_position")
    sm.uniform_locations[i]["ship_direction"] = rl.GetShaderLocation(sm.shaders[i], "ship_direction")
    sm.uniform_locations[i]["ship_velocity"] = rl.GetShaderLocation(sm.shaders[i], "ship_velocity")
    sm.uniform_locations[i]["ship_speed"] = rl.GetShaderLocation(sm.shaders[i], "ship_speed")

    fmt.printf("Shader %d common uniforms: time=%d, frame=%d, resolution=%d, mouse=%d, mouselerp=%d",
      i,
      sm.uniform_locations[i]["time"],
      sm.uniform_locations[i]["delta_time"],
      sm.uniform_locations[i]["frame"],
      sm.uniform_locations[i]["fps"],
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
      fmt.printf("Shader %d: %s location = %d (stored as key: '%s')", i, uniform_name, location, uniform_name)
    }
  }

  fmt.printf("Shader manager '%s' initialized with %d shaders", sm.name, sm.shader_count)
  return true
}

// high-level initialization helper that handles file existence checking
shader_manager_init_from_paths :: proc(
    name: string,
    vertex_path: string,
    fragment_paths: []string,
    width, height: i32,
    file_reader: File_Reader,
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
    fmt.printf("Shader manager '%s': some shader files not found", name)
    return shader_manager, false
  }

  // Initialize the shader manager
  success := shader_manager_init(&shader_manager, name, vertex_path, fragment_paths, width, height, file_reader)

  if !success {
    shader_manager_destroy(&shader_manager)
    return shader_manager, false
  }

  return shader_manager, true
}

// hot reload shaders
shader_manager_reload_shaders :: proc(sm: ^Shader_Manager) -> bool {
  fmt.printf("=== HOT RELOADING SHADERS (%s) ===", sm.name)

  // unload existing shaders
  for i in 0..<sm.shader_count {
    if sm.shaders[i].id != 0 {
      fmt.printf("Unloading old shader %d (ID: %d)", i, sm.shaders[i].id)
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
    fmt.printf("Reloading shader %d: vertex=%s, fragment=%s",
      i, sm.vertex_shader_path, sm.fragment_shader_paths[i],
    )

    vertex_cstr := strings.clone_to_cstring(sm.vertex_shader_path)
    defer delete(vertex_cstr)
    fragment_cstr := strings.clone_to_cstring(sm.fragment_shader_paths[i])
    defer delete(fragment_cstr)

    sm.shaders[i] = load_shader_with_preprocessing(sm, sm.vertex_shader_path, sm.fragment_shader_paths[i])

    if sm.shaders[i].id == 0 {
      fmt.printf(
        "RELOAD FAILED: Shader %d failed to compile: vertex=%s, fragment=%s",
        i, sm.vertex_shader_path, sm.fragment_shader_paths[i],
      )
      return false
    }

    fmt.printf("Shader %d reloaded successfully (new ID: %d)", i, sm.shaders[i].id)

    // get locations for common uniforms
    sm.uniform_locations[i]["time"] = rl.GetShaderLocation(sm.shaders[i], "time")
    sm.uniform_locations[i]["delta_time"] = rl.GetShaderLocation(sm.shaders[i], "delta_time")
    sm.uniform_locations[i]["frame"] = rl.GetShaderLocation(sm.shaders[i], "frame")
    sm.uniform_locations[i]["fps"] = rl.GetShaderLocation(sm.shaders[i], "fps")
    sm.uniform_locations[i]["resolution"] = rl.GetShaderLocation(sm.shaders[i], "resolution")
    sm.uniform_locations[i]["mouse"] = rl.GetShaderLocation(sm.shaders[i], "mouse")
    sm.uniform_locations[i]["mouselerp"] = rl.GetShaderLocation(sm.shaders[i], "mouselerp")
    sm.uniform_locations[i]["ship_world_position"] = rl.GetShaderLocation(sm.shaders[i], "ship_world_position")
    sm.uniform_locations[i]["ship_screen_position"] = rl.GetShaderLocation(sm.shaders[i], "ship_screen_position")
    sm.uniform_locations[i]["camera_position"] = rl.GetShaderLocation(sm.shaders[i], "camera_position")
    sm.uniform_locations[i]["ship_direction"] = rl.GetShaderLocation(sm.shaders[i], "ship_direction")
    sm.uniform_locations[i]["ship_velocity"] = rl.GetShaderLocation(sm.shaders[i], "ship_velocity")
    sm.uniform_locations[i]["ship_speed"] = rl.GetShaderLocation(sm.shaders[i], "ship_speed")

    fmt.printf(
      "RELOADED Shader %d common uniforms: time=%d, frame=%d, resolution=%d, mouse=%d, mouselerp=%d",
      i,
      sm.uniform_locations[i]["time"],
      sm.uniform_locations[i]["delta_time"],
      sm.uniform_locations[i]["frame"],
      sm.uniform_locations[i]["fps"],
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
      fmt.printf("RELOADED Shader %d: %s location = %d", i, uniform_name, location)
    }
  }

  fmt.printf("=== SHADER HOT RELOAD COMPLETE (%s) ===", sm.name)
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

  fmt.printf("Shader manager '%s' destroyed", sm.name)
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
  sm.delta_time = delta_time
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
  }

  fmt.printf("Shader manager '%s' resized to %dx%d", sm.name, new_width, new_height)
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
  shader_manager_apply_uniform(shader, locations["delta_time"], sm.delta_time)
  shader_manager_apply_uniform(shader, locations["frame"], sm.frame)
  shader_manager_apply_uniform(shader, locations["fps"], sm.fps)
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

// resolve shader path to correct version directory (v100 or v300es)
resolve_shader_path :: proc(relative_path: string, allocator := context.allocator) -> string {
  base_path := "shaders/v100/"
  when #config(USE_WEBGL2, false) {
    base_path = "shaders/v300es/"
  }
  return fmt.aprintf("%s%s", base_path, relative_path, allocator = allocator)
}

// process #include directives in shader source
process_shader_includes :: proc(sm: ^Shader_Manager, source: string, source_path: string, depth: int = 0) -> string {
  // nesting safe-guard
  if depth > 10 {
    fmt.printf("Maximum include depth exceeded (10) in %s", source_path)
    return source
  }

  if !strings.contains(source, "#include") {
    return source
  }

  builder := strings.builder_make()
  defer strings.builder_destroy(&builder)

  lines := strings.split_lines(source)
  defer delete(lines)

  for line_idx in 0..<len(lines) {
    line := lines[line_idx]
    trimmed_line := strings.trim_space(line)

    // look for #include directive
    // I think I'll support a commented out // #include in case I'm editing shaders
    // with some fucking annoying GLSL validator that keeps screaming at me
    if strings.has_prefix(trimmed_line, "#include ") || strings.has_prefix(trimmed_line, "// #include ") {
      // Extract filename from include directive
      include_filename := extract_include_filename(trimmed_line)
      if include_filename == "" {
        fmt.printf("Invalid #include directive at line %d in %s: %s", line_idx + 1, source_path, line)
        strings.write_string(&builder, line)
        strings.write_byte(&builder, '\n')
        continue
      }

      include_path := resolve_shader_path(include_filename)
      defer delete(include_path)

      include_data, include_ok := sm.file_reader(include_path)
      if !include_ok {
        fmt.printf("Failed to read include file: %s (referenced from %s)", include_path, source_path)
        strings.write_string(&builder, line)
        strings.write_byte(&builder, '\n')
        continue
      }
      defer delete(include_data)

      include_source := string(include_data)

      processed_include := process_shader_includes(sm, include_source, include_path, depth + 1)
      defer if processed_include != include_source do delete(processed_include)

      strings.write_string(&builder, processed_include)
      strings.write_byte(&builder, '\n')

      fmt.printf("Included %s into %s (depth %d)", include_path, source_path, depth)
    } else {
      strings.write_string(&builder, line)
      strings.write_byte(&builder, '\n')
    }
  }

  return strings.clone(strings.to_string(builder))
}

// extract filename from #include directive
extract_include_filename :: proc(line: string) -> string {
  trimmed := strings.trim_space(line)

  // remove comment prefix if present
  // TODO: improve this
  if strings.has_prefix(trimmed, "//") {
    trimmed = strings.trim_space(trimmed[2:])
  }

  // remove #include keyword
  if strings.has_prefix(trimmed, "#include") {
    trimmed = strings.trim_space(trimmed[8:])
  } else {
    return ""
  }

  // Extract filename (support both quoted and unquoted filenames)
  if strings.has_prefix(trimmed, "\"") && strings.has_suffix(trimmed, "\"") {
    // quoted filename: #include "filename.chunk.frag"
    return trimmed[1:len(trimmed)-1]
  } else if len(trimmed) > 0 && !strings.contains(trimmed, " ") {
    // unquoted filename: #include filename.chunk.frag
    return trimmed
  }

  return ""
}

// load and preprocess shaders - handles flexible #include system for .chunk.frag files
load_shader_with_preprocessing :: proc(sm: ^Shader_Manager, vertex_path: string, fragment_path: string) -> rl.Shader {
  // Load vertex shader content
  vertex_data, vertex_ok := sm.file_reader(vertex_path)
  if !vertex_ok {
    fmt.printf("Failed to read vertex shader: %s", vertex_path)
    return rl.Shader{}
  }
  defer delete(vertex_data)

  // Load fragment shader content
  fragment_data, fragment_ok := sm.file_reader(fragment_path)
  if !fragment_ok {
    fmt.printf("Failed to read fragment shader: %s", fragment_path)
    return rl.Shader{}
  }
  defer delete(fragment_data)

  // Convert to strings
  vertex_source := string(vertex_data)
  fragment_source := string(fragment_data)
  processed_fragment := process_shader_includes(sm, fragment_source, fragment_path)
  defer if processed_fragment != fragment_source do delete(processed_fragment)

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
