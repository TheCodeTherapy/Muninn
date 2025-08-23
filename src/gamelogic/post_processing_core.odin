#+feature dynamic-literals
package gamelogic

import rl "vendor:raylib"

Parameter_Type :: enum {
  FLOAT,
  INT,
  BOOL,
  VEC2,
  VEC3,
  COLOR,
}

Parameter_Constraint :: struct {
  type:     Parameter_Type,
  min_val:  f32,
  max_val:  f32,
  step:     f32,
  default:  f32,
}

Parameter_Reference :: union {
  ^f32,
  ^int,
  ^bool,
  ^rl.Vector2,
  ^rl.Vector3,
  ^rl.Color,
}

Effect_Parameter_Info :: struct {
  name:        string,
  constraint:  Parameter_Constraint,
  reference:   Parameter_Reference, // No rawptr!
}

Shader_Info :: struct {
  name: string,
  id:   u32,
}

Render_Target_Info :: struct {
  name:         string,
  id:           u32,
  width:        i32,
  height:       i32,
  pixel_format: rl.PixelFormat, // for memory calculation
}

Uniform_Map_Info :: struct {
  shader_name: string,
  uniforms:    map[string]i32,
}

Effect_Debug_Info :: struct {
  name:           string,
  initialized:    bool,
  parameters:     []Effect_Parameter_Info,

  // effects have in common (I'll try to standardize this later)
  shaders:        []Shader_Info,
  render_targets: []Render_Target_Info,
  uniforms:       []Uniform_Map_Info,
  memory_usage_mb: f32, // calculated from render targets + pixel formats
}

Post_Processing_Effect :: union {
  Bloom_Effect,
  BCS_Effect,
  // Future effects will be added here
}

Effect_Config :: union {
  Bloom_Config,
  BCS_Config,
  // Future configs will be added here
}

effect_init :: proc(effect: ^Post_Processing_Effect, config: Effect_Config, width, height: i32, file_reader: File_Reader) -> bool {
  switch &e in effect {
  case Bloom_Effect:
    if bloom_config, ok := config.(Bloom_Config); ok {
      return bloom_effect_init(&e, bloom_config, width, height, file_reader)
    }
  case BCS_Effect:
    if bcs_config, ok := config.(BCS_Config); ok {
      return bcs_effect_init(&e, bcs_config, width, height, file_reader)
    }
  }
  return false
}

effect_apply :: proc(effect: ^Post_Processing_Effect, input: rl.Texture2D, output: ^rl.RenderTexture2D) -> rl.Texture2D {
  switch &e in effect {
  case Bloom_Effect:
    return bloom_effect_apply(&e, input)
  case BCS_Effect:
    bcs_effect_apply(&e, input, output)
    return output.texture
  }
  return input
}

effect_composite :: proc(effect: ^Post_Processing_Effect, original: rl.Texture2D, effect_result: rl.Texture2D, output: ^rl.RenderTexture2D) {
  switch &e in effect {
  case Bloom_Effect:
    bloom_effect_composite(&e, original, effect_result, output)
  case BCS_Effect:
    // BCS has no compositing (single-pass)
  }
}

effect_resize :: proc(effect: ^Post_Processing_Effect, width, height: i32) {
  switch &e in effect {
  case Bloom_Effect:
    bloom_effect_resize(&e, width, height)
  case BCS_Effect:
    bcs_effect_resize(&e, width, height)
  }
}

effect_hot_reload :: proc(effect: ^Post_Processing_Effect) -> bool {
  switch &e in effect {
  case Bloom_Effect:
    return bloom_effect_hot_reload(&e)
  case BCS_Effect:
    return bcs_effect_hot_reload(&e)
  }
  return false
}

effect_destroy :: proc(effect: ^Post_Processing_Effect) {
  switch &e in effect {
  case Bloom_Effect:
    bloom_effect_destroy(&e)
  case BCS_Effect:
    bcs_effect_destroy(&e)
  }
}

effect_get_debug_info :: proc(effect: ^Post_Processing_Effect) -> Effect_Debug_Info {
  switch &e in effect {
  case Bloom_Effect:
    return bloom_get_debug_info(&e)
  case BCS_Effect:
    return bcs_get_debug_info(&e)
  }
  return {}
}

effect_update_config :: proc(effect: ^Post_Processing_Effect, config: Effect_Config) {
  switch &e in effect {
  case Bloom_Effect:
    if bloom_config, ok := config.(Bloom_Config); ok {
      bloom_effect_update_config(&e, bloom_config)
    }
  case BCS_Effect:
    if bcs_config, ok := config.(BCS_Config); ok {
      bcs_effect_update_config(&e, bcs_config)
    }
  }
}
