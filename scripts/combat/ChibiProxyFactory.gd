# scripts/combat/ChibiProxyFactory.gd
class_name ChibiProxyFactory
extends RefCounted

## Builds lightweight Chibi-proportioned 3D proxy visuals, Halo, SelectionRing, AttackRangeRing, TargetReticle, OrderStatusPillar, and 3D HP label on unit.
func attach_unit_visuals(
	unit: Node3D,
	display_name: String,
	primary_color: Color,
	halo_color: Color,
	scale_factor: float = 1.0,
	attack_range: float = 10.0
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

	# Attack Range Ring (shown when selected)
	var range_ring_inst := MeshInstance3D.new()
	range_ring_inst.name = "AttackRangeRing"
	var range_mesh := TorusMesh.new()
	range_mesh.inner_radius = maxf(0.5, attack_range - 0.12)
	range_mesh.outer_radius = maxf(0.6, attack_range)
	var range_mat := StandardMaterial3D.new()
	range_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	range_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	range_mat.albedo_color = Color(0.2, 0.85, 1.0, 0.32)
	range_mesh.material = range_mat
	range_ring_inst.mesh = range_mesh
	range_ring_inst.position = Vector3(0.0, 0.04, 0.0)
	range_ring_inst.visible = false
	vis_root.add_child(range_ring_inst)

	# Target Reticle (shown on focused enemies)
	var target_reticle := Node3D.new()
	target_reticle.name = "TargetReticle"
	target_reticle.visible = false
	vis_root.add_child(target_reticle)

	var reticle_ring_inst := MeshInstance3D.new()
	reticle_ring_inst.name = "ReticleRing"
	var reticle_mesh := TorusMesh.new()
	reticle_mesh.inner_radius = 0.55 * scale_factor
	reticle_mesh.outer_radius = 0.68 * scale_factor
	var reticle_mat := StandardMaterial3D.new()
	reticle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	reticle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	reticle_mat.albedo_color = Color(1.0, 0.18, 0.18, 0.9)
	reticle_mesh.material = reticle_mat
	reticle_ring_inst.mesh = reticle_mesh
	reticle_ring_inst.position = Vector3(0.0, 0.06, 0.0)
	target_reticle.add_child(reticle_ring_inst)

	var target_tag := Label3D.new()
	target_tag.name = "TargetTag"
	target_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	target_tag.position = Vector3(0.0, 2.05 * scale_factor, 0.0)
	target_tag.font_size = 26
	target_tag.outline_size = 6
	target_tag.modulate = Color(1.0, 0.25, 0.25)
	target_tag.text = "▼ TARGET ▼"
	target_reticle.add_child(target_tag)

	# Overhead Order Status Light Pillar + Icon
	var order_pillar := Node3D.new()
	order_pillar.name = "OrderStatusPillar"
	order_pillar.visible = false
	vis_root.add_child(order_pillar)

	var beam_inst := MeshInstance3D.new()
	beam_inst.name = "LightBeam"
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.22 * scale_factor
	beam_mesh.bottom_radius = 0.32 * scale_factor
	beam_mesh.height = 2.4 * scale_factor
	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_mat.albedo_color = Color(1.0, 0.78, 0.15, 0.42)
	beam_mesh.material = beam_mat
	beam_inst.mesh = beam_mesh
	beam_inst.position = Vector3(0.0, 1.2 * scale_factor, 0.0)
	order_pillar.add_child(beam_inst)

	var order_icon := Label3D.new()
	order_icon.name = "OrderIconLabel"
	order_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	order_icon.position = Vector3(0.0, 2.55 * scale_factor, 0.0)
	order_icon.font_size = 26
	order_icon.outline_size = 6
	order_icon.modulate = Color.WHITE
	order_icon.text = ""
	order_pillar.add_child(order_icon)

	# 3D HP Bar (background + shrinking left-aligned fill pivot)
	var hp_bar_3d := Node3D.new()
	hp_bar_3d.name = "HPBar3D"
	hp_bar_3d.position = Vector3(0.0, 1.42 * scale_factor, 0.0)
	vis_root.add_child(hp_bar_3d)

	var hp_back_inst := MeshInstance3D.new()
	hp_back_inst.name = "HPBackMesh"
	var hp_back_mesh := BoxMesh.new()
	hp_back_mesh.size = Vector3(0.92 * scale_factor, 0.11 * scale_factor, 0.04)
	var hp_back_mat := StandardMaterial3D.new()
	hp_back_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hp_back_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hp_back_mat.albedo_color = Color(0.08, 0.08, 0.1, 0.88)
	hp_back_mesh.material = hp_back_mat
	hp_back_inst.mesh = hp_back_mesh
	hp_bar_3d.add_child(hp_back_inst)

	var hp_fill_pivot := Node3D.new()
	hp_fill_pivot.name = "HPFillPivot"
	hp_fill_pivot.position = Vector3(-0.45 * scale_factor, 0.0, 0.01)
	hp_bar_3d.add_child(hp_fill_pivot)

	var hp_fill_inst := MeshInstance3D.new()
	hp_fill_inst.name = "HPFillMesh"
	var hp_fill_mesh := BoxMesh.new()
	hp_fill_mesh.size = Vector3(0.90 * scale_factor, 0.08 * scale_factor, 0.045)
	var hp_fill_mat := StandardMaterial3D.new()
	hp_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hp_fill_mat.albedo_color = Color(0.2, 0.92, 0.45)
	hp_fill_mesh.material = hp_fill_mat
	hp_fill_inst.mesh = hp_fill_mesh
	hp_fill_inst.position = Vector3(0.45 * scale_factor, 0.0, 0.0)
	hp_fill_pivot.add_child(hp_fill_inst)

	# 3D billboarded HP bar label
	var hp_label := Label3D.new()
	hp_label.name = "HPBarLabel"
	hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hp_label.position = Vector3(0.0, 1.68 * scale_factor, 0.0)
	hp_label.font_size = 24
	hp_label.outline_size = 6
	hp_label.modulate = Color.WHITE
	hp_label.text = display_name
	vis_root.add_child(hp_label)

## Attaches a metallic frontal ballistic riot-shield mesh inside VisualRoot/FacingPivot.
func attach_front_shield_visual(unit: Node3D, scale_factor: float = 1.0, facing: Vector3 = Vector3(0.0, 0.0, -1.0)) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var vis_root := unit.get_node_or_null("VisualRoot") as Node3D
	if vis_root == null:
		return
	var pivot := vis_root.get_node_or_null("FacingPivot") as Node3D
	if pivot == null:
		pivot = Node3D.new()
		pivot.name = "FacingPivot"
		vis_root.add_child(pivot)
	var f_xz := Vector2(facing.x, facing.z)
	if f_xz.length() > 0.01:
		var fn: Vector2 = f_xz.normalized()
		pivot.rotation.y = atan2(fn.x, fn.y)

	var existing_shield := pivot.get_node_or_null("FrontShieldMesh") as MeshInstance3D
	if existing_shield != null:
		return
	var shield_inst := MeshInstance3D.new()
	shield_inst.name = "FrontShieldMesh"
	var shield_mesh := BoxMesh.new()
	shield_mesh.size = Vector3(0.95, 0.90, 0.14) * scale_factor
	var shield_mat := StandardMaterial3D.new()
	shield_mat.albedo_color = Color(0.22, 0.28, 0.36, 1.0)
	shield_mat.metallic = 0.55
	shield_mat.roughness = 0.45
	shield_mesh.material = shield_mat
	shield_inst.mesh = shield_mesh
	shield_inst.position = Vector3(0.0, 0.55 * scale_factor, 0.55 * scale_factor)
	pivot.add_child(shield_inst)

## Toggles the ground RTS selection ring and attack range ring visibility on a unit.
func set_unit_selected(unit: Node3D, selected: bool, show_range: bool = true) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var ring := unit.get_node_or_null("VisualRoot/SelectionRing") as Node3D
	if ring != null:
		ring.visible = selected
	var range_ring := unit.get_node_or_null("VisualRoot/AttackRangeRing") as Node3D
	if range_ring != null:
		range_ring.visible = (selected and show_range)

## Updates the AttackRangeRing torus radii to match effective attack range (e.g., high ground bonus).
func update_unit_attack_range_ring(unit: Node3D, effective_range: float) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var range_ring := unit.get_node_or_null("VisualRoot/AttackRangeRing") as MeshInstance3D
	if range_ring != null and range_ring.mesh is TorusMesh:
		var tm := range_ring.mesh as TorusMesh
		var new_outer: float = maxf(0.6, effective_range)
		var new_inner: float = maxf(0.5, new_outer - 0.12)
		if not is_equal_approx(tm.outer_radius, new_outer):
			tm.inner_radius = new_inner
			tm.outer_radius = new_outer

## Toggles the red target reticle visibility on an enemy unit.
func set_unit_targeted(unit: Node3D, targeted: bool) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var reticle := unit.get_node_or_null("VisualRoot/TargetReticle") as Node3D
	if reticle != null:
		reticle.visible = targeted

## Updates the overhead OrderStatusPillar light beam and icon label for active RTS commands.
func update_unit_order_visual(unit: Node3D, order_type: String) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var pillar := unit.get_node_or_null("VisualRoot/OrderStatusPillar") as Node3D
	if pillar == null:
		return
	if order_type.is_empty():
		pillar.visible = false
		return

	var beam_color := Color(0.2, 0.85, 1.0, 0.30)
	var icon_text := order_type
	var show_beam: bool = true
	match order_type:
		"HOLD_POSITION":
			beam_color = Color(1.0, 0.78, 0.15, 0.42)
			icon_text = "🛡️ HOLD POS"
		"HOLD_FIRE":
			beam_color = Color(0.60, 0.42, 1.0, 0.42)
			icon_text = "🚫 HOLD FIRE"
		"FOCUS_FIRE":
			beam_color = Color(1.0, 0.22, 0.22, 0.35)
			icon_text = "🎯 FOCUS FIRE"
		"COVER":
			beam_color = Color(0.20, 0.95, 0.55, 0.35)
			icon_text = "🧱 TAKE COVER"
		"MOVE":
			beam_color = Color(0.20, 0.85, 1.0, 0.30)
			icon_text = "➔ MOVING"
		"⚠️ NÉ AoE":
			beam_color = Color(1.0, 0.35, 0.12, 0.42)
		"🛡️ RÚT LUI":
			beam_color = Color(1.0, 0.78, 0.18, 0.36)
		"🩹 CỨU THƯƠNG":
			beam_color = Color(0.25, 0.95, 0.55, 0.32)
		"🚩 TIẾN VÀO VÙNG":
			beam_color = Color(0.2, 0.88, 1.0, 0.30)
		"🎯 MỤC TIÊU CHỈ ĐỊNH":
			beam_color = Color(1.0, 0.25, 0.28, 0.32)
		"🧱 NẤP & BẮN":
			beam_color = Color(0.22, 0.9, 0.62, 0.24)
		"⚔️ TỰ ĐỘNG ĐÁNH":
			beam_color = Color(0.75, 0.85, 1.0, 0.18)
			icon_text = "⚔️ AUTO"
			show_beam = false
		"💣 BẮN PHÁ VÙNG":
			beam_color = Color(1.0, 0.28, 0.72, 0.42)
		"⚔️ TIẾN CÔNG", "➔ TIẾN QUÂN":
			beam_color = Color(1.0, 0.85, 0.22, 0.36)
		"🛡️ VÀO VÙNG PHÒNG THỦ", "🛡️ PHÒNG THỦ & BẮN", "🛡️ GIỮ VỊ TRÍ":
			beam_color = Color(0.22, 0.92, 0.52, 0.36)
		_:
			if order_type.begins_with("🚫 "):
				beam_color = Color(0.60, 0.42, 1.0, 0.42)

	var beam := pillar.get_node_or_null("LightBeam") as MeshInstance3D
	if beam != null:
		beam.visible = show_beam
		if beam.mesh is CylinderMesh:
			var cm := beam.mesh as CylinderMesh
			if cm.material is StandardMaterial3D:
				(cm.material as StandardMaterial3D).albedo_color = beam_color

	var lbl := pillar.get_node_or_null("OrderIconLabel") as Label3D
	if lbl != null:
		lbl.text = icon_text
		lbl.modulate = Color(beam_color.r, beam_color.g, beam_color.b, 1.0)

	pillar.visible = true

## Updates the floating 3D HP label and 3D HP fill bar above a unit.
func update_unit_hp_label(unit: Node3D, display_name: String, current_hp: int, max_hp: int, is_enemy: bool = false) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var safe_max: int = maxi(1, max_hp)
	var clamped_hp: int = maxi(0, current_hp)
	var hp_ratio: float = clampf(float(clamped_hp) / float(safe_max), 0.0, 1.0)

	var lbl := unit.get_node_or_null("VisualRoot/HPBarLabel") as Label3D
	if lbl != null:
		lbl.text = "%s\n%d/%d" % [display_name, clamped_hp, safe_max]

	var fill_pivot := unit.get_node_or_null("VisualRoot/HPBar3D/HPFillPivot") as Node3D
	if fill_pivot != null:
		fill_pivot.scale.x = hp_ratio

	var fill_mesh := unit.get_node_or_null("VisualRoot/HPBar3D/HPFillMesh") as MeshInstance3D
	if fill_mesh != null and fill_mesh.mesh is BoxMesh:
		var bm := fill_mesh.mesh as BoxMesh
		if bm.material is StandardMaterial3D:
			var mat := bm.material as StandardMaterial3D
			if is_enemy:
				mat.albedo_color = Color(0.95, 0.22, 0.22) if hp_ratio > 0.3 else Color(1.0, 0.55, 0.12)
			else:
				mat.albedo_color = Color(0.2, 0.92, 0.45) if hp_ratio > 0.35 else Color(1.0, 0.8, 0.15)

## Creates a 3D ground disc + outer ring showing Sensei's tactical command zone.
func create_tactical_zone_disc() -> Node3D:
	var root := Node3D.new()
	root.name = "TacticalZoneDisc"
	root.visible = false

	var disc := MeshInstance3D.new()
	disc.name = "ZoneFillMesh"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 0.05
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.20, 0.88, 1.0, 0.20)
	mesh.material = mat
	disc.mesh = mesh
	disc.position = Vector3(0.0, 0.03, 0.0)
	root.add_child(disc)

	var ring := MeshInstance3D.new()
	ring.name = "ZoneRingMesh"
	var r_mesh := TorusMesh.new()
	r_mesh.inner_radius = 0.96
	r_mesh.outer_radius = 1.0
	var r_mat := StandardMaterial3D.new()
	r_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	r_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	r_mat.albedo_color = Color(0.25, 0.92, 1.0, 0.78)
	r_mesh.material = r_mat
	ring.mesh = r_mesh
	ring.position = Vector3(0.0, 0.05, 0.0)
	root.add_child(ring)

	var cross := MeshInstance3D.new()
	cross.name = "InnerCrosshairMesh"
	var c_mesh := TorusMesh.new()
	c_mesh.inner_radius = 0.22
	c_mesh.outer_radius = 0.27
	var c_mat := StandardMaterial3D.new()
	c_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	c_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	c_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.55)
	c_mesh.material = c_mat
	cross.mesh = c_mesh
	cross.position = Vector3(0.0, 0.055, 0.0)
	root.add_child(cross)

	var label := Label3D.new()
	label.name = "ZoneTitleLabel"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 24
	label.outline_size = 6
	label.position = Vector3(0.0, 0.72, 0.0)
	root.add_child(label)
	return root

