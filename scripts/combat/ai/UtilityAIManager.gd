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
	var compliance_mult: float = 1.0 + clampf(float(maxi(1, bond_level)) * 0.005, 0.0, 0.5)
	var unit_role: int = StudentData.CombatRole.DAMAGE_DEALER
	var udata: Variant = unit.get(&"unit_data")
	var student_id: String = str(unit.name) if unit is Node else ""
	if udata != null and udata is StudentData:
		unit_role = (udata as StudentData).role
		if not (udata as StudentData).id.is_empty():
			student_id = (udata as StudentData).id
	var holding_fire: bool = bool(unit.get(&"is_holding_fire")) if (&"is_holding_fire" in unit) else false

	# Resolve per-unit zone & target assignments (behavior driven purely by unit's own zone)
	var unit_zone: Dictionary = {}
	if directives != null:
		if directives.has_method(&"get_zone_for_unit") and not student_id.is_empty():
			unit_zone = directives.get_zone_for_unit(student_id)
		elif bool(directives.get("has_tactical_zone")):
			var legacy_stance: int = int(directives.get("current_stance")) if (&"current_stance" in directives) else STANCE_BALANCED
			unit_zone = {
				"id": 0,
				"type": "DEFENSE" if legacy_stance == STANCE_DEFENSIVE else "ASSAULT",
				"center": directives.get("tactical_zone_center"),
				"radius": float(directives.get("tactical_zone_radius")),
			}
	var unit_zone_type: String = str(unit_zone.get("type", ""))

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
	var retreat_thresh: float = 0.50 if unit_zone_type == "DEFENSE" else 0.32
	if hp_ratio < retreat_thresh and not enemies.is_empty():
		var retreat_pos: Vector3 = _find_retreat_position(unit, unit_pos, allies, enemies, covers)
		var retreat_score: float = 95.0 if unit_zone_type == "DEFENSE" else 85.0
		if retreat_score > float(best["score"]):
			best = {
				"action": "SURVIVAL_RETREAT",
				"target": null,
				"target_pos": retreat_pos,
				"score": retreat_score,
				"status_tag": "🛡️ RÚT LUI",
			}

	var living_enemies: Array = []
	for e in enemies:
		if e != null and is_instance_valid(e) and _is_alive(e):
			living_enemies.append(e)
	var los_cache: Dictionary = {}

	# 4. Per-unit Tactical Zone directives (ASSAULT, DEFENSE, FREESHOT) with entry hysteresis
	var prio_target: Object = null
	if directives != null:
		if directives.has_method(&"get_target_for_unit") and not student_id.is_empty():
			prio_target = directives.get_target_for_unit(student_id)
		elif directives.has_method(&"get_valid_priority_target"):
			prio_target = directives.get_valid_priority_target()
	var valid_prio: Object = prio_target if (prio_target != null and is_instance_valid(prio_target) and _is_alive(prio_target)) else null

	var in_defense_lock: bool = false
	if not unit_zone.is_empty():
		var zone_id: int = int(unit_zone.get("id", 0))
		var zone_type: String = str(unit_zone.get("type", "ASSAULT"))
		var zone_center: Vector3 = unit_zone.get("center", Vector3.ZERO)
		var zone_rad: float = maxf(2.5, float(unit_zone.get("radius", 6.5)))
		var dist_to_zone: float = Vector2(unit_pos.x, unit_pos.z).distance_to(Vector2(zone_center.x, zone_center.z))
		var inner_anchor: Vector3 = _get_zone_inner_anchor(unit, unit_pos, allies, zone_center, zone_rad, covers, zone_type)

		if zone_type == "FREESHOT":
			var freeshot_enemy: Object = _pick_enemy_in_zone(zone_center, zone_rad, living_enemies, valid_prio)
			var freeshot_score: float = 80.0 * compliance_mult
			if freeshot_score > float(best["score"]):
				best = {
					"action": "FREESHOT_BOMBARD",
					"target": freeshot_enemy,
					"target_pos": zone_center,
					"zone_radius": zone_rad,
					"score": freeshot_score,
					"status_tag": "💣 BẮN PHÁ VÙNG",
				}
		elif zone_type == "DEFENSE":
			in_defense_lock = true
			var z_meta := StringName("_in_zone_%d" % zone_id)
			var was_inside: bool = unit.has_meta(z_meta) and bool(unit.get_meta(z_meta))
			if was_inside and dist_to_zone > zone_rad * 0.90:
				was_inside = false
				unit.set_meta(z_meta, false)
			elif not was_inside and dist_to_zone <= zone_rad * 0.65:
				was_inside = true
				unit.set_meta(z_meta, true)

			if not was_inside:
				var def_advance_score: float = 82.0 * compliance_mult
				if def_advance_score > float(best["score"]):
					best = {
						"action": "ADVANCE_TO_ZONE",
						"target": null,
						"target_pos": inner_anchor,
						"score": def_advance_score,
						"status_tag": "🛡️ VÀO VÙNG PHÒNG THỦ",
					}
			else:
				var def_enemy: Object = valid_prio if valid_prio != null else _pick_best_enemy(unit, unit_pos, living_enemies, room_info, los_cache) if not living_enemies.is_empty() else null
				var def_score: float = 76.0 * compliance_mult
				if def_enemy != null and def_score > float(best["score"]):
					best = {
						"action": "DEFEND_ZONE_ENGAGE",
						"target": def_enemy,
						"target_pos": inner_anchor,
						"zone_center": zone_center,
						"zone_radius": zone_rad,
						"score": def_score,
						"status_tag": "🛡️ PHÒNG THỦ & BẮN",
					}
				elif 64.0 > float(best["score"]):
					best = {
						"action": "HOLD_DEFENSE_ZONE",
						"target": null,
						"target_pos": inner_anchor,
						"score": 64.0,
						"status_tag": "🛡️ GIỮ VỊ TRÍ",
					}
		else:
			# ASSAULT zone: guide unit deep inside once; once cleared entry, allow free pursuit out
			var z_meta := StringName("_in_zone_%d" % zone_id)
			var reached_assault: bool = unit.has_meta(z_meta) and bool(unit.get_meta(z_meta))
			if not reached_assault and dist_to_zone <= zone_rad * 0.65:
				reached_assault = true
				unit.set_meta(z_meta, true)
			if not reached_assault and dist_to_zone > zone_rad * 0.65:
				var zone_score: float = 70.0 * compliance_mult
				if zone_score > float(best["score"]):
					best = {
						"action": "ADVANCE_TO_ZONE",
						"target": null,
						"target_pos": inner_anchor,
						"score": zone_score,
						"status_tag": "🚩 TIẾN VÀO VÙNG",
					}

	# 4b. Per-unit Advance Vector (Attack-Move: march toward destination while firing at enemies in range & LOS)
	var adv_target_var: Variant = null
	if directives != null:
		if directives.has_method(&"get_advance_target_for_unit") and not student_id.is_empty():
			adv_target_var = directives.get_advance_target_for_unit(student_id)
		elif bool(directives.get("has_advance_vector")):
			adv_target_var = directives.get("advance_target")
	if adv_target_var is Vector3:
		var adv_dest: Vector3 = adv_target_var as Vector3
		var dist_adv: float = Vector2(unit_pos.x, unit_pos.z).distance_to(Vector2(adv_dest.x, adv_dest.z))
		if dist_adv <= 1.2:
			if directives != null and directives.has_method(&"clear_advance_target_for_unit") and not student_id.is_empty():
				directives.clear_advance_target_for_unit(student_id)
		else:
			var adv_anchor: Vector3 = _get_zone_inner_anchor(unit, unit_pos, allies, adv_dest, 2.8, [], "ASSAULT")
			var atk_range_adv: float = maxf(6.0, float(unit.get(&"attack_range")) if (&"attack_range" in unit) else 10.0)
			var pen_adv: int = int(unit.get(&"penetration_power")) if (&"penetration_power" in unit) else 0
			var engage_on_march: Object = null
			if valid_prio != null:
				var p_pos: Vector3 = _get_pos(valid_prio)
				if Vector2(unit_pos.x, unit_pos.z).distance_to(Vector2(p_pos.x, p_pos.z)) <= atk_range_adv + 1.0 and _check_los(unit_pos, p_pos, room_info, pen_adv):
					engage_on_march = valid_prio
			if engage_on_march == null:
				var best_march_d: float = INF
				for enemy in living_enemies:
					var e_pos: Vector3 = _get_pos(enemy)
					var d_e: float = Vector2(unit_pos.x, unit_pos.z).distance_to(Vector2(e_pos.x, e_pos.z))
					if d_e <= atk_range_adv + 1.0 and d_e < best_march_d and _check_los(unit_pos, e_pos, room_info, pen_adv):
						best_march_d = d_e
						engage_on_march = enemy
			var adv_score: float = 73.0 * compliance_mult
			if adv_score > float(best["score"]):
				best = {
					"action": "ADVANCE_ENGAGE",
					"target": engage_on_march,
					"target_pos": adv_anchor,
					"score": adv_score,
					"status_tag": "⚔️ TIẾN CÔNG" if engage_on_march != null else "➔ TIẾN QUÂN",
				}

	# 5. Commander Priority Target directive (skipped when locked inside Defense perimeter so unit won't chase outside)
	if not in_defense_lock and valid_prio != null:
		var prio_score: float = 68.0 * compliance_mult
		if unit_zone_type == "ASSAULT":
			prio_score += 15.0
		if prio_score > float(best["score"]):
			best = {
				"action": "FOCUS_PRIORITY_TARGET",
				"target": valid_prio,
				"target_pos": _get_pos(valid_prio),
				"score": prio_score,
				"status_tag": "🎯 MỤC TIÊU CHỈ ĐỊNH",
			}

	# 6. Seek nearby CoverPoint3D & engage visible enemy
	if not living_enemies.is_empty() and not in_defense_lock:
		var cover_pick: Variant = _find_best_cover(unit, unit_pos, covers, directives, living_enemies, room_info, unit_zone)
		if cover_pick != null:
			var cover_score: float = 46.0
			if unit_zone_type == "ASSAULT":
				cover_score -= 12.0
			if unit_role == StudentData.CombatRole.TANKER:
				cover_score += 12.0
			if cover_score > float(best["score"]):
				var vis_enemy: Object = _pick_best_enemy(unit, unit_pos, living_enemies, room_info, los_cache)
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
			var eid: int = enemy.get_instance_id()
			var clear_los: bool
			if los_cache.has(eid):
				clear_los = bool(los_cache[eid])
			else:
				clear_los = _check_los(unit_pos, e_pos, room_info, pen)
				los_cache[eid] = clear_los
			var candidate_score: float = 36.0 - dist * 0.5 + (1.0 - e_hp) * 14.0
			if clear_los:
				candidate_score += 12.0
			if unit_zone_type == "ASSAULT":
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

	if holding_fire:
		var base_tag: String = str(best.get("status_tag", ""))
		best["holding_fire"] = true
		best["status_tag"] = "🚫 GIỮ HỎA LỰC" if base_tag.is_empty() else "🚫 %s" % base_tag

	return best

