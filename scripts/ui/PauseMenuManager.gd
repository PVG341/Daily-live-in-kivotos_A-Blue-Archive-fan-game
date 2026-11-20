# scripts/ui/PauseMenuManager.gd
class_name PauseMenuManager
extends Control

signal pause_toggled(is_paused: bool)
signal settings_requested()

var is_paused: bool = false
var save_manager: Node = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = is_paused
	_connect_buttons()

func toggle_pause() -> bool:
	is_paused = not is_paused
	visible = is_paused
	if is_inside_tree():
		get_tree().paused = is_paused
	if is_paused and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause_toggled.emit(is_paused)
	return is_paused

func request_save(slot: int = 1) -> bool:
	var manager := _get_save_manager()
	if manager != null and manager.has_method("save_game"):
		return bool(manager.save_game(slot))
	return false

func request_load(slot: int = 1) -> bool:
	var manager := _get_save_manager()
	if manager != null and manager.has_method("load_game"):
		return bool(manager.load_game(slot))
	return false

func _get_save_manager() -> Node:
	if save_manager != null:
		return save_manager
	if is_inside_tree():
		return get_node_or_null("/root/SaveManager")
	var loop := Engine.get_main_loop() as SceneTree
	if loop != null and loop.root != null:
		return loop.root.get_node_or_null("SaveManager")
	return null

func _connect_buttons() -> void:
	var resume_btn := find_child("ResumeButton", true, false) as Button
	if resume_btn != null and not resume_btn.pressed.is_connected(_on_resume_pressed):
		resume_btn.pressed.connect(_on_resume_pressed)

	var save_btn := find_child("SaveButton", true, false) as Button
	if save_btn != null and not save_btn.pressed.is_connected(_on_save_pressed):
		save_btn.pressed.connect(_on_save_pressed)

	var load_btn := find_child("LoadButton", true, false) as Button
	if load_btn != null and not load_btn.pressed.is_connected(_on_load_pressed):
		load_btn.pressed.connect(_on_load_pressed)

	var settings_btn := find_child("SettingsButton", true, false) as Button
	if settings_btn != null and not settings_btn.pressed.is_connected(_on_settings_pressed):
		settings_btn.pressed.connect(_on_settings_pressed)

	var quit_btn := find_child("QuitButton", true, false) as Button
	if quit_btn != null and not quit_btn.pressed.is_connected(_on_quit_pressed):
		quit_btn.pressed.connect(_on_quit_pressed)

func _on_resume_pressed() -> void:
	if is_paused:
		toggle_pause()

func _on_save_pressed() -> void:
	request_save(1)

func _on_load_pressed() -> void:
	request_load(1)

func _on_settings_pressed() -> void:
	settings_requested.emit()

func _on_quit_pressed() -> void:
	if is_inside_tree():
		get_tree().paused = false
		get_tree().quit()
