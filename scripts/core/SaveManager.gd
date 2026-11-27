# scripts/core/SaveManager.gd
extends Node

signal game_saved(slot: int)
signal game_loaded(slot: int)
signal save_deleted(slot: int)

const FALLBACK_SAVE_DIR: String = "user://saves"

var save_dir: String = ""
var current_slot: int = 1
var _fallback_warned: bool = false

# Autoload / Dependency references (injected or resolved via tree)
var day_cycle_manager: Node = null
var event_bus: Node = null

# Registered data models (e.g. StudentData instances keyed by student_id)
var students: Dictionary = {}

# Game state fields
var current_day: int = 1
var current_hour: float = 7.0
var current_ap: int = 100
var max_ap: int = 100
var credits: int = 0
var bonds: Dictionary = {}
var bonds_exp: Dictionary = {}
var inventory: Array = []
var unlocked_roguelike_cards: Array[String] = []
var unlocked_skill_variants: Dictionary = {}
var completed_quests: Dictionary = {}
var quest_progress: Dictionary = {}
var last_combat_summary: Dictionary = {}
var current_zone: String = "schale_office"
var playtime: float = 0.0

func _init() -> void:
	save_dir = get_save_root_dir()

func _ready() -> void:
	_connect_event_bus()

func _exit_tree() -> void:
	_disconnect_event_bus(_get_event_bus())

func get_save_root_dir() -> String:
	var portable_dir: String
	if OS.has_feature("editor"):
		portable_dir = "res://saves"
	else:
		portable_dir = OS.get_executable_path().get_base_dir().path_join("saves")

	if _is_dir_writable(portable_dir):
		return portable_dir

	if not _fallback_warned:
		_fallback_warned = true
		push_warning("SaveManager: Portable save directory '%s' is not writable, falling back to '%s'" % [portable_dir, FALLBACK_SAVE_DIR])
	return FALLBACK_SAVE_DIR

func _is_dir_writable(dir_path: String) -> bool:
	var existed: bool = DirAccess.dir_exists_absolute(dir_path)
	if not existed:
		var mk_err := DirAccess.make_dir_recursive_absolute(dir_path)
		if mk_err != OK:
			return false

	var probe_path: String = dir_path.path_join(".write_probe")
	var probe_file := FileAccess.open(probe_path, FileAccess.WRITE)
	if probe_file == null:
		if not existed:
			DirAccess.remove_absolute(dir_path)
		return false
	probe_file.close()
	DirAccess.remove_absolute(probe_path)

	if not existed:
		DirAccess.remove_absolute(dir_path)
	return true

func set_event_bus(bus: Node) -> void:
	_disconnect_event_bus(_get_event_bus())
	event_bus = bus
	_connect_event_bus()

func _disconnect_event_bus(bus: Node = null) -> void:
	var target_bus: Node = bus if bus != null else event_bus
	if target_bus != null and is_instance_valid(target_bus):
		if target_bus.has_signal("save_requested") and target_bus.save_requested.is_connected(_on_save_requested):
			target_bus.save_requested.disconnect(_on_save_requested)
		if target_bus.has_signal("load_requested") and target_bus.load_requested.is_connected(_on_load_requested):
			target_bus.load_requested.disconnect(_on_load_requested)
		if target_bus.has_signal("item_picked_up") and target_bus.item_picked_up.is_connected(_on_item_picked_up):
			target_bus.item_picked_up.disconnect(_on_item_picked_up)

func _connect_event_bus() -> void:
	var bus = _get_event_bus()
	if bus:
		if bus.has_signal("save_requested") and not bus.save_requested.is_connected(_on_save_requested):
			bus.save_requested.connect(_on_save_requested)
		if bus.has_signal("load_requested") and not bus.load_requested.is_connected(_on_load_requested):
			bus.load_requested.connect(_on_load_requested)
		if bus.has_signal("item_picked_up") and not bus.item_picked_up.is_connected(_on_item_picked_up):
			bus.item_picked_up.connect(_on_item_picked_up)

func _on_save_requested() -> void:
	save_game(current_slot)

func _on_load_requested(slot: int) -> void:
	load_game(slot)

