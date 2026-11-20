# scripts/hub/OfficeDecorator.gd
class_name OfficeDecorator
extends RefCounted

const FurnitureDataScript := preload("res://scripts/data/FurnitureData.gd")

var grid_width: int = 8
var grid_height: int = 8
var placed_items: Array[Dictionary] = [] # {"furniture": FurnitureData, "origin": Vector2i, "rotation_deg": int, "occupied_cells": Array[Vector2i]}

## Initializes the office decoration grid with clamped positive dimensions.
func _init(p_width: int = 8, p_height: int = 8) -> void:
	grid_width = maxi(1, p_width)
	grid_height = maxi(1, p_height)

func _normalize_rotation(rotation_deg: int) -> int:
	return ((rotation_deg % 360) + 360) % 360

## Normalizes rotation_deg to 0/90/180/270 and swaps x/y dimensions at 90 or 270 degrees.
func get_footprint_size(base_size: Vector2i, rotation_deg: int) -> Vector2i:
	var normalized: int = _normalize_rotation(rotation_deg)
	if normalized == 90 or normalized == 270:
		return Vector2i(base_size.y, base_size.x)
	return base_size

func _get_occupied_cells(origin: Vector2i, footprint: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dx in range(footprint.x):
		for dy in range(footprint.y):
			cells.append(Vector2i(origin.x + dx, origin.y + dy))
	return cells

func _is_cell_occupied(cell: Vector2i) -> bool:
	for entry in placed_items:
		var occupied: Array = entry.get("occupied_cells", [])
		if occupied.has(cell):
			return true
	return false

## Checks furniture validity, 90-degree rotation alignment, grid bounds, and overlap with existing items.
func can_place_furniture(furniture: FurnitureDataScript, cell: Vector2i, rotation_deg: int = 0) -> bool:
	if furniture == null:
		return false
	if furniture.grid_size.x <= 0 or furniture.grid_size.y <= 0:
		return false
	var normalized: int = _normalize_rotation(rotation_deg)
	if normalized % 90 != 0:
		return false

	var footprint: Vector2i = get_footprint_size(furniture.grid_size, normalized)
	var candidate_cells: Array[Vector2i] = _get_occupied_cells(cell, footprint)
	for c in candidate_cells:
		if c.x < 0 or c.x >= grid_width or c.y < 0 or c.y >= grid_height:
			return false
		if _is_cell_occupied(c):
			return false
	return true

## Places furniture on the grid if valid and records its occupied cells.
func place_furniture(furniture: FurnitureDataScript, cell: Vector2i, rotation_deg: int = 0) -> bool:
	if not can_place_furniture(furniture, cell, rotation_deg):
		return false
	var normalized: int = _normalize_rotation(rotation_deg)
	var footprint: Vector2i = get_footprint_size(furniture.grid_size, normalized)
	var occupied_cells: Array[Vector2i] = _get_occupied_cells(cell, footprint)
	placed_items.append({
		"furniture": furniture,
		"origin": cell,
		"rotation_deg": normalized,
		"occupied_cells": occupied_cells,
	})
	return true

## Removes the placed furniture occupying cell and returns its FurnitureData, or null if empty.
func remove_furniture(cell: Vector2i) -> FurnitureDataScript:
	for i in range(placed_items.size()):
		var entry: Dictionary = placed_items[i]
		var occupied: Array = entry.get("occupied_cells", [])
		if occupied.has(cell):
			var removed_furniture: FurnitureDataScript = entry.get("furniture")
			placed_items.remove_at(i)
			return removed_furniture
	return null

## Sums comfort_points across all currently placed furniture items.
func get_total_comfort() -> int:
	var total: int = 0
	for entry in placed_items:
		var furniture: FurnitureDataScript = entry.get("furniture")
		if furniture != null:
			total += furniture.comfort_points
	return total
