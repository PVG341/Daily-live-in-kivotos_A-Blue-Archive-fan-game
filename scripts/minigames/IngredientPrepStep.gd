# scripts/minigames/IngredientPrepStep.gd
class_name IngredientPrepStep
extends RefCounted

const VALID_PREP_TYPES: Array[String] = ["CHOP", "SLICE", "STIR", "SEASON", "KNEAD"]

var prep_type: String = "CHOP"
var target_count: int = 5
var current_count: int = 0
var action_scores: Array[float] = []

## Records one relaxed-pace prep action with clamped precision in [0.0, 1.0].
func perform_action(precision: float = 0.9) -> float:
	var score: float = clampf(precision, 0.0, 1.0)
	if current_count < target_count:
		current_count += 1
		action_scores.append(score)
	return score

## Returns true once current_count reaches target_count.
func is_complete() -> bool:
	return current_count >= target_count

## Returns the mean of recorded action_scores, or 0.0 if none recorded.
func get_average_quality() -> float:
	if action_scores.is_empty():
		return 0.0
	var total: float = 0.0
	for score in action_scores:
		total += score
	return total / float(action_scores.size())

## Resets progress and recorded action scores for reuse.
func reset() -> void:
	current_count = 0
	action_scores.clear()
