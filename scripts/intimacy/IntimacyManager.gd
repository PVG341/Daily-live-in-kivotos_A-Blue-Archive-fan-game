# scripts/intimacy/IntimacyManager.gd
class_name IntimacyManager
extends Node3D

const GestureReceiverScript := preload("res://scripts/intimacy/GestureReceiver.gd")
const BondProgressTrackerScript := preload("res://scripts/intimacy/BondProgressTracker.gd")

const HEADPAT_COMPLETION_EXP: int = 25

var current_student: StudentData = null
var gesture_receiver: GestureReceiverScript = GestureReceiverScript.new()
var bond_tracker: BondProgressTrackerScript = BondProgressTrackerScript.new()
var custom_actions: Dictionary = {}
var blendshape_weights: Dictionary = {
	"eye_smile": 0.0,
	"cheek_puff": 0.0,
	"mouth_open": 0.0,
	"blush": 0.0
}

func _init() -> void:
	gesture_receiver.headpat_completed.connect(_on_headpat_completed)

func start_session(student: StudentData) -> void:
	current_student = student
	gesture_receiver.reset()
	_reset_blendshapes()

func end_session() -> void:
	current_student = null
	gesture_receiver.reset()
	_reset_blendshapes()

func apply_headpat_Input(delta: Vector2) -> float:
	gesture_receiver.register_stroke(delta)
	var satisfaction: float = gesture_receiver.get_headpat_satisfaction()
	blendshape_weights["eye_smile"] = clampf(satisfaction, 0.0, 1.0)
	blendshape_weights["blush"] = clampf(
		maxf(float(blendshape_weights.get("blush", 0.0)), satisfaction * 0.8),
		0.0,
		1.0
	)
	return satisfaction

func apply_cheek_pinch_input(delta: Vector2) -> float:
	gesture_receiver.register_stroke(delta)
	var offset: float = gesture_receiver.get_cheek_pinch_offset()
	blendshape_weights["cheek_puff"] = clampf(offset, 0.0, 1.0)
	if offset > 0.0:
		blendshape_weights["blush"] = clampf(
			maxf(float(blendshape_weights.get("blush", 0.0)), offset * 0.5),
			0.0,
			1.0
		)
	return offset

func feed_student(item: ItemData) -> Dictionary:
	var result: Dictionary = gesture_receiver.register_feed(item, current_student)
	if result.get("accepted", false):
		blendshape_weights["mouth_open"] = 1.0
		var reaction: String = str(result.get("reaction", "HAPPY"))
		var target_smile: float = 1.0 if reaction in ["FAVORITE", "DELICIOUS"] else 0.7
		blendshape_weights["eye_smile"] = maxf(float(blendshape_weights.get("eye_smile", 0.0)), target_smile)
		var blush_gain: float = 0.6 if reaction == "FAVORITE" else 0.3
		blendshape_weights["blush"] = clampf(float(blendshape_weights.get("blush", 0.0)) + blush_gain, 0.0, 1.0)

		var bonus: int = int(result.get("bond_bonus", 0))
		if current_student != null and not current_student.id.is_empty() and bonus > 0:
			bond_tracker.add_bond_exp(current_student.id, bonus)
			_sync_student_bond()
	return result

func register_custom_action(action_id: String, config: Dictionary) -> void:
	if action_id.is_empty():
		return
	custom_actions[action_id] = config.duplicate(true)

func trigger_custom_action(action_id: String) -> bool:
	if not custom_actions.has(action_id):
		return false
	var config: Dictionary = custom_actions[action_id]
	if config.has("blendshapes") and config["blendshapes"] is Dictionary:
		for key in config["blendshapes"].keys():
			if blendshape_weights.has(key):
				blendshape_weights[key] = clampf(float(config["blendshapes"][key]), 0.0, 1.0)
	var bonus: int = int(config.get("bond_bonus", 0))
	if current_student != null and not current_student.id.is_empty() and bonus > 0:
		bond_tracker.add_bond_exp(current_student.id, bonus)
		_sync_student_bond()
	return true

func _on_headpat_completed(_satisfaction: float) -> void:
	if current_student != null and not current_student.id.is_empty():
		bond_tracker.add_bond_exp(current_student.id, HEADPAT_COMPLETION_EXP)
		_sync_student_bond()

func _sync_student_bond() -> void:
	if current_student == null or current_student.id.is_empty():
		return
	current_student.bond_level = bond_tracker.get_bond_level(current_student.id)
	current_student.bond_exp = bond_tracker.get_bond_exp(current_student.id)

func _reset_blendshapes() -> void:
	for key in blendshape_weights.keys():
		blendshape_weights[key] = 0.0
