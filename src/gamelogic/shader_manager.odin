package gamelogic

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

// uniform value types that can be passed to the shaders
Uniform_Value :: union {
  f32,
  i32,
  rl.Vector2,
  rl.Vector3,
  rl.Vector4,
  rl.Texture2D,
}

// uniform definition for external specification
Uniform_Definition :: struct {
  name: string,
  value: Uniform_Value,
}

// pair of render targets for ping-pong rendering
Render_Target_Pair :: struct {
  read_buffer:  rl.RenderTexture2D,
  write_buffer: rl.RenderTexture2D,
}

// abstract shader Manager for multi-pass rendering with ping-pong buffers
Shader_Manager :: struct {
  name: string,                              // unique identifier for this shader manager instance
  render_targets: []Render_Target_Pair,      // render targets for each shader (double-buffered)
  shaders: []rl.Shader,                      // fragment shaders

  uniform_locations: []map[string]i32,       // uniform locations for each shader
  uniforms: map[string]Uniform_Value,        // all uniform values (externally managed)

  screen_width, screen_height: i32,          // screen dimensions

  vertex_shader_path: string,                // vertex shader path (reused for all frag shaders)
  fragment_shader_paths: []string,           // fragment shader paths
  shader_count: int,                         // number of fragment shaders

  prev_render_targets: []Render_Target_Pair, // previous frame render target state

  frame: i32,                                // current frame number
  prev_frame: i32,                           // previous frame number
  display_frame_a: i32,                      // stable frame A for display
  display_frame_b: i32,                      // stable frame B for display

  display_targets_a: []Render_Target_Pair,   // stable targets A for display (updates every 2 frames)
  display_targets_b: []Render_Target_Pair,   // stable targets B for display(updates every 2 frames)
  display_pair_ready: bool,                  // whether we have a stable pair to display

  file_reader: File_Reader,                  // global cross-platform & cross-env file reader function
}

// initialize the abstract shader manager
shader_manager_init :: proc(
    sm: ^Shader_Manager,
    name: string,
    vertex_shader_path: string,
    fragment_shader_paths: []string,
    uniform_definitions: []Uniform_Definition,
    width, height: i32,
    file_reader: File_Reader,
) -> bool {
  sm.name = name
  sm.vertex_shader_path = vertex_shader_path
  sm.fragment_shader_paths = make([]string, len(fragment_shader_paths))
  copy(sm.fragment_shader_paths, fragment_shader_paths)
  sm.file_reader = file_reader

  sm.shader_count = len(fragment_shader_paths)
  sm.screen_width = width
  sm.screen_height = height

  // initialize uniforms map with provided definitions
  sm.uniforms = make(map[string]Uniform_Value)
  for uniform_def in uniform_definitions {
    sm.uniforms[uniform_def.name] = uniform_def.value
  }

  // create render targets
  sm.render_targets = make([]Render_Target_Pair, sm.shader_count)

  // create previous frame render targets
  sm.prev_render_targets = make([]Render_Target_Pair, sm.shader_count)

  // create stable display frame pairs
  sm.display_targets_a = make([]Render_Target_Pair, sm.shader_count)
  sm.display_targets_b = make([]Render_Target_Pair, sm.shader_count)
  sm.display_pair_ready = false

  // initialize frame tracking
  sm.frame = 0
  sm.prev_frame = -1
  sm.display_frame_a = -1
  sm.display_frame_b = -1

  for i in 0..<sm.shader_count {
    // use 32-bit float render textures for better precision
    sm.render_targets[i].read_buffer = create_render_target(width, height, .UNCOMPRESSED_R32G32B32A32)
    sm.render_targets[i].write_buffer = create_render_target(width, height, .UNCOMPRESSED_R32G32B32A32)

    if sm.render_targets[i].read_buffer.id == 0 || sm.render_targets[i].write_buffer.id == 0 {
      Log(.ERROR, "RENDER TARGETS", "Failed to create render targets for shader %d", i)
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
      Log(.ERROR, "SHADER MANAGER", "Vertex shader file not found: %s", vertex_shader_path)
      shader_manager_destroy(sm)
      return false
    }

    fragment_cstr := strings.clone_to_cstring(fragment_shader_paths[i])
    defer delete(fragment_cstr)

    if !rl.FileExists(fragment_cstr) {
      Log(.ERROR, "SHADER MANAGER", "Fragment shader file not found: %s", fragment_shader_paths[i])
      shader_manager_destroy(sm)
      return false
    }

    sm.shaders[i] = load_shader_with_preprocessing(sm, vertex_shader_path, fragment_shader_paths[i])

    if sm.shaders[i].id == 0 {
      Log(.ERROR, "SHADER MANAGER", "Failed to load shader %d: vertex=%s, fragment=%s", i, vertex_shader_path, fragment_shader_paths[i])
      shader_manager_destroy(sm)
      return false
    }

    // initialize uniform location map for this shader
    sm.uniform_locations[i] = make(map[string]i32)

    // get locations for all defined uniforms
    for uniform_name, _ in sm.uniforms {
      name_cstr := strings.clone_to_cstring(uniform_name)
      defer delete(name_cstr)
      sm.uniform_locations[i][uniform_name] = rl.GetShaderLocation(sm.shaders[i], name_cstr)
    }

    // get locations for all prgm*Texture uniforms (every shader gets all texture uniforms)
    for j in 0..<sm.shader_count {
      uniform_name := fmt.aprintf("prgm%dTexture", j)
      cstr_name := strings.clone_to_cstring(uniform_name)
      defer delete(cstr_name)
      location := rl.GetShaderLocation(sm.shaders[i], cstr_name)
      sm.uniform_locations[i][uniform_name] = location
      Log(.SUCCESS, "SHADER MANAGER", "Shader %d: %s location = %d (stored as key: '%s')", i, uniform_name, location, uniform_name)
    }
  }

  Log(.SUCCESS, "SHADER MANAGER", "'%s' initialized with %d shaders", sm.name, sm.shader_count)
  return true
}

