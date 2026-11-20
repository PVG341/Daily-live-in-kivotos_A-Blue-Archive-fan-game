# scripts/minigames/CookingManager.gd
class_name CookingManager
extends RefCounted

const IngredientPrepStepScript := preload("res://scripts/minigames/IngredientPrepStep.gd")

const SWEET_SPOT_CENTER: float = 0.5
const QUALITY_PERFECT_THRESHOLD: float = 0.85
const QUALITY_GOOD_THRESHOLD: float = 0.60

var active_recipe: RecipeData = null
var prep_steps: Array[IngredientPrepStepScript] = []
var prep_scores: Array[float] = []
var indicator_time: float = 0.0
var indicator_speed: float = 2.0

## Returns true when recipe is valid and inventory meets all required ingredient counts.
func can_cook(recipe: RecipeData, inventory: Dictionary) -> bool:
	if recipe == null:
		return false
	for item_id in recipe.ingredients:
		var required: int = int(recipe.ingredients[item_id])
		if int(inventory.get(item_id, 0)) < required:
			return false
	return true

## Validates ingredients, deducts from inventory when provided, and resets cooking state.
func start_recipe(recipe: RecipeData, inventory: Dictionary = {}) -> bool:
	if not can_cook(recipe, inventory):
		return false
	if not inventory.is_empty():
		for item_id in recipe.ingredients:
			var required: int = int(recipe.ingredients[item_id])
			if required > 0 and inventory.has(item_id):
				inventory[item_id] = maxi(0, int(inventory[item_id]) - required)
	active_recipe = recipe
	prep_scores.clear()
	indicator_time = 0.0
	return true

## Records a clamped [0.0, 1.0] prep step quality score.
func complete_prep_step(step_index: int, quality: float) -> void:
	var clamped: float = clampf(quality, 0.0, 1.0)
	if step_index >= 0 and step_index < prep_scores.size():
		prep_scores[step_index] = clamped
	else:
		prep_scores.append(clamped)

## Advances the oscillating cook timing indicator and returns its normalized position.
func advance_indicator(delta: float) -> float:
	if delta > 0.0:
		indicator_time += delta * indicator_speed
	return get_cooking_indicator_position()

## Returns the oscillating indicator position in [0.0, 1.0].
func get_cooking_indicator_position() -> float:
	return clampf(0.5 + 0.5 * sin(indicator_time), 0.0, 1.0)

## Converts distance from SWEET_SPOT_CENTER (0.5) into a timing score in [0.0, 1.0].
func get_sweet_spot_score(indicator_pos: float = -1.0) -> float:
	var pos: float = indicator_pos if indicator_pos >= 0.0 else get_cooking_indicator_position()
	return clampf(1.0 - absf(pos - SWEET_SPOT_CENTER) * 2.0, 0.0, 1.0)

## Combines prep scores (60%) and cook timing (40%) into a dish quality tier.
func calculate_dish_quality(p_scores: Array, cook_timing: float) -> String:
	var clamped_timing: float = clampf(cook_timing, 0.0, 1.0)
	var weighted: float = clamped_timing
	if not p_scores.is_empty():
		var total: float = 0.0
		for score in p_scores:
			total += clampf(float(score), 0.0, 1.0)
		var avg_prep: float = total / float(p_scores.size())
		weighted = avg_prep * 0.6 + clamped_timing * 0.4
	if weighted >= QUALITY_PERFECT_THRESHOLD:
		return "PERFECT"
	if weighted >= QUALITY_GOOD_THRESHOLD:
		return "GOOD"
	return "NORMAL"

## Builds a cooked FOOD ItemData resource with bond bonus scaled by dish quality.
func create_dish_item(recipe_id: String, quality: String, dish_name: String = "") -> ItemData:
	var dish := ItemData.new()
	dish.id = recipe_id
	dish.name = dish_name if not dish_name.is_empty() else recipe_id
	dish.type = ItemData.ItemType.FOOD
	dish.quality = quality
	match quality:
		"PERFECT":
			dish.bond_bonus = 50
		"GOOD":
			dish.bond_bonus = 30
		_:
			dish.bond_bonus = 15
	return dish

## Finalizes the active cook using the override timing or current indicator sweet spot.
func finalize_cook(cook_timing_override: float = -1.0) -> ItemData:
	var timing: float = cook_timing_override if cook_timing_override >= 0.0 else get_sweet_spot_score(get_cooking_indicator_position())
	var quality: String = calculate_dish_quality(prep_scores, timing)
	var recipe_id: String = active_recipe.id if active_recipe != null else "dish"
	var dish_name: String = active_recipe.name if active_recipe != null else "Dish"
	return create_dish_item(recipe_id, quality, dish_name)
