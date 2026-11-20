# scripts/combat/SkillTargetingOverlay.gd
class_name SkillTargetingOverlay
extends Control

signal target_confirmed(skill: SkillData, world_position: Vector3)
signal target_cancelled()

var active_skill: SkillData = null
var is_targeting: bool = false
var preview_world_position: Vector3 = Vector3.ZERO

func _init() -> void:
	visible = false

## Activates targeting mode for the given skill and reveals the overlay.
func begin_targeting(skill: SkillData) -> void:
	if skill == null:
		return
	active_skill = skill
	is_targeting = true
	visible = true

## Projects screen_pos onto the ground plane at ground_y (or uses headless fallback) and confirms targeting.
func confirm_target(screen_pos: Vector2, camera: Camera3D = null, ground_y: float = 0.0) -> Vector3:
	var world_pos := Vector3(screen_pos.x, ground_y, screen_pos.y)
	if camera != null and is_instance_valid(camera) and camera.is_inside_tree():
		var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
		var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)
		if absf(ray_dir.y) > 0.0001:
			var t: float = (ground_y - ray_origin.y) / ray_dir.y
			if t >= 0.0:
				world_pos = ray_origin + ray_dir * t
	preview_world_position = world_pos
	is_targeting = false
	visible = false
	target_confirmed.emit(active_skill, preview_world_position)
	return preview_world_position

## Cancels active targeting, clears active_skill, hides the overlay, and emits target_cancelled.
func cancel_targeting() -> void:
	is_targeting = false
	active_skill = null
	visible = false
	target_cancelled.emit()
