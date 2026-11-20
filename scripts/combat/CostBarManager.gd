# scripts/combat/CostBarManager.gd
class_name CostBarManager
extends RefCounted

var current_cost: float = 0.0
var max_cost: float = 10.0
var generation_rate: float = 0.5

## Accumulates EX cost over delta seconds, clamped to [0, max_cost], and returns current_cost.
func accumulate(delta: float) -> float:
	if delta > 0.0:
		current_cost = clampf(current_cost + generation_rate * delta, 0.0, max_cost)
	return current_cost

## Spends the given cost amount if non-negative and affordable; returns true on success.
func spend(amount: float) -> bool:
	if amount < 0.0 or current_cost < amount:
		return false
	current_cost -= amount
	return true

## Returns the normalized [0, 1] fill ratio of the cost bar.
func get_fill_percent() -> float:
	return clampf(current_cost / maxf(0.001, max_cost), 0.0, 1.0)
