package gamelogic

import "core:math"
import "core:fmt"
import rl "vendor:raylib"

MAX_TRAIL_LENGTH :: 120
TRAIL_WIDTH_FACTOR :: 2.0
TRAIL_OFFSET :: 2.5
TRAIL_SMOOTHING_SEGMENTS :: 30

// trail position (I'll store world space only)
Trail_Position :: struct {
	world_position:  rl.Vector2,                       // world position where triangle was created
	timestamp:       f32,
}

Ship_Trail :: struct {
	max_length:      int,                              // max number of positions in the trail
	ship_radius:     f32,                              // radius of the ship
	min_distance:    f32,                              // min world distance before creating new triangle
	last_world_pos:  rl.Vector2,                       // last world position where we created a triangle
	thruster_offset: rl.Vector2,                       // offset from ship center to thruster position (local space)

	positions:       [MAX_TRAIL_LENGTH]Trail_Position, // circular buffer of positions
	position_count:  int,                              // number of positions in the trail
	head_index:      int,                              // circular buffer head

	// render data
	vertices:        [MAX_TRAIL_LENGTH * 2 * 3]f32,    // 2 vertices per position, 3 components each (x,y,z)
	uvs:             [MAX_TRAIL_LENGTH * 2 * 2]f32,    // 2 vertices per position, 2 UV components each
	indices:         [MAX_TRAIL_LENGTH * 6]u16,        // 6 indices per segment (2 triangles)

	// raylib's mesh and material
	mesh:            rl.Mesh,                           // mesh data
	material:        rl.Material,                       // material data
	shader:          rl.Shader,                         // shader data

	// uniforms
	time_uniform:    i32,                              // time uniform
	color_uniform:   i32,                              // color uniform
	opacity_uniform: i32,                              // opacity uniform
	aspect_ratio_uniform: i32,                         // trail aspect ratio uniform
	active_triangle_count: int,                        // number of active triangles
	initialized: bool,                                 // whether the trail is initialized
	hot_reloading: bool,                               // flag to disable rendering during hot reload
}

init_ship_trail :: proc(trail: ^Ship_Trail, ship_radius: f32) -> bool {
	trail.max_length = MAX_TRAIL_LENGTH
	trail.ship_radius = ship_radius
	trail.min_distance = ship_radius * 0.25
	trail.position_count = 0
	trail.head_index = 0

	// Set default thruster offset (behind the ship, adjustable for fine-tuning)
	trail.thruster_offset = rl.Vector2{-ship_radius * TRAIL_OFFSET, 0.0} // 1.5x ship radius behind center
	trail.last_world_pos = {0, 0}

	// initialize positions array
	for i in 0..<MAX_TRAIL_LENGTH {
		trail.positions[i] = Trail_Position{}
	}

	// generate indices for triangle strips
	index := 0
	for i in 0..<MAX_TRAIL_LENGTH-1 {
		left_top := u16(i * 2)
		right_top := u16(i * 2 + 1)
		left_bottom := u16((i + 1) * 2)
		right_bottom := u16((i + 1) * 2 + 1)

		// first tri
		trail.indices[index] = left_top
		trail.indices[index + 1] = right_top
		trail.indices[index + 2] = left_bottom

		// second tri
		trail.indices[index + 3] = right_top
		trail.indices[index + 4] = right_bottom
		trail.indices[index + 5] = left_bottom

		index += 6
	}

	// create mesh
	trail.mesh = rl.Mesh{}
	trail.mesh.vertexCount = MAX_TRAIL_LENGTH * 2
	trail.mesh.triangleCount = (MAX_TRAIL_LENGTH - 1) * 2

	// allocate mesh data
	trail.mesh.vertices = raw_data(trail.vertices[:])
	trail.mesh.texcoords = raw_data(trail.uvs[:])
	trail.mesh.indices = raw_data(trail.indices[:])

	// load trail shader using resolve_shader_path like other systems
	vertex_shader_path := resolve_shader_path("default.vert")
	defer delete(vertex_shader_path)

	fragment_shader_path := resolve_shader_path("ship-trail.frag")
	defer delete(fragment_shader_path)

	// try to load shader files
	vertex_data, vertex_ok := file_reader_func(vertex_shader_path)
	fragment_data, fragment_ok := file_reader_func(fragment_shader_path)

	if !vertex_ok || !fragment_ok {
		trail.shader = rl.Shader{}
	} else {
		defer delete(vertex_data)
		defer delete(fragment_data)

		vertex_code := string(vertex_data)
		fragment_code := string(fragment_data)

		trail.shader = rl.LoadShaderFromMemory(
			len(vertex_code) > 0 ? cstring(raw_data(vertex_code)) : nil,
			len(fragment_code) > 0 ? cstring(raw_data(fragment_code)) : nil,
		)
	}

	// get uniform loc
	trail.time_uniform = rl.GetShaderLocation(trail.shader, "time")
	trail.color_uniform = rl.GetShaderLocation(trail.shader, "color")
	trail.opacity_uniform = rl.GetShaderLocation(trail.shader, "opacity")
	trail.aspect_ratio_uniform = rl.GetShaderLocation(trail.shader, "trail_aspect_ratio")

	// create material
	trail.material = rl.LoadMaterialDefault()
	trail.material.shader = trail.shader

	// upload mesh to GPU
	rl.UploadMesh(&trail.mesh, false)

	rl.UpdateMeshBuffer(trail.mesh, 0, raw_data(trail.vertices[:]), len(trail.vertices) * size_of(f32), 0)
	rl.UpdateMeshBuffer(trail.mesh, 1, raw_data(trail.uvs[:]), len(trail.uvs) * size_of(f32), 0)
	// Note: Indices are handled separately in Raylib, not through UpdateMeshBuffer with index 2
	// Index 2 would be for normals, which we don't use in this trail system

	trail.initialized = true
	return true
}

