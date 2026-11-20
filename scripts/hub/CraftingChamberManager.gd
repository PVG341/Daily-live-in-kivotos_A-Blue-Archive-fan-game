# scripts/hub/CraftingChamberManager.gd
class_name CraftingChamberManager
extends RefCounted

const FurnitureDataScript := preload("res://scripts/data/FurnitureData.gd")

## Configurable display name so lore terminology can be updated via property or JSON config.
var facility_display_name: String = "Crafting Chamber"

## Applies JSON-deserialized configuration values (e.g. facility_display_name).
func apply_config(config: Dictionary) -> void:
	if config.has("facility_display_name"):
		var configured_name: String = str(config["facility_display_name"]).strip_edges()
		if not configured_name.is_empty():
			facility_display_name = configured_name

## Returns true if furniture is valid and inventory contains at least the required material quantities.
func can_craft_furniture(furniture: FurnitureDataScript, inventory: Dictionary) -> bool:
	if furniture == null:
		return false
	for mat_id in furniture.craft_materials:
		var required_qty: int = int(furniture.craft_materials[mat_id])
		if int(inventory.get(mat_id, 0)) < required_qty:
			return false
	return true

## Validates materials, deducts required quantities from inventory in place, and returns true on success.
func craft_furniture(furniture: FurnitureDataScript, inventory: Dictionary) -> bool:
	if not can_craft_furniture(furniture, inventory):
		return false
	for mat_id in furniture.craft_materials:
		var required_qty: int = int(furniture.craft_materials[mat_id])
		if required_qty > 0:
			inventory[mat_id] = int(inventory.get(mat_id, 0)) - required_qty
	return true
