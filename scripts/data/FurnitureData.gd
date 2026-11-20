# scripts/data/FurnitureData.gd
class_name FurnitureData
extends Resource

@export var id: String = ""
@export var name: String = ""
@export var grid_size: Vector2i = Vector2i(1, 1)
@export var comfort_points: int = 100
@export var craft_materials: Dictionary = {} # material_id -> quantity
@export var price: int = 500
@export var model_path: String = ""
