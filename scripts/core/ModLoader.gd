# scripts/core/ModLoader.gd
extends Node

const PLACEHOLDER_NORMAL_MODEL: String = "res://assets/placeholders/placeholder_normal.glb"
const PLACEHOLDER_CHIBI_MODEL: String = "res://assets/placeholders/placeholder_chibi.glb"
const DEFAULT_MOD_SETTINGS_PATH: String = "user://mod_settings.json"

const ROLE_MAP: Dictionary = {
	"TANKER": StudentData.CombatRole.TANKER,
	"DAMAGE_DEALER": StudentData.CombatRole.DAMAGE_DEALER,
	"HEALER": StudentData.CombatRole.HEALER,
	"BUFFER": StudentData.CombatRole.BUFFER,
}

const SLOT_MAP: Dictionary = {
	"STRIKER": StudentData.SquadSlot.STRIKER,
	"SPECIAL": StudentData.SquadSlot.SPECIAL,
}

const RESERVED_ROOT_SUBDIRS: Array[String] = [
	"students",
	"packages",
	"models",
	"skins",
	"audio",
]

var mod_root_dir: String = ""
var settings_path: String = DEFAULT_MOD_SETTINGS_PATH
var event_bus: Node = null

var loaded_mods: Array[Dictionary] = []
var loaded_students: Dictionary = {}
var _mod_enabled_states: Dictionary = {}

func _init() -> void:
	mod_root_dir = get_mod_root_dir()
	_load_mod_settings()

func get_mod_root_dir() -> String:
	if OS.has_feature("editor"):
		return "res://mods"
	return OS.get_executable_path().get_base_dir().path_join("mods")

func scan_and_load_mods() -> Array[Dictionary]:
	loaded_mods.clear()
	loaded_students.clear()

	if mod_root_dir.is_empty():
		mod_root_dir = get_mod_root_dir()

	if not DirAccess.dir_exists_absolute(mod_root_dir):
		return get_loaded_mods()

	var dir := DirAccess.open(mod_root_dir)
	if dir == null:
		return get_loaded_mods()

	# Support flat layout if mod_root_dir directly contains mod_info.json / students / packages
	if _has_mod_contents(mod_root_dir):
		_load_single_mod(mod_root_dir, "default_mod")

	# Scan mod subdirectories
	var subdirs: PackedStringArray = dir.get_directories()
	subdirs.sort()
	for subdir_name in subdirs:
		if subdir_name.begins_with(".") or subdir_name in RESERVED_ROOT_SUBDIRS:
			continue
		var sub_path: String = mod_root_dir.path_join(subdir_name)
		if _has_mod_contents(sub_path) or _has_pck_files(sub_path):
			_load_single_mod(sub_path, subdir_name)

	# Scan top-level standalone .pck files directly inside mod_root_dir
	var root_files: PackedStringArray = dir.get_files()
	root_files.sort()
	for file_name in root_files:
		if file_name.to_lower().ends_with(".pck"):
			var pck_mod_id: String = file_name.get_basename()
			var full_pck_path: String = mod_root_dir.path_join(file_name)
			if not is_mod_enabled(pck_mod_id):
				loaded_mods.append({
					"id": pck_mod_id,
					"name": pck_mod_id,
					"version": "1.0.0",
					"author": "",
					"description": "",
					"path": full_pck_path,
					"enabled": false,
					"students": [],
					"packages": [],
				})
				continue
			if load_pck_package(full_pck_path):
				var pck_meta: Dictionary = {
					"id": pck_mod_id,
					"name": pck_mod_id,
					"version": "1.0.0",
					"author": "",
					"description": "",
					"path": full_pck_path,
					"enabled": true,
					"students": [],
					"packages": [full_pck_path],
				}
				loaded_mods.append(pck_meta)
				_emit_mod_loaded(pck_mod_id)

	return get_loaded_mods()

