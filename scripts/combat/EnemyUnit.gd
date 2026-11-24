# scripts/combat/EnemyUnit.gd
class_name EnemyUnit
extends CombatUnit

@export var enemy_type: String = "GRUNT"
@export var behavior: String = "AGGRESSIVE"
@export var loot_table: Array[Dictionary] = []
@export var detection_radius: float = 28.0
@export var is_alerted: bool = true

var patrol_origin: Vector3 = Vector3.ZERO
var dropped_loot: Array[Dictionary] = []

## Alerts this enemy so it enters combat immediately.
func alert() -> void:
	is_alerted = true

## Marks enemy alerted when taking damage before delegating to CombatUnit.take_damage().
func take_damage(amount: int, source: Object = null) -> int:
	is_alerted = true
	return super.take_damage(amount, source)

## Rolls each entry in loot_table against its drop chance, updates dropped_loot, and returns it.
func roll_loot(rng_roll: float = -1.0) -> Array[Dictionary]:
	dropped_loot.clear()
	for entry in loot_table:
		var chance: float = float(entry.get("chance", 0.0))
		if chance <= 0.0:
			continue
		var roll: float = rng_roll if rng_roll >= 0.0 else randf()
		if roll <= chance:
			dropped_loot.append(entry.duplicate(true))
	return dropped_loot

## Rolls loot on death before delegating to CombatUnit.die().
func die() -> void:
	if not is_alive:
		return
	roll_loot()
	super.die()
