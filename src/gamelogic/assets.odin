package gamelogic

import rl "vendor:raylib"

// Load font atlas texture for shaders
load_font_atlas_texture :: proc() -> rl.Texture2D {
	font_atlas_image := rl.LoadImage("assets/font_atlas.png")
	font_atlas_texture: rl.Texture2D
	if font_atlas_image.data != nil {
		// flip the image vertically to correct for OpenGL coordinate system
		rl.ImageFlipVertical(&font_atlas_image)
		font_atlas_texture = rl.LoadTextureFromImage(font_atlas_image)
		rl.UnloadImage(font_atlas_image)
	} else {
		// fallback: create a simple white texture if font atlas is not found
		font_atlas_texture = rl.LoadTextureFromImage(rl.GenImageColor(1, 1, rl.WHITE))
		rl.SetTextureFilter(font_atlas_texture, .ANISOTROPIC_16X)
	}
	return font_atlas_texture
}

load_assets :: proc() {
	icon_image := rl.LoadImage("assets/tri.png")
	if icon_image.data != nil {
		rl.SetWindowIcon(icon_image)
		rl.UnloadImage(icon_image)
	}
}
