package game

import ship "."
import "core:fmt"
import rl "vendor:raylib"

Game_Memory :: struct {
	resolution:       rl.Vector2,
	player_pos:       rl.Vector2,
	player_texture:   rl.Texture,
	fps:              int,
	delta_time:       f32,
	global_time:      f32,
	frame:            int,
	player:           ship.Ship,
	shaderTarget:     rl.RenderTexture2D,
	bg_shader:        rl.Shader,
	u_resolution_loc: i32,
	u_time_loc:       i32,
}

g_mem: ^Game_Memory

update :: proc() {
	width := f32(rl.GetScreenWidth())
	height := f32(rl.GetScreenHeight())
	delta_time := rl.GetFrameTime()

	if g_mem.resolution.x != width || g_mem.resolution.y != height {
		rl.UnloadRenderTexture(g_mem.shaderTarget)
		g_mem.shaderTarget = rl.LoadRenderTexture(i32(width), i32(height))
		g_mem.resolution = rl.Vector2{width, height}
	}

	update_ship(&g_mem.player, delta_time, width, height)

	g_mem.player_pos = g_mem.player.position

	g_mem.frame += 1
	g_mem.fps = int(rl.GetFPS())
	g_mem.delta_time = delta_time
	g_mem.global_time += delta_time
}

draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)

	rl.BeginShaderMode(g_mem.bg_shader)
	rl.SetShaderValue(g_mem.bg_shader, g_mem.u_resolution_loc, &g_mem.resolution, .VEC2)
	rl.SetShaderValue(g_mem.bg_shader, g_mem.u_time_loc, &g_mem.global_time, .FLOAT)
	rl.DrawTextureRec(
		g_mem.shaderTarget.texture,
		rl.Rectangle {
			0,
			0,
			f32(g_mem.shaderTarget.texture.width),
			-f32(g_mem.shaderTarget.texture.height),
		},
		rl.Vector2{0, 0},
		rl.WHITE,
	)
	rl.EndShaderMode()

	draw_ship(&g_mem.player)


	player_pos_x := fmt.ctprintf("%09.4f", g_mem.player_pos.x)
	player_pos_y := fmt.ctprintf("%09.4f", g_mem.player_pos.y)
	dt := fmt.ctprintf("%0.5f", g_mem.delta_time)
	time := fmt.ctprintf("%0.5f", g_mem.global_time)
	text := fmt.ctprintf(
		"fps: %v\ndt: %v\ntime: %v\nframe: %v\nplayer_pos: (%s, %s)\nres_loc: %v\ntime_loc: %v",
		g_mem.fps,
		dt,
		time,
		g_mem.frame,
		player_pos_x,
		player_pos_y,
		g_mem.u_resolution_loc,
		g_mem.u_time_loc,
	)
	rl.DrawText(text, 10, 10, 20, rl.WHITE)

	rl.EndDrawing()
}

@(export)
game_update :: proc() {
	update()
	draw()
}

@(export)
game_init_window :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .MSAA_4X_HINT})
	rl.InitWindow(1600, 900, "wip")
	rl.SetWindowPosition(200, 200)
}

@(export)
game_init :: proc() {
	g_mem = new(Game_Memory)

	bg_shader := rl.LoadShader("shaders/default_300.vert", "shaders/space_300.frag")

	u_resolution_location := rl.GetShaderLocation(bg_shader, "resolution")
	u_time_location := rl.GetShaderLocation(bg_shader, "time")

	width := rl.GetScreenWidth()
	height := rl.GetScreenHeight()

	g_mem^ = Game_Memory {
		resolution       = rl.Vector2{f32(width), f32(height)},
		fps              = 0,
		delta_time       = 0,
		global_time      = 0,
		frame            = 1,
		player_texture   = rl.LoadTexture("assets/round_cat.png"),
		player           = init_ship(f32(width), f32(height)),
		shaderTarget     = rl.LoadRenderTexture(width, height),
		bg_shader        = bg_shader,
		u_resolution_loc = u_resolution_location,
		u_time_loc       = u_time_location,
	}


	game_hot_reloaded(g_mem)
}

@(export)
game_should_close :: proc() -> bool {
	return rl.WindowShouldClose()
}

@(export)
game_shutdown :: proc() {
	free(g_mem)
}

@(export)
game_shutdown_window :: proc() {
	rl.CloseWindow()
}

@(export)
game_memory :: proc() -> rawptr {
	return g_mem
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(Game_Memory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g_mem = (^Game_Memory)(mem)

	// Here you can also set your own global variables. A good idea is to make
	// your global variables into pointers that point to something inside
	// `g_mem`.
}

@(export)
game_force_reload :: proc() -> bool {
	return rl.IsKeyPressed(.F5)
}

@(export)
game_force_restart :: proc() -> bool {
	return rl.IsKeyPressed(.F6)
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
game_parent_window_size_changed :: proc(w, h: int) {
	rl.SetWindowSize(i32(w), i32(h))
}
