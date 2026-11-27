# scripts/hub/HubSceneController.gd
class_name HubSceneController
extends Node3D

const MissionTerminalScript := preload("res://scripts/hub/MissionTerminal.gd")
const SortieDispatchServiceScript := preload("res://scripts/combat/SortieDispatchService.gd")

@export var hud_path: NodePath
@export var sensei_path: NodePath
@export var phone_os_path: NodePath
@export var pause_menu_path: NodePath
@export var settings_menu_path: NodePath
@export var mod_manager_path: NodePath
@export var shittim_chest_path: NodePath

var hud: HUDManager = null
var sensei: SenseiController = null
var phone_os: PhoneOSManager = null
var pause_menu: PauseMenuManager = null
var settings_menu: Control = null
var mod_manager: ModManagerUI = null
var shittim_chest: ShittimChestSpaceManager = null
var mission_terminal: InteractableBase = null
var _sortie_service := SortieDispatchServiceScript.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_resolve_nodes()
	_ensure_mission_terminal()
	_connect_signals()
	if settings_menu != null:
		settings_menu.visible = false
	if mod_manager != null:
		mod_manager.visible = false
	_sync_mouse_mode()

func _exit_tree() -> void:
	_disconnect_signals()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	var key_event := event as InputEventKey
	match key_event.keycode:
		KEY_ESCAPE:
			_handle_escape()
		KEY_TAB, KEY_P:
			_handle_toggle_phone()
		KEY_F1:
			_handle_toggle_shittim_chest()

func _handle_escape() -> void:
	if settings_menu != null and settings_menu.visible:
		_close_settings_menu()
		return
	if mod_manager != null and mod_manager.visible:
		mod_manager.visible = false
		_sync_mouse_mode()
		return
	if phone_os != null and phone_os.is_open:
		phone_os.toggle()
		_sync_mouse_mode()
		return
	if pause_menu != null:
		pause_menu.toggle_pause()
		_sync_mouse_mode()

func _handle_toggle_phone() -> void:
	if pause_menu != null and pause_menu.is_paused:
		return
	if phone_os != null:
		phone_os.toggle()
		_sync_mouse_mode()

func _handle_toggle_shittim_chest() -> void:
	if pause_menu != null and pause_menu.is_paused:
		return
	if shittim_chest == null:
		return
	if shittim_chest.is_loaded:
		shittim_chest.exit_space()
	else:
		shittim_chest.enter_space()
	_sync_mouse_mode()

func _on_settings_requested() -> void:
	if settings_menu != null:
		settings_menu.visible = true
	if pause_menu != null:
		pause_menu.visible = false
	_sync_mouse_mode()

func _close_settings_menu() -> void:
	if settings_menu != null:
		settings_menu.visible = false
	if pause_menu != null and pause_menu.is_paused:
		pause_menu.visible = true
	_sync_mouse_mode()

func _on_interactable_focused(prompt_text: String, _target: Object) -> void:
	if hud != null:
		hud.update_interaction_prompt(prompt_text)

func _on_pause_toggled(_is_paused: bool) -> void:
	_sync_mouse_mode()

func _on_phone_toggled(_is_open: bool) -> void:
	_sync_mouse_mode()

func _sync_mouse_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var any_ui_open: bool = (
		(pause_menu != null and pause_menu.is_paused)
		or (phone_os != null and phone_os.is_open)
		or (settings_menu != null and settings_menu.visible)
		or (mod_manager != null and mod_manager.visible)
		or (shittim_chest != null and shittim_chest.is_loaded)
	)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if any_ui_open else Input.MOUSE_MODE_CAPTURED

func _resolve_nodes() -> void:
	hud = _find_typed_node(hud_path, HUDManager) as HUDManager
	sensei = _find_typed_node(sensei_path, SenseiController) as SenseiController
	phone_os = _find_typed_node(phone_os_path, PhoneOSManager) as PhoneOSManager
	pause_menu = _find_typed_node(pause_menu_path, PauseMenuManager) as PauseMenuManager
	mod_manager = _find_typed_node(mod_manager_path, ModManagerUI) as ModManagerUI
	shittim_chest = _find_typed_node(shittim_chest_path, ShittimChestSpaceManager) as ShittimChestSpaceManager

	if not settings_menu_path.is_empty():
		settings_menu = get_node_or_null(settings_menu_path) as Control
	if settings_menu == null:
		settings_menu = find_child("SettingsMenu", true, false) as Control

func _find_typed_node(explicit_path: NodePath, target_type: Variant) -> Node:
	if not explicit_path.is_empty():
		var direct := get_node_or_null(explicit_path)
		if direct != null and is_instance_of(direct, target_type):
			return direct
	return _search_children_by_type(self, target_type)

func _search_children_by_type(parent: Node, target_type: Variant) -> Node:
	for child in parent.get_children():
		if is_instance_of(child, target_type):
			return child
		var found := _search_children_by_type(child, target_type)
		if found != null:
			return found
	return null

