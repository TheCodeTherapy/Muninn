package gamelogic

import "core:fmt"
import mu "vendor:microui"

RENDER_PANEL_NAME :: "Render Information"
RENDER_PANEL_UNFOLDED :: true

debug_render_panel :: proc(ctx: ^mu.Context) {
	if g_state == nil {
		mu.label(ctx, "Game state not available")
		return
	}

	if .ACTIVE in mu.header(ctx, RENDER_PANEL_NAME, RENDER_PANEL_UNFOLDED ? {.EXPANDED} : {}) {
		mu.layout_row(ctx, {150, 200}, 0)

		mu.label(ctx, "Total Render Time:")
		mu.label(ctx, fmt.tprintf("%.3f ms (%.3f ms avg)", g_state.render_timing.total_render_time, g_state.render_timing.average_render_time))

		mu.label(ctx, "Step 1 - Space BG:")
		mu.label(ctx, fmt.tprintf("%.3f ms", g_state.render_timing.step1_space_background))

		mu.label(ctx, "Step 2 - Ship Render:")
		mu.label(ctx, fmt.tprintf("%.3f ms", g_state.render_timing.step2_ship_render))

		mu.label(ctx, "Step 3 - BG Draw:")
		mu.label(ctx, fmt.tprintf("%.3f ms", g_state.render_timing.step3_background_draw))

		mu.label(ctx, "Step 4 - Ship Draw:")
		mu.label(ctx, fmt.tprintf("%.3f ms", g_state.render_timing.step4_ship_draw))

		mu.label(ctx, "Step 5 - Bloom/Final:")
		mu.label(ctx, fmt.tprintf("%.3f ms", g_state.render_timing.step5_bloom_or_final))

		mu.label(ctx, "Debug UI:")
		mu.label(ctx, fmt.tprintf("%.3f ms", g_state.render_timing.step6_debug_ui))

		mu.layout_row(ctx, {-1}, 5)
		mu.label(ctx, "")

		mu.layout_row(ctx, {150, 200}, 0)
    mu.label(ctx, "Space Background:")
		mu.label(
      ctx,
      fmt.tprintf(
        "ID=%d (%dx%d)",
        g_state.space_background_texture.id,
        g_state.space_background_texture.width,
        g_state.space_background_texture.height,
      ),
    )

    mu.label(ctx, "Ship RT:")
		mu.label(
      ctx,
      fmt.tprintf(
        "ID=%d (%dx%d)",
        g_state.ship_render_target.id,
        g_state.ship_render_target.texture.width,
        g_state.ship_render_target.texture.height,
      ),
    )

    mu.label(ctx, "Bloom Composite RT:")
		mu.label(
      ctx,
      fmt.tprintf(
        "ID=%d (%dx%d)",
        g_state.bloom_composite_target.id,
        g_state.bloom_composite_target.texture.width,
        g_state.bloom_composite_target.texture.height,
      ),
    )

		mu.label(ctx, "Final RT:")
		mu.label(
      ctx,
      fmt.tprintf(
        "ID=%d (%dx%d)",
        g_state.final_render_target.id,
        g_state.final_render_target.texture.width,
        g_state.final_render_target.texture.height,
      ),
    )
	}
}

debug_render_panel_config :: proc() -> (name: string, start_unfolded: bool) {
	return RENDER_PANEL_NAME, RENDER_PANEL_UNFOLDED
}
