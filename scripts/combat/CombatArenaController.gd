# scripts/combat/CombatArenaController.gd
class_name CombatArenaController
extends Node3D

const DungeonLayoutGeneratorScript := preload("res://scripts/combat/DungeonLayoutGenerator.gd")
const RoguelikeCardManagerScript := preload("res://scripts/combat/RoguelikeCardManager.gd")
const ChibiProxyFactoryScript := preload("res://scripts/combat/ChibiProxyFactory.gd")
const DungeonRoomManagerScript := preload("res://scripts/combat/DungeonRoomManager.gd")
const UnitSelectionManagerScript := preload("res://scripts/combat/UnitSelectionManager.gd")
const ProjectileManagerScript := preload("res://scripts/combat/ProjectileManager.gd")
const WaveSpawnerScript := preload("res://scripts/combat/WaveSpawner.gd")
const CombatEventManagerScript := preload("res://scripts/combat/CombatEventManager.gd")
const EXSkillSystemScript := preload("res://scripts/combat/EXSkillSystem.gd")
const TankerAIScript := preload("res://scripts/combat/ai/TankerAI.gd")
const DamageDealerAIScript := preload("res://scripts/combat/ai/DamageDealerAI.gd")
const HealerAIScript := preload("res://scripts/combat/ai/HealerAI.gd")
const BufferAIScript := preload("res://scripts/combat/ai/BufferAI.gd")
const EnemyAIScript := preload("res://scripts/combat/EnemyAI.gd")
const CombatUnitScript := preload("res://scripts/combat/CombatUnit.gd")
const EnemyUnitScript := preload("res://scripts/combat/EnemyUnit.gd")
const BossUnitScript := preload("res://scripts/combat/BossUnit.gd")
const TelegraphedAoEScript := preload("res://scripts/combat/TelegraphedAoE.gd")
const CoverPoint3DScript := preload("res://scripts/combat/CoverPoint3D.gd")
const RTSCamera3DScript := preload("res://scripts/combat/RTSCamera3D.gd")
const CombatHUDScript := preload("res://scripts/ui/CombatHUD.gd")
const SkillTargetingOverlayScript := preload("res://scripts/combat/SkillTargetingOverlay.gd")
const SelectionBoxOverlayScript := preload("res://scripts/combat/SelectionBoxOverlay.gd")
const CombatRoomDataScript := preload("res://scripts/combat/CombatRoomData.gd")

const BOSS_AOE_INTERVAL: float = 4.5
const EVENT_CHECK_INTERVAL: float = 5.0
const STRIKER_ATTACK_COOLDOWN: float = 1.2
const ENEMY_ATTACK_COOLDOWN: float = 1.6

var layout_generator: DungeonLayoutGeneratorScript
var card_manager: RoguelikeCardManagerScript
var proxy_factory: ChibiProxyFactoryScript

var room_manager: DungeonRoomManagerScript
var selection_manager: UnitSelectionManagerScript
var projectile_manager: ProjectileManagerScript
var wave_spawner: WaveSpawnerScript
var event_manager: CombatEventManagerScript
var ex_skill_system: EXSkillSystemScript

var tanker_ai: TankerAIScript
var dps_ai: DamageDealerAIScript
var healer_ai: HealerAIScript
var buffer_ai: BufferAIScript
var enemy_ai: EnemyAIScript

var camera_rig: RTSCamera3DScript = null
var combat_hud: CombatHUDScript = null
var card_draft_panel: PanelContainer = null
var targeting_overlay: SkillTargetingOverlayScript = null
var selection_box_overlay: SelectionBoxOverlayScript = null
var status_banner: Label = null
var result_panel: PanelContainer = null

var room_container: Node3D = null
var units_container: Node3D = null
var enemies_container: Node3D = null
var effects_container: Node3D = null

var squad_units: Array[CombatUnitScript] = []
var enemy_units: Array[EnemyUnitScript] = []
var cover_points: Array[CoverPoint3DScript] = []
var active_aoes: Array[TelegraphedAoEScript] = []
var special_students: Array[StudentData] = []
var current_draft_cards: Array[Dictionary] = []

var run_finished: bool = false
var room_elapsed_time: float = 0.0
var _boss_aoe_timer: float = 2.5
var _event_check_timer: float = 0.0
var _unit_cooldowns: Dictionary = {}
var _is_dragging_box: bool = false
var _drag_start_pos: Vector2 = Vector2.ZERO
var _initialized: bool = false

func _init() -> void:
	layout_generator = DungeonLayoutGeneratorScript.new()
	card_manager = RoguelikeCardManagerScript.new()
	proxy_factory = ChibiProxyFactoryScript.new()

func _ready() -> void:
	_setup_child_managers()
	_resolve_scene_nodes()
	_connect_signals()
	_ensure_combat_input_bindings()
	_setup_default_squad()
	start_run()

func _exit_tree() -> void:
	_disconnect_signals()
	if projectile_manager != null:
		projectile_manager.clear_projectiles()
	_clear_active_aoes()
	if selection_manager != null:
		selection_manager.selected_units.clear()

func _physics_process(delta: float) -> void:
	step_combat(delta)

