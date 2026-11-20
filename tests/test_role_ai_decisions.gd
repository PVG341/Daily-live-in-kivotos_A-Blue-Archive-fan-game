# tests/test_role_ai_decisions.gd
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

	print("PASS: test_role_ai_decisions")
	quit(0)
	return true

func _make_student(id: String, name: String, hp: int, role: StudentData.CombatRole) -> StudentData:
	var data := StudentData.new()
	data.id = id
	data.student_name = name
	data.base_hp = hp
	data.role = role
	return data

func _run_tests() -> void:
	var cover_script: GDScript = load("res://scripts/combat/CoverPoint3D.gd")
	if not check(cover_script != null and cover_script.can_instantiate(), "CoverPoint3D.gd must load and compile"):
		return
	var base_script: GDScript = load("res://scripts/combat/ai/RoleAIBase.gd")
	if not check(base_script != null and base_script.can_instantiate(), "RoleAIBase.gd must load and compile"):
		return
	var tanker_script: GDScript = load("res://scripts/combat/ai/TankerAI.gd")
	if not check(tanker_script != null and tanker_script.can_instantiate(), "TankerAI.gd must load and compile"):
		return
	var dps_script: GDScript = load("res://scripts/combat/ai/DamageDealerAI.gd")
	if not check(dps_script != null and dps_script.can_instantiate(), "DamageDealerAI.gd must load and compile"):
		return
	var healer_script: GDScript = load("res://scripts/combat/ai/HealerAI.gd")
	if not check(healer_script != null and healer_script.can_instantiate(), "HealerAI.gd must load and compile"):
		return
	var buffer_script: GDScript = load("res://scripts/combat/ai/BufferAI.gd")
	if not check(buffer_script != null and buffer_script.can_instantiate(), "BufferAI.gd must load and compile"):
		return

	var unit_script: GDScript = load("res://scripts/combat/CombatUnit.gd")
	if not check(unit_script != null and unit_script.can_instantiate(), "CombatUnit.gd must load and compile"):
		return

	# 1. HealerAI.pick_heal_target()
	var healer = healer_script.new()
	check(healer is Node, "HealerAI must extend Node (via RoleAIBase)")
	var heal_allies: Array = [
		{"name": "Shiroko", "hp_percent": 0.85, "is_alive": true},
		{"name": "DeadAlly", "hp_percent": 0.0, "is_alive": false},
		{"name": "ZeroHpAliveFlag", "hp_percent": 0.0, "is_alive": true},
		{"name": "Hoshino", "hp_percent": 0.2, "is_alive": true},
		{"name": "Serika", "hp_percent": 0.5, "is_alive": true},
	]
	var heal_pick: Variant = healer.pick_heal_target(heal_allies)
	check(heal_pick is Dictionary and heal_pick["name"] == "Hoshino", "HealerAI must pick lowest HP living ally 'Hoshino' at 0.2")
	check(healer.pick_heal_target([{"name": "Dead", "hp_percent": 0.0, "is_alive": false}]) == null, "HealerAI must return null when no living allies exist")

	# CombatUnit support for HealerAI
	var hoshino_unit = unit_script.new()
	hoshino_unit.setup(_make_student("hoshino", "Hoshino", 1000, StudentData.CombatRole.TANKER))
	hoshino_unit.take_damage(800) # 20% HP
	var shiroko_unit = unit_script.new()
	shiroko_unit.setup(_make_student("shiroko", "Shiroko", 1000, StudentData.CombatRole.DAMAGE_DEALER))
	shiroko_unit.take_damage(200) # 80% HP
	var dead_unit = unit_script.new()
	dead_unit.setup(_make_student("dead", "Dead", 1000, StudentData.CombatRole.DAMAGE_DEALER))
	dead_unit.take_damage(1000) # Dead
	check(healer.pick_heal_target([dead_unit, shiroko_unit, hoshino_unit]) == hoshino_unit, "HealerAI must pick lowest HP living CombatUnit")

	var healer_eval: Dictionary = healer.evaluate_action(null, heal_allies, [], [])
	check(healer_eval["action"] == "HEAL_ALLY" and healer_eval["target"]["name"] == "Hoshino" and is_equal_approx(float(healer_eval["priority"]), 1.0), "HealerAI.evaluate_action must return HEAL_ALLY")

	# 2. TankerAI.pick_cover_point() & CoverPoint3D lifecycle
	var tanker = tanker_script.new()
	var dict_covers: Array = [
		{"name": "OccupiedFront", "distance_to_enemy": 2.0, "cover_type": "FULL", "is_occupied": true},
		{"name": "HalfCloser", "distance_to_enemy": 3.0, "cover_type": "HALF", "is_occupied": false},
		{"name": "FullBack", "distance_to_enemy": 9.0, "cover_type": "FULL", "is_occupied": false},
		{"name": "FullFront", "distance_to_enemy": 5.0, "cover_type": "FULL", "is_occupied": false},
	]
	var cover_pick: Variant = tanker.pick_cover_point(dict_covers)
	check(cover_pick is Dictionary and is_equal_approx(float(cover_pick["distance_to_enemy"]), 5.0), "TankerAI must prefer unoccupied FULL cover closest to enemy (distance_to_enemy == 5.0)")

	var half_only_covers: Array = [
		{"name": "HalfFar", "distance_to_enemy": 8.0, "cover_type": "HALF", "is_occupied": false},
		{"name": "HalfNear", "distance_to_enemy": 4.0, "cover_type": "HALF", "is_occupied": false},
	]
	var half_pick: Variant = tanker.pick_cover_point(half_only_covers)
	check(half_pick is Dictionary and half_pick["name"] == "HalfNear", "TankerAI must fall back to closest unoccupied HALF cover when no FULL cover is free")
	check(tanker.pick_cover_point([{"distance_to_enemy": 1.0, "cover_type": "FULL", "is_occupied": true}]) == null, "TankerAI must return null when all covers are occupied")

	# CoverPoint3D claim/release lifecycle & direction
	var cover_node = cover_script.new()
	check(cover_node is Marker3D, "CoverPoint3D must extend Marker3D")
	cover_node.cover_type = cover_script.CoverType.FULL
	cover_node.cover_direction = Vector3(0.0, 0.0, -4.0)
	check(cover_node.get_cover_direction().is_equal_approx(Vector3.FORWARD), "CoverPoint3D.get_cover_direction must normalize cover_direction")
	cover_node.cover_direction = Vector3.ZERO
	check(cover_node.get_cover_direction().is_equal_approx(Vector3.FORWARD), "CoverPoint3D.get_cover_direction must fall back to Vector3.FORWARD when zero")

	check(cover_node.claim(hoshino_unit) == true, "First unit claiming unoccupied CoverPoint3D must succeed")
	check(cover_node.is_occupied == true and cover_node.occupant == hoshino_unit, "CoverPoint3D must record occupant after claim")
	check(cover_node.claim(hoshino_unit) == true, "Same unit re-claiming its own CoverPoint3D must succeed")
	check(cover_node.claim(shiroko_unit) == false, "Different unit claiming occupied CoverPoint3D must fail")
	cover_node.release(shiroko_unit)
	check(cover_node.is_occupied == true and cover_node.occupant == hoshino_unit, "Release by non-occupant must not clear CoverPoint3D")
	cover_node.release(hoshino_unit)
	check(cover_node.is_occupied == false and cover_node.occupant == null, "Release by occupant must clear CoverPoint3D")
	cover_node.claim(shiroko_unit)
	cover_node.release()
	check(cover_node.is_occupied == false and cover_node.occupant == null, "Release with null argument must force-clear CoverPoint3D")

	# CoverPoint3D node selection in TankerAI
	var c_full_far = cover_script.new()
	c_full_far.cover_type = cover_script.CoverType.FULL
	c_full_far.position = Vector3(0.0, 0.0, 2.0)
	var c_full_near = cover_script.new()
	c_full_near.cover_type = cover_script.CoverType.FULL
	c_full_near.position = Vector3(0.0, 0.0, -5.0)
	var enemy_node = unit_script.new()
	enemy_node.setup(_make_student("enemy1", "Enemy", 500, StudentData.CombatRole.DAMAGE_DEALER))
	enemy_node.position = Vector3(0.0, 0.0, -10.0)
	var tanker_eval_cover: Dictionary = tanker.evaluate_action(hoshino_unit, [], [enemy_node], [c_full_far, c_full_near])
	check(tanker_eval_cover["action"] == "TAKE_COVER_AND_TAUNT" and tanker_eval_cover["target"] == c_full_near and is_equal_approx(float(tanker_eval_cover["priority"]), 1.0), "TankerAI.evaluate_action must choose nearest FULL CoverPoint3D to enemy")

	var tanker_eval_engage: Dictionary = tanker.evaluate_action(hoshino_unit, [], [enemy_node], [])
	check(tanker_eval_engage["action"] == "TAUNT_ENGAGE" and tanker_eval_engage["target"] == enemy_node and is_equal_approx(float(tanker_eval_engage["priority"]), 0.9), "TankerAI.evaluate_action must fall back to TAUNT_ENGAGE when no cover is free")

	# 3. DamageDealerAI.pick_attack_target()
	var dps = dps_script.new()
	var enemies_with_ping: Array = [
		{"name": "Grunt", "hp_percent": 0.15, "is_alive": true, "is_pinged": false},
		{"name": "Elite", "hp_percent": 0.80, "is_alive": true, "is_pinged": true},
		{"name": "DeadPinged", "hp_percent": 0.0, "is_alive": false, "is_pinged": true},
	]
	var dps_pick_pinged: Variant = dps.pick_attack_target(enemies_with_ping)
	check(dps_pick_pinged is Dictionary and dps_pick_pinged["name"] == "Elite", "DamageDealerAI must prioritize living pinged enemy 'Elite' over lower-HP unpinged 'Grunt'")

	var enemies_unpinged: Array = [
		{"name": "Heavy", "hp_percent": 0.90, "is_alive": true, "is_pinged": false},
		{"name": "Grunt", "hp_percent": 0.25, "is_alive": true, "is_pinged": false},
		{"name": "Dead", "hp_percent": 0.0, "is_alive": false, "is_pinged": false},
	]
	var dps_pick_low: Variant = dps.pick_attack_target(enemies_unpinged)
	check(dps_pick_low is Dictionary and dps_pick_low["name"] == "Grunt", "DamageDealerAI must pick lowest-HP living enemy when none is pinged")
	check(dps.pick_attack_target([]) == null, "DamageDealerAI must return null when no enemies exist")
	var dps_idle: Dictionary = dps.evaluate_action(shiroko_unit, [], [], [])
	check(dps_idle["action"] == "IDLE" and dps_idle["target"] == null, "DamageDealerAI.evaluate_action must return IDLE when no living enemies exist")
	var dps_attack: Dictionary = dps.evaluate_action(shiroko_unit, [], enemies_with_ping, [])
	check(dps_attack["action"] == "ATTACK_TARGET" and dps_attack["target"]["name"] == "Elite" and is_equal_approx(float(dps_attack["priority"]), 1.0), "DamageDealerAI.evaluate_action must return ATTACK_TARGET")

	# 4. BufferAI.calculate_optimal_position()
	var buffer = buffer_script.new()
	var ally_positions: Array = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(6.0, 0.0, 0.0),
		Vector3(3.0, 0.0, 9.0),
	]
	var centroid: Vector3 = buffer.calculate_optimal_position(ally_positions, 5.0)
	check(centroid.is_equal_approx(Vector3(3.0, 0.0, 3.0)), "BufferAI.calculate_optimal_position must return centroid (3, 0, 3), got %s" % str(centroid))
	check(buffer.calculate_optimal_position([], 5.0).is_equal_approx(Vector3.ZERO), "BufferAI.calculate_optimal_position must return Vector3.ZERO for empty array")

	hoshino_unit.position = Vector3(2.0, 0.0, 0.0)
	shiroko_unit.position = Vector3(4.0, 0.0, 6.0)
	var buf_eval: Dictionary = buffer.evaluate_action(null, [hoshino_unit, shiroko_unit, dead_unit], [], [])
	check(buf_eval["action"] == "POSITION_AND_BUFF" and buf_eval["target"].is_equal_approx(Vector3(3.0, 0.0, 3.0)) and is_equal_approx(float(buf_eval["priority"]), 0.85), "BufferAI.evaluate_action must compute centroid of living allies")

	# 5. RoleAIBase yield & emergency override
	var role_base = base_script.new()
	check(role_base.should_yield_to_player(null) == false, "should_yield_to_player(null) must return false")
	check(role_base.should_yield_to_player_dict({"has_player_order": true, "hp_percent": 0.50}) == true, "Dict helper must yield when has_player_order == true and HP >= 10%")
	check(role_base.should_yield_to_player_dict({"has_player_order": false, "hp_percent": 0.50}) == false, "Dict helper must not yield when has_player_order == false")
	check(role_base.should_yield_to_player_dict({"has_player_order": true, "hp_percent": 0.10}) == true, "Dict helper must still yield at exactly 10% HP")
	check(role_base.should_yield_to_player_dict({"has_player_order": true, "hp_percent": 0.09}) == false, "Dict helper must override player order below 10% HP")

	var ordered_unit = unit_script.new()
	ordered_unit.setup(_make_student("yuuka", "Yuuka", 1000, StudentData.CombatRole.TANKER))
	ordered_unit.receive_move_order(Vector3(5.0, 0.0, 5.0))
	check(role_base.should_yield_to_player(ordered_unit) == true, "RoleAIBase must yield when CombatUnit has active player order and HP >= 10%")
	var yield_eval: Dictionary = dps.evaluate_action(ordered_unit, [], enemies_with_ping, [])
	check(yield_eval["action"] == "YIELD_TO_PLAYER" and yield_eval["target"] == null and is_equal_approx(float(yield_eval["priority"]), 0.0), "Subclass evaluate_action must yield when player order is active")

	# Drop to < 10% HP -> emergency override resumes AI control
	ordered_unit.take_damage(910) # 1000 -> 90 HP (9%)
	check(role_base.should_yield_to_player(ordered_unit) == false, "Emergency override (HP < 10%) must resume AI control")
	var emergency_eval: Dictionary = dps.evaluate_action(ordered_unit, [], enemies_with_ping, [])
	check(emergency_eval["action"] == "ATTACK_TARGET", "After emergency override, Role AI must evaluate its combat action")

	# Cleanup
	healer.free()
	tanker.free()
	dps.free()
	buffer.free()
	role_base.free()
	hoshino_unit.free()
	shiroko_unit.free()
	dead_unit.free()
	enemy_node.free()
	ordered_unit.free()
	cover_node.free()
	c_full_far.free()
	c_full_near.free()

	_completed = true
