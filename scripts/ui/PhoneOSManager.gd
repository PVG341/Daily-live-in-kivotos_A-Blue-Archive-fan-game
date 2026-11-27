# scripts/ui/PhoneOSManager.gd
class_name PhoneOSManager
extends Control

const SortieDispatchServiceScript := preload("res://scripts/combat/SortieDispatchService.gd")
const ProgressionManagerScript := preload("res://scripts/core/ProgressionManager.gd")

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
signal sortie_launch_requested(mission_id: String, striker_ids: Array[String], special_ids: Array[String], challenge_modifiers: Array[String])

var is_open: bool = false
var active_tab: String = "CONTACTS"
var student_skins: Dictionary = {}
var current_bgm_track: String = "Constant Moderato"

var _sortie_service := SortieDispatchServiceScript.new()
var _selected_mission_id: String = "schale_patrol_normal"
var _selected_strikers: Array[String] = ["hoshino", "shiroko", "serika", "hanae"]
var _selected_specials: Array[String] = ["hibiki", "serina"]
var _selected_modifiers: Array[String] = []
var _missions_ui_built: bool = false
var _inventory_ui_built: bool = false
var _ui_styles: Dictionary = {}

func _ready() -> void:
	visible = is_open
	_setup_tab_bar()
	_build_missions_ui()
	_build_inventory_ui()
	_update_tab_panels()
	refresh_live_panels()

func toggle() -> bool:
	is_open = not is_open
	visible = is_open
	if is_open:
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		refresh_live_panels()
	phone_toggled.emit(is_open)
	return is_open

func open_tab(tab_name: String) -> void:
	if VALID_TABS.has(tab_name):
		switch_tab(tab_name)
	if not is_open:
		toggle()
	else:
		refresh_live_panels()

func switch_tab(tab_name: String) -> bool:
	if not VALID_TABS.has(tab_name):
		return false
	active_tab = tab_name
	_update_tab_panels()
	_sync_tab_bar_selection()
	refresh_live_panels()
	tab_switched.emit(tab_name)
	return true

func set_mission_status(message: String, is_error: bool = false) -> void:
	var status_lbl := find_child("MissionStatusLabel", true, false) as Label
	if status_lbl == null:
		return
	status_lbl.text = message
	status_lbl.add_theme_color_override(
		"font_color",
		Color(1.0, 0.42, 0.42) if is_error else Color(0.45, 0.95, 0.65)
	)

func get_selected_mission_id() -> String:
	return _selected_mission_id

func get_selected_striker_ids() -> Array[String]:
	return _selected_strikers.duplicate()

func get_selected_special_ids() -> Array[String]:
	return _selected_specials.duplicate()

func get_selected_modifiers() -> Array[String]:
	return _selected_modifiers.duplicate()

func refresh_live_panels(day_cycle_override: Node = null, save_mgr_override: Node = null, mod_loader_override: Node = null) -> void:
	var dcm: Node = day_cycle_override if day_cycle_override != null else (get_node_or_null("/root/DayCycleManager") if is_inside_tree() else null)
	var save_mgr: Node = save_mgr_override if save_mgr_override != null else (get_node_or_null("/root/SaveManager") if is_inside_tree() else null)
	var mod_loader: Node = mod_loader_override if mod_loader_override != null else (get_node_or_null("/root/ModLoader") if is_inside_tree() else null)

	_refresh_missions_panel(dcm, save_mgr, mod_loader)
	_refresh_inventory_panel(save_mgr)

