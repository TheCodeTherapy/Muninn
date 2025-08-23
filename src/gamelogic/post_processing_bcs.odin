#+feature dynamic-literals
package gamelogic

import "core:fmt"
import rl "vendor:raylib"

BCS_Config :: struct {
  brightness: f32, // -1.0 to 1.0, default 0.0 (additive)
  contrast:   f32, // 0.0 to 2.0, default 1.0 (multiplicative around 0.5)
  saturation: f32, // 0.0 to 2.0, default 1.0 (0.0 = grayscale, 1.0 = original, 2.0 = oversaturated)
}

BCS_Effect :: struct {
  config: BCS_Config,
  bcs_shader: rl.Shader,
  bcs_uniforms: map[string]i32,
  screen_width:  i32,
  screen_height: i32,
  render_target: rl.RenderTexture2D,
  file_reader: File_Reader,
  initialized: bool,
}

DEFAULT_BCS_CONFIG :: BCS_Config {
  brightness = 0.0,
  contrast   = 1.0,
  saturation = 0.7,
}

// parameter constraints MicroUI sliders
BCS_PARAMETER_CONSTRAINTS := map[string]Parameter_Constraint{
  "brightness" = {type = .FLOAT, min_val = -1.0, max_val = 1.0, step = 0.01, default = 0.0},
  "contrast"   = {type = .FLOAT, min_val = 0.0, max_val = 2.0, step = 0.01, default = 1.0},
  "saturation" = {type = .FLOAT, min_val = 0.0, max_val = 2.0, step = 0.01, default = 1.0},
}

// initialize BCS effect
bcs_effect_init :: proc(bcs: ^BCS_Effect, config: BCS_Config, width, height: i32, file_reader: File_Reader) -> bool {
  bcs.config = config
  bcs.screen_width = width
  bcs.screen_height = height
  bcs.file_reader = file_reader

  if !bcs_load_shader(bcs) {
    fmt.printf("ERROR: BCS: Failed to load shader\n")
    bcs_effect_destroy(bcs)
    return false
  }

  if !bcs_create_render_target(bcs) {
    fmt.printf("ERROR: BCS: Failed to create render target\n")
    bcs_effect_destroy(bcs)
    return false
  }

  bcs.initialized = true

  fmt.printf("========== BCS EFFECT INITIALIZED ==========\n")
  fmt.printf("Screen Resolution: %dx%d\n", width, height)
  fmt.printf("Config: brightness=%.2f, contrast=%.2f, saturation=%.2f\n",
              config.brightness, config.contrast, config.saturation)
  fmt.printf("Shader ID: %d\n", bcs.bcs_shader.id)
  fmt.printf("Render Target ID: %d (%dx%d)\n",
              bcs.render_target.id, bcs.render_target.texture.width, bcs.render_target.texture.height)
  fmt.printf("===========================================\n")

  return true
}

bcs_effect_init_default :: proc(bcs: ^BCS_Effect, width, height: i32, file_reader: File_Reader) -> bool {
  return bcs_effect_init(bcs, DEFAULT_BCS_CONFIG, width, height, file_reader)
}

bcs_load_shader :: proc(bcs: ^BCS_Effect) -> bool {
  vertex_path := resolve_shader_path("default.vert")
  defer delete(vertex_path)

  fragment_path := resolve_shader_path("bcs.frag")
  defer delete(fragment_path)

  bcs.bcs_shader = load_shader(bcs.file_reader, vertex_path, fragment_path)

  if bcs.bcs_shader.id == 0 {
    fmt.printf("BCS: Failed to load shader\n")
    return false
  }

  bcs_cache_uniform_locations(bcs)
  return true
}

bcs_cache_uniform_locations :: proc(bcs: ^BCS_Effect) {
  if bcs.bcs_uniforms == nil {
    bcs.bcs_uniforms = make(map[string]i32)
  } else {
    clear(&bcs.bcs_uniforms)
  }

  bcs.bcs_uniforms["inputTexture"] = rl.GetShaderLocation(bcs.bcs_shader, "inputTexture")
  bcs.bcs_uniforms["brightness"] = rl.GetShaderLocation(bcs.bcs_shader, "brightness")
  bcs.bcs_uniforms["contrast"] = rl.GetShaderLocation(bcs.bcs_shader, "contrast")
  bcs.bcs_uniforms["saturation"] = rl.GetShaderLocation(bcs.bcs_shader, "saturation")
}

