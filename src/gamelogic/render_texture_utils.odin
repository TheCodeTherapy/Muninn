package gamelogic

import "core:c"
import "core:fmt"
import rl "vendor:raylib"
import gl "vendor:raylib/rlgl"

LoadRenderTextureWithFormat :: proc(width, height: c.int, format: rl.PixelFormat, depth_as_texture := true) -> rl.RenderTexture2D {
  result: rl.RenderTexture2D
  result.id = 0
  result.texture = rl.Texture2D{}
  result.depth   = rl.Texture2D{}

  // 1) FBO
  fbo_id := gl.LoadFramebuffer()          // glGenFramebuffers(1)
  gl.EnableFramebuffer(fbo_id)            // glBindFramebuffer(GL_FRAMEBUFFER, fbo_id)

  // 2) color texture in requested format
  // LoadTexture(data, w, h, format, mipmaps)
  color_tex_id := gl.LoadTexture(nil, width, height, cast(c.int)format, 1)

  // basic parameters (filter/wrap)
  // TODO: check out all correct constants for texture params. For now I'll use basic filtering

  // attach color texture to FBO color 0
  // FramebufferAttach(fbo, texId, attachType, texType, mipLevel)
  gl.FramebufferAttach(
    fbo_id,
    color_tex_id,
    cast(c.int)gl.FramebufferAttachType.COLOR_CHANNEL0,
    cast(c.int)gl.FramebufferAttachTextureType.TEXTURE2D,
    0,
  )

  // 3) Depth: texture or renderbuffer
  // LoadTextureDepth(w, h, useRenderBuffer)
  depth_id := gl.LoadTextureDepth(width, height, !depth_as_texture)

  depth_texture_type := depth_as_texture ? gl.FramebufferAttachTextureType.TEXTURE2D : gl.FramebufferAttachTextureType.RENDERBUFFER
  gl.FramebufferAttach(
    fbo_id,
    depth_id,
    cast(c.int)gl.FramebufferAttachType.DEPTH,
    cast(c.int)depth_texture_type,
    0,
  )

  // 4) Validate FBO
  if !gl.FramebufferComplete(fbo_id) {
    // clean up and return empty result if something failed
    gl.UnloadTexture(depth_id)
    gl.UnloadTexture(color_tex_id)
    gl.DisableFramebuffer()
    gl.UnloadFramebuffer(fbo_id)
    return result // zeroed; indicates failure
  }

  // 5) Unbind
  gl.DisableFramebuffer() // glBindFramebuffer(GL_FRAMEBUFFER, 0)

  // 6) Fill RenderTexture2D so BeginTextureMode/EndTextureMode work
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

  // Final fallback: RGBA8
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
    // seems that UnloadTexture works for both textures and renderbuffers in rlgl.
    gl.UnloadTexture(rt.depth.id)
    rt.depth.id = 0
  }
  if rt.id != 0 {
    gl.UnloadFramebuffer(rt.id)
    rt.id = 0
  }
}
