#+feature dynamic-literals
package gamelogic

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

Bloom_Config :: struct {
  threshold:     f32, // Brightness threshold for bloom
  intensity:     f32, // Bloom intensity multiplier
  strength:      f32, // Final bloom strength when compositing
  exposure:      f32, // Exposure/tone mapping
  radius:        f32, // Bloom radius/spread (scales blur kernel size)
  mip_levels:    int, // Number of MIP levels (typically 5-6)
  mip_weights:   []f32, // Weight for each MIP level during upsampling
}

Bloom_Mip_Level :: struct {
  read_buffer:  rl.RenderTexture2D,  // ping-pong reaad buffer
  write_buffer: rl.RenderTexture2D,  // ping-pong write buffer
  width:        i32,
  height:       i32,
}

Bloom_Effect :: struct {
  config: Bloom_Config,
  mip_levels: []Bloom_Mip_Level,

  // shaders for different passes
  bright_pass_shader:  rl.Shader,
  downsample_shader:   rl.Shader,
  upsample_shader:     rl.Shader,
  composite_shader:    rl.Shader,

  // uniform locations (cached for performance)
  bright_pass_uniforms: map[string]i32,
  downsample_uniforms:  map[string]i32,
  upsample_uniforms:    map[string]i32,
  composite_uniforms:   map[string]i32,

  // screen dimensions
  screen_width:  i32,
  screen_height: i32,

  // file reader
  file_reader: File_Reader,

  // init status
  initialized: bool,
}

DEFAULT_BLOOM_CONFIG :: Bloom_Config {
  threshold = 0.3,
  intensity = 0.3,
  strength = 1.7,
  exposure = 3.5,
  radius = 1.3,
  mip_levels = 5,
  mip_weights = {}, // set in bloom_effect_init_default
}

// parameter constraints MicroUI sliders
BLOOM_PARAMETER_CONSTRAINTS := map[string]Parameter_Constraint{
  "threshold" = {type = .FLOAT, min_val = 0.0, max_val = 2.0, step = 0.01, default = 0.3},
  "intensity" = {type = .FLOAT, min_val = 0.0, max_val = 5.0, step = 0.1, default = 0.3},
  "strength"  = {type = .FLOAT, min_val = 0.0, max_val = 10.0, step = 0.1, default = 1.7},
  "exposure"  = {type = .FLOAT, min_val = 0.1, max_val = 10.0, step = 0.1, default = 3.5},
  "radius"    = {type = .FLOAT, min_val = 0.1, max_val = 5.0, step = 0.1, default = 1.3},
  "mip_levels"= {type = .INT, min_val = 2, max_val = 8, step = 1, default = 5},
}

bloom_effect_init :: proc(bloom: ^Bloom_Effect, config: Bloom_Config, width, height: i32, file_reader: File_Reader) -> bool {
  bloom.config = config
  bloom.screen_width = width
  bloom.screen_height = height
  bloom.file_reader = file_reader

  if config.mip_levels < 2 || config.mip_levels > 8 {
    fmt.printf("ERROR: Bloom: Invalid MIP levels count: %d (must be 2-8)\n", config.mip_levels)
    return false
  }

  if len(config.mip_weights) != config.mip_levels {
    fmt.printf(
      "ERROR: Bloom: MIP weights count (%d) doesn't match MIP levels (%d)\n",
      len(config.mip_weights), config.mip_levels,
    )
    return false
  }

  if !bloom_load_shaders(bloom) {
    fmt.printf("ERROR: Bloom: Failed to load shaders\n")
    bloom_effect_destroy(bloom)
    return false
  }

  // create MIP chain render targets
  if !bloom_create_mip_chain(bloom) {
    fmt.printf("ERROR: Bloom: Failed to create MIP chain\n")
    bloom_effect_destroy(bloom)
    return false
  }

  bloom.initialized = true

  fmt.printf("========== BLOOM EFFECT INITIALIZED ==========\n")
  fmt.printf("Screen Resolution: %dx%d\n", width, height)
  fmt.printf("MIP Levels: %d\n", config.mip_levels)
  fmt.printf(
    "Config: threshold=%.2f, intensity=%.2f, strength=%.2f, exposure=%.2f\n",
    config.threshold, config.intensity, config.strength, config.exposure,
  )

  for i in 0..<config.mip_levels {
    fmt.printf(
      "MIP Level %d: %dx%d (read: %d, write: %d)\n",
      i, bloom.mip_levels[i].width, bloom.mip_levels[i].height,
      bloom.mip_levels[i].read_buffer.texture.id, bloom.mip_levels[i].write_buffer.texture.id,
    )
  }

  fmt.printf(
    "Shaders loaded: bright_pass=%d, downsample=%d, upsample=%d, composite=%d\n",
    bloom.bright_pass_shader.id, bloom.downsample_shader.id,
    bloom.upsample_shader.id, bloom.composite_shader.id,
  )
  fmt.printf("===============================================\n")

  return true
}

