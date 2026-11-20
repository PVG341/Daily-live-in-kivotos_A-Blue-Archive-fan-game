# scripts/core/SettingsManager.gd
extends Node

signal settings_changed()

const DEFAULT_SETTINGS_PATH: String = "res://saves/settings.json"
const FALLBACK_SETTINGS_PATH: String = "user://settings.json"
const SHADOW_ATLAS_SIZES: Array[int] = [0, 1024, 2048, 4096]

var settings_path: String = ""
var current_render_scale: float = 1.0
var current_draw_distance: float = 120.0
var shadow_tier: int = 2
var max_active_students: int = 5
var bloom_enabled: bool = true
var dof_enabled: bool = false
var particles_enabled: bool = true

var _fallback_warned: bool = false

func _init() -> void:
	settings_path = _resolve_default_settings_path()

func _ready() -> void:
	if FileAccess.file_exists(settings_path):
		load_settings()
	else:
		apply_render_scale(current_render_scale)

func _resolve_default_settings_path() -> String:
	var portable_path: String
	if OS.has_feature("editor"):
		portable_path = DEFAULT_SETTINGS_PATH
	else:
		portable_path = OS.get_executable_path().get_base_dir().path_join("saves/settings.json")

	if _is_dir_writable(portable_path.get_base_dir()):
		return portable_path

	if not _fallback_warned:
		_fallback_warned = true
		push_warning("SettingsManager: Portable settings directory '%s' is not writable, falling back to '%s'" % [portable_path.get_base_dir(), FALLBACK_SETTINGS_PATH])
	return FALLBACK_SETTINGS_PATH

func _is_dir_writable(dir_path: String) -> bool:
	var existed: bool = DirAccess.dir_exists_absolute(dir_path)
	if not existed:
		var mk_err: Error = DirAccess.make_dir_recursive_absolute(dir_path)
		if mk_err != OK:
			return false

	var probe_path: String = dir_path.path_join(".settings_write_probe")
	var probe_file: FileAccess = FileAccess.open(probe_path, FileAccess.WRITE)
	if probe_file == null:
		if not existed:
			DirAccess.remove_absolute(dir_path)
		return false
	probe_file.close()
	DirAccess.remove_absolute(probe_path)

	if not existed:
		DirAccess.remove_absolute(dir_path)
	return true

func apply_render_scale(scale: float) -> void:
	current_render_scale = clampf(scale, 0.5, 1.0)
	if is_inside_tree():
		var vp: Viewport = get_viewport()
		if vp != null:
			vp.scaling_3d_scale = current_render_scale
	settings_changed.emit()

func apply_draw_distance(dist: float) -> void:
	current_draw_distance = clampf(dist, 50.0, 200.0)
	settings_changed.emit()

func apply_shadow_tier(tier: int) -> void:
	shadow_tier = clampi(tier, 0, 3)
	if is_inside_tree():
		var vp: Viewport = get_viewport()
		if vp != null:
			vp.positional_shadow_atlas_size = SHADOW_ATLAS_SIZES[shadow_tier]
	settings_changed.emit()

func apply_max_active_students(cap: int) -> void:
	max_active_students = clampi(cap, 1, 10)
	settings_changed.emit()

func apply_post_processing(p_bloom: bool, p_dof: bool, p_particles: bool) -> void:
	bloom_enabled = p_bloom
	dof_enabled = p_dof
	particles_enabled = p_particles
	settings_changed.emit()

func reset_to_defaults() -> void:
	apply_render_scale(1.0)
	apply_draw_distance(120.0)
	apply_shadow_tier(2)
	apply_max_active_students(5)
	apply_post_processing(true, false, true)

func to_dict() -> Dictionary:
	return {
		"render_scale": current_render_scale,
		"draw_distance": current_draw_distance,
		"shadow_tier": shadow_tier,
		"max_active_students": max_active_students,
		"bloom_enabled": bloom_enabled,
		"dof_enabled": dof_enabled,
		"particles_enabled": particles_enabled,
	}

func from_dict(data: Dictionary) -> void:
	if data.has("render_scale"):
		apply_render_scale(float(data["render_scale"]))
	if data.has("draw_distance"):
		apply_draw_distance(float(data["draw_distance"]))
	if data.has("shadow_tier"):
		apply_shadow_tier(int(data["shadow_tier"]))
	if data.has("max_active_students"):
		apply_max_active_students(int(data["max_active_students"]))
	if data.has("bloom_enabled"):
		bloom_enabled = bool(data["bloom_enabled"])
	if data.has("dof_enabled"):
		dof_enabled = bool(data["dof_enabled"])
	if data.has("particles_enabled"):
		particles_enabled = bool(data["particles_enabled"])
	settings_changed.emit()

func save_settings() -> bool:
	var target_path: String = settings_path if not settings_path.is_empty() else DEFAULT_SETTINGS_PATH
	var parent_dir: String = target_path.get_base_dir()
	if not parent_dir.is_empty() and parent_dir != "user://" and parent_dir != "res://":
		if not DirAccess.dir_exists_absolute(parent_dir):
			var mk_err: Error = DirAccess.make_dir_recursive_absolute(parent_dir)
			if mk_err != OK:
				push_error("SettingsManager: Failed to create settings directory: %s" % parent_dir)
				return false

	var file: FileAccess = FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		push_error("SettingsManager: Failed to write settings file: %s (error %d)" % [target_path, FileAccess.get_open_error()])
		return false

	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	return true

func load_settings() -> bool:
	var target_path: String = settings_path if not settings_path.is_empty() else DEFAULT_SETTINGS_PATH
	if not FileAccess.file_exists(target_path):
		return false

	var file: FileAccess = FileAccess.open(target_path, FileAccess.READ)
	if file == null:
		push_error("SettingsManager: Failed to open settings file for reading: %s" % target_path)
		return false

	var text: String = file.get_as_text()
	file.close()
	if text.strip_edges().is_empty():
		return false

	var json := JSON.new()
	var err: Error = json.parse(text)
	if err != OK or not (json.data is Dictionary):
		push_error("SettingsManager: Invalid JSON in settings file: %s" % target_path)
		return false

	from_dict(json.data)
	return true
