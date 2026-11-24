# scripts/combat/TacticalTerrainZone.gd
class_name TacticalTerrainZone
extends Area3D

enum TerrainType {
	WATER_TRENCH,
	CRATER_PIT,
	HIGH_GROUND,
	BUNKER_INTERIOR,
	UNDER_BRIDGE,
}

@export var terrain_type: TerrainType = TerrainType.WATER_TRENCH
@export var zone_extents: Vector2 = Vector2(4.0, 3.0)
@export var speed_multiplier: float = 0.55
@export var range_bonus_multiplier: float = 1.0
@export var damage_taken_multiplier: float = 1.0
@export var elevation_offset: float = 0.0

func get_terrain_type_name() -> String:
	match terrain_type:
		TerrainType.WATER_TRENCH:
			return "WATER_TRENCH"
		TerrainType.CRATER_PIT:
			return "CRATER_PIT"
		TerrainType.HIGH_GROUND:
			return "HIGH_GROUND"
		TerrainType.BUNKER_INTERIOR:
			return "BUNKER_INTERIOR"
		TerrainType.UNDER_BRIDGE:
			return "UNDER_BRIDGE"
		_:
			return "NORMAL"

## Returns the world-space center of this terrain zone even when parented to an offset sector out-of-tree.
func get_world_center() -> Vector3:
	if is_inside_tree():
		return global_position
	var xform: Transform3D = transform
	var p: Node = get_parent()
	while p != null:
		if p is Node3D:
			xform = (p as Node3D).transform * xform
		p = p.get_parent()
	return xform.origin

## Checks whether world_pos falls inside this terrain zone's XZ bounding box.
func contains_point_xz(world_pos: Vector3) -> bool:
	var center: Vector3 = get_world_center()
	var half_x: float = maxf(0.1, absf(zone_extents.x))
	var half_z: float = maxf(0.1, absf(zone_extents.y))
	return absf(world_pos.x - center.x) <= half_x and absf(world_pos.z - center.z) <= half_z

## Returns the tactical modifiers dictionary applied by this terrain zone.
func get_terrain_modifiers() -> Dictionary:
	return {
		"terrain_type": get_terrain_type_name(),
		"speed_multiplier": clampf(speed_multiplier, 0.1, 3.0),
		"range_bonus_multiplier": clampf(range_bonus_multiplier, 0.2, 3.0),
		"damage_taken_multiplier": clampf(damage_taken_multiplier, 0.1, 3.0),
		"elevation_offset": elevation_offset,
	}