func parse_student_json(json_string: String) -> StudentData:
	var parsed = _parse_json_dict(json_string)
	if parsed == null:
		return null
	var data: Dictionary = parsed

	var student := StudentData.new()
	student.id = str(data.get("id", ""))
	student.student_name = str(data.get("student_name", ""))

	var role_str: String = str(data.get("role", "DAMAGE_DEALER")).strip_edges().to_upper()
	student.role = ROLE_MAP.get(role_str, StudentData.CombatRole.DAMAGE_DEALER)

	var slot_str: String = str(data.get("squad_slot", "STRIKER")).strip_edges().to_upper()
	student.squad_slot = SLOT_MAP.get(slot_str, StudentData.SquadSlot.STRIKER)

	var normal_path: String = str(data.get("normal_model_path", "")).strip_edges()
	student.normal_model_path = normal_path if not normal_path.is_empty() else PLACEHOLDER_NORMAL_MODEL

	var chibi_path: String = str(data.get("chibi_model_path", "")).strip_edges()
	student.chibi_model_path = chibi_path if not chibi_path.is_empty() else PLACEHOLDER_CHIBI_MODEL

	student.bond_level = int(data.get("bond_level", student.bond_level))
	student.bond_exp = int(data.get("bond_exp", student.bond_exp))
	student.base_hp = int(data.get("base_hp", student.base_hp))
	student.base_atk = int(data.get("base_atk", student.base_atk))
	student.base_def = int(data.get("base_def", student.base_def))
	student.base_speed = float(data.get("base_speed", student.base_speed))
	student.attack_range = float(data.get("attack_range", student.attack_range))
	student.attack_type = str(data.get("attack_type", student.attack_type))
	student.favorite_food = str(data.get("favorite_food", student.favorite_food))
	student.favorite_gift = str(data.get("favorite_gift", student.favorite_gift))

	if data.has("skills") and data["skills"] is Array:
		for skill_entry in data["skills"]:
			if skill_entry is Dictionary:
				student.skills.append(_parse_skill_dict(skill_entry))

	return student

func load_student_from_json(path: String) -> StudentData:
	var content := _read_text_file(path)
	if content.is_empty():
		return null
	return parse_student_json(content)

func resolve_model_path(path: String, is_chibi: bool = false) -> String:
	if not path.is_empty():
		if FileAccess.file_exists(path) or ResourceLoader.exists(path):
			return path
		if path.is_relative_path() and not mod_root_dir.is_empty():
			var mod_relative_path: String = mod_root_dir.path_join(path)
			if FileAccess.file_exists(mod_relative_path) or ResourceLoader.exists(mod_relative_path):
				return mod_relative_path
	return PLACEHOLDER_CHIBI_MODEL if is_chibi else PLACEHOLDER_NORMAL_MODEL

func load_pck_package(path: String) -> bool:
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	return ProjectSettings.load_resource_pack(path)

func get_loaded_mods() -> Array[Dictionary]:
	var copy: Array[Dictionary] = []
	for mod_meta in loaded_mods:
		copy.append(mod_meta.duplicate(true))
	return copy

func get_enabled_mods() -> Array[Dictionary]:
	var copy: Array[Dictionary] = []
	for mod_meta in loaded_mods:
		if bool(mod_meta.get("enabled", true)):
			copy.append(mod_meta.duplicate(true))
	return copy

func set_mod_enabled(mod_id: String, enabled: bool) -> void:
	if mod_id.is_empty():
		return
	_mod_enabled_states[mod_id] = enabled
	for mod_meta in loaded_mods:
		if str(mod_meta.get("id", "")) == mod_id:
			mod_meta["enabled"] = enabled
	_save_mod_settings()

func is_mod_enabled(mod_id: String) -> bool:
	return bool(_mod_enabled_states.get(mod_id, true))

