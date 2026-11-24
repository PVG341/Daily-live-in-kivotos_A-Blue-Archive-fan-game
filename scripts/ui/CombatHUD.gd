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
var striker_meta: Dictionary = {}
var selected_striker_ids: Array[String] = []
var displayed_selection_summary: String = ""
var displayed_sector_summary: String = ""
var active_buff_ids: Array[String] = []
var active_tool_id: String = "NONE"

var _tool_buttons: Dictionary = {}
var _ui_styles: Dictionary = {}
var _last_cost_text: String = ""
var _last_ex_card_states: Dictionary = {}
var _slow_mo_active: bool = false

func _ready() -> void:
	_ensure_ba_theme_elements()
	_ensure_commander_toolbar()
	_ensure_sector_progress_label()
	update_cost(displayed_cost, displayed_max_cost)
	update_wave(displayed_wave)
	_refresh_buff_row()
	set_active_commander_tool("NONE")
	set_slow_mo_active(_slow_mo_active)

func _exit_tree() -> void:
	_ui_styles.clear()
	_last_ex_card_states.clear()

func _make_ba_panel_style(bg_col: Color, border_col: Color, border_w: int = 2, corner_r: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_col
	sb.border_color = border_col
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(corner_r)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb

func _get_cached_style(key: String, bg_col: Color, border_col: Color, border_w: int = 2, corner_r: int = 6) -> StyleBoxFlat:
	if _ui_styles.has(key):
		return _ui_styles[key] as StyleBoxFlat
	var sb := _make_ba_panel_style(bg_col, border_col, border_w, corner_r)
	_ui_styles[key] = sb
	return sb

func _ensure_ba_theme_elements() -> void:
	if find_child("TopHeaderBackdrop", true, false) == null:
		var header_panel := Panel.new()
		header_panel.name = "TopHeaderBackdrop"
		header_panel.offset_left = 12.0
		header_panel.offset_top = 12.0
		header_panel.offset_right = 304.0
		header_panel.offset_bottom = 48.0
		header_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		header_panel.add_theme_stylebox_override(
			"panel",
			_get_cached_style("top_header", Color(0.06, 0.11, 0.20, 0.86), Color(0.18, 0.72, 0.98, 0.90), 2, 6)
		)
		add_child(header_panel)
		move_child(header_panel, 0)

	var wave_lbl := find_child("WaveLabel", true, false) as Label
	if wave_lbl != null:
		wave_lbl.add_theme_color_override("font_color", Color(0.88, 0.96, 1.0, 1.0))

	var sel_lbl := find_child("SelectedUnitsLabel", true, false) as Label
	if sel_lbl != null:
		sel_lbl.add_theme_color_override("font_color", Color(0.82, 0.92, 1.0, 0.95))

	var cost_bar := find_child("CostProgressBar", true, false) as ProgressBar
	if cost_bar != null:
		cost_bar.show_percentage = false
		cost_bar.add_theme_stylebox_override(
			"background",
			_get_cached_style("cost_bg", Color(0.06, 0.10, 0.18, 0.92), Color(0.22, 0.45, 0.68, 0.85), 2, 6)
		)
		var fill_sb := StyleBoxFlat.new()
		fill_sb.bg_color = Color(0.08, 0.74, 0.98, 1.0)
		fill_sb.set_corner_radius_all(4)
		_ui_styles["cost_fill"] = fill_sb
		cost_bar.add_theme_stylebox_override("fill", fill_sb)
		if cost_bar.get_node_or_null("CostValueLabel") == null:
			var clbl := Label.new()
			clbl.name = "CostValueLabel"
			clbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			clbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			clbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			clbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			clbl.add_theme_color_override("font_color", Color(0.96, 0.99, 1.0, 1.0))
			clbl.add_theme_color_override("font_outline_color", Color(0.04, 0.08, 0.14, 0.95))
			clbl.add_theme_constant_override("outline_size", 3)
			clbl.text = "COST  0.0 / 10"
			cost_bar.add_child(clbl)

	if find_child("SlowMoBadge", true, false) == null:
		var slow_badge := Label.new()
		slow_badge.name = "SlowMoBadge"
		slow_badge.anchor_left = 1.0
		slow_badge.anchor_right = 1.0
		slow_badge.offset_left = -310.0
		slow_badge.offset_top = 48.0
		slow_badge.offset_right = -18.0
		slow_badge.offset_bottom = 74.0
		slow_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		slow_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slow_badge.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25, 1.0))
		slow_badge.add_theme_color_override("font_outline_color", Color(0.05, 0.07, 0.12, 0.95))
		slow_badge.add_theme_constant_override("outline_size", 3)
		slow_badge.text = "⏸ TACTICAL 0.25x [TAB]"
		slow_badge.visible = false
		add_child(slow_badge)