func _ensure_mission_terminal() -> void:
	var existing := _search_children_by_type(self, MissionTerminalScript) as InteractableBase
	if existing != null:
		mission_terminal = existing
		return
	var desk := find_child("SenseiDesk", true, false) as Node3D
	if desk == null:
		return
	var term := MissionTerminalScript.new()
	term.name = "MissionTerminal"
	term.position = Vector3(-0.65, 0.65, 0.0)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.75, 0.55, 0.45)
	col.shape = box
	term.add_child(col)

	var screen := MeshInstance3D.new()
	screen.name = "TerminalScreenMesh"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.60, 0.36, 0.06)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.78, 0.98)
	mat.emission_enabled = true
	mat.emission = Color(0.16, 0.82, 1.0)
	mat.emission_energy_multiplier = 1.4
	mesh.material = mat
	screen.mesh = mesh
	screen.rotation.x = deg_to_rad(-18.0)
	term.add_child(screen)

	desk.add_child(term)
	mission_terminal = term

func _on_mission_terminal_activated(_terminal: Node) -> void:
	if phone_os != null:
		phone_os.open_tab("MISSIONS")
		_sync_mouse_mode()

func _on_sortie_launch_requested(
	mission_id: String,
	striker_ids: Array[String],
	special_ids: Array[String],
	challenge_modifiers: Array[String]
) -> void:
	var dcm: Node = get_node_or_null("/root/DayCycleManager") if is_inside_tree() else null
	var ztm: Node = get_node_or_null("/root/ZoneTransitionManager") if is_inside_tree() else null
	var cur_scene: String = scene_file_path if not scene_file_path.is_empty() else "res://scenes/hub/zones/schale_building.tscn"
	var res: Dictionary = _sortie_service.validate_and_launch_sortie(
		mission_id,
		striker_ids,
		special_ids,
		challenge_modifiers,
		dcm,
		ztm,
		cur_scene,
		true
	)
	if not bool(res.get("ok", false)):
		if phone_os != null:
			phone_os.set_mission_status(str(res.get("error", "Không thể xuất kích!")), true)
	elif phone_os != null:
		phone_os.set_mission_status("Đang xuất kích...", false)
		phone_os.refresh_live_panels()

func _connect_signals() -> void:
	if pause_menu != null:
		if not pause_menu.settings_requested.is_connected(_on_settings_requested):
			pause_menu.settings_requested.connect(_on_settings_requested)
		if not pause_menu.pause_toggled.is_connected(_on_pause_toggled):
			pause_menu.pause_toggled.connect(_on_pause_toggled)
	if phone_os != null:
		if not phone_os.phone_toggled.is_connected(_on_phone_toggled):
			phone_os.phone_toggled.connect(_on_phone_toggled)
		if phone_os.has_signal(&"sortie_launch_requested") and not phone_os.sortie_launch_requested.is_connected(_on_sortie_launch_requested):
			phone_os.sortie_launch_requested.connect(_on_sortie_launch_requested)
	if mission_terminal != null and mission_terminal.has_signal(&"terminal_activated"):
		if not mission_terminal.is_connected(&"terminal_activated", _on_mission_terminal_activated):
			mission_terminal.connect(&"terminal_activated", _on_mission_terminal_activated)
	if sensei != null:
		if not sensei.interactable_focused.is_connected(_on_interactable_focused):
			sensei.interactable_focused.connect(_on_interactable_focused)
	if settings_menu != null and settings_menu.has_signal(&"back_requested"):
		if not settings_menu.is_connected(&"back_requested", _close_settings_menu):
			settings_menu.connect(&"back_requested", _close_settings_menu)

func _disconnect_signals() -> void:
	if pause_menu != null and is_instance_valid(pause_menu):
		if pause_menu.settings_requested.is_connected(_on_settings_requested):
			pause_menu.settings_requested.disconnect(_on_settings_requested)
		if pause_menu.pause_toggled.is_connected(_on_pause_toggled):
			pause_menu.pause_toggled.disconnect(_on_pause_toggled)
	if phone_os != null and is_instance_valid(phone_os):
		if phone_os.phone_toggled.is_connected(_on_phone_toggled):
			phone_os.phone_toggled.disconnect(_on_phone_toggled)
		if phone_os.has_signal(&"sortie_launch_requested") and phone_os.sortie_launch_requested.is_connected(_on_sortie_launch_requested):
			phone_os.sortie_launch_requested.disconnect(_on_sortie_launch_requested)
	if mission_terminal != null and is_instance_valid(mission_terminal) and mission_terminal.has_signal(&"terminal_activated"):
		if mission_terminal.is_connected(&"terminal_activated", _on_mission_terminal_activated):
			mission_terminal.disconnect(&"terminal_activated", _on_mission_terminal_activated)
	if sensei != null and is_instance_valid(sensei):
		if sensei.interactable_focused.is_connected(_on_interactable_focused):
			sensei.interactable_focused.disconnect(_on_interactable_focused)
	if settings_menu != null and is_instance_valid(settings_menu) and settings_menu.has_signal(&"back_requested"):
		if settings_menu.is_connected(&"back_requested", _close_settings_menu):
			settings_menu.disconnect(&"back_requested", _close_settings_menu)
