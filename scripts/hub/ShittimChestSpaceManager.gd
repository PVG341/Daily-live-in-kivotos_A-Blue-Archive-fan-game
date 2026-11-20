# scripts/hub/ShittimChestSpaceManager.gd
class_name ShittimChestSpaceManager
extends Node

const GestureReceiverScript := preload("res://scripts/intimacy/GestureReceiver.gd")

const SPACE_SCENE_PATH: String = "res://scenes/hub/shittim_chest_space.tscn"
const SUPPORTED_MASCOTS: Array[String] = ["arona", "plana"]

const MASCOT_GREETINGS: Dictionary = {
	"arona": {
		"curfew": "Sensei! It's almost 3:00 AM—please get some sleep soon before you collapse!",
		"late": "Sensei, it's past 3:00 AM! Please stop working and get some sleep right away!",
		"morning": "Good morning, Sensei! The blue sky inside the Shittim Chest is bright today!",
		"afternoon": "Good afternoon, Sensei! Taking a breather with us in the classroom?",
		"evening": "Good evening, Sensei! Thank you for guiding everyone safely today."
	},
	"plana": {
		"curfew": "Notice, Sensei: 3:00 AM curfew is imminent. Recommend sleep immediately to prevent fatigue.",
		"late": "Warning, Sensei: 3:00 AM threshold exceeded. Immediate sleep is advised.",
		"morning": "Good morning, Sensei. Shittim Chest systems are nominal and schedule data is synced.",
		"afternoon": "Afternoon status report: all Kivotos channels are stable, Sensei.",
		"evening": "Good evening, Sensei. Please conclude your remaining tasks at a reasonable hour."
	}
}

const MASCOT_REACTIONS: Dictionary = {
	"arona": {
		"HEADPAT": "Ehehe~ Sensei's hand is so warm! Keep patting, please!",
		"CHEEK_PINCH": "Wah! S-Sensei, my cheeks aren't mochi!",
		"POKE": "Hyaa! Did you just poke me, Sensei? Pay attention to your work too!",
		"CHAT": "Arona is always cheering for you, Sensei! Let's tackle the next mission together!"
	},
	"plana": {
		"HEADPAT": "...Thank you, Sensei. Tactile input recorded. Mood metrics improving.",
		"CHEEK_PINCH": "Sensei, stretching my facial model serves no tactical purpose... please stop.",
		"POKE": "Input detected. Do you require assistance with mission routing, Sensei?",
		"CHAT": "System standby complete. I am ready to assist whenever you need, Sensei."
	}
}

signal space_entered()
signal space_exited()
signal mascot_interacted(mascot_id: String, gesture_type: String, response: String)

var is_loaded: bool = false
var active_mascots: Array[String] = ["arona", "plana"]
var loaded_space_instance: Node = null

var gesture_receiver: GestureReceiverScript = GestureReceiverScript.new()
var day_cycle_manager: Node = null
var event_bus: Node = null

func enter_space() -> bool:
	if is_loaded and loaded_space_instance != null and is_instance_valid(loaded_space_instance):
		return true

	var packed := ResourceLoader.load(SPACE_SCENE_PATH) as PackedScene
	if packed == null:
		return false

	var instance: Node = packed.instantiate()
	if instance == null:
		return false

	loaded_space_instance = instance
	is_loaded = true
	gesture_receiver.reset()

	if is_inside_tree():
		add_child(loaded_space_instance)

	var current_hour: float = _get_current_hour()
	_update_subtitle(get_mascot_greeting("arona", current_hour))
	_connect_event_bus()

	space_entered.emit()
	return true

func exit_space() -> void:
	_disconnect_event_bus()

	if not is_loaded and (loaded_space_instance == null or not is_instance_valid(loaded_space_instance)):
		loaded_space_instance = null
		is_loaded = false
		return

	if loaded_space_instance != null and is_instance_valid(loaded_space_instance):
		if loaded_space_instance.is_inside_tree():
			if loaded_space_instance.get_parent() != null:
				loaded_space_instance.get_parent().remove_child(loaded_space_instance)
			loaded_space_instance.queue_free()
		else:
			loaded_space_instance.free()

	loaded_space_instance = null
	is_loaded = false
	gesture_receiver.reset()
	space_exited.emit()

func get_mascot_greeting(mascot_id: String, current_hour: float = 8.0) -> String:
	var key: String = mascot_id.to_lower()
	if not MASCOT_GREETINGS.has(key):
		return ""

	var greetings: Dictionary = MASCOT_GREETINGS[key]
	var bucket: String = _get_greeting_bucket(current_hour)
	return str(greetings.get(bucket, greetings["morning"]))