func _on_item_picked_up(item_id: String, quantity: int) -> void:
	add_inventory_item(item_id, quantity)

func add_inventory_item(item_id: String, quantity: int) -> void:
	if item_id.is_empty() or quantity <= 0:
		return
	for entry in inventory:
		if entry is Dictionary and str(entry.get("id", "")) == item_id:
			entry["qty"] = int(entry.get("qty", 0)) + quantity
			return
	inventory.append({"id": item_id, "qty": quantity})

func add_credits(amount: int) -> int:
	credits += maxi(0, amount)
	return credits

func unlock_roguelike_card(card_id: String) -> bool:
	if card_id.is_empty():
		return false
	if not unlocked_roguelike_cards.has(card_id):
		unlocked_roguelike_cards.append(card_id)
		return true
	return false

func sync_from_progression(progression_mgr: Object, mission_mgr: Object) -> void:
	if progression_mgr != null and is_instance_valid(progression_mgr):
		if progression_mgr.has_method(&"get_unlocked_roguelike_cards"):
			var cards = progression_mgr.call(&"get_unlocked_roguelike_cards")
			if cards is Array:
				for cid in cards:
					unlock_roguelike_card(str(cid))
		if &"unlocked_skill_variants" in progression_mgr:
			var variants = progression_mgr.get(&"unlocked_skill_variants")
			if variants is Dictionary:
				for sid in variants:
					var dest: Array = unlocked_skill_variants.get(sid, []).duplicate()
					for vid in variants[sid]:
						if not dest.has(vid):
							dest.append(vid)
					unlocked_skill_variants[sid] = dest
	if mission_mgr != null and is_instance_valid(mission_mgr):
		if &"completed_quests" in mission_mgr:
			var cq = mission_mgr.get(&"completed_quests")
			if cq is Dictionary:
				for qid in cq:
					if bool(cq[qid]):
						completed_quests[qid] = true
		if &"quest_progress" in mission_mgr:
			var qp = mission_mgr.get(&"quest_progress")
			if qp is Dictionary:
				for qid in qp:
					quest_progress[qid] = maxi(int(quest_progress.get(qid, 0)), int(qp[qid]))

func sync_to_progression(progression_mgr: Object, mission_mgr: Object) -> void:
	if progression_mgr != null and is_instance_valid(progression_mgr) and progression_mgr.has_method(&"unlock_horizontal_option"):
		for cid in unlocked_roguelike_cards:
			progression_mgr.call(&"unlock_horizontal_option", "", "ROGUELIKE_CARD", str(cid))
		for sid in unlocked_skill_variants:
			var arr = unlocked_skill_variants[sid]
			if arr is Array:
				for vid in arr:
					progression_mgr.call(&"unlock_horizontal_option", str(sid), "SKILL_VARIANT", str(vid))
	if mission_mgr != null and is_instance_valid(mission_mgr):
		if &"completed_quests" in mission_mgr:
			var cq = mission_mgr.get(&"completed_quests")
			if cq is Dictionary:
				for qid in completed_quests:
					if bool(completed_quests[qid]):
						cq[qid] = true
		if &"quest_progress" in mission_mgr:
			var qp = mission_mgr.get(&"quest_progress")
			if qp is Dictionary:
				for qid in quest_progress:
					qp[qid] = maxi(int(qp.get(qid, 0)), int(quest_progress[qid]))

func register_student(student: StudentData) -> void:
	if student and not student.id.is_empty():
		students[student.id] = student
		if not bonds.has(student.id):
			bonds[student.id] = student.bond_level
		if not bonds_exp.has(student.id):
			bonds_exp[student.id] = student.bond_exp

func state_to_json(state: Dictionary) -> String:
	return JSON.stringify(state, "\t")

func json_to_state(json_str: String) -> Dictionary:
	if json_str.strip_edges().is_empty():
		return {}
	var json := JSON.new()
	var err := json.parse(json_str)
	if err != OK:
		return {}
	if json.data is Dictionary:
		return json.data
	return {}