## Positions, scales, and colors a 3D Commander tactical command zone from zone dictionary metadata.
func update_tactical_zone_visual(disc: Node3D, zone_data: Dictionary, visible_state: bool) -> void:
	if disc == null or not is_instance_valid(disc):
		return
	disc.visible = visible_state
	if not visible_state:
		return
	var center: Vector3 = zone_data.get("center", Vector3.ZERO)
	var r: float = maxf(1.0, float(zone_data.get("radius", 6.5)))
	var ztype: String = str(zone_data.get("type", "ASSAULT")).to_upper()
	var assigned: Array = zone_data.get("assigned_unit_ids", ["*"])

	disc.position = Vector3(center.x, center.y, center.z)
	disc.scale = Vector3.ONE

	var base_col := Color(1.0, 0.45, 0.18)
	var title_txt := "⚔️ GIAO TRANH"
	if ztype == "DEFENSE":
		base_col = Color(0.22, 0.92, 0.52)
		title_txt = "🛡️ PHÒNG THỦ"
	elif ztype == "FREESHOT":
		base_col = Color(1.0, 0.28, 0.72)
		title_txt = "💣 FREESHOT"

	var fill_mesh := disc.get_node_or_null("ZoneFillMesh") as MeshInstance3D
	if fill_mesh != null:
		fill_mesh.scale = Vector3(r, 1.0, r)
		if fill_mesh.mesh is CylinderMesh:
			var cm := fill_mesh.mesh as CylinderMesh
			if cm.material is StandardMaterial3D:
				(cm.material as StandardMaterial3D).albedo_color = Color(base_col.r, base_col.g, base_col.b, 0.18)
	var ring_mesh := disc.get_node_or_null("ZoneRingMesh") as MeshInstance3D
	if ring_mesh != null:
		ring_mesh.scale = Vector3(r, 1.0, r)
		if ring_mesh.mesh is TorusMesh:
			var tm := ring_mesh.mesh as TorusMesh
			if tm.material is StandardMaterial3D:
				(tm.material as StandardMaterial3D).albedo_color = Color(base_col.r, base_col.g, base_col.b, 0.82)
	var cross_mesh := disc.get_node_or_null("InnerCrosshairMesh") as MeshInstance3D
	if cross_mesh != null:
		cross_mesh.scale = Vector3(r * 0.65, 1.0, r * 0.65)
		if cross_mesh.mesh is TorusMesh:
			var cm2 := cross_mesh.mesh as TorusMesh
			if cm2.material is StandardMaterial3D:
				(cm2.material as StandardMaterial3D).albedo_color = Color(base_col.r, base_col.g, base_col.b, 0.55)
	var lbl := disc.get_node_or_null("ZoneTitleLabel") as Label3D
	if lbl != null:
		var is_full_squad: bool = bool(zone_data.get("is_full_squad", false)) or assigned.is_empty() or assigned.has("*") or assigned.size() >= 4
		var who_str: String = "TOÀN ĐỘI" if is_full_squad else ", ".join(assigned)
		lbl.text = "%s (%.0fm)\n[%s]" % [title_txt, r, who_str]
		lbl.modulate = Color(base_col.r, base_col.g, base_col.b, 1.0)

