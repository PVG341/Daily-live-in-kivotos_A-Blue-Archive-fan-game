# scripts/ui/CombatHUD.gd
class_name CombatHUD
extends CanvasLayer

var displayed_cost: float = 0.0
var displayed_max_cost: float = 10.0
var displayed_wave: int = 1
var striker_hp: Dictionary = {}
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

func set_active_buff_ids(buff_ids: Array[String]) -> void:
	active_buff_ids = buff_ids.duplicate()
	_refresh_buff_row()

func clear_hud() -> void:
	striker_hp.clear()
	active_buff_ids.clear()
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
		existing.text = "%s: %d/%d" % [sid, hp_vec.x, hp_vec.y]

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
