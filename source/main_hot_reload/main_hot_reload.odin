/*
┌─────────────────────────────────────────────────────────────────────────────┐
│ This is the game's development binary.                                      │
│ Whenever code changes are saved, the changed parts are recompiled and       │
│ loaded like dynamically linked libraries.                                   │
│ Here we will load: build/hot_reload/game_\d+\.(so|dylib|dll)                │
└─────────────────────────────────────────────────────────────────────────────┘
*/

package main

import "core:c/libc"
import "core:dynlib"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:os/os2"
import "core:path/filepath"

when ODIN_OS == .Windows {
	DLL_EXT :: ".dll"
} else when ODIN_OS == .Darwin {
	DLL_EXT :: ".dylib"
} else {
	DLL_EXT :: ".so"
}

GAME_DLL_DIR :: "build/hot_reload/"
GAME_DLL_PATH :: GAME_DLL_DIR + "game" + DLL_EXT

/*
┌─────────────────────────────────────────────────────────────────────────────┐
│ We copy the DLL because using it directly would lock it in the file system  │
│ which would prevent the compiler from writing it.                           │
└─────────────────────────────────────────────────────────────────────────────┘
*/
copy_dll :: proc(to: string) -> bool {
	copy_err := os2.copy_file(to, GAME_DLL_PATH)

	if copy_err != nil {
		fmt.printfln("Failed to copy " + GAME_DLL_PATH + " to {0}: %v", to, copy_err)
		return false
	}

	return true
}

Game_API :: struct {
	lib:               dynlib.Library,
	init_window:       proc(),
	init:              proc(),
	update:            proc(),
	should_close:      proc() -> bool,
	shutdown:          proc(),
	shutdown_window:   proc(),
	memory:            proc() -> rawptr,
	memory_size:       proc() -> int,
	hot_reloaded:      proc(mem: rawptr),
	force_reload:      proc() -> bool,
	force_restart:     proc() -> bool,
	modification_time: os.File_Time,
	api_version:       int,
}

load_game_api :: proc(api_version: int) -> (api: Game_API, ok: bool) {
	mod_time, mod_time_error := os.last_write_time_by_name(GAME_DLL_PATH)
	if mod_time_error != os.ERROR_NONE {
		fmt.printfln(
			"Failed getting last write time of " + GAME_DLL_PATH + ", error code: {1}",
			mod_time_error,
		)
		return
	}

	game_dll_name := fmt.tprintf(GAME_DLL_DIR + "game_{0}" + DLL_EXT, api_version)
	copy_dll(game_dll_name) or_return

	/* 
  ┌───────────────────────────────────────────────────────────────────────────┐
  │ This proc matches the names of the fields in the Game_API to symbols in   │
  │ the game DLL. It actually looks for symbols starting with `game_`, which  │
  │ is why the argument `"game_"` is there.                                   │
  └───────────────────────────────────────────────────────────────────────────┘
  */
	_, ok = dynlib.initialize_symbols(&api, game_dll_name, "game_", "lib")
	if !ok {
		fmt.printfln("Failed initializing symbols: {0}", dynlib.last_error())
	}

	api.api_version = api_version
	api.modification_time = mod_time
	ok = true

	return
}

unload_game_api :: proc(api: ^Game_API) {
	if api.lib != nil {
		if !dynlib.unload_library(api.lib) {
			fmt.printfln("Failed unloading lib: {0}", dynlib.last_error())
		}
	}

	game_dll_name := fmt.tprintf(GAME_DLL_DIR + "game_{0}" + DLL_EXT, api.api_version)
	fmt.printfln("Attempting to remove: {0}", game_dll_name)

	if os.exists(game_dll_name) {
		remove_err := os.remove(game_dll_name)
		if remove_err != nil {
			fmt.printfln("Failed to remove {0}: {1}", game_dll_name, remove_err)
		} else {
			fmt.printfln("Successfully removed {0}", game_dll_name)
		}
	} else {
		fmt.printfln("File {0} does not exist, nothing to remove", game_dll_name)
	}
}


