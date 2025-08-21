package gamelogic

import rl "vendor:raylib"

load_assets :: proc() {
	// load and set window icon
	icon_image := rl.LoadImage("assets/tri.png")
	if icon_image.data != nil {
		rl.SetWindowIcon(icon_image)
		rl.UnloadImage(icon_image) // unload after setting icon
	}
}
