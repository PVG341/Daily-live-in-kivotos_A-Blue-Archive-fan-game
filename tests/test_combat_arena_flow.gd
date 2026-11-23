# tests/test_combat_arena_flow.gd
extends SceneTree

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

	print("PASS: test_combat_arena_flow")
	quit(0)
	return true

func _find_first_nav_region(node: Node) -> NavigationRegion3D:
	if node is NavigationRegion3D:
		return node as NavigationRegion3D
	for child in node.get_children():
		var found := _find_first_nav_region(child)
		if found != null:
			return found
	return null

func _run_tests() -> void:
	# Preload new scripts directly so headless mode works without editor global class cache rebuild
	var room_data_script: GDScript = load("res://scripts/combat/CombatRoomData.gd")
	var proxy_script: GDScript = load("res://scripts/combat/ChibiProxyFactory.gd")
	var sel_overlay_script: GDScript = load("res://scripts/combat/SelectionBoxOverlay.gd")
	var arena_ctrl_script: GDScript = load("res://scripts/combat/CombatArenaController.gd")
	var boss_script: GDScript = load("res://scripts/combat/BossUnit.gd")

	if not check(room_data_script != null and proxy_script != null and sel_overlay_script != null and arena_ctrl_script != null, "All new combat scripts must load and compile"):
		return

	# 1. Verify all 4 modular room scenes load, instantiate, and expose CombatRoomData
	var room_specs: Array[Dictionary] = [
		{"path": "res://scenes/combat/rooms/room_combat.tscn", "type": "COMBAT", "min_covers": 4, "min_enemies": 5, "boss": false},
		{"path": "res://scenes/combat/rooms/room_elite.tscn", "type": "ELITE", "min_covers": 6, "min_enemies": 6, "boss": false},
		{"path": "res://scenes/combat/rooms/room_rest.tscn", "type": "REST", "min_covers": 0, "min_enemies": 0, "boss": false},
		{"path": "res://scenes/combat/rooms/room_boss.tscn", "type": "BOSS", "min_covers": 4, "min_enemies": 2, "boss": true},
	]

	for spec in room_specs:
		var rpath: String = str(spec["path"])
		var packed := load(rpath) as PackedScene
		if not check(packed != null, "Room scene must load cleanly: %s" % rpath):
			return
		var room := packed.instantiate()
		if not check(room != null and is_instance_of(room, room_data_script), "%s root must use CombatRoomData" % rpath):
			return
		check(room.room_type == str(spec["type"]), "%s room_type must be '%s'" % [rpath, str(spec["type"])])
		check(_find_first_nav_region(room) != null, "%s must contain NavigationRegion3D" % rpath)
		check(room.get_player_spawn_positions().size() >= 4, "%s must contain at least 4 PlayerSpawns" % rpath)
		check(room.get_cover_points().size() >= int(spec["min_covers"]), "%s must contain at least %d CoverPoint3Ds" % [rpath, int(spec["min_covers"])])
		check(room.get_enemy_spawn_positions().size() >= int(spec["min_enemies"]), "%s must contain at least %d EnemySpawns" % [rpath, int(spec["min_enemies"])])
		if str(spec["type"]) == "COMBAT":
			check(room.arena_size.x >= 60.0 and room.arena_size.y >= 52.0, "room_combat.tscn arena_size must be expanded (>= 60x52)")
			check(room.get_terrain_zones().size() >= 5, "room_combat.tscn must contain at least 5 TacticalTerrainZones")
			var trench_mods: Dictionary = room.get_terrain_modifiers_at(Vector3(-12.0, 0.0, 3.0))
			check(float(trench_mods.get("speed_multiplier", 1.0)) < 1.0, "Water trench zone must reduce speed_multiplier")
			var high_mods: Dictionary = room.get_terrain_modifiers_at(Vector3(-18.0, 0.0, 14.0))
			check(float(high_mods.get("range_bonus_multiplier", 1.0)) > 1.0, "High ground zone must grant range_bonus_multiplier > 1.0")
			var bunker_mods: Dictionary = room.get_terrain_modifiers_at(Vector3(0.0, 0.0, -1.0))
			check(float(bunker_mods.get("damage_taken_multiplier", 1.0)) < 1.0, "Bunker interior zone must grant damage_taken_multiplier < 1.0")
		if bool(spec["boss"]):
			check(room.get_node_or_null("BossSpawn") is Marker3D, "room_boss.tscn must contain BossSpawn Marker3D")
		room.free()

	# 2. Instantiate scenes/combat/combat_arena.tscn in-tree
	var arena_packed := load("res://scenes/combat/combat_arena.tscn") as PackedScene
	if not check(arena_packed != null, "scenes/combat/combat_arena.tscn must load cleanly"):
		return
	var arena := arena_packed.instantiate()
	if not check(arena != null and is_instance_of(arena, arena_ctrl_script), "combat_arena.tscn root must use CombatArenaController"):
		return
	root.add_child(arena)

	check(arena.squad_units.size() == 4, "Arena must spawn 4 Striker CombatUnits, got %d" % arena.squad_units.size())
	check(arena.enemy_units.size() >= 3, "Room 0 (COMBAT) must spawn initial enemies")
	check(arena.room_manager.get_current_room_index() == 0, "Dungeon run must start at room 0")
	check(arena.room_manager.is_draft_open == false, "Card draft must start closed")
	check(arena.combat_hud != null and arena.combat_hud.striker_hp.size() == 4, "CombatHUD must display 4 Strikers")

	var settings_mgr: Node = root.get_node_or_null("SettingsManager")
	check(settings_mgr != null and settings_mgr.get("show_group_frame") == false, "SettingsManager default show_group_frame must be false")
	check(arena.selection_box_overlay != null and arena.selection_box_overlay.show_group_frame == false, "SelectionBoxOverlay show_group_frame must default to false")

	# 2b. Combat Camera panning & recentering
	arena.camera_rig.center_on_position(Vector3(5.0, 0.0, 8.0))
	check(is_equal_approx(arena.camera_rig.global_position.x, 5.0) and is_equal_approx(arena.camera_rig.global_position.z, 8.0), "RTSCamera3D.center_on_position must recenter XZ position")
	var pos_before_drag: Vector3 = arena.camera_rig.global_position
	arena.camera_rig.pan_by_screen_delta(Vector2(40.0, -30.0))
	check(not arena.camera_rig.global_position.is_equal_approx(pos_before_drag), "RTSCamera3D.pan_by_screen_delta must pan camera on XZ plane")
	arena.camera_rig.center_on_position(Vector3.ZERO)

	# 3. step_combat accumulates cost bar & ticks units without errors
	var cost_before: float = arena.ex_skill_system.cost_bar.current_cost
	arena.step_combat(0.5)
	check(arena.ex_skill_system.cost_bar.current_cost > cost_before, "step_combat(0.5) must accumulate EX cost bar")

	# 3b. Tactical UI, Multi-Unit Selection, Order Pillars, Target Reticle, and EX-Skill Preview
	var striker0 = arena.squad_units[0]
	var striker1 = arena.squad_units[1]
	var focus_enemy = arena.enemy_units[0]
	arena.selection_manager.select_unit(striker0, false)
	arena.selection_manager.select_unit(striker1, true)
	check(arena.combat_hud.selected_striker_ids.size() == 2, "Selecting 2 Strikers must update CombatHUD.selected_striker_ids to 2")
	var ring0 := striker0.get_node_or_null("VisualRoot/SelectionRing") as Node3D
	var atk_ring0 := striker0.get_node_or_null("VisualRoot/AttackRangeRing") as Node3D
	check(ring0 != null and ring0.visible == true, "Selected Striker VisualRoot/SelectionRing must be visible")
	check(atk_ring0 != null and atk_ring0.visible == true, "Selected Striker VisualRoot/AttackRangeRing must be visible")

	arena.selection_manager.issue_hold_position()
	var pillar0 := striker0.get_node_or_null("VisualRoot/OrderStatusPillar") as Node3D
	var order_lbl0 := striker0.get_node_or_null("VisualRoot/OrderStatusPillar/OrderIconLabel") as Label3D
	check(pillar0 != null and pillar0.visible == true, "HOLD_POSITION must reveal VisualRoot/OrderStatusPillar")
	check(order_lbl0 != null and order_lbl0.text.contains("HOLD POS"), "HOLD_POSITION pillar label must show HOLD POS")

	arena.selection_manager.issue_hold_fire()
	check(order_lbl0 != null and order_lbl0.text.contains("HOLD FIRE"), "HOLD_FIRE pillar label must show HOLD FIRE")

	arena.selection_manager.issue_focus_fire(focus_enemy)
	var enemy_reticle := focus_enemy.get_node_or_null("VisualRoot/TargetReticle") as Node3D
	check(enemy_reticle != null and enemy_reticle.visible == true, "FOCUS_FIRE must reveal enemy VisualRoot/TargetReticle")

	var preview_skill: SkillData = arena.ex_skill_system.registered_skills[0]
	arena.targeting_overlay.set_caster_origin(Vector3.ZERO)
	arena.targeting_overlay.begin_targeting(preview_skill)
	var prev_pos: Vector3 = arena.targeting_overlay.update_preview(Vector2(640.0, 360.0), null, 0.0)
	check(arena.targeting_overlay.is_targeting == true and prev_pos == arena.targeting_overlay.preview_world_position, "SkillTargetingOverlay.update_preview must update preview_world_position")
	var clamped_far: Vector3 = arena.targeting_overlay.update_preview(Vector2(100.0, 0.0), null, 0.0)
	check(Vector2(clamped_far.x, clamped_far.z).length() <= preview_skill.cast_range + 0.05, "SkillTargetingOverlay.update_preview must clamp out-of-range targets to cast_range")
	check(arena.targeting_overlay.is_target_in_range_flag == false, "Out-of-range preview must mark is_target_in_range_flag false")
	arena.targeting_overlay.cancel_targeting()
	check(arena.targeting_overlay.is_targeting == false and arena.targeting_overlay.visible == false, "cancel_targeting must reset overlay visibility")
	if arena.skill_preview_disc != null:
		check(arena.skill_preview_disc.visible == false, "cancel_targeting must hide 3D skill_preview_disc")

	# 3c. SkillData range config & CIRCLE/CONE/LINE AoE checks
	var shape_skill := SkillData.new()
	shape_skill.cast_range = 15.0
	shape_skill.aoe_radius = 6.0
	shape_skill.aoe_shape = "CIRCLE"
	check(shape_skill.clamp_target_to_range(Vector3.ZERO, Vector3(30.0, 0.0, 0.0)).is_equal_approx(Vector3(15.0, 0.0, 0.0)), "SkillData.clamp_target_to_range must clamp to cast_range")
	check(shape_skill.is_point_inside_aoe(Vector3.ZERO, Vector3(8.0, 0.0, 0.0), Vector3(11.0, 0.0, 0.0)) == true, "CIRCLE AoE must include points within aoe_radius")
	shape_skill.aoe_shape = "CONE"
	shape_skill.cone_angle_deg = 60.0
	check(shape_skill.is_point_inside_aoe(Vector3.ZERO, Vector3(0.0, 0.0, -10.0), Vector3(1.0, 0.0, -5.0)) == true, "CONE AoE must include forward-cone target")
	check(shape_skill.is_point_inside_aoe(Vector3.ZERO, Vector3(0.0, 0.0, -10.0), Vector3(0.0, 0.0, 5.0)) == false, "CONE AoE must exclude behind-caster point")
	shape_skill.aoe_shape = "LINE"
	shape_skill.line_width = 2.0
	check(shape_skill.is_point_inside_aoe(Vector3.ZERO, Vector3(0.0, 0.0, -10.0), Vector3(0.5, 0.0, -6.0)) == true, "LINE AoE must include point inside beam width")
	check(shape_skill.is_point_inside_aoe(Vector3.ZERO, Vector3(0.0, 0.0, -10.0), Vector3(3.0, 0.0, -6.0)) == false, "LINE AoE must exclude point outside beam width")

	# 4. Cast an EX-Skill and verify cost deduction + AoE damage + HP bar & floating popup
	arena.ex_skill_system.cost_bar.current_cost = 6.0
	var dmg_skill: SkillData = arena.ex_skill_system.registered_skills[0]
	var first_enemy = arena.enemy_units[0]
	var enemy_hp_before: int = first_enemy.current_hp
	check(arena.ex_skill_system.activate_skill(dmg_skill, first_enemy.position) == true, "Activating Missile Barrage must succeed")
	check(is_equal_approx(arena.ex_skill_system.cost_bar.current_cost, 3.0), "Cost bar must drop by skill cost (6.0 -> 3.0)")
	check(first_enemy.current_hp < enemy_hp_before, "Offensive EX-Skill must damage enemies inside radius")
	var enemy_hp_pivot := first_enemy.get_node_or_null("VisualRoot/HPBar3D/HPFillPivot") as Node3D
	check(enemy_hp_pivot != null and enemy_hp_pivot.scale.x < 1.0, "Damaging enemy must shrink VisualRoot/HPBar3D/HPFillPivot.scale.x")
	check(arena.health_bar_overlay != null and arena.health_bar_overlay.floating_numbers.size() >= 1, "Damaging enemy must spawn floating damage number")

	# 4b. Phase B — Line-of-Sight, Wall Blocking, Penetration & Wall-Breaching Skills
	var wall_script: GDScript = load("res://scripts/combat/DestructibleWall3D.gd")
	check(wall_script != null and wall_script.can_instantiate(), "DestructibleWall3D.gd must load cleanly")
	check(arena.ex_skill_system.registered_skills.size() >= 4, "Arena must register piercing/breaching EX skills (Shotgun Breach & Railgun Beam)")
	check(arena.current_room_info.get_wall_obstacles().size() >= 6, "room_combat must subdivide modular DestructibleWall3D obstacles (>= 6)")

	var wall_test_enemy = arena.enemy_units[1]
	wall_test_enemy.position = Vector3(0.0, 0.0, -5.0)
	var test_wall = wall_script.new()
	test_wall.name = "PhaseBTestWall"
	test_wall.position = Vector3(0.0, 1.5, 0.0)
	arena.current_room_info.add_child(test_wall)
	test_wall.setup_wall(Vector3(4.0, 3.0, 0.6), 2, 500, Color(0.7, 0.6, 0.5), true)
	arena.current_room_info.register_wall_obstacle(test_wall)
	arena.projectile_manager.set_wall_obstacles(arena.current_room_info.get_wall_obstacles())

	check(arena.current_room_info.check_line_of_sight(Vector3(0.0, 0.7, 5.0), Vector3(0.0, 0.7, -5.0), 0)["clear"] == false, "Normal LOS (pen=0) must be blocked by armor_tier=2 wall")
	check(arena.current_room_info.check_line_of_sight(Vector3(0.0, 0.7, 5.0), Vector3(0.0, 0.7, -5.0), 2)["clear"] == true, "High penetration LOS (pen=2) must pierce armor_tier=2 wall")

	var hp_pre_block: int = wall_test_enemy.current_hp
	var norm_proj: Dictionary = arena.projectile_manager.spawn_projectile(Vector3(0.0, 0.7, 5.0), Vector3(0.0, 0.7, -5.0), 25.0, 200, striker0, wall_test_enemy, 0, 10)
	arena.projectile_manager.tick_projectiles(1.0)
	check(norm_proj["blocked_by_wall"] == test_wall and wall_test_enemy.current_hp == hp_pre_block, "Normal projectile (pen=0) must stop on wall and deal 0 damage behind it")

	var wall_hp_before_pierce: int = test_wall.current_hp
	var pierce_proj: Dictionary = arena.projectile_manager.spawn_projectile(Vector3(0.0, 0.7, 5.0), Vector3(0.0, 0.7, -5.0), 25.0, 200, striker0, wall_test_enemy, 2, 100)
	arena.projectile_manager.tick_projectiles(1.0)
	check(pierce_proj["blocked_by_wall"] == null and test_wall.current_hp < wall_hp_before_pierce and wall_test_enemy.current_hp < hp_pre_block, "Piercing projectile (pen=2) must pierce wall, damage wall, and hit enemy behind it")

	striker0.position = Vector3(0.0, 0.0, 5.0)
	arena.selection_manager.select_unit(striker0, false)
	arena.ex_skill_system.cost_bar.current_cost = 10.0
	var breach_skill: SkillData = arena.ex_skill_system.registered_skills[2]
	check(arena.ex_skill_system.activate_skill(breach_skill, Vector3(0.0, 0.0, -5.0)) == true, "Shotgun Breach cone skill must activate")
	check(test_wall.is_destroyed == true, "Shotgun Breach must destroy the armor_tier=2 wall segment")
	check(arena.current_room_info.check_line_of_sight(Vector3(0.0, 0.7, 5.0), Vector3(0.0, 0.7, -5.0), 0)["clear"] == true, "Destroyed wall must leave a breached hole allowing normal bullets through")

	# 4c. Phase C — Anti-Stuck Barricade/Bunker Navigation & Crowd Separation
	check(arena.commander_system != null and arena.utility_ai != null, "Arena must initialize CommanderDirectiveSystem and UtilityAIManager")
	striker0.clear_player_order()
	striker1.clear_player_order()
	striker0.position = Vector3(0.0, 0.0, 7.2)
	striker1.position = Vector3(0.2, 0.0, 7.2)
	for e_nav in arena.enemy_units:
		if e_nav.is_alive:
			e_nav.position = Vector3(0.0, 0.0, -17.0)
	var s0_start: Vector3 = striker0.position
	var s1_start: Vector3 = striker1.position
	for _nav_tick in range(15):
		arena.step_combat(0.2)
	check(striker0.position.distance_to(s0_start) > 2.5, "striker0 must flank cleanly around CoverCraterRim barricade & bunker without getting stuck, moved %.2f" % striker0.position.distance_to(s0_start))
	check(striker1.position.distance_to(s1_start) > 2.5, "striker1 must flank cleanly around CoverCraterRim barricade & bunker without getting stuck, moved %.2f" % striker1.position.distance_to(s1_start))
	check(striker0.position.distance_to(striker1.position) >= 0.45, "Friendly unit separation must prevent strikers from stacking on top of each other")

	# 4d. Phase C — Commander Directive System & Utility AI
	arena.commander_system.place_tactical_zone(Vector3(-14.0, 0.0, 12.0), 5.0)
	check(arena.tactical_zone_disc != null and arena.tactical_zone_disc.visible == true, "place_tactical_zone must reveal 3D TacticalZoneDisc")
	var zone_eval: Dictionary = arena.utility_ai.evaluate_unit_utility(
		striker0, arena.squad_units, arena.enemy_units, arena.cover_points, arena.active_aoes, arena.commander_system, arena.current_room_info, 10
	)
	check(str(zone_eval.get("action", "")) == "ADVANCE_TO_ZONE", "UtilityAI must prioritize ADVANCE_TO_ZONE when unit is outside commanded zone, got %s" % str(zone_eval.get("action", "")))

	arena.commander_system.clear_directives()
	var prio_enemy = null
	for pe in arena.enemy_units:
		if pe.is_alive:
			prio_enemy = pe
			break
	if prio_enemy != null:
		arena.commander_system.set_priority_target(prio_enemy)
		var prio_reticle := prio_enemy.get_node_or_null("VisualRoot/TargetReticle") as Node3D
		check(prio_reticle != null and prio_reticle.visible == true, "set_priority_target must reveal enemy VisualRoot/TargetReticle")
		var prio_eval: Dictionary = arena.utility_ai.evaluate_unit_utility(
			striker1, arena.squad_units, arena.enemy_units, arena.cover_points, arena.active_aoes, arena.commander_system, arena.current_room_info, 10
		)
		check(str(prio_eval.get("action", "")) == "FOCUS_PRIORITY_TARGET", "UtilityAI must prioritize FOCUS_PRIORITY_TARGET when priority enemy is set")

	arena.commander_system.toggle_tactical_slow_mo(true)
	check(arena.commander_system.get_effective_time_scale() < 1.0, "toggle_tactical_slow_mo(true) must slow combat time scale")
	arena.commander_system.toggle_tactical_slow_mo(false)
	arena.commander_system.clear_directives()

	# 5. Defeating all enemies triggers wave_cleared -> opens RoguelikeCardDraft -> select_draft_card advances room
	for enemy in arena.enemy_units:
		if enemy.is_alive:
			enemy.take_damage(99999)

	check(arena.room_manager.is_draft_open == true, "Defeating all enemies in room 0 must open draft")
	check(arena.card_draft_panel.visible == true, "RoguelikeCardDraft panel must be visible when draft opens")
	check(arena.current_draft_cards.size() == 3, "Draft must roll 3 cards")
	check(arena.select_draft_card(0) == true, "select_draft_card(0) must apply card and advance")
	check(arena.card_manager.get_active_buffs().size() == 1, "Selected card must be recorded in card_manager active buffs")
	check(arena.room_manager.get_current_room_index() == 1, "Room manager must advance to room 1 after card draft")

	# 6. Force-load BOSS room -> BossUnit + TelegraphedAoE detonation & cleanup
	arena.load_single_room_for_test("BOSS", 1)
	check(arena.room_manager.get_current_room_index() == 0, "load_single_room_for_test resets room index to 0")
	var spawned_boss = null
	for e in arena.enemy_units:
		if is_instance_of(e, boss_script):
			spawned_boss = e
			break
	if not check(spawned_boss != null, "BOSS room must spawn a BossUnit"):
		root.remove_child(arena)
		arena.free()
		return
	check(arena.health_bar_overlay != null and bool(arena.health_bar_overlay.boss_bar.get("visible", false)) == true, "BOSS room must populate CombatHealthBarOverlay.boss_bar")

	var target_striker = arena.squad_units[0]
	target_striker.receive_hold_position()
	var striker_hp_before: int = target_striker.current_hp
	var spawned_aoe = arena.spawn_boss_telegraphed_aoe(spawned_boss, target_striker.position)
	check(spawned_aoe != null, "spawn_boss_telegraphed_aoe must create a TelegraphedAoE")
	check(arena.active_aoes.size() == 1, "active_aoes must track the spawned TelegraphedAoE")

	# Verify autonomous EVADE_AOE reaction when a second unit stands inside active TelegraphedAoE
	var evade_striker = arena.squad_units[1]
	evade_striker.clear_player_order()
	var danger_aoe = arena.spawn_boss_telegraphed_aoe(spawned_boss, evade_striker.position)
	var evade_eval: Dictionary = arena.utility_ai.evaluate_unit_utility(
		evade_striker, arena.squad_units, arena.enemy_units, arena.cover_points, arena.active_aoes, arena.commander_system, arena.current_room_info, 1
	)
	check(str(evade_eval.get("action", "")) == "EVADE_AOE", "UtilityAI must evaluate EVADE_AOE when unit stands inside TelegraphedAoE radius")
	var evade_start_pos: Vector3 = evade_striker.position

	# Step past warn_duration so AoE detonates on held striker, while evade_striker dodges away
	arena.step_combat(0.5)
	check(arena.active_aoes.size() == 2, "AoEs must remain active before warn_duration elapses")
	check(evade_striker.position.distance_to(evade_start_pos) > 1.0, "Autonomous Utility AI must actively dodge out of danger zone during EVADE_AOE")
	arena.step_combat(2.5)
	check(target_striker.current_hp < striker_hp_before, "Detonated TelegraphedAoE must damage held striker inside radius")
	check(arena.active_aoes.is_empty(), "Detonated TelegraphedAoEs must be freed and removed from active_aoes")
	check(not is_instance_valid(danger_aoe), "Detonated danger_aoe must be freed from ObjectDB")

	# 7. Cleanup & Orphan Node Check
	root.remove_child(arena)
	arena.free()
	var orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	check(orphans == 0, "OBJECT_ORPHAN_NODE_COUNT after freeing CombatArena must be 0, got %d" % orphans)

	_completed = true
