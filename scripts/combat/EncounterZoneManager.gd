# scripts/combat/EncounterZoneManager.gd
class_name EncounterZoneManager
extends Node

const CombatRoomDataScript := preload("res://scripts/combat/CombatRoomData.gd")
const DestructibleWall3DScript := preload("res://scripts/combat/DestructibleWall3D.gd")
const CoverPoint3DScript := preload("res://scripts/combat/CoverPoint3D.gd")
const BattlefieldNavGridScript := preload("res://scripts/combat/BattlefieldNavGrid.gd")

signal sector_gate_unlocked(sector_index: int, gate_world_pos: Vector3)
signal battlefield_built(sector_count: int, bounds_min: Vector2, bounds_max: Vector2)

const DEFAULT_CORRIDOR_LENGTH: float = 10.0
const DEFAULT_GATEWAY_WIDTH: float = 16.0

var active_sectors: Array = []
var sector_connectors: Array[Node3D] = []
var sector_gates: Dictionary = {}
var sector_metadata: Array[Dictionary] = []
var nav_grid: BattlefieldNavGridScript = null

var bounds_min: Vector2 = Vector2(-65.0, -65.0)
var bounds_max: Vector2 = Vector2(65.0, 65.0)

var _packed_cache: Dictionary = {}
var _threaded_requested: Dictionary = {}

func _process(_delta: float) -> void:
	if _threaded_requested.is_empty():
		return
	var done_paths: Array[String] = []
	for path_var: Variant in _threaded_requested.keys():
		var path: String = str(path_var)
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var threaded_res := ResourceLoader.load_threaded_get(path) as PackedScene
			if threaded_res != null:
				_packed_cache[path] = threaded_res
			done_paths.append(path)
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			done_paths.append(path)
	for p in done_paths:
		_threaded_requested.erase(p)

## Queues background threaded loading for all unique sector scenes in layout and returns count of unique scenes.
func preload_layout_chunks(layout: Array[Dictionary]) -> int:
	var unique_paths: Dictionary = {}
	for entry in layout:
		var path: String = str(entry.get("room_scene_path", ""))
		if path.is_empty():
			continue
		unique_paths[path] = true
		if not _packed_cache.has(path) and not _threaded_requested.has(path):
			if ResourceLoader.exists(path):
				var err: Error = ResourceLoader.load_threaded_request(path)
				if err == OK:
					_threaded_requested[path] = true
	return unique_paths.size()

## Retrieves a preloaded or newly loaded PackedScene for the given sector scene path.
func get_chunk_scene(scene_path: String) -> PackedScene:
	if scene_path.is_empty():
		return null
	if _packed_cache.has(scene_path) and _packed_cache[scene_path] is PackedScene:
		return _packed_cache[scene_path] as PackedScene

	if _threaded_requested.has(scene_path):
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(scene_path)
		if status == ResourceLoader.THREAD_LOAD_LOADED or status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			var threaded_res := ResourceLoader.load_threaded_get(scene_path) as PackedScene
			if threaded_res != null:
				_packed_cache[scene_path] = threaded_res
				_threaded_requested.erase(scene_path)
				return threaded_res
		_threaded_requested.erase(scene_path)

	var loaded := load(scene_path) as PackedScene
	if loaded != null:
		_packed_cache[scene_path] = loaded
	return loaded