// global static weights to avoid dangling pointer issues
@(private)
STATIC_MIP_WEIGHTS := [5]f32{1.0, 1.0, 1.0, 1.0, 1.0}

bloom_effect_init_default :: proc(bloom: ^Bloom_Effect, width, height: i32, file_reader: File_Reader) -> bool {
  config := DEFAULT_BLOOM_CONFIG
  // global static weights array to avoid dangling pointer
  config.mip_weights = STATIC_MIP_WEIGHTS[:config.mip_levels]
  return bloom_effect_init(bloom, config, width, height, file_reader)
}

bloom_load_shaders :: proc(bloom: ^Bloom_Effect) -> bool {
  vertex_path := resolve_shader_path("default.vert")
  defer delete(vertex_path)

  bright_pass_path := resolve_shader_path("bloom-bright-pass.frag")
  defer delete(bright_pass_path)

  downsample_path := resolve_shader_path("bloom-downsample.frag")
  defer delete(downsample_path)

  upsample_path := resolve_shader_path("bloom-upsample.frag")
  defer delete(upsample_path)

  composite_path := resolve_shader_path("bloom-composite.frag")
  defer delete(composite_path)

  bloom.bright_pass_shader = load_shader(bloom.file_reader, vertex_path, bright_pass_path)
  bloom.downsample_shader = load_shader(bloom.file_reader, vertex_path, downsample_path)
  bloom.upsample_shader = load_shader(bloom.file_reader, vertex_path, upsample_path)
  bloom.composite_shader = load_shader(bloom.file_reader, vertex_path, composite_path)

  if bloom.bright_pass_shader.id == 0 ||bloom.downsample_shader.id == 0 ||
    bloom.upsample_shader.id == 0 || bloom.composite_shader.id == 0 {
    fmt.printf("Bloom: Failed to load one or more shaders")
    return false
  }

  bloom_cache_uniform_locations(bloom)

  return true
}