func _ensure_sector_progress_label() -> void:
	if find_child("SectorProgressLabel", true, false) != null:
		return
	var lbl := Label.new()
	lbl.name = "SectorProgressLabel"
	lbl.anchor_left = 1.0
	lbl.anchor_right = 1.0
	lbl.offset_left = -310.0
	lbl.offset_top = 16.0
	lbl.offset_right = -18.0
	lbl.offset_bottom = 44.0
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.modulate = Color(0.45, 0.92, 1.0, 1.0)
	lbl.add_theme_color_override("font_outline_color", Color(0.04, 0.08, 0.14, 0.9))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.text = displayed_sector_summary
	add_child(lbl)

## Updates the compact top-right seamless sector chain readout.
func update_sector_progress(active_index: int, layout: Array[Dictionary]) -> void:
	_ensure_sector_progress_label()
	var parts: Array[String] = []
	for i in range(layout.size()):
		var rtype: String = str(layout[i].get("room_type", "COMBAT"))
		var short_type: String = rtype.substr(0, mini(5, rtype.length()))
		if i < active_index:
			parts.append("✓%d" % (i + 1))
		elif i == active_index:
			parts.append("▶%d/%d %s" % [i + 1, layout.size(), short_type])
		else:
			parts.append("%d" % (i + 1))
	displayed_sector_summary = "Seamless: " + " ➔ ".join(parts) if not parts.is_empty() else ""
	var lbl := find_child("SectorProgressLabel", true, false) as Label
	if lbl != null:
		lbl.text = displayed_sector_summary

## Toggles the top-right Tactical Slow-Mo badge visibility.
func set_slow_mo_active(active: bool) -> void:
	_slow_mo_active = active
	var slow_badge := find_child("SlowMoBadge", true, false) as Label
	if slow_badge != null:
		slow_badge.visible = active

func _ensure_commander_toolbar() -> void:
	if find_child("CommanderToolBar", true, false) != null:
		return
	var bar := HBoxContainer.new()
	bar.name = "CommanderToolBar"
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = 18.0
	bar.offset_top = -138.0
	bar.offset_right = 612.0
	bar.offset_bottom = -104.0
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.add_theme_constant_override("separation", 6)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)

	var defs: Array[Dictionary] = [
		{"id": "ASSAULT", "label": "⚔️ Giao Tranh [Z]"},
		{"id": "DEFENSE", "label": "🛡️ Phòng Thủ [V]"},
		{"id": "FREESHOT", "label": "💣 Freeshot [B]"},
		{"id": "HOLD_FIRE", "label": "🚫 Hold [H]"},
		{"id": "CLEAR", "label": "✖ Hủy [G]"},
		{"id": "CLEAR_ALL", "label": "✖ Hết [⇧G]"},
	]
	var normal_sb := _get_cached_style("tool_norm", Color(0.08, 0.13, 0.23, 0.90), Color(0.24, 0.52, 0.78, 0.85), 1, 5)
	var hover_sb := _get_cached_style("tool_hover", Color(0.14, 0.22, 0.36, 0.95), Color(0.35, 0.82, 1.0, 1.0), 2, 5)
	for item: Dictionary in defs:
		var tid: String = str(item["id"])
		var btn := Button.new()
		btn.name = "ToolBtn_%s" % tid
		btn.text = str(item["label"])
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 12)
		btn.add_theme_color_override("font_color", Color(0.90, 0.96, 1.0, 1.0))
		btn.add_theme_stylebox_override("normal", normal_sb)
		btn.add_theme_stylebox_override("hover", hover_sb)
		btn.add_theme_stylebox_override("pressed", hover_sb)
		btn.pressed.connect(func() -> void: commander_tool_clicked.emit(tid))
		bar.add_child(btn)
		_tool_buttons[tid] = btn