## Instantiates and stitches all encounter zones in layout into a continuous multi-sector 3D battlefield along -Z.
func build_seamless_battlefield(room_container: Node3D, layout: Array[Dictionary]) -> Array:
	clear_battlefield()
	if layout.is_empty():
		return active_sectors

	preload_layout_chunks(layout)

	var min_x: float = -36.0
	var max_x: float = 36.0
	var min_z: float = -28.0
	var max_z: float = 28.0

	var cur_z: float = 0.0
	var prev_depth: float = 0.0
	var total: int = layout.size()

	for i in range(total):
		var rdata: Dictionary = layout[i]
		var rtype: String = str(rdata.get("room_type", "COMBAT"))
		var scene_path: String = str(rdata.get("room_scene_path", "res://scenes/combat/rooms/room_combat.tscn"))
		var packed: PackedScene = get_chunk_scene(scene_path)
		if packed == null:
			continue

		var sector_inst := packed.instantiate()
		var sector := sector_inst as CombatRoomDataScript
		if sector == null:
			sector_inst.free()
			continue

		var dims: Vector2 = rdata.get("sector_dimensions", sector.arena_size)
		if dims.x <= 1.0 or dims.y <= 1.0:
			dims = sector.arena_size
		var corridor_len: float = float(rdata.get("corridor_length", DEFAULT_CORRIDOR_LENGTH))
		var gate_w: float = float(rdata.get("gateway_width", DEFAULT_GATEWAY_WIDTH))

		var origin: Vector3
		if rdata.has("sector_origin") and rdata["sector_origin"] is Vector3:
			origin = rdata["sector_origin"]
			cur_z = origin.z
		else:
			if i == 0:
				cur_z = 0.0
			else:
				var prev_north: float = cur_z - prev_depth * 0.5
				cur_z = prev_north - corridor_len - dims.y * 0.5
			origin = Vector3(0.0, 0.0, cur_z)
		prev_depth = dims.y

		sector.name = "Sector_%d_%s" % [i, rtype]
		sector.position = origin
		sector.sector_index = i
		sector.arena_size = dims
		if room_container != null:
			room_container.add_child(sector)

		var has_north_neighbor: bool = (i < total - 1)
		var has_south_neighbor: bool = (i > 0)
		sector.open_sector_gateways(has_north_neighbor, has_south_neighbor, gate_w)
		sector.setup_destructible_walls()

		var north_edge_z: float = origin.z - dims.y * 0.5
		var south_edge_z: float = origin.z + dims.y * 0.5
		min_x = minf(min_x, -dims.x * 0.5)
		max_x = maxf(max_x, dims.x * 0.5)
		min_z = minf(min_z, north_edge_z)
		max_z = maxf(max_z, south_edge_z)

		active_sectors.append(sector)
		sector_metadata.append({
			"sector_index": i,
			"room_type": rtype,
			"sector_origin": origin,
			"sector_dimensions": dims,
			"north_edge_z": north_edge_z,
			"south_edge_z": south_edge_z,
			"corridor_length": corridor_len,
			"gateway_width": gate_w,
		})

	for s in active_sectors:
		if s != null and is_instance_valid(s):
			s.linked_sectors = active_sectors.duplicate()
			if s.has_signal(&"wall_obstacle_added") and not s.wall_obstacle_added.is_connected(_on_sector_wall_added):
				s.wall_obstacle_added.connect(_on_sector_wall_added)

	for i in range(active_sectors.size() - 1):
		var cur_meta: Dictionary = sector_metadata[i]
		var next_meta: Dictionary = sector_metadata[i + 1]
		var north_edge_z: float = float(cur_meta["north_edge_z"])
		var next_south_z: float = float(next_meta["south_edge_z"])
		var gate_w: float = float(cur_meta.get("gateway_width", DEFAULT_GATEWAY_WIDTH))
		var next_type: String = str(next_meta.get("room_type", "COMBAT"))

		var connector := _create_sector_connector(i, north_edge_z, next_south_z, gate_w, next_type)
		if room_container != null:
			room_container.add_child(connector)
		sector_connectors.append(connector)

		var sector_node = active_sectors[i]
		var local_north_z: float = -float((cur_meta["sector_dimensions"] as Vector2).y) * 0.5
		var gate := _create_sector_gate(i, local_north_z, gate_w, next_type)
		sector_node.add_child(gate)
		sector_node.register_wall_obstacle(gate)
		sector_gates[i] = gate

	update_sector_visibility(0)

	bounds_min = Vector2(min_x - 24.0, min_z - 28.0)
	bounds_max = Vector2(max_x + 24.0, max_z + 28.0)
	rebuild_nav_grid()
	battlefield_built.emit(active_sectors.size(), bounds_min, bounds_max)
	return active_sectors

## Rebuilds the shared BattlefieldNavGrid across all active sectors and connectors.
func rebuild_nav_grid() -> void:
	if nav_grid == null:
		nav_grid = BattlefieldNavGridScript.new()
	nav_grid.build_from_battlefield(bounds_min, bounds_max, active_sectors, sector_connectors)

## Unmarks a destroyed DestructibleWall3D from the navigation grid.
func notify_wall_destroyed(wall: Object) -> void:
	if nav_grid != null:
		nav_grid.unmark_wall(wall)

## Marks a newly added DestructibleWall3D onto the navigation grid.
func notify_wall_added(wall: Object) -> void:
	if nav_grid != null:
		nav_grid.mark_wall(wall)

func _on_sector_wall_added(wall: Node3D) -> void:
	notify_wall_added(wall)

## Shows only the active sector and immediate adjacent sectors/connectors to reduce GPU draw calls.
func update_sector_visibility(active_index: int) -> void:
	for i in range(active_sectors.size()):
		var s = active_sectors[i]
		if s != null and is_instance_valid(s) and s is Node3D:
			(s as Node3D).visible = (absi(i - active_index) <= 1)
	for i in range(sector_connectors.size()):
		var conn: Node3D = sector_connectors[i]
		if conn != null and is_instance_valid(conn):
			conn.visible = (i >= active_index - 1 and i <= active_index + 1)

