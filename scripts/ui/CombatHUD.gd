# scripts/ui/CombatHUD.gd
class_name CombatHUD
extends CanvasLayer

var displayed_cost: float = 0.0
var displayed_max_cost: float = 10.0
var displayed_wave: int = 1
var striker_hp: Dictionary = {}
var striker_orders: Dictionary = {}
var selected_striker_ids: Array[String] = []
var displayed_selection_summary: String = ""
var active_buff_ids: Array[String] = []

func _ready() -> void:
	update_cost(displayed_cost, displayed_max_cost)
	update_wave(displayed_wave)
	_refresh_buff_row()

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
		displayed_selection_summary = "Chưa chọn học sinh (Kéo chuột trái chọn nhóm)"
	else:
		displayed_selection_summary = "Đang chọn (%d): %s" % [selected_striker_ids.size(), ", ".join(selected_striker_ids)]

	var sel_lbl := find_child("SelectedUnitsLabel", true, false) as Label
	if sel_lbl != null:
		sel_lbl.text = displayed_selection_summary
	_refresh_striker_portraits()

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
	var sel_lbl := find_child("SelectedUnitsLabel", true, false) as Label
	if sel_lbl != null:
		sel_lbl.text = "Chưa chọn học sinh (Kéo chuột trái chọn nhóm)"
	_refresh_striker_portraits()
	_refresh_buff_row()

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
			portraits.add_child(existing)
		var is_sel: bool = selected_striker_ids.has(sid)
		var order_str: String = str(striker_orders.get(sid, ""))
		var order_tag: String = " (%s)" % order_str if not order_str.is_empty() else ""
		var base_text: String = "%s: %d/%d%s" % [sid, hp_vec.x, hp_vec.y, order_tag]
		existing.text = "★ [%s]" % base_text if is_sel else base_text
		existing.modulate = Color(0.35, 0.95, 1.0) if is_sel else Color.WHITE

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