func serialize_game_state() -> Dictionary:
	var dcm = _get_day_cycle_manager()
	var day_val: int = dcm.current_day if dcm else current_day
	var hour_val: float = dcm.current_hour if dcm else current_hour
	var ap_val: int = dcm.current_ap if dcm else current_ap
	var max_ap_val: int = dcm.max_ap if dcm else max_ap

	var bonds_copy = bonds.duplicate(true)
	var bonds_exp_copy = bonds_exp.duplicate(true)
	for student_id in students:
		var student = students[student_id]
		if student is StudentData:
			bonds_copy[student_id] = student.bond_level
			bonds_exp_copy[student_id] = student.bond_exp

	var state: Dictionary = {
		"day": day_val,
		"hour": hour_val,
		"ap": ap_val,
		"max_ap": max_ap_val,
		"credits": credits,
		"bonds": bonds_copy,
		"bonds_exp": bonds_exp_copy,
		"inventory": inventory.duplicate(true),
		"unlocked_roguelike_cards": unlocked_roguelike_cards.duplicate(),
		"unlocked_skill_variants": unlocked_skill_variants.duplicate(true),
		"completed_quests": completed_quests.duplicate(true),
		"quest_progress": quest_progress.duplicate(true),
		"current_zone": current_zone,
		"playtime": playtime
	}
	return state

func deserialize_game_state(data: Dictionary) -> bool:
	if data.is_empty():
		return false

	var state_data: Dictionary = data
	if data.has("state") and data["state"] is Dictionary:
		state_data = data["state"]

	var dcm = _get_day_cycle_manager()
	if dcm:
		if state_data.has("day"):
			dcm.current_day = int(state_data["day"])
		if state_data.has("hour"):
			dcm.current_hour = float(state_data["hour"])
		if state_data.has("ap"):
			dcm.current_ap = int(state_data["ap"])
		if state_data.has("max_ap"):
			dcm.max_ap = int(state_data["max_ap"])

	if state_data.has("day"):
		current_day = int(state_data["day"])
	if state_data.has("hour"):
		current_hour = float(state_data["hour"])
	if state_data.has("ap"):
		current_ap = int(state_data["ap"])
	if state_data.has("max_ap"):
		max_ap = int(state_data["max_ap"])
	if state_data.has("credits"):
		credits = int(state_data["credits"])
	if state_data.has("bonds") and state_data["bonds"] is Dictionary:
		bonds = state_data["bonds"].duplicate(true)
		for student_id in bonds:
			if students.has(student_id) and students[student_id] is StudentData:
				students[student_id].bond_level = int(bonds[student_id])
	if state_data.has("bonds_exp") and state_data["bonds_exp"] is Dictionary:
		bonds_exp = state_data["bonds_exp"].duplicate(true)
		for student_id in bonds_exp:
			if students.has(student_id) and students[student_id] is StudentData:
				students[student_id].bond_exp = int(bonds_exp[student_id])
	if state_data.has("inventory") and state_data["inventory"] is Array:
		inventory = state_data["inventory"].duplicate(true)
	unlocked_roguelike_cards.clear()
	if state_data.has("unlocked_roguelike_cards") and state_data["unlocked_roguelike_cards"] is Array:
		for raw_cid in state_data["unlocked_roguelike_cards"]:
			unlock_roguelike_card(str(raw_cid))
	if state_data.has("unlocked_skill_variants") and state_data["unlocked_skill_variants"] is Dictionary:
		unlocked_skill_variants = state_data["unlocked_skill_variants"].duplicate(true)
	else:
		unlocked_skill_variants = {}
	if state_data.has("completed_quests") and state_data["completed_quests"] is Dictionary:
		completed_quests = state_data["completed_quests"].duplicate(true)
	else:
		completed_quests = {}
	if state_data.has("quest_progress") and state_data["quest_progress"] is Dictionary:
		quest_progress = state_data["quest_progress"].duplicate(true)
	else:
		quest_progress = {}
	if state_data.has("current_zone"):
		current_zone = str(state_data["current_zone"])
	if state_data.has("playtime"):
		playtime = float(state_data["playtime"])

	var dcm_bus: Node = dcm._get_event_bus() if dcm != null and dcm.has_method("_get_event_bus") else null
	if dcm != null and dcm.has_method("_emit_ap_changed"):
		dcm._emit_ap_changed()
	var bus = _get_event_bus()
	if bus != null:
		if (dcm == null or dcm_bus != bus) and bus.has_signal("ap_changed"):
			bus.ap_changed.emit(current_ap, max_ap)
		if bus.has_signal("day_advanced"):
			bus.day_advanced.emit(current_day, false)

	return true

