# scripts/combat/DungeonLayoutGenerator.gd
class_name DungeonLayoutGenerator
extends RefCounted

const ROOM_TYPES: Array[String] = ["COMBAT", "ELITE", "REST", "BOSS"]
const MIDDLE_ROOM_TYPES: Array[String] = ["COMBAT", "ELITE", "REST"]
const NON_REST_MIDDLE_TYPES: Array[String] = ["COMBAT", "ELITE"]
const CORRIDOR_LENGTH: float = 10.0
const GATEWAY_WIDTH: float = 16.0

## Generates a dungeon room sequence starting with COMBAT, ending with BOSS, and avoiding adjacent REST rooms.
## Also computes contiguous world-space sector origins along the -Z campaign advance axis for seamless battlefields.
func generate_layout(room_count: int = 5, difficulty: int = 1, allow_rest_rooms: bool = true) -> Array[Dictionary]:
	var total_rooms: int = maxi(2, room_count)
	var eff_difficulty: int = maxi(1, difficulty)
	var result: Array[Dictionary] = []
	var prev_type: String = ""
	var cur_z: float = 0.0
	var prev_depth: float = 0.0

	for i in range(total_rooms):
		var room_type: String
		if i == 0:
			room_type = "COMBAT"
		elif i == total_rooms - 1:
			room_type = "BOSS"
		else:
			var pool: Array[String] = NON_REST_MIDDLE_TYPES if (not allow_rest_rooms or prev_type == "REST") else MIDDLE_ROOM_TYPES
			room_type = pool[randi() % pool.size()]

		var dims: Vector2 = _get_sector_dimensions(room_type)
		if i == 0:
			cur_z = 0.0
		else:
			var prev_north_edge: float = cur_z - prev_depth * 0.5
			cur_z = prev_north_edge - CORRIDOR_LENGTH - dims.y * 0.5
		prev_depth = dims.y
		prev_type = room_type

		var sector_origin := Vector3(0.0, 0.0, cur_z)
		var north_gate_pos := Vector3(0.0, 0.0, cur_z - dims.y * 0.5)
		result.append({
			"room_index": i,
			"room_type": room_type,
			"room_scene_path": _get_scene_path(room_type),
			"enemy_wave_def": _build_wave_def(room_type, i, eff_difficulty),
			"door_positions": _get_door_positions(room_type),
			"sector_origin": sector_origin,
			"sector_dimensions": dims,
			"corridor_length": CORRIDOR_LENGTH,
			"gateway_width": GATEWAY_WIDTH,
			"north_gate_position": north_gate_pos,
		})

	return result

func _get_sector_dimensions(room_type: String) -> Vector2:
	match room_type:
		"ELITE":
			return Vector2(68.0, 60.0)
		"REST":
			return Vector2(64.0, 36.0)
		"BOSS":
			return Vector2(72.0, 64.0)
		_:
			return Vector2(64.0, 56.0)

func _get_scene_path(room_type: String) -> String:
	return "res://scenes/combat/rooms/room_%s.tscn" % room_type.to_lower()

func _build_wave_def(room_type: String, room_index: int, eff_difficulty: int) -> Dictionary:
	var enemy_count: int = 0
	var wave_count: int = 1
	match room_type:
		"REST":
			enemy_count = 0
			wave_count = 0
		"COMBAT":
			enemy_count = 3 + room_index + (eff_difficulty - 1) * 2
			wave_count = 1
		"ELITE":
			enemy_count = 4 + room_index + (eff_difficulty - 1) * 2
			wave_count = 2
		"BOSS":
			enemy_count = 1 + eff_difficulty * 2
			wave_count = 1

	return {
		"room_type": room_type,
		"difficulty": eff_difficulty,
		"enemy_count": enemy_count,
		"wave_count": wave_count,
	}

func _get_door_positions(room_type: String) -> Array:
	if room_type == "BOSS":
		return []
	return [Vector3(0.0, 0.0, -12.0)]
