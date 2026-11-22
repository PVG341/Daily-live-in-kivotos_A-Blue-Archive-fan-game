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

## Checks whether world_pos falls inside this terrain zone's XZ bounding box.
func contains_point_xz(world_pos: Vector3) -> bool:
	var center: Vector3 = global_position if is_inside_tree() else position
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
