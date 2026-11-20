# scripts/core/ProgressionManager.gd
class_name ProgressionManager
extends Node

const MAX_PERMANENT_STAT_BONUS: float = 0.10
const CHALLENGE_MODIFIER_WEIGHTS: Dictionary = {
	"ENEMY_SPEED_UP": 0.15,
	"NO_REST_ROOMS": 0.25,
	"DOUBLE_BOSS_PHASE": 0.35,
}

var unlocked_roguelike_cards: Array[String] = []
var unlocked_skill_variants: Dictionary = {} # student_id -> Array[String]
var active_challenge_modifiers: Array[String] = []

## Computes the permanent stat multiplier capped at +10% (1.10) so skill and roguelike cards dominate.
func get_permanent_stat_multiplier(_student_id: String, bond_level: int = 1, upgrade_tier: int = 0) -> float:
	var bond_bonus: float = float(maxi(0, bond_level - 1)) * 0.0005
	var tier_bonus: float = float(maxi(0, upgrade_tier)) * 0.01
	return clampf(1.0 + bond_bonus + tier_bonus, 1.0, 1.0 + MAX_PERMANENT_STAT_BONUS)

## Unlocks a horizontal option ("ROGUELIKE_CARD" or "SKILL_VARIANT") without duplicates.
func unlock_horizontal_option(student_id: String, option_type: String, option_id: String) -> bool:
	if option_id.is_empty():
		return false

	if option_type == "ROGUELIKE_CARD":
		if not unlocked_roguelike_cards.has(option_id):
			unlocked_roguelike_cards.append(option_id)
		return true

	if option_type == "SKILL_VARIANT":
		if student_id.is_empty():
			return false
		if not unlocked_skill_variants.has(student_id):
			var initial_variants: Array[String] = []
			unlocked_skill_variants[student_id] = initial_variants
		var variants: Array[String] = unlocked_skill_variants[student_id]
		if not variants.has(option_id):
			variants.append(option_id)
		return true

	return false

## Returns a copy of all unlocked roguelike card IDs.
func get_unlocked_roguelike_cards() -> Array[String]:
	return unlocked_roguelike_cards.duplicate()

## Returns a copy of all unlocked skill variant IDs for the given student.
func get_unlocked_skill_variants(student_id: String) -> Array[String]:
	var variants: Array[String] = []
	if unlocked_skill_variants.has(student_id):
		for item in unlocked_skill_variants[student_id]:
			variants.append(str(item))
	return variants

## Stores unique valid challenge modifier IDs from CHALLENGE_MODIFIER_WEIGHTS.
func set_challenge_modifiers(modifiers: Array) -> void:
	active_challenge_modifiers.clear()
	for mod in modifiers:
		var mod_id: String = str(mod)
		if CHALLENGE_MODIFIER_WEIGHTS.has(mod_id) and not active_challenge_modifiers.has(mod_id):
			active_challenge_modifiers.append(mod_id)

## Returns 1.0 plus the sum of active challenge modifier reward weights.
func get_challenge_reward_multiplier() -> float:
	var bonus: float = 0.0
	for mod_id in active_challenge_modifiers:
		bonus += float(CHALLENGE_MODIFIER_WEIGHTS.get(mod_id, 0.0))
	return 1.0 + bonus
