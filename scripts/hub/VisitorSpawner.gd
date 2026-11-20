# scripts/hub/VisitorSpawner.gd
class_name VisitorSpawner
extends RefCounted

const COMFORT_PER_VISITOR: int = 250
const BONUS_GIFT_PER_OVERFLOW: float = 0.15

## Hard cap on simultaneously spawned 3D student NPCs to protect framerate on low-end PCs.
var max_active_students: int = 5

## Syncs max_active_students from SettingsManager if available.
func sync_from_settings(settings_manager: Object) -> void:
	if settings_manager != null and "max_active_students" in settings_manager:
		max_active_students = maxi(1, int(settings_manager.max_active_students))

## Splits desired daily visitors into FPS-capped active_spawns, overflow_queue, and bonus_gift_multiplier.
func calculate_daily_visitors(unlocked_students: Array[String], comfort_score: int, day_offset: int = 0) -> Dictionary:
	var active_spawns: Array[String] = []
	var overflow_queue: Array[String] = []

	if unlocked_students.is_empty():
		return {
			"active_spawns": active_spawns,
			"overflow_queue": overflow_queue,
			"bonus_gift_multiplier": 1.0,
		}

	var count: int = unlocked_students.size()
	var start_idx: int = posmod(day_offset, count) if day_offset != 0 else 0
	var desired_count: int = clampi(
		1 + int(maxi(0, comfort_score) / COMFORT_PER_VISITOR),
		1,
		count
	)
	var cap: int = maxi(1, max_active_students)
	var active_count: int = mini(desired_count, cap)

	for i in range(desired_count):
		var student_id: String = unlocked_students[(start_idx + i) % count]
		if i < active_count:
			active_spawns.append(student_id)
		else:
			overflow_queue.append(student_id)

	var bonus_gift_multiplier: float = 1.0 + float(overflow_queue.size()) * BONUS_GIFT_PER_OVERFLOW
	return {
		"active_spawns": active_spawns,
		"overflow_queue": overflow_queue,
		"bonus_gift_multiplier": bonus_gift_multiplier,
	}
