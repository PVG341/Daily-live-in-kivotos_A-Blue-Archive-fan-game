# scripts/combat/ai/UtilityAIManager.gd
class_name UtilityAIManager
extends RefCounted

const STANCE_ASSAULT: int = 0
const STANCE_BALANCED: int = 1
const STANCE_DEFENSIVE: int = 2

## Scores autonomous combat options weighted by Commander directives, Role, AoE threats, LOS, and Bond compliance.
func evaluate_unit_utility(
	unit: Object,
	allies: Array,
	enemies: Array,
	covers: Array,
	active_aoes: Array,
	directives: Object,
	room_info: Object = null,
	bond_level: int = 1
) -> Dictionary:
	if unit == null or not is_instance_valid(unit) or not _is_alive(unit):
		return {"action": "IDLE", "target": null, "target_pos": Vector3.ZERO, "score": 0.0, "status_tag": ""}

	var unit_pos: Vector3 = _get_pos(unit)
	var hp_ratio: float = _get_hp_ratio(unit)
	var stance: int = int(directives.get("current_stance")) if (directives != null and &"current_stance" in directives) else STANCE_BALANCED
	var compliance_mult: float = 1.0 + clampf(float(maxi(1, bond_level)) * 0.005, 0.0, 0.5)
	var unit_role: int = StudentData.CombatRole.DAMAGE_DEALER
	var udata: Variant = unit.get(&"unit_data")
	if udata != null and udata is StudentData:
		unit_role = (udata as StudentData).role

	var best: Dictionary = {
		"action": "IDLE",
		"target": null,
		"target_pos": unit_pos,
		"score": 0.1,
		"status_tag": "",
	}

	# 1. Evade incoming red TelegraphedAoE zones (highest survival instinct)
	for aoe in active_aoes:
		if aoe == null or not is_instance_valid(aoe):
			continue
		if bool(aoe.get(&"has_detonated")):
			continue
		var aoe_pos: Vector3 = _get_pos(aoe)
		var aoe_rad: float = float(aoe.get(&"radius"))
		var offset_xz := Vector2(unit_pos.x - aoe_pos.x, unit_pos.z - aoe_pos.z)
		var dist_xz: float = offset_xz.length()
		if dist_xz <= aoe_rad + 0.8:
			var esc_dir: Vector2 = (offset_xz / dist_xz) if dist_xz > 0.05 else _unit_spread_dir(unit)
			var esc_dist: float = aoe_rad + 2.4
			var escape_pos := Vector3(aoe_pos.x + esc_dir.x * esc_dist, unit_pos.y, aoe_pos.z + esc_dir.y * esc_dist)
			best = {
				"action": "EVADE_AOE",
				"target": aoe,
				"target_pos": escape_pos,
				"score": 120.0,
				"status_tag": "⚠️ NÉ AoE",
			}
			break

	# 2. Healer rescues injured allies
	if unit_role == StudentData.CombatRole.HEALER:
		var injured: Object = null
		var lowest_hp: float = 0.85
		for ally in allies:
			if ally == null or not is_instance_valid(ally) or not _is_alive(ally):
				continue
			var r: float = _get_hp_ratio(ally)
			if r < lowest_hp:
				lowest_hp = r
				injured = ally
		if injured != null:
			var heal_score: float = 72.0 + (1.0 - lowest_hp) * 40.0
			if heal_score > float(best["score"]):
				best = {
					"action": "HEAL_ALLY",
					"target": injured,
					"target_pos": _get_pos(injured),
					"score": heal_score,
					"status_tag": "🩹 CỨU THƯƠNG",
				}

	# 3. Critical HP survival retreat toward safe cover or backline
	var retreat_thresh: float = 0.50 if stance == STANCE_DEFENSIVE else 0.32
	if hp_ratio < retreat_thresh and not enemies.is_empty():
		var retreat_pos: Vector3 = _find_retreat_position(unit, unit_pos, allies, enemies, covers)
		var retreat_score: float = 95.0 if stance == STANCE_DEFENSIVE else 85.0
		if retreat_score > float(best["score"]):
			best = {
				"action": "SURVIVAL_RETREAT",
				"target": null,
				"target_pos": retreat_pos,
				"score": retreat_score,
				"status_tag": "🛡️ RÚT LUI",
			}

	# 4. Commander Tactical Zone / Advance Vector directive
	if directives != null and bool(directives.get("has_tactical_zone")):
		var zone_center: Vector3 = directives.get("tactical_zone_center")
		var zone_rad: float = maxf(2.5, float(directives.get("tactical_zone_radius")))
		var dist_to_zone: float = Vector2(unit_pos.x, unit_pos.z).distance_to(Vector2(zone_center.x, zone_center.z))
		if dist_to_zone > zone_rad:
			var zone_score: float = 60.0 * compliance_mult
			if bool(directives.get("has_advance_vector")) or stance == STANCE_DEFENSIVE:
				zone_score += 16.0
			var spread: Vector2 = _unit_spread_dir(unit) * minf(2.6, zone_rad * 0.42)
			var move_target := Vector3(zone_center.x + spread.x, unit_pos.y, zone_center.z + spread.y)
			if zone_score > float(best["score"]):
				best = {
					"action": "ADVANCE_TO_ZONE",
					"target": null,
					"target_pos": move_target,
					"score": zone_score,
					"status_tag": "🚩 TIẾN VÀO VÙNG",
				}

	# 5. Commander Priority Target directive
	var prio_target: Object = null
	if directives != null and directives.has_method(&"get_valid_priority_target"):
		prio_target = directives.get_valid_priority_target()
	if prio_target != null and _is_alive(prio_target):
		var prio_score: float = 68.0 * compliance_mult
		if stance == STANCE_ASSAULT:
			prio_score += 15.0
		elif stance == STANCE_DEFENSIVE:
			prio_score -= 10.0
		if prio_score > float(best["score"]):
			best = {
				"action": "FOCUS_PRIORITY_TARGET",
				"target": prio_target,
				"target_pos": _get_pos(prio_target),
				"score": prio_score,
				"status_tag": "🎯 MỤC TIÊU CHỈ ĐỊNH",
			}

	# 6. Seek nearby CoverPoint3D & engage visible enemy
	var living_enemies: Array = []
	for e in enemies:
		if e != null and is_instance_valid(e) and _is_alive(e):
			living_enemies.append(e)

	if not living_enemies.is_empty():
		var cover_pick: Variant = _find_best_cover(unit, unit_pos, covers, directives, living_enemies, room_info)
		if cover_pick != null:
			var cover_score: float = 46.0
			if stance == STANCE_DEFENSIVE:
				cover_score += 18.0
			elif stance == STANCE_ASSAULT:
				cover_score -= 12.0
			if unit_role == StudentData.CombatRole.TANKER:
				cover_score += 12.0
			if cover_score > float(best["score"]):
				var vis_enemy: Object = _pick_best_enemy(unit, unit_pos, living_enemies, room_info)
				best = {
					"action": "TAKE_COVER_AND_ENGAGE",
					"target": vis_enemy,
					"target_pos": _get_pos(cover_pick),
					"cover": cover_pick,
					"score": cover_score,
					"status_tag": "🧱 NẤP & BẮN",
				}

		# 7. Autonomous combat target scoring (prefers clear LOS & weakened targets)
		var pen: int = int(unit.get(&"penetration_power")) if (&"penetration_power" in unit) else 0
		var best_enemy: Object = null
		var best_enemy_score: float = -INF
		for enemy in living_enemies:
			var e_pos: Vector3 = _get_pos(enemy)
			var dist: float = Vector2(unit_pos.x, unit_pos.z).distance_to(Vector2(e_pos.x, e_pos.z))
			var e_hp: float = _get_hp_ratio(enemy)
			var clear_los: bool = _check_los(unit_pos, e_pos, room_info, pen)
			var candidate_score: float = 36.0 - dist * 0.5 + (1.0 - e_hp) * 14.0
			if clear_los:
				candidate_score += 12.0
			if stance == STANCE_ASSAULT:
				candidate_score += 12.0
			if candidate_score > best_enemy_score:
				best_enemy_score = candidate_score
				best_enemy = enemy

		if best_enemy != null and best_enemy_score > float(best["score"]):
			best = {
				"action": "ENGAGE_BEST_ENEMY",
				"target": best_enemy,
				"target_pos": _get_pos(best_enemy),
				"score": best_enemy_score,
				"status_tag": "⚔️ TỰ ĐỘNG ĐÁNH",
			}

	return best

