# scripts/combat/BattlefieldNavGrid.gd
class_name BattlefieldNavGrid
extends RefCounted

const DEFAULT_CELL_SIZE: float = 1.0
const DEFAULT_WALL_PADDING: float = 0.48

var grid: AStarGrid2D = AStarGrid2D.new()
var cell_size: float = DEFAULT_CELL_SIZE
var origin_x: float = -40.0
var origin_z: float = -40.0
var grid_width: int = 0
var grid_height: int = 0

var _cell_block_counts: PackedInt32Array = PackedInt32Array()
var _wall_cells: Dictionary = {}
var _static_boxes: Array[Dictionary] = []
var _is_built: bool = false

## Builds the XZ navigation grid and stamps all destructible walls, static perimeter walls, fountains, and connector walls.
func build_from_battlefield(
	bounds_min: Vector2,
	bounds_max: Vector2,
	sectors: Array,
	connectors: Array,
	p_cell_size: float = DEFAULT_CELL_SIZE
) -> void:
	clear()
	cell_size = maxf(0.5, p_cell_size)
	origin_x = floorf(bounds_min.x - 2.0)
	origin_z = floorf(bounds_min.y - 2.0)
	var span_x: float = maxf(4.0, (bounds_max.x + 2.0) - origin_x)
	var span_z: float = maxf(4.0, (bounds_max.y + 2.0) - origin_z)
	grid_width = maxi(4, int(ceilf(span_x / cell_size)))
	grid_height = maxi(4, int(ceilf(span_z / cell_size)))

	grid.region = Rect2i(0, 0, grid_width, grid_height)
	grid.cell_size = Vector2(cell_size, cell_size)
	grid.offset = Vector2(origin_x + cell_size * 0.5, origin_z + cell_size * 0.5)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()

	_cell_block_counts.resize(grid_width * grid_height)
	_cell_block_counts.fill(0)
	_is_built = true

	for sector in sectors:
		if sector == null or not is_instance_valid(sector):
			continue
		if sector.has_method(&"get_wall_obstacles"):
			for wall in sector.get_wall_obstacles():
				mark_wall(wall)

		var nav_reg := sector.get_node_or_null("NavigationRegion3D") as Node
		if nav_reg != null:
			for child in nav_reg.get_children():
				if child is CSGBox3D:
					var box := child as CSGBox3D
					var cname: String = str(box.name)
					if box.visible and box.use_collision and cname.contains("Wall"):
						_stamp_csg_box(box)

		var fountain := sector.get_node_or_null("RestFountain") as Node
		if fountain is CSGCylinder3D:
			var cyl := fountain as CSGCylinder3D
			if cyl.visible and cyl.use_collision:
				var f_xform: Transform3D = _get_node_world_transform(cyl)
				var rad: float = maxf(0.1, cyl.radius)
				_add_static_box(
					f_xform.origin.x - rad,
					f_xform.origin.x + rad,
					f_xform.origin.z - rad,
					f_xform.origin.z + rad
				)

	for conn in connectors:
		if conn == null or not is_instance_valid(conn):
			continue
		for child in conn.get_children():
			if child is CSGBox3D:
				var box := child as CSGBox3D
				var cname: String = str(box.name)
				if box.visible and box.use_collision and cname.contains("Wall"):
					_stamp_csg_box(box)

