# scripts/combat/CommanderDirectiveSystem.gd
class_name CommanderDirectiveSystem
extends Node

enum SquadStance {
	ALL_OUT_ASSAULT,
	BALANCED_TACTICAL,
	DEFENSIVE_HOLD,
}

enum ToolMode {
	NONE,
	ASSAULT_ZONE,
	DEFENSE_ZONE,
	FREESHOT_ZONE,
}

signal directive_changed(directive_summary: String)
signal stance_changed(new_stance: int, stance_name: String)
signal priority_target_changed(target_enemy: Node3D)
signal tactical_slow_mo_toggled(active: bool, time_scale: float)
signal tool_changed(new_tool: int, tool_name: String)
signal zones_updated(active_zones: Array)

var current_stance: int = SquadStance.ALL_OUT_ASSAULT
var active_tool: int = ToolMode.NONE
var priority_target: Node3D = null
var has_tactical_zone: bool = false
var tactical_zone_center: Vector3 = Vector3.ZERO
var tactical_zone_radius: float = 6.5
var has_advance_vector: bool = false
var advance_origin: Vector3 = Vector3.ZERO
var advance_target: Vector3 = Vector3.ZERO
var tactical_slow_mo: bool = false
var slow_mo_scale: float = 0.25

var active_zones: Array[Dictionary] = []
var unit_zone_map: Dictionary = {}
var unit_target_map: Dictionary = {}
var unit_advance_map: Dictionary = {}
var squad_unit_ids: Array[String] = ["hoshino", "shiroko", "serika", "hanae"]
var _next_zone_id: int = 1

func _exit_tree() -> void:
	priority_target = null
	unit_target_map.clear()
	unit_zone_map.clear()
	unit_advance_map.clear()
	active_zones.clear()

## Updates the canonical list of living squad unit IDs used when a directive targets the full squad.
func set_squad_unit_ids(unit_ids: Array) -> void:
	var cleaned: Array[String] = []
	for raw_id in unit_ids:
		var sid: String = str(raw_id)
		if not sid.is_empty() and sid != "*" and not cleaned.has(sid):
			cleaned.append(sid)
	if not cleaned.is_empty():
		squad_unit_ids = cleaned

func _resolve_target_unit_ids(unit_ids: Array) -> Array[String]:
	var resolved: Array[String] = []
	for raw_uid in unit_ids:
		var uid: String = str(raw_uid)
		if not uid.is_empty() and uid != "*" and not resolved.has(uid):
			resolved.append(uid)
	if resolved.is_empty():
		return squad_unit_ids.duplicate()
	return resolved

## Selects an explicit Commander tool mode without changing unit behavior until placed.
func select_tool(tool: int) -> void:
	var clamped: int = clampi(tool, ToolMode.NONE, ToolMode.FREESHOT_ZONE)
	if clamped == active_tool and clamped != ToolMode.NONE:
		cancel_tool()
		return
	active_tool = clamped
	tool_changed.emit(active_tool, get_tool_name())
	directive_changed.emit(get_directive_summary())

## Cancels the currently armed Commander tool back to default selection cursor.
func cancel_tool() -> void:
	if active_tool == ToolMode.NONE:
		return
	active_tool = ToolMode.NONE
	tool_changed.emit(active_tool, get_tool_name())
	directive_changed.emit(get_directive_summary())

## Returns the localized display label for the armed Commander tool.
func get_tool_name() -> String:
	match active_tool:
		ToolMode.ASSAULT_ZONE:
			return "VÙNG GIAO TRANH [Z]"
		ToolMode.DEFENSE_ZONE:
			return "VÙNG PHÒNG THỦ [V]"
		ToolMode.FREESHOT_ZONE:
			return "VÙNG FREESHOT [B]"
		_:
			return "CHỌN LÍNH (Mặc định)"

## Updates the squad-wide tactical stance and broadcasts directive updates.
func set_squad_stance(stance: int) -> void:
	current_stance = clampi(stance, SquadStance.ALL_OUT_ASSAULT, SquadStance.DEFENSIVE_HOLD)
	stance_changed.emit(current_stance, get_stance_name())
	directive_changed.emit(get_directive_summary())

## Returns the human-readable Vietnamese name of the current tactical stance.
func get_stance_name() -> String:
	match current_stance:
		SquadStance.DEFENSIVE_HOLD:
			return "PHÒNG THỦ"
		_:
			return "GIAO TRANH"

## Marks (or clears) the squad's commander-assigned priority target enemy (latest command wins).
func set_priority_target(enemy: Node3D) -> void:
	if enemy == null or not is_instance_valid(enemy):
		priority_target = null
		unit_target_map.clear()
	else:
		var alive_val: Variant = enemy.get(&"is_alive")
		priority_target = enemy if (alive_val == null or bool(alive_val)) else null
		unit_target_map.clear()
		if priority_target != null:
			for sid: String in squad_unit_ids:
				unit_target_map[sid] = priority_target
	priority_target_changed.emit(priority_target)
	directive_changed.emit(get_directive_summary())

