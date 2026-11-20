# tests/test_ex_skill.gd
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

	print("PASS: test_ex_skill")
	quit(0)
	return true

func _make_skill(id: String, skill_name: String, cost: int, cooldown: float, aoe: float = 2.0, effect: String = "DAMAGE") -> SkillData:
	var s := SkillData.new()
	s.id = id
	s.name = skill_name
	s.cost = cost
	s.cooldown = cooldown
	s.aoe_radius = aoe
	s.effect_type = effect
	return s

func _make_student(id: String, student_name: String, skills: Array[SkillData]) -> StudentData:
	var st := StudentData.new()
	st.id = id
	st.student_name = student_name
	st.squad_slot = StudentData.SquadSlot.SPECIAL
	st.skills = skills
	return st

func _run_tests() -> void:
	# 1. Load scripts
	var cost_bar_script: GDScript = load("res://scripts/combat/CostBarManager.gd")
	if not check(cost_bar_script != null and cost_bar_script.can_instantiate(), "CostBarManager.gd must load and compile"):
		return
	var ex_sys_script: GDScript = load("res://scripts/combat/EXSkillSystem.gd")
	if not check(ex_sys_script != null and ex_sys_script.can_instantiate(), "EXSkillSystem.gd must load and compile"):
		return
	var overlay_script: GDScript = load("res://scripts/combat/SkillTargetingOverlay.gd")
	if not check(overlay_script != null and overlay_script.can_instantiate(), "SkillTargetingOverlay.gd must load and compile"):
		return

	# 2. CostBarManager tests
	var bar = cost_bar_script.new()
	check(bar is RefCounted, "CostBarManager must extend RefCounted")
	check(is_equal_approx(bar.current_cost, 0.0), "CostBarManager initial current_cost must be 0.0")
	check(is_equal_approx(bar.max_cost, 10.0), "CostBarManager default max_cost must be 10.0")
	check(is_equal_approx(bar.generation_rate, 0.5), "CostBarManager default generation_rate must be 0.5")
	check(is_equal_approx(bar.get_fill_percent(), 0.0), "Initial fill percent must be 0.0")

	var after_acc: float = bar.accumulate(5.0)
	check(is_equal_approx(after_acc, 2.5) and is_equal_approx(bar.current_cost, 2.5), "accumulate(5.0) with rate 0.5 must yield 2.5")
	check(is_equal_approx(bar.get_fill_percent(), 0.25), "fill percent at 2.5/10.0 must be 0.25")

	bar.accumulate(-2.0)
	check(is_equal_approx(bar.current_cost, 2.5), "accumulate(-2.0) must not change current_cost")

	var clamped_acc: float = bar.accumulate(100.0)
	check(is_equal_approx(clamped_acc, 10.0) and is_equal_approx(bar.current_cost, 10.0), "accumulate(100.0) must clamp at max_cost 10.0")
	check(is_equal_approx(bar.get_fill_percent(), 1.0), "fill percent at max_cost must be 1.0")

	bar.current_cost = 4.0
	check(is_equal_approx(bar.get_fill_percent(), 0.4), "fill percent at 4.0/10.0 must be 0.4")
	check(bar.spend(3.0) == true, "spend(3.0) with 4.0 available must succeed")
	check(is_equal_approx(bar.current_cost, 1.0), "spend(3.0) from 4.0 must leave 1.0")
	check(bar.spend(5.0) == false, "spend(5.0) with 1.0 available must fail")
	check(is_equal_approx(bar.current_cost, 1.0), "failed spend must leave current_cost unchanged")
	check(bar.spend(-1.0) == false, "spend(-1.0) must fail")
	check(is_equal_approx(bar.current_cost, 1.0), "negative spend must leave current_cost unchanged")

	# 3. EXSkillSystem tests
	var ex_sys = ex_sys_script.new()
	check(ex_sys is Node, "EXSkillSystem must extend Node")
	check(ex_sys.MAX_SPECIAL_SLOTS == 2, "MAX_SPECIAL_SLOTS must be 2")
	check(ex_sys.cost_bar != null, "EXSkillSystem must initialize cost_bar in _init()")

	var sk_missile := _make_skill("sk_missile", "Missile Barrage", 3, 8.0)
	var sk_heal := _make_skill("sk_heal", "Emergency Heal", 4, 10.0, 4.0, "HEAL")
	var sk_buff := _make_skill("sk_buff", "Tactical Cheer", 2, 6.0, 5.0, "BUFF")
	var sk_empty := _make_skill("", "Invalid", 1, 1.0)

	var sp1 := _make_student("sp_hibiki", "Hibiki", [sk_missile])
	var sp2 := _make_student("sp_serina", "Serina", [sk_heal])
	var sp3 := _make_student("sp_kotama", "Kotama", [sk_buff])

	ex_sys.set_special_students([sp1, sp2, sp3])
	check(ex_sys.special_slots.size() == 2, "set_special_students must cap special_slots at MAX_SPECIAL_SLOTS (2)")
	check(ex_sys.special_slots[0] == sp1 and ex_sys.special_slots[1] == sp2, "special_slots must retain first 2 Special students")
	check(ex_sys.registered_skills.size() == 2, "set_special_students must register skills of slotted students only")

	ex_sys.register_skill(null)
	ex_sys.register_skill(sk_empty)
	ex_sys.register_skill(sk_missile) # duplicate
	check(ex_sys.registered_skills.size() == 2, "register_skill must ignore null, empty id, and duplicates")

	ex_sys.register_skill(sk_buff)
	check(ex_sys.registered_skills.size() == 3, "register_skill must add new valid skill")

	ex_sys.cost_bar.current_cost = 3.0
	var avail_at_3: Array[SkillData] = ex_sys.get_available_skills()
	check(avail_at_3.size() == 2 and avail_at_3.has(sk_missile) and avail_at_3.has(sk_buff) and not avail_at_3.has(sk_heal), "get_available_skills at cost 3.0 must return sk_missile and sk_buff only")

	var activated_events: Array = []
	ex_sys.skill_activated.connect(func(sk: SkillData, pos: Vector3): activated_events.append({"skill": sk, "pos": pos}))

	check(ex_sys.activate_skill(sk_heal, Vector3.ZERO) == false, "activate_skill must fail when cost is insufficient")
	check(activated_events.is_empty(), "failed activate_skill must not emit skill_activated")
	check(ex_sys.is_skill_on_cooldown(sk_heal) == false, "failed activate_skill must not put skill on cooldown")

	var target_pos := Vector3(10.0, 0.0, -5.0)
	check(ex_sys.activate_skill(sk_missile, target_pos) == true, "activate_skill(sk_missile) with cost 3.0 must succeed")
	check(is_equal_approx(ex_sys.cost_bar.current_cost, 0.0), "activate_skill must deduct skill.cost from cost_bar")
	check(ex_sys.is_skill_on_cooldown(sk_missile) == true, "activated skill must be on cooldown")
	check(activated_events.size() == 1 and activated_events[0]["skill"] == sk_missile and activated_events[0]["pos"].is_equal_approx(target_pos), "activate_skill must emit skill_activated with skill and target_position")

	# Refill cost; skill must still be blocked by cooldown
	ex_sys.cost_bar.current_cost = 10.0
	check(ex_sys.activate_skill(sk_missile, target_pos) == false, "activate_skill must fail while skill is on cooldown")
	check(is_equal_approx(ex_sys.cost_bar.current_cost, 10.0), "blocked activation on cooldown must not spend cost")
	check(not ex_sys.get_available_skills().has(sk_missile), "get_available_skills must exclude skills on cooldown")

	ex_sys.tick_cooldowns(5.0)
	check(ex_sys.is_skill_on_cooldown(sk_missile) == true, "sk_missile with 8.0s cooldown must still be on cooldown after 5.0s")
	ex_sys.tick_cooldowns(3.0)
	check(ex_sys.is_skill_on_cooldown(sk_missile) == false, "sk_missile must come off cooldown after 8.0s total")
	check(ex_sys.get_available_skills().has(sk_missile), "sk_missile must appear in get_available_skills once cooldown expires")

	# 4. SkillTargetingOverlay tests
	var overlay = overlay_script.new()
	check(overlay is Control, "SkillTargetingOverlay must extend Control")
	check(overlay.is_targeting == false and overlay.active_skill == null, "Initial overlay must not be targeting")

	overlay.begin_targeting(null)
	check(overlay.is_targeting == false and overlay.active_skill == null, "begin_targeting(null) must be a no-op")

	var confirmed_events: Array = []
	var cancelled_count := [0]
	overlay.target_confirmed.connect(func(sk: SkillData, pos: Vector3): confirmed_events.append({"skill": sk, "pos": pos}))
	overlay.target_cancelled.connect(func(): cancelled_count[0] += 1)

	overlay.begin_targeting(sk_missile)
	check(overlay.is_targeting == true and overlay.active_skill == sk_missile and overlay.visible == true, "begin_targeting must set active_skill, is_targeting=true, visible=true")

	var confirmed_pos: Vector3 = overlay.confirm_target(Vector2(12.5, -4.0), null, 0.5)
	var expected_pos := Vector3(12.5, 0.5, -4.0)
	check(confirmed_pos.is_equal_approx(expected_pos), "confirm_target without camera must return fallback ground-plane position")
	check(overlay.preview_world_position.is_equal_approx(expected_pos), "confirm_target must store preview_world_position")
	check(overlay.is_targeting == false, "confirm_target must reset is_targeting to false")
	check(confirmed_events.size() == 1 and confirmed_events[0]["skill"] == sk_missile and confirmed_events[0]["pos"].is_equal_approx(expected_pos), "confirm_target must emit target_confirmed")

	# Camera3D projection test
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 10.0, 0.0), Vector3.ZERO, Vector3.FORWARD)
	var vp_center: Vector2 = root.get_visible_rect().size * 0.5
	overlay.begin_targeting(sk_missile)
	var cam_pos: Vector3 = overlay.confirm_target(vp_center, cam, 2.0)
	check(cam_pos.is_equal_approx(Vector3(0.0, 2.0, 0.0)), "confirm_target with straight-down Camera3D at center must hit (0, 2, 0)")
	cam.queue_free()

	overlay.begin_targeting(sk_heal)
	check(overlay.is_targeting == true and overlay.active_skill == sk_heal, "second begin_targeting must set active_skill to sk_heal")
	overlay.cancel_targeting()
	check(overlay.is_targeting == false and overlay.active_skill == null and overlay.visible == false, "cancel_targeting must reset state and hide overlay")
	check(cancelled_count[0] == 1, "cancel_targeting must emit target_cancelled")

	# Cleanup
	ex_sys.free()
	overlay.free()

	_completed = true
