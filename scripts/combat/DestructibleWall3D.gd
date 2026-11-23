# scripts/combat/DestructibleWall3D.gd
class_name DestructibleWall3D
extends Node3D

signal wall_damaged(wall: Node3D, current_hp: int, max_hp: int)
signal wall_destroyed(wall: Node3D, world_pos: Vector3)

@export var wall_size: Vector3 = Vector3(2.6, 3.0, 0.5)
@export var armor_tier: int = 2 # 1 = Light/Barricade, 2 = Brick/House Wall, 3 = Concrete Bunker, 99 = Indestructible
@export var max_hp: int = 550
@export var is_destructible: bool = true

var current_hp: int = 550
var is_destroyed: bool = false
var base_color: Color = Color(0.72, 0.66, 0.58)

var wall_mesh_inst: MeshInstance3D = null
var rubble_root: Node3D = null
var static_body: StaticBody3D = null
var collision_shape: CollisionShape3D = null

## Initializes dimensions, armor tier, HP, material color, and physics collider.
func setup_wall(
	p_size: Vector3,
	p_armor_tier: int = 2,
	p_max_hp: int = 550,
	p_color: Color = Color(0.72, 0.66, 0.58),
	p_destructible: bool = true
) -> void:
	wall_size = Vector3(maxf(0.1, p_size.x), maxf(0.1, p_size.y), maxf(0.1, p_size.z))
	armor_tier = p_armor_tier
	max_hp = maxi(1, p_max_hp)
	current_hp = max_hp
	base_color = p_color
	is_destructible = p_destructible
	is_destroyed = false

	_ensure_nodes()
	_sync_visuals_and_collider()

func _ensure_nodes() -> void:
	if wall_mesh_inst == null:
		wall_mesh_inst = get_node_or_null("WallVisual") as MeshInstance3D
	if wall_mesh_inst == null:
		wall_mesh_inst = MeshInstance3D.new()
		wall_mesh_inst.name = "WallVisual"
		add_child(wall_mesh_inst)

	if static_body == null:
		static_body = get_node_or_null("WallBody") as StaticBody3D
	if static_body == null:
		static_body = StaticBody3D.new()
		static_body.name = "WallBody"
		add_child(static_body)

	if collision_shape == null:
		collision_shape = static_body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		static_body.add_child(collision_shape)

	if rubble_root == null:
		rubble_root = get_node_or_null("RubbleRoot") as Node3D
	if rubble_root == null:
		rubble_root = Node3D.new()
		rubble_root.name = "RubbleRoot"
		rubble_root.visible = false
		add_child(rubble_root)
		for i in range(3):
			var chunk := MeshInstance3D.new()
			chunk.name = "Rubble_%d" % i
			var cmesh := BoxMesh.new()
			cmesh.size = Vector3(0.45, 0.18, 0.42)
			var cmat := StandardMaterial3D.new()
			cmat.albedo_color = base_color.darkened(0.35)
			cmesh.material = cmat
			chunk.mesh = cmesh
			rubble_root.add_child(chunk)

func _sync_visuals_and_collider() -> void:
	if wall_mesh_inst != null:
		var bmesh := BoxMesh.new()
		bmesh.size = wall_size
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = base_color
		bmesh.material = bmat
		wall_mesh_inst.mesh = bmesh
		wall_mesh_inst.visible = not is_destroyed

	if collision_shape != null:
		var bshape := BoxShape3D.new()
		bshape.size = wall_size
		collision_shape.shape = bshape
		collision_shape.disabled = is_destroyed

	if rubble_root != null:
		rubble_root.visible = is_destroyed
		var floor_y: float = -wall_size.y * 0.5 + 0.09
		var spread_x: float = minf(0.55, wall_size.x * 0.28)
		var spread_z: float = minf(0.35, wall_size.z * 0.25)
		var idx: int = 0
		for child in rubble_root.get_children():
			if child is MeshInstance3D:
				var offset_x: float = float(idx - 1) * spread_x
				var offset_z: float = (0.14 if idx % 2 == 0 else -0.14) + (0.0 if spread_z <= 0.1 else spread_z * 0.15)
				(child as MeshInstance3D).position = Vector3(offset_x, floor_y, offset_z)
				idx += 1

func _get_effective_transform() -> Transform3D:
	if is_inside_tree():
		return global_transform
	var xform: Transform3D = transform
	var p: Node = get_parent()
	while p != null:
		if p is Node3D:
			xform = (p as Node3D).transform * xform
		p = p.get_parent()
	return xform

## Returns the world-space center of this wall segment.
func get_world_center() -> Vector3:
	return _get_effective_transform().origin

