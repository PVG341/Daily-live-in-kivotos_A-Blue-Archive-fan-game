# scripts/combat/ProjectileManager.gd
class_name ProjectileManager
extends Node

const MAX_PROJECTILE_LIFETIME: float = 15.0

signal projectile_wall_hit(wall: Object, hit_pos: Vector3, penetrated: bool, wall_destroyed: bool)

var active_projectiles: Array[Dictionary] = []
var wall_obstacles: Array = []

func _exit_tree() -> void:
	clear_projectiles()
	wall_obstacles.clear()

## Registers active room DestructibleWall3D instances for projectile interception and piercing.
func set_wall_obstacles(walls: Array) -> void:
	wall_obstacles = walls.duplicate()

## Spawns a tracked projectile moving from origin toward target_pos with optional wall penetration stats.
func spawn_projectile(
	origin: Vector3,
	target_pos: Vector3,
	proj_speed: float,
	damage: int,
	source: Object = null,
	target_unit: Object = null,
	penetration_power: int = 0,
	wall_damage: int = 18
) -> Dictionary:
	var proj: Dictionary = {
		"origin": origin,
		"position": origin,
		"target_pos": target_pos,
		"speed": proj_speed,
		"damage": damage,
		"source": source,
		"target_unit": target_unit,
		"penetration_power": penetration_power,
		"wall_damage": wall_damage,
		"penetrated_wall_ids": [],
		"blocked_by_wall": null,
		"active": true,
		"elapsed": 0.0,
	}
	active_projectiles.append(proj)
	return proj

## Advances all active projectiles toward their targets, resolving wall collisions/penetration and hits on arrival.
func tick_projectiles(delta: float) -> int:
	var hits_resolved: int = 0
	var remaining: Array[Dictionary] = []
	var clamped_delta: float = maxf(0.0, delta)

	for proj in active_projectiles:
		if not bool(proj.get("active", false)):
			continue
		proj["elapsed"] = float(proj.get("elapsed", 0.0)) + clamped_delta
		if float(proj.get("speed", 0.0)) <= 0.0 or float(proj["elapsed"]) > MAX_PROJECTILE_LIFETIME:
			proj["active"] = false
			proj["source"] = null
			proj["target_unit"] = null
			continue
		var pos: Vector3 = proj["position"]
		var target_pos: Vector3 = proj["target_pos"]
		var step: float = maxf(0.0, float(proj["speed"]) * clamped_delta)
		var to_target: Vector3 = target_pos - pos
		var dist: float = to_target.length()
		var arriving: bool = (dist <= step or dist <= 0.0001)
		var next_pos: Vector3 = target_pos if arriving else (pos + (to_target / dist) * step)

		if _resolve_segment_wall_hits(proj, pos, next_pos):
			continue

		if arriving:
			proj["position"] = target_pos
			proj["active"] = false
			var target_unit: Variant = proj.get("target_unit", null)
			if target_unit != null and is_instance_valid(target_unit) and target_unit.has_method("take_damage"):
				target_unit.take_damage(int(proj["damage"]), proj.get("source", null))
			proj["source"] = null
			proj["target_unit"] = null
			hits_resolved += 1
		else:
			proj["position"] = next_pos
			remaining.append(proj)

	active_projectiles = remaining
	return hits_resolved

func _resolve_segment_wall_hits(proj: Dictionary, from_pos: Vector3, to_pos: Vector3) -> bool:
	if wall_obstacles.is_empty():
		return false
	var pierced_ids: Array = proj.get("penetrated_wall_ids", [])
	var origin: Vector3 = proj.get("origin", from_pos)
	var hits: Array[Dictionary] = []

	for wall in wall_obstacles:
		if wall == null or not is_instance_valid(wall) or wall.is_destroyed:
			continue
		if pierced_ids.has(wall.get_instance_id()):
			continue
		if wall.wall_size.y <= 1.05 and Vector2(origin.x, origin.z).distance_to(Vector2(wall.get_world_center().x, wall.get_world_center().z)) <= 3.2:
			continue
		var res: Dictionary = wall.intersects_segment(from_pos, to_pos)
		if bool(res.get("hit", false)):
			hits.append(res)

	if hits.is_empty():
		return false

	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("t", 1.0)) < float(b.get("t", 1.0))
	)

	var pen_power: int = int(proj.get("penetration_power", 0))
	var w_dmg: int = int(proj.get("wall_damage", 18))

	for h in hits:
		var wall = h.get("wall", null)
		if wall == null or not is_instance_valid(wall):
			continue
		var hit_pos: Vector3 = h.get("point", to_pos)
		var was_alive: bool = not bool(wall.is_destroyed)
		wall.take_structural_damage(w_dmg, pen_power)
		var now_destroyed: bool = bool(wall.is_destroyed)

		if pen_power >= int(wall.armor_tier) or now_destroyed:
			pierced_ids.append(wall.get_instance_id())
			proj["penetrated_wall_ids"] = pierced_ids
			proj["damage"] = maxi(1, int(round(float(proj["damage"]) * 0.75)))
			projectile_wall_hit.emit(wall, hit_pos, true, was_alive and now_destroyed)
		else:
			proj["position"] = hit_pos
			proj["active"] = false
			proj["blocked_by_wall"] = wall
			proj["source"] = null
			proj["target_unit"] = null
			projectile_wall_hit.emit(wall, hit_pos, false, false)
			return true

	return false

## Clears all tracked projectiles and releases any held object references.
func clear_projectiles() -> void:
	for proj in active_projectiles:
		proj["active"] = false
		proj["source"] = null
		proj["target_unit"] = null
		proj["blocked_by_wall"] = null
	active_projectiles.clear()

## Immediately applies hitscan damage along LOS, resolving wall interception/penetration first.
func spawn_hitscan(
	origin: Vector3,
	target: Object,
	damage: int,
	source: Object = null,
	penetration_power: int = 0,
	wall_damage: int = 35
) -> int:
	if target == null or not is_instance_valid(target) or not target.has_method("take_damage"):
		return 0

	var resolved_damage: int = damage
	if target is Node3D and not wall_obstacles.is_empty():
		var t_node := target as Node3D
		var target_pos: Vector3 = (t_node.global_position if t_node.is_inside_tree() else t_node.position) + Vector3(0.0, 0.7, 0.0)
		var hits: Array[Dictionary] = []
		for wall in wall_obstacles:
			if wall == null or not is_instance_valid(wall) or wall.is_destroyed:
				continue
			var res: Dictionary = wall.intersects_segment(origin, target_pos)
			if bool(res.get("hit", false)):
				hits.append(res)
		hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("t", 1.0)) < float(b.get("t", 1.0))
		)
		for h in hits:
			var wall = h.get("wall", null)
			if wall == null:
				continue
			var was_alive: bool = not bool(wall.is_destroyed)
			wall.take_structural_damage(wall_damage, penetration_power)
			var now_destroyed: bool = bool(wall.is_destroyed)
			if penetration_power >= int(wall.armor_tier) or now_destroyed:
				resolved_damage = maxi(1, int(round(float(resolved_damage) * 0.75)))
				projectile_wall_hit.emit(wall, h.get("point", target_pos), true, was_alive and now_destroyed)
			else:
				projectile_wall_hit.emit(wall, h.get("point", target_pos), false, false)
				return 0

	return int(target.take_damage(resolved_damage, source))