ship_trail_hot_reload :: proc(trail: ^Ship_Trail) -> bool {
	if !trail.initialized {
		fmt.printf("ERROR: Ship trail hot reload: Trail not initialized\n")
		return false
	}

	trail.hot_reloading = true

	if trail.mesh.vertices != nil && trail.mesh.vaoId != 0 {
		trail.mesh.vertices = nil
		trail.mesh.texcoords = nil
		trail.mesh.indices = nil

		rl.UnloadMesh(trail.mesh)
		trail.mesh = rl.Mesh{}
	} else {
		fmt.printf("Mesh not properly uploaded, skipping unload\n")
	}

	if trail.material.shader.id != 0 {
		rl.UnloadMaterial(trail.material)
	} else {
		fmt.printf("Material not properly created, skipping unload\n")
	}

	vertex_shader_path := resolve_shader_path("default.vert")
	defer delete(vertex_shader_path)

	fragment_shader_path := resolve_shader_path("ship-trail.frag")
	defer delete(fragment_shader_path)

	vertex_data, vertex_ok := file_reader_func(vertex_shader_path)

	fragment_data, fragment_ok := file_reader_func(fragment_shader_path)

	if !vertex_ok || !fragment_ok {
		fmt.printf("ERROR: Failed to read shader files (vertex=%v, fragment=%v)\n", vertex_ok, fragment_ok)
		trail.shader = rl.Shader{}
		return false
	}
	defer delete(vertex_data)
	defer delete(fragment_data)

	vertex_code := string(vertex_data)
	fragment_code := string(fragment_data)

	trail.shader = rl.LoadShaderFromMemory(
		len(vertex_code) > 0 ? cstring(raw_data(vertex_code)) : nil,
		len(fragment_code) > 0 ? cstring(raw_data(fragment_code)) : nil,
	)

	if trail.shader.id == 0 {
		fmt.printf("ERROR: Failed to compile shader\n")
		return false
	}

	// re-create material
	trail.material = rl.LoadMaterialDefault()
	trail.material.shader = trail.shader

	// re-create mesh
	trail.mesh = rl.Mesh{}
	trail.mesh.vertices = raw_data(trail.vertices[:])
	trail.mesh.texcoords = raw_data(trail.uvs[:])
	trail.mesh.indices = raw_data(trail.indices[:])
	trail.mesh.vertexCount = i32(MAX_TRAIL_LENGTH * 2)
	trail.mesh.triangleCount = i32((MAX_TRAIL_LENGTH - 1) * 2)
	rl.UploadMesh(&trail.mesh, false)

	// get uniform locs
	trail.time_uniform = rl.GetShaderLocation(trail.shader, "time")
	trail.color_uniform = rl.GetShaderLocation(trail.shader, "color")
	trail.opacity_uniform = rl.GetShaderLocation(trail.shader, "opacity")
	trail.aspect_ratio_uniform = rl.GetShaderLocation(trail.shader, "trail_aspect_ratio")

	// update thruster offset
	trail.thruster_offset = rl.Vector2{-trail.ship_radius * TRAIL_OFFSET, 0.0}

	// re-enable rendering
	trail.hot_reloading = false

	return true
}

