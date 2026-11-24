# scripts/combat/CombatRoomData.gd
class_name CombatRoomData
extends Node3D

const TacticalTerrainZoneScript := preload("res://scripts/combat/TacticalTerrainZone.gd")
const DestructibleWall3DScript := preload("res://scripts/combat/DestructibleWall3D.gd")

@export var room_type: String = "COMBAT"
@export var arena_size: Vector2 = Vector2(64.0, 56.0)

var sector_index: int = 0
var linked_sectors: Array = []
var wall_obstacles: Array = []
var _walls_initialized: bool = false
var _gateways_opened: bool = false

func _node_world_pos(n: Node3D) -> Vector3:
	if n == null:
		return Vector3.ZERO
	if n.is_inside_tree():
		return n.global_position
	var xform: Transform3D = n.transform
	var p: Node = n.get_parent()
	while p != null:
		if p is Node3D:
			xform = (p as Node3D).transform * xform
		p = p.get_parent()
	return xform.origin

## Returns spawn positions from all Marker3D children under PlayerSpawns.
func get_player_spawn_positions() -> Array[Vector3]:
	var result: Array[Vector3] = []
	var container := get_node_or_null("PlayerSpawns")
	if container == null:
		return result
	for child in container.get_children():
		if child is Marker3D:
			result.append(_node_world_pos(child as Marker3D))
	return result

## Returns spawn positions from all Marker3D children under EnemySpawns.
func get_enemy_spawn_positions() -> Array[Vector3]:
	var result: Array[Vector3] = []
	var container := get_node_or_null("EnemySpawns")
	if container == null:
		return result
	for child in container.get_children():
		if child is Marker3D:
			result.append(_node_world_pos(child as Marker3D))
	return result

## Returns the BossSpawn Marker3D position, or default Vector3(0, 0, -18) in world space if absent.
func get_boss_spawn_position() -> Vector3:
	var boss_spawn := get_node_or_null("BossSpawn") as Marker3D
	if boss_spawn != null:
		return _node_world_pos(boss_spawn)
	return _node_world_pos(self) + Vector3(0.0, 0.0, -18.0)

## Recursively collects all CoverPoint3D nodes under CoverPoints (or self).
func get_cover_points() -> Array[CoverPoint3D]:
	var covers: Array[CoverPoint3D] = []
	var root_search: Node = get_node_or_null("CoverPoints")
	if root_search == null:
		root_search = self
	_collect_covers_recursive(root_search, covers)
	return covers

func _collect_covers_recursive(node: Node, out: Array[CoverPoint3D]) -> void:
	if node is CoverPoint3D:
		out.append(node as CoverPoint3D)
	for child in node.get_children():
		_collect_covers_recursive(child, out)

## Recursively collects all TacticalTerrainZone nodes under TerrainFeatures (or self).
func get_terrain_zones() -> Array:
	var zones: Array = []
	var root_search: Node = get_node_or_null("TerrainFeatures")
	if root_search == null:
		root_search = self
	_collect_terrain_recursive(root_search, zones)
	return zones

func _collect_terrain_recursive(node: Node, out: Array) -> void:
	if is_instance_of(node, TacticalTerrainZoneScript):
		out.append(node)
	for child in node.get_children():
		_collect_terrain_recursive(child, out)