func set_active_commander_tool(tool_id: String) -> void:
	active_tool_id = tool_id
	var active_sb := _get_cached_style("tool_active", Color(0.18, 0.26, 0.14, 0.95), Color(1.0, 0.84, 0.24, 1.0), 2, 5)
	var normal_sb := _get_cached_style("tool_norm", Color(0.08, 0.13, 0.23, 0.90), Color(0.24, 0.52, 0.78, 0.85), 1, 5)
	for tid: String in _tool_buttons:
		var btn: Button = _tool_buttons[tid] as Button
		if btn == null or not is_instance_valid(btn):
			continue
		if tid == active_tool_id and tid != "NONE":
			btn.modulate = Color(1.0, 0.92, 0.55)
			btn.add_theme_stylebox_override("normal", active_sb)
		else:
			btn.modulate = Color.WHITE
			btn.add_theme_stylebox_override("normal", normal_sb)

func update_cost(current: float, max_cost: float = 10.0) -> void:
	displayed_cost = current
	displayed_max_cost = max_cost
	var cost_bar := find_child("CostProgressBar", true, false) as ProgressBar
	if cost_bar != null:
		cost_bar.max_value = maxf(0.001, max_cost)
		cost_bar.value = clampf(current, 0.0, cost_bar.max_value)
		var cost_lbl := cost_bar.get_node_or_null("CostValueLabel") as Label
		if cost_lbl != null:
			var next_txt: String = "COST  %.1f / %.0f" % [current, max_cost]
			if next_txt != _last_cost_text:
				_last_cost_text = next_txt
				cost_lbl.text = next_txt

## Registers display name, weapon archetype badge, and theme accent color for a Striker card.
func update_striker_meta(student_id: String, display_name: String, weapon_class: String, accent_color: Color = Color(0.22, 0.75, 0.98)) -> void:
	striker_meta[student_id] = {
		"name": display_name,
		"weapon_class": weapon_class,
		"color": accent_color,
	}

func update_striker_hp(student_id: String, current_hp: int, max_hp: int) -> void:
	var next_val := Vector2i(current_hp, max_hp)
	if striker_hp.has(student_id) and striker_hp[student_id] == next_val:
		return
	striker_hp[student_id] = next_val
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
		displayed_selection_summary = "Mặc định: Click/Kéo chọn lính [F1-F4/~] | [Z] Giao tranh [V] Phòng thủ [B] Freeshot [H] Hold"
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
		if not striker_orders.has(student_id):
			return
		striker_orders.erase(student_id)
	else:
		if str(striker_orders.get(student_id, "")) == order_type:
			return
		striker_orders[student_id] = order_type
	_refresh_striker_portraits()

func set_active_buff_ids(buff_ids: Array[String]) -> void:
	active_buff_ids = buff_ids.duplicate()
	_refresh_buff_row()

## Styles an EX-Skill Button as a compact Blue Archive tactical card showing Cost, Hotkey, Name, and Caster.
func style_ex_skill_button(btn: Button, slot_index: int, skill: SkillData) -> void:
	if btn == null or skill == null:
		return
	var caster_tag: String = skill.caster_name if not skill.caster_name.is_empty() else "Special"
	var short_name: String = skill.name
	var paren_idx: int = short_name.find(" (")
	if paren_idx > 0:
		short_name = short_name.substr(0, paren_idx)
	btn.custom_minimum_size = Vector2(108.0, 86.0)
	btn.focus_mode = Control.FOCUS_NONE
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.clip_text = false
	btn.add_theme_font_size_override("font_size", 12)
	btn.text = "[%d] Cost %d\n%s\n★ %s" % [slot_index + 1, skill.cost, short_name, caster_tag]
	btn.add_theme_stylebox_override(
		"normal",
		_get_cached_style("ex_ready", Color(0.08, 0.14, 0.24, 0.92), Color(0.18, 0.78, 1.0, 0.95), 2, 8)
	)
	btn.add_theme_stylebox_override(
		"hover",
		_get_cached_style("ex_hover", Color(0.14, 0.24, 0.38, 0.96), Color(0.55, 0.92, 1.0, 1.0), 2, 8)
	)

