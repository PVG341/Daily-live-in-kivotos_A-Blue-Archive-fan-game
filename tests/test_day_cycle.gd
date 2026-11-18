# tests/test_day_cycle.gd
extends SceneTree

func _init():
	var mgr = preload("res://scripts/core/DayCycleManager.gd").new()
	mgr.max_ap = 100
	mgr.current_ap = 100
	mgr.current_hour = 8.0
	mgr.current_day = 1

	# Test AP consumption
	assert(mgr.consume_ap(30) == true, "Should succeed with 100 AP")
	assert(mgr.current_ap == 70, "AP should be 70 after consuming 30")
	assert(mgr.consume_ap(80) == false, "Should fail with only 70 AP")
	assert(mgr.current_ap == 70, "AP should remain 70 after failed consume")

	# Test AP restoration
	mgr.restore_ap(15)
	assert(mgr.current_ap == 85, "AP should be 85 after restoring 15")
	mgr.restore_ap(50)
	assert(mgr.current_ap == 100, "AP should clamp to max_ap (100)")

	# Test time of day and forced sleep queries
	mgr.current_hour = 8.0
	assert(mgr.get_time_of_day() == "MORNING", "8:00 should be MORNING")
	assert(mgr.is_forced_sleep_hour() == false, "8:00 should not be forced sleep hour")

	mgr.current_hour = 14.0
	assert(mgr.get_time_of_day() == "AFTERNOON", "14:00 should be AFTERNOON")

	mgr.current_hour = 19.0
	assert(mgr.get_time_of_day() == "EVENING", "19:00 should be EVENING")

	mgr.current_hour = 23.0
	assert(mgr.get_time_of_day() == "NIGHT", "23:00 should be NIGHT")

	mgr.current_hour = 1.0
	assert(mgr.get_time_of_day() == "NIGHT", "1:00 should be NIGHT")
	assert(mgr.is_forced_sleep_hour() == false, "1:00 should not be forced sleep hour")

	mgr.current_hour = 3.0
	assert(mgr.is_forced_sleep_hour() == true, "3:00 should be forced sleep hour")

	# Test day advance
	mgr.advance_day()
	assert(mgr.current_day == 2, "Day should advance to 2")
	assert(mgr.current_ap == 100, "AP should fully restore on new day")
	assert(mgr.current_hour == 7.0, "Normal day advance should reset hour to 7.0")

	# Test normal advance_time
	mgr.advance_time(3.0)
	assert(mgr.current_hour == 10.0, "Time should advance by 3 hours to 10.0")
	assert(mgr.current_day == 2, "Day should remain 2")

	# Test 3AM forced sleep
	mgr.current_hour = 2.5
	mgr.advance_time(1.0)  # reaches 3:30 -> triggers forced sleep
	assert(mgr.current_day == 3, "Forced sleep should advance day")
	assert(mgr.current_hour >= 10.0, "Wake up should be late morning after forced sleep")
	assert(mgr.current_ap < 100, "Fatigue penalty should reduce max AP recovery")
	assert(mgr.current_ap == 70, "Fatigue penalty should be 70% of max AP (70)")

	# Test EventBus signal emission
	var event_bus = load("res://scripts/core/EventBus.gd").new()
	mgr.event_bus = event_bus

	var last_day_event = []
	var last_ap_event = []
	event_bus.day_advanced.connect(func(new_day: int, fatigue: bool): last_day_event.append([new_day, fatigue]))
	event_bus.ap_changed.connect(func(curr: int, max_val: int): last_ap_event.append([curr, max_val]))

	mgr.consume_ap(20)
	assert(last_ap_event.size() > 0, "ap_changed signal should be emitted")
	assert(last_ap_event[-1] == [mgr.current_ap, 100], "ap_changed args should match")

	mgr.advance_day()
	assert(last_day_event.size() > 0, "day_advanced signal should be emitted")
	assert(last_day_event[-1] == [mgr.current_day, false], "day_advanced args should match normal advance")

	mgr.current_hour = 2.0
	mgr.advance_time(1.5)  # triggers forced sleep at 3:30
	assert(last_day_event.size() > 1, "day_advanced signal should be emitted on forced sleep")
	assert(last_day_event[-1] == [mgr.current_day, true], "day_advanced args should match forced sleep (fatigue=true)")

	event_bus.free()
	mgr.free()

	print("PASS: test_day_cycle")
	quit(0)