func _build_missions_ui() -> void:
	if _missions_ui_built:
		return
	var panel := find_child("MissionsPanel", true, false) as Control
	if panel == null:
		return
	_missions_ui_built = true

	var scroll := ScrollContainer.new()
	scroll.name = "MissionsScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var root_box := VBoxContainer.new()
	root_box.name = "MissionsRoot"
	root_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_box.add_theme_constant_override("separation", 8)
	scroll.add_child(root_box)

	var header := Label.new()
	header.name = "MissionHeaderLabel"
	header.text = "AP: 100/100 | Credits: 0 | Thưởng: 1.00x"
	header.add_theme_color_override("font_color", Color(0.45, 0.90, 1.0))
	root_box.add_child(header)

	var m_title := Label.new()
	m_title.text = "1. Chọn Phó bản Xuất kích:"
	root_box.add_child(m_title)

	var m_row := HBoxContainer.new()
	m_row.name = "MissionButtonsRow"
	m_row.add_theme_constant_override("separation", 6)
	root_box.add_child(m_row)
	for m in _sortie_service.get_mission_catalog():
		var mid: String = str(m.get("id", ""))
		var btn := Button.new()
		btn.name = "MissionBtn_%s" % mid
		btn.text = "%s\n(%d AP)" % [str(m.get("title", mid)), int(m.get("ap_cost", 20))]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_mission_selected.bind(mid))
		m_row.add_child(btn)

	var desc := Label.new()
	desc.name = "MissionDescLabel"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_box.add_child(desc)

	var mod_title := Label.new()
	mod_title.text = "2. Challenge Modifiers (Tùy chọn tăng thưởng):"
	root_box.add_child(mod_title)

	var mod_row := HBoxContainer.new()
	mod_row.name = "ModifiersBox"
	mod_row.add_theme_constant_override("separation", 8)
	root_box.add_child(mod_row)
	var mod_labels: Dictionary = {
		"ENEMY_SPEED_UP": "Địch Nhanh (+15%)",
		"NO_REST_ROOMS": "Không Trạm Nghỉ (+25%)",
		"DOUBLE_BOSS_PHASE": "Boss Cuồng Nộ (+35%)",
	}
	for mod_id in ProgressionManagerScript.CHALLENGE_MODIFIER_WEIGHTS:
		var cb := CheckBox.new()
		cb.name = "ModCheck_%s" % str(mod_id)
		cb.text = str(mod_labels.get(mod_id, str(mod_id)))
		cb.toggled.connect(_on_modifier_toggled.bind(str(mod_id)))
		mod_row.add_child(cb)

	var st_title := Label.new()
	st_title.text = "3. Đội hình Striker (Tối đa 4):"
	root_box.add_child(st_title)

	var st_row := HBoxContainer.new()
	st_row.name = "StrikersRow"
	st_row.add_theme_constant_override("separation", 6)
	root_box.add_child(st_row)

	var sp_title := Label.new()
	sp_title.text = "4. Đội hình Special Chi viện (Tối đa 2):"
	root_box.add_child(sp_title)

	var sp_row := HBoxContainer.new()
	sp_row.name = "SpecialsRow"
	sp_row.add_theme_constant_override("separation", 6)
	root_box.add_child(sp_row)

	var status_lbl := Label.new()
	status_lbl.name = "MissionStatusLabel"
	status_lbl.text = "Chọn nhiệm vụ và đội hình để bắt đầu."
	status_lbl.add_theme_color_override("font_color", Color(0.75, 0.88, 0.96))
	root_box.add_child(status_lbl)

	var launch_btn := Button.new()
	launch_btn.name = "LaunchSortieButton"
	launch_btn.text = "🚀 XUẤT KÍCH (LAUNCH SORTIE)"
	launch_btn.custom_minimum_size = Vector2(0, 38)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.45, 0.72)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	_ui_styles["launch_btn"] = sb
	launch_btn.add_theme_stylebox_override("normal", sb)
	launch_btn.pressed.connect(_on_launch_sortie_pressed)
	root_box.add_child(launch_btn)

func _build_inventory_ui() -> void:
	if _inventory_ui_built:
		return
	var panel := find_child("InventoryPanel", true, false) as Control
	if panel == null:
		return
	_inventory_ui_built = true

	var scroll := ScrollContainer.new()
	scroll.name = "InventoryScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var root_box := VBoxContainer.new()
	root_box.name = "InventoryRoot"
	root_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_box.add_theme_constant_override("separation", 8)
	scroll.add_child(root_box)

	var sum_lbl := Label.new()
	sum_lbl.name = "InventorySummaryLabel"
	sum_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_box.add_child(sum_lbl)

	var items_lbl := Label.new()
	items_lbl.name = "InventoryItemsLabel"
	items_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_box.add_child(items_lbl)

func _refresh_missions_panel(dcm: Node, save_mgr: Node, mod_loader: Node) -> void:
	if not _missions_ui_built:
		_build_missions_ui()
	var header := find_child("MissionHeaderLabel", true, false) as Label
	if header != null:
		var ap_cur: int = int(dcm.get(&"current_ap")) if (dcm != null and &"current_ap" in dcm) else 100
		var ap_max: int = int(dcm.get(&"max_ap")) if (dcm != null and &"max_ap" in dcm) else 100
		var credits_val: int = int(save_mgr.get(&"credits")) if (save_mgr != null and &"credits" in save_mgr) else 0
		var mult: float = 1.0
		for mid in _selected_modifiers:
			mult += float(ProgressionManagerScript.CHALLENGE_MODIFIER_WEIGHTS.get(mid, 0.0))
		header.text = "AP: %d/%d  |  Credits: %d  |  Hệ số Thưởng: %.2fx" % [ap_cur, ap_max, credits_val, mult]

	var m_info: Dictionary = _sortie_service.get_mission_by_id(_selected_mission_id)
	var desc := find_child("MissionDescLabel", true, false) as Label
	if desc != null and not m_info.is_empty():
		desc.text = "%s — Phần thưởng gốc: %d Credits + Mở khóa thẻ [%s]" % [
			str(m_info.get("description", "")),
			int(m_info.get("reward_credits", 0)),
			str(m_info.get("reward_card_id", "")),
		]

	for m in _sortie_service.get_mission_catalog():
		var mid: String = str(m.get("id", ""))
		var btn := find_child("MissionBtn_%s" % mid, true, false) as Button
		if btn != null:
			btn.modulate = Color(0.45, 0.95, 1.0) if mid == _selected_mission_id else Color(0.85, 0.85, 0.88)

	_sync_roster_checkboxes(find_child("StrikersRow", true, false) as Container, _sortie_service.get_available_strikers(mod_loader), _selected_strikers, true)
	_sync_roster_checkboxes(find_child("SpecialsRow", true, false) as Container, _sortie_service.get_available_specials(mod_loader), _selected_specials, false)

