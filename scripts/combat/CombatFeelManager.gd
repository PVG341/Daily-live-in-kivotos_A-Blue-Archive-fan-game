# scripts/combat/CombatFeelManager.gd
class_name CombatFeelManager
extends Node

const MAX_ACTIVE_VFX: int = 48
const SFX_POOL_SIZE: int = 6

var effects_container: Node3D = null

var hit_stop_remaining: float = 0.0
var hit_stop_scale: float = 1.0

var _active_vfx: Array[Dictionary] = []
var _active_flashes: Array[Dictionary] = []
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_streams: Dictionary = {}
var _sfx_cursor: int = 0
var _audio_ready: bool = false

func _ready() -> void:
	_ensure_audio_pool()

func _exit_tree() -> void:
	clear_effects()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		clear_effects()

func _ensure_audio_pool() -> void:
	if _audio_ready or DisplayServer.get_name() == "headless":
		return
	_audio_ready = true
	for i in range(SFX_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "SFXPlayer_%d" % i
		add_child(player)
		_sfx_players.append(player)

	_sfx_streams["shot_ar"] = _synth_tone_wav(460.0, 210.0, 0.07, 0.12)
	_sfx_streams["shot_sg"] = _synth_tone_wav(220.0, 85.0, 0.13, 0.35)
	_sfx_streams["shot_sr"] = _synth_tone_wav(920.0, 320.0, 0.14, 0.08)
	_sfx_streams["explosion"] = _synth_tone_wav(145.0, 48.0, 0.24, 0.55)
	_sfx_streams["breach"] = _synth_tone_wav(190.0, 58.0, 0.20, 0.65)
	_sfx_streams["heal"] = _synth_tone_wav(540.0, 860.0, 0.18, 0.0)
	_sfx_streams["alert"] = _synth_tone_wav(740.0, 980.0, 0.12, 0.02)
	_sfx_streams["ui_click"] = _synth_tone_wav(680.0, 820.0, 0.05, 0.0)

func _synth_tone_wav(start_freq: float, end_freq: float, duration_sec: float, noise_mix: float) -> AudioStreamWAV:
	var mix_rate: int = 22050
	var sample_count: int = maxi(64, int(round(duration_sec * float(mix_rate))))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var phase: float = 0.0
	var seed_val: int = 1337
	for i in range(sample_count):
		var t: float = float(i) / float(sample_count)
		var freq: float = lerpf(start_freq, end_freq, t)
		phase += TAU * freq / float(mix_rate)
		seed_val = (seed_val * 1103515245 + 12345) & 0x7fffffff
		var noise: float = (float(seed_val % 2000) / 1000.0) - 1.0
		var env: float = (1.0 - t) * (1.0 - t)
		var tone: float = sin(phase) * (1.0 - noise_mix) + noise * noise_mix
		var sample_i16: int = clampi(int(round(tone * env * 22000.0)), -32767, 32767)
		data[i * 2] = sample_i16 & 0xFF
		data[i * 2 + 1] = (sample_i16 >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	wav.data = data
	return wav

## Plays a synthesized procedural combat sound effect on the round-robin AudioStreamPlayer pool.
func play_sfx(sfx_name: String, volume_db: float = -8.0) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not _audio_ready:
		_ensure_audio_pool()
	var stream: Variant = _sfx_streams.get(sfx_name, null)
	if not (stream is AudioStreamWAV) or _sfx_players.is_empty():
		return
	var player: AudioStreamPlayer = _sfx_players[_sfx_cursor % _sfx_players.size()]
	_sfx_cursor += 1
	if player != null and is_instance_valid(player):
		player.stream = stream as AudioStreamWAV
		player.volume_db = volume_db
		player.play()

func _get_settings_values() -> Dictionary:
	var sm: Node = null
	if is_inside_tree():
		sm = get_node_or_null("/root/SettingsManager")
	var shake_mult: float = 1.0
	var reduce_flash: bool = false
	if sm != null:
		if &"screen_shake_strength" in sm:
			shake_mult = clampf(float(sm.get("screen_shake_strength")), 0.0, 1.0)
		if &"reduce_flashing" in sm:
			reduce_flash = bool(sm.get("reduce_flashing"))
	return {
		"shake_strength": shake_mult,
		"reduce_flashing": reduce_flash,
	}

## Fires a proportional multi-channel feedback bundle ("SMALL", "MEDIUM", or "LARGE").
func trigger_feedback(tier: String, _world_pos: Vector3, camera_rig: Node3D = null) -> void:
	var cfg: Dictionary = _get_settings_values()
	var shake_mult: float = float(cfg["shake_strength"])
	if camera_rig != null and is_instance_valid(camera_rig):
		if &"shake_strength" in camera_rig:
			camera_rig.set(&"shake_strength", shake_mult)
	match tier.to_upper():
		"SMALL":
			if camera_rig != null and is_instance_valid(camera_rig) and camera_rig.has_method(&"add_trauma"):
				camera_rig.add_trauma(0.10)
		"MEDIUM":
			if camera_rig != null and is_instance_valid(camera_rig) and camera_rig.has_method(&"add_trauma"):
				camera_rig.add_trauma(0.32)
			trigger_hit_stop(0.035, 0.15)
		"LARGE":
			if camera_rig != null and is_instance_valid(camera_rig) and camera_rig.has_method(&"add_trauma"):
				camera_rig.add_trauma(0.68)
			trigger_hit_stop(0.075, 0.08)

## Triggers a non-blocking real-time simulation hit-stop multiplier without overlapping extensions.
func trigger_hit_stop(duration: float, slow_scale: float = 0.12) -> void:
	if duration <= 0.0:
		return
	if hit_stop_remaining > 0.0:
		if duration > hit_stop_remaining:
			hit_stop_remaining = duration
			hit_stop_scale = clampf(slow_scale, 0.04, 1.0)
		return
	hit_stop_remaining = duration
	hit_stop_scale = clampf(slow_scale, 0.04, 1.0)

## Returns current simulation time scale factor contributed by active hit-stop.
func get_hit_stop_scale() -> float:
	if hit_stop_remaining > 0.0:
		return hit_stop_scale
	return 1.0

func _attach_vfx_node(node: Node3D) -> void:
	while _active_vfx.size() >= MAX_ACTIVE_VFX:
		var oldest: Dictionary = _active_vfx.pop_front()
		var old_n: Variant = oldest.get("node", null)
		if old_n is Node and is_instance_valid(old_n):
			var on := old_n as Node
			if on.get_parent() != null:
				on.get_parent().remove_child(on)
			on.free()
	if effects_container != null and is_instance_valid(effects_container):
		effects_container.add_child(node)
	else:
		add_child(node)

## Spawns an unshaded tracer beam along from_pos -> to_pos that fades cleanly over duration.
func spawn_tracer(
	from_pos: Vector3,
	to_pos: Vector3,
	color: Color,
	width: float = 0.09,
	duration: float = 0.14
) -> MeshInstance3D:
	var diff: Vector3 = to_pos - from_pos
	var dist: float = diff.length()
	if dist <= 0.02:
		return null

	var cfg: Dictionary = _get_settings_values()
	var eff_col := color
	if bool(cfg["reduce_flashing"]):
		eff_col.a = minf(eff_col.a, 0.55)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "TracerVFX"
	var bm := BoxMesh.new()
	bm.size = Vector3(width, width, dist)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = eff_col
	bm.material = mat
	mesh_inst.mesh = bm

	var fwd: Vector3 = diff / dist
	var up_ref: Vector3 = Vector3.UP if absf(fwd.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var right: Vector3 = up_ref.cross(fwd).normalized()
	var real_up: Vector3 = fwd.cross(right).normalized()
	mesh_inst.transform = Transform3D(Basis(right, real_up, -fwd), from_pos.lerp(to_pos, 0.5))

	_attach_vfx_node(mesh_inst)
	_active_vfx.append({
		"type": "TRACER",
		"node": mesh_inst,
		"material": mat,
		"base_alpha": eff_col.a,
		"elapsed": 0.0,
		"duration": maxf(0.04, duration),
	})
	return mesh_inst

## Spawns an expanding 3D shockwave ring + burst sphere at world_pos.
func spawn_explosion_burst(
	world_pos: Vector3,
	radius: float,
	color: Color,
	duration: float = 0.34
) -> Node3D:
	var cfg: Dictionary = _get_settings_values()
	var safe_rad: float = maxf(0.5, radius)
	var eff_col := color
	if bool(cfg["reduce_flashing"]):
		eff_col.a = minf(eff_col.a, 0.45)

	var root := Node3D.new()
	root.name = "ExplosionBurstVFX"
	root.position = Vector3(world_pos.x, world_pos.y + 0.15, world_pos.z)
	root.scale = Vector3(0.25, 0.25, 0.25)

	var ring := MeshInstance3D.new()
	ring.name = "ShockRing"
	var tm := TorusMesh.new()
	tm.inner_radius = safe_rad * 0.78
	tm.outer_radius = safe_rad
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = Color(eff_col.r, eff_col.g, eff_col.b, 0.85)
	tm.material = ring_mat
	ring.mesh = tm
	root.add_child(ring)

	var core := MeshInstance3D.new()
	core.name = "BurstCore"
	var sm := SphereMesh.new()
	sm.radius = safe_rad * 0.45
	sm.height = safe_rad * 0.90
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core_mat.albedo_color = Color(eff_col.r, eff_col.g, eff_col.b, 0.42 if bool(cfg["reduce_flashing"]) else 0.68)
	sm.material = core_mat
	core.mesh = sm
	root.add_child(core)

	_attach_vfx_node(root)
	_active_vfx.append({
		"type": "BURST",
		"node": root,
		"materials": [ring_mat, core_mat],
		"base_alphas": [ring_mat.albedo_color.a, core_mat.albedo_color.a],
		"elapsed": 0.0,
		"duration": maxf(0.05, duration),
	})
	return root

## Spawns a 5-ray shotgun cone muzzle blast fan toward target_pos.
func spawn_cone_flash(
	origin_pos: Vector3,
	target_pos: Vector3,
	radius: float,
	color: Color,
	duration: float = 0.24
) -> Node3D:
	var root := Node3D.new()
	root.name = "ConeFlashVFX"
	root.position = Vector3(origin_pos.x, origin_pos.y + 0.55, origin_pos.z)
	var diff := Vector2(target_pos.x - origin_pos.x, target_pos.z - origin_pos.z)
	var base_yaw: float = atan2(diff.x, diff.y) if diff.length() > 0.01 else 0.0
	var reach: float = clampf(radius, 3.0, 14.0)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, 0.82)

	for i in range(-2, 3):
		var ray := MeshInstance3D.new()
		ray.name = "ConeRay_%d" % (i + 2)
		var bm := BoxMesh.new()
		bm.size = Vector3(0.11, 0.11, reach)
		bm.material = mat
		ray.mesh = bm
		var yaw: float = base_yaw + deg_to_rad(float(i) * 12.0)
		var dir3 := Vector3(sin(yaw), 0.0, cos(yaw))
		ray.rotation.y = yaw
		ray.position = dir3 * (reach * 0.5)
		root.add_child(ray)

	_attach_vfx_node(root)
	_active_vfx.append({
		"type": "BURST",
		"node": root,
		"materials": [mat],
		"base_alphas": [mat.albedo_color.a],
		"elapsed": 0.0,
		"duration": maxf(0.05, duration),
	})
	return root

## Triggers a non-stacking squash/pop scale reaction on unit VisualRoot when hit.
func trigger_unit_hit_flash(unit: Node3D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var vis_root := unit.get_node_or_null("VisualRoot") as Node3D
	if vis_root == null or not is_instance_valid(vis_root):
		return
	vis_root.scale = Vector3(1.14, 0.88, 1.14)
	for entry in _active_flashes:
		if entry.get("vis_root", null) == vis_root:
			entry["elapsed"] = 0.0
			return
	_active_flashes.append({
		"vis_root": vis_root,
		"elapsed": 0.0,
		"duration": 0.12,
	})

## Advances hit-stop, active VFX lifetimes, and hit squash recovery in real time.
func tick_effects(real_delta: float) -> void:
	var dt: float = maxf(0.0, real_delta)
	if dt <= 0.0:
		return

	if hit_stop_remaining > 0.0:
		hit_stop_remaining = maxf(0.0, hit_stop_remaining - dt)
		if hit_stop_remaining <= 0.0:
			hit_stop_scale = 1.0

	var remaining_vfx: Array[Dictionary] = []
	for entry in _active_vfx:
		var node: Variant = entry.get("node", null)
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		var elapsed: float = float(entry.get("elapsed", 0.0)) + dt
		var duration: float = maxf(0.02, float(entry.get("duration", 0.2)))
		if elapsed >= duration:
			var n := node as Node
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
			continue
		entry["elapsed"] = elapsed
		var t: float = clampf(elapsed / duration, 0.0, 1.0)
		var vtype: String = str(entry.get("type", "TRACER"))
		if vtype == "TRACER":
			var mat: Variant = entry.get("material", null)
			if mat is StandardMaterial3D:
				(mat as StandardMaterial3D).albedo_color.a = float(entry.get("base_alpha", 0.9)) * (1.0 - t)
		elif vtype == "BURST":
			var s: float = lerpf(0.25, 1.15, 1.0 - (1.0 - t) * (1.0 - t))
			(node as Node3D).scale = Vector3(s, s, s)
			var mats: Array = entry.get("materials", [])
			var alphas: Array = entry.get("base_alphas", [])
			for i in range(mats.size()):
				var m: Variant = mats[i]
				if m is StandardMaterial3D:
					var ba: float = float(alphas[i]) if i < alphas.size() else 0.7
					(m as StandardMaterial3D).albedo_color.a = ba * (1.0 - t)
		remaining_vfx.append(entry)
	_active_vfx = remaining_vfx

	var remaining_flashes: Array[Dictionary] = []
	for fentry in _active_flashes:
		var vr: Variant = fentry.get("vis_root", null)
		if not (vr is Node3D) or not is_instance_valid(vr):
			continue
		var vis := vr as Node3D
		var elapsed: float = float(fentry.get("elapsed", 0.0)) + dt
		var duration: float = maxf(0.02, float(fentry.get("duration", 0.12)))
		if elapsed >= duration:
			vis.scale = Vector3.ONE
			continue
		fentry["elapsed"] = elapsed
		var p: float = clampf(elapsed / duration, 0.0, 1.0)
		vis.scale = Vector3(1.14, 0.88, 1.14).lerp(Vector3.ONE, p)
		remaining_flashes.append(fentry)
	_active_flashes = remaining_flashes

## Frees all transient VFX nodes and restores unit scales and hit-stop immediately.
func clear_effects() -> void:
	hit_stop_remaining = 0.0
	hit_stop_scale = 1.0
	for entry in _active_vfx:
		var node: Variant = entry.get("node", null)
		if node is Node and is_instance_valid(node):
			var n := node as Node
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	_active_vfx.clear()

	for fentry in _active_flashes:
		var vr: Variant = fentry.get("vis_root", null)
		if vr is Node3D and is_instance_valid(vr):
			(vr as Node3D).scale = Vector3.ONE
	_active_flashes.clear()
