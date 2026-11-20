# scripts/combat/ai/DamageDealerAI.gd
class_name DamageDealerAI
extends RoleAIBase

## Selects a living enemy target, prioritizing pinged enemies first and lowest HP otherwise.
func pick_attack_target(enemies: Array) -> Variant:
	var best_target: Variant = null
	var best_pinged: bool = false
	var best_hp: float = INF

	for enemy in enemies:
		if not _is_unit_alive(enemy):
			continue
		var is_pinged: bool = _is_unit_pinged(enemy)
		var hp_val: float = _get_unit_hp_percent(enemy)

		if best_target == null:
			best_target = enemy
			best_pinged = is_pinged
			best_hp = hp_val
			continue

		if is_pinged and not best_pinged:
			best_target = enemy
			best_pinged = true
			best_hp = hp_val
		elif is_pinged == best_pinged and hp_val < best_hp:
			best_target = enemy
			best_hp = hp_val

	return best_target

## Evaluates DPS action by focusing pinged or weakened living enemies unless yielding to player order.
func evaluate_action(owner_unit: Object, _allies: Array, enemies: Array, _covers: Array) -> Dictionary:
	if should_yield_to_player(owner_unit):
		return _yield_action()

	var target: Variant = pick_attack_target(enemies)
	if target == null:
		return _idle_action()
	return {"action": "ATTACK_TARGET", "target": target, "priority": 1.0}
