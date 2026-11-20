# scripts/ui/HUDManager.gd
class_name HUDManager
extends CanvasLayer

var displayed_ap: int = 100
var displayed_max_ap: int = 100
var displayed_day: int = 1
var displayed_credits: int = 0

var event_bus: Node = null

func _ready() -> void:
	_connect_event_bus()
	_sync_initial_state()
	_refresh_labels()

func update_ap(current: int, max_ap: int) -> void:
	displayed_ap = current
	displayed_max_ap = max_ap
	var ap_bar := find_child("APBar", true, false) as ProgressBar
	if ap_bar != null:
		ap_bar.max_value = maxf(1.0, float(max_ap))
		ap_bar.value = clampf(float(current), 0.0, ap_bar.max_value)

func update_day(day: int, _fatigue: bool = false) -> void:
	displayed_day = day
	var day_label := find_child("DayLabel", true, false) as Label
	if day_label != null:
		day_label.text = "Day %d (Fatigued)" % day if _fatigue else "Day %d" % day

func update_credits(amount: int) -> void:
	displayed_credits = amount
	var credits_label := find_child("CreditsLabel", true, false) as Label
	if credits_label != null:
		credits_label.text = "%d Credits" % amount

func _refresh_labels() -> void:
	update_ap(displayed_ap, displayed_max_ap)
	update_day(displayed_day, false)
	update_credits(displayed_credits)

func _sync_initial_state() -> void:
	if not is_inside_tree():
		return
	var dcm := get_node_or_null("/root/DayCycleManager")
	if dcm != null:
		if "current_ap" in dcm and "max_ap" in dcm:
			displayed_ap = int(dcm.current_ap)
			displayed_max_ap = int(dcm.max_ap)
		if "current_day" in dcm:
			displayed_day = int(dcm.current_day)
	var sm := get_node_or_null("/root/SaveManager")
	if sm != null and "credits" in sm:
		displayed_credits = int(sm.credits)

func _connect_event_bus() -> void:
	var bus := _get_event_bus()
	if bus == null:
		return
	if bus.has_signal("ap_changed") and not bus.ap_changed.is_connected(update_ap):
		bus.ap_changed.connect(update_ap)
	if bus.has_signal("day_advanced") and not bus.day_advanced.is_connected(update_day):
		bus.day_advanced.connect(update_day)

func _get_event_bus() -> Node:
	if event_bus != null:
		return event_bus
	if is_inside_tree():
		return get_node_or_null("/root/EventBus")
	return null
