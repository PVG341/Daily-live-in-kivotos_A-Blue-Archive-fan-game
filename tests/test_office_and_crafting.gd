# tests/test_office_and_crafting.gd
extends SceneTree

var _failed: bool = false
var _completed: bool = false

func check(cond: bool, msg: String) -> bool:
	if not cond:
		printerr("FAIL: " + msg)
		_failed = true
		quit(1)
		return false
	return true

func _init() -> void:
	_run_tests()

	if _failed or not _completed:
		quit(1)
		return

	print("PASS: test_office_and_crafting")
	quit(0)

func _make_furniture(
	furniture_script: GDScript,
	id: String,
	display_name: String,
	grid_size: Vector2i,
	comfort_points: int,
	craft_materials: Dictionary = {},
	price: int = 500,
	model_path: String = ""
) -> Resource:
	var f: Resource = furniture_script.new()
	f.id = id
	f.name = display_name
	f.grid_size = grid_size
	f.comfort_points = comfort_points
	f.craft_materials = craft_materials
	f.price = price
	f.model_path = model_path
	return f

func _run_tests() -> void:
	var furniture_script: GDScript = load("res://scripts/data/FurnitureData.gd")
	if not check(furniture_script != null and furniture_script.can_instantiate(), "FurnitureData.gd must load and compile"):
		return
	var crafting_script: GDScript = load("res://scripts/hub/CraftingChamberManager.gd")
	if not check(crafting_script != null and crafting_script.can_instantiate(), "CraftingChamberManager.gd must load and compile"):
		return
	var decorator_script: GDScript = load("res://scripts/hub/OfficeDecorator.gd")
	if not check(decorator_script != null and decorator_script.can_instantiate(), "OfficeDecorator.gd must load and compile"):
		return
	var spawner_script: GDScript = load("res://scripts/hub/VisitorSpawner.gd")
	if not check(spawner_script != null and spawner_script.can_instantiate(), "VisitorSpawner.gd must load and compile"):
		return

	# 1. FurnitureData defaults
	var default_furniture: Resource = furniture_script.new()
	check(default_furniture.id == "", "FurnitureData default id must be empty string")
	check(default_furniture.name == "", "FurnitureData default name must be empty string")
	check(default_furniture.grid_size == Vector2i(1, 1), "FurnitureData default grid_size must be Vector2i(1, 1)")
	check(default_furniture.comfort_points == 100, "FurnitureData default comfort_points must be 100")
	check(default_furniture.craft_materials is Dictionary and default_furniture.craft_materials.is_empty(), "FurnitureData default craft_materials must be empty Dictionary")
	check(default_furniture.price == 500, "FurnitureData default price must be 500")
	check(default_furniture.model_path == "", "FurnitureData default model_path must be empty string")

	# 2. CraftingChamberManager: display name & crafting validation/deduction
	var crafting = crafting_script.new()
	check(crafting.facility_display_name == "Crafting Chamber", "CraftingChamberManager default facility_display_name must be 'Crafting Chamber'")
	crafting.facility_display_name = "Synthesis Workshop"
	check(crafting.facility_display_name == "Synthesis Workshop", "CraftingChamberManager facility_display_name must be customizable")
	crafting.apply_config({"facility_display_name": "Materializer Bay"})
	check(crafting.facility_display_name == "Materializer Bay", "CraftingChamberManager apply_config must update facility_display_name from JSON dict")

	var sofa: Resource = _make_furniture(
		furniture_script,
		"sofa_schale",
		"Schale Lounge Sofa",
		Vector2i(2, 1),
		350,
		{"wood": 3, "fabric": 2},
		1200,
		"res://assets/models/sofa.glb"
	)
	var desk: Resource = _make_furniture(
		furniture_script,
		"desk_sensei",
		"Sensei Desk",
		Vector2i(2, 2),
		400,
		{"wood": 2, "steel": 1},
		1500
	)

	var low_inv: Dictionary = {"wood": 3, "fabric": 1}
	check(crafting.can_craft_furniture(null, low_inv) == false, "can_craft_furniture(null, ...) must return false")
	check(crafting.can_craft_furniture(sofa, low_inv) == false, "can_craft_furniture must return false when materials are insufficient")
	check(crafting.craft_furniture(sofa, low_inv) == false, "craft_furniture must return false when materials are insufficient")
	check(low_inv["wood"] == 3 and low_inv["fabric"] == 1, "Failed craft_furniture must not deduct materials")

	var inv: Dictionary = {"wood": 5, "fabric": 2, "steel": 1}
	check(crafting.can_craft_furniture(sofa, inv) == true, "can_craft_furniture must return true when materials suffice")
	check(crafting.craft_furniture(sofa, inv) == true, "craft_furniture must return true when materials suffice")
	check(inv["wood"] == 2 and inv["fabric"] == 0, "craft_furniture must deduct required materials in place")
	check(inv["steel"] == 1, "craft_furniture must not modify unrelated materials")

	# 3. OfficeDecorator: grid bounds, 90-deg rotation footprint, overlap, comfort, removal
	var office = decorator_script.new(6, 5)
	check(office.grid_width == 6 and office.grid_height == 5, "OfficeDecorator._init must set grid dimensions")
	check(office.get_total_comfort() == 0, "Empty office total comfort must be 0")

	check(office.get_footprint_size(Vector2i(2, 1), 0) == Vector2i(2, 1), "0 deg footprint must preserve (2, 1)")
	check(office.get_footprint_size(Vector2i(2, 1), 90) == Vector2i(1, 2), "90 deg footprint must swap (2, 1) to (1, 2)")
	check(office.get_footprint_size(Vector2i(2, 1), 180) == Vector2i(2, 1), "180 deg footprint must keep (2, 1)")
	check(office.get_footprint_size(Vector2i(2, 1), 270) == Vector2i(1, 2), "270 deg footprint must swap (2, 1) to (1, 2)")
	check(office.get_footprint_size(Vector2i(2, 1), -90) == Vector2i(1, 2), "-90 deg footprint must normalize to 270 and swap to (1, 2)")

	check(office.can_place_furniture(null, Vector2i(0, 0), 0) == false, "can_place_furniture(null, ...) must return false")
	check(office.can_place_furniture(sofa, Vector2i(0, 0), 45) == false, "Non-90-degree rotation must be rejected")
	check(office.can_place_furniture(sofa, Vector2i(-1, 0), 0) == false, "Negative coordinate must be rejected")
	check(office.can_place_furniture(sofa, Vector2i(5, 0), 0) == false, "2x1 furniture at x=5 on width 6 must be rejected (out of bounds)")
	check(office.can_place_furniture(sofa, Vector2i(5, 0), 90) == true, "2x1 furniture rotated 90 deg at (5, 0) fits in 1x2 footprint")

	# Place sofa rotated 90 deg at (2, 1): occupies (2, 1) and (2, 2)
	check(office.place_furniture(sofa, Vector2i(2, 1), 90) == true, "Placing rotated sofa at (2, 1) must succeed")
	check(office.placed_items.size() == 1, "placed_items must contain 1 entry after placement")
	var placed_entry: Dictionary = office.placed_items[0]
	var occupied: Array = placed_entry["occupied_cells"]
	check(occupied.size() == 2 and occupied.has(Vector2i(2, 1)) and occupied.has(Vector2i(2, 2)), "2x1 rotated 90 deg at (2, 1) must occupy (2, 1) and (2, 2)")
	check(office.get_total_comfort() == 350, "Total comfort must equal 350 after placing sofa")

	# Overlap checks against both occupied cells (2, 1) and (2, 2)
	check(office.can_place_furniture(desk, Vector2i(1, 1), 0) == false, "2x2 desk at (1, 1) overlaps (2, 1) and (2, 2)")
	check(office.place_furniture(desk, Vector2i(1, 2), 0) == false, "2x2 desk at (1, 2) overlaps (2, 2) and must fail")
	check(office.place_furniture(desk, Vector2i(0, 0), 0) == true, "2x2 desk at (0, 0) must succeed without overlap")
	check(office.get_total_comfort() == 750, "Total comfort must sum to 750")

	# Removal by any occupied cell
	check(office.remove_furniture(Vector2i(5, 4)) == null, "Removing from empty cell must return null")
	var removed_sofa: Resource = office.remove_furniture(Vector2i(2, 2))
	check(removed_sofa == sofa, "remove_furniture(2, 2) must find and return the rotated sofa")
	check(office.placed_items.size() == 1, "placed_items must have 1 entry after removing sofa")
	check(office.get_total_comfort() == 400, "Total comfort must drop to 400 after removing sofa")
	check(office.can_place_furniture(sofa, Vector2i(2, 1), 90) == true, "Freed cells must be available for placement again")

	# 4. VisitorSpawner: FPS cap enforcement, overflow queue, bonus gift multiplier
	var spawner = spawner_script.new()
	check(spawner.max_active_students == 5, "VisitorSpawner default max_active_students must be 5")
	check(spawner.COMFORT_PER_VISITOR == 250, "VisitorSpawner COMFORT_PER_VISITOR must be 250")

	var empty_roster: Array[String] = []
	var empty_result: Dictionary = spawner.calculate_daily_visitors(empty_roster, 2000)
	check(empty_result["active_spawns"].is_empty(), "Empty roster must produce 0 active_spawns")
	check(empty_result["overflow_queue"].is_empty(), "Empty roster must produce 0 overflow_queue")
	check(is_equal_approx(float(empty_result["bonus_gift_multiplier"]), 1.0), "Empty roster bonus_gift_multiplier must be 1.0")

	var roster: Array[String] = ["shiroko", "hoshino", "serika", "nonomi", "ayane", "hina", "aru"]
	spawner.max_active_students = 4
	var high_comfort_result: Dictionary = spawner.calculate_daily_visitors(roster, 2000)
	var active_spawns: Array = high_comfort_result["active_spawns"]
	var overflow_queue: Array = high_comfort_result["overflow_queue"]
	var bonus_mult: float = float(high_comfort_result["bonus_gift_multiplier"])

	check(active_spawns.size() == 4 and active_spawns.size() <= spawner.max_active_students, "active_spawns must never exceed max_active_students (4)")
	check(overflow_queue.size() == 3, "7 desired visitors with cap 4 must place 3 into overflow_queue")
	check(bonus_mult > 1.0, "Overflow visitors must grant bonus_gift_multiplier > 1.0")
	check(is_equal_approx(bonus_mult, 1.45), "3 overflow visitors must yield 1.0 + 3 * 0.15 = 1.45 bonus_gift_multiplier")

	var low_comfort_result: Dictionary = spawner.calculate_daily_visitors(roster, 0)
	check(low_comfort_result["active_spawns"].size() == 1, "0 comfort with non-empty roster must yield 1 active visitor")
	check(low_comfort_result["overflow_queue"].is_empty(), "1 desired visitor with cap 4 must have empty overflow_queue")
	check(is_equal_approx(float(low_comfort_result["bonus_gift_multiplier"]), 1.0), "No overflow must keep bonus_gift_multiplier at 1.0")

	var settings_script: GDScript = load("res://scripts/core/SettingsManager.gd")
	if check(settings_script != null and settings_script.can_instantiate(), "SettingsManager.gd must load and compile"):
		var settings = settings_script.new()
		settings.apply_max_active_students(3)
		spawner.sync_from_settings(settings)
		check(spawner.max_active_students == 3, "VisitorSpawner.sync_from_settings must sync max_active_students from SettingsManager")
		var synced_result: Dictionary = spawner.calculate_daily_visitors(roster, 2000)
		check(synced_result["active_spawns"].size() == 3, "Synced cap 3 must restrict active_spawns to 3")
		check(synced_result["overflow_queue"].size() == 4, "Synced cap 3 with 7 desired visitors must put 4 into overflow_queue")
		settings.free()

	_completed = true
