# scripts/hub/ZoneTransitionManager.gd
extends Node

signal transition_started(target_scene_path: String, spawn_point_id: String)
signal transition_completed(target_scene_path: String, spawn_point_id: String)

var current_scene_path: String = ""
var pending_spawn_point_id: String = ""
var spawn_points: Dictionary = {}
var loading_tips: Array[String] = [
	"Schale Tip: Visit students around Kivotos between commissions to deepen your bond rank.",
	"Schale Tip: Manage your AP wisely—staying awake past 3:00 AM triggers forced sleep and reduces next-day AP.",
	"Schale Tip: Press [V] at any time in the Hub to toggle between Third-Person and First-Person view.",
	"Schale Tip: Check the Abydos desert and Trinity courtyard for hidden pickable supplies and gifts."
]

func register_spawn_point(id: String, position: Vector3) -> void:
	if id.is_empty():
		return
	spawn_points[id] = position

func get_spawn_position(id: String) -> Vector3:
	if spawn_points.has(id):
		return spawn_points[id] as Vector3
	return Vector3.ZERO

func clear_spawn_points() -> void:
	spawn_points.clear()

func get_random_tip() -> String:
	if loading_tips.is_empty():
		return ""
	return loading_tips[randi() % loading_tips.size()]

func transition_to(scene_path: String, spawn_id: String = "default") -> bool:
	if scene_path.is_empty():
		return false
	current_scene_path = scene_path
	pending_spawn_point_id = spawn_id
	transition_started.emit(scene_path, spawn_id)
	if is_inside_tree() and ResourceLoader.exists(scene_path):
		var tree := get_tree()
		if tree != null:
			tree.change_scene_to_file(scene_path)
	transition_completed.emit(scene_path, spawn_id)
	return true
