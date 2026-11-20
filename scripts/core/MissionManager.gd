# scripts/core/MissionManager.gd
class_name MissionManager
extends Node

const QuestDataScript := preload("res://scripts/data/QuestData.gd")

signal quest_completed(quest_id: String, student_id: String)

var quests: Dictionary = {} # quest_id -> QuestData
var quest_progress: Dictionary = {} # quest_id -> int
var completed_quests: Dictionary = {} # quest_id -> bool

## Registers a quest, resets its tracked progress to 0, and registers >20 bond gates on bond_tracker.
func register_quest(quest: QuestDataScript, bond_tracker: Object = null) -> void:
	if quest == null or quest.id.is_empty():
		return
	quests[quest.id] = quest
	quest_progress[quest.id] = 0
	if quest.required_bond_level > 20 and bond_tracker != null and bond_tracker.has_method("register_quest_gate"):
		bond_tracker.register_quest_gate(quest.student_id, quest.required_bond_level)

## Returns all uncompleted quests for student_id unlocked at or below current_bond_level.
func get_available_quests(student_id: String, current_bond_level: int) -> Array[QuestDataScript]:
	var available: Array[QuestDataScript] = []
	if student_id.is_empty():
		return available
	for quest_id in quests:
		if is_quest_completed(quest_id):
			continue
		var quest: QuestDataScript = quests[quest_id]
		if quest.student_id == student_id and current_bond_level >= quest.required_bond_level:
			available.append(quest)
	return available

## Increments progress for all uncompleted quests matching objective_type and target_id.
func record_objective_progress(objective_type: String, target_id: String, count: int = 1) -> void:
	var delta: int = maxi(0, count)
	if delta == 0:
		return
	for quest_id in quests:
		if is_quest_completed(quest_id):
			continue
		var quest: QuestDataScript = quests[quest_id]
		if quest.objective_type == objective_type and quest.target_id == target_id:
			quest_progress[quest_id] = int(quest_progress.get(quest_id, 0)) + delta

## Returns true if the quest exists, is not completed, and meets its target_count.
func is_quest_ready_to_complete(quest_id: String) -> bool:
	if not quests.has(quest_id) or is_quest_completed(quest_id):
		return false
	var quest: QuestDataScript = quests[quest_id]
	return int(quest_progress.get(quest_id, 0)) >= quest.target_count

## Returns true if quest_id has been marked completed.
func is_quest_completed(quest_id: String) -> bool:
	return bool(completed_quests.get(quest_id, false))

## Completes a ready quest, unlocks its bond gate on bond_tracker if provided, and emits quest_completed.
func complete_quest(quest_id: String, bond_tracker: Object = null) -> bool:
	if not is_quest_ready_to_complete(quest_id):
		return false
	var quest: QuestDataScript = quests[quest_id]
	completed_quests[quest_id] = true
	if bond_tracker != null and bond_tracker.has_method("complete_bond_quest_gate"):
		bond_tracker.complete_bond_quest_gate(quest.student_id, quest.required_bond_level)
	quest_completed.emit(quest_id, quest.student_id)
	return true