## Assigns a priority target enemy for specific unit IDs (or full squad if empty; latest command wins).
func set_target_for_units(enemy: Node3D, unit_ids: Array = []) -> void:
	if unit_ids.is_empty():
		set_priority_target(enemy)
		return
	var valid_enemy: Node3D = null
	if enemy != null and is_instance_valid(enemy):
		var alive_val: Variant = enemy.get(&"is_alive")
		if alive_val == null or bool(alive_val):
			valid_enemy = enemy
	var assigned: Array[String] = _resolve_target_unit_ids(unit_ids)
	for uid: String in assigned:
		if valid_enemy == null:
			unit_target_map.erase(uid)
		else:
			unit_target_map[uid] = valid_enemy
	priority_target_changed.emit(valid_enemy)
	directive_changed.emit(get_directive_summary())

## Resolves the active priority target for a given unit, falling back to squad priority target.
func get_target_for_unit(student_id: String) -> Node3D:
	if unit_target_map.has(student_id):
		var unit_target: Variant = unit_target_map[student_id]
		if unit_target == null or not is_instance_valid(unit_target):
			unit_target_map.erase(student_id)
			return null
		var node_target: Node3D = unit_target as Node3D
		if node_target == null:
			unit_target_map.erase(student_id)
			return null
		var alive_val: Variant = node_target.get(&"is_alive")
		if alive_val != null and not bool(alive_val):
			unit_target_map.erase(student_id)
			return null
		return node_target
	return get_valid_priority_target()

## Creates a typed tactical zone for specific unit IDs (or full squad if empty; latest command wins).
func create_zone_for_units(zone_type: String, center: Vector3, radius: float, unit_ids: Array = []) -> int:
	var resolved_type: String = zone_type.to_upper()
	if resolved_type != "ASSAULT" and resolved_type != "DEFENSE" and resolved_type != "FREESHOT":
		resolved_type = "ASSAULT"
	var clean_center := Vector3(center.x, 0.0, center.z)
	var clamped_radius: float = clampf(radius, 3.5, 14.0)
	var assigned: Array[String] = _resolve_target_unit_ids(unit_ids)

	# Latest command wins: remove assigned units from any prior zones and clear their old advance vectors
	for existing: Dictionary in active_zones:
		var existing_ids: Array = existing.get("assigned_unit_ids", [])
		existing_ids.erase("*")
		for uid: String in assigned:
			existing_ids.erase(uid)
			unit_zone_map.erase(uid)
			unit_advance_map.erase(uid)
		existing["is_full_squad"] = (not squad_unit_ids.is_empty() and existing_ids.size() >= squad_unit_ids.size())
	for uid: String in assigned:
		unit_advance_map.erase(uid)
	if unit_advance_map.is_empty():
		has_advance_vector = false

	# Prune any zone that no longer owns any units
	var kept_zones: Array[Dictionary] = []
	for existing: Dictionary in active_zones:
		var existing_ids: Array = existing.get("assigned_unit_ids", [])
		if not existing_ids.is_empty():
			kept_zones.append(existing)
	active_zones = kept_zones

	var zone_id: int = _next_zone_id
	_next_zone_id += 1
	var full_squad_flag: bool = not squad_unit_ids.is_empty() and assigned.size() >= squad_unit_ids.size()
	var zone_dict: Dictionary = {
		"id": zone_id,
		"type": resolved_type,
		"center": clean_center,
		"radius": clamped_radius,
		"assigned_unit_ids": assigned,
		"is_full_squad": full_squad_flag,
	}
	active_zones.append(zone_dict)
	for uid: String in assigned:
		unit_zone_map[uid] = zone_id

	_sync_legacy_zone_fields()
	zones_updated.emit(active_zones.duplicate(true))
	directive_changed.emit(get_directive_summary())
	return zone_id

## Returns the active zone Dictionary assigned to a unit.
func get_zone_for_unit(student_id: String) -> Dictionary:
	if unit_zone_map.has(student_id):
		var target_id: int = int(unit_zone_map[student_id])
		for z: Dictionary in active_zones:
			if int(z.get("id", -1)) == target_id:
				return z
	for i: int in range(active_zones.size() - 1, -1, -1):
		var z: Dictionary = active_zones[i]
		var ids: Array = z.get("assigned_unit_ids", [])
		if ids.has(student_id):
			return z
	return {}

## Places a circular tactical zone for the full squad (legacy helper -> multi-zone pool).
func place_tactical_zone(center: Vector3, radius: float = 6.5) -> void:
	var ztype: String = "DEFENSE" if current_stance == SquadStance.DEFENSIVE_HOLD else "ASSAULT"
	create_zone_for_units(ztype, center, radius, [])

