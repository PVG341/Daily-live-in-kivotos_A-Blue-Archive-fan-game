# scripts/combat/DestructibleWall3D.gd
class_name DestructibleWall3D
extends Node3D

signal wall_damaged(wall: Node3D, current_hp: int, max_hp: int)
signal wall_destroyed(wall: Node3D, world_pos: Vector3)

const _NO_HIT: Dictionary = {"hit": false}

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

var _xform_dirty: bool = true
var _cached_xform: Transform3D = Transform3D.IDENTITY
var _cached_inv_xform: Transform3D = Transform3D.IDENTITY
var _cached_center: Vector3 = Vector3.ZERO
var _cached_half_x: float = 1.0
var _cached_half_z: float = 1.0
var _has_unique_material: bool = false

func _ready() -> void:
	set_notify_transform(true)
	_xform_dirty = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED or what == NOTIFICATION_ENTER_TREE:
		_xform_dirty = true

## Initializes dimensions, armor tier, HP, material color, and physics collider.
func setup_wall(
	p_size: Vector3,
	p_armor_tier: int = 2,
	p_max_hp: int = 550,
	p_color: Color = Color(0.72, 0.66, 0.58),
	p_destructible: bool = true,
	p_shared_material: StandardMaterial3D = null
) -> void:
	wall_size = Vector3(maxf(0.1, p_size.x), maxf(0.1, p_size.y), maxf(0.1, p_size.z))
	armor_tier = p_armor_tier
	max_hp = maxi(1, p_max_hp)
	current_hp = max_hp
	base_color = p_color
	is_destructible = p_destructible
	is_destroyed = false
	_xform_dirty = true

	_ensure_nodes()
	_sync_visuals_and_collider(p_shared_material)

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

func _ensure_rubble_nodes() -> void:
	if rubble_root == null:
		rubble_root = get_node_or_null("RubbleRoot") as Node3D
	if rubble_root == null:
		rubble_root = Node3D.new()
		rubble_root.name = "RubbleRoot"
		rubble_root.visible = false
		add_child(rubble_root)
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = base_color.darkened(0.35)
		for i in range(3):
			var chunk := MeshInstance3D.new()
			chunk.name = "Rubble_%d" % i
			var cmesh := BoxMesh.new()
			cmesh.size = Vector3(0.45, 0.18, 0.42)
			cmesh.material = cmat
			chunk.mesh = cmesh
			rubble_root.add_child(chunk)
	_layout_rubble_chunks()

func _layout_rubble_chunks() -> void:
	if rubble_root == null:
		return
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

func _sync_visuals_and_collider(p_shared_material: StandardMaterial3D = null) -> void:
	if wall_mesh_inst != null:
		var bmesh := BoxMesh.new()
		bmesh.size = wall_size
		if p_shared_material != null:
			bmesh.material = p_shared_material
			_has_unique_material = false
		else:
			var bmat := StandardMaterial3D.new()
			bmat.albedo_color = base_color
			bmesh.material = bmat
			_has_unique_material = true
		wall_mesh_inst.mesh = bmesh
		wall_mesh_inst.visible = not is_destroyed

	if collision_shape != null:
		var bshape := BoxShape3D.new()
		bshape.size = wall_size
		collision_shape.shape = bshape
		collision_shape.disabled = is_destroyed

	if rubble_root != null:
		rubble_root.visible = is_destroyed
		_layout_rubble_chunks()

func _refresh_xform_cache() -> void:
	if is_inside_tree():
		if not _xform_dirty:
			return
		_cached_xform = global_transform
		_xform_dirty = false
	else:
		var xform: Transform3D = transform
		var p: Node = get_parent()
		while p != null:
			if p is Node3D:
				xform = (p as Node3D).transform * xform
			p = p.get_parent()
		_cached_xform = xform

	_cached_inv_xform = _cached_xform.affine_inverse()
	_cached_center = _cached_xform.origin
	var hx: float = wall_size.x * 0.5
	var hy: float = wall_size.y * 0.5
	var hz: float = wall_size.z * 0.5
	var bx: Vector3 = _cached_xform.basis.x
	var by: Vector3 = _cached_xform.basis.y
	var bz: Vector3 = _cached_xform.basis.z
	_cached_half_x = absf(bx.x) * hx + absf(by.x) * hy + absf(bz.x) * hz
	_cached_half_z = absf(bx.z) * hx + absf(by.z) * hy + absf(bz.z) * hz