func interact_with_mascot(mascot_id: String, gesture_type: String) -> Dictionary:
	var normalized_id: String = mascot_id.to_lower()
	var canonical_gesture: String = _canonicalize_gesture(gesture_type)

	if not is_loaded or loaded_space_instance == null or not is_instance_valid(loaded_space_instance):
		return {
			"accepted": false,
			"mascot_id": mascot_id,
			"gesture_type": gesture_type,
			"reaction": "UNAVAILABLE"
		}

	if not SUPPORTED_MASCOTS.has(normalized_id) or not active_mascots.has(normalized_id):
		return {
			"accepted": false,
			"mascot_id": mascot_id,
			"gesture_type": gesture_type,
			"reaction": "UNAVAILABLE"
		}

	var mascot_table: Dictionary = MASCOT_REACTIONS.get(normalized_id, {})
	if not mascot_table.has(canonical_gesture):
		return {
			"accepted": false,
			"mascot_id": normalized_id,
			"gesture_type": gesture_type,
			"reaction": "UNAVAILABLE"
		}

	_record_gesture(canonical_gesture)
	var reaction_text: String = str(mascot_table[canonical_gesture])
	_update_subtitle(reaction_text)
	mascot_interacted.emit(normalized_id, gesture_type, reaction_text)

	return {
		"accepted": true,
		"mascot_id": normalized_id,
		"gesture_type": gesture_type,
		"reaction": reaction_text
	}

func _canonicalize_gesture(gesture_type: String) -> String:
	var upper: String = gesture_type.to_upper()
	if upper == "CHEETH_PINCH":
		return "CHEEK_PINCH"
	return upper

func _record_gesture(canonical_gesture: String) -> void:
	match canonical_gesture:
		"HEADPAT":
			gesture_receiver.register_stroke(Vector2(45.0, 0.0))
			gesture_receiver.register_stroke(Vector2(-45.0, 0.0))
		"CHEEK_PINCH":
			gesture_receiver.register_stroke(Vector2(24.0, 12.0))

func _get_greeting_bucket(current_hour: float) -> String:
	if current_hour >= 2.0 and current_hour < 3.0:
		return "curfew"
	if current_hour >= 3.0 and current_hour < 7.0:
		return "late"
	if current_hour >= 7.0 and current_hour < 12.0:
		return "morning"
	if current_hour >= 12.0 and current_hour < 18.0:
		return "afternoon"
	return "evening"

func _get_current_hour() -> float:
	var dcm: Node = _get_day_cycle_manager()
	if dcm != null and dcm.get("current_hour") != null:
		return float(dcm.current_hour)
	return 8.0

func _get_day_cycle_manager() -> Node:
	if day_cycle_manager != null:
		return day_cycle_manager
	if is_inside_tree():
		return get_node_or_null("/root/DayCycleManager")
	var loop := Engine.get_main_loop() as SceneTree
	if loop and loop.root:
		return loop.root.get_node_or_null("DayCycleManager")
	return null

func _get_event_bus() -> Node:
	if event_bus != null:
		return event_bus
	if is_inside_tree():
		return get_node_or_null("/root/EventBus")
	var loop := Engine.get_main_loop() as SceneTree
	if loop and loop.root:
		return loop.root.get_node_or_null("EventBus")
	return null

func _connect_event_bus() -> void:
	var bus: Node = _get_event_bus()
	if bus != null and bus.has_signal("day_advanced"):
		var cb := Callable(self, "_on_day_advanced")
		if not bus.day_advanced.is_connected(cb):
			bus.day_advanced.connect(cb)

func _disconnect_event_bus() -> void:
	var bus: Node = _get_event_bus()
	if bus != null and bus.has_signal("day_advanced"):
		var cb := Callable(self, "_on_day_advanced")
		if bus.day_advanced.is_connected(cb):
			bus.day_advanced.disconnect(cb)

func _on_day_advanced(_new_day: int, _fatigue_penalty: bool) -> void:
	if is_loaded:
		_update_subtitle(get_mascot_greeting("arona", _get_current_hour()))

func _update_subtitle(text: String) -> void:
	if loaded_space_instance == null or not is_instance_valid(loaded_space_instance):
		return
	var label := loaded_space_instance.get_node_or_null("DialogueOverlay/SubtitleLabel") as Label
	if label != null:
		label.text = text
