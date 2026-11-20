# tests/test_enemy_and_events.gd
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

	print("PASS: test_enemy_and_events")
	quit(0)
	return true

func _run_tests() -> void:
	# 1. Load scripts
	var enemy_unit_script: GDScript = load("res://scripts/combat/EnemyUnit.gd")
	if not check(enemy_unit_script != null and enemy_unit_script.can_instantiate(), "EnemyUnit.gd must load and compile"):
		return
	var enemy_ai_script: GDScript = load("res://scripts/combat/EnemyAI.gd")
	if not check(enemy_ai_script != null and enemy_ai_script.can_instantiate(), "EnemyAI.gd must load and compile"):
		return
	var wave_spawner_script: GDScript = load("res://scripts/combat/WaveSpawner.gd")
	if not check(wave_spawner_script != null and wave_spawner_script.can_instantiate(), "WaveSpawner.gd must load and compile"):
		return
	var event_mgr_script: GDScript = load("res://scripts/combat/CombatEventManager.gd")
	if not check(event_mgr_script != null and event_mgr_script.can_instantiate(), "CombatEventManager.gd must load and compile"):
		return

	# 2. EnemyUnit tests
	var enemy = enemy_unit_script.new()
	check(enemy is CombatUnit, "EnemyUnit must extend CombatUnit")
	check(enemy.enemy_type == "GRUNT", "EnemyUnit default enemy_type must be GRUNT")
	check(enemy.behavior == "AGGRESSIVE", "EnemyUnit default behavior must be AGGRESSIVE")

	var loot_entries: Array[Dictionary] = [
		{"item_id": "iron", "chance": 1.0, "quantity": 2},
		{"item_id": "rare_core", "chance": 0.25, "quantity": 1},
	]
	enemy.loot_table = loot_entries

	var rolled_mid: Array[Dictionary] = enemy.roll_loot(0.5)
	check(rolled_mid.size() == 1 and rolled_mid[0].get("item_id", "") == "iron", "roll_loot(0.5) must drop guaranteed iron only")
	check(enemy.dropped_loot.size() == 1, "dropped_loot must match rolled_mid")

	var rolled_low: Array[Dictionary] = enemy.roll_loot(0.1)
	check(rolled_low.size() == 2, "roll_loot(0.1) must drop both iron and rare_core")

	var enemy_died_unit = enemy_unit_script.new()
	var guaranteed_loot: Array[Dictionary] = [{"item_id": "iron", "chance": 1.0, "quantity": 2}]
	enemy_died_unit.loot_table = guaranteed_loot
	var died_count := [0]
	enemy_died_unit.unit_died.connect(func(_u): died_count[0] += 1)
	enemy_died_unit.die()
	check(not enemy_died_unit.is_alive, "EnemyUnit.die() must mark unit not alive")
	check(died_count[0] == 1, "EnemyUnit.die() must emit unit_died via super.die()")
	check(enemy_died_unit.dropped_loot.size() == 1 and enemy_died_unit.dropped_loot[0].get("item_id", "") == "iron", "EnemyUnit.die() must populate dropped_loot")

	# 3. EnemyAI tests
	var ai = enemy_ai_script.new()
	check(ai is Node, "EnemyAI must extend Node")

	var idle_res: Dictionary = ai.evaluate_simple({"behavior": "AGGRESSIVE", "attack_range": 10.0}, [])
	check(idle_res.get("action", "") == "IDLE" and idle_res.get("target") == null, "EnemyAI.evaluate_simple with no players must return IDLE")

	var near_player := {"name": "Hoshino", "position": Vector3(0.0, 0.0, 5.0), "is_alive": true}
	var far_player := {"name": "Shiroko", "position": Vector3(0.0, 0.0, 20.0), "is_alive": true}
	var dead_player := {"name": "Dead", "position": Vector3(0.0, 0.0, 1.0), "is_alive": false}
	var players: Array = [far_player, dead_player, near_player]

	var aggro_res: Dictionary = ai.evaluate_simple({"behavior": "AGGRESSIVE", "attack_range": 10.0, "position": Vector3.ZERO}, players)
	check(aggro_res.get("action", "") == "RUSH" and aggro_res.get("target") == near_player, "AGGRESSIVE must RUSH nearest living player")

	var def_res: Dictionary = ai.evaluate_simple({"behavior": "DEFENSIVE", "attack_range": 10.0, "position": Vector3.ZERO}, players)
	check(def_res.get("action", "") == "HOLD_AND_SHOOT" and def_res.get("target") == near_player, "DEFENSIVE must HOLD_AND_SHOOT nearest living player")

	var patrol_far_res: Dictionary = ai.evaluate_simple({"behavior": "PATROL", "attack_range": 4.0, "position": Vector3.ZERO}, players)
	check(patrol_far_res.get("action", "") == "PATROL" and patrol_far_res.get("target") == null, "PATROL out of attack_range must return PATROL with null target")

	var patrol_near_res: Dictionary = ai.evaluate_simple({"behavior": "PATROL", "attack_range": 6.0, "position": Vector3.ZERO}, players)
	check(patrol_near_res.get("action", "") == "ENGAGE" and patrol_near_res.get("target") == near_player, "PATROL within attack_range must return ENGAGE with nearest target")

	# EnemyAI.evaluate() with EnemyUnit and Dictionary
	var unit_enemy = enemy_unit_script.new()
	unit_enemy.behavior = "DEFENSIVE"
	unit_enemy.attack_range = 10.0
	unit_enemy.position = Vector3.ZERO
	var eval_unit_res: Dictionary = ai.evaluate(unit_enemy, players)
	check(eval_unit_res.get("action", "") == "HOLD_AND_SHOOT" and eval_unit_res.get("target") == near_player, "EnemyAI.evaluate must work with EnemyUnit")

	var eval_dict_res: Dictionary = ai.evaluate({"behavior": "AGGRESSIVE", "attack_range": 10.0, "position": Vector3.ZERO}, players)
	check(eval_dict_res.get("action", "") == "RUSH" and eval_dict_res.get("target") == near_player, "EnemyAI.evaluate must work with Dictionary")

	# 4. WaveSpawner tests
	var spawner = wave_spawner_script.new()
	check(spawner is Node, "WaveSpawner must extend Node")
	var started_log: Array = []
	var cleared_log: Array = []
	spawner.wave_started.connect(func(w: int, c: int): started_log.append([w, c]))
	spawner.wave_cleared.connect(func(w: int): cleared_log.append(w))

	spawner.start_wave(1, 0)
	check(spawner.get_current_wave() == 1, "start_wave must set current_wave")
	check(started_log.size() == 1 and started_log[0][0] == 1 and started_log[0][1] == 0, "start_wave must emit wave_started")

	spawner.register_enemy_count(3)
	check(spawner.is_wave_complete() == false, "Wave with 3 alive enemies must not be complete")

	spawner.register_enemy_killed()
	check(spawner.is_wave_complete() == false and cleared_log.is_empty(), "Wave after 1 kill must not be complete")
	spawner.register_enemy_killed()
	check(spawner.is_wave_complete() == false and cleared_log.is_empty(), "Wave after 2 kills must not be complete")
	spawner.register_enemy_killed()
	check(spawner.is_wave_complete() == true, "Wave after 3 kills must be complete")
	check(cleared_log.size() == 1 and cleared_log[0] == 1, "Wave completion must emit wave_cleared(current_wave)")

	# 5. CombatEventManager tests
	var evt_mgr = event_mgr_script.new()
	check(evt_mgr is Node, "CombatEventManager must extend Node")
	check(is_equal_approx(evt_mgr.MIN_ELAPSED_SECONDS, 15.0), "MIN_ELAPSED_SECONDS must be 15.0")

	check(evt_mgr.check_for_random_event(5.0, 1, false, 0.0) == null, "Event must be blocked before 15.0s elapsed")
	check(evt_mgr.check_for_random_event(60.0, 2, true, 0.0) == null, "Event must be blocked when card draft UI is open")
	check(evt_mgr.check_for_random_event(60.0, 0, false, 0.0) == null, "Event must be blocked when room_index <= 0")
	check(evt_mgr.check_for_random_event(20.0, 1, false, 0.99) == null, "Event must not trigger when roll exceeds chance")

	var ev: Variant = evt_mgr.check_for_random_event(20.0, 2, false, 0.01)
	check(ev is Dictionary and ev.has("type") and ev.get("room_index") == 2, "Valid check_for_random_event must return event Dictionary")
	check(evt_mgr.EVENT_TYPES.has(str(ev["type"])), "Event type must be in EVENT_TYPES")

	var bus_script: GDScript = load("res://scripts/core/EventBus.gd")
	var mock_bus = bus_script.new()
	evt_mgr.event_bus = mock_bus
	var triggered_types: Array[String] = []
	mock_bus.combat_event_triggered.connect(func(t: String): triggered_types.append(t))

	check(evt_mgr.trigger_event({}) == false, "trigger_event({}) must return false")
	check(evt_mgr.trigger_event({"room_index": 1}) == false, "trigger_event without type must return false")
	check(evt_mgr.trigger_event(ev) == true, "trigger_event(ev) must return true")
	check(evt_mgr.last_triggered_event.get("type", "") == ev["type"], "last_triggered_event must store triggered event")
	check(triggered_types.size() == 1 and triggered_types[0] == str(ev["type"]), "trigger_event must emit EventBus.combat_event_triggered")

	# High room_index chance cap (0.50): roll 0.51 misses, roll 0.49 hits
	check(evt_mgr.check_for_random_event(20.0, 20, false, 0.51) == null, "Chance must be capped at 0.50 so 0.51 misses")
	var capped_ev: Variant = evt_mgr.check_for_random_event(20.0, 20, false, 0.49)
	check(capped_ev is Dictionary and capped_ev.get("room_index") == 20, "Roll 0.49 must trigger at capped 0.50 chance")

	# Cleanup
	enemy.free()
	enemy_died_unit.free()
	ai.free()
	unit_enemy.free()
	spawner.free()
	evt_mgr.free()
	mock_bus.free()

	_completed = true
