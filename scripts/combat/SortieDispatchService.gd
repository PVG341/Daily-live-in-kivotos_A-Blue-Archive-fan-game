# scripts/combat/SortieDispatchService.gd
class_name SortieDispatchService
extends RefCounted

const ProgressionManagerScript := preload("res://scripts/core/ProgressionManager.gd")

const MISSION_CATALOG: Array[Dictionary] = [
	{
		"id": "schale_patrol_normal",
		"title": "Tuần tra Schale (Thường)",
		"mode": "DUNGEON",
		"difficulty": 1,
		"ap_cost": 20,
		"room_count": 4,
		"reward_credits": 1200,
		"reward_card_id": "tactical_overdrive",
		"description": "4 phân khu liên hoàn & Boss Hieronymus. Chi phí 20 AP.",
	},
	{
		"id": "kivotos_sweep_hard",
		"title": "Quét sạch Kivotos (Khó)",
		"mode": "DUNGEON",
		"difficulty": 2,
		"ap_cost": 30,
		"room_count": 4,
		"reward_credits": 2200,
		"reward_card_id": "armor_shredder",
		"description": "Địch tăng giáp & sát thương, tỷ lệ rớt quà cao. Chi phí 30 AP.",
	},
	{
		"id": "abyss_assault_extreme",
		"title": "Tổng lực Abyss (Cực Khó)",
		"mode": "DUNGEON",
		"difficulty": 3,
		"ap_cost": 40,
		"room_count": 4,
		"reward_credits": 3600,
		"reward_card_id": "shittim_blessing",
		"description": "Chiến dịch khốc liệt nhất trước Total Assault (Binah/Hod sau Mốc 4-5). Chi phí 40 AP.",
	},
]

const DEFAULT_STRIKERS: Array[Dictionary] = [
	{"id": "hoshino", "name": "Hoshino", "role": "TANKER", "weapon_class": "SG", "is_mod": false},
	{"id": "shiroko", "name": "Shiroko", "role": "DAMAGE_DEALER", "weapon_class": "SR", "is_mod": false},
	{"id": "serika", "name": "Serika", "role": "DAMAGE_DEALER", "weapon_class": "ARTILLERY", "is_mod": false},
	{"id": "hanae", "name": "Hanae", "role": "HEALER", "weapon_class": "HG", "is_mod": false},
]

const DEFAULT_SPECIALS: Array[Dictionary] = [
	{"id": "hibiki", "name": "Hibiki", "role": "DAMAGE_DEALER", "skill": "Missile Barrage (3)", "is_mod": false},
	{"id": "serina", "name": "Serina", "role": "HEALER", "skill": "Team Heal (4)", "is_mod": false},
]

## Returns all mission definitions in the sortie catalog.
func get_mission_catalog() -> Array[Dictionary]:
	return MISSION_CATALOG.duplicate(true)

## Looks up a mission dictionary by ID, or returns an empty Dictionary.
func get_mission_by_id(mission_id: String) -> Dictionary:
	for entry in MISSION_CATALOG:
		if str(entry.get("id", "")) == mission_id:
			return entry.duplicate(true)
	return {}