bloom_cache_uniform_locations :: proc(bloom: ^Bloom_Effect) {
  if bloom.bright_pass_uniforms == nil {
    bloom.bright_pass_uniforms = make(map[string]i32)
  } else {
    clear(&bloom.bright_pass_uniforms)
  }

  if bloom.downsample_uniforms == nil {
    bloom.downsample_uniforms = make(map[string]i32)
  } else {
    clear(&bloom.downsample_uniforms)
  }

  if bloom.upsample_uniforms == nil {
    bloom.upsample_uniforms = make(map[string]i32)
  } else {
    clear(&bloom.upsample_uniforms)
  }

  if bloom.composite_uniforms == nil {
    bloom.composite_uniforms = make(map[string]i32)
  } else {
    clear(&bloom.composite_uniforms)
  }

  // bright pass uniforms
  bloom.bright_pass_uniforms["inputTexture"] = rl.GetShaderLocation(bloom.bright_pass_shader, "inputTexture")
  bloom.bright_pass_uniforms["threshold"] = rl.GetShaderLocation(bloom.bright_pass_shader, "threshold")
  bloom.bright_pass_uniforms["intensity"] = rl.GetShaderLocation(bloom.bright_pass_shader, "intensity")

  // downsample uniforms
  bloom.downsample_uniforms["inputTexture"] = rl.GetShaderLocation(bloom.downsample_shader, "inputTexture")
  bloom.downsample_uniforms["texelSize"] = rl.GetShaderLocation(bloom.downsample_shader, "texelSize")
  bloom.downsample_uniforms["radius"] = rl.GetShaderLocation(bloom.downsample_shader, "radius")

  // upsample uniforms
  bloom.upsample_uniforms["inputTexture"] = rl.GetShaderLocation(bloom.upsample_shader, "inputTexture")
  bloom.upsample_uniforms["lowerMipTexture"] = rl.GetShaderLocation(bloom.upsample_shader, "lowerMipTexture")
  bloom.upsample_uniforms["texelSize"] = rl.GetShaderLocation(bloom.upsample_shader, "texelSize")
  bloom.upsample_uniforms["mipWeight"] = rl.GetShaderLocation(bloom.upsample_shader, "mipWeight")
  bloom.upsample_uniforms["radius"] = rl.GetShaderLocation(bloom.upsample_shader, "radius")

  // composite uniforms
  bloom.composite_uniforms["originalTexture"] = rl.GetShaderLocation(bloom.composite_shader, "originalTexture")
  bloom.composite_uniforms["bloomTexture"] = rl.GetShaderLocation(bloom.composite_shader, "bloomTexture")
  bloom.composite_uniforms["bloomStrength"] = rl.GetShaderLocation(bloom.composite_shader, "bloomStrength")
  bloom.composite_uniforms["exposure"] = rl.GetShaderLocation(bloom.composite_shader, "exposure")
}

bloom_create_mip_chain :: proc(bloom: ^Bloom_Effect) -> bool {
  // clean up existing MIP levels first to prevent memory leaks
  if bloom.mip_levels != nil {
    for &level in bloom.mip_levels {
      if level.read_buffer.id != 0 {
        rl.UnloadRenderTexture(level.read_buffer)
      }
      if level.write_buffer.id != 0 {
        rl.UnloadRenderTexture(level.write_buffer)
      }
    }
    delete(bloom.mip_levels)
  }

  bloom.mip_levels = make([]Bloom_Mip_Level, bloom.config.mip_levels)

  current_width := bloom.screen_width
  current_height := bloom.screen_height

  for i in 0..<bloom.config.mip_levels {
    if i > 0 {
      current_width = max(current_width / 2, 1)
      current_height = max(current_height / 2, 1)
    }

    bloom.mip_levels[i].width = current_width
    bloom.mip_levels[i].height = current_height

    // create ping-pong buffers
    bloom.mip_levels[i].read_buffer = LoadRT_WithFallback(current_width, current_height, .UNCOMPRESSED_R32G32B32A32)
    bloom.mip_levels[i].write_buffer = LoadRT_WithFallback(current_width, current_height, .UNCOMPRESSED_R32G32B32A32)

    if bloom.mip_levels[i].read_buffer.id == 0 || bloom.mip_levels[i].write_buffer.id == 0 {
      fmt.printf("ERROR: Bloom: Failed to create MIP level %d render targets (%dx%d)\n",
        i, current_width, current_height)
      return false
    }

    // set texture filtering for both buffers
    rl.SetTextureFilter(bloom.mip_levels[i].read_buffer.texture, .BILINEAR)
    rl.SetTextureWrap(bloom.mip_levels[i].read_buffer.texture, .CLAMP)
    rl.SetTextureFilter(bloom.mip_levels[i].write_buffer.texture, .BILINEAR)
    rl.SetTextureWrap(bloom.mip_levels[i].write_buffer.texture, .CLAMP)

    rl.BeginTextureMode(bloom.mip_levels[i].read_buffer)
    defer rl.EndTextureMode()

    rl.ClearBackground(rl.Color{0, 0, 0, 0})

    rl.BeginTextureMode(bloom.mip_levels[i].write_buffer)
    defer rl.EndTextureMode()

    rl.ClearBackground(rl.Color{0, 0, 0, 0})
  }

  return true
}

