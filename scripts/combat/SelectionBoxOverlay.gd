# scripts/combat/SelectionBoxOverlay.gd
class_name SelectionBoxOverlay
extends Control

var is_dragging: bool = false
var drag_rect: Rect2 = Rect2()

func set_drag_rect(active: bool, rect: Rect2) -> void:
	is_dragging = active
	drag_rect = rect
	queue_redraw()

func _draw() -> void:
	if not is_dragging:
		return
	draw_rect(drag_rect, Color(0.2, 0.75, 1.0, 0.22), true)
	draw_rect(drag_rect, Color(0.25, 0.9, 1.0, 0.95), false, 2.0)
