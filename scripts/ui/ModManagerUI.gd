# scripts/ui/ModManagerUI.gd
class_name ModManagerUI
extends Control

var mod_loader: Node = null

func _ready() -> void:
	var refresh_btn := find_child("RefreshButton", true, false) as Button
	if refresh_btn != null and not refresh_btn.pressed.is_connected(refresh_mod_list):
		refresh_btn.pressed.connect(refresh_mod_list)
	refresh_mod_list()

func refresh_mod_list() -> Array[Dictionary]:
	var loader := _get_mod_loader()
	var mods: Array[Dictionary] = []
	if loader != null and loader.has_method("get_loaded_mods"):
		var raw = loader.get_loaded_mods()
		if raw is Array:
			for entry in raw:
				if entry is Dictionary:
					mods.append(entry)
	_rebuild_mod_list_ui(mods)
	return mods

func toggle_mod(mod_id: String, enabled: bool) -> void:
	var loader := _get_mod_loader()
	if loader != null and loader.has_method("set_mod_enabled"):
		loader.set_mod_enabled(mod_id, enabled)

func _get_mod_loader() -> Node:
	if mod_loader != null:
		return mod_loader
	if is_inside_tree():
		return get_node_or_null("/root/ModLoader")
	var loop := Engine.get_main_loop() as SceneTree
	if loop != null and loop.root != null:
		return loop.root.get_node_or_null("ModLoader")
	return null

func _rebuild_mod_list_ui(mods: Array[Dictionary]) -> void:
	var container := find_child("ModListContainer", true, false) as Container
	if container == null:
		return
	for child in container.get_children():
		container.remove_child(child)
		child.free()

	for mod_entry in mods:
		var mod_id: String = str(mod_entry.get("id", ""))
		var mod_name: String = str(mod_entry.get("name", mod_id))
		var mod_version: String = str(mod_entry.get("version", ""))
		var enabled: bool = bool(mod_entry.get("enabled", true))

		var check_box := CheckBox.new()
		check_box.text = "%s (%s)" % [mod_name, mod_version] if not mod_version.is_empty() else mod_name
		check_box.button_pressed = enabled
		check_box.toggled.connect(func(pressed: bool) -> void:
			toggle_mod(mod_id, pressed)
		)
		container.add_child(check_box)