func _pick_best_enemy(unit: Object, unit_pos: Vector3, living_enemies: Array, room_info: Object, los_cache: Dictionary = {}) -> Object:
	var pen: int = int(unit.get(&"penetration_power")) if (&"penetration_power" in unit) else 0
	var chosen: Object = living_enemies[0]
	var chosen_score: float = -INF
	for enemy in living_enemies:
		var e_pos: Vector3 = _get_pos(enemy)
		var dist: float = Vector2(unit_pos.x, unit_pos.z).distance_to(Vector2(e_pos.x, e_pos.z))
		var eid: int = enemy.get_instance_id()
		var has_los: bool
		if los_cache.has(eid):
			has_los = bool(los_cache[eid])
		else:
			has_los = _check_los(unit_pos, e_pos, room_info, pen)
			los_cache[eid] = has_los
		var sc: float = -dist + (15.0 if has_los else 0.0)
		if sc > chosen_score:
			chosen_score = sc
			chosen = enemy
	return chosen

func _get_zone_inner_anchor(unit: Object, unit_pos: Vector3, allies: Array, zone_center: Vector3, zone_rad: float, covers: Array, zone_type: String) -> Vector3:
	if zone_type == "DEFENSE":
		var best_cover: Variant = null
		var best_d: float = INF
		for cp in covers:
			if cp == null or not is_instance_valid(cp):
				continue
			var occ: Variant = cp.get(&"occupant")
			if bool(cp.get(&"is_occupied")) and occ != unit and occ != null and is_instance_valid(occ) and _is_alive(occ):
				continue
			var cp_pos: Vector3 = _get_pos(cp)
			if Vector2(cp_pos.x, cp_pos.z).distance_to(Vector2(zone_center.x, zone_center.z)) <= zone_rad * 0.72:
				var d: float = Vector2(unit_pos.x, unit_pos.z).distance_to(Vector2(cp_pos.x, cp_pos.z))
				if d < best_d:
					best_d = d
					best_cover = cp
		if best_cover != null:
			return _get_pos(best_cover)

	var slot_idx: int = allies.find(unit)
	if slot_idx < 0:
		slot_idx = abs(unit.get_instance_id()) % 4
	var angle: float = (PI * 0.25) + float(slot_idx % 4) * (TAU / 4.0)
	var offset_len: float = clampf(zone_rad * 0.42, 1.4, 2.8)
	return Vector3(zone_center.x + cos(angle) * offset_len, unit_pos.y, zone_center.z + sin(angle) * offset_len)