destroy_ship_trail :: proc(trail: ^Ship_Trail) {
	if !trail.initialized {
		return
	}

	defer trail.initialized = false

	if trail.mesh.vertices != nil {
		rl.UnloadMesh(trail.mesh)
	}

	if trail.material.shader.id != 0 {
		rl.UnloadMaterial(trail.material)
	}

	if trail.shader.id != 0 {
		rl.UnloadShader(trail.shader)
	}
}

add_trail_position :: proc(
  trail: ^Ship_Trail,
  ship_world_pos: rl.Vector2,
  ship_rotation: f32,
  ship_speed: f32,
  max_ship_speed: f32,
  current_time: f32,
) {
	if !trail.initialized {
		return
	}

	// calculate thruster world position by applying rotation to the offset
	cos_rot := math.cos(math.to_radians(ship_rotation))
	sin_rot := math.sin(math.to_radians(ship_rotation))

	// rotate the thruster offset and add to ship position
	rotated_offset_x := trail.thruster_offset.x * cos_rot - trail.thruster_offset.y * sin_rot
	rotated_offset_y := trail.thruster_offset.x * sin_rot + trail.thruster_offset.y * cos_rot

	thruster_world_pos := rl.Vector2{
		ship_world_pos.x + rotated_offset_x,
		ship_world_pos.y + rotated_offset_y,
	}

	// calculate distance moved in world space since last tri (using thruster position)
	if trail.position_count > 0 {
		dx := thruster_world_pos.x - trail.last_world_pos.x
		dy := thruster_world_pos.y - trail.last_world_pos.y
		distance_moved := math.sqrt(dx * dx + dy * dy)

		normalized_speed := math.clamp(ship_speed / max_ship_speed, 1e-3, 1.0)
		distance_threshold := trail.min_distance * normalized_speed

		// only create new tri if moved enough distance
		if distance_moved < distance_threshold {
			return
		}
	}

	// add thruster world position to circular buffer
	trail.positions[trail.head_index] = Trail_Position{
		world_position = thruster_world_pos,
		timestamp = current_time,
	}

	// update last world position (using thruster position)
	trail.last_world_pos = thruster_world_pos

	trail.head_index = (trail.head_index + 1) % MAX_TRAIL_LENGTH
	if trail.position_count < MAX_TRAIL_LENGTH {
		trail.position_count += 1
	}
}

