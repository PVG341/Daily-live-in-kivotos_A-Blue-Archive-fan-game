# scripts/combat/SkillTargetingOverlay.gd
class_name SkillTargetingOverlay
extends Control

signal target_confirmed(skill: SkillData, world_position: Vector3)
signal target_cancelled()

var active_skill: SkillData = null
var is_targeting: bool = false
var preview_world_position: Vector3 = Vector3.ZERO
var unclamped_world_position: Vector3 = Vector3.ZERO
var caster_origin: Vector3 = Vector3.ZERO
var is_target_in_range_flag: bool = true
var preview_screen_position: Vector2 = Vector2.ZERO
var preview_pixel_radius: float = 64.0
var caster_screen_position: Vector2 = Vector2.ZERO
var cast_range_pixel_radius: float = 0.0

func _init() -> void:
	visible = false

## Sets the caster world origin used for skill cast_range clamping and CONE/LINE orientation.
func set_caster_origin(origin: Vector3) -> void:
	caster_origin = origin

## Activates targeting mode for the given skill and reveals the overlay.
func begin_targeting(skill: SkillData) -> void:
	if skill == null:
		return
	active_skill = skill
	is_targeting = true
	is_target_in_range_flag = true
	visible = true
	queue_redraw()

## Updates live 2D/3D EX-Skill AoE preview position while hovering cursor, clamped to cast_range.
func update_preview(screen_pos: Vector2, camera: Camera3D = null, ground_y: float = 0.0) -> Vector3:
	preview_screen_position = screen_pos
	var raw_world_pos: Vector3 = _screen_to_ground(screen_pos, camera, ground_y)
	unclamped_world_position = raw_world_pos

	var world_pos: Vector3 = raw_world_pos
	if active_skill != null:
		is_target_in_range_flag = active_skill.is_target_in_range(caster_origin, raw_world_pos)
		world_pos = active_skill.clamp_target_to_range(caster_origin, raw_world_pos)
	else:
		is_target_in_range_flag = true

	var skill_radius: float = maxf(0.5, active_skill.aoe_radius if active_skill != null else 4.0)
	preview_pixel_radius = skill_radius * 18.0
	cast_range_pixel_radius = 0.0

	if camera != null and is_instance_valid(camera) and camera.is_inside_tree():
		if not camera.is_position_behind(world_pos):
			preview_screen_position = camera.unproject_position(world_pos)
			var edge_world: Vector3 = world_pos + Vector3(skill_radius, 0.0, 0.0)
			if not camera.is_position_behind(edge_world):
				var p1: Vector2 = camera.unproject_position(edge_world)
				preview_pixel_radius = clampf(preview_screen_position.distance_to(p1), 18.0, 260.0)
		if active_skill != null and active_skill.cast_range > 0.0 and not camera.is_position_behind(caster_origin):
			caster_screen_position = camera.unproject_position(caster_origin)
			var range_edge: Vector3 = caster_origin + Vector3(active_skill.cast_range, 0.0, 0.0)
			if not camera.is_position_behind(range_edge):
				cast_range_pixel_radius = clampf(caster_screen_position.distance_to(camera.unproject_position(range_edge)), 32.0, 1200.0)

	preview_world_position = world_pos
	queue_redraw()
	return preview_world_position

## Projects screen_pos onto the ground plane at ground_y (or uses headless fallback), clamps range, and confirms targeting.
func confirm_target(screen_pos: Vector2, camera: Camera3D = null, ground_y: float = 0.0) -> Vector3:
	var raw_world_pos: Vector3 = _screen_to_ground(screen_pos, camera, ground_y)
	unclamped_world_position = raw_world_pos
	var world_pos: Vector3 = raw_world_pos
	if active_skill != null:
		is_target_in_range_flag = active_skill.is_target_in_range(caster_origin, raw_world_pos)
		world_pos = active_skill.clamp_target_to_range(caster_origin, raw_world_pos)
	preview_world_position = world_pos
	is_targeting = false
	visible = false
	queue_redraw()
	target_confirmed.emit(active_skill, preview_world_position)
	return preview_world_position

func _screen_to_ground(screen_pos: Vector2, camera: Camera3D, ground_y: float) -> Vector3:
	var world_pos := Vector3(screen_pos.x, ground_y, screen_pos.y)
	if camera != null and is_instance_valid(camera) and camera.is_inside_tree():
		var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
		var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)
		if absf(ray_dir.y) > 0.0001:
			var t: float = (ground_y - ray_origin.y) / ray_dir.y
			if t >= 0.0:
				world_pos = ray_origin + ray_dir * t
	return world_pos

## Cancels active targeting, clears active_skill, hides the overlay, and emits target_cancelled.
func cancel_targeting() -> void:
	is_targeting = false
	active_skill = null
	is_target_in_range_flag = true
	cast_range_pixel_radius = 0.0
	visible = false
	queue_redraw()
	target_cancelled.emit()

func _draw() -> void:
	if not is_targeting or active_skill == null:
		return
	if cast_range_pixel_radius > 0.0:
		draw_arc(caster_screen_position, cast_range_pixel_radius, 0.0, TAU, 56, Color(0.3, 0.85, 1.0, 0.45), 1.8)
	var fill_col := Color(1.0, 0.75, 0.15, 0.22) if is_target_in_range_flag else Color(1.0, 0.25, 0.18, 0.24)
	var ring_col := Color(1.0, 0.85, 0.2, 0.95) if is_target_in_range_flag else Color(1.0, 0.3, 0.2, 0.95)
	draw_circle(preview_screen_position, preview_pixel_radius, fill_col)
	draw_arc(preview_screen_position, preview_pixel_radius, 0.0, TAU, 40, ring_col, 2.5)
