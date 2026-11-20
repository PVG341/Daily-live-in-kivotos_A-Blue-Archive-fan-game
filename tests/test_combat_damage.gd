# tests/test_combat_damage.gd
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

	print("PASS: test_combat_damage")
	quit(0)
	return true

func _run_tests() -> void:
	# 1. Load scripts
	var resolver_script: GDScript = load("res://scripts/combat/DamageResolver.gd")
	if not check(resolver_script != null and resolver_script.can_instantiate(), "DamageResolver.gd must load and compile"):
		return
	var unit_script: GDScript = load("res://scripts/combat/CombatUnit.gd")
	if not check(unit_script != null and unit_script.can_instantiate(), "CombatUnit.gd must load and compile"):
		return
	var proj_script: GDScript = load("res://scripts/combat/ProjectileManager.gd")
	if not check(proj_script != null and proj_script.can_instantiate(), "ProjectileManager.gd must load and compile"):
		return

	# 2. DamageResolver tests
	var resolver = resolver_script.new()
	check(resolver is RefCounted, "DamageResolver must extend RefCounted")

	for _i in range(20):
		var raw_sample: int = resolver.calculate_damage_raw(500, 200)
		if not check(raw_sample >= 360 and raw_sample <= 440, "calculate_damage_raw(500, 200) must be within [360, 440], got %d" % raw_sample):
			return

	check(resolver.calculate_damage_raw(500, 200, 1.0) == 400, "calculate_damage_raw(500, 200, 1.0) must equal 400")
	check(resolver.calculate_damage_raw(500, 200, 1.05) == 420, "calculate_damage_raw(500, 200, 1.05) must equal 420")
	check(resolver.calculate_damage_raw(100, 300) >= 1, "High defense calculate_damage_raw(100, 300) must be >= 1")
	check(resolver.calculate_damage_raw(100, 300, 1.0) == 1, "High defense with variance 1.0 must clamp base to 1")

	check(resolver.apply_buff_modifiers(400, [{"type": "ATK_UP", "value": 0.2}]) == 480, "apply_buff_modifiers(400, ATK_UP 0.2) must equal 480")
	check(
		resolver.apply_buff_modifiers(
			400,
			[
				{"type": "ATK_UP", "value": 0.2},
				{"type": "DMG_UP", "value": 0.1},
				{"type": "FLAT_DMG", "value": 50},
			]
		) == 570,
		"apply_buff_modifiers must combine ATK_UP, DMG_UP, and FLAT_DMG"
	)
	check(resolver.apply_buff_modifiers(10, [{"type": "ATK_UP", "value": -2.0}]) == 1, "apply_buff_modifiers must clamp minimum damage to 1")

	# calculate_damage with StudentData fallback (base_atk / base_def)
	var student_atk := StudentData.new()
	student_atk.id = "shiroko"
	student_atk.student_name = "Shiroko"
	student_atk.base_hp = 1200
	student_atk.base_atk = 500
	student_atk.base_def = 100
	student_atk.base_speed = 6.5
	student_atk.attack_range = 12.0

	var student_def := StudentData.new()
	student_def.id = "hoshino"
	student_def.student_name = "Hoshino"
	student_def.base_hp = 2500
	student_def.base_atk = 220
	student_def.base_def = 200
	student_def.base_speed = 4.0
	student_def.attack_range = 6.0

	var sd_dmg: int = resolver.calculate_damage(student_atk, student_def, [{"type": "FLAT_DMG", "value": 100}])
	check(sd_dmg >= 460 and sd_dmg <= 540, "calculate_damage on StudentData must extract base_atk/base_def and apply buffs, got %d" % sd_dmg)

	# 3. CombatUnit tests
	var unit = unit_script.new()
	check(unit is CharacterBody3D, "CombatUnit must extend CharacterBody3D")
	check(unit.damage_resolver != null, "CombatUnit.damage_resolver must be initialized in _init()")

	unit.setup(student_atk)
	check(unit.unit_data == student_atk, "setup must store unit_data")
	check(unit.max_hp == 1200 and unit.current_hp == 1200, "setup must set max_hp and current_hp from base_hp")
	check(unit.atk == 500 and unit.def == 100, "setup must copy atk and def")
	check(is_equal_approx(unit.speed, 6.5), "setup must copy speed")
	check(is_equal_approx(unit.attack_range, 12.0), "setup must copy attack_range")
	check(unit.is_alive == true and unit.has_player_order == false, "setup must set is_alive=true and has_player_order=false")

	# Signal tracking
	var hp_signals: Array = []
	unit.hp_changed.connect(func(curr: int, max_v: int): hp_signals.append([curr, max_v]))
	var died_units: Array = []
	unit.unit_died.connect(func(u): died_units.append(u))
	var completed_orders: Array = []
	unit.order_completed.connect(func(u): completed_orders.append(u))

	# take_damage & heal
	check(unit.take_damage(0) == 0 and unit.take_damage(-25) == 0, "Non-positive take_damage must return 0")
	var dmg_taken: int = unit.take_damage(300)
	check(dmg_taken == 300, "take_damage(300) must return 300")
	check(unit.current_hp == 900, "current_hp must drop to 900")
	check(hp_signals.size() == 1 and hp_signals[0][0] == 900 and hp_signals[0][1] == 1200, "hp_changed must emit (900, 1200)")

	check(unit.heal(0) == 0 and unit.heal(-10) == 0, "Non-positive heal must return 0")
	var healed_partial: int = unit.heal(150)
	check(healed_partial == 150 and unit.current_hp == 1050, "heal(150) must restore 150 HP to 1050")
	var healed_clamped: int = unit.heal(500)
	check(healed_clamped == 150 and unit.current_hp == 1200, "heal(500) must clamp to max_hp 1200 and return actual 150 restored")

	# calculate_damage using CombatUnit properties (atk/def)
	var defender_unit = unit_script.new()
	defender_unit.setup(student_def)
	var unit_dmg: int = resolver.calculate_damage(unit, defender_unit)
	check(unit_dmg >= 360 and unit_dmg <= 440, "calculate_damage on CombatUnit(500 atk) vs CombatUnit(200 def) must be in [360, 440], got %d" % unit_dmg)

	# take_raw_hit
	var raw_hit_dmg: int = defender_unit.take_raw_hit(500, [{"type": "ATK_UP", "value": 0.2}])
	check(raw_hit_dmg >= 432 and raw_hit_dmg <= 528, "take_raw_hit must mitigate with defender.def and apply buffs, got %d" % raw_hit_dmg)
	check(defender_unit.current_hp == 2500 - raw_hit_dmg, "defender_unit current_hp must reflect take_raw_hit")

	# Order lifecycle + UnitSelectionManager integration
	var sel_mgr_script: GDScript = load("res://scripts/combat/UnitSelectionManager.gd")
	var sel_mgr = sel_mgr_script.new()
	sel_mgr.select_unit(unit, false)
	sel_mgr.issue_move_order(Vector3(10.0, 0.0, -5.0))
	check(unit.has_player_order == true, "UnitSelectionManager.issue_move_order must set has_player_order=true on CombatUnit")
	check(unit.current_order_type == "MOVE", "CombatUnit.current_order_type must update to 'MOVE'")
	check(unit.order_target_position.is_equal_approx(Vector3(10.0, 0.0, -5.0)), "CombatUnit.order_target_position must update")

	unit.clear_player_order()
	check(unit.has_player_order == false and unit.current_order_type == "" and unit.order_target_node == null, "clear_player_order must reset order state")
	check(completed_orders.size() == 1 and completed_orders[0] == unit, "clear_player_order must emit order_completed(self)")

	# check_emergency_override (HP < 10%)
	sel_mgr.issue_focus_fire(defender_unit)
	check(unit.has_player_order == true and unit.current_order_type == "FOCUS_FIRE" and unit.order_target_node == defender_unit, "issue_focus_fire must set order on CombatUnit")
	unit.take_damage(1080) # 1200 -> 120 (exactly 10%)
	check(unit.current_hp == 120, "HP should be 120 (10% of 1200)")
	check(unit.check_emergency_override() == false, "At exactly 10% HP, emergency override must NOT trigger")
	check(unit.has_player_order == true, "has_player_order must remain true when HP >= 10%")

	unit.take_damage(1) # 120 -> 119 (< 10%)
	check(unit.check_emergency_override() == true, "Below 10% HP, check_emergency_override must return true")
	check(unit.has_player_order == false, "check_emergency_override must clear has_player_order")

	# Death on 0 HP
	var lethal_actual: int = unit.take_damage(500)
	check(lethal_actual == 119, "Overkill take_damage(500) at 119 HP must return actual damage 119")
	check(unit.current_hp == 0 and unit.is_alive == false, "Unit must die at 0 HP")
	check(died_units.size() == 1 and died_units[0] == unit, "unit_died signal must emit once with unit")
	check(unit.take_damage(50) == 0, "Dead unit take_damage must return 0")
	check(unit.heal(100) == 0, "Dead unit heal must return 0")
	check(unit.check_emergency_override() == false, "Dead unit check_emergency_override must return false")

	# 4. ProjectileManager tests
	var proj_mgr = proj_script.new()
	check(proj_mgr is Node, "ProjectileManager must extend Node")
	check(proj_mgr.active_projectiles.is_empty(), "active_projectiles must start empty")

	var target_unit = unit_script.new()
	target_unit.setup(student_def) # 2500 HP

	# Hitscan
	var hs_dealt: int = proj_mgr.spawn_hitscan(Vector3.ZERO, target_unit, 350, defender_unit)
	check(hs_dealt == 350 and target_unit.current_hp == 2150, "spawn_hitscan must deal immediate 350 damage")
	check(proj_mgr.spawn_hitscan(Vector3.ZERO, null, 100) == 0, "spawn_hitscan with null target must return 0")

	# Projectile flight across multiple ticks
	var proj: Dictionary = proj_mgr.spawn_projectile(
		Vector3(0.0, 1.0, 0.0),
		Vector3(10.0, 1.0, 0.0),
		5.0,
		250,
		defender_unit,
		target_unit
	)
	check(proj_mgr.active_projectiles.size() == 1, "spawn_projectile must add projectile to active_projectiles")
	check(proj["active"] == true and proj["position"].is_equal_approx(Vector3(0.0, 1.0, 0.0)), "Projectile must start active at origin")

	var hits_t1: int = proj_mgr.tick_projectiles(1.0)
	check(hits_t1 == 0, "After 1.0s at speed 5.0 over 10m, projectile must not have hit yet")
	check(proj_mgr.active_projectiles.size() == 1, "Projectile must remain active mid-flight")
	check(proj_mgr.active_projectiles[0]["position"].is_equal_approx(Vector3(5.0, 1.0, 0.0)), "Projectile must advance to (5, 1, 0)")
	check(target_unit.current_hp == 2150, "Target HP must be unchanged before projectile arrival")

	var hits_t2: int = proj_mgr.tick_projectiles(1.0)
	check(hits_t2 == 1, "After second 1.0s tick, projectile must arrive and resolve 1 hit")
	check(proj["active"] == false, "Projectile record must be marked active = false on arrival")
	check(proj_mgr.active_projectiles.is_empty(), "Inactive projectiles must be removed from active_projectiles")
	check(target_unit.current_hp == 1900, "Target HP must drop by 250 on projectile arrival")

	# Cleanup
	sel_mgr.free()
	unit.free()
	defender_unit.free()
	target_unit.free()
	proj_mgr.free()

	_completed = true