## Positions, scales, and colors the 3D Commander tactical command zone based on active stance.
func update_tactical_zone_disc(disc: Node3D, center: Vector3, radius: float, stance: int, visible_state: bool) -> void:
	var ztype: String = "DEFENSE" if stance == 2 else "ASSAULT"
	update_tactical_zone_visual(disc, {
		"type": ztype,
		"center": center,
		"radius": radius,
		"assigned_unit_ids": ["*"],
	}, visible_state)

## Creates a 3D ground ring displaying maximum cast_range while targeting an EX-Skill.
func create_skill_range_ring() -> Node3D:
	var root := Node3D.new()
	root.name = "SkillRangeRing"
	root.visible = false

	var ring_inst := MeshInstance3D.new()
	ring_inst.name = "RangeRingMesh"
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.985
	mesh.outer_radius = 1.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.25, 0.85, 1.0, 0.52)
	mesh.material = mat
	ring_inst.mesh = mesh
	ring_inst.position = Vector3(0.0, 0.05, 0.0)
	root.add_child(ring_inst)
	return root

## Positions and scales the 3D EX-Skill max cast_range ground ring around origin_pos.
func update_skill_range_ring(ring: Node3D, origin_pos: Vector3, max_range: float, visible_state: bool) -> void:
	if ring == null or not is_instance_valid(ring):
		return
	ring.visible = visible_state and max_range > 0.0
	if ring.visible:
		var r: float = maxf(0.5, max_range)
		ring.position = Vector3(origin_pos.x, origin_pos.y, origin_pos.z)
		var ring_inst := ring.get_node_or_null("RangeRingMesh") as MeshInstance3D
		if ring_inst != null and ring_inst.mesh is TorusMesh:
			var tm := ring_inst.mesh as TorusMesh
			var desired_inner: float = maxf(0.2, r - 0.18)
			if not is_equal_approx(tm.outer_radius, r):
				tm.inner_radius = desired_inner
				tm.outer_radius = r

