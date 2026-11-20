# scripts/combat/EnemyAI.gd
class_name EnemyAI
extends Node

## Evaluates enemy AI decision from a lightweight dictionary and player unit list.
func evaluate_simple(enemy_dict: Dictionary, player_units: Array) -> Dictionary:
	var enemy_pos: Vector3 = _get_world_position(enemy_dict)
	var nearest: Variant = null
	var nearest_dist: float = INF

	for unit in player_units:
		if not _is_unit_alive(unit):
			continue
		var dist: float = enemy_pos.distance_to(_get_world_position(unit))
		if nearest == null or dist < nearest_dist:
			nearest = unit
			nearest_dist = dist

	if nearest == null:
		return {"action": "IDLE", "target": null}

	var behavior: String = str(enemy_dict.get("behavior", "AGGRESSIVE"))
	var attack_range: float = float(enemy_dict.get("attack_range", 10.0))

	match behavior:
		"AGGRESSIVE":
			return {"action": "RUSH", "target": nearest}
		"DEFENSIVE":
			return {"action": "HOLD_AND_SHOOT", "target": nearest}
		"PATROL":
			if nearest_dist <= attack_range:
				return {"action": "ENGAGE", "target": nearest}
			return {"action": "PATROL", "target": null}
		_:
			return {"action": "IDLE", "target": null}

## Evaluates enemy AI decision for either an EnemyUnit object or a Dictionary.
func evaluate(owner_enemy: Variant, player_units: Array) -> Dictionary:
	if owner_enemy == null:
		return {"action": "IDLE", "target": null}
	if owner_enemy is Dictionary:
		return evaluate_simple(owner_enemy, player_units)
	if owner_enemy is Object:
		if not is_instance_valid(owner_enemy):
			return {"action": "IDLE", "target": null}
		var behavior_val: Variant = owner_enemy.get(&"behavior")
		var range_val: Variant = owner_enemy.get(&"attack_range")
		var enemy_dict: Dictionary = {
			"behavior": str(behavior_val) if behavior_val != null else "AGGRESSIVE",
			"attack_range": float(range_val) if range_val != null else 10.0,
			"position": _get_world_position(owner_enemy),
		}
		return evaluate_simple(enemy_dict, player_units)
	return {"action": "IDLE", "target": null}

func _is_unit_alive(unit: Variant) -> bool:
	if unit == null:
		return false
	if unit is Dictionary:
		if not bool(unit.get("is_alive", true)):
			return false
		if unit.has("hp_percent"):
			return float(unit["hp_percent"]) > 0.0
		if unit.has("current_hp"):
			return int(unit["current_hp"]) > 0
		return true
	if unit is Object:
		if not is_instance_valid(unit):
			return false
		var alive_val: Variant = unit.get(&"is_alive")
		if alive_val != null and not bool(alive_val):
			return false
		var hp_pct: Variant = unit.get(&"hp_percent")
		if hp_pct != null:
			return float(hp_pct) > 0.0
		var curr_hp: Variant = unit.get(&"current_hp")
		if curr_hp != null:
			return int(curr_hp) > 0
		return true
	return false

func _get_world_position(item: Variant) -> Vector3:
	if item is Vector3:
		return item
	if item is Dictionary:
		if item.has("position") and item["position"] is Vector3:
			return item["position"]
		if item.has("global_position") and item["global_position"] is Vector3:
			return item["global_position"]
		return Vector3.ZERO
	if item is Node3D and is_instance_valid(item):
		return item.global_position if item.is_inside_tree() else item.position
	if item is Object and is_instance_valid(item):
		var pos_val: Variant = item.get(&"position")
		if pos_val is Vector3:
			return pos_val
	return Vector3.ZERO