bloom_effect_apply :: proc(bloom: ^Bloom_Effect, input_texture: rl.Texture2D) -> rl.Texture2D {
  if !bloom.initialized {
    fmt.printf("WARNING: Bloom: Effect not initialized, returning original texture\n")
    return input_texture
  }

  // pass 1: high pass filter
  bloom_render_bright_pass(bloom, input_texture)

  // pass 2: downsample chain (create MIP levels)
  bloom_render_downsample_chain(bloom)

  // pass 3: upsample chain (blur and combine MIP levels)
  bloom_render_upsample_chain(bloom)

  final_texture := bloom.mip_levels[0].read_buffer.texture

  return final_texture
}

bloom_effect_composite :: proc(bloom: ^Bloom_Effect, original_texture: rl.Texture2D, bloom_texture: rl.Texture2D, output_target: ^rl.RenderTexture2D) {
  if !bloom.initialized {
    fmt.printf("WARNING: Bloom: Effect not initialized, skipping composite\n")
    return
  }

  rl.BeginTextureMode(output_target^)
  defer rl.EndTextureMode()

  rl.ClearBackground(rl.Color{0, 0, 0, 0})

  rl.BeginShaderMode(bloom.composite_shader)
  defer rl.EndShaderMode()

  // set uniforms
  rl.SetShaderValueTexture(bloom.composite_shader, bloom.composite_uniforms["originalTexture"], original_texture)
  rl.SetShaderValueTexture(bloom.composite_shader, bloom.composite_uniforms["bloomTexture"], bloom_texture)

  strength := bloom.config.strength
  exposure := bloom.config.exposure
  rl.SetShaderValue(bloom.composite_shader, bloom.composite_uniforms["bloomStrength"], &strength, .FLOAT)
  rl.SetShaderValue(bloom.composite_shader, bloom.composite_uniforms["exposure"], &exposure, .FLOAT)

  // draw fullscreen quad scaled to composite target dimensions
  draw_to_rt_scaled(original_texture, output_target^)
}

bloom_render_bright_pass :: proc(bloom: ^Bloom_Effect, input_texture: rl.Texture2D) {
  // write to MIP level 0 write buffer
  rl.BeginTextureMode(bloom.mip_levels[0].write_buffer)
  defer rl.EndTextureMode()

  rl.ClearBackground(rl.Color{0, 0, 0, 0})

  rl.BeginShaderMode(bloom.bright_pass_shader)
  defer rl.EndShaderMode()

  // set uniforms
  rl.SetShaderValueTexture(bloom.bright_pass_shader, bloom.bright_pass_uniforms["inputTexture"], input_texture)

  threshold := bloom.config.threshold
  intensity := bloom.config.intensity
  rl.SetShaderValue(bloom.bright_pass_shader, bloom.bright_pass_uniforms["threshold"], &threshold, .FLOAT)
  rl.SetShaderValue(bloom.bright_pass_shader, bloom.bright_pass_uniforms["intensity"], &intensity, .FLOAT)

  // draw fullscreen quad scaled to MIP level 0 dimensions
  draw_to_rt_scaled(input_texture, bloom.mip_levels[0].write_buffer)

  // swap buffers after bright pass
  temp := bloom.mip_levels[0].read_buffer
  bloom.mip_levels[0].read_buffer = bloom.mip_levels[0].write_buffer
  bloom.mip_levels[0].write_buffer = temp
}

bloom_render_downsample_chain :: proc(bloom: ^Bloom_Effect) {
  for i in 1..<bloom.config.mip_levels {
    source_level := &bloom.mip_levels[i-1]
    target_level := &bloom.mip_levels[i]

    // write to target level's write buffer, read from source level's read buffer
    rl.BeginTextureMode(target_level.write_buffer)
    defer rl.EndTextureMode()

    rl.ClearBackground(rl.Color{0, 0, 0, 0})

    rl.BeginShaderMode(bloom.downsample_shader)
    defer rl.EndShaderMode()

    // set uniforms - read from source level's read buffer
    rl.SetShaderValueTexture(bloom.downsample_shader, bloom.downsample_uniforms["inputTexture"], source_level.read_buffer.texture)

    texel_size := rl.Vector2{1.0 / f32(source_level.width), 1.0 / f32(source_level.height)}
    rl.SetShaderValue(bloom.downsample_shader, bloom.downsample_uniforms["texelSize"], &texel_size, .VEC2)

    radius := bloom.config.radius
    rl.SetShaderValue(bloom.downsample_shader, bloom.downsample_uniforms["radius"], &radius, .FLOAT)

    // draw fullscreen quad scaled to target level dimensions
    draw_to_rt_scaled(source_level.read_buffer.texture, target_level.write_buffer)

    // swap buffers after downsample
    temp := target_level.read_buffer
    target_level.read_buffer = target_level.write_buffer
    target_level.write_buffer = temp
  }
}

