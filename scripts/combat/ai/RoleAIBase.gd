# scripts/combat/ai/RoleAIBase.gd
class_name RoleAIBase
extends Node

## Returns true when the unit has an active player order and is not in emergency HP override (< 10%).
func should_yield_to_player(owner_unit: Object) -> bool:
	if owner_unit == null or not is_instance_valid(owner_unit):
		return false
	if owner_unit.has_method(&"check_emergency_override") and owner_unit.check_emergency_override():
		return false
	var order_val: Variant = owner_unit.get(&"has_player_order")
	return bool(order_val) if order_val != null else false

## Lightweight dictionary variant of yield/override evaluation for data-driven tests.
func should_yield_to_player_dict(owner_dict: Dictionary) -> bool:
	if float(owner_dict.get("hp_percent", 1.0)) < 0.10:
		return false
	return bool(owner_dict.get("has_player_order", false))

## Evaluates the next AI decision, yielding to player orders unless overridden.
func evaluate_action(owner_unit: Object, _allies: Array, _enemies: Array, _covers: Array) -> Dictionary:
	if should_yield_to_player(owner_unit):
		return _yield_action()
	return _idle_action()

func _yield_action() -> Dictionary:
	return {"action": "YIELD_TO_PLAYER", "target": null, "priority": 0.0}

func _idle_action() -> Dictionary:
	return {"action": "IDLE", "target": null, "priority": 0.0}

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

func _get_unit_hp_percent(unit: Variant) -> float:
	if unit is Dictionary:
		if unit.has("hp_percent"):
			return float(unit["hp_percent"])
		if unit.has("current_hp") and unit.has("max_hp"):
			return float(unit["current_hp"]) / float(maxi(1, int(unit["max_hp"])))
		if unit.has("current_hp"):
			return float(unit["current_hp"])
		return 1.0
	if unit is Object and is_instance_valid(unit):
		var hp_pct: Variant = unit.get(&"hp_percent")
		if hp_pct != null:
			return float(hp_pct)
		var curr_hp: Variant = unit.get(&"current_hp")
		var max_hp: Variant = unit.get(&"max_hp")
		if curr_hp != null and max_hp != null:
			return float(curr_hp) / float(maxi(1, int(max_hp)))
		if curr_hp != null:
			return float(curr_hp)
	return 1.0

func _is_unit_pinged(unit: Variant) -> bool:
	if unit is Dictionary:
		return bool(unit.get("is_pinged", false))
	if unit is Object and is_instance_valid(unit):
		var ping_prop: Variant = unit.get(&"is_pinged")
		if ping_prop != null and bool(ping_prop):
			return true
		if unit.has_meta(&"is_pinged") and bool(unit.get_meta(&"is_pinged")):
			return true
	return false

func _get_world_position(item: Variant) -> Variant:
	if item is Vector3:
		return item
	if item is Dictionary:
		if item.has("position") and item["position"] is Vector3:
			return item["position"]
		if item.has("global_position") and item["global_position"] is Vector3:
			return item["global_position"]
		return null
	if item is Node3D:
		if not is_instance_valid(item):
			return null
		return item.global_position if item.is_inside_tree() else item.position
	if item is Object and is_instance_valid(item):
		var pos_val: Variant = item.get(&"position")
		if pos_val is Vector3:
			return pos_val
	return null
