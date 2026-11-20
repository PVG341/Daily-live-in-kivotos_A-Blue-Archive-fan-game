# scripts/combat/SelectionMath.gd
class_name SelectionMath
extends RefCounted

## Normalizes two screen-space drag corners into a Rect2 with top-left origin and non-negative size.
func normalize_selection_rect(start: Vector2, end: Vector2) -> Rect2:
	var origin := Vector2(minf(start.x, end.x), minf(start.y, end.y))
	var size := (end - start).abs()
	return Rect2(origin, size)

## Returns true if point lies inside or on the inclusive boundary of rect.
func is_point_in_rect(point: Vector2, rect: Rect2) -> bool:
	var normalized: Rect2 = rect.abs()
	var end_pt: Vector2 = normalized.position + normalized.size
	return (
		point.x >= normalized.position.x
		and point.x <= end_pt.x
		and point.y >= normalized.position.y
		and point.y <= end_pt.y
	)