func _load_single_mod(mod_dir: String, fallback_id: String) -> Dictionary:
	var info: Dictionary = {}
	var info_path: String = mod_dir.path_join("mod_info.json")
	if FileAccess.file_exists(info_path):
		var parsed_info = _parse_json_dict(_read_text_file(info_path))
		if parsed_info is Dictionary:
			info = parsed_info

	var mod_id: String = str(info.get("id", fallback_id)).strip_edges()
	if mod_id.is_empty():
		mod_id = fallback_id

	var enabled: bool = is_mod_enabled(mod_id)
	var mod_meta: Dictionary = {
		"id": mod_id,
		"name": str(info.get("name", mod_id)),
		"version": str(info.get("version", "1.0.0")),
		"author": str(info.get("author", "")),
		"description": str(info.get("description", "")),
		"path": mod_dir,
		"enabled": enabled,
		"students": [],
		"packages": [],
	}

	if not enabled:
		loaded_mods.append(mod_meta)
		return mod_meta

	var loaded_packages: Array[String] = []
	var packages_dir: String = mod_dir.path_join("packages")
	if DirAccess.dir_exists_absolute(packages_dir):
		loaded_packages.append_array(_load_pcks_in_dir(packages_dir))
	loaded_packages.append_array(_load_pcks_in_dir(mod_dir))

	var loaded_student_ids: Array[String] = []
	var students_dir: String = mod_dir.path_join("students")
	if DirAccess.dir_exists_absolute(students_dir):
		var sdir := DirAccess.open(students_dir)
		if sdir != null:
			var student_files: PackedStringArray = sdir.get_files()
			student_files.sort()
			for file_name in student_files:
				if file_name.to_lower().ends_with(".json"):
					var student := load_student_from_json(students_dir.path_join(file_name))
					if student != null and not student.id.is_empty():
						loaded_students[student.id] = student
						loaded_student_ids.append(student.id)

	mod_meta["students"] = loaded_student_ids
	mod_meta["packages"] = loaded_packages
	loaded_mods.append(mod_meta)
	_emit_mod_loaded(mod_id)
	return mod_meta

func _load_pcks_in_dir(dir_path: String) -> Array[String]:
	var loaded: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return loaded
	var files: PackedStringArray = dir.get_files()
	files.sort()
	for file_name in files:
		if file_name.to_lower().ends_with(".pck"):
			var full_path: String = dir_path.path_join(file_name)
			if load_pck_package(full_path):
				loaded.append(full_path)
	return loaded

func _has_mod_contents(dir_path: String) -> bool:
	return (
		FileAccess.file_exists(dir_path.path_join("mod_info.json"))
		or DirAccess.dir_exists_absolute(dir_path.path_join("students"))
		or DirAccess.dir_exists_absolute(dir_path.path_join("packages"))
	)

func _has_pck_files(dir_path: String) -> bool:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return false
	for file_name in dir.get_files():
		if file_name.to_lower().ends_with(".pck"):
			return true
	return false

func _parse_skill_dict(skill_dict: Dictionary) -> SkillData:
	var skill := SkillData.new()
	skill.id = str(skill_dict.get("id", ""))
	skill.name = str(skill_dict.get("name", ""))
	skill.cost = int(skill_dict.get("cost", skill.cost))
	skill.cooldown = float(skill_dict.get("cooldown", skill.cooldown))
	skill.aoe_radius = float(skill_dict.get("aoe_radius", skill.aoe_radius))
	skill.effect_type = str(skill_dict.get("effect_type", ""))
	return skill

func _parse_json_dict(json_string: String) -> Variant:
	if json_string.strip_edges().is_empty():
		return null
	var json := JSON.new()
	var err := json.parse(json_string)
	if err != OK:
		return null
	if json.data is Dictionary:
		return json.data
	return null

func _read_text_file(path: String) -> String:
	if path.is_empty() or not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var content := file.get_as_text()
	file.close()
	return content

func _load_mod_settings() -> void:
	if settings_path.is_empty() or not FileAccess.file_exists(settings_path):
		return
	var parsed = _parse_json_dict(_read_text_file(settings_path))
	if parsed is Dictionary:
		for key in parsed:
			_mod_enabled_states[str(key)] = bool(parsed[key])

func _save_mod_settings() -> void:
	if settings_path.is_empty():
		return
	var dir_path := settings_path.get_base_dir()
	if not dir_path.is_empty() and not DirAccess.dir_exists_absolute(dir_path):
		var mk_err := DirAccess.make_dir_recursive_absolute(dir_path)
		if mk_err != OK:
			return
	var file := FileAccess.open(settings_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_mod_enabled_states, "\t"))
	file.close()

func _get_event_bus() -> Node:
	if event_bus != null:
		return event_bus
	if is_inside_tree():
		return get_node_or_null("/root/EventBus")
	var loop := Engine.get_main_loop() as SceneTree
	if loop and loop.root:
		return loop.root.get_node_or_null("EventBus")
	return null

func _emit_mod_loaded(mod_id: String) -> void:
	var bus := _get_event_bus()
	if bus and bus.has_signal("mod_loaded"):
		bus.mod_loaded.emit(mod_id)
