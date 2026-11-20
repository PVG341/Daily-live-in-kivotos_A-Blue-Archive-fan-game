# scripts/combat/ai/HealerAI.gd
class_name HealerAI
extends RoleAIBase

## Selects the living ally with the lowest HP percentage, or null if none are alive.
func pick_heal_target(allies: Array) -> Variant:
	var best_ally: Variant = null
	var best_hp: float = INF

	for ally in allies:
		if not _is_unit_alive(ally):
			continue
		var hp_val: float = _get_unit_hp_percent(ally)
		if best_ally == null or hp_val < best_hp:
			best_ally = ally
			best_hp = hp_val

	return best_ally

## Evaluates healer action by targeting the most injured living ally unless yielding to player order.
func evaluate_action(owner_unit: Object, allies: Array, _enemies: Array, _covers: Array) -> Dictionary:
	if owner_unit != null and not _is_unit_alive(owner_unit):
		return _make_action("IDLE", null, 0.0)
	if should_yield_to_player(owner_unit):
		return _yield_action()

	var target: Variant = pick_heal_target(allies)
	if target == null:
		return _idle_action()
	return {"action": "HEAL_ALLY", "target": target, "priority": 1.0}
