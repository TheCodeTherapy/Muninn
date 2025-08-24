package gamelogic

import "core:fmt"
import mu "vendor:microui"

_ :: fmt

MAX_DEBUG_PANELS :: 16

Debug_Panel_Proc :: proc(ctx: ^mu.Context)

Debug_Panel :: struct {
	name:           string,
	render_proc:    Debug_Panel_Proc,
	enabled:        bool,
	active:         bool, // whether this slot is used
	start_unfolded: bool, // whether this panel starts expanded
}

// debug system state (stored in Game_State to survive hot reloads)
Debug_System :: struct {
	panels:      [MAX_DEBUG_PANELS]Debug_Panel, // fixed size arrays as God intended
	panel_count: int,
	initialized: bool,
	enabled:     bool,
}

// initialize debug system
debug_system_init :: proc() {
	when #config(ODIN_DEBUG, true) {
		fmt.printf("=== DEBUG SYSTEM INIT (ARRAY VERSION) ===\n")

		if g_state == nil {
			fmt.printf("ERROR: g_state is nil in debug_system_init\n")
			return
		}

		debug_sys := &g_state.debug_system

		// clear all panels (no allocation)
		for i in 0..<MAX_DEBUG_PANELS {
			debug_sys.panels[i] = {}
		}

		debug_sys.panel_count = 0
		debug_sys.initialized = true
		debug_sys.enabled = true

		// register built-in panels
		name, start_unfolded := debug_system_panel_config()
		debug_register_panel_with_config(name, debug_system_panel, start_unfolded)

		render_name, render_unfolded := debug_render_panel_config()
		debug_register_panel_with_config(render_name, debug_render_panel, render_unfolded)

			shader_name, shader_unfolded := debug_shader_manager_panel_config("Space Shaders Manager")
	debug_register_panel_with_config(shader_name, debug_shader_manager_panel, shader_unfolded)

	post_processing_name, post_processing_unfolded := debug_post_processing_panel_config()
	debug_register_panel_with_config(post_processing_name, debug_post_processing_panel, post_processing_unfolded)

	fmt.printf("Debug system initialized with %d panels\n", debug_sys.panel_count)
	}
}

// destroy debug system
debug_system_destroy :: proc() {
	when #config(ODIN_DEBUG, true) {
		if g_state == nil do return

		debug_sys := &g_state.debug_system

		// clear all panels (no deallocation)
		for i in 0..<MAX_DEBUG_PANELS {
			debug_sys.panels[i] = {}
		}

		debug_sys.panel_count = 0
		debug_sys.initialized = false

		fmt.printf("Debug system destroyed\n")
	}
}

// register a debug panel with config
debug_register_panel_with_config :: proc(name: string, panel_proc: Debug_Panel_Proc, start_unfolded: bool) {
	when #config(ODIN_DEBUG, true) {
		fmt.printf("=== REGISTER PANEL: %s (unfolded: %v) ===\n", name, start_unfolded)
		if g_state == nil {
			fmt.printf("ERROR: g_state is nil in debug_register_panel_with_config\n")
			return
		}

		debug_sys := &g_state.debug_system

		if debug_sys.panel_count >= MAX_DEBUG_PANELS {
			fmt.printf("ERROR: Maximum debug panels reached (%d)\n", MAX_DEBUG_PANELS)
			return
		}

		// find first available slot
		for i in 0..<MAX_DEBUG_PANELS {
			if !debug_sys.panels[i].active {
				debug_sys.panels[i] = Debug_Panel{
					name = name,
					render_proc = panel_proc,
					enabled = true,
					active = true,
					start_unfolded = start_unfolded,
				}
				debug_sys.panel_count += 1
				fmt.printf("SUCCESS: Registered debug panel: %s (slot %d, total: %d, unfolded: %v)\n", name, i, debug_sys.panel_count, start_unfolded)
				return
			}
		}

		fmt.printf("ERROR: No available slots for panel '%s'\n", name)
	}
}

// register a debug panel
debug_register_panel :: proc(name: string, panel_proc: Debug_Panel_Proc) {
	when #config(ODIN_DEBUG, true) {
		fmt.printf("=== REGISTER PANEL: %s ===\n", name)
		if g_state == nil {
			fmt.printf("ERROR: g_state is nil in debug_register_panel\n")
			return
		}

		debug_sys := &g_state.debug_system

		if debug_sys.panel_count >= MAX_DEBUG_PANELS {
			fmt.printf("ERROR: Maximum debug panels reached (%d)\n", MAX_DEBUG_PANELS)
			return
		}

		// find first available slot
		for i in 0..<MAX_DEBUG_PANELS {
			if !debug_sys.panels[i].active {
				debug_sys.panels[i] = Debug_Panel{
					name = name,
					render_proc = panel_proc,
					enabled = true,
					active = true,
					start_unfolded = false,
				}
				debug_sys.panel_count += 1
				fmt.printf("SUCCESS: Registered debug panel: %s (slot %d, total: %d)\n", name, i, debug_sys.panel_count)
				return
			}
		}

		fmt.printf("ERROR: No available slots for panel '%s'\n", name)
	}
}

debug_system_render :: proc(ctx: ^mu.Context) {
	when #config(ODIN_DEBUG, true) {
		if g_state == nil || !g_state.debug_ui_enabled do return

		debug_sys := &g_state.debug_system
		if !debug_sys.initialized || !debug_sys.enabled do return

		ctx.style.colors[.WINDOW_BG] = {0, 0, 0, 200}           // Window background
		ctx.style.colors[.BUTTON] = {60, 60, 60, 180}           // Header normal
		ctx.style.colors[.BUTTON_HOVER] = {80, 80, 80, 200}     // Header hover
		ctx.style.colors[.BUTTON_FOCUS] = {100, 100, 100, 220}  // Header focus

		if mu.begin_window(ctx, "Debug System", {12, 12, 500, i32(g_state.resolution.y) - 24}, {.NO_CLOSE}) {
			mu.layout_row(ctx, {-1}, 0)
			mu.label(ctx, fmt.tprintf("Panels: %d/%d", debug_sys.panel_count, MAX_DEBUG_PANELS))

			for i in 0..<MAX_DEBUG_PANELS {
				panel := &debug_sys.panels[i]
				if panel.active && panel.enabled && panel.render_proc != nil {
					mu.layout_row(ctx, {-1}, 0)
					panel.render_proc(ctx)
				}
			}
		}
		mu.end_window(ctx)
	}
}

debug_system_hot_reload :: proc() {
	when #config(ODIN_DEBUG, true) {
		fmt.printf("=== DEBUG HOT RELOAD (ARRAY VERSION) ===\n")
		debug_system_init()
	}
}

debug_system_toggle :: proc() {
	when #config(ODIN_DEBUG, true) {
		if g_state == nil do return
		debug_sys := &g_state.debug_system
		debug_sys.enabled = !debug_sys.enabled
		fmt.printf("Debug system toggled: %v\n", debug_sys.enabled)
	}
}
