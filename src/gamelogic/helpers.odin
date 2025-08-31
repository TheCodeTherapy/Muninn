package gamelogic

import "core:fmt"
import "core:strings"
import "core:math"
import "core:c"
import rlgl "vendor:raylib/rlgl"
import rl "vendor:raylib"

// ===========================================================================
// LOG HELPERS
// ===========================================================================
MAX_LOG_LINE_LENGTH :: 120

LogLevel :: enum {
  SUCCESS,
  WARNING,
  ERROR,
  MESSAGE,
}

Log :: proc(level: LogLevel, source: string, format: string, args: ..any) {
  debug :: #config(ODIN_DEBUG, false)
  if debug {
    // determine color based on log level
    color_code: string
    switch level {
    case .SUCCESS:
      color_code = "\033[32m" // green
    case .WARNING:
      color_code = "\033[33m" // yellow/orange
    case .ERROR:
      color_code = "\033[31m" // red
    case .MESSAGE:
      color_code = "\033[37m" // white
    }

    // print the prefix with color
    fmt.printf("%s[GL] %s: \033[0m", color_code, source)
    prefix_len := 5 + len(source) + 2 // "[GL] " + source + ": "

    // capture the formatted message length by printing to a temp buffer
    buf: [512]byte // static buffer, no allocation
    sb := strings.builder_from_bytes(buf[:])
    fmt.sbprintf(&sb, format, ..args)
    message := strings.to_string(sb)

    // print the message
    fmt.printf("%s", message)

    // calculate and print padding
    total_length := prefix_len + len(message)
    if total_length < MAX_LOG_LINE_LENGTH {
      remaining := MAX_LOG_LINE_LENGTH - total_length - 1 // -1 for space
      fmt.printf(" ")
      for _ in 0..<remaining {
        fmt.printf("-")
      }
    }
    fmt.printf("\n")
  }
}

// ===========================================================================
// MATH HELPERS
// ===========================================================================
round :: proc(n: f32, digits: int) -> f32 {
  multiplier := math.pow(10.0, f32(digits))
  return math.round(n * multiplier) / multiplier
}

ease :: proc(target, n, factor, dt: f32, fps: f32 = 60.0) -> f32 {
  k := -math.ln_f32(1 - factor) * fps
  factor_dt := 1 - math.exp_f32(-k * math.max(dt, 0))
  return round((target - n) * factor_dt, 5)
}

clamp :: proc(value: f32, min_val: f32, max_val: f32) -> f32 {
  return math.max(min_val, math.min(max_val, value))
}

vector_magnitude :: proc(v: rl.Vector2) -> f32 {
  return math.sqrt(v.x * v.x + v.y * v.y)
}

vector_normalize :: proc(v: rl.Vector2) -> rl.Vector2 {
  mag := vector_magnitude(v)
  if mag == 0 {
    return {0, 0}
  }
  return {v.x / mag, v.y / mag}
}

direction_from_angle :: proc(angle_degrees: f32) -> rl.Vector2 {
  radians := angle_degrees * rl.DEG2RAD
  return {math.cos(radians), math.sin(radians)}
}

remap :: proc(value: f32, min_value: f32, max_value: f32, min_scaled_value: f32, max_scaled_value: f32) -> f32 {
	return min_scaled_value + ((max_scaled_value - min_scaled_value) * (value - min_value)) / (max_value - min_value)
}

// ===========================================================================
// GL HELPERS
// ===========================================================================
rectangle_source_flipped :: proc(tex: rl.Texture2D) -> rl.Rectangle {
  return rl.Rectangle{ 0, 0, f32(tex.width), -f32(tex.height) } // flip Y
}

rectangle_dest_render_target :: proc(rt: rl.RenderTexture2D) -> rl.Rectangle {
  return rl.Rectangle{ 0, 0, f32(rt.texture.width), f32(rt.texture.height) }
}

draw_to_render_target :: proc(tex: rl.Texture2D, rt: rl.RenderTexture2D) {
  rl.DrawTexturePro(
    tex,
    rectangle_source_flipped(tex),
    rectangle_dest_render_target(rt),
    rl.Vector2{0,0},
    0.0,
    rl.WHITE,
  )
}