## Updates EX-Skill card visual affordability, cooldown readout, and incapacitated-caster state.
func update_ex_skill_states(skills: Array, current_cost: float, cooldowns: Dictionary, dead_caster_ids: Array[String] = []) -> void:
	var btn_box := find_child("SpecialSkillButtons", true, false) as Container
	if btn_box == null:
		return
	var children := btn_box.get_children()
	var ready_sb := _get_cached_style("ex_ready", Color(0.08, 0.14, 0.24, 0.92), Color(0.18, 0.78, 1.0, 0.95), 2, 8)
	var wait_sb := _get_cached_style("ex_wait", Color(0.06, 0.08, 0.14, 0.72), Color(0.32, 0.38, 0.48, 0.75), 1, 8)
	var down_sb := _get_cached_style("ex_down", Color(0.16, 0.06, 0.08, 0.78), Color(0.82, 0.24, 0.28, 0.85), 1, 8)

	for i in range(mini(children.size(), skills.size())):
		var btn := children[i] as Button
		var sk := skills[i] as SkillData
		if btn == null or sk == null:
			continue
		var cd_left: float = float(cooldowns.get(sk.id, 0.0))
		var is_dead_caster: bool = (not sk.caster_id.is_empty()) and dead_caster_ids.has(sk.caster_id)
		var can_cast: bool = (not is_dead_caster) and (cd_left <= 0.0) and (current_cost >= float(sk.cost))
		var state_key: String = "%s|%s|%.1f" % [str(is_dead_caster), str(can_cast), cd_left if cd_left > 0.0 else 0.0]
		if str(_last_ex_card_states.get(i, "")) == state_key:
			continue
		_last_ex_card_states[i] = state_key

		var caster_tag: String = sk.caster_name if not sk.caster_name.is_empty() else "Special"
		var short_name: String = sk.name
		var paren_idx: int = short_name.find(" (")
		if paren_idx > 0:
			short_name = short_name.substr(0, paren_idx)

		if is_dead_caster:
			btn.text = "[%d] DOWN\n%s\n✖ %s" % [i + 1, short_name, caster_tag]
			btn.add_theme_stylebox_override("normal", down_sb)
			btn.modulate = Color(0.85, 0.45, 0.45, 0.85)
		elif cd_left > 0.05:
			btn.text = "[%d] CD %.1fs\n%s\n★ %s" % [i + 1, cd_left, short_name, caster_tag]
			btn.add_theme_stylebox_override("normal", wait_sb)
			btn.modulate = Color(0.72, 0.76, 0.84, 0.88)
		elif can_cast:
			btn.text = "[%d] Cost %d\n%s\n★ %s" % [i + 1, sk.cost, short_name, caster_tag]
			btn.add_theme_stylebox_override("normal", ready_sb)
			btn.modulate = Color.WHITE
		else:
			btn.text = "[%d] Cost %d\n%s\n★ %s" % [i + 1, sk.cost, short_name, caster_tag]
			btn.add_theme_stylebox_override("normal", wait_sb)
			btn.modulate = Color(0.66, 0.72, 0.82, 0.85)

func clear_hud() -> void:
	striker_hp.clear()
	striker_orders.clear()
	striker_meta.clear()
	selected_striker_ids.clear()
	active_buff_ids.clear()
	_last_ex_card_states.clear()
	_last_cost_text = ""
	displayed_selection_summary = ""
	displayed_sector_summary = ""
	var sector_lbl := find_child("SectorProgressLabel", true, false) as Label
	if sector_lbl != null:
		sector_lbl.text = ""
	var sel_lbl := find_child("SelectedUnitsLabel", true, false) as Label
	if sel_lbl != null:
		sel_lbl.text = "Mặc định: Click/Kéo chọn lính [F1-F4/~] | [Z] Giao tranh [V] Phòng thủ [B] Freeshot [H] Hold"
	_refresh_striker_portraits()
	_refresh_buff_row()
	set_active_commander_tool("NONE")
	set_slow_mo_active(false)

