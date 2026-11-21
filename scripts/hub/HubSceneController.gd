# scripts/hub/HubSceneController.gd
class_name HubSceneController
extends Node3D

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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_resolve_nodes()
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

func _connect_signals() -> void:
	if pause_menu != null:
		if not pause_menu.settings_requested.is_connected(_on_settings_requested):
			pause_menu.settings_requested.connect(_on_settings_requested)
		if not pause_menu.pause_toggled.is_connected(_on_pause_toggled):
			pause_menu.pause_toggled.connect(_on_pause_toggled)
	if phone_os != null:
		if not phone_os.phone_toggled.is_connected(_on_phone_toggled):
			phone_os.phone_toggled.connect(_on_phone_toggled)
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
	if sensei != null and is_instance_valid(sensei):
		if sensei.interactable_focused.is_connected(_on_interactable_focused):
			sensei.interactable_focused.disconnect(_on_interactable_focused)
	if settings_menu != null and is_instance_valid(settings_menu) and settings_menu.has_signal(&"back_requested"):
		if settings_menu.is_connected(&"back_requested", _close_settings_menu):
			settings_menu.disconnect(&"back_requested", _close_settings_menu)
