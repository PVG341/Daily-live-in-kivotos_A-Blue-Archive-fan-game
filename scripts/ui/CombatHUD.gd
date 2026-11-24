# scripts/ui/CombatHUD.gd
class_name CombatHUD
extends CanvasLayer

signal commander_tool_clicked(tool_id: String)
signal striker_portrait_clicked(student_id: String)

var displayed_cost: float = 0.0
var displayed_max_cost: float = 10.0
var displayed_wave: int = 1
var striker_hp: Dictionary = {}
var striker_orders: Dictionary = {}
var selected_striker_ids: Array[String] = []
var displayed_selection_summary: String = ""
var displayed_sector_summary: String = ""
var active_buff_ids: Array[String] = []
var active_tool_id: String = "NONE"
var _tool_buttons: Dictionary = {}

func _ready() -> void:
	_ensure_commander_toolbar()
	_ensure_sector_progress_label()
	update_cost(displayed_cost, displayed_max_cost)
	update_wave(displayed_wave)
	_refresh_buff_row()
	set_active_commander_tool("NONE")

func _ensure_sector_progress_label() -> void:
	if find_child("SectorProgressLabel", true, false) != null:
		return
	var lbl := Label.new()
	lbl.name = "SectorProgressLabel"
	lbl.offset_left = 188.0
	lbl.offset_top = 24.0
	lbl.offset_right = 880.0
	lbl.offset_bottom = 52.0
	lbl.modulate = Color(0.55, 0.92, 1.0, 1.0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.text = displayed_sector_summary
	add_child(lbl)

func update_sector_progress(active_index: int, layout: Array[Dictionary]) -> void:
	_ensure_sector_progress_label()
	var parts: Array[String] = []
	for i in range(layout.size()):
		var rtype: String = str(layout[i].get("room_type", "COMBAT"))
		if i < active_index:
			parts.append("✓ %s" % rtype)
		elif i == active_index:
			parts.append("▶ [%d/%d %s]" % [i + 1, layout.size(), rtype])
		else:
			parts.append("%s" % rtype)
	displayed_sector_summary = "Chiến trường Seamless: " + " ➔ ".join(parts) if not parts.is_empty() else ""
	var lbl := find_child("SectorProgressLabel", true, false) as Label
	if lbl != null:
		lbl.text = displayed_sector_summary

func _ensure_commander_toolbar() -> void:
	if find_child("CommanderToolBar", true, false) != null:
		return
	var bar := HBoxContainer.new()
	bar.name = "CommanderToolBar"
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = 24.0
	bar.offset_top = -164.0
	bar.offset_right = 680.0
	bar.offset_bottom = -128.0
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.add_theme_constant_override("separation", 8)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)

	var defs: Array[Dictionary] = [
		{"id": "ASSAULT", "label": "⚔️ Giao Tranh [Z / ZZ]"},
		{"id": "DEFENSE", "label": "🛡️ Phòng Thủ [V / VV]"},
		{"id": "FREESHOT", "label": "💣 Freeshot [B / BB]"},
		{"id": "HOLD_FIRE", "label": "🚫 Giữ Hỏa Lực [H]"},
		{"id": "CLEAR", "label": "✖ Hủy Chọn [G]"},
		{"id": "CLEAR_ALL", "label": "✖ Hủy Hết [Shift+G]"},
	]
	for item: Dictionary in defs:
		var tid: String = str(item["id"])
		var btn := Button.new()
		btn.name = "ToolBtn_%s" % tid
		btn.text = str(item["label"])
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(func() -> void: commander_tool_clicked.emit(tid))
		bar.add_child(btn)
		_tool_buttons[tid] = btn

func set_active_commander_tool(tool_id: String) -> void:
	active_tool_id = tool_id
	for tid: String in _tool_buttons:
		var btn: Button = _tool_buttons[tid] as Button
		if btn == null or not is_instance_valid(btn):
			continue
		if tid == active_tool_id and tid != "NONE":
			btn.modulate = Color(1.0, 0.85, 0.25)
		else:
			btn.modulate = Color.WHITE

func update_cost(current: float, max_cost: float = 10.0) -> void:
	displayed_cost = current
	displayed_max_cost = max_cost
	var cost_bar := find_child("CostProgressBar", true, false) as ProgressBar
	if cost_bar != null:
		cost_bar.max_value = maxf(0.001, max_cost)
		cost_bar.value = clampf(current, 0.0, cost_bar.max_value)