func _pick_best_enemy(unit: Object, unit_pos: Vector3, living_enemies: Array, room_info: Object) -> Object:
	var pen: int = int(unit.get(&"penetration_power")) if (&"penetration_power" in unit) else 0
	var chosen: Object = living_enemies[0]
	var chosen_score: float = -INF
	for enemy in living_enemies:
		var e_pos: Vector3 = _get_pos(enemy)
		var dist: float = Vector2(unit_pos.x, unit_pos.z).distance_to(Vector2(e_pos.x, e_pos.z))
		var sc: float = -dist + (15.0 if _check_los(unit_pos, e_pos, room_info, pen) else 0.0)
		if sc > chosen_score:
			chosen_score = sc
			chosen = enemy
	return chosen

func _find_best_cover(unit: Object, unit_pos: Vector3, covers: Array, directives: Object, living_enemies: Array = [], room_info: Object = null) -> Variant:
	var best_cp: Variant = null
	var best_score: float = -INF
	var has_zone: bool = directives != null and bool(directives.get("has_tactical_zone"))
	var zone_center: Vector3 = directives.get("tactical_zone_center") if has_zone else Vector3.ZERO
	var zone_rad: float = float(directives.get("tactical_zone_radius")) if has_zone else 999.0
	var stance: int = int(directives.get("current_stance")) if (directives != null and &"current_stance" in directives) else STANCE_BALANCED
	var pen: int = int(unit.get(&"penetration_power")) if (&"penetration_power" in unit) else 0
	var atk_range: float = maxf(6.0, float(unit.get(&"attack_range")) if (&"attack_range" in unit) else 10.0)

	for cp in covers:
		if cp == null or not is_instance_valid(cp):
			continue
		var occ: Variant = cp.get(&"occupant")
		if bool(cp.get(&"is_occupied")) and occ != unit and occ != null and is_instance_valid(occ) and _is_alive(occ):
			continue
		var cp_pos: Vector3 = _get_pos(cp)
		var d: float = Vector2(unit_pos.x, unit_pos.z).distance_to(Vector2(cp_pos.x, cp_pos.z))
		if d > 14.0:
			continue
		if has_zone and Vector2(cp_pos.x, cp_pos.z).distance_to(Vector2(zone_center.x, zone_center.z)) > zone_rad + 1.5:
			continue

		# Skip blind covers unless holding defensive stance, so units advance/flank after clearing nearby foes
		var can_engage_from_cover: bool = false
		for enemy in living_enemies:
			var e_pos: Vector3 = _get_pos(enemy)
			if Vector2(cp_pos.x, cp_pos.z).distance_to(Vector2(e_pos.x, e_pos.z)) <= atk_range + 2.0:
				if _check_los(cp_pos, e_pos, room_info, pen):
					can_engage_from_cover = true
					break
		if not can_engage_from_cover and stance != STANCE_DEFENSIVE:
			continue

		var sc: float = 20.0 - d
		if occ == unit:
			sc += 6.0
		if sc > best_score:
			best_score = sc
			best_cp = cp
	return best_cp