update_trail_geometry :: proc(trail: ^Ship_Trail, current_time: f32, camera: ^Camera_State, window_width: f32, window_height: f32, ship_rotation: f32) {
	// if !trail.initialized || trail.position_count < 2 {
	// 	return
	// }

	last_valid_pos := rl.Vector2{}
	if trail.position_count > 0 {
		tail_idx := (trail.head_index - trail.position_count + MAX_TRAIL_LENGTH) % MAX_TRAIL_LENGTH
		tail_world_pos := trail.positions[tail_idx].world_position
		last_valid_pos = rl.Vector2{
			tail_world_pos.x - camera.position.x + window_width / 2,
			tail_world_pos.y - camera.position.y + window_height / 2,
		}
	} else {
		last_valid_pos = rl.Vector2{window_width / 2, window_height / 2}
	}

	for i in 0..<len(trail.vertices) {
		if i % 3 == 2 {
			trail.vertices[i] = 0.0
		} else if i % 3 == 0 {
			trail.vertices[i] = last_valid_pos.x
		} else {
			trail.vertices[i] = last_valid_pos.y
		}
	}

	for i in 0..<len(trail.uvs) {
		if i % 2 == 0 {
			trail.uvs[i] = 1.0
		} else {
			trail.uvs[i] = 0.5
		}
	}

	// convert world positions to screen positions (transform by camera)
	screen_positions: [MAX_TRAIL_LENGTH]rl.Vector2
	count := 0

	// start from the most recent position (head - 1) and go backwards
	for i in 0..<trail.position_count {
		pos_idx := (trail.head_index - 1 - i + MAX_TRAIL_LENGTH) % MAX_TRAIL_LENGTH
		world_pos := trail.positions[pos_idx].world_position

		// transform world position to screen position (same as ship positioning logic)
		screen_pos := rl.Vector2{
			world_pos.x - camera.position.x + window_width / 2,
			world_pos.y - camera.position.y + window_height / 2,
		}

		screen_positions[count] = screen_pos
		count += 1
	}

	for i in 0..<count-1 {
		current_screen_pos := screen_positions[i]
		next_screen_pos := screen_positions[i + 1]

		direction: rl.Vector2
		if i == 0 {
			cos_rot := math.cos(math.to_radians(ship_rotation))
			sin_rot := math.sin(math.to_radians(ship_rotation))
			direction = rl.Vector2{cos_rot, sin_rot}
		} else {
			direction = rl.Vector2{
				current_screen_pos.x - next_screen_pos.x,
				current_screen_pos.y - next_screen_pos.y,
			}

			// skip if direction is too small (positions too close)
			length_sq := direction.x * direction.x + direction.y * direction.y
			if length_sq < 0.001 {
				continue
			}

			// normalize direction
			length := math.sqrt(length_sq)
			direction.x /= length
			direction.y /= length
		}

		// smooth the first segments to reduce sharp bends near the ship or misalignment
		if i > 0 && i < TRAIL_SMOOTHING_SEGMENTS {
			// Get the ship's rotation direction for blending
			cos_rot := math.cos(math.to_radians(ship_rotation))
			sin_rot := math.sin(math.to_radians(ship_rotation))
			ship_direction := rl.Vector2{cos_rot, sin_rot}

			ship_influence := f32(0.5) * (1.0 - f32(i-1) / f32(TRAIL_SMOOTHING_SEGMENTS - 1) * 2.0)
			if ship_influence < 0.0 {
				ship_influence = 0.0 // Ensure it doesn't go negative
			}

			// blend trail direction with ship direction
			direction.x = direction.x * (1.0 - ship_influence) + ship_direction.x * ship_influence
			direction.y = direction.y * (1.0 - ship_influence) + ship_direction.y * ship_influence

			// re-normalize after blending
			blend_length := math.sqrt(direction.x * direction.x + direction.y * direction.y)
			if blend_length > 0.001 {
				direction.x /= blend_length
				direction.y /= blend_length
			}
		}

		// Calculate perpendicular for trail width (thickness decreases towards tail)
		// i=0 is newest (ship), i=count-1 is oldest (tail)
		thickness_factor := 1.0 - f32(i) / f32(count - 1)
		perpendicular := rl.Vector2{
			-direction.y, // perpendicular to direction
			direction.x,
		}
		trail_width := (trail.ship_radius * TRAIL_WIDTH_FACTOR) * thickness_factor
		perpendicular.x *= trail_width
		perpendicular.y *= trail_width

		// set vertices (2 vertices per position: left and right)
		// vertex layout: [left0_xyz, right0_xyz, left1_xyz, right1_xyz, ...]
		left_vertex_index := i * 2 * 3      // each position has 2 vertices, each vertex has 3 components
		right_vertex_index := left_vertex_index + 3

		// use screen positions directly (like projectiles!)
		// left vertex (in SCREEN coordinates)
		trail.vertices[left_vertex_index + 0] = current_screen_pos.x + perpendicular.x
		trail.vertices[left_vertex_index + 1] = current_screen_pos.y + perpendicular.y
		trail.vertices[left_vertex_index + 2] = 0.0

		// right vertex (in SCREEN coordinates)
		trail.vertices[right_vertex_index + 0] = current_screen_pos.x - perpendicular.x
		trail.vertices[right_vertex_index + 1] = current_screen_pos.y - perpendicular.y
		trail.vertices[right_vertex_index + 2] = 0.0

		// set UVs (u goes from 0 at head to 1 at tail)
		// UV layout: [left0_uv, right0_uv, left1_uv, right1_uv, ...]
		left_uv_index := i * 2 * 2          // each position has 2 vertices, each vertex has 2 UV components
		right_uv_index := left_uv_index + 2
		u := f32(i) / f32(count - 1)

		trail.uvs[left_uv_index + 0] = u     // left U
		trail.uvs[left_uv_index + 1] = 0.0   // left V (top of trail)
		trail.uvs[right_uv_index + 0] = u    // right U
		trail.uvs[right_uv_index + 1] = 1.0  // right V (bottom of trail)
	}

	// generate indices for active segments
	index := 0
	for i in 0..<count-1 {
		left_top := u16(i * 2)
		right_top := u16(i * 2 + 1)
		left_bottom := u16((i + 1) * 2)
		right_bottom := u16((i + 1) * 2 + 1)

		// first triangle
		trail.indices[index] = left_top
		trail.indices[index + 1] = right_top
		trail.indices[index + 2] = left_bottom

		// second triangle
		trail.indices[index + 3] = right_top
		trail.indices[index + 4] = right_bottom
		trail.indices[index + 5] = left_bottom

		index += 6
	}

	// update mesh on GPU
	rl.UpdateMeshBuffer(trail.mesh, 0, raw_data(trail.vertices[:]), len(trail.vertices) * size_of(f32), 0)
	rl.UpdateMeshBuffer(trail.mesh, 1, raw_data(trail.uvs[:]), len(trail.uvs) * size_of(f32), 0)
	// Note: Indices are handled separately in Raylib, not through UpdateMeshBuffer with index 2
	// Index 2 would be for normals, which we don't use in this trail system

	// store the number of active triangles for rendering
	trail.active_triangle_count = count - 1
}