## Stamps an unbroken DestructibleWall3D's occupied cells into the grid using reference-counted solidity.
func mark_wall(wall: Object, padding: float = DEFAULT_WALL_PADDING) -> void:
	if not _is_built or wall == null or not is_instance_valid(wall):
		return
	if bool(wall.get(&"is_destroyed")):
		return
	var wid: int = wall.get_instance_id()
	if _wall_cells.has(wid):
		return

	if wall.has_method(&"_refresh_xform_cache"):
		wall._refresh_xform_cache()
	var center: Vector3 = wall.get_world_center() if wall.has_method(&"get_world_center") else (wall as Node3D).position
	var half_x: float
	var half_z: float
	if &"_cached_half_x" in wall and &"_cached_half_z" in wall:
		half_x = float(wall.get(&"_cached_half_x"))
		half_z = float(wall.get(&"_cached_half_z"))
	else:
		var ws: Vector3 = wall.get(&"wall_size") if (&"wall_size" in wall) else Vector3(2.0, 2.0, 2.0)
		var max_dim: float = maxf(ws.x, ws.z) * 0.5
		half_x = max_dim
		half_z = max_dim

	var min_gx: int = clampi(int(floorf((center.x - half_x - padding - origin_x) / cell_size)), 0, grid_width - 1)
	var max_gx: int = clampi(int(floorf((center.x + half_x + padding - origin_x) / cell_size)), 0, grid_width - 1)
	var min_gz: int = clampi(int(floorf((center.z - half_z - padding - origin_z) / cell_size)), 0, grid_height - 1)
	var max_gz: int = clampi(int(floorf((center.z + half_z + padding - origin_z) / cell_size)), 0, grid_height - 1)

	var has_pt_check: bool = wall.has_method(&"intersects_point_xz")
	var stamped := PackedInt32Array()
	for gz in range(min_gz, max_gz + 1):
		var cz: float = origin_z + (float(gz) + 0.5) * cell_size
		for gx in range(min_gx, max_gx + 1):
			var cx: float = origin_x + (float(gx) + 0.5) * cell_size
			if has_pt_check and not wall.intersects_point_xz(Vector3(cx, center.y, cz), padding):
				continue
			var flat_idx: int = gz * grid_width + gx
			stamped.append(flat_idx)
			_increment_cell_block(flat_idx, gx, gz)

	_wall_cells[wid] = stamped

## Unmarks a destroyed DestructibleWall3D's cells while keeping any cells still shared with intact neighbors solid.
func unmark_wall(wall: Object) -> void:
	if not _is_built or wall == null:
		return
	var wid: int = wall.get_instance_id()
	if not _wall_cells.has(wid):
		return
	var cells: PackedInt32Array = _wall_cells[wid]
	for flat_idx in cells:
		if flat_idx < 0 or flat_idx >= _cell_block_counts.size():
			continue
		var next_cnt: int = maxi(0, _cell_block_counts[flat_idx] - 1)
		_cell_block_counts[flat_idx] = next_cnt
		if next_cnt == 0:
			var gx: int = flat_idx % grid_width
			var gz: int = flat_idx / grid_width
			grid.set_point_solid(Vector2i(gx, gz), false)
	_wall_cells.erase(wid)

func _stamp_csg_box(box: CSGBox3D) -> void:
	var xform: Transform3D = _get_node_world_transform(box)
	var hx: float = box.size.x * 0.5
	var hy: float = box.size.y * 0.5
	var hz: float = box.size.z * 0.5
	var bx: Vector3 = xform.basis.x
	var by: Vector3 = xform.basis.y
	var bz: Vector3 = xform.basis.z
	var half_x: float = absf(bx.x) * hx + absf(by.x) * hy + absf(bz.x) * hz
	var half_z: float = absf(bx.z) * hx + absf(by.z) * hy + absf(bz.z) * hz
	var c: Vector3 = xform.origin
	_add_static_box(c.x - half_x, c.x + half_x, c.z - half_z, c.z + half_z)

func _add_static_box(min_x: float, max_x: float, min_z: float, max_z: float, padding: float = DEFAULT_WALL_PADDING) -> void:
	_static_boxes.append({
		"min_x": min_x,
		"max_x": max_x,
		"min_z": min_z,
		"max_z": max_z,
	})
	if not _is_built:
		return
	var p_min_x: float = min_x - padding
	var p_max_x: float = max_x + padding
	var p_min_z: float = min_z - padding
	var p_max_z: float = max_z + padding
	var min_gx: int = clampi(int(floorf((p_min_x - origin_x) / cell_size)), 0, grid_width - 1)
	var max_gx: int = clampi(int(floorf((p_max_x - origin_x) / cell_size)), 0, grid_width - 1)
	var min_gz: int = clampi(int(floorf((p_min_z - origin_z) / cell_size)), 0, grid_height - 1)
	var max_gz: int = clampi(int(floorf((p_max_z - origin_z) / cell_size)), 0, grid_height - 1)
	for gz in range(min_gz, max_gz + 1):
		var cz: float = origin_z + (float(gz) + 0.5) * cell_size
		if cz < p_min_z or cz > p_max_z:
			continue
		for gx in range(min_gx, max_gx + 1):
			var cx: float = origin_x + (float(gx) + 0.5) * cell_size
			if cx < p_min_x or cx > p_max_x:
				continue
			var flat_idx: int = gz * grid_width + gx
			_increment_cell_block(flat_idx, gx, gz)