## Creates a 3D ground disc for previewing EX-Skill AoE radius under the cursor.
func create_skill_preview_disc() -> Node3D:
	var root := Node3D.new()
	root.name = "SkillPreviewDisc"
	root.visible = false

	var disc := MeshInstance3D.new()
	disc.name = "DiscMesh"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 0.06
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.82, 0.15, 0.38)
	mesh.material = mat
	disc.mesh = mesh
	disc.position = Vector3(0.0, 0.04, 0.0)
	root.add_child(disc)
	return root

## Positions, scales, and colors the 3D EX-Skill AoE preview disc on the ground.
func update_skill_preview_disc(disc: Node3D, world_pos: Vector3, radius: float, visible_state: bool, in_range: bool = true) -> void:
	if disc == null or not is_instance_valid(disc):
		return
	disc.visible = visible_state
	if visible_state:
		var r: float = maxf(0.25, radius)
		disc.position = Vector3(world_pos.x, world_pos.y, world_pos.z)
		disc.scale = Vector3(r, 1.0, r)
		var mesh_inst := disc.get_node_or_null("DiscMesh") as MeshInstance3D
		if mesh_inst != null and mesh_inst.mesh is CylinderMesh:
			var cm := mesh_inst.mesh as CylinderMesh
			if cm.material is StandardMaterial3D:
				(cm.material as StandardMaterial3D).albedo_color = Color(1.0, 0.82, 0.15, 0.38) if in_range else Color(1.0, 0.28, 0.18, 0.42)