func save_game(slot: int) -> bool:
	if not _ensure_save_dir():
		push_error("SaveManager: Failed to create save directory: %s" % save_dir)
		return false

	var state: Dictionary = serialize_game_state()
	var timestamp: int = int(Time.get_unix_time_from_system())

	var payload: Dictionary = {
		"version": 1,
		"metadata": {
			"slot": slot,
			"day": state.get("day", 1),
			"playtime": state.get("playtime", 0.0),
			"timestamp": timestamp
		},
		"state": state
	}

	var json_str: String = state_to_json(payload)
	var file_path: String = _get_save_file_path(slot)
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: Failed to write save file: %s (error %d)" % [file_path, FileAccess.get_open_error()])
		return false

	file.store_string(json_str)
	file.close()

	current_slot = slot
	game_saved.emit(slot)
	return true

func load_game(slot: int) -> bool:
	var file_path: String = _get_save_file_path(slot)
	if not FileAccess.file_exists(file_path):
		return false

	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("SaveManager: Failed to open save file for reading: %s" % file_path)
		return false

	var json_str: String = file.get_as_text()
	file.close()

	var data = json_to_state(json_str)
	if data.is_empty():
		push_error("SaveManager: Corrupted save data in %s" % file_path)
		return false

	var success = deserialize_game_state(data)
	if success:
		current_slot = slot
		game_loaded.emit(slot)
	return success

func delete_save(slot: int) -> bool:
	var file_path: String = _get_save_file_path(slot)
	if not FileAccess.file_exists(file_path):
		return false

	var err = DirAccess.remove_absolute(file_path)
	if err == OK:
		save_deleted.emit(slot)
		return true
	return false

func get_save_slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(save_dir):
		return result

	var files = DirAccess.get_files_at(save_dir)
	for file_name in files:
		if file_name.begins_with("slot_") and file_name.ends_with(".json"):
			var slot_str = file_name.trim_prefix("slot_").trim_suffix(".json")
			if slot_str.is_valid_int():
				var slot_num = slot_str.to_int()
				var full_path = "%s/%s" % [save_dir, file_name]
				var file = FileAccess.open(full_path, FileAccess.READ)
				if file != null:
					var text = file.get_as_text()
					file.close()
					var data = json_to_state(text)
					var metadata: Dictionary = {}
					if data.has("metadata") and data["metadata"] is Dictionary:
						metadata = data["metadata"]

					var day_val: int = int(metadata.get("day", data.get("day", 1)))
					var playtime_val: float = float(metadata.get("playtime", data.get("playtime", 0.0)))
					var timestamp_val: int = int(metadata.get("timestamp", data.get("timestamp", 0)))

					result.append({
						"slot": slot_num,
						"day": day_val,
						"playtime": playtime_val,
						"timestamp": timestamp_val
					})

	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["slot"] < b["slot"])
	return result

func _get_save_file_path(slot: int) -> String:
	return save_dir.path_join("slot_%d.json" % slot)

func _ensure_save_dir() -> bool:
	if save_dir.is_empty():
		save_dir = get_save_root_dir()
	if not DirAccess.dir_exists_absolute(save_dir):
		var err = DirAccess.make_dir_recursive_absolute(save_dir)
		return err == OK
	return true

func _get_day_cycle_manager() -> Node:
	if day_cycle_manager != null:
		return day_cycle_manager
	if is_inside_tree():
		return get_node_or_null("/root/DayCycleManager")
	var loop = Engine.get_main_loop() as SceneTree
	if loop and loop.root:
		return loop.root.get_node_or_null("DayCycleManager")
	return null

func _get_event_bus() -> Node:
	if event_bus != null:
		return event_bus
	if is_inside_tree():
		return get_node_or_null("/root/EventBus")
	var loop = Engine.get_main_loop() as SceneTree
	if loop and loop.root:
		return loop.root.get_node_or_null("EventBus")
	return null