func _increment_cell_block(flat_idx: int, gx: int, gz: int) -> void:
	if flat_idx < 0 or flat_idx >= _cell_block_counts.size():
		return
	var prev: int = _cell_block_counts[flat_idx]
	_cell_block_counts[flat_idx] = prev + 1
	if prev == 0:
		grid.set_point_solid(Vector2i(gx, gz), true)

func _get_node_world_transform(n: Node3D) -> Transform3D:
	if n == null:
		return Transform3D.IDENTITY
	if n.is_inside_tree():
		return n.global_transform
	var xform: Transform3D = n.transform
	var p: Node = n.get_parent()
	while p != null:
		if p is Node3D:
			xform = (p as Node3D).transform * xform
		p = p.get_parent()
	return xform

## Returns true when world_pos overlaps any static perimeter/corridor wall or fountain AABB plus padding.
func is_point_blocked_by_static(world_pos: Vector3, padding: float = 0.36) -> bool:
	for box in _static_boxes:
		if world_pos.x >= float(box["min_x"]) - padding and world_pos.x <= float(box["max_x"]) + padding:
			if world_pos.z >= float(box["min_z"]) - padding and world_pos.z <= float(box["max_z"]) + padding:
				return true
	return false

## Returns an XZ push-out offset if world_pos overlaps any static wall AABB plus padding.
func get_static_push_out_offset(world_pos: Vector3, padding: float = 0.40) -> Vector3:
	for box in _static_boxes:
		var min_x: float = float(box["min_x"]) - padding
		var max_x: float = float(box["max_x"]) + padding
		if world_pos.x < min_x or world_pos.x > max_x:
			continue
		var min_z: float = float(box["min_z"]) - padding
		var max_z: float = float(box["max_z"]) + padding
		if world_pos.z < min_z or world_pos.z > max_z:
			continue
		var pen_left: float = world_pos.x - min_x
		var pen_right: float = max_x - world_pos.x
		var pen_back: float = world_pos.z - min_z
		var pen_front: float = max_z - world_pos.z
		var best_pen: float = pen_left
		var push := Vector3(-(pen_left + 0.04), 0.0, 0.0)
		if pen_right < best_pen:
			best_pen = pen_right
			push = Vector3(pen_right + 0.04, 0.0, 0.0)
		if pen_back < best_pen:
			best_pen = pen_back
			push = Vector3(0.0, 0.0, -(pen_back + 0.04))
		if pen_front < best_pen:
			push = Vector3(0.0, 0.0, pen_front + 0.04)
		return push
	return Vector3.ZERO

## Returns true if the XZ segment [from_pos, to_pos] intersects any padded static wall AABB.
func is_segment_blocked_by_static(from_pos: Vector3, to_pos: Vector3, padding: float = 0.32) -> bool:
	if _static_boxes.is_empty():
		return false
	var x0: float = from_pos.x
	var z0: float = from_pos.z
	var dx: float = to_pos.x - x0
	var dz: float = to_pos.z - z0
	var seg_min_x: float = minf(x0, to_pos.x)
	var seg_max_x: float = maxf(x0, to_pos.x)
	var seg_min_z: float = minf(z0, to_pos.z)
	var seg_max_z: float = maxf(z0, to_pos.z)
	for box in _static_boxes:
		var b_min_x: float = float(box["min_x"]) - padding
		var b_max_x: float = float(box["max_x"]) + padding
		if seg_max_x < b_min_x or seg_min_x > b_max_x:
			continue
		var b_min_z: float = float(box["min_z"]) - padding
		var b_max_z: float = float(box["max_z"]) + padding
		if seg_max_z < b_min_z or seg_min_z > b_max_z:
			continue
		var t_min: float = 0.0
		var t_max: float = 1.0
		if absf(dx) < 0.00001:
			if x0 < b_min_x or x0 > b_max_x:
				continue
		else:
			var tx1: float = (b_min_x - x0) / dx
			var tx2: float = (b_max_x - x0) / dx
			if tx1 > tx2:
				var tmp: float = tx1
				tx1 = tx2
				tx2 = tmp
			t_min = maxf(t_min, tx1)
			t_max = minf(t_max, tx2)
			if t_min > t_max:
				continue
		if absf(dz) < 0.00001:
			if z0 < b_min_z or z0 > b_max_z:
				continue
		else:
			var tz1: float = (b_min_z - z0) / dz
			var tz2: float = (b_max_z - z0) / dz
			if tz1 > tz2:
				var tmp2: float = tz1
				tz1 = tz2
				tz2 = tmp2
			t_min = maxf(t_min, tz1)
			t_max = minf(t_max, tz2)
			if t_min > t_max:
				continue
		return true
	return false

