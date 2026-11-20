# scripts/combat/RoguelikeCardManager.gd
class_name RoguelikeCardManager
extends RefCounted

var card_pool: Array[Dictionary] = []
var _active_buffs: Array[Dictionary] = []

func _init() -> void:
	card_pool = [
		{"id": "fire_rounds", "name": "Đạn cháy", "type": "ATK_UP", "value": 0.15, "effect": "ATK+15%"},
		{"id": "cost_regen", "name": "Hồi Cost nhanh", "type": "COST_RATE", "value": 0.30, "effect": "COST_RATE+30%"},
		{"id": "tank_reflect", "name": "Khiên phản đòn", "type": "REFLECT_DMG", "value": 0.10, "effect": "REFLECT_DMG_10%"},
		{"id": "heal_on_kill", "name": "Hồi máu khi hạ gục", "type": "HEAL_ON_KILL", "value": 0.05, "effect": "HEAL_ON_KILL_5%"},
		{"id": "piercing_ammo", "name": "Đạn xuyên giáp", "type": "ATK_UP", "value": 0.20, "effect": "ATK+20%"},
		{"id": "tactical_reload", "name": "Thay đạn chiến thuật", "type": "FLAT_DMG", "value": 40, "effect": "FLAT_DMG+40"},
	]

## Registers a custom or unlocked card if it has a valid, non-duplicate id.
func register_card(card: Dictionary) -> void:
	if not card.has("id"):
		return
	var card_id: String = str(card["id"])
	if card_id.is_empty() or _has_card_id(card_id):
		return
	card_pool.append(card.duplicate(true))

## Registers any unlocked roguelike card IDs from ProgressionManager into card_pool; returns count added.
func sync_unlocked_cards(progression_manager: Object) -> int:
	if progression_manager == null or not progression_manager.has_method("get_unlocked_roguelike_cards"):
		return 0
	var added: int = 0
	var unlocked_ids = progression_manager.get_unlocked_roguelike_cards()
	if unlocked_ids is Array:
		for raw_id in unlocked_ids:
			var card_id: String = str(raw_id)
			if card_id.is_empty() or _has_card_id(card_id):
				continue
			register_card({
				"id": card_id,
				"name": card_id,
				"type": "ATK_UP",
				"value": 0.15,
				"effect": "Unlocked: %s" % card_id,
			})
			added += 1
	return added

## Loads moddable card definitions from a JSON array or {"cards": [...]} dictionary; returns count added.
func load_cards_from_json(json_text: String) -> int:
	if json_text.strip_edges().is_empty():
		return 0
	var json := JSON.new()
	if json.parse(json_text) != OK:
		return 0
	var entries: Array = []
	if json.data is Array:
		entries = json.data
	elif json.data is Dictionary:
		if json.data.has("cards") and json.data["cards"] is Array:
			entries = json.data["cards"]
		elif json.data.has("id"):
			entries = [json.data]
	var added: int = 0
	for entry in entries:
		if entry is Dictionary:
			var card_id: String = str(entry.get("id", ""))
			if not card_id.is_empty() and not _has_card_id(card_id):
				register_card(entry)
				added += 1
	return added

func _has_card_id(card_id: String) -> bool:
	for existing in card_pool:
		if str(existing.get("id", "")) == card_id:
			return true
	return false

## Samples up to count distinct cards without replacement from card_pool.
func roll_cards(count: int = 3) -> Array[Dictionary]:
	var sample_count: int = mini(maxi(0, count), card_pool.size())
	var result: Array[Dictionary] = []
	if sample_count == 0:
		return result

	var indices: Array[int] = []
	for i in range(card_pool.size()):
		indices.append(i)
	indices.shuffle()

	for i in range(sample_count):
		result.append(card_pool[indices[i]].duplicate(true))
	return result

## Applies a card buff by id into the active session buff list; returns false if unknown.
func apply_buff(card_id: String) -> bool:
	for card in card_pool:
		if str(card.get("id", "")) == card_id:
			_active_buffs.append(card.duplicate(true))
			return true
	return false

## Returns a deep copy of all active buffs in the current run.
func get_active_buffs() -> Array[Dictionary]:
	return _active_buffs.duplicate(true)

## Clears all active session buffs.
func clear_session_buffs() -> void:
	_active_buffs.clear()