func _build_striker_card(sid: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "Portrait_%s" % sid
	card.custom_minimum_size = Vector2(138.0, 74.0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(_on_portrait_gui_input.bind(sid))

	var vbox := VBoxContainer.new()
	vbox.name = "CardVBox"
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 2)
	card.add_child(vbox)

	var top_lbl := Label.new()
	top_lbl.name = "NameLabel"
	top_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_lbl.add_theme_font_size_override("font_size", 12)
	vbox.add_child(top_lbl)

	var hp_bar := ProgressBar.new()
	hp_bar.name = "CardHPBar"
	hp_bar.custom_minimum_size = Vector2(122.0, 8.0)
	hp_bar.show_percentage = false
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hp_bar)

	var hp_lbl := Label.new()
	hp_lbl.name = "HPLabel"
	hp_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(hp_lbl)

	var status_lbl := Label.new()
	status_lbl.name = "StatusLabel"
	status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_lbl.add_theme_font_size_override("font_size", 10)
	vbox.add_child(status_lbl)

	return card

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

	var sel_sb := _get_cached_style("card_sel", Color(0.08, 0.19, 0.30, 0.94), Color(0.22, 0.88, 1.0, 1.0), 2, 6)
	var norm_sb := _get_cached_style("card_norm", Color(0.07, 0.11, 0.19, 0.88), Color(0.24, 0.42, 0.62, 0.85), 1, 6)
	var dead_sb := _get_cached_style("card_dead", Color(0.10, 0.08, 0.10, 0.72), Color(0.45, 0.25, 0.25, 0.75), 1, 6)

	for sid in striker_hp:
		var hp_vec: Vector2i = striker_hp[sid]
		var card := portraits.get_node_or_null("Portrait_%s" % sid) as PanelContainer
		if card == null:
			card = _build_striker_card(sid)
			portraits.add_child(card)

		var is_sel: bool = selected_striker_ids.has(sid)
		var is_dead: bool = hp_vec.x <= 0
		var meta: Dictionary = striker_meta.get(sid, {})
		var disp_name: String = str(meta.get("name", sid))
		var wclass: String = str(meta.get("weapon_class", ""))
		var class_tag: String = "[%s] " % wclass if not wclass.is_empty() else ""
		var order_str: String = str(striker_orders.get(sid, ""))

		if is_dead:
			card.add_theme_stylebox_override("panel", dead_sb)
			card.modulate = Color(0.65, 0.58, 0.60, 0.85)
		elif is_sel:
			card.add_theme_stylebox_override("panel", sel_sb)
			card.modulate = Color.WHITE
		else:
			card.add_theme_stylebox_override("panel", norm_sb)
			card.modulate = Color.WHITE

		var name_lbl := card.find_child("NameLabel", true, false) as Label
		if name_lbl != null:
			name_lbl.text = ("%s%s%s" % ["★ " if is_sel else "", class_tag, disp_name])
			name_lbl.add_theme_color_override("font_color", Color(0.38, 0.94, 1.0) if is_sel else Color(0.95, 0.98, 1.0))

		var hp_bar := card.find_child("CardHPBar", true, false) as ProgressBar
		if hp_bar != null:
			hp_bar.max_value = maxf(1.0, float(hp_vec.y))
			hp_bar.value = clampf(float(hp_vec.x), 0.0, hp_bar.max_value)

		var hp_lbl := card.find_child("HPLabel", true, false) as Label
		if hp_lbl != null:
			hp_lbl.text = "%d / %d" % [hp_vec.x, hp_vec.y] if not is_dead else "K.O."

		var status_lbl := card.find_child("StatusLabel", true, false) as Label
		if status_lbl != null:
			status_lbl.text = order_str if not order_str.is_empty() else "⚔️ AUTO"
			status_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35) if not order_str.is_empty() else Color(0.68, 0.84, 0.98))

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
		lbl.text = "[%s]" % buff_id
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.55, 0.95, 0.72, 1.0))
		buff_row.add_child(lbl)