func _sync_roster_checkboxes(container: Container, candidates: Array[Dictionary], selected_list: Array[String], is_striker: bool) -> void:
	if container == null:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.free()
	for c in candidates:
		var cid: String = str(c.get("id", ""))
		var cb := CheckBox.new()
		cb.name = "RosterCheck_%s" % cid
		var tag: String = str(c.get("weapon_class", c.get("skill", "")))
		var mod_mark: String = "[MOD] " if bool(c.get("is_mod", false)) else ""
		cb.text = "%s%s (%s)" % [mod_mark, str(c.get("name", cid)), tag]
		cb.button_pressed = selected_list.has(cid)
		cb.toggled.connect(_on_roster_toggled.bind(cid, is_striker, cb))
		container.add_child(cb)

func _refresh_inventory_panel(save_mgr: Node) -> void:
	if not _inventory_ui_built:
		_build_inventory_ui()
	var sum_lbl := find_child("InventorySummaryLabel", true, false) as Label
	var items_lbl := find_child("InventoryItemsLabel", true, false) as Label
	if sum_lbl == null or items_lbl == null:
		return
	if save_mgr == null:
		sum_lbl.text = "Credits: 0 | Thẻ đã mở khóa: 0 | Nhiệm vụ xong: 0"
		items_lbl.text = "(Chưa kết nối SaveManager)"
		return
	var cr: int = int(save_mgr.get(&"credits")) if &"credits" in save_mgr else 0
	var cards: Array = save_mgr.get(&"unlocked_roguelike_cards") if &"unlocked_roguelike_cards" in save_mgr else []
	var cquests: Dictionary = save_mgr.get(&"completed_quests") if &"completed_quests" in save_mgr else {}
	var last_sum: Dictionary = save_mgr.get(&"last_combat_summary") if &"last_combat_summary" in save_mgr else {}
	var lines: PackedStringArray = [
		"Credits: %d | Thẻ Roguelike mở khóa: %d | Quest xong: %d" % [cr, cards.size(), cquests.size()],
	]
	if not cards.is_empty():
		lines.append("Thẻ mở khóa: %s" % ", ".join(cards))
	if not last_sum.is_empty():
		lines.append("Trận gần nhất: %s — %s (+%d Credits)" % [
			str(last_sum.get("mission_title", "Dungeon")),
			"THẮNG" if bool(last_sum.get("victory", false)) else "THẤT BẠI",
			int(last_sum.get("credits_earned", 0)),
		])
	sum_lbl.text = "\n".join(lines)

	var inv: Array = save_mgr.get(&"inventory") if &"inventory" in save_mgr else []
	if inv.is_empty():
		items_lbl.text = "Kho vật phẩm: (Trống)"
	else:
		var inv_lines: PackedStringArray = ["Kho vật phẩm & Chiến lợi phẩm:"]
		for entry in inv:
			if entry is Dictionary:
				inv_lines.append("  • %s x%d" % [str(entry.get("id", "?")), int(entry.get("qty", 0))])
		items_lbl.text = "\n".join(inv_lines)

func _on_mission_selected(mission_id: String) -> void:
	_selected_mission_id = mission_id
	refresh_live_panels()

func _on_modifier_toggled(pressed: bool, mod_id: String) -> void:
	if pressed:
		if not _selected_modifiers.has(mod_id):
			_selected_modifiers.append(mod_id)
	else:
		_selected_modifiers.erase(mod_id)
	refresh_live_panels()

func _on_roster_toggled(pressed: bool, unit_id: String, is_striker: bool, cb: CheckBox) -> void:
	var target_list: Array[String] = _selected_strikers if is_striker else _selected_specials
	var max_count: int = 4 if is_striker else 2
	if pressed:
		if not target_list.has(unit_id):
			if target_list.size() >= max_count:
				cb.set_pressed_no_signal(false)
				set_mission_status("Tối đa %d thành viên ở vị trí này!" % max_count, true)
				return
			target_list.append(unit_id)
	else:
		if target_list.size() <= 1:
			cb.set_pressed_no_signal(true)
			set_mission_status("Phải có ít nhất 1 thành viên trong đội hình!", true)
			return
		target_list.erase(unit_id)

func _on_launch_sortie_pressed() -> void:
	sortie_launch_requested.emit(
		_selected_mission_id,
		_selected_strikers.duplicate(),
		_selected_specials.duplicate(),
		_selected_modifiers.duplicate()
	)

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