// high-level initialization helper that handles file existence checking
shader_manager_init_from_paths :: proc(
    name: string,
    vertex_path: string,
    fragment_paths: []string,
    uniform_definitions: []Uniform_Definition,
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
    Log(.ERROR, "SHADER MANAGER", "ERROR: '%s' -> some shader files not found", name)
    return shader_manager, false
  }

  // Initialize the shader manager
  success := shader_manager_init(&shader_manager, name, vertex_path, fragment_paths, uniform_definitions, width, height, file_reader)

  if !success {
    shader_manager_destroy(&shader_manager)
    return shader_manager, false
  }

  return shader_manager, true
}

// hot reload shaders
shader_manager_reload_shaders :: proc(sm: ^Shader_Manager) -> bool {
  if debug {
    Log(.SUCCESS, "SHADER MANAGER", "HOT RELOAD START (%s)", sm.name)
  }

  // unload existing shaders
  for i in 0..<sm.shader_count {
    if sm.shaders[i].id != 0 {
      Log(.SUCCESS, "SHADER MANAGER", "Unloading old shader %d (ID: %d)", i, sm.shaders[i].id)
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
    Log(.SUCCESS, "SHADER MANAGER", "Reloading shader %d: vertex=%s, fragment=%s", i, sm.vertex_shader_path, sm.fragment_shader_paths[i])

    vertex_cstr := strings.clone_to_cstring(sm.vertex_shader_path)
    defer delete(vertex_cstr)
    fragment_cstr := strings.clone_to_cstring(sm.fragment_shader_paths[i])
    defer delete(fragment_cstr)

    sm.shaders[i] = load_shader_with_preprocessing(sm, sm.vertex_shader_path, sm.fragment_shader_paths[i])

    if sm.shaders[i].id == 0 {
      Log(.ERROR, "SHADER MANAGER", "RELOAD FAILED: Shader %d failed to compile: vertex=%s, fragment=%s", i, sm.vertex_shader_path, sm.fragment_shader_paths[i])
      return false
    }

    Log(.SUCCESS, "SHADER MANAGER", "Shader %d reloaded successfully (new ID: %d)", i, sm.shaders[i].id)

    // get locations for all defined uniforms
    for uniform_name, _ in sm.uniforms {
      name_cstr := strings.clone_to_cstring(uniform_name)
      defer delete(name_cstr)
      sm.uniform_locations[i][uniform_name] = rl.GetShaderLocation(sm.shaders[i], name_cstr)
    }

    // get locations for all prgm*Texture uniforms
    for j in 0..<sm.shader_count {
      uniform_name := fmt.aprintf("prgm%dTexture", j)

      cstr_name := strings.clone_to_cstring(uniform_name)
      defer delete(cstr_name)

      location := rl.GetShaderLocation(sm.shaders[i], cstr_name)
      sm.uniform_locations[i][uniform_name] = location
      Log(.SUCCESS, "SHADER MANAGER", "RELOADED Shader %d: %s location = %d", i, uniform_name, location)
    }
  }

  Log(.SUCCESS, "SHADER MANAGER", "HOT RELOAD  END  (%s)", sm.name)
  return true
}

// destroy the abstract shader manager and clean up resources
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

  delete(sm.render_targets)
  delete(sm.prev_render_targets)
  delete(sm.display_targets_a)
  delete(sm.display_targets_b)

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

  // clean up uniforms
  delete(sm.uniforms)

  // clean up shader paths
  delete(sm.fragment_shader_paths)

  Log(.SUCCESS, "SHADER MANAGER", "'%s' destroyed", sm.name)
}

