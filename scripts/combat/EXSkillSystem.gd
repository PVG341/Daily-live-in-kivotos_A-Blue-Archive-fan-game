# scripts/combat/EXSkillSystem.gd
class_name EXSkillSystem
extends Node

const CostBarManagerScript := preload("res://scripts/combat/CostBarManager.gd")

signal skill_activated(skill: SkillData, target_position: Vector3)

const MAX_SPECIAL_SLOTS: int = 2

var cost_bar: CostBarManagerScript = null
var special_slots: Array[StudentData] = []
var registered_skills: Array[SkillData] = []
var cooldown_remaining: Dictionary = {}

func _init() -> void:
	cost_bar = CostBarManagerScript.new()

## Assigns up to MAX_SPECIAL_SLOTS Special students and registers their EX skills.
func set_special_students(students: Array) -> void:
	special_slots.clear()
	for entry in students:
		if not (entry is StudentData) or entry == null:
			continue
		if special_slots.size() >= MAX_SPECIAL_SLOTS:
			break
		var student := entry as StudentData
		special_slots.append(student)
		for skill in student.skills:
			register_skill(skill)

## Registers a non-null skill with a non-empty id if not already registered.
func register_skill(skill: SkillData) -> void:
	if skill == null or skill.id.is_empty():
		return
	for existing in registered_skills:
		if existing == skill or existing.id == skill.id:
			return
	registered_skills.append(skill)

## Returns true when the given skill currently has remaining cooldown > 0.
func is_skill_on_cooldown(skill: SkillData) -> bool:
	return skill != null and float(cooldown_remaining.get(skill.id, 0.0)) > 0.0

## Advances active skill cooldowns by delta seconds, removing expired entries.
func tick_cooldowns(delta: float) -> void:
	var step: float = maxf(0.0, delta)
	if step <= 0.0:
		return
	for skill_id in cooldown_remaining.keys():
		var remaining: float = float(cooldown_remaining[skill_id]) - step
		if remaining <= 0.0:
			cooldown_remaining.erase(skill_id)
		else:
			cooldown_remaining[skill_id] = remaining

## Returns all registered skills that are off cooldown and affordable with current cost.
func get_available_skills() -> Array[SkillData]:
	var available: Array[SkillData] = []
	if cost_bar == null:
		return available
	for skill in registered_skills:
		if skill != null and not is_skill_on_cooldown(skill) and cost_bar.current_cost >= float(skill.cost):
			available.append(skill)
	return available

## Spends cost, starts cooldown, and emits skill_activated if the skill can be cast.
func activate_skill(skill: SkillData, target_position: Vector3) -> bool:
	if skill == null or is_skill_on_cooldown(skill) or cost_bar == null or not cost_bar.spend(float(skill.cost)):
		return false
	cooldown_remaining[skill.id] = maxf(0.0, skill.cooldown)
	skill_activated.emit(skill, target_position)
	return true
