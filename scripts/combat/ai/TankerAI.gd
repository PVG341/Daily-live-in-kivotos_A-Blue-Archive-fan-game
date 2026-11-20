# scripts/combat/ai/TankerAI.gd
class_name TankerAI
extends RoleAIBase

const CoverPoint3DScript := preload("res://scripts/combat/CoverPoint3D.gd")

## Selects an unoccupied cover point, preferring FULL cover and sorting by closest distance to enemies.
func pick_cover_point(covers: Array, enemies: Array = []) -> Variant:
	var candidates: Array = []
	for cover in covers:
		if cover == null:
			continue
		if cover is Object and not is_instance_valid(cover):
			continue
		if _is_cover_occupied(cover):
			continue
		candidates.append(cover)

	if candidates.is_empty():
		return null

	var best_cover: Variant = null
	var best_is_full: bool = false
	var best_dist: float = INF

	for cover in candidates:
		var is_full: bool = _is_full_cover(cover)
		var dist: float = _get_cover_enemy_distance(cover, enemies)
		if best_cover == null:
			best_cover = cover
			best_is_full = is_full
			best_dist = dist
			continue
		if is_full and not best_is_full:
			best_cover = cover
			best_is_full = true
			best_dist = dist
		elif is_full == best_is_full and dist < best_dist:
			best_cover = cover
			best_dist = dist

	return best_cover

## Takes forward cover to taunt enemies, or directly engages the nearest living enemy if no cover is free.
func evaluate_action(owner_unit: Object, _allies: Array, enemies: Array, covers: Array) -> Dictionary:
	if owner_unit != null and not _is_unit_alive(owner_unit):
		return _make_action("IDLE", null, 0.0)
	if should_yield_to_player(owner_unit):
		return _yield_action()

	var cover: Variant = pick_cover_point(covers, enemies)
	if cover != null:
		return {"action": "TAKE_COVER_AND_TAUNT", "target": cover, "priority": 1.0}

	var nearest_enemy: Variant = _pick_nearest_enemy(owner_unit, enemies)
	if nearest_enemy != null:
		return {"action": "TAUNT_ENGAGE", "target": nearest_enemy, "priority": 0.9}

	return _idle_action()

func _is_cover_occupied(cover: Variant) -> bool:
	if cover is Dictionary:
		return bool(cover.get("is_occupied", false))
	if cover is Object:
		var occ: Variant = cover.get(&"is_occupied")
		return bool(occ) if occ != null else false
	return true

func _is_full_cover(cover: Variant) -> bool:
	var raw_type: Variant = null
	if cover is Dictionary:
		raw_type = cover.get("cover_type", "HALF")
	elif cover is Object:
		raw_type = cover.get(&"cover_type")
	if raw_type is String:
		return raw_type == "FULL"
	if raw_type is int:
		return raw_type == CoverPoint3DScript.CoverType.FULL
	return false

func _get_cover_enemy_distance(cover: Variant, enemies: Array) -> float:
	if cover is Dictionary and cover.has("distance_to_enemy"):
		return float(cover["distance_to_enemy"])
	if cover is Object:
		var dist_prop: Variant = cover.get(&"distance_to_enemy")
		if dist_prop != null:
			return float(dist_prop)
		if cover.has_meta(&"distance_to_enemy"):
			return float(cover.get_meta(&"distance_to_enemy"))

	var cover_pos: Variant = _get_world_position(cover)
	if cover_pos is Vector3 and not enemies.is_empty():
		var min_dist: float = INF
		for enemy in enemies:
			if not _is_unit_alive(enemy):
				continue
			var enemy_pos: Variant = _get_world_position(enemy)
			if enemy_pos is Vector3:
				min_dist = minf(min_dist, (cover_pos as Vector3).distance_to(enemy_pos as Vector3))
		return min_dist
	return INF

func _pick_nearest_enemy(owner_unit: Object, enemies: Array) -> Variant:
	var owner_pos: Variant = _get_world_position(owner_unit)
	var best_enemy: Variant = null
	var best_dist: float = INF

	for enemy in enemies:
		if not _is_unit_alive(enemy):
			continue
		var dist: float = INF
		if enemy is Dictionary and enemy.has("distance"):
			dist = float(enemy["distance"])
		else:
			var enemy_pos: Variant = _get_world_position(enemy)
			if owner_pos is Vector3 and enemy_pos is Vector3:
				dist = (owner_pos as Vector3).distance_to(enemy_pos as Vector3)

		if best_enemy == null or dist < best_dist:
			best_enemy = enemy
			best_dist = dist

	return best_enemy
