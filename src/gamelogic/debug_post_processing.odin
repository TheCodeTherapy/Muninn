package gamelogic

import "core:fmt"
import mu "vendor:microui"
import rl "vendor:raylib"

POST_PROCESSING_PANEL_NAME :: "Post-Processing Effects"
POST_PROCESSING_PANEL_UNFOLDED :: true

Post_Processing_Stack :: struct {
  effects: []Post_Processing_Effect,
  enabled: []bool,
}

debug_post_processing_panel :: proc(ctx: ^mu.Context) {
  if g_state == nil {
    mu.label(ctx, "Game state not available")
    return
  }

  if .ACTIVE in mu.header(ctx, POST_PROCESSING_PANEL_NAME, POST_PROCESSING_PANEL_UNFOLDED ? {.EXPANDED} : {}) {
    mu.layout_row(ctx, {5, -1}, 0)
    mu.label(ctx, "")

    mu.layout_begin_column(ctx)
    defer mu.layout_end_column(ctx)

    if g_state.bcs_effect.initialized {
      render_bcs_effect_direct_ui(ctx, &g_state.bcs_effect, &g_state.bcs_enabled)
    }

    if g_state.bloom_effect.initialized {
      render_bloom_effect_direct_ui(ctx, &g_state.bloom_effect, &g_state.bloom_enabled)
    }

    if !g_state.bcs_effect.initialized && !g_state.bloom_effect.initialized {
      mu.layout_row(ctx, {-1}, 0)
      mu.label(ctx, "No post-processing effects initialized")
    }
  }
}

// direct BCS UI - no arrays, works on web
render_bcs_effect_direct_ui :: proc(ctx: ^mu.Context, bcs: ^BCS_Effect, enabled: ^bool) {
  if .ACTIVE in mu.header(ctx, "BCS Effect", {}) {
    mu.layout_row(ctx, {80, -1}, 0)

    // enable checkbox
    mu.checkbox(ctx, "Enabled", enabled)
    mu.label(ctx, "")

    // status
    status_text := bcs.initialized ? "Status: Initialized" : "Status: Not Initialized"
    mu.label(ctx, "Status:")
    mu.label(ctx, status_text)

    // direct sliders on config
    mu.label(ctx, "Brightness:")
    mu.slider(ctx, &bcs.config.brightness, -1.0, 1.0)

    mu.label(ctx, "Contrast:")
    mu.slider(ctx, &bcs.config.contrast, 0.0, 3.0)

    mu.label(ctx, "Saturation:")
    mu.slider(ctx, &bcs.config.saturation, 0.0, 3.0)
  }
}

// direct Bloom UI - no arrays, works on web
render_bloom_effect_direct_ui :: proc(ctx: ^mu.Context, bloom: ^Bloom_Effect, enabled: ^bool) {
  if .ACTIVE in mu.header(ctx, "Bloom Effect", {}) {
    mu.layout_row(ctx, {80, -1}, 0)

    mu.checkbox(ctx, "Enabled", enabled)
    mu.label(ctx, "")

    status_text := bloom.initialized ? "Status: Initialized" : "Status: Not Initialized"
    mu.label(ctx, "Status:")
    mu.label(ctx, status_text)

    mu.label(ctx, "Threshold:")
    mu.slider(ctx, &bloom.config.threshold, 0.0, 1.0)

    mu.label(ctx, "Intensity:")
    mu.slider(ctx, &bloom.config.intensity, 0.0, 1.0)

    mu.label(ctx, "Strength:")
    mu.slider(ctx, &bloom.config.strength, 0.0, 3.0)

    mu.label(ctx, "Exposure:")
    mu.slider(ctx, &bloom.config.exposure, 0.1, 5.0)

    mu.label(ctx, "Radius:")
    mu.slider(ctx, &bloom.config.radius, 0.1, 3.0)
  }
}

