# scripts/combat/DungeonLayoutGenerator.gd
class_name DungeonLayoutGenerator
extends RefCounted

const ROOM_TYPES: Array[String] = ["COMBAT", "ELITE", "REST", "BOSS"]
const MIDDLE_ROOM_TYPES: Array[String] = ["COMBAT", "ELITE", "REST"]
const NON_REST_MIDDLE_TYPES: Array[String] = ["COMBAT", "ELITE"]

## Generates a dungeon room sequence starting with COMBAT, ending with BOSS, and avoiding adjacent REST rooms.
func generate_layout(room_count: int = 5, difficulty: int = 1) -> Array[Dictionary]:
	var total_rooms: int = maxi(2, room_count)
	var eff_difficulty: int = maxi(1, difficulty)
	var result: Array[Dictionary] = []
	var prev_type: String = ""

	for i in range(total_rooms):
		var room_type: String
		if i == 0:
			room_type = "COMBAT"
		elif i == total_rooms - 1:
			room_type = "BOSS"
		else:
			var pool: Array[String] = NON_REST_MIDDLE_TYPES if prev_type == "REST" else MIDDLE_ROOM_TYPES
			room_type = pool[randi() % pool.size()]

		prev_type = room_type
		result.append({
			"room_index": i,
			"room_type": room_type,
			"room_scene_path": _get_scene_path(room_type),
			"enemy_wave_def": _build_wave_def(room_type, i, eff_difficulty),
			"door_positions": _get_door_positions(room_type),
		})

	return result

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