bloom_render_upsample_chain :: proc(bloom: ^Bloom_Effect) {
  // start from the smallest MIP and work back up
  for i := bloom.config.mip_levels - 2; i >= 0; i -= 1 {
    source_level := &bloom.mip_levels[i+1]  // smaller/lower resolution level
    target_level := &bloom.mip_levels[i]    // larger/higher resolution level

    // write to target level's write buffer
    rl.BeginTextureMode(target_level.write_buffer)
    defer rl.EndTextureMode()

    rl.ClearBackground(rl.Color{0, 0, 0, 0})

    rl.BeginShaderMode(bloom.upsample_shader)
    defer rl.EndShaderMode()

    // set shader uniforms
    // inputTexture: the smaller mip level we're upsampling from (read buffer)
    rl.SetShaderValueTexture(bloom.upsample_shader, bloom.upsample_uniforms["inputTexture"], source_level.read_buffer.texture)

    // lowerMipTexture: the existing content at this level from downsample pass (read buffer)
    rl.SetShaderValueTexture(bloom.upsample_shader, bloom.upsample_uniforms["lowerMipTexture"], target_level.read_buffer.texture)

    // texelSize: for proper filtering based on source level size
    texel_size := rl.Vector2{1.0 / f32(source_level.width), 1.0 / f32(source_level.height)}
    rl.SetShaderValue(bloom.upsample_shader, bloom.upsample_uniforms["texelSize"], &texel_size, .VEC2)

    // mipWeight: weight for combining this mip level
    mip_weight := bloom.config.mip_weights[i+1]
    rl.SetShaderValue(bloom.upsample_shader, bloom.upsample_uniforms["mipWeight"], &mip_weight, .FLOAT)

    // radius: bloom spread/kernel size multiplier
    radius := bloom.config.radius
    rl.SetShaderValue(bloom.upsample_shader, bloom.upsample_uniforms["radius"], &radius, .FLOAT)

    // draw fullscreen quad to apply the upsample shader
    draw_to_rt_scaled(source_level.read_buffer.texture, target_level.write_buffer)

    // swap buffers after upsample
    temp := target_level.read_buffer
    target_level.read_buffer = target_level.write_buffer
    target_level.write_buffer = temp
  }
}

bloom_effect_resize :: proc(bloom: ^Bloom_Effect, new_width, new_height: i32) {
  if !bloom.initialized do return

  bloom.screen_width = new_width
  bloom.screen_height = new_height

  bloom_create_mip_chain(bloom)

  fmt.printf("Bloom effect resized to %dx%d\n", new_width, new_height)
}

bloom_effect_update_config :: proc(bloom: ^Bloom_Effect, config: Bloom_Config) {
  bloom.config = config
}

bloom_effect_hot_reload :: proc(bloom: ^Bloom_Effect) -> bool {
  if !bloom.initialized do return false

  fmt.printf("=== HOT RELOADING BLOOM SHADERS ===\n")

  // unload existing shaders
  if bloom.bright_pass_shader.id != 0 {
    fmt.printf("Unloading old bright pass shader (ID: %d)\n", bloom.bright_pass_shader.id)
    rl.UnloadShader(bloom.bright_pass_shader)
  }
  if bloom.downsample_shader.id != 0 {
    fmt.printf("Unloading old downsample shader (ID: %d)\n", bloom.downsample_shader.id)
    rl.UnloadShader(bloom.downsample_shader)
  }
  if bloom.upsample_shader.id != 0 {
    fmt.printf("Unloading old upsample shader (ID: %d)\n", bloom.upsample_shader.id)
    rl.UnloadShader(bloom.upsample_shader)
  }
  if bloom.composite_shader.id != 0 {
    fmt.printf("Unloading old composite shader (ID: %d)\n", bloom.composite_shader.id)
    rl.UnloadShader(bloom.composite_shader)
  }

  // clear old uniform locations
  if bloom.bright_pass_uniforms != nil do clear(&bloom.bright_pass_uniforms)
  if bloom.downsample_uniforms != nil do clear(&bloom.downsample_uniforms)
  if bloom.upsample_uniforms != nil do clear(&bloom.upsample_uniforms)
  if bloom.composite_uniforms != nil do clear(&bloom.composite_uniforms)

  // reload all shaders (bloom_load_shaders will call bloom_cache_uniform_locations to recreate maps)
  if !bloom_load_shaders(bloom) {
    fmt.printf("ERROR: Bloom hot reload: Failed to reload shaders\n")
    return false
  }

  fmt.printf("=== BLOOM HOT RELOAD COMPLETE ===\n")
  return true
}

