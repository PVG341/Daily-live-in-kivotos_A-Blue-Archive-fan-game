# scripts/combat/CombatHealthBarOverlay.gd
class_name CombatHealthBarOverlay
extends Control

const BOSS_BAR_WIDTH: float = 480.0
const BOSS_BAR_HEIGHT: float = 20.0
const UNIT_BAR_WIDTH: float = 68.0
const UNIT_BAR_HEIGHT: float = 8.0

var unit_bars: Array[Dictionary] = []
var boss_bar: Dictionary = {}
var floating_numbers: Array[Dictionary] = []

## Updates tracked 2D unit health bars and optional top Boss HP bar, then requests redraw.
func update_bars(p_unit_bars: Array[Dictionary], p_boss_bar: Dictionary = {}) -> void:
	unit_bars = p_unit_bars.duplicate(true)
	boss_bar = p_boss_bar.duplicate(true)
	queue_redraw()

## Spawns a floating damage or heal number anchored in 3D world space.
func spawn_floating_number(world_pos: Vector3, amount: int, is_heal: bool = false, is_heavy: bool = false) -> void:
	if amount <= 0:
		return
	var jitter_x: float = float((floating_numbers.size() % 5) - 2) * 0.22
	var start_world := world_pos + Vector3(jitter_x, 0.0, 0.0)
	var col: Color = Color(0.32, 1.0, 0.52) if is_heal else (Color(1.0, 0.80, 0.16) if is_heavy else Color(1.0, 0.30, 0.26))
	floating_numbers.append({
		"world_pos": start_world,
		"screen_pos": Vector2(start_world.x, start_world.z),
		"text": ("+%d" % amount) if is_heal else ("-%d" % amount),
		"color": col,
		"elapsed": 0.0,
		"duration": 0.9,
		"rise_height": 1.4,
		"is_heavy": is_heavy,
	})
	queue_redraw()

## Advances active floating numbers and updates their projected screen positions.
func tick_floating_numbers(delta: float, camera: Camera3D = null) -> void:
	if delta <= 0.0 and floating_numbers.is_empty():
		return
	var step: float = maxf(0.0, delta)
	var remaining: Array[Dictionary] = []
	var has_cam: bool = camera != null and is_instance_valid(camera) and camera.is_inside_tree()

	for entry in floating_numbers:
		var elapsed: float = float(entry.get("elapsed", 0.0)) + step
		var duration: float = maxf(0.05, float(entry.get("duration", 0.9)))
		if elapsed >= duration:
			continue
		var progress: float = clampf(elapsed / duration, 0.0, 1.0)
		var base_world: Vector3 = entry.get("world_pos", Vector3.ZERO)
		var cur_world: Vector3 = base_world + Vector3(0.0, progress * float(entry.get("rise_height", 1.4)), 0.0)
		var scr_pos := Vector2(cur_world.x, cur_world.z)
		if has_cam and not camera.is_position_behind(cur_world):
			scr_pos = camera.unproject_position(cur_world)
		entry["elapsed"] = elapsed
		entry["screen_pos"] = scr_pos
		remaining.append(entry)

	floating_numbers = remaining
	queue_redraw()

## Clears all rendered bars and active floating damage popups.
func clear_all() -> void:
	unit_bars.clear()
	boss_bar.clear()
	floating_numbers.clear()
	queue_redraw()

func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var vp_width: float = size.x if size.x > 10.0 else 1280.0

	# 1. Per-unit 2D HP bars above living units
	for bar in unit_bars:
		var scr: Vector2 = bar.get("screen_pos", Vector2.ZERO)
		var ratio: float = clampf(float(bar.get("hp_ratio", 1.0)), 0.0, 1.0)
		var is_enemy: bool = bool(bar.get("is_enemy", false))
		var cur_hp: int = int(bar.get("current_hp", 0))
		var max_hp: int = maxi(1, int(bar.get("max_hp", 1)))
		var w: float = UNIT_BAR_WIDTH * (1.25 if bool(bar.get("is_boss", false)) else 1.0)
		var h: float = UNIT_BAR_HEIGHT
		var bar_rect := Rect2(scr.x - w * 0.5, scr.y - 46.0, w, h)

		draw_rect(bar_rect.grow(1.5), Color(0.04, 0.04, 0.07, 0.92), true)
		var fill_col: Color
		if is_enemy:
			fill_col = Color(0.95, 0.22, 0.22) if ratio > 0.30 else Color(1.0, 0.58, 0.14)
		else:
			fill_col = Color(0.22, 0.92, 0.48) if ratio > 0.35 else Color(1.0, 0.80, 0.16)
		draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * ratio, bar_rect.size.y)), fill_col, true)
		draw_rect(bar_rect, Color(0.92, 0.94, 0.98, 0.45), false, 1.0)

		if font != null:
			var hp_str: String = "%d/%d" % [cur_hp, max_hp]
			draw_string(font, bar_rect.position + Vector2(2.0, -3.0), hp_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 1.0, 1.0, 0.92))

	# 2. Prominent top-center Boss HP bar with 70% / 30% phase threshold ticks
	if not boss_bar.is_empty() and bool(boss_bar.get("visible", false)):
		var b_ratio: float = clampf(float(boss_bar.get("hp_ratio", 1.0)), 0.0, 1.0)
		var b_name: String = str(boss_bar.get("name", "BOSS"))
		var b_phase: int = int(boss_bar.get("phase", 1))
		var b_cur: int = int(boss_bar.get("current_hp", 0))
		var b_max: int = maxi(1, int(boss_bar.get("max_hp", 1)))
		var bx: float = vp_width * 0.5 - BOSS_BAR_WIDTH * 0.5
		var by: float = 54.0
		var boss_rect := Rect2(bx, by, BOSS_BAR_WIDTH, BOSS_BAR_HEIGHT)

		draw_rect(boss_rect.grow(3.0), Color(0.06, 0.04, 0.06, 0.92), true)
		draw_rect(Rect2(boss_rect.position, Vector2(boss_rect.size.x * b_ratio, boss_rect.size.y)), Color(0.88, 0.16, 0.22, 0.96), true)
		for thresh: float in [0.3, 0.7]:
			var tx: float = boss_rect.position.x + boss_rect.size.x * thresh
			draw_line(Vector2(tx, boss_rect.position.y), Vector2(tx, boss_rect.end.y), Color(1.0, 0.92, 0.55, 0.9), 2.0)
		draw_rect(boss_rect, Color(1.0, 0.42, 0.42, 0.95), false, 1.5)

		if font != null:
			var label_text: String = "%s (Phase %d)  %d / %d" % [b_name, b_phase, b_cur, b_max]
			draw_string(font, Vector2(boss_rect.position.x + 8.0, boss_rect.position.y + 15.0), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

	# 3. Floating damage & heal numbers
	if font != null:
		for entry in floating_numbers:
			var elapsed: float = float(entry.get("elapsed", 0.0))
			var duration: float = maxf(0.05, float(entry.get("duration", 0.9)))
			var alpha: float = clampf(1.0 - (elapsed / duration), 0.0, 1.0)
			var col: Color = entry.get("color", Color.WHITE)
			col.a *= alpha
			var scr_pos: Vector2 = entry.get("screen_pos", Vector2.ZERO)
			var txt: String = str(entry.get("text", ""))
			var f_size: int = 18 if bool(entry.get("is_heavy", false)) else 14
			draw_string(font, scr_pos + Vector2(1.0, 1.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f_size, Color(0.0, 0.0, 0.0, alpha * 0.85))
			draw_string(font, scr_pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, f_size, col)