## Evaluates combined terrain modifiers at world_pos across all overlapping TacticalTerrainZones (including linked seamless sectors).
func get_terrain_modifiers_at(world_pos: Vector3) -> Dictionary:
	var active_type: String = "NORMAL"
	var speed_mult: float = 1.0
	var range_mult: float = 1.0
	var dmg_taken_mult: float = 1.0
	var elev_offset: float = 0.0

	var all_zones: Array = get_terrain_zones()
	for sector in linked_sectors:
		if sector != null and is_instance_valid(sector) and sector != self and sector.has_method(&"get_terrain_zones"):
			for sz in sector.get_terrain_zones():
				all_zones.append(sz)

	for zone in all_zones:
		if zone != null and is_instance_valid(zone) and zone.contains_point_xz(world_pos):
			var mods: Dictionary = zone.get_terrain_modifiers()
			active_type = str(mods.get("terrain_type", active_type))
			speed_mult = minf(speed_mult, float(mods.get("speed_multiplier", 1.0)))
			range_mult = maxf(range_mult, float(mods.get("range_bonus_multiplier", 1.0)))
			dmg_taken_mult = minf(dmg_taken_mult, float(mods.get("damage_taken_multiplier", 1.0)))
			var z_elev: float = float(mods.get("elevation_offset", 0.0))
			if absf(z_elev) > absf(elev_offset):
				elev_offset = z_elev

	return {
		"terrain_type": active_type,
		"speed_multiplier": speed_mult,
		"range_bonus_multiplier": range_mult,
		"damage_taken_multiplier": dmg_taken_mult,
		"elevation_offset": elev_offset,
	}

## Splits WallNorth and/or WallSouth to open a central thoroughfare gateway of gate_width meters for seamless multi-sector stitching.
func open_sector_gateways(open_north: bool, open_south: bool, gate_width: float = 16.0) -> void:
	if _gateways_opened:
		return
	_gateways_opened = true
	if open_north:
		_split_perimeter_wall("NavigationRegion3D/WallNorth", "WallNorth", gate_width)
	if open_south:
		_split_perimeter_wall("NavigationRegion3D/WallSouth", "WallSouth", gate_width)

func _split_perimeter_wall(node_path: String, base_name: String, gate_width: float) -> void:
	var wall := get_node_or_null(node_path) as CSGBox3D
	if wall == null or wall.size.x <= gate_width + 2.0:
		return
	var parent_node := wall.get_parent()
	if parent_node == null:
		return
	var total_w: float = wall.size.x
	var side_w: float = (total_w - gate_width) * 0.5
	var offset_x: float = gate_width * 0.5 + side_w * 0.5
	var orig_pos: Vector3 = wall.position
	var orig_size: Vector3 = wall.size

	wall.visible = false
	wall.use_collision = false

	for side_info: Dictionary in [
		{"suffix": "West", "x": orig_pos.x - offset_x},
		{"suffix": "East", "x": orig_pos.x + offset_x},
	]:
		var flank := CSGBox3D.new()
		flank.name = "%s%s" % [base_name, str(side_info["suffix"])]
		flank.size = Vector3(side_w, orig_size.y, orig_size.z)
		flank.position = Vector3(float(side_info["x"]), orig_pos.y, orig_pos.z)
		flank.use_collision = true
		flank.material = wall.material
		parent_node.add_child(flank)

## Subdivides structural CSGBox3D walls/barricades/piers under TerrainFeatures and CoverPoints into modular DestructibleWall3D segments.
func setup_destructible_walls() -> Array:
	if _walls_initialized:
		return _prune_wall_obstacles()
	_walls_initialized = true

	var candidates: Array[CSGBox3D] = []
	for folder_name: String in ["TerrainFeatures", "CoverPoints"]:
		var folder := get_node_or_null(folder_name)
		if folder != null:
			_collect_wall_boxes_recursive(folder, candidates)

	for box in candidates:
		if box == null or not is_instance_valid(box):
			continue
		var parent_node := box.get_parent()
		if parent_node == null:
			continue

		var full_name: String = "%s/%s" % [str(parent_node.name), str(box.name)]
		var tier: int = 2
		var seg_hp: int = 520
		if full_name.contains("Bunker") or full_name.contains("Pier"):
			tier = 3
			seg_hp = 900
		elif full_name.contains("Barricade") or full_name.contains("Parapet"):
			tier = 1
			seg_hp = 320

		var mat_color := Color(0.68, 0.64, 0.58)
		if box.material is StandardMaterial3D:
			mat_color = (box.material as StandardMaterial3D).albedo_color

		var box_size: Vector3 = box.size
		var along_x: bool = box_size.x >= box_size.z
		var longest: float = box_size.x if along_x else box_size.z
		var seg_count: int = maxi(1, int(round(longest / 2.65)))
		var seg_len: float = longest / float(seg_count)

		box.visible = false
		box.use_collision = false

		for s_idx in range(seg_count):
			var seg = DestructibleWall3DScript.new()
			seg.name = "%s_Seg%d" % [str(box.name), s_idx + 1]
			var seg_size := Vector3(seg_len, box_size.y, box_size.z) if along_x else Vector3(box_size.x, box_size.y, seg_len)
			var offset_scalar: float = (-longest * 0.5) + seg_len * (float(s_idx) + 0.5)
			var local_offset := Vector3(offset_scalar, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, offset_scalar)
			seg.transform = Transform3D(box.transform.basis, box.transform.origin + (box.transform.basis * local_offset))
			parent_node.add_child(seg)
			seg.setup_wall(seg_size, tier, seg_hp, mat_color, true)
			wall_obstacles.append(seg)

	return _prune_wall_obstacles()

