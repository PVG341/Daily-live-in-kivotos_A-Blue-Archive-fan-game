# scripts/combat/CombatRoomData.gd
class_name CombatRoomData
extends Node3D

const TacticalTerrainZoneScript := preload("res://scripts/combat/TacticalTerrainZone.gd")

@export var room_type: String = "COMBAT"
@export var arena_size: Vector2 = Vector2(64.0, 56.0)

## Returns spawn positions from all Marker3D children under PlayerSpawns.
func get_player_spawn_positions() -> Array[Vector3]:
	var result: Array[Vector3] = []
	var container := get_node_or_null("PlayerSpawns")
	if container == null:
		return result
	for child in container.get_children():
		if child is Marker3D:
			var m := child as Marker3D
			result.append(m.global_position if m.is_inside_tree() else m.position)
	return result

## Returns spawn positions from all Marker3D children under EnemySpawns.
func get_enemy_spawn_positions() -> Array[Vector3]:
	var result: Array[Vector3] = []
	var container := get_node_or_null("EnemySpawns")
	if container == null:
		return result
	for child in container.get_children():
		if child is Marker3D:
			var m := child as Marker3D
			result.append(m.global_position if m.is_inside_tree() else m.position)
	return result

## Returns the BossSpawn Marker3D position, or default Vector3(0, 0, -18) if absent.
func get_boss_spawn_position() -> Vector3:
	var boss_spawn := get_node_or_null("BossSpawn") as Marker3D
	if boss_spawn != null:
		return boss_spawn.global_position if boss_spawn.is_inside_tree() else boss_spawn.position
	return Vector3(0.0, 0.0, -18.0)

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

## Evaluates combined terrain modifiers at world_pos across all overlapping TacticalTerrainZones.
func get_terrain_modifiers_at(world_pos: Vector3) -> Dictionary:
	var active_type: String = "NORMAL"
	var speed_mult: float = 1.0
	var range_mult: float = 1.0
	var dmg_taken_mult: float = 1.0
	var elev_offset: float = 0.0

	for zone in get_terrain_zones():
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
