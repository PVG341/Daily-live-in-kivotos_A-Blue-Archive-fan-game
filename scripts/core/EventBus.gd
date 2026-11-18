extends Node

signal student_bonded(student_id: String, new_level: int)
signal ap_changed(current: int, max_ap: int)
signal day_advanced(new_day: int, fatigue_penalty: bool)
signal mod_loaded(mod_id: String)
signal combat_room_cleared(room_index: int)
signal item_picked_up(item_id: String, quantity: int)
signal combat_event_triggered(event_type: String)
signal save_requested()
signal load_requested(slot: int)
