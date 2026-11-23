# scripts/combat/SelectionBoxOverlay.gd
class_name SelectionBoxOverlay
extends Control

var is_dragging: bool = false
var drag_rect: Rect2 = Rect2()
var selected_screen_points: Array[Vector2] = []
var order_lines: Array[Dictionary] = []
var show_group_frame: bool = false
var tactical_zone_screen_center: Vector2 = Vector2.ZERO
var tactical_zone_screen_radius: float = 0.0
var advance_arrow: Dictionary = {}

func set_drag_rect(active: bool, rect: Rect2) -> void:
	is_dragging = active
	drag_rect = rect
	queue_redraw()

func update_tactical_markers(p_points: Array[Vector2], p_lines: Array[Dictionary]) -> void:
	selected_screen_points = p_points.duplicate()
	order_lines = p_lines.duplicate(true)
	queue_redraw()

## Updates 2D screen-space Commander tactical zone ring and directional advance arrow.
func update_commander_markers(zone_center: Vector2, zone_radius: float, arrow_info: Dictionary) -> void:
	tactical_zone_screen_center = zone_center
	tactical_zone_screen_radius = maxf(0.0, zone_radius)
	advance_arrow = arrow_info.duplicate(true)
	queue_redraw()

func _draw() -> void:
	# 0. Draw Commander directional advance vector arrow (tactical zones use aligned 3D discs)
	if bool(advance_arrow.get("active", false)):
		var a_from: Vector2 = advance_arrow.get("from", Vector2.ZERO)
		var a_to: Vector2 = advance_arrow.get("to", Vector2.ZERO)
		var a_col: Color = advance_arrow.get("color", Color(1.0, 0.82, 0.22, 0.90))
		if a_from.distance_to(a_to) > 8.0:
			draw_line(a_from, a_to, a_col, 3.0)
			var dir2: Vector2 = (a_to - a_from).normalized()
			var wing1: Vector2 = a_to - dir2.rotated(0.45) * 16.0
			var wing2: Vector2 = a_to - dir2.rotated(-0.45) * 16.0
			draw_line(a_to, wing1, a_col, 3.0)
			draw_line(a_to, wing2, a_col, 3.0)

	# 1. Draw active order / focus-fire target lines
	for line_info in order_lines:
		var from_pt: Vector2 = line_info.get("from", Vector2.ZERO)
		var to_pt: Vector2 = line_info.get("to", Vector2.ZERO)
		var col: Color = line_info.get("color", Color(0.25, 0.9, 1.0, 0.85))
		draw_line(from_pt, to_pt, col, 2.0)
		draw_arc(to_pt, 8.0, 0.0, TAU, 16, col, 2.0)

	# 2. Draw unit selection brackets & optional group multi-selection hull
	if show_group_frame and selected_screen_points.size() >= 2:
		var min_pt: Vector2 = selected_screen_points[0]
		var max_pt: Vector2 = selected_screen_points[0]
		for pt in selected_screen_points:
			min_pt.x = minf(min_pt.x, pt.x)
			min_pt.y = minf(min_pt.y, pt.y)
			max_pt.x = maxf(max_pt.x, pt.x)
			max_pt.y = maxf(max_pt.y, pt.y)
		var group_rect := Rect2(min_pt - Vector2(26.0, 26.0), (max_pt - min_pt) + Vector2(52.0, 52.0))
		draw_rect(group_rect, Color(0.25, 0.95, 0.65, 0.08), true)
		draw_rect(group_rect, Color(0.25, 0.95, 0.65, 0.75), false, 2.0)

	for pt in selected_screen_points:
		var box := Rect2(pt - Vector2(11.0, 11.0), Vector2(22.0, 22.0))
		draw_rect(box, Color(0.2, 0.9, 1.0, 0.95), false, 2.0)

	# 3. Draw live drag selection box
	if is_dragging:
		draw_rect(drag_rect, Color(0.2, 0.75, 1.0, 0.22), true)
		draw_rect(drag_rect, Color(0.25, 0.9, 1.0, 0.95), false, 2.0)
