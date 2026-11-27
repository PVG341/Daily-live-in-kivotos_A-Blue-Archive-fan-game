# tests/test_phase3a_sortie_loop.gd
extends SceneTree

const SortieDispatchServiceScript := preload("res://scripts/combat/SortieDispatchService.gd")

var _failed: bool = false
var _completed: bool = false
var _ran: bool = false

func check(cond: bool, msg: String) -> bool:
	if not cond:
		printerr("FAIL: " + msg)
		_failed = true
		quit(1)
		return false
	return true

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run_tests()

	if _failed or not _completed:
		quit(1)
		return true

	print("PASS: test_phase3a_sortie_loop")
	quit(0)
	return true

func _run_tests() -> void:
	var dcm: Node = root.get_node_or_null("DayCycleManager")
	var save_mgr: Node = root.get_node_or_null("SaveManager")
	var mod_loader: Node = root.get_node_or_null("ModLoader")
	var ztm: Node = root.get_node_or_null("ZoneTransitionManager")
	if not check(dcm != null and save_mgr != null and mod_loader != null and ztm != null, "Required autoloads must be present"):
		return

	# Snapshot autoload state so test leaves singletons pristine
	var orig_ap: int = int(dcm.get("current_ap"))
	var orig_max_ap: int = int(dcm.get("max_ap"))
	var orig_hour: float = float(dcm.get("current_hour"))
	var orig_day: int = int(dcm.get("current_day"))
	var orig_credits: int = int(save_mgr.get("credits"))
	var orig_inv: Array = (save_mgr.get("inventory") as Array).duplicate(true)
	var orig_cards: Array = (save_mgr.get("unlocked_roguelike_cards") as Array).duplicate()
	var orig_variants: Dictionary = (save_mgr.get("unlocked_skill_variants") as Dictionary).duplicate(true)
	var orig_quests: Dictionary = (save_mgr.get("completed_quests") as Dictionary).duplicate(true)
	var orig_qprog: Dictionary = (save_mgr.get("quest_progress") as Dictionary).duplicate(true)
	var orig_summary: Dictionary = (save_mgr.get("last_combat_summary") as Dictionary).duplicate(true)
	var orig_pending: Dictionary = (ztm.get("pending_combat_config") as Dictionary).duplicate(true)

	# 1. Hub MissionTerminal auto-attached on SenseiDesk opens PhoneOS MISSIONS tab
	var building_packed := load("res://scenes/hub/zones/schale_building.tscn") as PackedScene
	if not check(building_packed != null, "schale_building.tscn must load cleanly"):
		return
	var building := building_packed.instantiate()
	root.add_child(building)
	check(building.mission_terminal != null, "HubSceneController must attach MissionTerminal to SenseiDesk")
	if building.mission_terminal != null:
		check(building.mission_terminal.get_interaction_type() == "MISSION_TERMINAL", "MissionTerminal interaction type must be MISSION_TERMINAL")
		building.mission_terminal.interact()
		check(building.phone_os != null and building.phone_os.is_open == true and building.phone_os.active_tab == "MISSIONS", "Activating MissionTerminal must open PhoneOS to MISSIONS tab")
	root.remove_child(building)
	building.free()

	# 2. SortieDispatchService roster (built-ins + ModLoader) and AP validation/consumption
	var mod_sk_st := SkillData.new()
	mod_sk_st.id = "ex_mod_arona_beam"
	mod_sk_st.name = "Arona Beam (2)"
	mod_sk_st.cost = 2
	mod_sk_st.cooldown = 5.0
	mod_sk_st.aoe_radius = 4.0
	mod_sk_st.cast_range = 18.0
	mod_sk_st.aoe_shape = "CIRCLE"
	mod_sk_st.effect_type = "DAMAGE"

	var mod_striker := StudentData.new()
	mod_striker.id = "mod_arona_striker"
	mod_striker.student_name = "Arona Mod"
	mod_striker.role = StudentData.CombatRole.DAMAGE_DEALER
	mod_striker.squad_slot = StudentData.SquadSlot.STRIKER
	mod_striker.base_hp = 1350
	mod_striker.base_atk = 210
	mod_striker.base_def = 50
	mod_striker.base_speed = 5.0
	mod_striker.attack_range = 15.0
	mod_striker.skills = [mod_sk_st]

	var mod_sk_sp := SkillData.new()
	mod_sk_sp.id = "ex_mod_plana_heal"
	mod_sk_sp.name = "Plana Shield (3)"
	mod_sk_sp.cost = 3
	mod_sk_sp.cooldown = 6.0
	mod_sk_sp.aoe_radius = 5.0
	mod_sk_sp.cast_range = 18.0
	mod_sk_sp.aoe_shape = "CIRCLE"
	mod_sk_sp.effect_type = "HEAL"
	mod_sk_sp.caster_name = "Plana Mod"

	var mod_special := StudentData.new()
	mod_special.id = "mod_plana_special"
	mod_special.student_name = "Plana Mod"
	mod_special.role = StudentData.CombatRole.HEALER
	mod_special.squad_slot = StudentData.SquadSlot.SPECIAL
	mod_special.skills = [mod_sk_sp]

	mod_loader.loaded_students["mod_arona_striker"] = mod_striker
	mod_loader.loaded_students["mod_plana_special"] = mod_special

	var sortie_svc := SortieDispatchServiceScript.new()
	var strikers_avail := sortie_svc.get_available_strikers(mod_loader)
	var specials_avail := sortie_svc.get_available_specials(mod_loader)
	var found_mod_st: bool = false
	for item in strikers_avail:
		if str(item.get("id", "")) == "mod_arona_striker" and bool(item.get("is_mod", false)):
			found_mod_st = true
	var found_mod_sp: bool = false
	for item in specials_avail:
		if str(item.get("id", "")) == "mod_plana_special" and bool(item.get("is_mod", false)):
			found_mod_sp = true
	check(found_mod_st, "SortieDispatchService must expose modded Striker from ModLoader")
	check(found_mod_sp, "SortieDispatchService must expose modded Special from ModLoader")

	# Insufficient AP guard
	dcm.current_ap = 15
	var fail_res: Dictionary = sortie_svc.validate_and_launch_sortie(
		"kivotos_sweep_hard",
		["hoshino", "shiroko", "mod_arona_striker", "hanae"],
		["hibiki", "mod_plana_special"],
		["ENEMY_SPEED_UP", "NO_REST_ROOMS", "DOUBLE_BOSS_PHASE"],
		dcm,
		ztm,
		"res://scenes/hub/zones/schale_building.tscn",
		false
	)
	check(bool(fail_res.get("ok", true)) == false and int(dcm.current_ap) == 15, "Sortie launch must fail without deducting AP when AP < mission ap_cost")

	# Valid launch consumes AP and stores pending combat config
	dcm.current_ap = 100
	var ok_res: Dictionary = sortie_svc.validate_and_launch_sortie(
		"kivotos_sweep_hard",
		["hoshino", "shiroko", "mod_arona_striker", "hanae"],
		["hibiki", "mod_plana_special"],
		["ENEMY_SPEED_UP", "NO_REST_ROOMS", "DOUBLE_BOSS_PHASE"],
		dcm,
		ztm,
		"res://scenes/hub/zones/schale_building.tscn",
		false
	)
	check(bool(ok_res.get("ok", false)) == true and int(dcm.current_ap) == 70, "Valid hard sortie launch (30 AP) must deduct AP from 100 to 70")
	check(str(ztm.pending_combat_config.get("mission_id", "")) == "kivotos_sweep_hard", "ZoneTransitionManager must store pending_combat_config")

	# 3. CombatArenaController consumes pending_combat_config, spawns modded units, enforces challenge modifiers
	var arena_packed := load("res://scenes/combat/combat_arena.tscn") as PackedScene
	if not check(arena_packed != null, "combat_arena.tscn must load cleanly"):
		return
	var arena := arena_packed.instantiate()
	root.add_child(arena)

	check(ztm.pending_combat_config.is_empty(), "CombatArenaController._ready() must consume pending_combat_config")
	check(arena.squad_units.size() == 4, "Arena must spawn 4 selected Strikers")
	var has_mod_striker: bool = false
	for su in arena.squad_units:
		if su.unit_data != null and su.unit_data.id == "mod_arona_striker":
			has_mod_striker = true
	var has_mod_special: bool = false
	for sp in arena.special_students:
		if sp != null and sp.id == "mod_plana_special":
			has_mod_special = true
	check(has_mod_striker, "Arena must spawn modded Striker 'mod_arona_striker' from Sortie config")
	check(has_mod_special, "Arena must register modded Special 'mod_plana_special' from Sortie config")

	var has_rest_room: bool = false
	for room_def in arena.room_manager.layout:
		if str(room_def.get("room_type", "")) == "REST":
			has_rest_room = true
	check(not has_rest_room, "NO_REST_ROOMS challenge modifier must prevent REST sectors from spawning")

	var any_fast_enemy: bool = false
	for eu in arena.enemy_units:
		if eu.is_alive and eu.speed >= 4.0:
			any_fast_enemy = true
	check(any_fast_enemy, "ENEMY_SPEED_UP challenge modifier must increase spawned enemy movement speed")

	# 4a. Random Event 1: ALLY_ARTILLERY telegraph & detonation
	for su in arena.squad_units:
		su.set_hold_fire(true)
	var art_target = null
	for eu in arena.enemy_units:
		if eu.is_alive:
			art_target = eu
			break
	if check(art_target != null, "Arena must have living enemy to test ALLY_ARTILLERY"):
		arena._resolve_random_event({"type": "ALLY_ARTILLERY"})
		check(arena._active_artillery_strikes.size() == 1, "ALLY_ARTILLERY must spawn 1 active telegraphed strike")
		var strike_pos: Vector3 = arena._active_artillery_strikes[0].get("pos", Vector3.ZERO)
		art_target.position = strike_pos
		var orig_art_spd: float = art_target.speed
		art_target.speed = 0.0
		var hp_before_art: int = art_target.current_hp
		arena.step_combat(2.2)
		art_target.speed = orig_art_spd
		check(art_target.current_hp < hp_before_art, "Detonated ALLY_ARTILLERY strike must damage enemy inside radius")
		check(arena._active_artillery_strikes.is_empty(), "Detonated ALLY_ARTILLERY strike disc must be freed cleanly")
	for su in arena.squad_units:
		su.set_hold_fire(false)

	# 4b. Random Event 2: HIDDEN_BOSS spawn + rare loot collection
	var alive_before_hb: int = arena.wave_spawner.alive_enemies
	arena._resolve_random_event({"type": "HIDDEN_BOSS"})
	check(arena.wave_spawner.alive_enemies == alive_before_hb + 1, "HIDDEN_BOSS must increment WaveSpawner alive_enemies by 1")
	var hb_unit = null
	for eu in arena.enemy_units:
		if eu.is_alive and eu.enemy_type == "HIDDEN_BOSS":
			hb_unit = eu
			break
	check(hb_unit != null, "HIDDEN_BOSS event must spawn EnemyUnit with enemy_type == 'HIDDEN_BOSS'")
	if hb_unit != null:
		hb_unit.take_damage(99999)
		check(arena.run_bosses_killed >= 1, "Killing HIDDEN_BOSS must increment run_bosses_killed")
		check(arena.run_collected_loot.has("boss_core_fragment"), "Killing HIDDEN_BOSS must collect rare loot 'boss_core_fragment'")

	# 4c. Random Event 3: THIRD_PARTY cross-faction targeting
	arena._resolve_random_event({"type": "THIRD_PARTY"})
	check(arena._third_party_units.size() == 2, "THIRD_PARTY event must spawn 2 mercenary skirmishers")
	if not arena._third_party_units.is_empty():
		var tp0 = arena._third_party_units[0]
		var mixed_targets: Array = arena._get_targets_for_enemy(tp0, arena._get_living_strikers())
		var has_striker_target: bool = false
		var has_enemy_target: bool = false
		for mt in mixed_targets:
			if mt in arena.squad_units:
				has_striker_target = true
			elif mt is EnemyUnit and (mt as EnemyUnit).enemy_type != "THIRD_PARTY":
				has_enemy_target = true
		check(has_striker_target and has_enemy_target, "THIRD_PARTY units must target both Strikers and non-THIRD_PARTY enemies")

	# 5. Reward Payout & Idempotency (_finish_run)
	var credits_before: int = int(save_mgr.credits)
	var hour_before: float = float(dcm.current_hour)
	arena._finish_run(true)
	check(arena.run_credits_earned > 0, "_finish_run(true) must compute positive run_credits_earned")
	check(int(save_mgr.credits) == credits_before + arena.run_credits_earned, "_finish_run(true) must add credits to SaveManager")
	check(save_mgr.unlocked_roguelike_cards.has("armor_shredder"), "Victory must unlock mission card 'armor_shredder' in SaveManager")
	check(save_mgr.unlocked_roguelike_cards.has("schale_tactical_focus"), "Victory must auto-complete CLEAR_DUNGEON quest card 'schale_tactical_focus'")
	check(save_mgr.completed_quests.has("quest_clear_patrol_1"), "SaveManager must record completed quest 'quest_clear_patrol_1'")
	var has_boss_core_inv: bool = false
	var has_ration_inv: bool = false
	for inv_e in save_mgr.inventory:
		if inv_e is Dictionary:
			if str(inv_e.get("id", "")) == "boss_core_fragment":
				has_boss_core_inv = true
			elif str(inv_e.get("id", "")) == "schale_ration_pack":
				has_ration_inv = true
	check(has_boss_core_inv and has_ration_inv, "Victory must store collected & guaranteed loot items into SaveManager.inventory")
	check(not is_equal_approx(float(dcm.current_hour), hour_before), "Dungeon run launched from Hub must advance DayCycleManager time")
	var reward_lbl := arena.result_panel.find_child("RewardSummaryLabel", true, false) as Label
	check(reward_lbl != null and reward_lbl.text.contains("Credits"), "ResultPanel RewardSummaryLabel must display reward summary")

	var credits_after_first: int = int(save_mgr.credits)
	arena._finish_run(true)
	check(int(save_mgr.credits) == credits_after_first, "Calling _finish_run(true) a second time must be idempotent")

	root.remove_child(arena)
	arena.free()

	# 6. PhoneOS INVENTORY live panel refresh reads SaveManager loot & credits
	var phone_packed := load("res://scenes/ui/phone_os.tscn") as PackedScene
	if check(phone_packed != null, "phone_os.tscn must load cleanly"):
		var phone := phone_packed.instantiate()
		root.add_child(phone)
		phone.open_tab("INVENTORY")
		var inv_sum := phone.find_child("InventorySummaryLabel", true, false) as Label
		var inv_items := phone.find_child("InventoryItemsLabel", true, false) as Label
		check(inv_sum != null and inv_sum.text.contains(str(save_mgr.credits)), "PhoneOS INVENTORY summary must display updated SaveManager credits")
		check(inv_items != null and inv_items.text.contains("boss_core_fragment"), "PhoneOS INVENTORY items must list looted boss_core_fragment")
		root.remove_child(phone)
		phone.free()

	# Restore autoload singletons & verify 0 orphan nodes
	mod_loader.loaded_students.erase("mod_arona_striker")
	mod_loader.loaded_students.erase("mod_plana_special")
	dcm.current_ap = orig_ap
	dcm.max_ap = orig_max_ap
	dcm.current_hour = orig_hour
	dcm.current_day = orig_day
	save_mgr.credits = orig_credits
	save_mgr.inventory = orig_inv
	save_mgr.unlocked_roguelike_cards.clear()
	for c in orig_cards:
		save_mgr.unlocked_roguelike_cards.append(str(c))
	save_mgr.unlocked_skill_variants = orig_variants
	save_mgr.completed_quests = orig_quests
	save_mgr.quest_progress = orig_qprog
	save_mgr.last_combat_summary = orig_summary
	ztm.pending_combat_config = orig_pending

	var orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	check(orphans == 0, "OBJECT_ORPHAN_NODE_COUNT after Phase 3A sortie test must be 0, got %d" % orphans)

	_completed = true
