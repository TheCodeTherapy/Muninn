package gamelogic

import "core:math"
import "core:c"
import "core:fmt"

import rl "vendor:raylib"
import gl "vendor:raylib/rlgl"

// MATH HELPER FUNCTIONS =====================================================
round :: proc(n: f32, digits: int) -> f32 {
  multiplier := math.pow(10.0, f32(digits))
  return math.round(n * multiplier) / multiplier
}

ease :: proc(target, n, factor, dt: f32, fps: f32 = 60.0) -> f32 {
  k := -math.ln_f32(1 - factor) * fps
  factor_dt := 1 - math.exp_f32(-k * math.max(dt, 0))
  return round((target - n) * factor_dt, 5)
}

ease_vec2 :: proc(target: rl.Vector2, current: rl.Vector2, factor: f32, delta_time: f32, fps: f32) -> rl.Vector2 {
  return rl.Vector2{
    ease(target.x, current.x, factor, delta_time, fps),
    ease(target.y, current.y, factor, delta_time, fps),
  }
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

// GL HELPER FUNCTIONS =======================================================
LoadRenderTextureWithFormat :: proc(width, height: c.int, format: rl.PixelFormat, depth_as_texture := true) -> rl.RenderTexture2D {
  result: rl.RenderTexture2D
  result.id = 0
  result.texture = rl.Texture2D{}
  result.depth   = rl.Texture2D{}

  fbo_id := gl.LoadFramebuffer()
  gl.EnableFramebuffer(fbo_id)

  color_tex_id := gl.LoadTexture(nil, width, height, cast(c.int)format, 1)

  gl.FramebufferAttach(
    fbo_id,
    color_tex_id,
    cast(c.int)gl.FramebufferAttachType.COLOR_CHANNEL0,
    cast(c.int)gl.FramebufferAttachTextureType.TEXTURE2D,
    0,
  )

  depth_id := gl.LoadTextureDepth(width, height, !depth_as_texture)

  depth_texture_type := depth_as_texture ? gl.FramebufferAttachTextureType.TEXTURE2D : gl.FramebufferAttachTextureType.RENDERBUFFER
  gl.FramebufferAttach(
    fbo_id,
    depth_id,
    cast(c.int)gl.FramebufferAttachType.DEPTH,
    cast(c.int)depth_texture_type,
    0,
  )

  if !gl.FramebufferComplete(fbo_id) {
    gl.UnloadTexture(depth_id)
    gl.UnloadTexture(color_tex_id)
    gl.DisableFramebuffer()
    gl.UnloadFramebuffer(fbo_id)
    return result // zeroed indicates failure
  }

  gl.DisableFramebuffer()

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

LoadRT_WithFallback :: proc(width, height: c.int, wanted: rl.PixelFormat, depth_as_texture := false) -> rl.RenderTexture2D {
  // try wanted
  rt := LoadRenderTextureWithFormat(width, height, wanted, depth_as_texture)

  if rt.id != 0 {
    fmt.printf("Successfully loaded render texture with format: %v\n", wanted)
    // conservative params for float/half-float
    if wanted != rl.PixelFormat.UNCOMPRESSED_R8G8B8A8 {
      rl.SetTextureFilter(rt.texture, rl.TextureFilter.POINT)
      rl.SetTextureWrap(rt.texture, rl.TextureWrap.CLAMP)
    }
    return rt
  }

  // try half-float
  if wanted != rl.PixelFormat.UNCOMPRESSED_R16G16B16A16 {
    fmt.printf("Trying half-float render texture with format: %v\n", rl.PixelFormat.UNCOMPRESSED_R16G16B16A16)
    rt = LoadRenderTextureWithFormat(width, height, rl.PixelFormat.UNCOMPRESSED_R16G16B16A16, depth_as_texture)
    if rt.id != 0 {
      rl.SetTextureFilter(rt.texture, rl.TextureFilter.POINT)
      rl.SetTextureWrap(rt.texture, rl.TextureWrap.CLAMP)
      return rt
    }
  }

  // final fallback RGBA8
  fmt.printf("Trying final fallback render texture with format: %v\n", rl.PixelFormat.UNCOMPRESSED_R8G8B8A8)
  rt = LoadRenderTextureWithFormat(width, height, rl.PixelFormat.UNCOMPRESSED_R8G8B8A8, depth_as_texture)
  rl.SetTextureWrap(rt.texture, .CLAMP)
  rl.SetTextureFilter(rt.texture, .POINT)
  return rt
}

// unloads a RenderTexture2D created with LoadRenderTextureWithFormat
UnloadRenderTextureWithFormat :: proc(using rt: ^rl.RenderTexture2D, depth_as_texture: bool) {
  if rt.texture.id != 0 {
    gl.UnloadTexture(rt.texture.id)
    rt.texture.id = 0
  }
  if rt.depth.id != 0 {
    gl.UnloadTexture(rt.depth.id)
    rt.depth.id = 0
  }
  if rt.id != 0 {
    gl.UnloadFramebuffer(rt.id)
    rt.id = 0
  }
}

// RENDER TEXTURE UTILS ======================================================
rect_src_flipped :: proc(tex: rl.Texture2D) -> rl.Rectangle {
	return rl.Rectangle{ 0, 0, f32(tex.width), -f32(tex.height) } // flip Y
}

rect_dst_rt :: proc(rt: rl.RenderTexture2D) -> rl.Rectangle {
	return rl.Rectangle{ 0, 0, f32(rt.texture.width), f32(rt.texture.height) }
}

draw_to_rt_scaled :: proc(tex: rl.Texture2D, rt: rl.RenderTexture2D) {
	rl.DrawTexturePro(
		tex,
		rect_src_flipped(tex),
		rect_dst_rt(rt),
		rl.Vector2{0,0},
		0.0,
		rl.WHITE,
	)
}
