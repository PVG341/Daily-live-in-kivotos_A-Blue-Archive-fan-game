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

## Attempts to reserve this cover point for the given unit; fails if already held by another unit.
func claim(unit: Object) -> bool:
	if unit == null:
		return false
	if is_occupied and occupant != unit:
		return false
	is_occupied = true
	occupant = unit
	return true

## Releases occupancy when called by the current occupant or with no unit specified.
func release(unit: Object = null) -> void:
	if unit == null or occupant == unit:
		is_occupied = false
		occupant = null