## Maps a world-space XZ coordinate to a clamped grid cell.
func world_to_cell(world_pos: Vector3) -> Vector2i:
	if grid_width <= 0 or grid_height <= 0:
		return Vector2i(-1, -1)
	var gx: int = clampi(int(floorf((world_pos.x - origin_x) / cell_size)), 0, grid_width - 1)
	var gz: int = clampi(int(floorf((world_pos.z - origin_z) / cell_size)), 0, grid_height - 1)
	return Vector2i(gx, gz)

## Maps a grid cell index back to its world-space center.
func cell_to_world(cell: Vector2i, y: float = 0.0) -> Vector3:
	return Vector3(
		origin_x + (float(cell.x) + 0.5) * cell_size,
		y,
		origin_z + (float(cell.y) + 0.5) * cell_size
	)

## Returns the cell containing world_pos if walkable, or the closest non-solid cell within max_radius.
func find_nearest_walkable_cell(world_pos: Vector3, max_radius: int = 6) -> Vector2i:
	if not _is_built:
		return Vector2i(-1, -1)
	var base := world_to_cell(world_pos)
	if base.x < 0 or base.y < 0:
		return Vector2i(-1, -1)
	if not grid.is_point_solid(base):
		return base
	var best_cell := Vector2i(-1, -1)
	var best_dist_sq: float = INF
	for r in range(1, max_radius + 1):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r:
					continue
				var cx: int = base.x + dx
				var cz: int = base.y + dz
				if cx < 0 or cx >= grid_width or cz < 0 or cz >= grid_height:
					continue
				var cand := Vector2i(cx, cz)
				if grid.is_point_solid(cand):
					continue
				var wpos := cell_to_world(cand)
				var ddx: float = wpos.x - world_pos.x
				var ddz: float = wpos.z - world_pos.z
				var d_sq: float = ddx * ddx + ddz * ddz
				if d_sq < best_dist_sq:
					best_dist_sq = d_sq
					best_cell = cand
		if best_cell.x >= 0:
			return best_cell
	return Vector2i(-1, -1)

## Computes an XZ waypoint path between from_pos and to_pos using AStarGrid2D.
func find_path_xz(from_pos: Vector3, to_pos: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if not _is_built:
		return result
	var start_cell := find_nearest_walkable_cell(from_pos)
	var goal_cell := find_nearest_walkable_cell(to_pos)
	if start_cell.x < 0 or goal_cell.x < 0:
		return result
	if start_cell == goal_cell:
		result.append(Vector3(to_pos.x, from_pos.y, to_pos.z))
		return result

	var raw_pts: PackedVector2Array = grid.get_point_path(start_cell, goal_cell, true)
	if raw_pts.is_empty():
		return result

	for i in range(raw_pts.size()):
		var pt2: Vector2 = raw_pts[i]
		var wp := Vector3(pt2.x, from_pos.y, pt2.y)
		if i == 0 and raw_pts.size() > 1:
			var dx: float = wp.x - from_pos.x
			var dz: float = wp.z - from_pos.z
			if dx * dx + dz * dz <= 0.4225:
				continue
		result.append(wp)

	if not result.is_empty():
		var raw_goal_cell := world_to_cell(to_pos)
		if goal_cell == raw_goal_cell and not grid.is_point_solid(goal_cell):
			result[result.size() - 1] = Vector3(to_pos.x, from_pos.y, to_pos.z)

	return result

## Clears all cached solidity and grid state.
func clear() -> void:
	_wall_cells.clear()
	_static_boxes.clear()
	_cell_block_counts.clear()
	grid.clear()
	grid_width = 0
	grid_height = 0
	_is_built = false