func _find_retreat_position(unit: Object, unit_pos: Vector3, allies: Array, enemies: Array, covers: Array) -> Vector3:
	for ally in allies:
		if ally == unit or ally == null or not is_instance_valid(ally) or not _is_alive(ally):
			continue
		var udata: Variant = ally.get(&"unit_data")
		if udata is StudentData and (udata as StudentData).role == StudentData.CombatRole.HEALER:
			return _get_pos(ally) + Vector3(0.0, 0.0, 2.5)
	var nearest_enemy: Object = enemies[0]
	var min_d: float = INF
	for e in enemies:
		if e == null or not is_instance_valid(e) or not _is_alive(e):
			continue
		var d: float = unit_pos.distance_to(_get_pos(e))
		if d < min_d:
			min_d = d
			nearest_enemy = e
	var e_pos: Vector3 = _get_pos(nearest_enemy)
	var away := Vector2(unit_pos.x - e_pos.x, unit_pos.z - e_pos.z)
	var dir2: Vector2 = away.normalized() if away.length() > 0.05 else Vector2(0.0, 1.0)
	var fallback := unit_pos + Vector3(dir2.x * 5.0, 0.0, dir2.y * 5.0)
	for cp in covers:
		if cp != null and is_instance_valid(cp) and not bool(cp.get(&"is_occupied")):
			var cp_pos: Vector3 = _get_pos(cp)
			if cp_pos.distance_to(e_pos) > min_d:
				return cp_pos
	return fallback

func _check_los(from_pos: Vector3, to_pos: Vector3, room_info: Object, pen: int) -> bool:
	if room_info == null or not is_instance_valid(room_info) or not room_info.has_method(&"check_line_of_sight"):
		return true
	var res: Dictionary = room_info.check_line_of_sight(from_pos + Vector3(0.0, 0.7, 0.0), to_pos + Vector3(0.0, 0.7, 0.0), pen)
	return bool(res.get("clear", true))

func _unit_spread_dir(unit: Object) -> Vector2:
	var idx: int = abs(unit.get_instance_id()) % 8
	var angle: float = float(idx) * (TAU / 8.0)
	return Vector2(cos(angle), sin(angle))

func _is_alive(obj: Object) -> bool:
	var alive_val: Variant = obj.get(&"is_alive")
	return bool(alive_val) if alive_val != null else true

func _get_hp_ratio(obj: Object) -> float:
	var cur: float = float(obj.get(&"current_hp"))
	var mx: float = maxf(1.0, float(obj.get(&"max_hp")))
	return clampf(cur / mx, 0.0, 1.0)

func _get_pos(obj: Object) -> Vector3:
	if obj is Node3D:
		var n := obj as Node3D
		return n.global_position if n.is_inside_tree() else n.position
	return Vector3.ZERO
