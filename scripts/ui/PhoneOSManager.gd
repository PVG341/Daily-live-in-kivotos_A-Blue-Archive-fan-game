# scripts/ui/PhoneOSManager.gd
class_name PhoneOSManager
extends Control

const VALID_TABS: Array[String] = ["INVENTORY", "MAP", "CONTACTS", "MISSIONS", "BGM"]

const TAB_PANEL_NAMES: Dictionary = {
	"INVENTORY": "InventoryPanel",
	"MAP": "MapPanel",
	"CONTACTS": "ContactsPanel",
	"MISSIONS": "MissionsPanel",
	"BGM": "BGMPanel",
}

signal phone_toggled(is_open: bool)
signal tab_switched(tab_name: String)
signal skin_changed(student_id: String, skin_id: String)
signal fast_travel_requested(zone_id: String)
signal bgm_track_selected(track_id: String)

var is_open: bool = false
var active_tab: String = "CONTACTS"
var student_skins: Dictionary = {}
var current_bgm_track: String = "Constant Moderato"

func _ready() -> void:
	visible = is_open
	_setup_tab_bar()
	_update_tab_panels()

func toggle() -> bool:
	is_open = not is_open
	visible = is_open
	if is_open and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	phone_toggled.emit(is_open)
	return is_open

func switch_tab(tab_name: String) -> bool:
	if not VALID_TABS.has(tab_name):
		return false
	active_tab = tab_name
	_update_tab_panels()
	_sync_tab_bar_selection()
	tab_switched.emit(tab_name)
	return true

func set_student_skin(student_id: String, skin_id: String) -> void:
	student_skins[student_id] = skin_id
	skin_changed.emit(student_id, skin_id)

func get_student_skin(student_id: String) -> String:
	return str(student_skins.get(student_id, "default"))

func select_bgm_track(track_id: String) -> void:
	current_bgm_track = track_id
	bgm_track_selected.emit(track_id)

func request_fast_travel(zone_id: String) -> void:
	fast_travel_requested.emit(zone_id)

func _setup_tab_bar() -> void:
	var tab_bar := find_child("TabBar", true, false) as TabBar
	if tab_bar == null:
		return
	if tab_bar.tab_count == 0:
		for tab_name in VALID_TABS:
			tab_bar.add_tab(tab_name)
	if not tab_bar.tab_changed.is_connected(_on_tab_bar_changed):
		tab_bar.tab_changed.connect(_on_tab_bar_changed)
	_sync_tab_bar_selection()

func _sync_tab_bar_selection() -> void:
	var tab_bar := find_child("TabBar", true, false) as TabBar
	if tab_bar == null:
		return
	var idx := VALID_TABS.find(active_tab)
	if idx >= 0 and idx < tab_bar.tab_count and tab_bar.current_tab != idx:
		tab_bar.current_tab = idx

func _on_tab_bar_changed(tab_index: int) -> void:
	if tab_index >= 0 and tab_index < VALID_TABS.size():
		var target_tab: String = VALID_TABS[tab_index]
		if target_tab != active_tab:
			switch_tab(target_tab)

func _update_tab_panels() -> void:
	for tab_key in TAB_PANEL_NAMES:
		var panel_name: String = TAB_PANEL_NAMES[tab_key]
		var panel := find_child(panel_name, true, false) as Control
		if panel != null:
			panel.visible = (tab_key == active_tab)