func _create_sector_connector(
	sector_idx: int,
	from_north_z: float,
	to_south_z: float,
	gate_width: float,
	next_room_type: String
) -> Node3D:
	var root := Node3D.new()
	root.name = "SectorConnector_%d_%d" % [sector_idx, sector_idx + 1]
	var center_z: float = (from_north_z + to_south_z) * 0.5
	var length_z: float = maxf(2.0, absf(from_north_z - to_south_z))
	root.position = Vector3(0.0, 0.0, center_z)

	var floor_box := CSGBox3D.new()
	floor_box.name = "ConnectorFloor"
	floor_box.size = Vector3(gate_width + 2.0, 0.2, length_z + 0.6)
	floor_box.position = Vector3(0.0, -0.09, 0.0)
	floor_box.use_collision = true
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.28, 0.31, 0.36, 1.0)
	floor_box.material = floor_mat
	root.add_child(floor_box)

	for side_sign: float in [-1.0, 1.0]:
		var wall := CSGBox3D.new()
		wall.name = "CorridorWallWest" if side_sign < 0.0 else "CorridorWallEast"
		wall.size = Vector3(0.6, 1.6, length_z + 0.4)
		wall.position = Vector3(side_sign * (gate_width * 0.5 + 0.3), 0.8, 0.0)
		wall.use_collision = true
		var wmat := StandardMaterial3D.new()
		wmat.albedo_color = Color(0.46, 0.50, 0.56, 1.0)
		wall.material = wmat
		root.add_child(wall)

		var cp := CoverPoint3DScript.new()
		cp.name = "CorridorCoverWest" if side_sign < 0.0 else "CorridorCoverEast"
		cp.cover_type = CoverPoint3DScript.CoverType.HALF
		cp.cover_direction = Vector3(0.0, 0.0, -1.0)
		cp.position = Vector3(side_sign * (gate_width * 0.32), 0.0, 0.0)
		root.add_child(cp)

	var banner := Label3D.new()
	banner.name = "ArchwayLabel"
	banner.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	banner.no_depth_test = true
	banner.font_size = 26
	banner.outline_size = 6
	banner.position = Vector3(0.0, 3.2, 0.0)
	banner.modulate = Color(1.0, 0.62, 0.25, 1.0)
	banner.text = "🔒 CỔNG KHU VỰC %d [%s]" % [sector_idx + 2, next_room_type]
	root.add_child(banner)

	return root

func _create_sector_gate(
	sector_idx: int,
	local_north_z: float,
	gate_width: float,
	next_room_type: String
) -> Node3D:
	var gate = DestructibleWall3DScript.new()
	gate.name = "SectorGate_%d" % sector_idx
	gate.position = Vector3(0.0, 1.35, local_north_z)
	gate.setup_wall(Vector3(gate_width, 2.7, 0.55), 99, 99999, Color(1.0, 0.28, 0.18, 0.45), false)
	if gate.wall_mesh_inst != null and gate.wall_mesh_inst.mesh is BoxMesh:
		var bm := gate.wall_mesh_inst.mesh as BoxMesh
		if bm.material is StandardMaterial3D:
			var mat := bm.material as StandardMaterial3D
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(1.0, 0.28, 0.18, 0.40)
	gate.set_meta(&"next_room_type", next_room_type)
	return gate

## Unlocks and lowers the energy gate between sector_index and sector_index + 1 once the encounter zone is cleared.
func unlock_sector_gate(sector_index: int) -> bool:
	if not sector_gates.has(sector_index):
		return false
	var gate = sector_gates[sector_index]
	if gate == null or not is_instance_valid(gate) or gate.is_destroyed:
		return false

	gate.is_destructible = true
	gate.destroy_wall()
	notify_wall_destroyed(gate)
	if gate.rubble_root != null:
		gate.rubble_root.visible = false

	if sector_index >= 0 and sector_index < sector_connectors.size():
		var conn: Node3D = sector_connectors[sector_index]
		if conn != null and is_instance_valid(conn):
			var lbl := conn.get_node_or_null("ArchwayLabel") as Label3D
			if lbl != null:
				var next_type: String = str(gate.get_meta(&"next_room_type", "NEXT"))
				lbl.text = "🔓 KHU VỰC %d [%s] — TIẾN QUÂN ➔" % [sector_index + 2, next_type]
				lbl.modulate = Color(0.28, 1.0, 0.58, 1.0)

	sector_gate_unlocked.emit(sector_index, gate.get_world_center())
	return true

## Returns true if the gate exiting sector_index is unlocked/open (or if sector_index is the final sector).
func is_sector_gate_unlocked(sector_index: int) -> bool:
	if not sector_gates.has(sector_index):
		return true
	var gate = sector_gates[sector_index]
	return gate == null or not is_instance_valid(gate) or bool(gate.is_destroyed)

