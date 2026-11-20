# scripts/combat/ProjectileManager.gd
class_name ProjectileManager
extends Node

var active_projectiles: Array[Dictionary] = []

## Spawns a tracked projectile moving from origin toward target_pos.
func spawn_projectile(
	origin: Vector3,
	target_pos: Vector3,
	proj_speed: float,
	damage: int,
	source: Object = null,
	target_unit: Object = null
) -> Dictionary:
	var proj: Dictionary = {
		"origin": origin,
		"position": origin,
		"target_pos": target_pos,
		"speed": proj_speed,
		"damage": damage,
		"source": source,
		"target_unit": target_unit,
		"active": true,
	}
	active_projectiles.append(proj)
	return proj

## Advances all active projectiles toward their targets and resolves hits on arrival.
func tick_projectiles(delta: float) -> int:
	var hits_resolved: int = 0
	var remaining: Array[Dictionary] = []
	var clamped_delta: float = maxf(0.0, delta)

	for proj in active_projectiles:
		if not bool(proj.get("active", false)):
			continue
		var pos: Vector3 = proj["position"]
		var target_pos: Vector3 = proj["target_pos"]
		var step: float = maxf(0.0, float(proj["speed"]) * clamped_delta)
		var to_target: Vector3 = target_pos - pos
		var dist: float = to_target.length()

		if dist <= step or dist <= 0.0001:
			proj["position"] = target_pos
			proj["active"] = false
			var target_unit: Variant = proj.get("target_unit", null)
			if target_unit != null and is_instance_valid(target_unit) and target_unit.has_method("take_damage"):
				target_unit.take_damage(int(proj["damage"]), proj.get("source", null))
			hits_resolved += 1
		else:
			proj["position"] = pos + (to_target / dist) * step
			remaining.append(proj)

	active_projectiles = remaining
	return hits_resolved

## Immediately applies hitscan damage to target if valid and damageable.
func spawn_hitscan(_origin: Vector3, target: Object, damage: int, source: Object = null) -> int:
	if target == null or not is_instance_valid(target) or not target.has_method("take_damage"):
		return 0
	return int(target.take_damage(damage, source))
