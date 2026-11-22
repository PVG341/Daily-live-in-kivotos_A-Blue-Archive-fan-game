# scripts/combat/SkillTargetingOverlay.gd
class_name SkillTargetingOverlay
extends Control

signal target_confirmed(skill: SkillData, world_position: Vector3)
signal target_cancelled()

var active_skill: SkillData = null
var is_targeting: bool = false
var preview_world_position: Vector3 = Vector3.ZERO
var preview_screen_position: Vector2 = Vector2.ZERO
var preview_pixel_radius: float = 64.0

func _init() -> void:
	visible = false

## Activates targeting mode for the given skill and reveals the overlay.
func begin_targeting(skill: SkillData) -> void:
	if skill == null:
		return
	active_skill = skill
	is_targeting = true
	visible = true
	queue_redraw()

## Updates live 2D/3D EX-Skill AoE preview position while hovering cursor.
func update_preview(screen_pos: Vector2, camera: Camera3D = null, ground_y: float = 0.0) -> Vector3:
	preview_screen_position = screen_pos
	var world_pos := Vector3(screen_pos.x, ground_y, screen_pos.y)
	var skill_radius: float = maxf(0.5, active_skill.aoe_radius if active_skill != null else 4.0)
	preview_pixel_radius = skill_radius * 18.0

	if camera != null and is_instance_valid(camera) and camera.is_inside_tree():
		var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
		var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)
		if absf(ray_dir.y) > 0.0001:
			var t: float = (ground_y - ray_origin.y) / ray_dir.y
			if t >= 0.0:
				world_pos = ray_origin + ray_dir * t
				var edge_world: Vector3 = world_pos + Vector3(skill_radius, 0.0, 0.0)
				if not camera.is_position_behind(world_pos) and not camera.is_position_behind(edge_world):
					var p0: Vector2 = camera.unproject_position(world_pos)
					var p1: Vector2 = camera.unproject_position(edge_world)
					preview_pixel_radius = clampf(p0.distance_to(p1), 18.0, 260.0)

	preview_world_position = world_pos
	queue_redraw()
	return preview_world_position

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
	queue_redraw()
	target_confirmed.emit(active_skill, preview_world_position)
	return preview_world_position

## Cancels active targeting, clears active_skill, hides the overlay, and emits target_cancelled.
func cancel_targeting() -> void:
	is_targeting = false
	active_skill = null
	visible = false
	queue_redraw()
	target_cancelled.emit()

func _draw() -> void:
	if not is_targeting or active_skill == null:
		return
	draw_circle(preview_screen_position, preview_pixel_radius, Color(1.0, 0.75, 0.15, 0.22))
	draw_arc(preview_screen_position, preview_pixel_radius, 0.0, TAU, 40, Color(1.0, 0.85, 0.2, 0.95), 2.5)