func _pick_enemy_in_zone(zone_center: Vector3, zone_rad: float, living_enemies: Array, prio_target: Object) -> Object:
	if prio_target != null and is_instance_valid(prio_target) and _is_alive(prio_target):
		var p_pos: Vector3 = _get_pos(prio_target)
		if Vector2(p_pos.x, p_pos.z).distance_to(Vector2(zone_center.x, zone_center.z)) <= zone_rad + 2.0:
			return prio_target
	var best_e: Object = null
	var best_d: float = INF
	for e in living_enemies:
		var e_pos: Vector3 = _get_pos(e)
		var d: float = Vector2(e_pos.x, e_pos.z).distance_to(Vector2(zone_center.x, zone_center.z))
		if d <= zone_rad + 1.5 and d < best_d:
			best_d = d
			best_e = e
	return best_e

func _find_best_cover(unit: Object, unit_pos: Vector3, covers: Array, _directives: Object, living_enemies: Array = [], room_info: Object = null, unit_zone: Dictionary = {}) -> Variant:
	var best_cp: Variant = null
	var best_score: float = -INF
	var has_zone: bool = not unit_zone.is_empty()
	var zone_type: String = str(unit_zone.get("type", ""))
	var zone_center: Vector3 = unit_zone.get("center", Vector3.ZERO) if has_zone else Vector3.ZERO
	var zone_rad: float = float(unit_zone.get("radius", 999.0)) if has_zone else 999.0
	var pen: int = int(unit.get(&"penetration_power")) if (&"penetration_power" in unit) else 0
	var atk_range: float = maxf(6.0, float(unit.get(&"attack_range")) if (&"attack_range" in unit) else 10.0)

	for cp in covers:
		if cp == null or not is_instance_valid(cp):
			continue
		var occ: Variant = cp.get(&"occupant")
		if bool(cp.get(&"is_occupied")) and occ != unit and occ != null and is_instance_valid(occ) and _is_alive(occ):
			continue
		var cp_pos: Vector3 = _get_pos(cp)
		if absf(cp_pos.x - unit_pos.x) > 14.0 or absf(cp_pos.z - unit_pos.z) > 14.0:
			continue
		var d: float = Vector2(unit_pos.x, unit_pos.z).distance_to(Vector2(cp_pos.x, cp_pos.z))
		if d > 14.0:
			continue
		if has_zone and Vector2(cp_pos.x, cp_pos.z).distance_to(Vector2(zone_center.x, zone_center.z)) > zone_rad + 1.5:
			continue

		# Skip blind covers unless holding a DEFENSE zone
		var can_engage_from_cover: bool = false
		for enemy in living_enemies:
			var e_pos: Vector3 = _get_pos(enemy)
			if Vector2(cp_pos.x, cp_pos.z).distance_to(Vector2(e_pos.x, e_pos.z)) <= atk_range + 2.0:
				if _check_los(cp_pos, e_pos, room_info, pen):
					can_engage_from_cover = true
					break
		if not can_engage_from_cover and zone_type != "DEFENSE":
			continue

		var sc: float = 20.0 - d
		if occ == unit:
			sc += 6.0
		if str(unit.get(&"weapon_class")) == "SR" and room_info != null and is_instance_valid(room_info) and room_info.has_method(&"get_terrain_modifiers_at"):
			var cp_mods: Dictionary = room_info.get_terrain_modifiers_at(cp_pos)
			if float(cp_mods.get("range_bonus_multiplier", 1.0)) > 1.0:
				sc += 10.0
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
		if n.is_inside_tree():
			return n.global_position
		var xform: Transform3D = n.transform
		var p: Node = n.get_parent()
		while p != null:
			if p is Node3D:
				xform = (p as Node3D).transform * xform
			p = p.get_parent()
		return xform.origin
	return Vector3.ZERO