// resize render targets when screen size changes
shader_manager_resize :: proc(sm: ^Shader_Manager, new_width, new_height: i32) {
  sm.screen_width = new_width
  sm.screen_height = new_height

  // resize all render targets
  for &target in sm.render_targets {
    rl.UnloadRenderTexture(target.read_buffer)
    rl.UnloadRenderTexture(target.write_buffer)
    target.read_buffer = create_render_target(new_width, new_height, .UNCOMPRESSED_R32G32B32A32)
    target.write_buffer = create_render_target(new_width, new_height, .UNCOMPRESSED_R32G32B32A32)
  }

  Log(.SUCCESS, "SHADER MANAGER", "'%s' resized to (%dx%d)", sm.name, new_width, new_height)
}

// set a uniform value
shader_manager_set_uniform :: proc(sm: ^Shader_Manager, name: string, value: Uniform_Value) {
  sm.uniforms[name] = value

  // update uniform locations for all shaders if not already cached
  for i in 0..<sm.shader_count {
    if name not_in sm.uniform_locations[i] {
      name_cstr := strings.clone_to_cstring(name)
      defer delete(name_cstr)
      sm.uniform_locations[i][name] = rl.GetShaderLocation(sm.shaders[i], name_cstr)
    }
  }
}

// get a uniform value
shader_manager_get_uniform :: proc(sm: ^Shader_Manager, name: string) -> (Uniform_Value, bool) {
  value, ok := sm.uniforms[name]
  return value, ok
}

// update multiple uniforms at once
shader_manager_update_uniforms :: proc(sm: ^Shader_Manager, uniform_definitions: []Uniform_Definition) {
  for uniform_def in uniform_definitions {
    shader_manager_set_uniform(sm, uniform_def.name, uniform_def.value)
  }
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

// main rendering function - performs simple linear multi-pass rendering and returns output texture
shader_manager_render :: proc(sm: ^Shader_Manager) -> rl.Texture2D {
  if sm.shader_count == 0 do return rl.Texture2D{}

  // update frame tracking
  sm.prev_frame = sm.frame
  sm.frame += 1

  // capture previous frame state before rendering
  for i in 0..<sm.shader_count {
    sm.prev_render_targets[i] = sm.render_targets[i]
  }

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

  // set all uniforms
  for name, value in sm.uniforms {
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
  // use negative height to match the flipping done in the original draw_to_screen
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
    Log(.ERROR, "SHADER MANAGER", "Maximum include depth exceeded (10) in %s", source_path)
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
    // support commented out // #include for editing with GLSL validators
    if strings.has_prefix(trimmed_line, "#include ") || strings.has_prefix(trimmed_line, "// #include ") {
      // Extract filename from include directive
      include_filename := extract_include_filename(trimmed_line)
      if include_filename == "" {
        Log(.ERROR, "SHADER MANAGER", "Invalid #include directive at line %d in %s: %s", line_idx + 1, source_path, line)
        strings.write_string(&builder, line)
        strings.write_byte(&builder, '\n')
        continue
      }

      include_path := resolve_shader_path(include_filename)
      defer delete(include_path)

      include_data, include_ok := sm.file_reader(include_path)
      if !include_ok {
        Log(.ERROR, "SHADER MANAGER", "Failed to read include file: %s (referenced from %s)", include_path, source_path)
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

      Log(.SUCCESS, "SHADER MANAGER", "Included %s into %s (depth %d)", include_path, source_path, depth)
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
    Log(.ERROR, "SHADER MANAGER", "Failed to read vertex shader: %s", vertex_path)
    return rl.Shader{}
  }
  defer delete(vertex_data)

  // Load fragment shader content
  fragment_data, fragment_ok := sm.file_reader(fragment_path)
  if !fragment_ok {
    Log(.ERROR, "SHADER MANAGER", "Failed to read fragment shader: %s", fragment_path)
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