func update_striker_hp(student_id: String, current_hp: int, max_hp: int) -> void:
	striker_hp[student_id] = Vector2i(current_hp, max_hp)
	_refresh_striker_portraits()

func update_wave(wave_index: int) -> void:
	displayed_wave = wave_index
	var wave_label := find_child("WaveLabel", true, false) as Label
	if wave_label != null:
		wave_label.text = "Wave %d" % wave_index

func update_selected_units(selected_ids: Array[String], summary_text: String = "") -> void:
	selected_striker_ids = selected_ids.duplicate()
	if not summary_text.strip_edges().is_empty():
		displayed_selection_summary = summary_text
	elif selected_striker_ids.is_empty():
		displayed_selection_summary = "Mặc định: Click/Kéo chọn lính [F1-F4/~] | [Z] Giao tranh [V] Phòng thủ [B] Freeshot [H] Giữ hỏa lực"
	else:
		displayed_selection_summary = "Đang chọn (%d): %s — Chọn công cụ [Z/V/B] rồi Click bản đồ" % [selected_striker_ids.size(), ", ".join(selected_striker_ids)]

	var sel_lbl := find_child("SelectedUnitsLabel", true, false) as Label
	if sel_lbl != null:
		sel_lbl.text = displayed_selection_summary
	_refresh_striker_portraits()

func update_commander_status(summary_text: String) -> void:
	displayed_selection_summary = summary_text
	var sel_lbl := find_child("SelectedUnitsLabel", true, false) as Label
	if sel_lbl != null:
		sel_lbl.text = summary_text

func update_striker_order(student_id: String, order_type: String) -> void:
	if order_type.is_empty():
		striker_orders.erase(student_id)
	else:
		striker_orders[student_id] = order_type
	_refresh_striker_portraits()

func set_active_buff_ids(buff_ids: Array[String]) -> void:
	active_buff_ids = buff_ids.duplicate()
	_refresh_buff_row()

func clear_hud() -> void:
	striker_hp.clear()
	striker_orders.clear()
	selected_striker_ids.clear()
	active_buff_ids.clear()
	displayed_selection_summary = ""
	displayed_sector_summary = ""
	var sector_lbl := find_child("SectorProgressLabel", true, false) as Label
	if sector_lbl != null:
		sector_lbl.text = ""
	var sel_lbl := find_child("SelectedUnitsLabel", true, false) as Label
	if sel_lbl != null:
		sel_lbl.text = "Mặc định: Click/Kéo chọn lính [F1-F4/~] | [Z] Giao tranh [V] Phòng thủ [B] Freeshot [H] Giữ hỏa lực"
	_refresh_striker_portraits()
	_refresh_buff_row()
	set_active_commander_tool("NONE")

func _refresh_striker_portraits() -> void:
	var portraits := find_child("StrikerPortraits", true, false) as Container
	if portraits == null:
		return
	for child in portraits.get_children():
		var child_name: String = str(child.name)
		var keep: bool = false
		for sid in striker_hp:
			if child_name == "Portrait_%s" % sid:
				keep = true
				break
		if not keep:
			portraits.remove_child(child)
			child.free()
	for sid in striker_hp:
		var hp_vec: Vector2i = striker_hp[sid]
		var existing := portraits.get_node_or_null("Portrait_%s" % sid) as Label
		if existing == null:
			existing = Label.new()
			existing.name = "Portrait_%s" % sid
			existing.mouse_filter = Control.MOUSE_FILTER_STOP
			existing.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			existing.gui_input.connect(_on_portrait_gui_input.bind(sid))
			portraits.add_child(existing)
		var is_sel: bool = selected_striker_ids.has(sid)
		var order_str: String = str(striker_orders.get(sid, ""))
		var order_tag: String = " (%s)" % order_str if not order_str.is_empty() else ""
		var base_text: String = "%s: %d/%d%s" % [sid, hp_vec.x, hp_vec.y, order_tag]
		existing.text = "★ [%s]" % base_text if is_sel else base_text
		existing.modulate = Color(0.35, 0.95, 1.0) if is_sel else Color.WHITE

func _on_portrait_gui_input(event: InputEvent, student_id: String) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			striker_portrait_clicked.emit(student_id)
			get_viewport().set_input_as_handled()

func _refresh_buff_row() -> void:
	var buff_row := find_child("BuffRow", true, false) as Container
	if buff_row == null:
		return
	for child in buff_row.get_children():
		buff_row.remove_child(child)
		child.free()
	for buff_id in active_buff_ids:
		var lbl := Label.new()
		lbl.text = buff_id
		buff_row.add_child(lbl)
