package game

import math "core:math"
import rl "vendor:raylib"

MAX_PROJECTILES :: 1000

Projectile :: struct {
	position: rl.Vector2,
	velocity: rl.Vector2,
	active:   bool,
}

Ship :: struct {
	scale:          f32,
	position:       rl.Vector2,
	velocity:       rl.Vector2,
	rotation:       f32,
	acceleration:   f32,
	friction:       f32,
	shoot_cooldown: f32,
	shoot_interval: f32,
	projectiles:    [MAX_PROJECTILES]Projectile,
}

init_ship :: proc(window_width: f32, window_height: f32) -> Ship {
	return Ship {
		scale = 30,
		position = rl.Vector2{window_width / 2, window_height / 2},
		velocity = rl.Vector2{0.0, 0.0},
		rotation = 0.0,
		acceleration = 500.0,
		friction = 0.5,
		shoot_cooldown = 0.0,
		shoot_interval = 0.0125,
		projectiles = [MAX_PROJECTILES]Projectile{},
	}
}

shoot_projectile :: proc(ship: ^Ship) {
	if ship.shoot_cooldown > 0.0 {
		return
	}
	for &projectile in &ship.projectiles {
		if !projectile.active {
			radians := ship.rotation * rl.DEG2RAD

			projectile.position = rl.Vector2 {
				ship.position.x + math.cos(radians) * ship.scale,
				ship.position.y + math.sin(radians) * ship.scale,
			}
			projectile_velocity := rl.Vector2{math.cos(radians), math.sin(radians)} * 250.0
			projectile.velocity = projectile_velocity + ship.velocity

			projectile.active = true
			ship.shoot_cooldown = ship.shoot_interval
			break
		}
	}
}

update_projectiles :: proc(ship: ^Ship, delta_time: f32, window_width: f32, window_height: f32) {
	for &projectile in &ship.projectiles {
		if projectile.active {
			projectile.position.x += projectile.velocity.x * delta_time
			projectile.position.y += projectile.velocity.y * delta_time

			if (projectile.position.x < 0 ||
				   projectile.position.x > window_width ||
				   projectile.position.y < 0 ||
				   projectile.position.y > window_height) {
				projectile.active = false
			}
		}
	}
}

draw_projectiles :: proc(ship: ^Ship) {
	for projectile in &ship.projectiles {
		if projectile.active {
			rl.DrawCircleV(projectile.position, 5.0, rl.YELLOW)
		}
	}
}

update_ship :: proc(ship: ^Ship, delta_time: f32, window_width: f32, window_height: f32) {
	if rl.IsKeyDown(rl.KeyboardKey.RIGHT) {
		ship.rotation += 180.0 * delta_time
	}
	if rl.IsKeyDown(rl.KeyboardKey.LEFT) {
		ship.rotation -= 180.0 * delta_time
	}

	if rl.IsKeyDown(rl.KeyboardKey.UP) {
		radians := ship.rotation * rl.DEG2RAD
		ship.velocity.x += math.cos(radians) * ship.acceleration * delta_time
		ship.velocity.y += math.sin(radians) * ship.acceleration * delta_time
	}

	ship.velocity.x *= 1.0 - (ship.friction * delta_time)
	ship.velocity.y *= 1.0 - (ship.friction * delta_time)

	ship.position.x += ship.velocity.x * delta_time
	ship.position.y += ship.velocity.y * delta_time

	if ship.position.x > window_width {
		ship.position.x = 0
	} else if ship.position.x < 0 {
		ship.position.x = window_width
	}
	if ship.position.y > window_height {
		ship.position.y = 0
	} else if ship.position.y < 0 {
		ship.position.y = window_height
	}

	if rl.IsKeyDown(rl.KeyboardKey.SPACE) {
		shoot_projectile(ship)
	}

	if ship.shoot_cooldown > 0.0 {
		ship.shoot_cooldown -= delta_time
	}

	update_projectiles(ship, delta_time, window_width, window_height)
}

draw_ship :: proc(ship: ^Ship) {
	radians := ship.rotation * rl.DEG2RAD

	tip := rl.Vector2 {
		ship.position.x + math.cos(radians) * ship.scale,
		ship.position.y + math.sin(radians) * ship.scale,
	}
	left := rl.Vector2 {
		ship.position.x + math.cos(radians + rl.DEG2RAD * 135.0) * ship.scale,
		ship.position.y + math.sin(radians + rl.DEG2RAD * 135.0) * ship.scale,
	}
	right := rl.Vector2 {
		ship.position.x + math.cos(radians - rl.DEG2RAD * 135.0) * ship.scale,
		ship.position.y + math.sin(radians - rl.DEG2RAD * 135.0) * ship.scale,
	}

	rl.DrawLine(i32(tip.x), i32(tip.y), i32(left.x), i32(left.y), rl.WHITE)
	rl.DrawLine(i32(tip.x), i32(tip.y), i32(right.x), i32(right.y), rl.WHITE)
	rl.DrawLine(i32(left.x), i32(left.y), i32(right.x), i32(right.y), rl.WHITE)
	// rl.DrawTriangle(tip, right, left, rl.DARKGRAY)
	draw_projectiles(ship)
}
