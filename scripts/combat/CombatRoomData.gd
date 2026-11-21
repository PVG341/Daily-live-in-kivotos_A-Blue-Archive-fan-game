# scripts/combat/CombatRoomData.gd
class_name CombatRoomData
extends Node3D

@export var room_type: String = "COMBAT"

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

## Returns the BossSpawn Marker3D position, or default Vector3(0, 0, -9) if absent.
func get_boss_spawn_position() -> Vector3:
	var boss_spawn := get_node_or_null("BossSpawn") as Marker3D
	if boss_spawn != null:
		return boss_spawn.global_position if boss_spawn.is_inside_tree() else boss_spawn.position
	return Vector3(0.0, 0.0, -9.0)

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
