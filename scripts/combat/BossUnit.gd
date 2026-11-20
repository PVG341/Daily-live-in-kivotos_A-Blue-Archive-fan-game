# scripts/combat/BossUnit.gd
class_name BossUnit
extends EnemyUnit

signal phase_changed(new_phase: int)

var current_phase: int = 1
var phase_thresholds: Array[float] = [0.7, 0.3]

func _init() -> void:
	super._init()
	enemy_type = "BOSS"
	max_hp = 10000
	current_hp = 10000

## Returns the boss's current HP as a normalized ratio in [0.0, 1.0].
func get_hp_ratio() -> float:
	return clampf(float(current_hp) / float(maxi(1, max_hp)), 0.0, 1.0)

## Evaluates phase transitions from current HP ratio; phase only increases and emits phase_changed.
func update_phase_from_hp() -> int:
	var hp_ratio: float = get_hp_ratio()
	var phase2_threshold: float = phase_thresholds[0] if phase_thresholds.size() > 0 else 0.7
	var phase3_threshold: float = phase_thresholds[1] if phase_thresholds.size() > 1 else 0.3

	var target_phase: int = 1
	if hp_ratio <= phase3_threshold:
		target_phase = 3
	elif hp_ratio <= phase2_threshold:
		target_phase = 2

	if target_phase > current_phase:
		current_phase = target_phase
		phase_changed.emit(current_phase)
	return current_phase

## Applies damage via EnemyUnit/CombatUnit and updates boss phase immediately while alive.
func take_damage(amount: int, source: Object = null) -> int:
	var damage_taken: int = super.take_damage(amount, source)
	if is_alive:
		update_phase_from_hp()
	return damage_taken

## Returns the telegraphed attack pattern configuration for the active boss phase.
func select_boss_pattern() -> Dictionary:
	match current_phase:
		2:
			return {
				"pattern_id": "missile_barrage",
				"phase": 2,
				"aoe_radius": 4.0,
				"warn_duration": 1.4,
				"damage": int(round(float(atk) * 1.35)),
			}
		3:
			return {
				"pattern_id": "overdrive_annihilation",
				"phase": 3,
				"aoe_radius": 5.5,
				"warn_duration": 1.1,
				"damage": int(round(float(atk) * 1.75)),
			}
		_:
			return {
				"pattern_id": "sweeping_fire",
				"phase": 1,
				"aoe_radius": 3.0,
				"warn_duration": 1.8,
				"damage": atk,
			}