func _unhandled_input(event: InputEvent) -> void:
	if run_finished or room_manager == null or room_manager.is_draft_open:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		match key.keycode:
			KEY_1:
				_begin_special_skill_targeting(0)
			KEY_2:
				_begin_special_skill_targeting(1)
			KEY_H:
				if selection_manager != null:
					selection_manager.issue_hold_position()
			KEY_G:
				if selection_manager != null:
					selection_manager.issue_hold_fire()
			KEY_ESCAPE:
				if targeting_overlay != null and targeting_overlay.is_targeting:
					targeting_overlay.cancel_targeting()

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if targeting_overlay != null and targeting_overlay.is_targeting:
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				var iso_cam := _get_isometric_camera()
				targeting_overlay.confirm_target(mb.position, iso_cam, 0.0)
				get_viewport().set_input_as_handled()
				return
			elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
				targeting_overlay.cancel_targeting()
				get_viewport().set_input_as_handled()
				return

		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_is_dragging_box = true
				_drag_start_pos = mb.position
				if selection_box_overlay != null:
					selection_box_overlay.set_drag_rect(true, Rect2(mb.position, Vector2.ZERO))
			else:
				if _is_dragging_box:
					_is_dragging_box = false
					if selection_box_overlay != null:
						selection_box_overlay.set_drag_rect(false, Rect2())
					_finalize_box_selection(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_handle_right_click_order(mb.position)

	elif event is InputEventMouseMotion and _is_dragging_box:
		var mm := event as InputEventMouseMotion
		if selection_box_overlay != null and selection_manager != null:
			var rect: Rect2 = selection_manager.selection_math.normalize_selection_rect(_drag_start_pos, mm.position)
			selection_box_overlay.set_drag_rect(true, rect)

## Starts or restarts a 4-room Roguelike dungeon run.
func start_run(difficulty: int = 1) -> void:
	run_finished = false
	_unit_cooldowns.clear()
	card_manager.clear_session_buffs()
	if combat_hud != null:
		combat_hud.clear_hud()
		combat_hud.set_active_buff_ids([])
	if result_panel != null:
		result_panel.visible = false
	if card_draft_panel != null:
		card_draft_panel.visible = false

	_spawn_persistent_strikers()
	var layout: Array[Dictionary] = layout_generator.generate_layout(4, difficulty)
	room_manager.start_dungeon(layout)

## Forces loading a specific room type (used by tests or debug tools).
func load_single_room_for_test(room_type: String, difficulty: int = 1) -> void:
	run_finished = false
	var single_layout: Array[Dictionary] = [
		{
			"room_index": 0,
			"room_type": room_type,
			"room_scene_path": "res://scenes/combat/rooms/room_%s.tscn" % room_type.to_lower(),
			"enemy_wave_def": {
				"room_type": room_type,
				"difficulty": difficulty,
				"enemy_count": 2 if room_type == "BOSS" else 3,
				"wave_count": 1,
			},
			"door_positions": [],
		}
	]
	room_manager.start_dungeon(single_layout)

## Deterministic combat step callable from _physics_process or headless tests.
func step_combat(delta: float) -> void:
	if delta <= 0.0 or run_finished or room_manager == null or room_manager.is_draft_open:
		return

	room_elapsed_time += delta

	# 1. Cost bar & EX skill cooldowns
	var cost_rate_mult: float = 1.0
	for buff in card_manager.get_active_buffs():
		if str(buff.get("type", "")) == "COST_RATE":
			cost_rate_mult += float(buff.get("value", 0.0))

	if ex_skill_system != null and ex_skill_system.cost_bar != null:
		ex_skill_system.cost_bar.accumulate(delta * cost_rate_mult)
		ex_skill_system.tick_cooldowns(delta)
		if combat_hud != null:
			combat_hud.update_cost(ex_skill_system.cost_bar.current_cost, ex_skill_system.cost_bar.max_cost)

	# 2. Striker units AI & player orders
	var living_enemies: Array = _get_living_enemies()
	var living_strikers: Array = _get_living_strikers()

	for striker in squad_units:
		if striker == null or not is_instance_valid(striker) or not striker.is_alive:
			continue
		_tick_striker(striker, delta, living_strikers, living_enemies)

	# 3. Enemy units & Boss AoE patterns
	for enemy in enemy_units:
		if enemy == null or not is_instance_valid(enemy) or not enemy.is_alive:
			continue
		_tick_enemy(enemy, delta, living_strikers)

		if enemy is BossUnitScript:
			_boss_aoe_timer -= delta
			if _boss_aoe_timer <= 0.0 and not living_strikers.is_empty():
				_boss_aoe_timer = BOSS_AOE_INTERVAL
				var target_striker: CombatUnitScript = living_strikers[0]
				spawn_boss_telegraphed_aoe(enemy as BossUnitScript, target_striker.position)

	# 4. Tick active telegraphed AoEs and free detonated instances
	_tick_active_aoes(delta)

	# 5. Tick projectiles
	if projectile_manager != null:
		projectile_manager.tick_projectiles(delta)

	# 6. Random combat event check every 5s after 15s elapsed
	_event_check_timer += delta
	if _event_check_timer >= EVENT_CHECK_INTERVAL:
		_event_check_timer = 0.0
		if event_manager != null and room_manager != null:
			var evt: Variant = event_manager.check_for_random_event(
				room_elapsed_time,
				room_manager.get_current_room_index() + 1,
				room_manager.is_draft_open
			)
			if evt is Dictionary:
				event_manager.trigger_event(evt)
				_resolve_random_event(evt)

	# 7. Sync HUD & check defeat
	_refresh_all_unit_labels()
	if _get_living_strikers().is_empty() and not squad_units.is_empty():
		_finish_run(false)

## Spawns a TelegraphedAoE from a BossUnit pattern and attaches red danger visuals.
func spawn_boss_telegraphed_aoe(boss: BossUnitScript, target_pos: Vector3) -> TelegraphedAoEScript:
	if boss == null or not boss.is_alive:
		return null
	var pattern: Dictionary = boss.select_boss_pattern()
	var aoe := TelegraphedAoEScript.new()
	aoe.setup(
		target_pos,
		float(pattern.get("aoe_radius", 3.5)),
		float(pattern.get("warn_duration", 1.5)),
		int(pattern.get("damage", boss.atk))
	)
	proxy_factory.attach_aoe_visuals(aoe, aoe.radius)
	if effects_container != null:
		effects_container.add_child(aoe)
	elif is_inside_tree():
		add_child(aoe)
	active_aoes.append(aoe)
	return aoe

## Selects a rolled card during draft, applies its buff, and advances to the next room.
func select_draft_card(card_index: int) -> bool:
	if card_index < 0 or card_index >= current_draft_cards.size():
		return false
	var chosen: Dictionary = current_draft_cards[card_index]
	var card_id: String = str(chosen.get("id", ""))
	if card_id.is_empty():
		return false

	card_manager.apply_buff(card_id)
	var active_ids: Array[String] = []
	for b in card_manager.get_active_buffs():
		active_ids.append(str(b.get("id", "")))
	if combat_hud != null:
		combat_hud.set_active_buff_ids(active_ids)

	if card_draft_panel != null:
		card_draft_panel.visible = false

	_persist_squad_hp()
	room_manager.advance_to_next_room()
	return true

func _setup_child_managers() -> void:
	if _initialized:
		return
	_initialized = true

	room_manager = _ensure_child(DungeonRoomManagerScript, "DungeonRoomManager") as DungeonRoomManagerScript
	selection_manager = _ensure_child(UnitSelectionManagerScript, "UnitSelectionManager") as UnitSelectionManagerScript
	projectile_manager = _ensure_child(ProjectileManagerScript, "ProjectileManager") as ProjectileManagerScript
	wave_spawner = _ensure_child(WaveSpawnerScript, "WaveSpawner") as WaveSpawnerScript
	event_manager = _ensure_child(CombatEventManagerScript, "CombatEventManager") as CombatEventManagerScript
	ex_skill_system = _ensure_child(EXSkillSystemScript, "EXSkillSystem") as EXSkillSystemScript
	tanker_ai = _ensure_child(TankerAIScript, "TankerAI") as TankerAIScript
	dps_ai = _ensure_child(DamageDealerAIScript, "DamageDealerAI") as DamageDealerAIScript
	healer_ai = _ensure_child(HealerAIScript, "HealerAI") as HealerAIScript
	buffer_ai = _ensure_child(BufferAIScript, "BufferAI") as BufferAIScript
	enemy_ai = _ensure_child(EnemyAIScript, "EnemyAI") as EnemyAIScript

func _ensure_child(script_res: GDScript, node_name: String) -> Node:
	var existing := get_node_or_null(node_name)
	if existing != null:
		return existing
	var node: Node = script_res.new()
	node.name = node_name
	add_child(node)
	return node

func _resolve_scene_nodes() -> void:
	camera_rig = get_node_or_null("CombatCameraRig") as RTSCamera3DScript
	combat_hud = get_node_or_null("CombatHUD") as CombatHUDScript
	room_container = _ensure_container("RoomContainer")
	units_container = _ensure_container("UnitsContainer")
	enemies_container = _ensure_container("EnemiesContainer")
	effects_container = _ensure_container("EffectsContainer")

	var ui_layer := get_node_or_null("CombatUIOverlay")
	if ui_layer != null:
		card_draft_panel = ui_layer.get_node_or_null("RoguelikeCardDraft") as PanelContainer
		targeting_overlay = ui_layer.get_node_or_null("SkillTargetingOverlay") as SkillTargetingOverlayScript
		selection_box_overlay = ui_layer.get_node_or_null("SelectionBoxOverlay") as SelectionBoxOverlayScript
		status_banner = ui_layer.get_node_or_null("StatusBanner") as Label
		result_panel = ui_layer.get_node_or_null("ResultPanel") as PanelContainer

func _ensure_container(container_name: String) -> Node3D:
	var node := get_node_or_null(container_name) as Node3D
	if node == null:
		node = Node3D.new()
		node.name = container_name
		add_child(node)
	return node

func _setup_default_squad() -> void:
	if not special_students.is_empty():
		return
	var sk_missile := SkillData.new()
	sk_missile.id = "ex_missile_barrage"
	sk_missile.name = "Missile Barrage (3)"
	sk_missile.cost = 3
	sk_missile.cooldown = 6.0
	sk_missile.aoe_radius = 4.5
	sk_missile.effect_type = "DAMAGE"

	var sp_hibiki := StudentData.new()
	sp_hibiki.id = "hibiki"
	sp_hibiki.student_name = "Hibiki"
	sp_hibiki.squad_slot = StudentData.SquadSlot.SPECIAL
	sp_hibiki.skills = [sk_missile]

	var sk_heal := SkillData.new()
	sk_heal.id = "ex_emergency_heal"
	sk_heal.name = "Team Heal (4)"
	sk_heal.cost = 4
	sk_heal.cooldown = 8.0
	sk_heal.aoe_radius = 6.0
	sk_heal.effect_type = "HEAL"

	var sp_serina := StudentData.new()
	sp_serina.id = "serina"
	sp_serina.student_name = "Serina"
	sp_serina.squad_slot = StudentData.SquadSlot.SPECIAL
	sp_serina.skills = [sk_heal]

	special_students = [sp_hibiki, sp_serina]
	ex_skill_system.set_special_students(special_students)
	_populate_special_skill_buttons()

func _populate_special_skill_buttons() -> void:
	if combat_hud == null:
		return
	var btn_box := combat_hud.find_child("SpecialSkillButtons", true, false) as Container
	if btn_box == null:
		return
	for child in btn_box.get_children():
		btn_box.remove_child(child)
		child.free()
	for i in range(ex_skill_system.registered_skills.size()):
		var sk := ex_skill_system.registered_skills[i]
		var btn := Button.new()
		btn.text = "[%d] %s" % [i + 1, sk.name]
		var idx: int = i
		btn.pressed.connect(func() -> void: _begin_special_skill_targeting(idx))
		btn_box.add_child(btn)

func _spawn_persistent_strikers() -> void:
	for u in squad_units:
		if u != null and is_instance_valid(u):
			if u.get_parent() != null:
				u.get_parent().remove_child(u)
			u.free()
	squad_units.clear()

	var striker_defs: Array[Dictionary] = [
		{"id": "hoshino", "name": "Hoshino", "role": StudentData.CombatRole.TANKER, "hp": 2200, "atk": 140, "def": 140, "speed": 4.2, "range": 7.5, "color": Color(0.95, 0.55, 0.72), "halo": Color(1.0, 0.65, 0.85)},
		{"id": "shiroko", "name": "Shiroko", "role": StudentData.CombatRole.DAMAGE_DEALER, "hp": 1250, "atk": 220, "def": 60, "speed": 5.5, "range": 11.5, "color": Color(0.32, 0.72, 0.96), "halo": Color(0.35, 0.88, 1.0)},
		{"id": "serika", "name": "Serika", "role": StudentData.CombatRole.DAMAGE_DEALER, "hp": 1180, "atk": 235, "def": 55, "speed": 5.5, "range": 11.0, "color": Color(0.28, 0.28, 0.36), "halo": Color(0.95, 0.35, 0.45)},
		{"id": "hanae", "name": "Hanae", "role": StudentData.CombatRole.HEALER, "hp": 1100, "atk": 130, "def": 55, "speed": 4.8, "range": 10.0, "color": Color(0.95, 0.82, 0.45), "halo": Color(0.55, 1.0, 0.65)},
	]

	var initial_hp_map: Dictionary = {}
	for def_dict in striker_defs:
		var sd := StudentData.new()
		sd.id = str(def_dict["id"])
		sd.student_name = str(def_dict["name"])
		sd.role = def_dict["role"]
		sd.squad_slot = StudentData.SquadSlot.STRIKER
		sd.base_hp = int(def_dict["hp"])
		sd.base_atk = int(def_dict["atk"])
		sd.base_def = int(def_dict["def"])
		sd.base_speed = float(def_dict["speed"])
		sd.attack_range = float(def_dict["range"])

		var unit := CombatUnitScript.new()
		unit.name = sd.student_name
		unit.setup(sd)
		proxy_factory.attach_unit_visuals(unit, sd.student_name, def_dict["color"], def_dict["halo"], 1.0)
		proxy_factory.update_unit_hp_label(unit, sd.student_name, unit.current_hp, unit.max_hp)
		units_container.add_child(unit)
		squad_units.append(unit)
		initial_hp_map[sd.id] = unit.current_hp

	room_manager.set_squad_hp(initial_hp_map)

func _on_room_loaded(room_index: int, room_data: Dictionary) -> void:
	_clear_enemies()
	_clear_active_aoes()
	cover_points.clear()
	if projectile_manager != null:
		projectile_manager.clear_projectiles()
	if selection_manager != null:
		selection_manager.deselect_all()

	room_elapsed_time = 0.0
	_boss_aoe_timer = 2.5
	_event_check_timer = 0.0

	var scene_path: String = str(room_data.get("room_scene_path", "res://scenes/combat/rooms/room_combat.tscn"))
	var room_packed := load(scene_path) as PackedScene
	if room_packed == null:
		return
	var room_inst := room_packed.instantiate()
	room_container.add_child(room_inst)
	room_manager.current_room_node = room_inst

	var room_info := room_inst as CombatRoomDataScript
	var player_spawns: Array[Vector3] = room_info.get_player_spawn_positions() if room_info != null else []
	var persisted_hp: Dictionary = room_manager.get_squad_persistent_state()

	for i in range(squad_units.size()):
		var unit: CombatUnitScript = squad_units[i]
		if unit == null or not is_instance_valid(unit):
			continue
		if unit.unit_data != null and persisted_hp.has(unit.unit_data.id):
			unit.current_hp = clampi(int(persisted_hp[unit.unit_data.id]), 0, unit.max_hp)
			unit.is_alive = unit.current_hp > 0
		unit.visible = unit.is_alive
		unit.has_player_order = false
		unit.current_order_type = ""
		unit.order_target_node = null
		if i < player_spawns.size():
			unit.position = player_spawns[i]
		else:
			unit.position = Vector3(-4.5 + float(i) * 3.0, 0.0, 7.5)
		proxy_factory.set_unit_selected(unit, false)
		proxy_factory.update_unit_hp_label(unit, unit.name, unit.current_hp, unit.max_hp)
		if combat_hud != null and unit.unit_data != null:
			combat_hud.update_striker_hp(unit.unit_data.id, unit.current_hp, unit.max_hp)

	if room_info != null:
		cover_points = room_info.get_cover_points()

	var room_type: String = str(room_data.get("room_type", "COMBAT"))
	_update_status_banner("Room %d / %d - %s" % [room_index + 1, room_manager.layout.size(), room_type])

	if room_type == "REST":
		for unit in squad_units:
			if unit != null and unit.is_alive:
				unit.heal(int(round(float(unit.max_hp) * 0.35)))
				if combat_hud != null and unit.unit_data != null:
					combat_hud.update_striker_hp(unit.unit_data.id, unit.current_hp, unit.max_hp)
		if combat_hud != null:
			combat_hud.update_wave(room_index + 1)
		room_manager.mark_current_room_cleared()
		_open_card_draft()
		return

	var wave_def: Dictionary = room_data.get("enemy_wave_def", {})
	var enemy_count: int = int(wave_def.get("enemy_count", 3))
	var difficulty: int = int(wave_def.get("difficulty", 1))
	var enemy_spawns: Array[Vector3] = room_info.get_enemy_spawn_positions() if room_info != null else []

	if room_type == "BOSS":
		var boss := BossUnitScript.new()
		boss.name = "Hieronymus_Proxy"
		boss.max_hp = 5000 + difficulty * 1500
		boss.current_hp = boss.max_hp
		boss.atk = 155 + difficulty * 25
		boss.def = 80
		boss.speed = 3.0
		boss.attack_range = 13.0
		boss.position = room_info.get_boss_spawn_position() if room_info != null else Vector3(0.0, 0.0, -9.5)
		proxy_factory.attach_unit_visuals(boss, "BOSS", Color(0.75, 0.15, 0.2), Color(1.0, 0.2, 0.2), 1.65)
		proxy_factory.update_unit_hp_label(boss, "BOSS", boss.current_hp, boss.max_hp)
		boss.unit_died.connect(_on_enemy_died)
		boss.phase_changed.connect(func(new_phase: int) -> void:
			_update_status_banner("BOSS PHASE %d! Watch the red AoE zones!" % new_phase)
		)
		enemies_container.add_child(boss)
		enemy_units.append(boss)

	var grunt_count: int = enemy_count if room_type != "BOSS" else mini(2, maxi(0, enemy_count - 1))
	for j in range(grunt_count):
		var grunt := EnemyUnitScript.new()
		grunt.name = "Automaton_%d" % (j + 1)
		grunt.enemy_type = "ELITE" if room_type == "ELITE" else "GRUNT"
		grunt.max_hp = (900 if room_type == "ELITE" else 550) + difficulty * 120
		grunt.current_hp = grunt.max_hp
		grunt.atk = (115 if room_type == "ELITE" else 85) + difficulty * 15
		grunt.def = 40
		grunt.speed = 3.8
		grunt.attack_range = 10.5
		grunt.behavior = "DEFENSIVE" if (j % 2 == 1) else "AGGRESSIVE"
		if j < enemy_spawns.size():
			grunt.position = enemy_spawns[j]
		else:
			grunt.position = Vector3(-4.0 + float(j) * 3.0, 0.0, -7.5)
		var scale_f: float = 1.2 if room_type == "ELITE" else 0.95
		var col: Color = Color(0.6, 0.25, 0.85) if room_type == "ELITE" else Color(0.45, 0.45, 0.52)
		proxy_factory.attach_unit_visuals(grunt, grunt.name, col, Color(1.0, 0.4, 0.3), scale_f)
		proxy_factory.update_unit_hp_label(grunt, grunt.name, grunt.current_hp, grunt.max_hp)
		grunt.unit_died.connect(_on_enemy_died)
		enemies_container.add_child(grunt)
		enemy_units.append(grunt)

	wave_spawner.start_wave(room_index + 1, enemy_units.size())
	if combat_hud != null:
		combat_hud.update_wave(room_index + 1)

func _on_enemy_died(unit: CombatUnitScript) -> void:
	if unit != null and is_instance_valid(unit):
		unit.visible = false
	for buff in card_manager.get_active_buffs():
		if str(buff.get("type", "")) == "HEAL_ON_KILL":
			var ratio: float = float(buff.get("value", 0.05))
			for s in squad_units:
				if s != null and s.is_alive:
					s.heal(int(round(float(s.max_hp) * ratio)))
	if wave_spawner != null:
		wave_spawner.register_enemy_killed()

func _on_wave_cleared(_wave_index: int) -> void:
	if run_finished or room_manager == null or room_manager.is_draft_open:
		return
	room_manager.mark_current_room_cleared()
	_open_card_draft()

func _on_dungeon_completed() -> void:
	_finish_run(true)

func _open_card_draft() -> void:
	current_draft_cards = card_manager.roll_cards(3)
	if card_draft_panel == null:
		return
	for i in range(3):
		var btn := card_draft_panel.find_child("CardOption%d" % (i + 1), true, false) as Button
		if btn != null:
			if i < current_draft_cards.size():
				var card: Dictionary = current_draft_cards[i]
				btn.text = "%s\n(%s)" % [str(card.get("name", "Card")), str(card.get("effect", ""))]
				btn.visible = true
			else:
				btn.visible = false
	card_draft_panel.visible = true

func _finish_run(victory: bool) -> void:
	run_finished = true
	if room_manager != null:
		room_manager.is_draft_open = false
	if card_draft_panel != null:
		card_draft_panel.visible = false
	var msg: String = "DUNGEON CLEARED! Victory!" if victory else "SQUAD DEFEATED!"
	_update_status_banner(msg)
	if result_panel != null:
		var lbl := result_panel.find_child("ResultLabel", true, false) as Label
		if lbl != null:
			lbl.text = msg
		result_panel.visible = true

func _tick_striker(striker: CombatUnitScript, delta: float, allies: Array, enemies: Array) -> void:
	var uid: int = striker.get_instance_id()
	var cd: float = maxf(0.0, float(_unit_cooldowns.get(uid, 0.0)) - delta)
	_unit_cooldowns[uid] = cd

	if striker.has_player_order:
		if not striker.check_emergency_override():
			_execute_player_order(striker, delta, cd)
			return

	var role: StudentData.CombatRole = striker.unit_data.role if striker.unit_data != null else StudentData.CombatRole.DAMAGE_DEALER
	var decision: Dictionary
	match role:
		StudentData.CombatRole.TANKER:
			decision = tanker_ai.evaluate_action(striker, allies, enemies, cover_points)
		StudentData.CombatRole.HEALER:
			decision = healer_ai.evaluate_action(striker, allies, enemies, cover_points)
		StudentData.CombatRole.BUFFER:
			decision = buffer_ai.evaluate_action(striker, allies, enemies, cover_points)
		_:
			decision = dps_ai.evaluate_action(striker, allies, enemies, cover_points)

	var action: String = str(decision.get("action", "IDLE"))
	var target: Variant = decision.get("target", null)

	if action == "HEAL_ALLY" and target is CombatUnitScript:
		var ally := target as CombatUnitScript
		var dist: float = striker.position.distance_to(ally.position)
		if dist > striker.attack_range:
			_move_unit_toward(striker, ally.position, delta)
		elif cd <= 0.0 and ally.current_hp < ally.max_hp:
			ally.heal(striker.atk * 2)
			_unit_cooldowns[uid] = STRIKER_ATTACK_COOLDOWN
	elif action == "TAKE_COVER_AND_TAUNT" and target is CoverPoint3DScript:
		var cp := target as CoverPoint3DScript
		if striker.position.distance_to(cp.position) > 0.6:
			_move_unit_toward(striker, cp.position, delta)
		else:
			cp.claim(striker)
			if cd <= 0.0 and not enemies.is_empty():
				var nearest_e := enemies[0] as CombatUnitScript
				projectile_manager.spawn_projectile(striker.position + Vector3(0, 0.7, 0), nearest_e.position + Vector3(0, 0.7, 0), 22.0, striker.atk, striker, nearest_e)
				_unit_cooldowns[uid] = STRIKER_ATTACK_COOLDOWN
	elif (action == "ATTACK_TARGET" or action == "TAUNT_ENGAGE") and target is CombatUnitScript:
		var enemy := target as CombatUnitScript
		var dist: float = striker.position.distance_to(enemy.position)
		if dist > striker.attack_range:
			_move_unit_toward(striker, enemy.position, delta)
		elif cd <= 0.0:
			var dmg: int = striker.damage_resolver.calculate_damage(striker, enemy, card_manager.get_active_buffs())
			projectile_manager.spawn_projectile(striker.position + Vector3(0, 0.7, 0), enemy.position + Vector3(0, 0.7, 0), 24.0, dmg, striker, enemy)
			_unit_cooldowns[uid] = STRIKER_ATTACK_COOLDOWN
	elif action == "POSITION_AND_BUFF" and target is Vector3:
		_move_unit_toward(striker, target as Vector3, delta)

func _execute_player_order(striker: CombatUnitScript, delta: float, cd: float) -> void:
	var uid: int = striker.get_instance_id()
	match striker.current_order_type:
		"MOVE":
			if striker.position.distance_to(striker.order_target_position) <= 0.4:
				striker.clear_player_order()
			else:
				_move_unit_toward(striker, striker.order_target_position, delta)
		"COVER":
			if striker.position.distance_to(striker.order_target_position) <= 0.5:
				if striker.order_target_node is CoverPoint3DScript:
					(striker.order_target_node as CoverPoint3DScript).claim(striker)
				striker.clear_player_order()
			else:
				_move_unit_toward(striker, striker.order_target_position, delta)
		"FOCUS_FIRE":
			var target_enemy := striker.order_target_node as CombatUnitScript
			if target_enemy == null or not is_instance_valid(target_enemy) or not target_enemy.is_alive:
				striker.clear_player_order()
				return
			var dist: float = striker.position.distance_to(target_enemy.position)
			if dist > striker.attack_range:
				_move_unit_toward(striker, target_enemy.position, delta)
			elif cd <= 0.0:
				var dmg: int = striker.damage_resolver.calculate_damage(striker, target_enemy, card_manager.get_active_buffs())
				projectile_manager.spawn_projectile(striker.position + Vector3(0, 0.7, 0), target_enemy.position + Vector3(0, 0.7, 0), 24.0, dmg, striker, target_enemy)
				_unit_cooldowns[uid] = STRIKER_ATTACK_COOLDOWN
		"HOLD_POSITION":
			pass
		"HOLD_FIRE":
			pass

func _tick_enemy(enemy: EnemyUnitScript, delta: float, allies: Array) -> void:
	var uid: int = enemy.get_instance_id()
	var cd: float = maxf(0.0, float(_unit_cooldowns.get(uid, 0.0)) - delta)
	_unit_cooldowns[uid] = cd

	var decision: Dictionary = enemy_ai.evaluate(enemy, allies)
	var action: String = str(decision.get("action", "IDLE"))
	var target: Variant = decision.get("target", null)
	if not (target is CombatUnitScript) or action == "IDLE":
		return

	var ally := target as CombatUnitScript
	var dist: float = enemy.position.distance_to(ally.position)
	if action == "RUSH" and dist > enemy.attack_range:
		_move_unit_toward(enemy, ally.position, delta)
	elif dist <= enemy.attack_range and cd <= 0.0:
		var dmg: int = enemy.damage_resolver.calculate_damage(enemy, ally, [])
		projectile_manager.spawn_projectile(enemy.position + Vector3(0, 0.7, 0), ally.position + Vector3(0, 0.7, 0), 18.0, dmg, enemy, ally)
		_unit_cooldowns[uid] = ENEMY_ATTACK_COOLDOWN

func _move_unit_toward(unit: CombatUnitScript, target_pos: Vector3, delta: float) -> void:
	var flat_target := Vector3(target_pos.x, unit.position.y, target_pos.z)
	var to_target: Vector3 = flat_target - unit.position
	var dist: float = to_target.length()
	if dist <= 0.15 or delta <= 0.0:
		return
	var step: float = minf(dist, unit.speed * delta)
	unit.position += (to_target / dist) * step

func _tick_active_aoes(delta: float) -> void:
	var remaining: Array[TelegraphedAoEScript] = []
	var living_strikers: Array = _get_living_strikers()
	for aoe in active_aoes:
		if aoe == null or not is_instance_valid(aoe):
			continue
		aoe.tick(delta, living_strikers)
		if aoe.has_detonated:
			if aoe.get_parent() != null:
				aoe.get_parent().remove_child(aoe)
			aoe.free()
		else:
			proxy_factory.update_aoe_progress(aoe, aoe.get_warning_progress())
			remaining.append(aoe)
	active_aoes = remaining

func _resolve_random_event(evt: Dictionary) -> void:
	var etype: String = str(evt.get("type", ""))
	_update_status_banner("RANDOM EVENT: %s!" % etype)
	if etype == "ALLY_ARTILLERY":
		for enemy in _get_living_enemies():
			(enemy as CombatUnitScript).take_damage(250, self)
	elif etype == "THIRD_PARTY":
		for unit in _get_living_strikers():
			(unit as CombatUnitScript).heal(120)

func _begin_special_skill_targeting(skill_index: int) -> void:
	if ex_skill_system == null or targeting_overlay == null:
		return
	if skill_index < 0 or skill_index >= ex_skill_system.registered_skills.size():
		return
	var sk := ex_skill_system.registered_skills[skill_index]
	if ex_skill_system.cost_bar.current_cost >= float(sk.cost) and not ex_skill_system.is_skill_on_cooldown(sk):
		targeting_overlay.begin_targeting(sk)
		_update_status_banner("Targeting EX Skill: %s (Left-Click ground)" % sk.name)

func _on_ex_target_confirmed(skill: SkillData, world_pos: Vector3) -> void:
	if skill == null or ex_skill_system == null:
		return
	ex_skill_system.activate_skill(skill, world_pos)

func _on_ex_skill_activated(skill: SkillData, target_pos: Vector3) -> void:
	if skill == null:
		return
	var center_xz := Vector2(target_pos.x, target_pos.z)
	if skill.effect_type == "HEAL":
		for unit in _get_living_strikers():
			var s := unit as CombatUnitScript
			if Vector2(s.position.x, s.position.z).distance_to(center_xz) <= skill.aoe_radius:
				s.heal(450)
		_update_status_banner("EX Skill Cast: %s (Healed allies!)" % skill.name)
	else:
		for unit in _get_living_enemies():
			var e := unit as CombatUnitScript
			if Vector2(e.position.x, e.position.z).distance_to(center_xz) <= skill.aoe_radius:
				e.take_damage(650, self)
		_update_status_banner("EX Skill Cast: %s!" % skill.name)

func _finalize_box_selection(end_pos: Vector2) -> void:
	if selection_manager == null:
		return
	var iso_cam := _get_isometric_camera()
	var drag_dist: float = _drag_start_pos.distance_to(end_pos)
	if drag_dist < 8.0 and iso_cam != null and is_inside_tree():
		var world_pt: Vector3 = _project_to_ground(end_pos, iso_cam)
		var closest: CombatUnitScript = null
		var best_d: float = 1.6
		for s in _get_living_strikers():
			var d: float = Vector2(s.position.x, s.position.z).distance_to(Vector2(world_pt.x, world_pt.z))
			if d < best_d:
				best_d = d
				closest = s
		selection_manager.deselect_all()
		if closest != null:
			selection_manager.select_unit(closest, false)
	else:
		selection_manager.box_select(Rect2(_drag_start_pos, end_pos - _drag_start_pos), iso_cam, _get_living_strikers())

	for s in squad_units:
		if s != null and is_instance_valid(s):
			proxy_factory.set_unit_selected(s, selection_manager.selected_units.has(s))

func _handle_right_click_order(screen_pos: Vector2) -> void:
	var iso_cam := _get_isometric_camera()
	if iso_cam == null or selection_manager == null or selection_manager.selected_units.is_empty():
		return
	var world_pt: Vector3 = _project_to_ground(screen_pos, iso_cam)
	var click_xz := Vector2(world_pt.x, world_pt.z)

	for enemy in _get_living_enemies():
		var e := enemy as CombatUnitScript
		if Vector2(e.position.x, e.position.z).distance_to(click_xz) <= 1.6:
			selection_manager.issue_focus_fire(e)
			return

	for cp in cover_points:
		if cp != null and is_instance_valid(cp) and Vector2(cp.position.x, cp.position.z).distance_to(click_xz) <= 1.5:
			selection_manager.issue_cover_order(cp)
			return

	selection_manager.issue_move_order(world_pt)

func _project_to_ground(screen_pos: Vector2, cam: Camera3D, ground_y: float = 0.0) -> Vector3:
	if cam == null or not is_instance_valid(cam) or not cam.is_inside_tree():
		return Vector3.ZERO
	var origin: Vector3 = cam.project_ray_origin(screen_pos)
	var dir: Vector3 = cam.project_ray_normal(screen_pos)
	if absf(dir.y) > 0.0001:
		var t: float = (ground_y - origin.y) / dir.y
		if t >= 0.0:
			return origin + dir * t
	return Vector3.ZERO

func _get_isometric_camera() -> Camera3D:
	if camera_rig != null:
		return camera_rig.isometric_camera
	return null

func _get_living_strikers() -> Array:
	var out: Array = []
	for s in squad_units:
		if s != null and is_instance_valid(s) and s.is_alive:
			out.append(s)
	return out

func _get_living_enemies() -> Array:
	var out: Array = []
	for e in enemy_units:
		if e != null and is_instance_valid(e) and e.is_alive:
			out.append(e)
	return out

func _persist_squad_hp() -> void:
	var hp_map: Dictionary = {}
	for s in squad_units:
		if s != null and is_instance_valid(s) and s.unit_data != null:
			hp_map[s.unit_data.id] = s.current_hp
	room_manager.set_squad_hp(hp_map)

func _refresh_all_unit_labels() -> void:
	for s in squad_units:
		if s != null and is_instance_valid(s):
			proxy_factory.update_unit_hp_label(s, s.name, s.current_hp, s.max_hp)
			if combat_hud != null and s.unit_data != null:
				combat_hud.update_striker_hp(s.unit_data.id, s.current_hp, s.max_hp)
	for e in enemy_units:
		if e != null and is_instance_valid(e):
			proxy_factory.update_unit_hp_label(e, "BOSS" if e is BossUnitScript else e.name, e.current_hp, e.max_hp)

func _clear_enemies() -> void:
	for e in enemy_units:
		if e != null and is_instance_valid(e):
			if e.get_parent() != null:
				e.get_parent().remove_child(e)
			e.free()
	enemy_units.clear()

func _clear_active_aoes() -> void:
	for aoe in active_aoes:
		if aoe != null and is_instance_valid(aoe):
			if aoe.get_parent() != null:
				aoe.get_parent().remove_child(aoe)
			aoe.free()
	active_aoes.clear()

func _update_status_banner(text: String) -> void:
	if status_banner != null:
		status_banner.text = text

func _ensure_combat_input_bindings() -> void:
	var bindings := {
		&"move_forward": KEY_W,
		&"move_back": KEY_S,
		&"move_left": KEY_A,
		&"move_right": KEY_D,
		&"cam_rotate_left": KEY_Q,
		&"cam_rotate_right": KEY_E,
	}
	for action: StringName in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = bindings[action]
			InputMap.action_add_event(action, ev)

func _on_restart_pressed() -> void:
	start_run()

func _on_return_hub_pressed() -> void:
	var ztm := get_node_or_null("/root/ZoneTransitionManager")
	if ztm != null and ztm.has_method(&"transition_to"):
		ztm.transition_to("res://scenes/hub/zones/schale_building.tscn", "default")

func _connect_signals() -> void:
	if room_manager != null:
		if not room_manager.room_loaded.is_connected(_on_room_loaded):
			room_manager.room_loaded.connect(_on_room_loaded)
		if not room_manager.dungeon_completed.is_connected(_on_dungeon_completed):
			room_manager.dungeon_completed.connect(_on_dungeon_completed)
	if wave_spawner != null and not wave_spawner.wave_cleared.is_connected(_on_wave_cleared):
		wave_spawner.wave_cleared.connect(_on_wave_cleared)
	if targeting_overlay != null and not targeting_overlay.target_confirmed.is_connected(_on_ex_target_confirmed):
		targeting_overlay.target_confirmed.connect(_on_ex_target_confirmed)
	if ex_skill_system != null and not ex_skill_system.skill_activated.is_connected(_on_ex_skill_activated):
		ex_skill_system.skill_activated.connect(_on_ex_skill_activated)

	if card_draft_panel != null:
		for i in range(3):
			var btn := card_draft_panel.find_child("CardOption%d" % (i + 1), true, false) as Button
			if btn != null:
				var idx: int = i
				var cb := func() -> void: select_draft_card(idx)
				btn.set_meta(&"_draft_cb", cb)
				btn.pressed.connect(cb)

	if result_panel != null:
		var restart_btn := result_panel.find_child("RestartButton", true, false) as Button
		if restart_btn != null and not restart_btn.pressed.is_connected(_on_restart_pressed):
			restart_btn.pressed.connect(_on_restart_pressed)
		var hub_btn := result_panel.find_child("ReturnHubButton", true, false) as Button
		if hub_btn != null and not hub_btn.pressed.is_connected(_on_return_hub_pressed):
			hub_btn.pressed.connect(_on_return_hub_pressed)

func _disconnect_signals() -> void:
	if room_manager != null and is_instance_valid(room_manager):
		if room_manager.room_loaded.is_connected(_on_room_loaded):
			room_manager.room_loaded.disconnect(_on_room_loaded)
		if room_manager.dungeon_completed.is_connected(_on_dungeon_completed):
			room_manager.dungeon_completed.disconnect(_on_dungeon_completed)
	if wave_spawner != null and is_instance_valid(wave_spawner) and wave_spawner.wave_cleared.is_connected(_on_wave_cleared):
		wave_spawner.wave_cleared.disconnect(_on_wave_cleared)
	if targeting_overlay != null and is_instance_valid(targeting_overlay) and targeting_overlay.target_confirmed.is_connected(_on_ex_target_confirmed):
		targeting_overlay.target_confirmed.disconnect(_on_ex_target_confirmed)
	if ex_skill_system != null and is_instance_valid(ex_skill_system) and ex_skill_system.skill_activated.is_connected(_on_ex_skill_activated):
		ex_skill_system.skill_activated.disconnect(_on_ex_skill_activated)

	if card_draft_panel != null and is_instance_valid(card_draft_panel):
		for i in range(3):
			var btn := card_draft_panel.find_child("CardOption%d" % (i + 1), true, false) as Button
			if btn != null and btn.has_meta(&"_draft_cb"):
				var cb: Callable = btn.get_meta(&"_draft_cb")
				if btn.pressed.is_connected(cb):
					btn.pressed.disconnect(cb)

	if result_panel != null and is_instance_valid(result_panel):
		var restart_btn := result_panel.find_child("RestartButton", true, false) as Button
		if restart_btn != null and restart_btn.pressed.is_connected(_on_restart_pressed):
			restart_btn.pressed.disconnect(_on_restart_pressed)
		var hub_btn := result_panel.find_child("ReturnHubButton", true, false) as Button
		if hub_btn != null and hub_btn.pressed.is_connected(_on_return_hub_pressed):
			hub_btn.pressed.disconnect(_on_return_hub_pressed)