draw_texture :: proc(tex: rl.Texture2D) {
  if tex.id == 0 {
    return
  }
  rl.DrawTextureRec(
    tex,
    rl.Rectangle{ 0, 0, f32(tex.width), -f32(tex.height) },
    {0, 0},
    rl.WHITE,
  )
}

create_render_target_with_format :: proc(width, height: c.int, format: rl.PixelFormat, depth_as_texture := true) -> rl.RenderTexture2D {
  result: rl.RenderTexture2D
  result.id = 0
  result.texture = rl.Texture2D{}
  result.depth   = rl.Texture2D{}

  fbo_id := rlgl.LoadFramebuffer()
  rlgl.EnableFramebuffer(fbo_id)

  color_tex_id := rlgl.LoadTexture(nil, width, height, cast(c.int)format, 1)

  rlgl.FramebufferAttach(
    fbo_id,
    color_tex_id,
    cast(c.int)rlgl.FramebufferAttachType.COLOR_CHANNEL0,
    cast(c.int)rlgl.FramebufferAttachTextureType.TEXTURE2D,
    0,
  )

  depth_id := rlgl.LoadTextureDepth(width, height, !depth_as_texture)

  depth_texture_type := depth_as_texture ? rlgl.FramebufferAttachTextureType.TEXTURE2D : rlgl.FramebufferAttachTextureType.RENDERBUFFER
  rlgl.FramebufferAttach(
    fbo_id,
    depth_id,
    cast(c.int)rlgl.FramebufferAttachType.DEPTH,
    cast(c.int)depth_texture_type,
    0,
  )

  if !rlgl.FramebufferComplete(fbo_id) {
    rlgl.UnloadTexture(depth_id)
    rlgl.UnloadTexture(color_tex_id)
    rlgl.DisableFramebuffer()
    rlgl.UnloadFramebuffer(fbo_id)
    return result // zeroed indicates failure
  }

  rlgl.DisableFramebuffer()

  result.id = fbo_id

  result.texture.id       = color_tex_id
  result.texture.width    = width
  result.texture.height   = height
  result.texture.mipmaps  = 1
  result.texture.format   = format

  result.depth.id         = depth_id
  result.depth.width      = width
  result.depth.height     = height
  result.depth.mipmaps    = 1
  result.depth.format     = rl.PixelFormat.COMPRESSED_PVRT_RGB

  return result
}

create_render_target :: proc(width, height: c.int, wanted: rl.PixelFormat, depth_as_texture := false) -> rl.RenderTexture2D {
  rt := create_render_target_with_format(width, height, wanted, depth_as_texture)

  if rt.id != 0 {
    Log(.SUCCESS,"RENDER TARGETS", "Successfully loaded render texture with format: %v", wanted)
    if wanted != rl.PixelFormat.UNCOMPRESSED_R8G8B8A8 {
      rl.SetTextureFilter(rt.texture, rl.TextureFilter.POINT)
      rl.SetTextureWrap(rt.texture, rl.TextureWrap.CLAMP)
    }
    return rt
  }

  if wanted != rl.PixelFormat.UNCOMPRESSED_R16G16B16A16 {
    Log(.WARNING,"RENDER TARGETS", "Failed to load render texture with format: %v, trying half-float instead", wanted)
    rt = create_render_target_with_format(width, height, rl.PixelFormat.UNCOMPRESSED_R16G16B16A16, depth_as_texture)
    if rt.id != 0 {
      rl.SetTextureFilter(rt.texture, rl.TextureFilter.POINT)
      rl.SetTextureWrap(rt.texture, rl.TextureWrap.CLAMP)
      return rt
    }
  }

  Log(.WARNING, "RENDER TARGETS", "Failed to load render texture with format: %v, trying final fallback RGBA8", wanted)
  rt = create_render_target_with_format(width, height, rl.PixelFormat.UNCOMPRESSED_R8G8B8A8, depth_as_texture)
  rl.SetTextureWrap(rt.texture, .CLAMP)
  rl.SetTextureFilter(rt.texture, .POINT)

  if rt.id == 0 {
    Log(.ERROR, "RENDER TARGETS", "Failed to load render texture with format: %v and all fallback formats", wanted)
  }

  return rt
}

// ============================================================================
// SHADER LOADING
// ============================================================================
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