## Returns available Striker candidates combining built-in students and loaded ModLoader students.
func get_available_strikers(mod_loader: Node = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = DEFAULT_STRIKERS.duplicate(true)
	_append_mod_candidates(out, mod_loader, StudentData.SquadSlot.STRIKER)
	return out

## Returns available Special support candidates combining built-in students and loaded ModLoader students.
func get_available_specials(mod_loader: Node = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = DEFAULT_SPECIALS.duplicate(true)
	_append_mod_candidates(out, mod_loader, StudentData.SquadSlot.SPECIAL)
	return out

func _append_mod_candidates(out: Array[Dictionary], mod_loader: Node, target_slot: int) -> void:
	if mod_loader == null or not is_instance_valid(mod_loader) or not (&"loaded_students" in mod_loader):
		return
	var loaded_val: Variant = mod_loader.get(&"loaded_students")
	if not (loaded_val is Dictionary):
		return
	var seen_ids: Dictionary = {}
	for existing in out:
		seen_ids[str(existing.get("id", "")).to_lower()] = true
	var loaded_dict := loaded_val as Dictionary
	var keys: Array = loaded_dict.keys()
	keys.sort()
	for k in keys:
		var sd: Variant = loaded_dict[k]
		if not (sd is StudentData):
			continue
		var student := sd as StudentData
		if student.id.is_empty() or seen_ids.has(student.id.to_lower()):
			continue
		if student.squad_slot != target_slot:
			continue
		seen_ids[student.id.to_lower()] = true
		var role_name: String = "DAMAGE_DEALER"
		var wclass: String = "AR"
		match student.role:
			StudentData.CombatRole.TANKER:
				role_name = "TANKER"
				wclass = "SG"
			StudentData.CombatRole.HEALER:
				role_name = "HEALER"
				wclass = "HG"
			StudentData.CombatRole.BUFFER:
				role_name = "BUFFER"
				wclass = "HG"
			_:
				wclass = "SR" if student.attack_range >= 14.0 else "AR"
		var skill_label: String = "Mod Skill"
		if not student.skills.is_empty() and student.skills[0] != null:
			skill_label = student.skills[0].name
		out.append({
			"id": student.id,
			"name": student.student_name if not student.student_name.is_empty() else student.id,
			"role": role_name,
			"weapon_class": wclass,
			"skill": skill_label,
			"is_mod": true,
		})

## Validates mission, modifiers, squad, and AP before handing off pending combat config and changing scenes.
func validate_and_launch_sortie(
	mission_id: String,
	striker_ids: Array[String],
	special_ids: Array[String],
	challenge_modifiers: Array[String],
	day_cycle: Node,
	transition_mgr: Node,
	return_scene: String = "res://scenes/hub/zones/schale_building.tscn",
	perform_transition: bool = true
) -> Dictionary:
	var mission: Dictionary = get_mission_by_id(mission_id)
	if mission.is_empty():
		return {"ok": false, "config": {}, "error": "Không tìm thấy nhiệm vụ: %s" % mission_id}

	var valid_mods: Array[String] = []
	for mod_raw in challenge_modifiers:
		var mid: String = str(mod_raw).strip_edges()
		if ProgressionManagerScript.CHALLENGE_MODIFIER_WEIGHTS.has(mid) and not valid_mods.has(mid):
			valid_mods.append(mid)

	var final_strikers: Array[String] = []
	for sid_raw in striker_ids:
		var sid: String = str(sid_raw).strip_edges()
		if not sid.is_empty() and not final_strikers.has(sid):
			final_strikers.append(sid)
		if final_strikers.size() >= 4:
			break
	if final_strikers.is_empty():
		for d in DEFAULT_STRIKERS:
			final_strikers.append(str(d["id"]))

	var final_specials: Array[String] = []
	for sp_raw in special_ids:
		var sp_id: String = str(sp_raw).strip_edges()
		if not sp_id.is_empty() and not final_specials.has(sp_id):
			final_specials.append(sp_id)
		if final_specials.size() >= 2:
			break
	if final_specials.is_empty():
		for d in DEFAULT_SPECIALS:
			final_specials.append(str(d["id"]))

	var ap_cost: int = int(mission.get("ap_cost", 20))
	if day_cycle != null and is_instance_valid(day_cycle) and day_cycle.has_method(&"consume_ap"):
		if not bool(day_cycle.call(&"consume_ap", ap_cost)):
			var cur_ap: int = int(day_cycle.get(&"current_ap")) if &"current_ap" in day_cycle else 0
			return {
				"ok": false,
				"config": {},
				"error": "Không đủ AP! Cần %d AP (hiện có %d AP)." % [ap_cost, cur_ap],
			}

	var eff_return: String = return_scene if not return_scene.is_empty() else "res://scenes/hub/zones/schale_building.tscn"
	var cfg: Dictionary = {
		"mission_id": str(mission["id"]),
		"mission_title": str(mission["title"]),
		"mode": str(mission.get("mode", "DUNGEON")),
		"difficulty": int(mission.get("difficulty", 1)),
		"ap_cost": ap_cost,
		"room_count": int(mission.get("room_count", 4)),
		"reward_credits": int(mission.get("reward_credits", 1000)),
		"reward_card_id": str(mission.get("reward_card_id", "")),
		"challenge_modifiers": valid_mods,
		"striker_ids": final_strikers,
		"special_ids": final_specials,
		"return_scene": eff_return,
		"return_spawn": "office_desk",
		"launched_from_hub": true,
	}

	if transition_mgr != null and is_instance_valid(transition_mgr):
		if transition_mgr.has_method(&"set_pending_combat_config"):
			transition_mgr.call(&"set_pending_combat_config", cfg)
		if perform_transition and transition_mgr.has_method(&"transition_to"):
			transition_mgr.call(&"transition_to", "res://scenes/combat/combat_arena.tscn", "combat_start")

	return {"ok": true, "config": cfg, "error": ""}
