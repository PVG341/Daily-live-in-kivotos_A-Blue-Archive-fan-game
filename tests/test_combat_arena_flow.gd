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
	arena.targeting_overlay.begin_targeting(preview_skill)
	var prev_pos: Vector3 = arena.targeting_overlay.update_preview(Vector2(640.0, 360.0), null, 0.0)
	check(arena.targeting_overlay.is_targeting == true and prev_pos == arena.targeting_overlay.preview_world_position, "SkillTargetingOverlay.update_preview must update preview_world_position")
	arena.targeting_overlay.cancel_targeting()
	check(arena.targeting_overlay.is_targeting == false and arena.targeting_overlay.visible == false, "cancel_targeting must reset overlay visibility")
	if arena.skill_preview_disc != null:
		check(arena.skill_preview_disc.visible == false, "cancel_targeting must hide 3D skill_preview_disc")

	# 4. Cast an EX-Skill and verify cost deduction + AoE damage
	arena.ex_skill_system.cost_bar.current_cost = 6.0
	var dmg_skill: SkillData = arena.ex_skill_system.registered_skills[0]
	var first_enemy = arena.enemy_units[0]
	var enemy_hp_before: int = first_enemy.current_hp
	check(arena.ex_skill_system.activate_skill(dmg_skill, first_enemy.position) == true, "Activating Missile Barrage must succeed")
	check(is_equal_approx(arena.ex_skill_system.cost_bar.current_cost, 3.0), "Cost bar must drop by skill cost (6.0 -> 3.0)")
	check(first_enemy.current_hp < enemy_hp_before, "Offensive EX-Skill must damage enemies inside radius")

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

	var target_striker = arena.squad_units[0]
	var striker_hp_before: int = target_striker.current_hp
	var spawned_aoe = arena.spawn_boss_telegraphed_aoe(spawned_boss, target_striker.position)
	check(spawned_aoe != null, "spawn_boss_telegraphed_aoe must create a TelegraphedAoE")
	check(arena.active_aoes.size() == 1, "active_aoes must track the spawned TelegraphedAoE")

	# Step past warn_duration so AoE detonates on striker and removes itself cleanly
	arena.step_combat(0.5)
	check(arena.active_aoes.size() == 1, "AoE must remain active before warn_duration elapses")
	arena.step_combat(2.5)
	check(target_striker.current_hp < striker_hp_before, "Detonated TelegraphedAoE must damage striker inside radius")
	check(arena.active_aoes.is_empty(), "Detonated TelegraphedAoE must be freed and removed from active_aoes")

	# 7. Cleanup & Orphan Node Check
	root.remove_child(arena)
	arena.free()
	var orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	check(orphans == 0, "OBJECT_ORPHAN_NODE_COUNT after freeing CombatArena must be 0, got %d" % orphans)

	_completed = true