## Creates a 3D beacon marker showing Move/Cover destinations.
func create_order_beacon() -> Node3D:
	var root := Node3D.new()
	root.name = "OrderBeacon"
	root.visible = false

	var pillar := MeshInstance3D.new()
	pillar.name = "BeaconMesh"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.12
	mesh.bottom_radius = 0.35
	mesh.height = 1.4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.2, 0.9, 1.0, 0.45)
	mesh.material = mat
	pillar.mesh = mesh
	pillar.position = Vector3(0.0, 0.7, 0.0)
	root.add_child(pillar)
	return root

## Positions and colors the 3D Move/Cover order destination beacon.
func update_order_beacon(beacon: Node3D, world_pos: Vector3, color: Color, visible_state: bool) -> void:
	if beacon == null or not is_instance_valid(beacon):
		return
	beacon.visible = visible_state
	if visible_state:
		beacon.position = world_pos
		var pillar := beacon.get_node_or_null("BeaconMesh") as MeshInstance3D
		if pillar != null and pillar.mesh is CylinderMesh:
			var cm := pillar.mesh as CylinderMesh
			if cm.material is StandardMaterial3D:
				(cm.material as StandardMaterial3D).albedo_color = color

## Attaches translucent telegraph discs to a TelegraphedAoE or support strike node.
func attach_aoe_visuals(aoe: Node3D, radius: float, color: Color = Color(1.0, 0.2, 0.15)) -> void:
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
	danger_mat.albedo_color = Color(color.r, color.g, color.b, 0.35)
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
	fill_mat.albedo_color = Color(color.r, color.g, color.b, 0.55)
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