bloom_effect_destroy :: proc(bloom: ^Bloom_Effect) {
  if !bloom.initialized do return

  // unload shaders
  if bloom.bright_pass_shader.id != 0 {
    rl.UnloadShader(bloom.bright_pass_shader)
  }
  if bloom.downsample_shader.id != 0 {
    rl.UnloadShader(bloom.downsample_shader)
  }
  if bloom.upsample_shader.id != 0 {
    rl.UnloadShader(bloom.upsample_shader)
  }
  if bloom.composite_shader.id != 0 {
    rl.UnloadShader(bloom.composite_shader)
  }

  // unload render targets
  for &level in bloom.mip_levels {
    if level.read_buffer.id != 0 {
      rl.UnloadRenderTexture(level.read_buffer)
    }
    if level.write_buffer.id != 0 {
      rl.UnloadRenderTexture(level.write_buffer)
    }
  }
  delete(bloom.mip_levels)

  // clean up uniform location maps
  if bloom.bright_pass_uniforms != nil do delete(bloom.bright_pass_uniforms)
  if bloom.downsample_uniforms != nil do delete(bloom.downsample_uniforms)
  if bloom.upsample_uniforms != nil do delete(bloom.upsample_uniforms)
  if bloom.composite_uniforms != nil do delete(bloom.composite_uniforms)

  bloom.initialized = false
  fmt.printf("Bloom effect destroyed\n")
}

load_shader :: proc(file_reader: File_Reader, vertex_path: string, fragment_path: string) -> rl.Shader {
  vertex_data, vertex_ok := file_reader(vertex_path)
  if !vertex_ok {
    fmt.printf("ERROR: Failed to read vertex shader: %s\n", vertex_path)
    return rl.Shader{}
  }
  defer delete(vertex_data)

  fragment_data, fragment_ok := file_reader(fragment_path)
  if !fragment_ok {
    fmt.printf("ERROR: Failed to read fragment shader: %s\n", fragment_path)
    return rl.Shader{}
  }
  defer delete(fragment_data)

  vertex_cstr := strings.clone_to_cstring(string(vertex_data))
  defer delete(vertex_cstr)

  fragment_cstr := strings.clone_to_cstring(string(fragment_data))
  defer delete(fragment_cstr)

  return rl.LoadShaderFromMemory(vertex_cstr, fragment_cstr)
}

// calculate memory usage for debug info
calculate_bloom_memory_usage :: proc(bloom: ^Bloom_Effect) -> f32 {
  if !bloom.initialized do return 0.0

  total_bytes := 0
  for level in bloom.mip_levels {
    // Each render target: width * height * 16 bytes (RGBA32F)
    bytes_per_target := level.width * level.height * 16
    total_bytes += int(bytes_per_target * 2) // read + write buffer
  }

  return f32(total_bytes) / (1024.0 * 1024.0) // Convert to MB
}

bloom_get_debug_info :: proc(bloom: ^Bloom_Effect) -> Effect_Debug_Info {
  return Effect_Debug_Info{
    name = "Bloom Effect",
    initialized = bloom.initialized,
    parameters = {},
    shaders = {},
    render_targets = {},
    uniforms = {},
    memory_usage_mb = calculate_bloom_memory_usage(bloom),
  }
}
