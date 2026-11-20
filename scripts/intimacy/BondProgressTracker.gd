# scripts/intimacy/BondProgressTracker.gd
class_name BondProgressTracker
extends RefCounted

const MAX_BOND_LEVEL: int = 100
const DEFAULT_QUEST_GATE_LEVELS: Array[int] = [5, 10, 15, 20]

var event_bus: Object = null

var _bond_levels: Dictionary = {}
var _bond_exp: Dictionary = {}
var _custom_gates: Dictionary = {}
var _completed_gates: Dictionary = {}

func get_level_up_threshold(level: int) -> int:
	return maxi(100, level * 100 + 50)

func get_bond_level(student_id: String) -> int:
	return int(_bond_levels.get(student_id, 0))

func get_bond_exp(student_id: String) -> int:
	return int(_bond_exp.get(student_id, 0))

func has_student(student_id: String) -> bool:
	return _bond_levels.has(student_id) or _bond_exp.has(student_id)

func seed_student_bond(student_id: String, level: int, exp_val: int) -> void:
	if student_id.is_empty():
		return
	_bond_levels[student_id] = clampi(level, 0, MAX_BOND_LEVEL)
	_bond_exp[student_id] = maxi(0, exp_val)

func is_bond_gate_locked(student_id: String) -> bool:
	var level: int = get_bond_level(student_id)
	if level >= MAX_BOND_LEVEL:
		return false
	if not _is_blocked_at_level(student_id, level):
		return false
	return get_bond_exp(student_id) >= get_level_up_threshold(level)

func register_quest_gate(student_id: String, level: int) -> void:
	if student_id.is_empty() or level < 1 or level > MAX_BOND_LEVEL:
		return
	if not _custom_gates.has(student_id):
		_custom_gates[student_id] = {}
	_custom_gates[student_id][level] = true

func complete_bond_quest_gate(student_id: String, level: int) -> void:
	if student_id.is_empty():
		return
	if not _completed_gates.has(student_id):
		_completed_gates[student_id] = {}
	_completed_gates[student_id][level] = true
	_process_level_ups(student_id)

func add_bond_exp(student_id: String, amount: int) -> void:
	if student_id.is_empty() or amount <= 0:
		return
	_bond_exp[student_id] = get_bond_exp(student_id) + amount
	_process_level_ups(student_id)

func _is_gate_level(student_id: String, level: int) -> bool:
	if level in DEFAULT_QUEST_GATE_LEVELS:
		return true
	return _custom_gates.has(student_id) and _custom_gates[student_id].get(level, false)

func _is_gate_completed(student_id: String, level: int) -> bool:
	return _completed_gates.has(student_id) and _completed_gates[student_id].get(level, false)

func _is_blocked_at_level(student_id: String, level: int) -> bool:
	return _is_gate_level(student_id, level) and not _is_gate_completed(student_id, level)

func _process_level_ups(student_id: String) -> void:
	var level: int = get_bond_level(student_id)
	var exp_val: int = get_bond_exp(student_id)
	while level < MAX_BOND_LEVEL:
		if _is_blocked_at_level(student_id, level):
			break
		var threshold: int = get_level_up_threshold(level)
		if exp_val < threshold:
			break
		exp_val -= threshold
		level += 1
		_bond_levels[student_id] = level
		_bond_exp[student_id] = exp_val
		_emit_student_bonded(student_id, level)

func _emit_student_bonded(student_id: String, new_level: int) -> void:
	var bus := _get_event_bus()
	if bus != null and bus.has_signal(&"student_bonded"):
		bus.student_bonded.emit(student_id, new_level)

func _get_event_bus() -> Object:
	if event_bus != null:
		return event_bus
	var loop := Engine.get_main_loop() as SceneTree
	if loop != null and loop.root != null:
		return loop.root.get_node_or_null("EventBus")
	return null
