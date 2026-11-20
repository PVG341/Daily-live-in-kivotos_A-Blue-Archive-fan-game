# scripts/intimacy/GestureReceiver.gd
class_name GestureReceiver
extends RefCounted

signal headpat_completed(satisfaction: float)
signal cheek_pinched(offset: float)
signal food_fed(item_id: String, reaction: String)

var _headpat_satisfaction: float = 0.0
var _cheek_pinch_offset: float = 0.0
var _last_stroke_dir: Vector2 = Vector2.ZERO
var _headpat_completed_emitted: bool = false

func register_headpat_stroke(delta: Vector2) -> void:
	if delta.length_squared() <= 0.0001:
		return

	var dir: Vector2 = delta.normalized()
	if _last_stroke_dir != Vector2.ZERO and _last_stroke_dir.dot(dir) < 0.0:
		var gain: float = clampf(delta.length() / 200.0, 0.15, 0.35)
		_headpat_satisfaction = clampf(_headpat_satisfaction + gain, 0.0, 1.0)
		if is_equal_approx(_headpat_satisfaction, 1.0) and not _headpat_completed_emitted:
			_headpat_satisfaction = 1.0
			_headpat_completed_emitted = true
			headpat_completed.emit(1.0)
	_last_stroke_dir = dir

func register_cheek_pinch(delta: Vector2) -> void:
	if delta.length_squared() <= 0.0001:
		return

	_cheek_pinch_offset = clampf(_cheek_pinch_offset + delta.length() * 0.01, 0.0, 1.0)
	cheek_pinched.emit(_cheek_pinch_offset)

func register_stroke(delta: Vector2) -> void:
	register_headpat_stroke(delta)
	register_cheek_pinch(delta)

func get_headpat_satisfaction() -> float:
	return clampf(_headpat_satisfaction, 0.0, 1.0)

func get_cheek_pinch_offset() -> float:
	return clampf(_cheek_pinch_offset, 0.0, 1.0)

func register_feed(item: ItemData, student_data: StudentData = null) -> Dictionary:
	if item == null or item.type != ItemData.ItemType.FOOD:
		return {
			"accepted": false,
			"bond_bonus": 0,
			"reaction": "REJECTED"
		}

	var is_favorite: bool = (
		student_data != null
		and not item.id.is_empty()
		and student_data.favorite_food == item.id
	)
	var bond_bonus: int = int(round(float(item.bond_bonus) * 1.5)) if is_favorite else item.bond_bonus
	var reaction: String = "FAVORITE" if is_favorite else ("DELICIOUS" if item.quality == "PERFECT" else "HAPPY")

	food_fed.emit(item.id, reaction)
	return {
		"accepted": true,
		"bond_bonus": bond_bonus,
		"reaction": reaction
	}

func reset() -> void:
	_headpat_satisfaction = 0.0
	_cheek_pinch_offset = 0.0
	_last_stroke_dir = Vector2.ZERO
	_headpat_completed_emitted = false