## Returns the instantiated CombatRoomData node for sector_index, or null if out of range.
func get_sector_node(sector_index: int) -> Node3D:
	if sector_index < 0 or sector_index >= active_sectors.size():
		return null
	var s = active_sectors[sector_index]
	return s if (s != null and is_instance_valid(s)) else null

## Returns the world-space center origin of sector_index.
func get_sector_origin(sector_index: int) -> Vector3:
	if sector_index >= 0 and sector_index < sector_metadata.size():
		return sector_metadata[sector_index].get("sector_origin", Vector3.ZERO)
	var s := get_sector_node(sector_index)
	if s != null:
		return s.global_position if s.is_inside_tree() else s.position
	return Vector3.ZERO

## Returns the world-space entrance rally point (centroid of PlayerSpawns) for sector_index.
func get_sector_rally_point(sector_index: int) -> Vector3:
	var s = get_sector_node(sector_index)
	if s != null and s.has_method(&"get_player_spawn_positions"):
		var spawns: Array[Vector3] = s.get_player_spawn_positions()
		if not spawns.is_empty():
			var sum := Vector3.ZERO
			for p in spawns:
				sum += p
			return sum / float(spawns.size())
	return get_sector_origin(sector_index) + Vector3(0.0, 0.0, 14.0)

## Returns the index of the sector containing world_pos on the XZ plane, or -1 if inside a connecting corridor.
func get_sector_index_at_position(world_pos: Vector3) -> int:
	for i in range(sector_metadata.size()):
		var meta: Dictionary = sector_metadata[i]
		var orig: Vector3 = meta.get("sector_origin", Vector3.ZERO)
		var dims: Vector2 = meta.get("sector_dimensions", Vector2(64.0, 56.0))
		if absf(world_pos.x - orig.x) <= dims.x * 0.5 + 0.5 and absf(world_pos.z - orig.z) <= dims.y * 0.5 + 0.5:
			return i
	return -1

## Aggregates all unbroken and broken DestructibleWall3D obstacles (including locked SectorGates) across all sectors.
func get_all_wall_obstacles() -> Array:
	var all_walls: Array = []
	var seen_ids: Dictionary = {}
	for s in active_sectors:
		if s != null and is_instance_valid(s) and s.has_method(&"get_wall_obstacles"):
			for w in s.get_wall_obstacles():
				if w != null and is_instance_valid(w):
					var wid: int = w.get_instance_id()
					if not seen_ids.has(wid):
						seen_ids[wid] = true
						all_walls.append(w)
	return all_walls

## Aggregates all CoverPoint3D nodes across all sectors and connecting thoroughfares.
func get_all_cover_points() -> Array[CoverPoint3D]:
	var all_covers: Array[CoverPoint3D] = []
	var seen_ids: Dictionary = {}
	for s in active_sectors:
		if s != null and is_instance_valid(s) and s.has_method(&"get_cover_points"):
			for cp in s.get_cover_points():
				if cp != null and is_instance_valid(cp):
					var cid: int = cp.get_instance_id()
					if not seen_ids.has(cid):
						seen_ids[cid] = true
						all_covers.append(cp)
	for conn in sector_connectors:
		if conn != null and is_instance_valid(conn):
			for child in conn.get_children():
				if child is CoverPoint3DScript:
					var cid: int = child.get_instance_id()
					if not seen_ids.has(cid):
						seen_ids[cid] = true
						all_covers.append(child as CoverPoint3DScript)
	return all_covers

## Returns the full XZ camera bounds dictionary {"min": Vector2, "max": Vector2} for the stitched battlefield.
func get_battlefield_bounds() -> Dictionary:
	return {
		"min": bounds_min,
		"max": bounds_max,
	}

## Removes and frees all instantiated sector nodes, connectors, and gates to prevent orphan leaks.
func clear_battlefield() -> void:
	sector_gates.clear()
	sector_metadata.clear()
	for conn in sector_connectors:
		if conn != null and is_instance_valid(conn):
			if conn.get_parent() != null:
				conn.get_parent().remove_child(conn)
			conn.free()
	sector_connectors.clear()

	for s in active_sectors:
		if s != null and is_instance_valid(s):
			if s.has_signal(&"wall_obstacle_added") and s.wall_obstacle_added.is_connected(_on_sector_wall_added):
				s.wall_obstacle_added.disconnect(_on_sector_wall_added)
			var n := s as Node
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	active_sectors.clear()
	if nav_grid != null:
		nav_grid.clear()
		nav_grid = null

func _exit_tree() -> void:
	clear_battlefield()
	_packed_cache.clear()
	_threaded_requested.clear()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		clear_battlefield()
		_packed_cache.clear()
		_threaded_requested.clear()
