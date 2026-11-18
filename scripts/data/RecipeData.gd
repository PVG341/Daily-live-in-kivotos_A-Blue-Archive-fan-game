class_name RecipeData
extends Resource

@export var id: String = ""
@export var name: String = ""
@export var ingredients: Dictionary = {} # item_id (String) -> quantity (int)
@export var base_quality_threshold: float = 0.0
