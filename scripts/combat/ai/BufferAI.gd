# scripts/combat/ai/BufferAI.gd
class_name BufferAI
extends RoleAIBase

## Computes the centroid of allied positions for optimal buff aura coverage.
func calculate_optimal_position(ally_positions: Array, _aura_radius: float = 5.0) -> Vector3:
	var sum: Vector3 = Vector3.ZERO
	var count: int = 0

	for entry in ally_positions:
		var pos: Variant = _get_world_position(entry)
		if pos is Vector3:
			sum += pos as Vector3
			count += 1

	if count == 0:
		return Vector3.ZERO
	return sum / float(count)

## Positions the buffer at the centroid of living allies to apply team buffs unless yielding to player order.
func evaluate_action(owner_unit: Object, allies: Array, _enemies: Array, _covers: Array) -> Dictionary:
	if owner_unit != null and not _is_unit_alive(owner_unit):
		return _make_action("IDLE", null, 0.0)
	if should_yield_to_player(owner_unit):
		return _yield_action()

	var living_positions: Array = []
	for ally in allies:
		if ally is Vector3:
			living_positions.append(ally)
		elif _is_unit_alive(ally):
			var pos: Variant = _get_world_position(ally)
			if pos is Vector3:
				living_positions.append(pos)

	var optimal_pos: Vector3 = calculate_optimal_position(living_positions)
	return {"action": "POSITION_AND_BUFF", "target": optimal_pos, "priority": 0.85}