main :: proc() {
	exe_path := os.args[0]
	exe_dir := filepath.dir(string(exe_path), context.temp_allocator)
	os.set_current_directory(exe_dir)

	context.logger = log.create_console_logger()

	default_allocator := context.allocator
	tracking_allocator: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking_allocator, default_allocator)
	context.allocator = mem.tracking_allocator(&tracking_allocator)

	reset_tracking_allocator :: proc(a: ^mem.Tracking_Allocator) -> bool {
		err := false

		for _, value in a.allocation_map {
			fmt.printf("%v: Leaked %v bytes\n", value.location, value.size)
			err = true
		}

		mem.tracking_allocator_clear(a)
		return err
	}

	game_api_version := 0
	game_api, game_api_ok := load_game_api(game_api_version)

	if !game_api_ok {
		fmt.println("Failed to load Game API")
		return
	}

	game_api_version += 1
	game_api.init_window()
	game_api.init()

	old_game_apis := make([dynamic]Game_API, default_allocator)

	for !game_api.should_close() {
		game_api.update()
		force_reload := game_api.force_reload()
		force_restart := game_api.force_restart()
		reload := force_reload || force_restart
		game_dll_mod, game_dll_mod_err := os.last_write_time_by_name(GAME_DLL_PATH)

		if game_dll_mod_err == os.ERROR_NONE && game_api.modification_time != game_dll_mod {
			reload = true
		}

		if reload {
			new_game_api, new_game_api_ok := load_game_api(game_api_version)

			if new_game_api_ok {
				force_restart =
					force_restart || game_api.memory_size() != new_game_api.memory_size()

				if !force_restart {
					/*
          ┌───────────────────────────────────────────────────────────────────┐
          │ This does the hot reload.                                         │
          │ Note that we don't unload the old game APIs because that would    │
          │ unload the DLL and it may contain needed stored data.             │
          │ The old DLLs are only unloaded on a full reset or app shutdown.   │
          └───────────────────────────────────────────────────────────────────┘
          */
					append(&old_game_apis, game_api)
					game_memory := game_api.memory()
					game_api = new_game_api
					game_api.hot_reloaded(game_memory)
				} else {
					/*
          ┌───────────────────────────────────────────────────────────────────┐
          │ This does a full reload.                                          │
          │ It's basically like closing and re-opening the game, without      │
          │ having to restart the executable. This happens if the game        │
          │ requests a full reload or if the size of the game memory changes, │
          │ which would probably lead to a crash anyways.                     │
          └───────────────────────────────────────────────────────────────────┘
          */
					game_api.shutdown()
					reset_tracking_allocator(&tracking_allocator)

					for &g in old_game_apis {
						unload_game_api(&g)
					}

					clear(&old_game_apis)
					unload_game_api(&game_api)
					game_api = new_game_api
					game_api.init()
				}

				game_api_version += 1
			}
		}

		if len(tracking_allocator.bad_free_array) > 0 {
			for b in tracking_allocator.bad_free_array {
				log.errorf("Bad free at: %v", b.location)
			}
			/*
      ┌───────────────────────────────────────────────────────────────────────┐
      │ This prevents the game from closing without you seeing the bad frees. │
      └───────────────────────────────────────────────────────────────────────┘
      */
			libc.getchar()
			panic("Bad free detected")
		}

		free_all(context.temp_allocator)
	}

	free_all(context.temp_allocator)
	game_api.shutdown()
	if reset_tracking_allocator(&tracking_allocator) {
		/*
    ┌─────────────────────────────────────────────────────────────────────────┐
    │ This prevents the game from closing without you seeing memory leaks.    │
    └─────────────────────────────────────────────────────────────────────────┘
    */
		libc.getchar()
	}

	for &g in old_game_apis {
		unload_game_api(&g)
	}

	delete(old_game_apis)

	game_api.shutdown_window()
	unload_game_api(&game_api)
	mem.tracking_allocator_destroy(&tracking_allocator)

	if os.exists(GAME_DLL_PATH) {
		remove_err := os.remove(GAME_DLL_PATH)
		if remove_err != nil {
			fmt.printfln("Failed to remove original {0}: {1}", GAME_DLL_PATH, remove_err)
		} else {
			fmt.printfln("Successfully removed original {0}", GAME_DLL_PATH)
		}
	}

	/*
  ┌───────────────────────────────────────────────────────────────────────────┐
  │ This creates a signal file to tell the build script to stop.              │
  └───────────────────────────────────────────────────────────────────────────┘
  */
	signal_file_path := "exit_signal.tmp"

	file, err := os.open(signal_file_path, os.O_WRONLY | os.O_CREATE | os.O_TRUNC, 0o644)
	if err != nil {
		fmt.printfln("Failed to create signal file: %v", err)
	} else {
		defer os.close(file)
		os.write_string(file, "exit")
	}
}

@(export)
NvOptimusEnablement: u32 = 1

@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1
