# scripts/combat/TelegraphedAoE.gd
class_name TelegraphedAoE
extends Node3D

signal telegraph_started(target_pos: Vector3, radius: float, warn_duration: float)
signal aoe_detonated(hit_units: Array)

var target_position: Vector3 = Vector3.ZERO
var radius: float = 4.0
var warn_duration: float = 1.5
var damage: int = 500
var elapsed: float = 0.0
var has_detonated: bool = false

## Configures the telegraphed danger zone and emits telegraph_started.
func setup(p_pos: Vector3, p_radius: float, p_warn_duration: float, p_damage: int) -> void:
	target_position = p_pos
	position = p_pos
	radius = maxf(0.0, p_radius)
	warn_duration = maxf(0.0, p_warn_duration)
	damage = maxi(0, p_damage)
	elapsed = 0.0
	has_detonated = false
	telegraph_started.emit(target_position, radius, warn_duration)

## Returns normalized telegraph fill progress in [0.0, 1.0].
func get_warning_progress() -> float:
	return clampf(elapsed / maxf(0.001, warn_duration), 0.0, 1.0)

## Advances the telegraph timer and detonates once elapsed >= warn_duration, damaging units still inside radius.
func tick(delta: float, units_in_arena: Array) -> Array:
	if has_detonated or delta <= 0.0:
		return []

	elapsed += delta
	if elapsed < warn_duration:
		return []

	has_detonated = true
	var hit_units: Array = []
	var target_xz := Vector2(target_position.x, target_position.z)

	for unit in units_in_arena:
		if not _is_unit_living(unit):
			continue
		var unit_pos: Vector3 = _get_unit_position(unit)
		var unit_xz := Vector2(unit_pos.x, unit_pos.z)
		if unit_xz.distance_to(target_xz) <= radius:
			_apply_unit_damage(unit)
			hit_units.append(unit)

	aoe_detonated.emit(hit_units)
	return hit_units

func _is_unit_living(unit: Variant) -> bool:
	if unit == null:
		return false
	if unit is Dictionary:
		if unit.has("is_alive") and not bool(unit["is_alive"]):
			return false
		if unit.has("hp"):
			return int(unit["hp"]) > 0
		if unit.has("current_hp"):
			return int(unit["current_hp"]) > 0
		return true
	if unit is Object:
		if not is_instance_valid(unit):
			return false
		var alive_val: Variant = unit.get(&"is_alive")
		if alive_val != null and not bool(alive_val):
			return false
		var hp_val: Variant = unit.get(&"current_hp")
		if hp_val != null:
			return int(hp_val) > 0
		return true
	return false

func _get_unit_position(unit: Variant) -> Vector3:
	if unit is Dictionary:
		if unit.has("position") and unit["position"] is Vector3:
			return unit["position"]
		if unit.has("global_position") and unit["global_position"] is Vector3:
			return unit["global_position"]
		return Vector3.ZERO
	if unit is Node3D and is_instance_valid(unit):
		return unit.global_position if unit.is_inside_tree() else unit.position
	if unit is Object and is_instance_valid(unit):
		var pos_val: Variant = unit.get(&"position")
		if pos_val is Vector3:
			return pos_val
	return Vector3.ZERO

func _apply_unit_damage(unit: Variant) -> void:
	if unit is Dictionary:
		if unit.has("hp"):
			unit["hp"] = maxi(0, int(unit["hp"]) - damage)
			if int(unit["hp"]) == 0 and unit.has("is_alive"):
				unit["is_alive"] = false
		if unit.has("current_hp"):
			unit["current_hp"] = maxi(0, int(unit["current_hp"]) - damage)
			if int(unit["current_hp"]) == 0 and unit.has("is_alive"):
				unit["is_alive"] = false
	elif unit is Object and is_instance_valid(unit) and unit.has_method(&"take_damage"):
		unit.take_damage(damage, self)
