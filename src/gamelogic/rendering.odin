package gamelogic

import "core:log"
import "core:fmt"
import rl "vendor:raylib"

DEFAULT_POST_FX_SETTINGS :: Post_FX_Settings{
	space_bcs =       { brightness = 0.0, contrast = 1.0, saturation = 1.0, enabled = true},
	space_bloom =     { threshold = 0.3, intensity = 0.5, strength = 0.5, exposure = 3.0, enabled = true},
	trail_bloom =     { threshold = 0.3, intensity = 0.5, strength = 0.5, exposure = 1.0, enabled = true},
	ship_bloom =      { threshold = 0.1, intensity = 2.1, strength = 0.3, exposure = 1.0, enabled = true},
	composite_bloom = { threshold = 0.3, intensity = 1.0, strength = 1.5, exposure = 1.0, enabled = true},
}

render_game :: proc() {
	if g_state == nil {
		log.error("Game state not initialized")
		return
	}

	if g_state.final_render_target.id == 0 {
		log.error("Final render target is not initialized")
		return
	}

	rl.BeginDrawing()
	defer rl.EndDrawing()
	rl.ClearBackground(rl.BLACK)

	// step 1: render the space background into a texture
	space_background_texture := space_system_render(&g_state.space)

	// step 2: apply BCS effect to space background if enabled and using our new settings
	if space_background_texture.id != 0 {
		space_background_texture = apply_postfx(space_background_texture, .BCS)
	}

	// step 3: apply space bloom effect using dedicated instance
	if space_background_texture.id != 0 {
		space_background_texture = apply_postfx(space_background_texture, .BLOOM_SPACE)
	}

	// step 4: render the ship trail into a texture
	trail_texture := render_ship_trail_to_texture(&g_state.ship_trail, g_state.trail_render_target, g_state.global_time, &g_state.camera, g_state.resolution.x, g_state.resolution.y, g_state.ship.rotation)

	// step 5: apply trail bloom effect using dedicated instance
	if trail_texture.id != 0 {
		trail_texture = apply_postfx(trail_texture, .BLOOM_TRAIL)
	}

	// step 6: render the ship and related objects into a texture
	ship_texture := render_ship_to_texture(&g_state.ship, g_state.ship_render_target)

	// step 7: apply ship bloom effect using dedicated instance
	if ship_texture.id != 0 {
		ship_texture = apply_postfx(ship_texture, .BLOOM_SHIP)
	}

	if space_background_texture.id == 0 || ship_texture.id == 0 {
		// nothing to draw, skip rendering
		return
	}

	// step 8: prepare to render layers to final render target
	rl.BeginTextureMode(g_state.final_render_target)
	rl.ClearBackground(rl.BLACK)
	rl.BeginBlendMode(.ALPHA_PREMULTIPLY)

	draw_texture(space_background_texture) // step 9: render space background to final RT
	draw_texture(trail_texture) // step 10: render trail to final RT
	draw_texture(ship_texture) // step 11: render ship to final RT

  rl.EndBlendMode()
	rl.EndTextureMode()

	// step 12: apply bloom to final render target's texture
	final_texture := apply_postfx(g_state.final_render_target.texture, .BLOOM_FINAL)

	// step 13: render final texture to screen
	draw_texture(final_texture)

  when #config(ODIN_DEBUG, true) && ODIN_OS == .JS {
		if !g_state.debug_ui_enabled {
      rl.DrawText("debug build: Press P to open debug UI", 13, 13, 20, {210, 210, 210, 120})
    }
	}


	// step 14: render debug UI on top
	when #config(ODIN_DEBUG, true) {
		if g_state.debug_ui_enabled && g_state.debug_ui_ctx != nil {
			debug_render_microui_commands(g_state.debug_ui_ctx)
		}
	}
}

apply_postfx :: proc(input: rl.Texture2D, effect_type: PostFX_Type) -> rl.Texture2D {
	instance: ^PostFX_Effect_Instance
	for &inst in g_state.postfx_instances {
		if inst.type == effect_type {
			instance = &inst
			break
		}
	}

	if instance == nil || !instance.enabled^ {
		return input
	}

	switch instance.type {
	case .BCS:
		if !instance.bcs_effect.initialized {
			return input
		}

		instance.bcs_effect.config = BCS_Config{
			brightness = instance.bcs_settings.brightness,
			contrast = instance.bcs_settings.contrast,
			saturation = instance.bcs_settings.saturation,
		}

		return bcs_effect_apply(instance.bcs_effect, input)

	case .BLOOM_SPACE, .BLOOM_TRAIL, .BLOOM_SHIP, .BLOOM_FINAL:
		if !instance.bloom_effect.initialized {
			return input
		}

		instance.bloom_effect.config.threshold = instance.bloom_settings.threshold
		instance.bloom_effect.config.intensity = instance.bloom_settings.intensity
		instance.bloom_effect.config.strength = instance.bloom_settings.strength
		instance.bloom_effect.config.exposure = instance.bloom_settings.exposure

		return bloom_effect_apply_composited(instance.bloom_effect, input)
	}

	return input
}

