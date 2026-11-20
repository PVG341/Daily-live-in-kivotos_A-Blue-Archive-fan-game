# tests/test_mod_loader.gd
extends SceneTree

const TEST_TMP_ROOT := "res://.test_tmp"
const TEST_MODS_DIR := "res://.test_tmp/mods"
const TEST_SETTINGS_PATH := "res://.test_tmp/mod_settings.json"

var _failed: bool = false

func check(cond: bool, msg: String) -> bool:
	if not cond:
		printerr("FAIL: " + msg)
		_failed = true
		quit(1)
		return false
	return true

func _remove_dir_recursive(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if file_name != "." and file_name != "..":
				var full_path := path.path_join(file_name)
				if dir.current_is_dir():
					_remove_dir_recursive(full_path)
				else:
					dir.remove(file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
		dir = null
	DirAccess.remove_absolute(path)

func _write_text_file(path: String, content: String) -> void:
	var dir_path := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(content)
		f.close()

func _init() -> void:
	var loader = load("res://scripts/core/ModLoader.gd").new()
	var event_bus = load("res://scripts/core/EventBus.gd").new()
	loader.event_bus = event_bus

	_remove_dir_recursive(TEST_TMP_ROOT)
	_run_tests(loader, event_bus)

	_remove_dir_recursive(TEST_TMP_ROOT)
	event_bus.free()
	loader.free()

	if _failed:
		quit(1)
		return

	print("PASS: test_mod_loader")
	quit(0)

func _run_tests(loader: Node, event_bus: Node) -> void:
	# 1. Test path resolution
	var mod_dir: String = loader.get_mod_root_dir()
	check(mod_dir.ends_with("mods"), "Mod directory should end with 'mods', got: " + mod_dir)

	# 2. Test full student JSON parsing
	var full_json := '{"id":"nonomi","student_name":"Izayoi Nonomi","role":"DAMAGE_DEALER","squad_slot":"STRIKER","base_hp":2800,"base_atk":380,"base_def":80,"base_speed":5.5,"attack_range":12.0,"attack_type":"HITSCAN","favorite_food":"parfait","favorite_gift":"gold_card","normal_model_path":"mods/students/nonomi/normal.glb","chibi_model_path":"mods/students/nonomi/chibi.glb","skills":[{"id":"minigun_sweep","name":"Minigun Sweep","cost":5,"cooldown":12.0,"aoe_radius":4.5,"effect_type":"damage"}]}'
	var nonomi: StudentData = loader.parse_student_json(full_json)
	if not check(nonomi != null, "Parsed full student JSON must not be null"):
		return
	check(nonomi.id == "nonomi", "Parsed student id must match")
	check(nonomi.student_name == "Izayoi Nonomi", "Parsed student_name must match")
	check(nonomi.role == StudentData.CombatRole.DAMAGE_DEALER, "Parsed role must match DAMAGE_DEALER")
	check(nonomi.squad_slot == StudentData.SquadSlot.STRIKER, "Parsed squad_slot must match STRIKER")
	check(nonomi.base_hp == 2800, "Parsed HP must match")
	check(nonomi.base_atk == 380, "Parsed ATK must match")
	check(nonomi.normal_model_path == "mods/students/nonomi/normal.glb", "Parsed normal_model_path must match")
	check(nonomi.chibi_model_path == "mods/students/nonomi/chibi.glb", "Parsed chibi_model_path must match")
	check(nonomi.skills.size() == 1 and nonomi.skills[0].id == "minigun_sweep", "Parsed skills must populate SkillData")

	# 3. Missing model fallback & resolve_model_path
	var minimal_student: StudentData = loader.parse_student_json('{"id":"arona","student_name":"Arona"}')
	if not check(minimal_student != null, "Minimal student JSON must parse"):
		return
	check(minimal_student.normal_model_path == loader.PLACEHOLDER_NORMAL_MODEL, "Missing normal_model_path should fall back to PLACEHOLDER_NORMAL_MODEL")
	check(minimal_student.chibi_model_path == loader.PLACEHOLDER_CHIBI_MODEL, "Missing chibi_model_path should fall back to PLACEHOLDER_CHIBI_MODEL")
	check(loader.resolve_model_path("nonexistent.glb", true) == loader.PLACEHOLDER_CHIBI_MODEL, "Missing chibi model file should resolve to PLACEHOLDER_CHIBI_MODEL")
	check(loader.resolve_model_path("nonexistent.glb", false) == loader.PLACEHOLDER_NORMAL_MODEL, "Missing normal model file should resolve to PLACEHOLDER_NORMAL_MODEL")

	var existing_file_path := TEST_TMP_ROOT.path_join("dummy_model.glb")
	_write_text_file(existing_file_path, "dummy")
	check(loader.resolve_model_path(existing_file_path, false) == existing_file_path, "Existing model path should be returned as-is")

	# 4. Invalid JSON handling (must return null without crashing)
	check(loader.parse_student_json("not valid json") == null, "Invalid JSON must return null")
	check(loader.parse_student_json("") == null, "Empty JSON must return null")
	check(loader.parse_student_json("[1, 2, 3]") == null, "Non-dictionary JSON must return null")

	# 5. Mod enable/disable tracking
	loader.settings_path = TEST_SETTINGS_PATH
	check(loader.is_mod_enabled("unknown_mod") == true, "Unknown mod should default to enabled")
	loader.set_mod_enabled("test_mod", false)
	check(loader.is_mod_enabled("test_mod") == false, "Disabled mod should return false")
	loader.set_mod_enabled("test_mod", true)
	check(loader.is_mod_enabled("test_mod") == true, "Re-enabled mod should return true")

	# 6. Scanning a temporary mod directory & EventBus.mod_loaded emission
	var sample_mod_dir := TEST_MODS_DIR.path_join("sample_mod")
	_write_text_file(sample_mod_dir.path_join("mod_info.json"), '{"id":"sample_mod","name":"Sample Abydos Mod","version":"1.0.0","author":"Sensei"}')
	_write_text_file(sample_mod_dir.path_join("students/shiroko.json"), '{"id":"shiroko_mod","student_name":"Shiroko (Mod)","role":"TANKER","squad_slot":"SPECIAL","base_hp":4000,"base_atk":220}')

	var loaded_events: Array = []
	event_bus.mod_loaded.connect(func(mod_id: String): loaded_events.append(mod_id))

	loader.mod_root_dir = TEST_MODS_DIR
	var mods: Array[Dictionary] = loader.scan_and_load_mods()
	check(mods.size() == 1, "Expected 1 loaded mod, got: %d" % mods.size())
	check(mods[0].get("id") == "sample_mod", "Loaded mod id must match 'sample_mod'")
	check(loader.get_loaded_mods().size() == 1, "get_loaded_mods() should return 1 mod")
	check(loaded_events.size() == 1 and loaded_events[0] == "sample_mod", "EventBus.mod_loaded('sample_mod') must be emitted")
	check(loader.loaded_students.has("shiroko_mod"), "Loaded student 'shiroko_mod' should be registered")
	var shiroko: StudentData = loader.loaded_students.get("shiroko_mod")
	check(shiroko != null and shiroko.role == StudentData.CombatRole.TANKER and shiroko.squad_slot == StudentData.SquadSlot.SPECIAL, "Loaded mod student enum fields must match")

	# Disabled mod should be skipped on scan
	loaded_events.clear()
	loader.set_mod_enabled("sample_mod", false)
	var mods_after_disable: Array[Dictionary] = loader.scan_and_load_mods()
	check(mods_after_disable.size() == 0, "Disabled mod should be skipped during scan")
	check(loaded_events.size() == 0, "Disabled mod should not emit mod_loaded")

	# Verify settings persistence to disk
	check(FileAccess.file_exists(TEST_SETTINGS_PATH), "mod_settings.json should be persisted on disk")
	var loader2 = load("res://scripts/core/ModLoader.gd").new()
	loader2.settings_path = TEST_SETTINGS_PATH
	loader2._load_mod_settings()
	check(loader2.is_mod_enabled("sample_mod") == false, "Persisted disabled mod state should load in new instance")
	loader2.free()

	# Direct load_student_from_json check
	var loaded_from_file: StudentData = loader.load_student_from_json(sample_mod_dir.path_join("students/shiroko.json"))
	check(loaded_from_file != null and loaded_from_file.id == "shiroko_mod", "load_student_from_json should load valid file")
	check(loader.load_student_from_json(TEST_TMP_ROOT.path_join("does_not_exist.json")) == null, "load_student_from_json on missing file should return null")

	# Non-existent mod_root_dir check
	loader.mod_root_dir = TEST_TMP_ROOT.path_join("nonexistent_mods_dir")
	check(loader.scan_and_load_mods().size() == 0, "Missing mod_root_dir should return empty array cleanly")

	# Missing .pck package check
	check(loader.load_pck_package(TEST_TMP_ROOT.path_join("missing.pck")) == false, "Nonexistent .pck should return false")
