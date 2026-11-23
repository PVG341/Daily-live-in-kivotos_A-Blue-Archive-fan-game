class_name SkillData
extends Resource

@export var id: String = ""
@export var name: String = ""
@export var cost: int = 0
@export var cooldown: float = 0.0
@export var aoe_radius: float = 0.0
@export var effect_type: String = ""

# Tactical range, shape & wall interaction configuration
@export var cast_range: float = 24.0
@export var min_range: float = 0.0
@export var aoe_shape: String = "CIRCLE" # "CIRCLE", "CONE", "LINE"
@export var cone_angle_deg: float = 55.0
@export var line_width: float = 2.2
@export var requires_los: bool = true
@export var pierce_walls: bool = false
@export var penetration_power: int = 0
@export var wall_damage: int = 0

## Returns true when desired_pos lies within [min_range, cast_range] on the XZ plane from origin_pos.
func is_target_in_range(origin_pos: Vector3, desired_pos: Vector3) -> bool:
	var dist: float = Vector2(origin_pos.x, origin_pos.z).distance_to(Vector2(desired_pos.x, desired_pos.z))
	if min_range > 0.0 and dist < min_range - 0.01:
		return false
	if cast_range > 0.0 and dist > cast_range + 0.01:
		return false
	return true

## Clamps desired_pos on the XZ plane relative to origin_pos into [min_range, cast_range].
func clamp_target_to_range(origin_pos: Vector3, desired_pos: Vector3) -> Vector3:
	var orig_xz := Vector2(origin_pos.x, origin_pos.z)
	var target_xz := Vector2(desired_pos.x, desired_pos.z)
	var offset: Vector2 = target_xz - orig_xz
	var dist: float = offset.length()
	var dir: Vector2 = (offset / dist) if dist > 0.0001 else Vector2(0.0, -1.0)
	var clamped_dist: float = dist
	if min_range > 0.0:
		clamped_dist = maxf(clamped_dist, min_range)
	if cast_range > 0.0:
		clamped_dist = minf(clamped_dist, cast_range)
	var final_xz: Vector2 = orig_xz + dir * clamped_dist
	return Vector3(final_xz.x, desired_pos.y, final_xz.y)

## Evaluates whether candidate_pos is hit by this skill's configured AoE shape ("CIRCLE", "CONE", or "LINE").
func is_point_inside_aoe(origin_pos: Vector3, target_pos: Vector3, candidate_pos: Vector3) -> bool:
	var cand_xz := Vector2(candidate_pos.x, candidate_pos.z)
	var target_xz := Vector2(target_pos.x, target_pos.z)
	var shape: String = aoe_shape.to_upper()
	if shape == "CONE":
		var orig_xz := Vector2(origin_pos.x, origin_pos.z)
		var to_target: Vector2 = target_xz - orig_xz
		var forward: Vector2 = to_target.normalized() if to_target.length() > 0.0001 else Vector2(0.0, -1.0)
		var cone_len: float = maxf(aoe_radius, to_target.length())
		var to_cand: Vector2 = cand_xz - orig_xz
		var d: float = to_cand.length()
		if d > cone_len:
			return false
		if d <= 0.0001:
			return true
		var half_cos: float = cos(deg_to_rad(clampf(cone_angle_deg, 5.0, 175.0) * 0.5))
		return forward.dot(to_cand / d) >= half_cos
	elif shape == "LINE":
		var orig_xz := Vector2(origin_pos.x, origin_pos.z)
		var to_target: Vector2 = target_xz - orig_xz
		var forward: Vector2 = to_target.normalized() if to_target.length() > 0.0001 else Vector2(0.0, -1.0)
		var line_len: float = maxf(aoe_radius, to_target.length())
		var to_cand: Vector2 = cand_xz - orig_xz
		var proj: float = to_cand.dot(forward)
		if proj < 0.0 or proj > line_len:
			return false
		var perp: Vector2 = to_cand - forward * proj
		return perp.length() <= maxf(0.1, line_width * 0.5)
	return cand_xz.distance_to(target_xz) <= maxf(0.0, aoe_radius)
