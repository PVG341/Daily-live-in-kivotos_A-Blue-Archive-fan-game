# scripts/combat/UnitSelectionManager.gd
class_name UnitSelectionManager
extends Node

const SelectionMathScript := preload("res://scripts/combat/SelectionMath.gd")

signal selection_changed(units: Array[Node3D])
signal order_issued(order_type: String, units: Array[Node3D])

var selected_units: Array[Node3D] = []
var selection_math: SelectionMathScript = null

func _init() -> void:
	selection_math = SelectionMathScript.new()

## Selects a unit; when append is false, replaces the current selection.
func select_unit(unit: Node3D, append: bool = true) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if not append:
		selected_units.clear()
	if not selected_units.has(unit):
		selected_units.append(unit)
	selection_changed.emit(selected_units.duplicate())

## Removes a single unit from the current selection.
func deselect_unit(unit: Node3D) -> void:
	if unit == null:
		return
	if selected_units.has(unit):
		selected_units.erase(unit)
		selection_changed.emit(selected_units.duplicate())

## Clears all selected units.
func deselect_all() -> void:
	if selected_units.is_empty():
		return
	selected_units.clear()
	selection_changed.emit(selected_units.duplicate())

## Projects 3D units through camera and selects those inside the normalized screen_rect.
func box_select(screen_rect: Rect2, camera: Camera3D, units: Array) -> Array[Node3D]:
	deselect_all()
	if camera == null or not is_instance_valid(camera) or not camera.is_inside_tree():
		return selected_units
	var normalized: Rect2 = selection_math.normalize_selection_rect(screen_rect.position, screen_rect.end)
	for candidate in units:
		if not (candidate is Node3D) or not is_instance_valid(candidate):
			continue
		var unit := candidate as Node3D
		var world_pos: Vector3 = unit.global_position if unit.is_inside_tree() else unit.position
		if camera.is_position_behind(world_pos):
			continue
		var screen_pt: Vector2 = camera.unproject_position(world_pos)
		if selection_math.is_point_in_rect(screen_pt, normalized):
			if not selected_units.has(unit):
				selected_units.append(unit)
	selection_changed.emit(selected_units.duplicate())
	return selected_units

## Headless-friendly box selection using precomputed unit -> screen Vector2 coordinates.
func box_select_screen_points(screen_rect: Rect2, unit_screen_map: Dictionary) -> Array[Node3D]:
	deselect_all()
	var normalized: Rect2 = selection_math.normalize_selection_rect(screen_rect.position, screen_rect.end)
	for candidate in unit_screen_map.keys():
		if not (candidate is Node3D) or not is_instance_valid(candidate):
			continue
		var pt_variant: Variant = unit_screen_map[candidate]
		if not (pt_variant is Vector2):
			continue
		if selection_math.is_point_in_rect(pt_variant as Vector2, normalized):
			var unit := candidate as Node3D
			if not selected_units.has(unit):
				selected_units.append(unit)
	selection_changed.emit(selected_units.duplicate())
	return selected_units

## Orders all selected units to move to the target world position.
func issue_move_order(target: Vector3) -> void:
	_dispatch_order(
		"MOVE",
		{&"order_target_position": target},
		{&"target_position": target, &"order_target_position": target},
		[&"receive_move_order"],
		target,
		true
	)

## Orders all selected units to take cover at the given cover point.
func issue_cover_order(cover_point: Node3D) -> void:
	if cover_point == null or not is_instance_valid(cover_point):
		return
	_dispatch_order(
		"COVER",
		{&"order_target_cover": cover_point},
		{&"target_cover": cover_point, &"order_target_cover": cover_point},
		[&"receive_cover_order"],
		cover_point,
		true
	)

## Orders all selected units to focus fire on the specified enemy node.
func issue_focus_fire(enemy: Node3D) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	_dispatch_order(
		"FOCUS_FIRE",
		{&"order_target_enemy": enemy},
		{&"target_enemy": enemy, &"order_target_enemy": enemy},
		[&"receive_focus_fire", &"receive_focus_fire_order"],
		enemy,
		true
	)

## Orders all selected units to hold their current positions.
func issue_hold_position() -> void:
	_dispatch_order(
		"HOLD_POSITION",
		{},
		{},
		[&"receive_hold_position", &"receive_hold_position_order"]
	)

## Orders all selected units to hold fire.
func issue_hold_fire() -> void:
	_dispatch_order(
		"HOLD_FIRE",
		{},
		{},
		[&"receive_hold_fire", &"receive_hold_fire_order"]
	)

func _dispatch_order(
	order_type: String,
	meta_fields: Dictionary,
	prop_fields: Dictionary,
	callbacks: Array[StringName],
	callback_arg: Variant = null,
	has_arg: bool = false
) -> void:
	var valid_units: Array[Node3D] = []
	for unit in selected_units:
		if unit == null or not is_instance_valid(unit):
			continue
		valid_units.append(unit)
		unit.set_meta(&"has_player_order", true)
		unit.set_meta(&"order_type", order_type)
		if &"has_player_order" in unit:
			unit.set(&"has_player_order", true)
		if &"order_type" in unit:
			unit.set(&"order_type", order_type)

		for meta_key: StringName in meta_fields:
			unit.set_meta(meta_key, meta_fields[meta_key])
		for prop_key: StringName in prop_fields:
			if prop_key in unit:
				unit.set(prop_key, prop_fields[prop_key])

		for cb: StringName in callbacks:
			if unit.has_method(cb):
				if has_arg:
					unit.call(cb, callback_arg)
				else:
					unit.call(cb)
				break

	if valid_units.size() != selected_units.size():
		selected_units = valid_units
	order_issued.emit(order_type, valid_units)