render_ship_trail :: proc(trail: ^Ship_Trail, current_time: f32, camera: ^Camera_State, window_width: f32, window_height: f32, ship_rotation: f32) {
	if !trail.initialized || trail.position_count < 2 || trail.hot_reloading {
		return
	}

	// update geometry every frame (world positions need to be transformed to current screen positions)
	update_trail_geometry(trail, current_time, camera, window_width, window_height, ship_rotation)

	time_value := current_time
	rl.SetShaderValue(trail.shader, trail.time_uniform, &time_value, .FLOAT)

	trail_color := [3]f32{1.0, 1.0, 1.0}
	rl.SetShaderValue(trail.shader, trail.color_uniform, &trail_color, .VEC3)

	trail_opacity := f32(0.6)
	rl.SetShaderValue(trail.shader, trail.opacity_uniform, &trail_opacity, .FLOAT)

	// estimate aspect ratio: trail length vs trail thickness
	// length is roughly the number of segs * average seg length
	// thickness is ship_radius * TRAIL_WIDTH_FACTOR
	trail_length := f32(trail.position_count) * trail.min_distance
	trail_thickness := trail.ship_radius * TRAIL_WIDTH_FACTOR
	aspect_ratio := trail_length / trail_thickness
	// clamp to reasonable values and add a multiplier for visual effect
	aspect_ratio = math.clamp(aspect_ratio * 0.5, 1.0, 20.0)
	rl.SetShaderValue(trail.shader, trail.aspect_ratio_uniform, &aspect_ratio, .FLOAT)

	// only render if we have active triangles
	if trail.active_triangle_count > 0 {
		rl.BeginBlendMode(.ALPHA)

		// temporarily update the mesh triangle count to only render active triangles
		original_triangle_count := trail.mesh.triangleCount
		trail.mesh.triangleCount = i32(trail.active_triangle_count * 2)

		// draw mesh with material
		rl.DrawMesh(trail.mesh, trail.material, rl.Matrix(1))

		// restore original triangle count
		trail.mesh.triangleCount = original_triangle_count

		rl.EndBlendMode()
	}
}

reset_ship_trail :: proc(trail: ^Ship_Trail, world_pos: rl.Vector2, current_time: f32) {
	if !trail.initialized {
		return
	}

	// clear all positions
	for i in 0..<MAX_TRAIL_LENGTH {
		trail.positions[i] = Trail_Position{}
	}

	trail.position_count = 0
	trail.head_index = 0
	trail.last_world_pos = world_pos
}

// set thruster offset for fine-tuning (local space relative to ship center)
set_thruster_offset :: proc(trail: ^Ship_Trail, offset: rl.Vector2) {
	trail.thruster_offset = offset
}
