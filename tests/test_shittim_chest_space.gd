# tests/test_shittim_chest_space.gd
extends SceneTree

var _failed: bool = false
var _completed: bool = false

func check(cond: bool, msg: String) -> bool:
	if not cond:
		printerr("FAIL: " + msg)
		_failed = true
		quit(1)
		return false
	return true

func _init() -> void:
	_run_tests()

	if _failed or not _completed:
		quit(1)
		return

	print("PASS: test_shittim_chest_space")
	quit(0)

func _run_tests() -> void:
	var manager_script: GDScript = load("res://scripts/hub/ShittimChestSpaceManager.gd")
	if not check(manager_script != null and manager_script.can_instantiate(), "ShittimChestSpaceManager.gd must load and compile"):
		return

	var space_scene = load("res://scenes/hub/shittim_chest_space.tscn")
	if not check(space_scene != null and space_scene is PackedScene, "scenes/hub/shittim_chest_space.tscn must load as PackedScene"):
		return

	var manager = manager_script.new()

	var entered_events: Array = []
	var exited_events: Array = []
	var interacted_events: Array = []
	manager.space_entered.connect(func(): entered_events.append(true))
	manager.space_exited.connect(func(): exited_events.append(true))
	manager.mascot_interacted.connect(func(mid: String, gtype: String, resp: String):
		interacted_events.append([mid, gtype, resp])
	)

	# 1. Initial unloaded state & interaction rejected before entering
	check(manager.SPACE_SCENE_PATH == "res://scenes/hub/shittim_chest_space.tscn", "SPACE_SCENE_PATH must match scene path")
	check(manager.SUPPORTED_MASCOTS == ["arona", "plana"], "SUPPORTED_MASCOTS must be ['arona', 'plana']")
	check(manager.active_mascots == ["arona", "plana"], "active_mascots must default to ['arona', 'plana']")
	check(manager.is_loaded == false, "is_loaded must be false initially")
	check(manager.loaded_space_instance == null, "loaded_space_instance must be null initially")

	var pre_enter_res: Dictionary = manager.interact_with_mascot("arona", "HEADPAT")
	check(pre_enter_res.get("accepted", true) == false, "interact_with_mascot before enter_space must return accepted == false")
	check(pre_enter_res.get("reaction", "") == "UNAVAILABLE", "Rejected interaction before enter_space must return reaction 'UNAVAILABLE'")
	check(interacted_events.is_empty(), "mascot_interacted must not emit when space is not loaded")

	# 2. On-demand loading via enter_space() and scene structure verification
	check(manager.enter_space() == true, "enter_space() must return true")
	check(manager.is_loaded == true, "is_loaded must be true after enter_space()")
	check(manager.loaded_space_instance != null, "loaded_space_instance must not be null after enter_space()")
	check(entered_events.size() == 1, "space_entered signal must emit once on enter_space()")

	# Calling enter_space() again when already loaded should remain loaded and return true without duplicating
	var first_instance: Node = manager.loaded_space_instance
	check(manager.enter_space() == true, "enter_space() when already loaded must return true")
	check(manager.loaded_space_instance == first_instance, "enter_space() when already loaded must reuse existing loaded_space_instance")

	var space_root: Node = manager.loaded_space_instance
	check(space_root.name == "ShittimChestClassroom" and space_root is Node3D, "Root node must be Node3D named ShittimChestClassroom")
	check(space_root.get_node_or_null("VirtualCamera") is Camera3D, "Scene must have VirtualCamera (Camera3D)")
	var arona_anchor = space_root.get_node_or_null("AronaAnchor")
	var plana_anchor = space_root.get_node_or_null("PlanaAnchor")
	check(arona_anchor is Marker3D, "Scene must have AronaAnchor (Marker3D)")
	check(plana_anchor is Marker3D, "Scene must have PlanaAnchor (Marker3D)")
	check(arona_anchor != null and arona_anchor.get_node_or_null("AronaHitbox") is Area3D, "AronaAnchor must contain AronaHitbox (Area3D)")
	check(plana_anchor != null and plana_anchor.get_node_or_null("PlanaHitbox") is Area3D, "PlanaAnchor must contain PlanaHitbox (Area3D)")
	var overlay = space_root.get_node_or_null("DialogueOverlay")
	check(overlay is CanvasLayer, "Scene must have DialogueOverlay (CanvasLayer)")
	check(overlay != null and overlay.get_node_or_null("SubtitleLabel") is Label, "DialogueOverlay must contain SubtitleLabel (Label)")

	# 3. Mascot interactions (HEADPAT, CHEEK_PINCH, CHEETH_PINCH, POKE, CHAT, unknown mascot)
	var arona_pat: Dictionary = manager.interact_with_mascot("arona", "HEADPAT")
	check(arona_pat.get("accepted", false) == true, "interact_with_mascot('arona', 'HEADPAT') must be accepted")
	check(arona_pat.get("mascot_id", "") == "arona", "mascot_id must be normalized to 'arona'")
	check(not str(arona_pat.get("reaction", "")).is_empty(), "Arona HEADPAT must produce non-empty reaction")

	var plana_pinch: Dictionary = manager.interact_with_mascot("plana", "CHEEK_PINCH")
	check(plana_pinch.get("accepted", false) == true, "interact_with_mascot('plana', 'CHEEK_PINCH') must be accepted")
	check(plana_pinch.get("mascot_id", "") == "plana", "mascot_id must be 'plana'")
	check(not str(plana_pinch.get("reaction", "")).is_empty(), "Plana CHEEK_PINCH must produce non-empty reaction")

	var plana_cheeth: Dictionary = manager.interact_with_mascot("Plana", "CHEETH_PINCH")
	check(plana_cheeth.get("accepted", false) == true, "CHEETH_PINCH alias and mixed-case mascot_id must be accepted")
	check(plana_cheeth.get("mascot_id", "") == "plana", "Mixed-case mascot_id must normalize to lowercase 'plana'")

	var plana_poke: Dictionary = manager.interact_with_mascot("plana", "POKE")
	check(plana_poke.get("accepted", false) == true, "interact_with_mascot('plana', 'POKE') must be accepted")
	check(not str(plana_poke.get("reaction", "")).is_empty(), "Plana POKE must produce non-empty reaction")

	var arona_chat: Dictionary = manager.interact_with_mascot("arona", "CHAT")
	check(arona_chat.get("accepted", false) == true, "interact_with_mascot('arona', 'CHAT') must be accepted")
	check(not str(arona_chat.get("reaction", "")).is_empty(), "Arona CHAT must produce non-empty reaction")

	var unknown_res: Dictionary = manager.interact_with_mascot("shiroko", "HEADPAT")
	check(unknown_res.get("accepted", true) == false, "Unknown mascot must return accepted == false")
	check(unknown_res.get("reaction", "") == "UNAVAILABLE", "Unknown mascot must return reaction 'UNAVAILABLE'")

	check(interacted_events.size() == 5, "mascot_interacted must emit for each of the 5 accepted interactions")

	var subtitle_label: Label = overlay.get_node_or_null("SubtitleLabel") as Label
	if subtitle_label != null:
		check(subtitle_label.text == str(arona_chat.get("reaction", "")), "SubtitleLabel text should reflect latest mascot reaction")

	# 4. Greetings & 3:00 AM curfew warnings
	var arona_curfew: String = manager.get_mascot_greeting("arona", 2.5)
	var plana_curfew: String = manager.get_mascot_greeting("plana", 2.75)
	check(arona_curfew.find("3:00") != -1 and arona_curfew.to_lower().find("sleep") != -1, "Arona greeting at 2.5h must warn about 3:00 AM and sleep")
	check(plana_curfew.find("3:00") != -1 and plana_curfew.to_lower().find("sleep") != -1, "Plana greeting at 2.75h must warn about 3:00 AM and sleep")

	var arona_morning: String = manager.get_mascot_greeting("arona", 8.0)
	var arona_evening: String = manager.get_mascot_greeting("arona", 20.0)
	var plana_morning: String = manager.get_mascot_greeting("plana", 8.0)
	var plana_evening: String = manager.get_mascot_greeting("plana", 20.0)
	check(not arona_morning.is_empty() and not arona_evening.is_empty(), "Arona morning and evening greetings must be non-empty")
	check(arona_morning != arona_evening, "Arona morning and evening greetings must differ")
	check(not plana_morning.is_empty() and not plana_evening.is_empty(), "Plana morning and evening greetings must be non-empty")
	check(plana_morning != plana_evening, "Plana morning and evening greetings must differ")
	check(arona_morning != plana_morning, "Arona and Plana greetings should be distinct")

	# 5. Immediate freeing on exit_space()
	manager.exit_space()
	check(manager.is_loaded == false, "is_loaded must be false after exit_space()")
	check(manager.loaded_space_instance == null, "loaded_space_instance must be null after exit_space()")
	check(not is_instance_valid(first_instance), "loaded_space_instance must be freed immediately when outside SceneTree")
	check(exited_events.size() == 1, "space_exited signal must emit once on exit_space()")

	var post_exit_res: Dictionary = manager.interact_with_mascot("arona", "HEADPAT")
	check(post_exit_res.get("accepted", true) == false, "interact_with_mascot after exit_space() must return accepted == false")

	manager.free()
	_completed = true