PostFX_Type :: enum {
	BCS,
	BLOOM_SPACE,
	BLOOM_TRAIL,
	BLOOM_SHIP,
	BLOOM_FINAL,
}

PostFX_Effect_Instance :: struct {
	name: string,
	type: PostFX_Type,
	bloom_effect: ^Bloom_Effect,
	bcs_effect: ^BCS_Effect,
	bloom_settings: ^Bloom_Settings,
	bcs_settings: ^BCS_Settings,
	enabled: ^bool,
}

BCS_Settings :: struct {
	brightness: f32,  // -1.0 to 1.0
	contrast:   f32,  // 0.0 to 2.0
	saturation: f32,  // 0.0 to 2.0
	enabled:    bool, // Toggle for this BCS effect
}

Bloom_Settings :: struct {
	threshold: f32,
	intensity: f32,
	strength:  f32,
	exposure:  f32,
	enabled:   bool,
}

Post_FX_Settings :: struct {
	space_bcs:       BCS_Settings,
	space_bloom:     Bloom_Settings,
	trail_bloom:     Bloom_Settings,
	ship_bloom:      Bloom_Settings,
	composite_bloom: Bloom_Settings,
}

// ============================================================================
// BCS EFFECT IMPLEMENTATION
// ============================================================================
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
  bcs.render_target = create_render_target(bcs.screen_width, bcs.screen_height, .UNCOMPRESSED_R32G32B32A32)

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
  rl.EndTextureMode()

  return true
}

bcs_effect_apply :: proc(bcs: ^BCS_Effect, input_texture: rl.Texture2D) -> rl.Texture2D {
  if !bcs.initialized {
    return input_texture
  }

  // render to BCS's own internal render target
  rl.BeginTextureMode(bcs.render_target)
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

  // draw fullscreen quad to BCS's own render target
  draw_to_render_target(input_texture, bcs.render_target)

  return bcs.render_target.texture
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

// ============================================================================
// BLOOM EFFECT IMPLEMENTATION
// ============================================================================
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

  // self-managed render targets
  composite_target: rl.RenderTexture2D, // for final composited result

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
  radius = 1.0,
  mip_levels = 5,
  mip_weights = {},
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

  // clean up existing composite target
  if bloom.composite_target.id != 0 {
    rl.UnloadRenderTexture(bloom.composite_target)
  }

  bloom.mip_levels = make([]Bloom_Mip_Level, bloom.config.mip_levels)

  // create composite target at full resolution
  bloom.composite_target = create_render_target(bloom.screen_width, bloom.screen_height, .UNCOMPRESSED_R32G32B32A32)
  if bloom.composite_target.id == 0 {
    fmt.printf("ERROR: Bloom: Failed to create composite render target\n")
    return false
  }
  rl.SetTextureFilter(bloom.composite_target.texture, .BILINEAR)

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
    bloom.mip_levels[i].read_buffer = create_render_target(current_width, current_height, .UNCOMPRESSED_R32G32B32A32)
    bloom.mip_levels[i].write_buffer = create_render_target(current_width, current_height, .UNCOMPRESSED_R32G32B32A32)

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

bloom_effect_apply_composited :: proc(bloom: ^Bloom_Effect, input_texture: rl.Texture2D) -> rl.Texture2D {
  if !bloom.initialized {
    fmt.printf("WARNING: Bloom: Effect not initialized, returning original texture\n")
    return input_texture
  }

  bloom_texture := bloom_effect_apply(bloom, input_texture)
  bloom_effect_composite(bloom, input_texture, bloom_texture, &bloom.composite_target)

  return bloom.composite_target.texture
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
  draw_to_render_target(original_texture, output_target^)
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
  draw_to_render_target(input_texture, bloom.mip_levels[0].write_buffer)

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
    draw_to_render_target(source_level.read_buffer.texture, target_level.write_buffer)

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
    draw_to_render_target(source_level.read_buffer.texture, target_level.write_buffer)

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

  // unload composite target
  if bloom.composite_target.id != 0 {
    rl.UnloadRenderTexture(bloom.composite_target)
  }

  // clean up uniform location maps
  if bloom.bright_pass_uniforms != nil do delete(bloom.bright_pass_uniforms)
  if bloom.downsample_uniforms != nil do delete(bloom.downsample_uniforms)
  if bloom.upsample_uniforms != nil do delete(bloom.upsample_uniforms)
  if bloom.composite_uniforms != nil do delete(bloom.composite_uniforms)

  bloom.initialized = false
  fmt.printf("Bloom effect destroyed\n")
}