render_effect_parameters :: proc(ctx: ^mu.Context, parameters: []Effect_Parameter_Info) {
  for &param in parameters {
    switch &ref in param.reference {
    case ^f32:
      // single line: label (min-max): slider
      mu.layout_row(ctx, {150, -1}, 0)
      mu.label(ctx, fmt.tprintf("%s (%.1f-%.1f):", param.name, param.constraint.min_val, param.constraint.max_val))
      result := mu.slider(ctx, ref, param.constraint.min_val, param.constraint.max_val)
      _ = result

    case ^int:
      // single line: label (min-max): slider
      mu.layout_row(ctx, {150, -1}, 0)
      mu.label(ctx, fmt.tprintf("%s (%d-%d):", param.name, int(param.constraint.min_val), int(param.constraint.max_val)))
      temp_val := f32(ref^)
      result := mu.slider(ctx, &temp_val, param.constraint.min_val, param.constraint.max_val)
      if .CHANGE in result {
          ref^ = int(temp_val)
      }

    case ^bool:
      // single line: checkbox with label
      mu.layout_row(ctx, {150, -1}, 0)
      mu.checkbox(ctx, param.name, ref)

    case ^rl.Vector2:
      // single line: label (min-max): X slider Y slider
      mu.layout_row(ctx, {150, 80, 80}, 0)
      mu.label(ctx, fmt.tprintf("%s (%.1f-%.1f):", param.name, param.constraint.min_val, param.constraint.max_val))

      x_val := ref.x
      y_val := ref.y
      x_result := mu.slider(ctx, &x_val, param.constraint.min_val, param.constraint.max_val)
      if .CHANGE in x_result do ref.x = x_val
      y_result := mu.slider(ctx, &y_val, param.constraint.min_val, param.constraint.max_val)
      if .CHANGE in y_result do ref.y = y_val

    case ^rl.Vector3:
      // single line: label (min-max): X slider Y slider Z slider
      mu.layout_row(ctx, {150, 60, 60, 60}, 0)
      mu.label(ctx, fmt.tprintf("%s (%.1f-%.1f):", param.name, param.constraint.min_val, param.constraint.max_val))

      x_val := ref.x
      y_val := ref.y
      z_val := ref.z
      x_result := mu.slider(ctx, &x_val, param.constraint.min_val, param.constraint.max_val)
      if .CHANGE in x_result do ref.x = x_val
      y_result := mu.slider(ctx, &y_val, param.constraint.min_val, param.constraint.max_val)
      if .CHANGE in y_result do ref.y = y_val
      z_result := mu.slider(ctx, &z_val, param.constraint.min_val, param.constraint.max_val)
      if .CHANGE in z_result do ref.z = z_val

    case ^rl.Color:
      // single line: label (0-255): R slider G slider B slider A slider
      mu.layout_row(ctx, {150, 50, 50, 50, 50}, 0)
      mu.label(ctx, fmt.tprintf("%s (0-255):", param.name))

      r_val := f32(ref.r)
      g_val := f32(ref.g)
      b_val := f32(ref.b)
      a_val := f32(ref.a)
      r_result := mu.slider(ctx, &r_val, 0, 255)
      if .CHANGE in r_result do ref.r = u8(r_val)
      g_result := mu.slider(ctx, &g_val, 0, 255)
      if .CHANGE in g_result do ref.g = u8(g_val)
      b_result := mu.slider(ctx, &b_val, 0, 255)
      if .CHANGE in b_result do ref.b = u8(b_val)
      a_result := mu.slider(ctx, &a_val, 0, 255)
      if .CHANGE in a_result do ref.a = u8(a_val)
    }
  }
}

// generic resource rendering that works with any effect
render_generic_resources :: proc(ctx: ^mu.Context, debug_info: Effect_Debug_Info) {
  // memory usage and initialization status
  mu.layout_row(ctx, {120, 200}, 0)
  mu.label(ctx, "Memory Usage:")
  mu.label(ctx, fmt.tprintf("%.2f MB", debug_info.memory_usage_mb))

  mu.label(ctx, "Initialized:")
  mu.label(ctx, debug_info.initialized ? "Yes" : "No")

  // Shaders section
  if len(debug_info.shaders) > 0 {
    mu.layout_row(ctx, {-1}, 0)
    mu.label(ctx, fmt.tprintf("Shaders (%d):", len(debug_info.shaders)))

    for shader in debug_info.shaders {
      mu.layout_row(ctx, {20, 120, 100, -1}, 0)
      mu.label(ctx, "")  // indent
      mu.label(ctx, fmt.tprintf("%s:", shader.name))
      mu.label(ctx, fmt.tprintf("%d", shader.id))
      mu.label(ctx, "")
    }
  }

  // Render targets section
  if len(debug_info.render_targets) > 0 {
    mu.layout_row(ctx, {-1}, 0)
    mu.label(ctx, fmt.tprintf("Render Targets (%d):", len(debug_info.render_targets)))

    for target in debug_info.render_targets {
      mu.layout_row(ctx, {20, 120, 200, -1}, 0)
      mu.label(ctx, "")  // indent
      mu.label(ctx, fmt.tprintf("%s:", target.name))
      mu.label(ctx, fmt.tprintf("%d (%dx%d)", target.id, target.width, target.height))
      mu.label(ctx, "")
    }
  }
}

render_uniform_locations :: proc(ctx: ^mu.Context, shader_name: string, uniforms: map[string]i32) {
  mu.layout_row(ctx, {20, 100, -1}, 0)
  mu.label(ctx, "")  // indent
  mu.label(ctx, fmt.tprintf("%s:", shader_name))
  mu.label(ctx, "")

  for uniform_name, location in uniforms {
    mu.layout_row(ctx, {40, 120, 50, -1}, 0)
    mu.label(ctx, "")  // double indent
    mu.label(ctx, uniform_name)
    mu.label(ctx, fmt.tprintf("%d", location))
    mu.label(ctx, "")
  }
}

debug_post_processing_panel_config :: proc() -> (name: string, start_unfolded: bool) {
  return POST_PROCESSING_PANEL_NAME, POST_PROCESSING_PANEL_UNFOLDED
}