func _get_effective_transform() -> Transform3D:
	_refresh_xform_cache()
	return _cached_xform

## Returns the world-space center of this wall segment.
func get_world_center() -> Vector3:
	_refresh_xform_cache()
	return _cached_center

## Tests 3D segment [from_pos, to_pos] against this wall's oriented bounding box.
func intersects_segment(from_pos: Vector3, to_pos: Vector3, padding: float = 0.08) -> Dictionary:
	if is_destroyed:
		return _NO_HIT
	_refresh_xform_cache()
	var pad_x: float = _cached_half_x + padding
	if maxf(from_pos.x, to_pos.x) < _cached_center.x - pad_x or minf(from_pos.x, to_pos.x) > _cached_center.x + pad_x:
		return _NO_HIT
	var pad_z: float = _cached_half_z + padding
	if maxf(from_pos.z, to_pos.z) < _cached_center.z - pad_z or minf(from_pos.z, to_pos.z) > _cached_center.z + pad_z:
		return _NO_HIT

	var p0: Vector3 = _cached_inv_xform * from_pos
	var p1: Vector3 = _cached_inv_xform * to_pos
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
				return _NO_HIT
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
				return _NO_HIT

	var local_hit: Vector3 = p0 + dir * t_min
	return {
		"hit": true,
		"t": t_min,
		"point": _cached_xform * local_hit,
		"wall": self,
	}

## Returns true when world_pos lies inside this unbroken wall's XZ footprint plus padding.
func intersects_point_xz(world_pos: Vector3, padding: float = 0.35) -> bool:
	if is_destroyed:
		return false
	_refresh_xform_cache()
	if absf(world_pos.x - _cached_center.x) > _cached_half_x + padding or absf(world_pos.z - _cached_center.z) > _cached_half_z + padding:
		return false
	var local_pt: Vector3 = _cached_inv_xform * world_pos
	var half_x: float = wall_size.x * 0.5 + padding
	var half_z: float = wall_size.z * 0.5 + padding
	var half_y: float = wall_size.y * 0.5 + 1.0
	return absf(local_pt.x) <= half_x and absf(local_pt.z) <= half_z and absf(local_pt.y) <= half_y

## Returns a world-space XZ push-out vector if world_pos overlaps this unbroken wall plus padding.
func get_push_out_offset(world_pos: Vector3, padding: float = 0.42) -> Vector3:
	if not intersects_point_xz(world_pos, padding):
		return Vector3.ZERO
	var local_pt: Vector3 = _cached_inv_xform * world_pos
	var half_x: float = wall_size.x * 0.5 + padding
	var half_z: float = wall_size.z * 0.5 + padding
	var pen_x: float = half_x - absf(local_pt.x)
	var pen_z: float = half_z - absf(local_pt.z)
	var local_push := Vector3.ZERO
	if pen_x < pen_z:
		local_push.x = (pen_x + 0.04) * (1.0 if local_pt.x >= 0.0 else -1.0)
	else:
		local_push.z = (pen_z + 0.04) * (1.0 if local_pt.z >= 0.0 else -1.0)
	var world_push: Vector3 = _cached_xform.basis * local_push
	world_push.y = 0.0
	return world_push

## Returns the two lateral corner waypoints outside the ends of this wall segment for clean flanking.
func get_flank_corners(padding: float = 1.2) -> Array[Vector3]:
	_refresh_xform_cache()
	if wall_size.x >= wall_size.z:
		var reach: float = wall_size.x * 0.5 + padding
		return [_cached_xform * Vector3(-reach, 0.0, 0.0), _cached_xform * Vector3(reach, 0.0, 0.0)]
	var reach_z: float = wall_size.z * 0.5 + padding
	return [_cached_xform * Vector3(0.0, 0.0, -reach_z), _cached_xform * Vector3(0.0, 0.0, reach_z)]

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
			if not _has_unique_material:
				bm.material = (bm.material as StandardMaterial3D).duplicate()
				_has_unique_material = true
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
	_ensure_rubble_nodes()
	if rubble_root != null:
		rubble_root.visible = true
	wall_destroyed.emit(self, get_world_center())
