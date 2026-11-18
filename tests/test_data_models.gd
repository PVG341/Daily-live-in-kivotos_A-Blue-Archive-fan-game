# tests/test_data_models.gd
extends SceneTree

func _init():
	# Test StudentData
	var student = StudentData.new()
	student.id = "shiroko"
	student.student_name = "Sunaookami Shiroko"
	student.role = StudentData.CombatRole.DAMAGE_DEALER
	student.squad_slot = StudentData.SquadSlot.STRIKER
	student.base_hp = 3200
	student.base_atk = 450
	assert(student.id == "shiroko", "Student ID mismatch")
	assert(student.role == StudentData.CombatRole.DAMAGE_DEALER, "Role mismatch")
	assert(student.base_hp == 3200, "HP mismatch")

	# Test SkillData
	var skill = SkillData.new()
	skill.id = "drone_strike"
	skill.name = "Drone Strike"
	skill.cost = 3
	skill.cooldown = 15.0
	skill.aoe_radius = 5.0
	skill.effect_type = "damage"
	assert(skill.id == "drone_strike", "Skill ID mismatch")
	student.skills.append(skill)
	assert(student.skills.size() == 1, "Student skills mismatch")

	# Test ItemData
	var item = ItemData.new()
	item.id = "yakisoba_bread"
	item.type = ItemData.ItemType.FOOD
	item.bond_bonus = 30
	assert(item.type == ItemData.ItemType.FOOD, "Item type mismatch")

	# Test RecipeData
	var recipe = RecipeData.new()
	recipe.id = "parfait"
	recipe.ingredients = {"milk": 2, "fruit": 3, "sugar": 1}
	assert(recipe.ingredients.size() == 3, "Recipe ingredient count mismatch")

	# Test EventBus
	var event_bus = load("res://scripts/core/EventBus.gd").new()
	assert(event_bus.has_signal("student_bonded"), "Missing student_bonded signal")
	assert(event_bus.has_signal("ap_changed"), "Missing ap_changed signal")
	assert(event_bus.has_signal("day_advanced"), "Missing day_advanced signal")
	assert(event_bus.has_signal("mod_loaded"), "Missing mod_loaded signal")
	assert(event_bus.has_signal("combat_room_cleared"), "Missing combat_room_cleared signal")
	assert(event_bus.has_signal("item_picked_up"), "Missing item_picked_up signal")
	assert(event_bus.has_signal("combat_event_triggered"), "Missing combat_event_triggered signal")
	assert(event_bus.has_signal("save_requested"), "Missing save_requested signal")
	assert(event_bus.has_signal("load_requested"), "Missing load_requested signal")

	# Test signal emission and reception
	var received_bond = []
	event_bus.student_bonded.connect(func(student_id: String, level: int): received_bond.append([student_id, level]))
	event_bus.student_bonded.emit("shiroko", 2)
	assert(received_bond.size() == 1, "Signal emission failed")
	assert(received_bond[0] == ["shiroko", 2], "Signal argument mismatch")

	event_bus.free()

	print("PASS: test_data_models")
	quit(0)
