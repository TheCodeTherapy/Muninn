/*
This file is the starting point of your game.

Some important procedures are:
- game_init_window: Opens the window
- game_init: Sets up the game state
- game_update: Run once per frame
- game_should_close: For stopping your game when close button is pressed
- game_shutdown: Shuts down game and frees memory
- game_shutdown_window: Closes window

The procs above are used regardless if you compile using the `build_release`
script or the `build_hot_reload` script. However, in the hot reload case, the
contents of this file is compiled as part of `build/hot_reload/game.dll` (or
.dylib/.so on mac/linux). In the hot reload cases some other procedures are
also used in order to facilitate the hot reload functionality:

- game_memory: Run just before a hot reload. That way game_hot_reload.exe has a
	pointer to the game's memory that it can hand to the new game DLL.
- game_hot_reloaded: Run after a hot reload so that the `g` global
	variable can be set to whatever pointer it was in the old DLL.

NOTE: When compiled as part of `build_release`, `build_debug` or `build_web`
then this whole package is just treated as a normal Odin package. No DLL is
created.
*/

package game

import "core:fmt"
import rl "vendor:raylib"
import gamelogic "./gamelogic"

// Legacy type alias for hot reload compatibility
Game_Memory :: gamelogic.Game_State

g: ^Game_Memory

@(export)
game_update :: proc() {
	gamelogic.update()
	gamelogic.draw()

	// Everything on tracking allocator is valid until end-of-frame.
	free_all(context.temp_allocator)
}

@(export)
game_init_window :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1600, 900, "Muninn")
	when ODIN_OS != .JS {
		rl.SetWindowPosition(200, 200)
	}
}

@(export)
game_init :: proc() {
	gamelogic.set_file_reader(read_entire_file)
	gamelogic.init()
	g = gamelogic.get_state()
	game_hot_reloaded(g)
}

@(export)
game_should_run :: proc() -> bool {
	return gamelogic.should_run()
}

@(export)
game_shutdown :: proc() {
	gamelogic.shutdown()
}

@(export)
game_shutdown_window :: proc() {
	rl.CloseWindow()
}

@(export)
game_memory :: proc() -> rawptr {
	return g
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(Game_Memory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g = (^Game_Memory)(mem)
	gamelogic.set_state(g)

	// Hot reload shaders when code reloads
	fmt.printf("HOT RELOAD: Reloading shaders...\n")
	success := gamelogic.shader_manager_reload_shaders(&g.space_shaders)
	if success {
		fmt.printf("HOT RELOAD: Shader reload successful!\n")
	} else {
		fmt.printf("HOT RELOAD: Shader reload FAILED!\n")
	}

	// Hot reload camera parameters when code reloads
	fmt.printf("HOT RELOAD: Completely reinitializing camera system...\n")
	gamelogic.camera_hot_reload(&g.camera)
	fmt.printf("HOT RELOAD: Camera system reinitialized!\n")

	// Here you can also set your own global variables. A good idea is to make
	// your global variables into pointers that point to something inside `g`.
}

@(export)
game_force_reload :: proc() -> bool {
	return gamelogic.force_reload()
}

@(export)
game_force_restart :: proc() -> bool {
	return gamelogic.force_restart()
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
game_parent_window_size_changed :: proc(w, h: int) {
	rl.SetWindowSize(i32(w), i32(h))
}
