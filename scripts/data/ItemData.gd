class_name ItemData
extends Resource

enum ItemType {
	GIFT,
	FOOD,
	INGREDIENT,
	MATERIAL,
	AP_RESTORE
}

@export var id: String = ""
@export var name: String = ""
@export var type: ItemType = ItemType.MATERIAL
@export var stack_max: int = 99
@export var bond_bonus: int = 0
@export var quality: String = "NORMAL"