func _collect_wall_boxes_recursive(node: Node, out: Array[CSGBox3D]) -> void:
	if node is CSGBox3D:
		var nname: String = str(node.name)
		var is_skip: bool = nname.contains("Roof") or nname.contains("Floor") or nname.contains("Deck") or nname.contains("Ramp") or nname.contains("Water")
		var is_wall: bool = nname.contains("Wall") or nname.contains("Barricade") or nname.contains("Parapet") or nname.contains("Pier")
		if is_wall and not is_skip:
			out.append(node as CSGBox3D)
	for child in node.get_children():
		_collect_wall_boxes_recursive(child, out)

func _prune_wall_obstacles() -> Array:
	var valid: Array = []
	for w in wall_obstacles:
		if w != null and is_instance_valid(w):
			valid.append(w)
	wall_obstacles = valid
	return wall_obstacles

## Returns all modular DestructibleWall3D obstacles in this room.
func get_wall_obstacles() -> Array:
	if not _walls_initialized:
		return setup_destructible_walls()
	return _prune_wall_obstacles()

## Returns all DestructibleWall3D obstacles across this sector and any linked seamless battlefield sectors.
func get_all_battlefield_walls() -> Array:
	var all_walls: Array = get_wall_obstacles().duplicate()
	for sector in linked_sectors:
		if sector != null and is_instance_valid(sector) and sector != self and sector.has_method(&"get_wall_obstacles"):
			for sw in sector.get_wall_obstacles():
				if sw != null and is_instance_valid(sw) and not all_walls.has(sw):
					all_walls.append(sw)
	return all_walls

## Registers an extra DestructibleWall3D into wall_obstacles for LOS and projectile checks.
func register_wall_obstacle(wall: Node3D) -> void:
	if wall != null and is_instance_valid(wall) and not wall_obstacles.has(wall):
		wall_obstacles.append(wall)

## Evaluates Line-of-Sight between from_pos and to_pos considering wall armor_tier vs penetration_power across all linked sectors.
func check_line_of_sight(from_pos: Vector3, to_pos: Vector3, penetration_power: int = 0) -> Dictionary:
	var hits: Array[Dictionary] = []
	for wall in get_all_battlefield_walls():
		if wall == null or not is_instance_valid(wall) or wall.is_destroyed:
			continue
		if wall.wall_size.y <= 1.05 and Vector2(from_pos.x, from_pos.z).distance_to(Vector2(wall.get_world_center().x, wall.get_world_center().z)) <= 3.2:
			continue
		var res: Dictionary = wall.intersects_segment(from_pos, to_pos)
		if bool(res.get("hit", false)):
			hits.append(res)

	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("t", 1.0)) < float(b.get("t", 1.0))
	)

	var penetrated: Array = []
	for h in hits:
		var w = h.get("wall", null)
		if w == null:
			continue
		if int(w.armor_tier) > penetration_power:
			return {
				"clear": false,
				"blocker": w,
				"hit_point": h.get("point", to_pos),
				"penetrated_walls": penetrated,
			}
		penetrated.append(w)

	return {
		"clear": true,
		"blocker": null,
		"hit_point": to_pos,
		"penetrated_walls": penetrated,
	}
