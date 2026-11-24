# scripts/combat/CoverPoint3D.gd
class_name CoverPoint3D
extends Marker3D

enum CoverType {
	HALF,
	FULL
}

@export var cover_type: CoverType = CoverType.HALF
@export var cover_direction: Vector3 = Vector3.FORWARD

var is_occupied: bool = false
var occupant: Object = null

## Returns the normalized blocking direction of this cover point, defaulting to Vector3.FORWARD.
func get_cover_direction() -> Vector3:
	if cover_direction.is_zero_approx():
		return Vector3.FORWARD
	return cover_direction.normalized()

## Returns the world-space position of this cover point even when parented to an offset sector out-of-tree.
func get_world_position() -> Vector3:
	if is_inside_tree():
		return global_position
	var xform: Transform3D = transform
	var p: Node = get_parent()
	while p != null:
		if p is Node3D:
			xform = (p as Node3D).transform * xform
		p = p.get_parent()
	return xform.origin

func _sanitize_occupant() -> void:
	if occupant == null:
		is_occupied = false
		return
	if not is_instance_valid(occupant):
		is_occupied = false
		occupant = null
		return
	var alive_val: Variant = occupant.get(&"is_alive")
	if alive_val != null and not bool(alive_val):
		is_occupied = false
		occupant = null

## Attempts to reserve this cover point for the given unit; fails if already held by another unit.
func claim(unit: Object) -> bool:
	_sanitize_occupant()
	if unit == null or not is_instance_valid(unit):
		return false
	if is_occupied and occupant != unit:
		return false
	is_occupied = true
	occupant = unit
	return true

## Releases occupancy when called by the current occupant or with no unit specified.
func release(unit: Object = null) -> void:
	_sanitize_occupant()
	if unit == null or occupant == unit:
		is_occupied = false
		occupant = null
