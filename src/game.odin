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
import "gamelogic"

Game_Memory :: gamelogic.Game_State

g: ^Game_Memory

@(export)
game_update :: proc() {
	gamelogic.update()
	gamelogic.update_debug_gui()
	gamelogic.draw()

	// everything on tracking allocator is valid until end-of-frame
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

	// Initialize debug GUI
	gamelogic.init_debug_gui()
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
	fmt.printf("HOT RELOAD: Game state pointer updated to %p\n", g)

	gamelogic.set_file_reader(read_entire_file)
	gamelogic.space_system_reload_shaders(&g.space)
	gamelogic.camera_hot_reload(&g.camera)
	gamelogic.hot_reload_render_targets()

	fmt.printf("HOT RELOAD: Reinitializing PostFX effects...\n")
	for &instance in g.postfx_instances {
		switch instance.type {
		case .BCS:
			if instance.bcs_effect != nil && instance.bcs_effect.initialized {
				fmt.printf("HOT RELOAD: Reinitializing %s...\n", instance.name)
				success := gamelogic.bcs_effect_hot_reload(instance.bcs_effect)
				if !success {
					fmt.printf("HOT RELOAD: %s reload FAILED!\n", instance.name)
				}
			}
		case .BLOOM_SPACE, .BLOOM_TRAIL, .BLOOM_SHIP, .BLOOM_FINAL:
			if instance.bloom_effect != nil && instance.bloom_effect.initialized {
				fmt.printf("HOT RELOAD: Reinitializing %s...\n", instance.name)
				success := gamelogic.bloom_effect_hot_reload(instance.bloom_effect)
				if !success {
					fmt.printf("HOT RELOAD: %s reload FAILED!\n", instance.name)
				}
			}
		}
	}

	fmt.printf("HOT RELOAD: Reinitializing ship system...\n")
	ship_success := gamelogic.ship_hot_reload(&g.ship)
	if !ship_success {
		fmt.printf("HOT RELOAD: Ship system reload FAILED!\n")
	}

	fmt.printf("HOT RELOAD: Reinitializing ship trail system...\n")
	trail_success := gamelogic.ship_trail_hot_reload(&g.ship_trail)
	if !trail_success {
		fmt.printf("HOT RELOAD: Ship trail system reload FAILED!\n")
	}

	fmt.printf("HOT RELOAD: Reinitializing debug GUI...\n")
	gamelogic.destroy_debug_gui() // Clean up first to prevent leaks
	gamelogic.init_debug_gui()
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