## Tests 3D segment [from_pos, to_pos] against this wall's oriented bounding box.
func intersects_segment(from_pos: Vector3, to_pos: Vector3, padding: float = 0.08) -> Dictionary:
	if is_destroyed:
		return {"hit": false}
	var xform: Transform3D = _get_effective_transform()
	var inv: Transform3D = xform.affine_inverse()
	var p0: Vector3 = inv * from_pos
	var p1: Vector3 = inv * to_pos
	var dir: Vector3 = p1 - p0
	var half: Vector3 = wall_size * 0.5 + Vector3(padding, padding, padding)

	var t_min: float = 0.0
	var t_max: float = 1.0
	for axis in range(3):
		var d: float = dir[axis]
		var o: float = p0[axis]
		var b: float = half[axis]
		if absf(d) < 0.00001:
			if o < -b or o > b:
				return {"hit": false}
		else:
			var t1: float = (-b - o) / d
			var t2: float = (b - o) / d
			if t1 > t2:
				var tmp: float = t1
				t1 = t2
				t2 = tmp
			t_min = maxf(t_min, t1)
			t_max = minf(t_max, t2)
			if t_min > t_max:
				return {"hit": false}

	var local_hit: Vector3 = p0 + dir * t_min
	return {
		"hit": true,
		"t": t_min,
		"point": xform * local_hit,
		"wall": self,
	}

## Returns true when world_pos lies inside this unbroken wall's XZ footprint plus padding.
func intersects_point_xz(world_pos: Vector3, padding: float = 0.35) -> bool:
	if is_destroyed:
		return false
	var inv: Transform3D = _get_effective_transform().affine_inverse()
	var local_pt: Vector3 = inv * world_pos
	var half_x: float = wall_size.x * 0.5 + padding
	var half_z: float = wall_size.z * 0.5 + padding
	var half_y: float = wall_size.y * 0.5 + 1.0
	return absf(local_pt.x) <= half_x and absf(local_pt.z) <= half_z and absf(local_pt.y) <= half_y

## Returns a world-space XZ push-out vector if world_pos overlaps this unbroken wall plus padding.
func get_push_out_offset(world_pos: Vector3, padding: float = 0.42) -> Vector3:
	if not intersects_point_xz(world_pos, padding):
		return Vector3.ZERO
	var xform: Transform3D = _get_effective_transform()
	var local_pt: Vector3 = xform.affine_inverse() * world_pos
	var half_x: float = wall_size.x * 0.5 + padding
	var half_z: float = wall_size.z * 0.5 + padding
	var pen_x: float = half_x - absf(local_pt.x)
	var pen_z: float = half_z - absf(local_pt.z)
	var local_push := Vector3.ZERO
	if pen_x < pen_z:
		local_push.x = (pen_x + 0.04) * (1.0 if local_pt.x >= 0.0 else -1.0)
	else:
		local_push.z = (pen_z + 0.04) * (1.0 if local_pt.z >= 0.0 else -1.0)
	var world_push: Vector3 = xform.basis * local_push
	world_push.y = 0.0
	return world_push

## Returns the two lateral corner waypoints outside the ends of this wall segment for clean flanking.
func get_flank_corners(padding: float = 1.2) -> Array[Vector3]:
	var xform: Transform3D = _get_effective_transform()
	if wall_size.x >= wall_size.z:
		var reach: float = wall_size.x * 0.5 + padding
		return [xform * Vector3(-reach, 0.0, 0.0), xform * Vector3(reach, 0.0, 0.0)]
	var reach_z: float = wall_size.z * 0.5 + padding
	return [xform * Vector3(0.0, 0.0, -reach_z), xform * Vector3(0.0, 0.0, reach_z)]

## Applies structural damage scaled by penetration_power vs armor_tier; destroys wall at 0 HP.
func take_structural_damage(amount: int, penetration_power: int = 0) -> int:
	if is_destroyed or not is_destructible or amount <= 0:
		return 0

	var eff_dmg: int
	if penetration_power >= armor_tier:
		eff_dmg = amount
	elif penetration_power == armor_tier - 1:
		eff_dmg = maxi(1, int(round(float(amount) * 0.5)))
	else:
		eff_dmg = maxi(1, int(round(float(amount) * 0.2)))

	current_hp = maxi(0, current_hp - eff_dmg)

	if wall_mesh_inst != null and wall_mesh_inst.mesh is BoxMesh:
		var bm := wall_mesh_inst.mesh as BoxMesh
		if bm.material is StandardMaterial3D:
			var hp_ratio: float = clampf(float(current_hp) / float(maxi(1, max_hp)), 0.0, 1.0)
			var cracked_tint: Color = base_color.lerp(Color(0.32, 0.16, 0.14), (1.0 - hp_ratio) * 0.75)
			(bm.material as StandardMaterial3D).albedo_color = cracked_tint

	wall_damaged.emit(self, current_hp, max_hp)
	if current_hp == 0:
		destroy_wall()
	return eff_dmg

## Collapses this wall segment into low rubble, disables collision, and opens LOS/movement.
func destroy_wall() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	current_hp = 0
	if wall_mesh_inst != null:
		wall_mesh_inst.visible = false
	if collision_shape != null:
		collision_shape.disabled = true
	if rubble_root != null:
		rubble_root.visible = true
	wall_destroyed.emit(self, get_world_center())
