package gamelogic

import "core:fmt"
import mu "vendor:microui"

CORE_PANEL_NAME :: "Core Information"
CORE_PANEL_UNFOLDED :: true

debug_system_panel :: proc(ctx: ^mu.Context) {
	if g_state == nil {
		mu.label(ctx, "Game state not available")
		return
	}

	if .ACTIVE in mu.header(ctx, CORE_PANEL_NAME, {.EXPANDED}) {
		mu.layout_row(ctx, {150, 200}, 0)
		mu.label(ctx, "Global Time:")
		mu.label(ctx, fmt.tprintf("%.2f s", g_state.global_time))
		mu.label(ctx, "FPS:")
		mu.label(ctx, fmt.tprintf("%d", g_state.fps))
		mu.label(ctx, "Delta Time:")
		mu.label(ctx, fmt.tprintf("%.4f ms", g_state.delta_time * 1000.0))
		mu.label(ctx, "Frame:")
		mu.label(ctx, fmt.tprintf("%d", g_state.frame))
		mu.label(ctx, "Resolution:")
		mu.label(ctx, fmt.tprintf("%.0fx%.0f", g_state.resolution.x, g_state.resolution.y))
	}
}

debug_system_panel_config :: proc() -> (name: string, start_unfolded: bool) {
	return CORE_PANEL_NAME, CORE_PANEL_UNFOLDED
}
