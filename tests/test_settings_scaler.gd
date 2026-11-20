# tests/test_settings_scaler.gd
extends SceneTree

var _failed: bool = false
var _completed: bool = false
var _ran: bool = false

func check(cond: bool, msg: String) -> bool:
	if not cond:
		printerr("FAIL: " + msg)
		_failed = true
		quit(1)
		return false
	return true

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run_tests()

	if _failed or not _completed:
		quit(1)
		return true

	print("PASS: test_settings_scaler")
	quit(0)
	return true

func _cleanup_tmp_dir(tmp_dir: String, tmp_file: String) -> void:
	if FileAccess.file_exists(tmp_file):
		DirAccess.remove_absolute(tmp_file)
	if DirAccess.dir_exists_absolute(tmp_dir):
		DirAccess.remove_absolute(tmp_dir)

func _run_tests() -> void:
	# 1. Load SettingsManager script and verify autoload registration
	var settings_script: GDScript = load("res://scripts/core/SettingsManager.gd")
	if not check(settings_script != null and settings_script.can_instantiate(), "SettingsManager.gd must load and compile"):
		return

	var autoload_mgr: Node = root.get_node_or_null("SettingsManager")
	check(autoload_mgr != null, "SettingsManager must be registered as an autoload")

	var mgr: Node = settings_script.new()
	check(mgr is Node, "SettingsManager must extend Node")

	# Default values
	check(is_equal_approx(mgr.current_render_scale, 1.0), "Default render scale must be 1.0")
	check(is_equal_approx(mgr.current_draw_distance, 120.0), "Default draw distance must be 120.0")
	check(mgr.shadow_tier == 2, "Default shadow_tier must be 2")
	check(mgr.max_active_students == 5, "Default max_active_students must be 5")
	check(mgr.bloom_enabled == true, "Default bloom_enabled must be true")
	check(mgr.dof_enabled == false, "Default dof_enabled must be false")
	check(mgr.particles_enabled == true, "Default particles_enabled must be true")

	# Render scale updates and clamping [0.5, 1.0]
	mgr.apply_render_scale(0.75)
	check(is_equal_approx(mgr.current_render_scale, 0.75), "apply_render_scale(0.75) must set current_render_scale to 0.75")
	mgr.apply_render_scale(0.1)
	check(is_equal_approx(mgr.current_render_scale, 0.5), "apply_render_scale(< 0.5) must clamp to 0.5")
	mgr.apply_render_scale(2.0)
	check(is_equal_approx(mgr.current_render_scale, 1.0), "apply_render_scale(> 1.0) must clamp to 1.0")

	# Render scale & shadow tier viewport integration when inside tree
	root.add_child(mgr)
	mgr.apply_render_scale(0.8)
	check(is_equal_approx(root.scaling_3d_scale, 0.8), "apply_render_scale inside tree must update viewport scaling_3d_scale")
	mgr.apply_shadow_tier(1)
	check(root.positional_shadow_atlas_size == 1024, "apply_shadow_tier(1) inside tree must set viewport positional_shadow_atlas_size to 1024")
	mgr.apply_shadow_tier(3)
	check(root.positional_shadow_atlas_size == 4096, "apply_shadow_tier(3) inside tree must set viewport positional_shadow_atlas_size to 4096")
	mgr.apply_shadow_tier(0)
	check(root.positional_shadow_atlas_size == 0, "apply_shadow_tier(0) inside tree must set viewport positional_shadow_atlas_size to 0")
	root.remove_child(mgr)

	# Draw distance updates and clamping [50.0, 200.0]
	mgr.apply_draw_distance(80.0)
	check(is_equal_approx(mgr.current_draw_distance, 80.0), "apply_draw_distance(80.0) must set current_draw_distance to 80.0")
	mgr.apply_draw_distance(10.0)
	check(is_equal_approx(mgr.current_draw_distance, 50.0), "apply_draw_distance(< 50.0) must clamp to 50.0")
	mgr.apply_draw_distance(500.0)
	check(is_equal_approx(mgr.current_draw_distance, 200.0), "apply_draw_distance(> 200.0) must clamp to 200.0")

	# Shadow tier updates and clamping [0, 3]
	mgr.apply_shadow_tier(0)
	check(mgr.shadow_tier == 0, "apply_shadow_tier(0) must set shadow_tier to 0")
	mgr.apply_shadow_tier(3)
	check(mgr.shadow_tier == 3, "apply_shadow_tier(3) must set shadow_tier to 3")
	mgr.apply_shadow_tier(-2)
	check(mgr.shadow_tier == 0, "apply_shadow_tier(< 0) must clamp to 0")
	mgr.apply_shadow_tier(9)
	check(mgr.shadow_tier == 3, "apply_shadow_tier(> 3) must clamp to 3")

	# Max active students updates and clamping [1, 10]
	mgr.apply_max_active_students(3)
	check(mgr.max_active_students == 3, "apply_max_active_students(3) must set max_active_students to 3")
	mgr.apply_max_active_students(0)
	check(mgr.max_active_students == 1, "apply_max_active_students(< 1) must clamp to 1")
	mgr.apply_max_active_students(99)
	check(mgr.max_active_students == 10, "apply_max_active_students(> 10) must clamp to 10")

	# Toggles & apply_post_processing
	var pp_signals := [0]
	mgr.settings_changed.connect(func(): pp_signals[0] += 1)
	mgr.apply_post_processing(false, true, false)
	check(pp_signals[0] == 1, "apply_post_processing must emit settings_changed")
	check(mgr.bloom_enabled == false, "bloom_enabled must toggle to false")
	check(mgr.dof_enabled == true, "dof_enabled must toggle to true")
	check(mgr.particles_enabled == false, "particles_enabled must toggle to false")

	# 2. to_dict / from_dict round-trip and file persistence
	mgr.apply_render_scale(0.65)
	mgr.apply_draw_distance(150.0)
	mgr.apply_shadow_tier(1)
	mgr.apply_max_active_students(4)
	mgr.bloom_enabled = false
	mgr.dof_enabled = true
	mgr.particles_enabled = false

	var dict_data: Dictionary = mgr.to_dict()
	check(is_equal_approx(float(dict_data.get("render_scale", -1.0)), 0.65), "to_dict must include render_scale")
	check(is_equal_approx(float(dict_data.get("draw_distance", -1.0)), 150.0), "to_dict must include draw_distance")
	check(int(dict_data.get("shadow_tier", -1)) == 1, "to_dict must include shadow_tier")
	check(int(dict_data.get("max_active_students", -1)) == 4, "to_dict must include max_active_students")
	check(dict_data.get("bloom_enabled", true) == false, "to_dict must include bloom_enabled")
	check(dict_data.get("dof_enabled", false) == true, "to_dict must include dof_enabled")
	check(dict_data.get("particles_enabled", true) == false, "to_dict must include particles_enabled")

	var mgr2: Node = settings_script.new()
	mgr2.from_dict(dict_data)
	check(is_equal_approx(mgr2.current_render_scale, 0.65), "from_dict must restore render_scale")
	check(is_equal_approx(mgr2.current_draw_distance, 150.0), "from_dict must restore draw_distance")
	check(mgr2.shadow_tier == 1, "from_dict must restore shadow_tier")
	check(mgr2.max_active_students == 4, "from_dict must restore max_active_students")
	check(mgr2.bloom_enabled == false, "from_dict must restore bloom_enabled")
	check(mgr2.dof_enabled == true, "from_dict must restore dof_enabled")
	check(mgr2.particles_enabled == false, "from_dict must restore particles_enabled")

	var tmp_dir: String = "res://.test_tmp"
	var tmp_file: String = "res://.test_tmp/settings.json"
	_cleanup_tmp_dir(tmp_dir, tmp_file)

	mgr.settings_path = tmp_file
	check(mgr.save_settings() == true, "save_settings() must return true")
	check(FileAccess.file_exists(tmp_file), "save_settings() must write settings file")

	var mgr3: Node = settings_script.new()
	mgr3.settings_path = tmp_file
	check(mgr3.load_settings() == true, "load_settings() must return true")
	check(is_equal_approx(mgr3.current_render_scale, 0.65), "load_settings() must restore render_scale")
	check(is_equal_approx(mgr3.current_draw_distance, 150.0), "load_settings() must restore draw_distance")
	check(mgr3.shadow_tier == 1, "load_settings() must restore shadow_tier")
	check(mgr3.max_active_students == 4, "load_settings() must restore max_active_students")
	check(mgr3.bloom_enabled == false, "load_settings() must restore bloom_enabled")
	check(mgr3.dof_enabled == true, "load_settings() must restore dof_enabled")
	check(mgr3.particles_enabled == false, "load_settings() must restore particles_enabled")

	_cleanup_tmp_dir(tmp_dir, tmp_file)
	mgr.free()
	mgr2.free()
	mgr3.free()

	# 3. Shaders load and assign to ShaderMaterial
	var cel_shader: Resource = load("res://shaders/cel_toon_shader.gdshader")
	if not check(cel_shader != null and cel_shader is Shader, "cel_toon_shader.gdshader must load as Shader"):
		return
	var cel_mat := ShaderMaterial.new()
	cel_mat.shader = cel_shader
	check(cel_mat.shader == cel_shader, "ShaderMaterial must accept cel_toon_shader")
	var cel_uniforms: Array[String] = []
	for u in cel_shader.get_shader_uniform_list():
		cel_uniforms.append(str(u.get("name", "")))
	for expected_u in ["albedo_color", "albedo_texture", "shadow_color", "shadow_threshold", "shadow_smoothness"]:
		check(expected_u in cel_uniforms, "cel_toon_shader must expose uniform '%s'" % expected_u)

	var outline_shader: Resource = load("res://shaders/outline_shader.gdshader")
	if not check(outline_shader != null and outline_shader is Shader, "outline_shader.gdshader must load as Shader"):
		return
	var outline_mat := ShaderMaterial.new()
	outline_mat.shader = outline_shader
	check(outline_mat.shader == outline_shader, "ShaderMaterial must accept outline_shader")
	var outline_uniforms: Array[String] = []
	for u in outline_shader.get_shader_uniform_list():
		outline_uniforms.append(str(u.get("name", "")))
	for expected_u in ["outline_color", "outline_width"]:
		check(expected_u in outline_uniforms, "outline_shader must expose uniform '%s'" % expected_u)

	# 4. settings_menu.tscn instantiates cleanly with expected controls
	var menu_scene: PackedScene = load("res://scenes/ui/settings_menu.tscn")
	if not check(menu_scene != null, "scenes/ui/settings_menu.tscn must load"):
		return
	var menu_inst: Node = menu_scene.instantiate()
	if not check(menu_inst != null and menu_inst is Control and menu_inst.name == "SettingsMenu", "settings_menu.tscn root must be Control named SettingsMenu"):
		return
	var render_slider := menu_inst.find_child("RenderScaleSlider", true, false) as HSlider
	var draw_slider := menu_inst.find_child("DrawDistanceSlider", true, false) as HSlider
	var shadow_opt := menu_inst.find_child("ShadowTierOption", true, false) as OptionButton
	var students_spin := menu_inst.find_child("MaxActiveStudentsSpinBox", true, false) as SpinBox
	var bloom_cb := menu_inst.find_child("BloomCheckBox", true, false) as CheckBox
	var dof_cb := menu_inst.find_child("DOFCheckBox", true, false) as CheckBox
	var particles_cb := menu_inst.find_child("ParticlesCheckBox", true, false) as CheckBox
	var apply_btn := menu_inst.find_child("ApplyButton", true, false) as Button
	var reset_btn := menu_inst.find_child("ResetButton", true, false) as Button

	check(render_slider != null, "settings_menu.tscn must contain RenderScaleSlider HSlider")
	check(draw_slider != null, "settings_menu.tscn must contain DrawDistanceSlider HSlider")
	check(shadow_opt != null, "settings_menu.tscn must contain ShadowTierOption OptionButton")
	check(students_spin != null, "settings_menu.tscn must contain MaxActiveStudentsSpinBox SpinBox")
	check(bloom_cb != null, "settings_menu.tscn must contain BloomCheckBox CheckBox")
	check(dof_cb != null, "settings_menu.tscn must contain DOFCheckBox CheckBox")
	check(particles_cb != null, "settings_menu.tscn must contain ParticlesCheckBox CheckBox")
	check(apply_btn != null, "settings_menu.tscn must contain ApplyButton Button")
	check(reset_btn != null, "settings_menu.tscn must contain ResetButton Button")

	var orig_autoload_path: String = autoload_mgr.settings_path
	var ui_tmp_file: String = "res://.test_tmp/ui_settings.json"
	_cleanup_tmp_dir(tmp_dir, ui_tmp_file)
	autoload_mgr.settings_path = ui_tmp_file

	root.add_child(menu_inst)
	check(shadow_opt.item_count == 4, "ShadowTierOption must populate 4 tiers (Off, Low, Medium, High)")
	render_slider.value = 0.75
	draw_slider.value = 90.0
	shadow_opt.selected = 1
	students_spin.value = 3
	bloom_cb.button_pressed = false
	dof_cb.button_pressed = true
	particles_cb.button_pressed = false
	apply_btn.pressed.emit()
	check(is_equal_approx(autoload_mgr.current_render_scale, 0.75), "ApplyButton must apply render scale to SettingsManager")
	check(is_equal_approx(autoload_mgr.current_draw_distance, 90.0), "ApplyButton must apply draw distance to SettingsManager")
	check(autoload_mgr.shadow_tier == 1, "ApplyButton must apply shadow tier to SettingsManager")
	check(autoload_mgr.max_active_students == 3, "ApplyButton must apply max_active_students to SettingsManager")
	check(autoload_mgr.bloom_enabled == false and autoload_mgr.dof_enabled == true and autoload_mgr.particles_enabled == false, "ApplyButton must apply toggle states to SettingsManager")

	reset_btn.pressed.emit()
	check(is_equal_approx(autoload_mgr.current_render_scale, 1.0), "ResetButton must reset render scale to 1.0")
	check(autoload_mgr.max_active_students == 5, "ResetButton must reset max_active_students to 5")

	root.remove_child(menu_inst)
	menu_inst.free()
	autoload_mgr.settings_path = orig_autoload_path
	_cleanup_tmp_dir(tmp_dir, ui_tmp_file)

	_completed = true
