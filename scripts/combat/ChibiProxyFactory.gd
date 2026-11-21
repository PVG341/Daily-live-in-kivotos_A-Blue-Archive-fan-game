# scripts/combat/ChibiProxyFactory.gd
class_name ChibiProxyFactory
extends RefCounted

## Builds lightweight Chibi-proportioned 3D proxy visuals, Halo, SelectionRing, and 3D HP label on unit.
func attach_unit_visuals(
	unit: Node3D,
	display_name: String,
	primary_color: Color,
	halo_color: Color,
	scale_factor: float = 1.0
) -> void:
	if unit == null:
		return

	if unit.get_node_or_null("CollisionShape3D") == null:
		var col := CollisionShape3D.new()
		col.name = "CollisionShape3D"
		var cap := CapsuleShape3D.new()
		cap.radius = 0.38 * scale_factor
		cap.height = 1.0 * scale_factor
		col.shape = cap
		col.position = Vector3(0.0, 0.5 * scale_factor, 0.0)
		unit.add_child(col)

	var existing_vis := unit.get_node_or_null("VisualRoot") as Node3D
	if existing_vis != null:
		existing_vis.queue_free()

	var vis_root := Node3D.new()
	vis_root.name = "VisualRoot"
	unit.add_child(vis_root)

	# Chibi body
	var body_mesh_inst := MeshInstance3D.new()
	body_mesh_inst.name = "BodyMesh"
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.24 * scale_factor
	body_mesh.height = 0.65 * scale_factor
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = primary_color
	body_mesh.material = body_mat
	body_mesh_inst.mesh = body_mesh
	body_mesh_inst.position = Vector3(0.0, 0.35 * scale_factor, 0.0)
	vis_root.add_child(body_mesh_inst)

	# Oversized Chibi head
	var head_mesh_inst := MeshInstance3D.new()
	head_mesh_inst.name = "HeadMesh"
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.28 * scale_factor
	head_mesh.height = 0.52 * scale_factor
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.98, 0.91, 0.86).lerp(primary_color, 0.12)
	head_mesh.material = head_mat
	head_mesh_inst.mesh = head_mesh
	head_mesh_inst.position = Vector3(0.0, 0.85 * scale_factor, 0.0)
	vis_root.add_child(head_mesh_inst)

	# Halo hovering above head
	var halo_mesh_inst := MeshInstance3D.new()
	halo_mesh_inst.name = "HaloMesh"
	var halo_mesh := TorusMesh.new()
	halo_mesh.inner_radius = 0.20 * scale_factor
	halo_mesh.outer_radius = 0.26 * scale_factor
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.albedo_color = halo_color
	halo_mesh.material = halo_mat
	halo_mesh_inst.mesh = halo_mesh
	halo_mesh_inst.position = Vector3(0.0, 1.28 * scale_factor, 0.0)
	halo_mesh_inst.rotation_degrees = Vector3(12.0, 0.0, 0.0)
	vis_root.add_child(halo_mesh_inst)

	# RTS selection ring on ground
	var sel_ring_inst := MeshInstance3D.new()
	sel_ring_inst.name = "SelectionRing"
	var sel_mesh := TorusMesh.new()
	sel_mesh.inner_radius = 0.42 * scale_factor
	sel_mesh.outer_radius = 0.50 * scale_factor
	var sel_mat := StandardMaterial3D.new()
	sel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sel_mat.albedo_color = Color(0.2, 0.85, 1.0)
	sel_mesh.material = sel_mat
	sel_ring_inst.mesh = sel_mesh
	sel_ring_inst.position = Vector3(0.0, 0.05, 0.0)
	sel_ring_inst.visible = false
	vis_root.add_child(sel_ring_inst)

	# 3D billboarded HP bar label
	var hp_label := Label3D.new()
	hp_label.name = "HPBarLabel"
	hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hp_label.position = Vector3(0.0, 1.62 * scale_factor, 0.0)
	hp_label.font_size = 24
	hp_label.outline_size = 6
	hp_label.modulate = Color.WHITE
	hp_label.text = display_name
	vis_root.add_child(hp_label)

## Toggles the ground RTS selection ring visibility on a unit.
func set_unit_selected(unit: Node3D, selected: bool) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var ring := unit.get_node_or_null("VisualRoot/SelectionRing") as Node3D
	if ring != null:
		ring.visible = selected

## Updates the floating 3D HP label above a unit.
func update_unit_hp_label(unit: Node3D, display_name: String, current_hp: int, max_hp: int) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var lbl := unit.get_node_or_null("VisualRoot/HPBarLabel") as Label3D
	if lbl != null:
		lbl.text = "%s\n%d/%d" % [display_name, maxi(0, current_hp), maxi(1, max_hp)]

## Attaches translucent red telegraph discs to a TelegraphedAoE node.
func attach_aoe_visuals(aoe: Node3D, radius: float) -> void:
	if aoe == null:
		return
	var safe_radius: float = maxf(0.1, radius)

	var danger_inst := MeshInstance3D.new()
	danger_inst.name = "DangerDisc"
	var danger_mesh := CylinderMesh.new()
	danger_mesh.top_radius = safe_radius
	danger_mesh.bottom_radius = safe_radius
	danger_mesh.height = 0.06
	var danger_mat := StandardMaterial3D.new()
	danger_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	danger_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	danger_mat.albedo_color = Color(1.0, 0.15, 0.15, 0.35)
	danger_mesh.material = danger_mat
	danger_inst.mesh = danger_mesh
	danger_inst.position = Vector3(0.0, 0.03, 0.0)
	aoe.add_child(danger_inst)

	var fill_inst := MeshInstance3D.new()
	fill_inst.name = "FillDisc"
	var fill_mesh := CylinderMesh.new()
	fill_mesh.top_radius = safe_radius
	fill_mesh.bottom_radius = safe_radius
	fill_mesh.height = 0.07
	var fill_mat := StandardMaterial3D.new()
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_mat.albedo_color = Color(1.0, 0.05, 0.05, 0.55)
	fill_mesh.material = fill_mat
	fill_inst.mesh = fill_mesh
	fill_inst.position = Vector3(0.0, 0.04, 0.0)
	fill_inst.scale = Vector3(0.05, 1.0, 0.05)
	aoe.add_child(fill_inst)

## Scales the inner AoE fill indicator on XZ according to warning progress [0, 1].
func update_aoe_progress(aoe: Node3D, progress: float) -> void:
	if aoe == null or not is_instance_valid(aoe):
		return
	var fill_inst := aoe.get_node_or_null("FillDisc") as Node3D
	if fill_inst != null:
		var s: float = clampf(progress, 0.05, 1.0)
		fill_inst.scale = Vector3(s, 1.0, s)
