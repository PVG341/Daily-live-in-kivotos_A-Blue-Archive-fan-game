# scripts/combat/CommanderDirectiveSystem.gd
class_name CommanderDirectiveSystem
extends Node

enum SquadStance {
	ALL_OUT_ASSAULT,
	BALANCED_TACTICAL,
	DEFENSIVE_HOLD,
}

signal directive_changed(directive_summary: String)
signal stance_changed(new_stance: int, stance_name: String)
signal priority_target_changed(target_enemy: Node3D)
signal tactical_slow_mo_toggled(active: bool, time_scale: float)

var current_stance: int = SquadStance.BALANCED_TACTICAL
var priority_target: Node3D = null
var has_tactical_zone: bool = false
var tactical_zone_center: Vector3 = Vector3.ZERO
var tactical_zone_radius: float = 6.5
var has_advance_vector: bool = false
var advance_origin: Vector3 = Vector3.ZERO
var advance_target: Vector3 = Vector3.ZERO
var tactical_slow_mo: bool = false
var slow_mo_scale: float = 0.25

func _exit_tree() -> void:
	priority_target = null

## Updates the squad-wide tactical stance and broadcasts directive updates.
func set_squad_stance(stance: int) -> void:
	current_stance = clampi(stance, SquadStance.ALL_OUT_ASSAULT, SquadStance.DEFENSIVE_HOLD)
	stance_changed.emit(current_stance, get_stance_name())
	directive_changed.emit(get_directive_summary())

## Returns the human-readable Vietnamese name of the current tactical stance.
func get_stance_name() -> String:
	match current_stance:
		SquadStance.ALL_OUT_ASSAULT:
			return "TỔNG TẤN CÔNG"
		SquadStance.DEFENSIVE_HOLD:
			return "PHÒNG THỦ"
		_:
			return "CÂN BẰNG"

## Marks (or clears) the squad's commander-assigned priority target enemy.
func set_priority_target(enemy: Node3D) -> void:
	if enemy == null or not is_instance_valid(enemy):
		priority_target = null
	else:
		var alive_val: Variant = enemy.get(&"is_alive")
		priority_target = enemy if (alive_val == null or bool(alive_val)) else null
	priority_target_changed.emit(priority_target)
	directive_changed.emit(get_directive_summary())

## Places a circular tactical engagement/rally zone on the battlefield.
func place_tactical_zone(center: Vector3, radius: float = 6.5) -> void:
	has_tactical_zone = true
	tactical_zone_center = Vector3(center.x, 0.0, center.z)
	tactical_zone_radius = clampf(radius, 3.5, 14.0)
	directive_changed.emit(get_directive_summary())

## Sets a directional advance vector and centers the tactical rally zone at the destination.
func set_advance_vector(from_pos: Vector3, to_pos: Vector3) -> void:
	has_advance_vector = true
	advance_origin = Vector3(from_pos.x, 0.0, from_pos.z)
	advance_target = Vector3(to_pos.x, 0.0, to_pos.z)
	has_tactical_zone = true
	tactical_zone_center = advance_target
	directive_changed.emit(get_directive_summary())

## Clears all spatial directives and target markers while keeping current stance.
func clear_directives() -> void:
	priority_target = null
	has_tactical_zone = false
	has_advance_vector = false
	tactical_zone_center = Vector3.ZERO
	advance_origin = Vector3.ZERO
	advance_target = Vector3.ZERO
	priority_target_changed.emit(null)
	directive_changed.emit(get_directive_summary())

## Toggles or explicitly sets Commander tactical slow-motion planning mode.
func toggle_tactical_slow_mo(force_state: Variant = null) -> bool:
	if force_state is bool:
		tactical_slow_mo = bool(force_state)
	else:
		tactical_slow_mo = not tactical_slow_mo
	tactical_slow_mo_toggled.emit(tactical_slow_mo, get_effective_time_scale())
	directive_changed.emit(get_directive_summary())
	return tactical_slow_mo

## Returns active combat time scale multiplier (0.25x during tactical planning, 1.0x normal).
func get_effective_time_scale() -> float:
	return slow_mo_scale if tactical_slow_mo else 1.0

## Validates that priority_target is still alive and in memory.
func get_valid_priority_target() -> Node3D:
	if priority_target == null or not is_instance_valid(priority_target):
		priority_target = null
		return null
	var alive_val: Variant = priority_target.get(&"is_alive")
	if alive_val != null and not bool(alive_val):
		priority_target = null
		return null
	return priority_target

## Formats a concise Vietnamese directive status line for CombatHUD.
func get_directive_summary() -> String:
	var tags: Array[String] = []
	if has_advance_vector:
		tags.append("Hướng Tiến Công")
	elif has_tactical_zone:
		tags.append("Vùng Tập Kích (%.0fm)" % tactical_zone_radius)
	if get_valid_priority_target() != null:
		tags.append("Mục Tiêu Trọng Yếu")
	if tactical_slow_mo:
		tags.append("Slow-Mo 0.25x")
	var suffix: String = " | Chỉ thị: " + ", ".join(tags) if not tags.is_empty() else " | Tự động chiến đấu"
	return "Đội hình [Z/X/V]: %s%s" % [get_stance_name(), suffix]
