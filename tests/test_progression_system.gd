# tests/test_progression_system.gd
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

	print("PASS: test_progression_system")
	quit(0)
	return true

func _run_tests() -> void:
	var prog_script: GDScript = load("res://scripts/core/ProgressionManager.gd")
	if not check(prog_script != null and prog_script.can_instantiate(), "ProgressionManager.gd must load and compile"):
		return

	var pm = prog_script.new()
	check(pm is Node, "ProgressionManager must extend Node")
	check(is_equal_approx(pm.MAX_PERMANENT_STAT_BONUS, 0.10), "MAX_PERMANENT_STAT_BONUS must be 0.10")

	# 1. Baseline normal difficulty balance (bond 1, upgrade tier 0 -> 1.0)
	var baseline: float = pm.get_permanent_stat_multiplier("shiroko", 1, 0)
	check(is_equal_approx(baseline, 1.0), "Baseline multiplier at bond 1, tier 0 must be 1.0")

	var below_baseline: float = pm.get_permanent_stat_multiplier("shiroko", 0, -3)
	check(is_equal_approx(below_baseline, 1.0), "Sub-baseline inputs must clamp to 1.0")

	# Intermediate progression check
	var mid_mult: float = pm.get_permanent_stat_multiplier("shiroko", 21, 2)
	# (21 - 1) * 0.0005 = 0.01, 2 * 0.01 = 0.02 -> 1.03
	check(is_equal_approx(mid_mult, 1.03), "Multiplier at bond 21, tier 2 must be 1.03")

	# 2. Extreme progression strictly capped at 1.10 (+10% ceiling)
	var extreme_mult: float = pm.get_permanent_stat_multiplier("shiroko", 100, 99)
	check(extreme_mult <= 1.1001 and extreme_mult >= 1.0999, "Extreme progression must be strictly capped at 1.10")

	var super_extreme: float = pm.get_permanent_stat_multiplier("shiroko", 999, 999)
	check(super_extreme <= 1.1001 and super_extreme >= 1.0999, "Arbitrarily large inputs must remain capped at 1.10")

	# 3. Horizontal unlocks (roguelike cards and skill variants)
	check(not pm.unlock_horizontal_option("shiroko", "ROGUELIKE_CARD", ""), "Empty option_id must return false")
	check(not pm.unlock_horizontal_option("", "SKILL_VARIANT", "missile_pod_mk2"), "Empty student_id for SKILL_VARIANT must return false")
	check(not pm.unlock_horizontal_option("shiroko", "UNKNOWN_TYPE", "some_id"), "Unknown option_type must return false")

	check(pm.unlock_horizontal_option("shiroko", "ROGUELIKE_CARD", "drone_overclock"), "Unlocking ROGUELIKE_CARD must return true")
	check(pm.unlock_horizontal_option("shiroko", "ROGUELIKE_CARD", "drone_overclock"), "Re-unlocking same card must return true without duplicating")
	var cards: Array[String] = pm.get_unlocked_roguelike_cards()
	check(cards.size() == 1 and cards.has("drone_overclock"), "get_unlocked_roguelike_cards must contain drone_overclock once")

	# Duplicate safety: mutating returned array must not affect internal state
	cards.append("injected_card")
	check(pm.get_unlocked_roguelike_cards().size() == 1, "get_unlocked_roguelike_cards must return a duplicate")

	check(pm.unlock_horizontal_option("shiroko", "SKILL_VARIANT", "missile_pod_mk2"), "Unlocking SKILL_VARIANT must return true")
	check(pm.unlock_horizontal_option("shiroko", "SKILL_VARIANT", "missile_pod_mk2"), "Re-unlocking same skill variant must return true without duplicating")
	var variants: Array[String] = pm.get_unlocked_skill_variants("shiroko")
	check(variants.size() == 1 and variants.has("missile_pod_mk2"), "get_unlocked_skill_variants('shiroko') must contain missile_pod_mk2 once")
	check(pm.get_unlocked_skill_variants("hoshino").is_empty(), "Other students must not receive shiroko's skill variants")

	variants.append("injected_variant")
	check(pm.get_unlocked_skill_variants("shiroko").size() == 1, "get_unlocked_skill_variants must return a duplicate")

	# 4. Challenge modifiers (Hades-style optional heat/pact system)
	check(is_equal_approx(pm.get_challenge_reward_multiplier(), 1.0), "Default challenge reward multiplier must be 1.0")

	pm.set_challenge_modifiers(["ENEMY_SPEED_UP", "NO_REST_ROOMS"])
	var active_mult: float = pm.get_challenge_reward_multiplier()
	check(active_mult > 1.0 and is_equal_approx(active_mult, 1.40), "ENEMY_SPEED_UP (0.15) + NO_REST_ROOMS (0.25) must yield 1.40")
	check(pm.active_challenge_modifiers.size() == 2, "active_challenge_modifiers must store the 2 valid modifiers")

	# Filter duplicates and unknown modifiers
	pm.set_challenge_modifiers(["ENEMY_SPEED_UP", "ENEMY_SPEED_UP", "INVALID_MOD", "DOUBLE_BOSS_PHASE"])
	check(pm.active_challenge_modifiers.size() == 2, "Duplicate and invalid challenge modifiers must be filtered")
	check(is_equal_approx(pm.get_challenge_reward_multiplier(), 1.50), "ENEMY_SPEED_UP (0.15) + DOUBLE_BOSS_PHASE (0.35) must yield 1.50")

	# All three modifiers active
	pm.set_challenge_modifiers(["ENEMY_SPEED_UP", "NO_REST_ROOMS", "DOUBLE_BOSS_PHASE"])
	check(pm.active_challenge_modifiers.size() == 3, "All 3 valid modifiers must be stored")
	check(is_equal_approx(pm.get_challenge_reward_multiplier(), 1.75), "All 3 modifiers must yield 1.75")

	# Reset to empty
	pm.set_challenge_modifiers([])
	check(pm.active_challenge_modifiers.is_empty(), "Clearing challenge modifiers must empty active_challenge_modifiers")
	check(is_equal_approx(pm.get_challenge_reward_multiplier(), 1.0), "Resetting challenge modifiers must restore 1.0 multiplier")

	pm.free()
	_completed = true