bcs_create_render_target :: proc(bcs: ^BCS_Effect) -> bool {
  // clean up existing render target
  if bcs.render_target.id != 0 {
    rl.UnloadRenderTexture(bcs.render_target)
  }

  // create new render target
  bcs.render_target = LoadRT_WithFallback(bcs.screen_width, bcs.screen_height, .UNCOMPRESSED_R32G32B32A32)

  if bcs.render_target.id == 0 {
    fmt.printf("ERROR: BCS: Failed to create render target (%dx%d)\n", bcs.screen_width, bcs.screen_height)
    return false
  }

  // set texture filtering
  rl.SetTextureFilter(bcs.render_target.texture, .BILINEAR)
  rl.SetTextureWrap(bcs.render_target.texture, .CLAMP)

  // clear the render target
  rl.BeginTextureMode(bcs.render_target)
  defer rl.EndTextureMode()

  rl.ClearBackground(rl.Color{0, 0, 0, 0})

  return true
}

// apply BCS effect to input texture and render to separate target
bcs_effect_apply :: proc(bcs: ^BCS_Effect, input_texture: rl.Texture2D, output_target: ^rl.RenderTexture2D) {
  if !bcs.initialized {
    return
  }

  // render to the provided output target
  rl.BeginTextureMode(output_target^)
  defer rl.EndTextureMode()

  rl.ClearBackground(rl.Color{0, 0, 0, 0})

  rl.BeginShaderMode(bcs.bcs_shader)
  defer rl.EndShaderMode()

  rl.SetShaderValueTexture(bcs.bcs_shader, bcs.bcs_uniforms["inputTexture"], input_texture)

  brightness := bcs.config.brightness
  contrast := bcs.config.contrast
  saturation := bcs.config.saturation

  rl.SetShaderValue(bcs.bcs_shader, bcs.bcs_uniforms["brightness"], &brightness, .FLOAT)
  rl.SetShaderValue(bcs.bcs_shader, bcs.bcs_uniforms["contrast"], &contrast, .FLOAT)
  rl.SetShaderValue(bcs.bcs_shader, bcs.bcs_uniforms["saturation"], &saturation, .FLOAT)

  // draw fullscreen quad to the output target
  draw_to_rt_scaled(input_texture, output_target^)
}

bcs_effect_resize :: proc(bcs: ^BCS_Effect, new_width, new_height: i32) {
  if !bcs.initialized do return

  bcs.screen_width = new_width
  bcs.screen_height = new_height

  bcs_create_render_target(bcs)

  fmt.printf("BCS effect resized to %dx%d\n", new_width, new_height)
}

bcs_effect_update_config :: proc(bcs: ^BCS_Effect, config: BCS_Config) {
  bcs.config = config
}

bcs_effect_hot_reload :: proc(bcs: ^BCS_Effect) -> bool {
  if !bcs.initialized do return false

  fmt.printf("=== HOT RELOADING BCS SHADER ===\n")

  // Unload existing shader
  if bcs.bcs_shader.id != 0 {
    fmt.printf("Unloading old BCS shader (ID: %d)\n", bcs.bcs_shader.id)
    rl.UnloadShader(bcs.bcs_shader)
  }

  if bcs.bcs_uniforms != nil do clear(&bcs.bcs_uniforms)

  if !bcs_load_shader(bcs) {
    fmt.printf("ERROR: BCS hot reload: Failed to reload shader\n")
    return false
  }

  fmt.printf("=== BCS HOT RELOAD COMPLETE ===\n")
  return true
}

bcs_effect_destroy :: proc(bcs: ^BCS_Effect) {
  if !bcs.initialized do return

  if bcs.bcs_shader.id != 0 {
    rl.UnloadShader(bcs.bcs_shader)
  }

  if bcs.render_target.id != 0 {
    rl.UnloadRenderTexture(bcs.render_target)
  }

  if bcs.bcs_uniforms != nil do delete(bcs.bcs_uniforms)

  bcs.initialized = false
  fmt.printf("BCS effect destroyed\n")
}

// calculate memory usage for debug info
calculate_bcs_memory_usage :: proc(bcs: ^BCS_Effect) -> f32 {
  if !bcs.initialized do return 0.0

  // single render target: width * height * 16 bytes (RGBA32F)
  bytes := bcs.screen_width * bcs.screen_height * 16
  return f32(bytes) / (1024.0 * 1024.0) // convert to MB
}

bcs_get_debug_info :: proc(bcs: ^BCS_Effect) -> Effect_Debug_Info {
  return Effect_Debug_Info{
    name = "BCS Effect",
    initialized = bcs.initialized,
    parameters = {},
    shaders = {},
    render_targets = {},
    uniforms = {},
    memory_usage_mb = calculate_bcs_memory_usage(bcs),
  }
}
