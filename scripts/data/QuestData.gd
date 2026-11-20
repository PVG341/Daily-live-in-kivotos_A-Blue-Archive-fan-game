# scripts/data/QuestData.gd
class_name QuestData
extends Resource

@export var id: String = ""
@export var title: String = ""
@export var description: String = ""
@export var student_id: String = ""
@export var required_bond_level: int = 5
@export var objective_type: String = "CLEAR_DUNGEON" # CLEAR_DUNGEON, COOK_DISH, GIFT_ITEM, INTERACT
@export var target_id: String = ""
@export var target_count: int = 1
@export var reward_items: Dictionary = {}
@export var unlocks_roguelike_card_id: String = ""