## Sets a directional attack-move advance vector for specific units (or full squad if empty) WITHOUT spawning a zone.
func set_advance_target_for_units(from_pos: Vector3, to_pos: Vector3, unit_ids: Array = []) -> void:
	var clean_from := Vector3(from_pos.x, 0.0, from_pos.z)
	var clean_to := Vector3(to_pos.x, 0.0, to_pos.z)
	var assigned: Array[String] = _resolve_target_unit_ids(unit_ids)
	has_advance_vector = true
	advance_origin = clean_from
	advance_target = clean_to

	# Latest command wins: remove these units from older zones so they advance along the new vector
	for uid: String in assigned:
		unit_advance_map[uid] = clean_to
		unit_zone_map.erase(uid)
		for z: Dictionary in active_zones:
			var ids: Array = z.get("assigned_unit_ids", [])
			ids.erase(uid)
			z["is_full_squad"] = (not squad_unit_ids.is_empty() and ids.size() >= squad_unit_ids.size())
	var kept_zones: Array[Dictionary] = []
	for z: Dictionary in active_zones:
		var ids: Array = z.get("assigned_unit_ids", [])
		if not ids.is_empty():
			kept_zones.append(z)
	var zones_changed: bool = kept_zones.size() != active_zones.size()
	active_zones = kept_zones
	_sync_legacy_zone_fields()
	if zones_changed:
		zones_updated.emit(active_zones.duplicate(true))
	directive_changed.emit(get_directive_summary())

## Returns the active advance-move destination Vector3 for a unit, or null if none.
func get_advance_target_for_unit(student_id: String) -> Variant:
	if unit_advance_map.has(student_id):
		return unit_advance_map[student_id]
	return null

## Clears a unit's advance-move destination upon arrival.
func clear_advance_target_for_unit(student_id: String) -> void:
	if not unit_advance_map.has(student_id):
		return
	unit_advance_map.erase(student_id)
	if unit_advance_map.is_empty():
		has_advance_vector = false
		advance_origin = Vector3.ZERO
		advance_target = Vector3.ZERO
	directive_changed.emit(get_directive_summary())

## Sets a directional advance vector for the full squad WITHOUT implicitly spawning a tactical zone.
func set_advance_vector(from_pos: Vector3, to_pos: Vector3) -> void:
	set_advance_target_for_units(from_pos, to_pos, [])

## Clears zone/target/advance directives for specific unit IDs (if empty, does nothing; use clear_directives for all).
func clear_directives_for_units(unit_ids: Array = []) -> void:
	if unit_ids.is_empty():
		return
	for raw_uid in unit_ids:
		var uid: String = str(raw_uid)
		if uid.is_empty():
			continue
		unit_target_map.erase(uid)
		unit_zone_map.erase(uid)
		unit_advance_map.erase(uid)
		for z: Dictionary in active_zones:
			var ids: Array = z.get("assigned_unit_ids", [])
			ids.erase(uid)
			z["is_full_squad"] = (not squad_unit_ids.is_empty() and ids.size() >= squad_unit_ids.size())
	if unit_target_map.is_empty():
		priority_target = null
	if unit_advance_map.is_empty():
		has_advance_vector = false
		advance_origin = Vector3.ZERO
		advance_target = Vector3.ZERO
	var kept_zones: Array[Dictionary] = []
	for z: Dictionary in active_zones:
		var ids: Array = z.get("assigned_unit_ids", [])
		if not ids.is_empty():
			kept_zones.append(z)
	active_zones = kept_zones
	_sync_legacy_zone_fields()
	zones_updated.emit(active_zones.duplicate(true))
	directive_changed.emit(get_directive_summary())

## Clears all spatial directives, zones, targets, advance vectors, and active tool for the entire squad.
func clear_directives() -> void:
	priority_target = null
	has_tactical_zone = false
	has_advance_vector = false
	tactical_zone_center = Vector3.ZERO
	tactical_zone_radius = 6.5
	advance_origin = Vector3.ZERO
	advance_target = Vector3.ZERO
	active_zones.clear()
	unit_zone_map.clear()
	unit_target_map.clear()
	unit_advance_map.clear()
	active_tool = ToolMode.NONE
	tool_changed.emit(active_tool, get_tool_name())
	zones_updated.emit([])
	priority_target_changed.emit(null)
	directive_changed.emit(get_directive_summary())

func _sync_legacy_zone_fields() -> void:
	has_tactical_zone = not active_zones.is_empty()
	if has_tactical_zone:
		var latest: Dictionary = active_zones[active_zones.size() - 1]
		tactical_zone_center = latest.get("center", Vector3.ZERO)
		tactical_zone_radius = float(latest.get("radius", 6.5))
	else:
		tactical_zone_center = Vector3.ZERO
		tactical_zone_radius = 6.5

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
	var parts: Array[String] = []
	parts.append("Công cụ: %s" % get_tool_name())
	if active_zones.size() > 0:
		parts.append("%d Vùng tác chiến" % active_zones.size())
	if has_advance_vector or not unit_advance_map.is_empty():
		parts.append("Hướng tiến công")
	if get_valid_priority_target() != null or not unit_target_map.is_empty():
		parts.append("Mục tiêu ưu tiên")
	if tactical_slow_mo:
		parts.append("Slow-Mo 0.25x")
	return " | ".join(parts)
