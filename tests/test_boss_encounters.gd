# tests/test_boss_encounters.gd
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

	print("PASS: test_boss_encounters")
	quit(0)
	return true

func _run_tests() -> void:
	# 1. Load scripts
	var boss_script: GDScript = load("res://scripts/combat/BossUnit.gd")
	if not check(boss_script != null and boss_script.can_instantiate(), "BossUnit.gd must load and compile"):
		return
	var aoe_script: GDScript = load("res://scripts/combat/TelegraphedAoE.gd")
	if not check(aoe_script != null and aoe_script.can_instantiate(), "TelegraphedAoE.gd must load and compile"):
		return
	var combat_unit_script: GDScript = load("res://scripts/combat/CombatUnit.gd")
	if not check(combat_unit_script != null and combat_unit_script.can_instantiate(), "CombatUnit.gd must load and compile"):
		return

	# 2. BossUnit tests
	var boss = boss_script.new()
	check(boss is EnemyUnit, "BossUnit must extend EnemyUnit")
	check(boss is CombatUnit, "BossUnit must inherit from CombatUnit")
	check(boss.enemy_type == "BOSS", "BossUnit enemy_type must be BOSS")
	check(boss.max_hp == 10000 and boss.current_hp == 10000, "BossUnit must initialize with 10000/10000 HP")
	check(boss.current_phase == 1, "BossUnit must start in phase 1")
	check(is_equal_approx(boss.get_hp_ratio(), 1.0), "BossUnit initial HP ratio must be 1.0")

	var phase_log: Array[int] = []
	boss.phase_changed.connect(func(new_phase: int): phase_log.append(new_phase))

	boss.atk = 200
	var p1: Dictionary = boss.select_boss_pattern()
	check(p1.get("pattern_id", "") == "sweeping_fire", "Phase 1 pattern_id must be sweeping_fire")
	check(int(p1.get("phase", 0)) == 1, "Phase 1 pattern phase must be 1")
	check(is_equal_approx(float(p1.get("aoe_radius", 0.0)), 3.0), "Phase 1 aoe_radius must be 3.0")
	check(is_equal_approx(float(p1.get("warn_duration", 0.0)), 1.8), "Phase 1 warn_duration must be 1.8")
	check(int(p1.get("damage", 0)) == 200, "Phase 1 damage must equal atk (200)")

	# Damage above 70% threshold stays in Phase 1
	var dmg1: int = boss.take_damage(2000)
	check(dmg1 == 2000 and boss.current_hp == 8000, "take_damage(2000) must reduce HP to 8000")
	check(boss.current_phase == 1 and phase_log.is_empty(), "HP > 70% must stay in phase 1 with no signal")

	# Drop to 6800 / 10000 (<= 70%) triggers Phase 2
	var dmg2: int = boss.take_damage(1200)
	check(dmg2 == 1200 and boss.current_hp == 6800, "take_damage(1200) must reduce HP to 6800")
	check(is_equal_approx(boss.get_hp_ratio(), 0.68), "HP ratio must be 0.68")
	check(boss.current_phase == 2, "HP <= 70% must transition to phase 2")
	check(phase_log.size() == 1 and phase_log[0] == 2, "phase_changed(2) must be emitted once")

	var p2: Dictionary = boss.select_boss_pattern()
	check(p2.get("pattern_id", "") == "missile_barrage", "Phase 2 pattern_id must be missile_barrage")
	check(int(p2.get("phase", 0)) == 2, "Phase 2 pattern phase must be 2")
	check(is_equal_approx(float(p2.get("aoe_radius", 0.0)), 4.0), "Phase 2 aoe_radius must be 4.0")
	check(is_equal_approx(float(p2.get("warn_duration", 0.0)), 1.4), "Phase 2 warn_duration must be 1.4")
	check(int(p2.get("damage", 0)) == 270, "Phase 2 damage must be round(200 * 1.35) == 270")

	# Healing back above 70% must NOT regress phase
	boss.heal(2000)
	var after_heal_phase: int = boss.update_phase_from_hp()
	check(after_heal_phase == 2 and boss.current_phase == 2, "Boss phase must only increase and never regress")
	check(phase_log.size() == 1, "No phase_changed signal on heal")

	# Drop to 2500 / 10000 (<= 30%) triggers Phase 3
	boss.take_damage(6300)
	check(boss.current_hp == 2500, "HP must be 2500 after 6300 damage from 8800")
	check(boss.current_phase == 3, "HP <= 30% must transition to phase 3")
	check(phase_log.size() == 2 and phase_log[1] == 3, "phase_changed(3) must be emitted")

	var p3: Dictionary = boss.select_boss_pattern()
	check(p3.get("pattern_id", "") == "overdrive_annihilation", "Phase 3 pattern_id must be overdrive_annihilation")
	check(int(p3.get("phase", 0)) == 3, "Phase 3 pattern phase must be 3")
	check(is_equal_approx(float(p3.get("aoe_radius", 0.0)), 5.5), "Phase 3 aoe_radius must be 5.5")
	check(is_equal_approx(float(p3.get("warn_duration", 0.0)), 1.1), "Phase 3 warn_duration must be 1.1")
	check(int(p3.get("damage", 0)) == 350, "Phase 3 damage must be round(200 * 1.75) == 350")

	# 3. TelegraphedAoE tests with Dictionary units
	var aoe = aoe_script.new()
	check(aoe is Node3D, "TelegraphedAoE must extend Node3D")

	var started_events: Array = []
	var detonated_events: Array = []
	aoe.telegraph_started.connect(func(pos: Vector3, rad: float, dur: float): started_events.append([pos, rad, dur]))
	aoe.aoe_detonated.connect(func(hits: Array): detonated_events.append(hits))

	aoe.setup(Vector3.ZERO, 3.0, 1.5, 500)
	check(started_events.size() == 1, "setup must emit telegraph_started")
	check(is_equal_approx(aoe.get_warning_progress(), 0.0), "Initial warning progress must be 0.0")
	check(not aoe.has_detonated, "has_detonated must be false after setup")

	var hoshino := {"name": "Hoshino", "position": Vector3(1.0, 0.0, 1.0), "hp": 2000}
	var shiroko := {"name": "Shiroko", "position": Vector3(10.0, 0.0, 10.0), "hp": 1200}
	var dead_dict := {"name": "Defeated", "position": Vector3(0.5, 0.0, 0.5), "hp": 0, "is_alive": false}
	var arena_dicts: Array = [hoshino, shiroko, dead_dict]

	var early_hits: Array = aoe.tick(1.0, arena_dicts)
	check(early_hits.is_empty(), "AoE must NOT detonate before warn_duration elapses")
	check(not aoe.has_detonated and detonated_events.is_empty(), "has_detonated and signal must remain untriggered during telegraph")
	check(is_equal_approx(aoe.get_warning_progress(), 1.0 / 1.5), "Warning progress at 1.0/1.5 must match")
	check(int(hoshino["hp"]) == 2000 and int(shiroko["hp"]) == 1200, "No damage during telegraph warning")

	var detonate_hits: Array = aoe.tick(0.6, arena_dicts)
	check(aoe.has_detonated, "AoE must detonate once elapsed >= warn_duration")
	check(is_equal_approx(aoe.get_warning_progress(), 1.0), "Warning progress after detonation must clamp to 1.0")
	check(detonate_hits.size() == 1 and detonate_hits[0] == hoshino, "Only living unit inside radius (Hoshino) must be hit")
	check(detonated_events.size() == 1 and detonated_events[0].size() == 1, "aoe_detonated must emit hit_units")
	check(int(hoshino["hp"]) == 1500, "Hoshino must take 500 AoE damage (2000 -> 1500)")
	check(int(shiroko["hp"]) == 1200, "Shiroko outside radius must take 0 damage")

	var post_hits: Array = aoe.tick(0.5, arena_dicts)
	check(post_hits.is_empty() and int(hoshino["hp"]) == 1500, "Detonated AoE must not trigger a second time")

	# 4. TelegraphedAoE tests with real CombatUnit instances (micro dodging)
	var aoe_units = aoe_script.new()
	var unit_inside = combat_unit_script.new()
	unit_inside.max_hp = 1000
	unit_inside.current_hp = 1000
	unit_inside.position = Vector3(2.0, 0.0, 0.0)

	var unit_dodger = combat_unit_script.new()
	unit_dodger.max_hp = 1000
	unit_dodger.current_hp = 1000
	unit_dodger.position = Vector3(1.0, 0.0, 0.0)

	aoe_units.setup(Vector3.ZERO, 3.0, 1.2, 400)
	check(aoe_units.tick(0.6, [unit_inside, unit_dodger]).is_empty(), "No hits before telegraph expires")

	# Player micro-moves unit_dodger outside radius during telegraph window
	unit_dodger.position = Vector3(5.0, 0.0, 0.0)

	var unit_hits: Array = aoe_units.tick(0.7, [unit_inside, unit_dodger])
	check(unit_hits.size() == 1 and unit_hits[0] == unit_inside, "Only CombatUnit remaining inside radius must be hit")
	check(unit_inside.current_hp == 600, "unit_inside must take 400 damage (1000 -> 600)")
	check(unit_dodger.current_hp == 1000, "Micro-dodged CombatUnit must take 0 damage")

	# Cleanup
	boss.free()
	aoe.free()
	aoe_units.free()
	unit_inside.free()
	unit_dodger.free()

	_completed = true
