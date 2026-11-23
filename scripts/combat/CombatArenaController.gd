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
const CombatHealthBarOverlayScript := preload("res://scripts/combat/CombatHealthBarOverlay.gd")
const CommanderDirectiveSystemScript := preload("res://scripts/combat/CommanderDirectiveSystem.gd")
const UtilityAIManagerScript := preload("res://scripts/combat/ai/UtilityAIManager.gd")

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
var commander_system: CommanderDirectiveSystemScript
var utility_ai: UtilityAIManagerScript

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
var health_bar_overlay: CombatHealthBarOverlayScript = null
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

var current_room_info: CombatRoomDataScript = null
var skill_preview_disc: Node3D = null
var skill_range_ring: Node3D = null
var tactical_zone_disc: Node3D = null
var active_zone_discs: Dictionary = {}
var order_beacon: Node3D = null

var run_finished: bool = false
var room_elapsed_time: float = 0.0
var _boss_aoe_timer: float = 2.5
var _event_check_timer: float = 0.0
var _unit_cooldowns: Dictionary = {}
var _unit_flank_memory: Dictionary = {}
var _is_dragging_box: bool = false
var _drag_start_pos: Vector2 = Vector2.ZERO
var _initialized: bool = false

func _init() -> void:
	layout_generator = DungeonLayoutGeneratorScript.new()
	card_manager = RoguelikeCardManagerScript.new()
	proxy_factory = ChibiProxyFactoryScript.new()
	utility_ai = UtilityAIManagerScript.new()

func _ready() -> void:
	_setup_child_managers()
	_resolve_scene_nodes()
	if camera_rig != null:
		camera_rig.max_zoom = 38.0
		camera_rig.bounds_min = Vector2(-55.0, -55.0)
		camera_rig.bounds_max = Vector2(55.0, 55.0)
		camera_rig.adjust_zoom(6.0)
	if effects_container != null:
		skill_preview_disc = proxy_factory.create_skill_preview_disc()
		effects_container.add_child(skill_preview_disc)
		skill_range_ring = proxy_factory.create_skill_range_ring()
		effects_container.add_child(skill_range_ring)
		tactical_zone_disc = proxy_factory.create_tactical_zone_disc()
		effects_container.add_child(tactical_zone_disc)
		order_beacon = proxy_factory.create_order_beacon()
		effects_container.add_child(order_beacon)
	_connect_signals()
	_ensure_combat_input_bindings()
	_setup_default_squad()
	start_run()

func _exit_tree() -> void:
	_disconnect_signals()
	if projectile_manager != null:
		projectile_manager.clear_projectiles()
	_clear_active_aoes()
	_clear_active_zone_discs()
	_unit_flank_memory.clear()
	if selection_manager != null:
		selection_manager.selected_units.clear()

func _physics_process(delta: float) -> void:
	var scale_mult: float = commander_system.get_effective_time_scale() if commander_system != null else 1.0
	step_combat(delta * scale_mult)

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
			KEY_3:
				_begin_special_skill_targeting(2)
			KEY_4:
				_begin_special_skill_targeting(3)
			KEY_F1:
				_select_striker_slot(0, Input.is_key_pressed(KEY_SHIFT))
			KEY_F2:
				_select_striker_slot(1, Input.is_key_pressed(KEY_SHIFT))
			KEY_F3:
				_select_striker_slot(2, Input.is_key_pressed(KEY_SHIFT))
			KEY_F4:
				_select_striker_slot(3, Input.is_key_pressed(KEY_SHIFT))
			KEY_QUOTELEFT:
				_select_all_living_strikers()
			KEY_Z:
				if commander_system != null:
					commander_system.select_tool(CommanderDirectiveSystemScript.ToolMode.ASSAULT_ZONE)
			KEY_V:
				if commander_system != null:
					commander_system.select_tool(CommanderDirectiveSystemScript.ToolMode.DEFENSE_ZONE)
			KEY_B:
				if commander_system != null:
					commander_system.select_tool(CommanderDirectiveSystemScript.ToolMode.FREESHOT_ZONE)
			KEY_X:
				if commander_system != null:
					commander_system.cancel_tool()
			KEY_H:
				_toggle_hold_fire_for_selection()
			KEY_TAB:
				if commander_system != null:
					commander_system.toggle_tactical_slow_mo()
			KEY_G:
				_clear_directives_for_selection()
			KEY_C, KEY_HOME:
				_recenter_camera_on_squad()
			KEY_ESCAPE:
				if targeting_overlay != null and targeting_overlay.is_targeting:
					targeting_overlay.cancel_targeting()
				elif commander_system != null:
					commander_system.cancel_tool()

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if targeting_overlay != null and targeting_overlay.is_targeting:
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				targeting_overlay.set_caster_origin(_get_skill_caster_origin())
				var iso_cam := _get_isometric_camera()
				targeting_overlay.confirm_target(mb.position, iso_cam, 0.0)
				get_viewport().set_input_as_handled()
				return
			elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
				targeting_overlay.cancel_targeting()
				get_viewport().set_input_as_handled()
				return

		var armed_tool: int = commander_system.active_tool if commander_system != null else CommanderDirectiveSystemScript.ToolMode.NONE
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and Input.is_key_pressed(KEY_SPACE):
				return
			if mb.pressed:
				_is_dragging_box = true
				_drag_start_pos = mb.position
				if armed_tool == CommanderDirectiveSystemScript.ToolMode.NONE and selection_box_overlay != null:
					selection_box_overlay.set_drag_rect(true, Rect2(mb.position, Vector2.ZERO))
			else:
				if _is_dragging_box:
					_is_dragging_box = false
					if selection_box_overlay != null:
						selection_box_overlay.set_drag_rect(false, Rect2())
					if armed_tool != CommanderDirectiveSystemScript.ToolMode.NONE:
						_finalize_commander_zone_drag(mb.position)
					else:
						_finalize_box_selection(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if armed_tool != CommanderDirectiveSystemScript.ToolMode.NONE and commander_system != null:
				commander_system.cancel_tool()
			else:
				_handle_commander_right_click(mb.position)

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if targeting_overlay != null and targeting_overlay.is_targeting:
			var caster_origin: Vector3 = _get_skill_caster_origin()
			targeting_overlay.set_caster_origin(caster_origin)
			var wpos: Vector3 = targeting_overlay.update_preview(mm.position, _get_isometric_camera(), 0.0)
			var sk: SkillData = targeting_overlay.active_skill
			if sk != null and sk.requires_los and not sk.pierce_walls and current_room_info != null:
				var los_res: Dictionary = current_room_info.check_line_of_sight(caster_origin + Vector3(0.0, 0.7, 0.0), wpos + Vector3(0.0, 0.7, 0.0), sk.penetration_power)
				targeting_overlay.is_los_blocked_flag = not bool(los_res.get("clear", true))
			else:
				targeting_overlay.is_los_blocked_flag = false
			var sk_rad: float = sk.aoe_radius if sk != null else 4.0
			var sk_range: float = sk.cast_range if sk != null else 0.0
			var valid_preview: bool = targeting_overlay.is_target_in_range_flag and not (targeting_overlay.is_los_blocked_flag and sk != null and not sk.pierce_walls)
			proxy_factory.update_skill_preview_disc(skill_preview_disc, wpos, sk_rad, true, valid_preview)
			proxy_factory.update_skill_range_ring(skill_range_ring, caster_origin, sk_range, sk_range > 0.0)
		elif _is_dragging_box:
			var armed_tool: int = commander_system.active_tool if commander_system != null else CommanderDirectiveSystemScript.ToolMode.NONE
			if armed_tool == CommanderDirectiveSystemScript.ToolMode.NONE and selection_box_overlay != null:
				selection_box_overlay.set_drag_rect(true, Rect2(_drag_start_pos, mm.position - _drag_start_pos).abs())

## Starts or restarts a 4-room Roguelike dungeon run.
func start_run(difficulty: int = 1) -> void:
	run_finished = false
	_unit_cooldowns.clear()
	card_manager.clear_session_buffs()
	if combat_hud != null:
		combat_hud.clear_hud()
		combat_hud.set_active_buff_ids([])
	if health_bar_overlay != null:
		health_bar_overlay.clear_all()
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

	# 7. Sync HUD, tactical 2D overlay & check defeat
	if health_bar_overlay != null:
		health_bar_overlay.tick_floating_numbers(delta, _get_isometric_camera())
	_refresh_all_unit_labels()
	_update_tactical_2d_overlay()
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
	commander_system = _ensure_child(CommanderDirectiveSystemScript, "CommanderDirectiveSystem") as CommanderDirectiveSystemScript
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
		health_bar_overlay = ui_layer.get_node_or_null("CombatHealthBarOverlay") as CombatHealthBarOverlayScript
		if health_bar_overlay == null:
			health_bar_overlay = CombatHealthBarOverlayScript.new()
			health_bar_overlay.name = "CombatHealthBarOverlay"
			health_bar_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			health_bar_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			ui_layer.add_child(health_bar_overlay)
			ui_layer.move_child(health_bar_overlay, 0)
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
	sk_missile.cast_range = 24.0
	sk_missile.min_range = 2.0
	sk_missile.aoe_shape = "CIRCLE"
	sk_missile.requires_los = false
	sk_missile.pierce_walls = true
	sk_missile.penetration_power = 2
	sk_missile.wall_damage = 380
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
	sk_heal.cast_range = 18.0
	sk_heal.min_range = 0.0
	sk_heal.aoe_shape = "CIRCLE"
	sk_heal.requires_los = false
	sk_heal.effect_type = "HEAL"

	var sp_serina := StudentData.new()
	sp_serina.id = "serina"
	sp_serina.student_name = "Serina"
	sp_serina.squad_slot = StudentData.SquadSlot.SPECIAL
	sp_serina.skills = [sk_heal]

	var sk_shotgun_breach := SkillData.new()
	sk_shotgun_breach.id = "ex_shotgun_breach"
	sk_shotgun_breach.name = "Shotgun Breach (2)"
	sk_shotgun_breach.cost = 2
	sk_shotgun_breach.cooldown = 5.0
	sk_shotgun_breach.aoe_radius = 11.0
	sk_shotgun_breach.cast_range = 11.0
	sk_shotgun_breach.min_range = 0.0
	sk_shotgun_breach.aoe_shape = "CONE"
	sk_shotgun_breach.cone_angle_deg = 55.0
	sk_shotgun_breach.requires_los = false
	sk_shotgun_breach.pierce_walls = true
	sk_shotgun_breach.penetration_power = 2
	sk_shotgun_breach.wall_damage = 900
	sk_shotgun_breach.effect_type = "DAMAGE"

	var sk_railgun_beam := SkillData.new()
	sk_railgun_beam.id = "ex_railgun_beam"
	sk_railgun_beam.name = "Railgun Beam (3)"
	sk_railgun_beam.cost = 3
	sk_railgun_beam.cooldown = 7.0
	sk_railgun_beam.aoe_radius = 28.0
	sk_railgun_beam.cast_range = 28.0
	sk_railgun_beam.min_range = 0.0
	sk_railgun_beam.aoe_shape = "LINE"
	sk_railgun_beam.line_width = 2.4
	sk_railgun_beam.requires_los = false
	sk_railgun_beam.pierce_walls = true
	sk_railgun_beam.penetration_power = 3
	sk_railgun_beam.wall_damage = 1200
	sk_railgun_beam.effect_type = "DAMAGE"

	special_students = [sp_hibiki, sp_serina]
	ex_skill_system.set_special_students(special_students)
	ex_skill_system.register_skill(sk_shotgun_breach)
	ex_skill_system.register_skill(sk_railgun_beam)
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
		btn.focus_mode = Control.FOCUS_NONE
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
		unit.order_completed.connect(_on_striker_order_completed)
		proxy_factory.attach_unit_visuals(unit, sd.student_name, def_dict["color"], def_dict["halo"], 1.0, sd.attack_range)
		proxy_factory.update_unit_hp_label(unit, sd.student_name, unit.current_hp, unit.max_hp, false)
		_bind_unit_hp_feedback(unit)
		units_container.add_child(unit)
		squad_units.append(unit)
		initial_hp_map[sd.id] = unit.current_hp

	room_manager.set_squad_hp(initial_hp_map)

func _on_room_loaded(room_index: int, room_data: Dictionary) -> void:
	_clear_enemies()
	_clear_active_aoes()
	_clear_active_zone_discs()
	cover_points.clear()
	if projectile_manager != null:
		projectile_manager.clear_projectiles()
	if selection_manager != null:
		selection_manager.deselect_all()
	if commander_system != null:
		commander_system.clear_directives()
	_unit_flank_memory.clear()
	if health_bar_overlay != null:
		health_bar_overlay.clear_all()

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
	current_room_info = room_info
	if room_info != null:
		var walls: Array = room_info.setup_destructible_walls()
		if projectile_manager != null:
			projectile_manager.set_wall_obstacles(walls)
	elif projectile_manager != null:
		projectile_manager.set_wall_obstacles([])
	var player_spawns: Array[Vector3] = room_info.get_player_spawn_positions() if room_info != null else []
	var persisted_hp: Dictionary = room_manager.get_squad_persistent_state()

	for i in range(squad_units.size()):
		var unit: CombatUnitScript = squad_units[i]
		if unit == null or not is_instance_valid(unit):
			continue
		if unit.unit_data != null and persisted_hp.has(unit.unit_data.id):
			unit.current_hp = clampi(int(persisted_hp[unit.unit_data.id]), 0, unit.max_hp)
			unit.is_alive = unit.current_hp > 0
		unit.set_meta(&"_prev_hp", unit.current_hp)
		unit.visible = unit.is_alive
		unit.is_holding_fire = false
		unit.has_player_order = false
		unit.current_order_type = ""
		unit.order_target_node = null
		if i < player_spawns.size():
			unit.position = player_spawns[i]
		else:
			unit.position = Vector3(-4.5 + float(i) * 3.0, 0.0, 20.0)
		proxy_factory.set_unit_selected(unit, false)
		proxy_factory.update_unit_order_visual(unit, "")
		proxy_factory.update_unit_hp_label(unit, unit.name, unit.current_hp, unit.max_hp, false)
		if combat_hud != null and unit.unit_data != null:
			combat_hud.update_striker_hp(unit.unit_data.id, unit.current_hp, unit.max_hp)
			combat_hud.update_striker_order(unit.unit_data.id, "")

	proxy_factory.update_skill_preview_disc(skill_preview_disc, Vector3.ZERO, 1.0, false)
	proxy_factory.update_skill_range_ring(skill_range_ring, Vector3.ZERO, 0.0, false)
	proxy_factory.update_tactical_zone_disc(tactical_zone_disc, Vector3.ZERO, 6.5, 1, false)
	proxy_factory.update_order_beacon(order_beacon, Vector3.ZERO, Color.WHITE, false)
	if selection_box_overlay != null:
		selection_box_overlay.update_tactical_markers([], [])
		selection_box_overlay.update_commander_markers(Vector2.ZERO, 0.0, {})
	if combat_hud != null and commander_system != null:
		combat_hud.update_commander_status(commander_system.get_directive_summary())

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
		proxy_factory.update_unit_hp_label(boss, "BOSS", boss.current_hp, boss.max_hp, true)
		_bind_unit_hp_feedback(boss)
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
		proxy_factory.update_unit_hp_label(grunt, grunt.name, grunt.current_hp, grunt.max_hp, true)
		_bind_unit_hp_feedback(grunt)
		grunt.unit_died.connect(_on_enemy_died)
		enemies_container.add_child(grunt)
		enemy_units.append(grunt)

	wave_spawner.start_wave(room_index + 1, enemy_units.size())
	if combat_hud != null:
		combat_hud.update_wave(room_index + 1)
	_update_tactical_2d_overlay()

func _on_enemy_died(unit: CombatUnitScript) -> void:
	if unit != null and is_instance_valid(unit):
		unit.visible = false
		if commander_system != null and commander_system.priority_target == unit:
			commander_system.set_priority_target(null)
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

	var atk_mods: Dictionary = _get_terrain_mods(striker.position)
	var eff_range: float = striker.attack_range * float(atk_mods.get("range_bonus_multiplier", 1.0))
	proxy_factory.update_unit_attack_range_ring(striker, eff_range)

	# Sync elevation smoothly even when standing
	var target_elev: float = float(atk_mods.get("elevation_offset", 0.0))
	if not is_equal_approx(striker.position.y, target_elev):
		striker.position.y = lerpf(striker.position.y, target_elev, minf(1.0, delta * 8.0))

	if striker.has_player_order:
		if not striker.check_emergency_override():
			_execute_player_order(striker, delta, cd, eff_range)
			if striker.is_holding_fire and striker.has_player_order:
				proxy_factory.update_unit_order_visual(striker, "🚫 " + striker.current_order_type)
			_apply_unit_separation(striker, delta)
			return

	var decision: Dictionary
	if utility_ai != null:
		decision = utility_ai.evaluate_unit_utility(
			striker,
			allies,
			enemies,
			cover_points,
			active_aoes,
			commander_system,
			current_room_info,
			_get_student_bond_level(striker)
		)
	else:
		decision = dps_ai.evaluate_action(striker, allies, enemies, cover_points)

	var action: String = str(decision.get("action", "IDLE"))
	var target: Variant = decision.get("target", null)
	var target_pos: Vector3 = decision.get("target_pos", striker.position)
	var status_tag: String = str(decision.get("status_tag", ""))
	if not status_tag.is_empty():
		proxy_factory.update_unit_order_visual(striker, status_tag)
		if combat_hud != null and striker.unit_data != null:
			combat_hud.update_striker_order(striker.unit_data.id, status_tag)

	match action:
		"EVADE_AOE", "SURVIVAL_RETREAT", "ADVANCE_TO_ZONE", "HOLD_DEFENSE_ZONE":
			_navigate_unit_toward(striker, target_pos, delta)
		"FREESHOT_BOMBARD":
			var bomb_pos: Vector3 = (target as CombatUnitScript).position if (target is CombatUnitScript) else target_pos
			var dist_bomb: float = Vector2(striker.position.x, striker.position.z).distance_to(Vector2(bomb_pos.x, bomb_pos.z))
			if dist_bomb > eff_range:
				_navigate_unit_toward(striker, bomb_pos, delta)
			elif cd <= 0.0 and not striker.is_holding_fire:
				_fire_freeshot_shell(striker, bomb_pos, uid)
		"DEFEND_ZONE_ENGAGE":
			var anchor_dist: float = Vector2(striker.position.x, striker.position.z).distance_to(Vector2(target_pos.x, target_pos.z))
			if anchor_dist > 0.75:
				_navigate_unit_toward(striker, target_pos, delta)
			if target is CombatUnitScript:
				var d_enemy := target as CombatUnitScript
				if striker.position.distance_to(d_enemy.position) <= eff_range + 1.5 and has_unit_los(striker, d_enemy):
					if cd <= 0.0 and not striker.is_holding_fire:
						_fire_striker_shot(striker, d_enemy, uid)
		"HEAL_ALLY":
			if target is CombatUnitScript:
				var ally := target as CombatUnitScript
				var dist: float = striker.position.distance_to(ally.position)
				if dist > eff_range:
					_navigate_unit_toward(striker, ally.position, delta)
				elif cd <= 0.0 and ally.current_hp < ally.max_hp:
					ally.heal(striker.atk * 2)
					_unit_cooldowns[uid] = STRIKER_ATTACK_COOLDOWN
		"TAKE_COVER_AND_ENGAGE":
			var cp: Variant = decision.get("cover", null)
			var dist_cp: float = Vector2(striker.position.x, striker.position.z).distance_to(Vector2(target_pos.x, target_pos.z))
			if dist_cp > 0.65:
				_navigate_unit_toward(striker, target_pos, delta)
			else:
				if cp is CoverPoint3DScript:
					(cp as CoverPoint3DScript).claim(striker)
				if target is CombatUnitScript:
					var c_enemy := target as CombatUnitScript
					if striker.position.distance_to(c_enemy.position) <= eff_range and has_unit_los(striker, c_enemy):
						if cd <= 0.0 and not striker.is_holding_fire:
							_fire_striker_shot(striker, c_enemy, uid)
					elif commander_system == null or commander_system.current_stance != CommanderDirectiveSystemScript.SquadStance.DEFENSIVE_HOLD:
						_navigate_unit_toward(striker, c_enemy.position, delta)
		"FOCUS_PRIORITY_TARGET", "ENGAGE_BEST_ENEMY", "ATTACK_TARGET", "TAUNT_ENGAGE":
			if target is CombatUnitScript:
				var enemy := target as CombatUnitScript
				var dist: float = striker.position.distance_to(enemy.position)
				if dist > eff_range or not has_unit_los(striker, enemy):
					_navigate_unit_toward(striker, enemy.position, delta)
				elif cd <= 0.0 and not striker.is_holding_fire:
					_fire_striker_shot(striker, enemy, uid)
		"POSITION_AND_BUFF":
			if target is Vector3:
				_navigate_unit_toward(striker, target as Vector3, delta)

	_apply_unit_separation(striker, delta)

func _fire_striker_shot(striker: CombatUnitScript, enemy: CombatUnitScript, uid: int) -> void:
	if striker.is_holding_fire:
		return
	var dmg: int = striker.damage_resolver.calculate_damage(striker, enemy, card_manager.get_active_buffs())
	var def_mult: float = float(_get_terrain_mods(enemy.position).get("damage_taken_multiplier", 1.0))
	dmg = maxi(1, int(round(float(dmg) * def_mult)))
	projectile_manager.spawn_projectile(
		striker.position + Vector3(0.0, 0.7, 0.0),
		enemy.position + Vector3(0.0, 0.7, 0.0),
		24.0,
		dmg,
		striker,
		enemy,
		striker.penetration_power,
		striker.wall_damage
	)
	_unit_cooldowns[uid] = STRIKER_ATTACK_COOLDOWN

func _fire_freeshot_shell(striker: CombatUnitScript, impact_pos: Vector3, uid: int) -> void:
	if striker.is_holding_fire:
		return
	var splash_rad: float = maxf(2.2, striker.basic_aoe_radius)
	projectile_manager.spawn_projectile(
		striker.position + Vector3(0.0, 0.7, 0.0),
		impact_pos + Vector3(0.0, 0.2, 0.0),
		20.0,
		0,
		striker,
		null,
		striker.penetration_power,
		striker.wall_damage
	)
	var hit_any: bool = false
	for enemy in _get_living_enemies():
		var eu := enemy as CombatUnitScript
		if eu == null:
			continue
		if Vector2(eu.position.x, eu.position.z).distance_to(Vector2(impact_pos.x, impact_pos.z)) <= splash_rad:
			var dmg: int = striker.damage_resolver.calculate_damage(striker, eu, card_manager.get_active_buffs())
			dmg = maxi(1, int(round(float(dmg) * 0.85)))
			eu.take_damage(dmg, striker)
			hit_any = true
	if health_bar_overlay != null:
		health_bar_overlay.spawn_floating_text(
			impact_pos + Vector3(0.0, 1.0, 0.0),
			"💣 SHELL!" if hit_any else "💥",
			Color(1.0, 0.55, 0.82),
			hit_any
		)
	_unit_cooldowns[uid] = STRIKER_ATTACK_COOLDOWN

func _execute_player_order(striker: CombatUnitScript, delta: float, cd: float, eff_range: float) -> void:
	var uid: int = striker.get_instance_id()
	match striker.current_order_type:
		"MOVE":
			if Vector2(striker.position.x, striker.position.z).distance_to(Vector2(striker.order_target_position.x, striker.order_target_position.z)) <= 0.45:
				striker.clear_player_order()
			else:
				_navigate_unit_toward(striker, striker.order_target_position, delta)
		"COVER":
			if Vector2(striker.position.x, striker.position.z).distance_to(Vector2(striker.order_target_position.x, striker.order_target_position.z)) <= 0.55:
				if striker.order_target_node is CoverPoint3DScript:
					(striker.order_target_node as CoverPoint3DScript).claim(striker)
				striker.clear_player_order()
			else:
				_navigate_unit_toward(striker, striker.order_target_position, delta)
		"FOCUS_FIRE":
			var target_enemy := striker.order_target_node as CombatUnitScript
			if target_enemy == null or not is_instance_valid(target_enemy) or not target_enemy.is_alive:
				striker.clear_player_order()
				return
			var dist: float = striker.position.distance_to(target_enemy.position)
			if dist > eff_range or not has_unit_los(striker, target_enemy):
				_navigate_unit_toward(striker, target_enemy.position, delta)
			elif cd <= 0.0 and not striker.is_holding_fire:
				_fire_striker_shot(striker, target_enemy, uid)
		"HOLD_POSITION":
			pass
		"HOLD_FIRE":
			striker.has_player_order = false

func _tick_enemy(enemy: EnemyUnitScript, delta: float, allies: Array) -> void:
	var uid: int = enemy.get_instance_id()
	var cd: float = maxf(0.0, float(_unit_cooldowns.get(uid, 0.0)) - delta)
	_unit_cooldowns[uid] = cd

	var enemy_mods: Dictionary = _get_terrain_mods(enemy.position)
	var eff_range: float = enemy.attack_range * float(enemy_mods.get("range_bonus_multiplier", 1.0))
	var target_elev: float = float(enemy_mods.get("elevation_offset", 0.0))
	if not is_equal_approx(enemy.position.y, target_elev):
		enemy.position.y = lerpf(enemy.position.y, target_elev, minf(1.0, delta * 8.0))

	var decision: Dictionary = enemy_ai.evaluate(enemy, allies)
	var action: String = str(decision.get("action", "IDLE"))
	var target: Variant = decision.get("target", null)
	if not (target is CombatUnitScript) or action == "IDLE":
		return

	var ally := target as CombatUnitScript
	var dist: float = enemy.position.distance_to(ally.position)
	if (action == "RUSH" and dist > eff_range) or (dist <= eff_range and not has_unit_los(enemy, ally)):
		_navigate_unit_toward(enemy, ally.position, delta)
	elif dist <= eff_range and cd <= 0.0:
		var dmg: int = enemy.damage_resolver.calculate_damage(enemy, ally, [])
		var ally_mult: float = float(_get_terrain_mods(ally.position).get("damage_taken_multiplier", 1.0))
		dmg = maxi(1, int(round(float(dmg) * ally_mult)))
		projectile_manager.spawn_projectile(enemy.position + Vector3(0, 0.7, 0), ally.position + Vector3(0, 0.7, 0), 18.0, dmg, enemy, ally, enemy.penetration_power, enemy.wall_damage)
		_unit_cooldowns[uid] = ENEMY_ATTACK_COOLDOWN

## Returns true when attacker has clear Line-of-Sight (or sufficient wall penetration) to target.
func has_unit_los(attacker: CombatUnitScript, target: CombatUnitScript) -> bool:
	if attacker == null or target == null or current_room_info == null or not is_instance_valid(current_room_info):
		return true
	var res: Dictionary = current_room_info.check_line_of_sight(
		attacker.position + Vector3(0.0, 0.7, 0.0),
		target.position + Vector3(0.0, 0.7, 0.0),
		attacker.penetration_power
	)
	return bool(res.get("clear", true))

func _find_wall_blocking_point(world_pos: Vector3, padding: float = 0.36) -> Object:
	if current_room_info == null or not is_instance_valid(current_room_info):
		return null
	for wall in current_room_info.get_wall_obstacles():
		if wall != null and is_instance_valid(wall) and wall.intersects_point_xz(world_pos, padding):
			return wall
	return null

func _find_movement_blocker_along_segment(from_pos: Vector3, to_pos: Vector3) -> Object:
	if current_room_info == null or not is_instance_valid(current_room_info):
		return null
	var seg_a := Vector3(from_pos.x, from_pos.y + 0.5, from_pos.z)
	var seg_b := Vector3(to_pos.x, to_pos.y + 0.5, to_pos.z)
	var closest_wall: Object = null
	var best_t: float = 2.0
	for wall in current_room_info.get_wall_obstacles():
		if wall == null or not is_instance_valid(wall) or wall.is_destroyed:
			continue
		var res: Dictionary = wall.intersects_segment(seg_a, seg_b, 0.32)
		if bool(res.get("hit", false)):
			var t_val: float = float(res.get("t", 1.0))
			if t_val < best_t:
				best_t = t_val
				closest_wall = wall
	return closest_wall

func _push_out_of_overlapping_walls(unit: CombatUnitScript) -> void:
	for _pass in range(2):
		var blocker = _find_wall_blocking_point(unit.position, 0.36)
		if blocker == null or not blocker.has_method(&"get_push_out_offset"):
			break
		var push: Vector3 = blocker.get_push_out_offset(unit.position, 0.42)
		if push.is_zero_approx():
			break
		unit.position += push

func _pick_unblocked_corner(unit: CombatUnitScript, blocker: Object, target_pos: Vector3) -> Vector3:
	var corners: Array[Vector3] = blocker.get_flank_corners(1.25)
	var b_center: Vector3 = blocker.get_world_center()
	var resolved_corners: Array[Vector3] = []
	for c in corners:
		var cand: Vector3 = Vector3(c.x, unit.position.y, c.z)
		var out_dir: Vector3 = Vector3(cand.x - b_center.x, 0.0, cand.z - b_center.z)
		if out_dir.length() > 0.01:
			out_dir = out_dir.normalized()
			for _step in range(4):
				if _find_wall_blocking_point(cand, 0.38) == null:
					break
				cand += out_dir * 1.6
		resolved_corners.append(cand)

	var uid: int = unit.get_instance_id()
	var blocker_id: int = blocker.get_instance_id()
	var mem: Variant = _unit_flank_memory.get(uid, null)
	if mem is Dictionary:
		var m := mem as Dictionary
		if int(m.get("wall_id", -1)) == blocker_id and room_elapsed_time < float(m.get("expires", 0.0)):
			var prev_idx: int = int(m.get("side_idx", 0))
			var prev_wp: Vector3 = resolved_corners[clampi(prev_idx, 0, resolved_corners.size() - 1)]
			if Vector2(unit.position.x, unit.position.z).distance_to(Vector2(prev_wp.x, prev_wp.z)) > 0.55:
				return prev_wp

	var best_idx: int = 0
	var cost_a: float = Vector2(unit.position.x, unit.position.z).distance_to(Vector2(resolved_corners[0].x, resolved_corners[0].z)) + Vector2(resolved_corners[0].x, resolved_corners[0].z).distance_to(Vector2(target_pos.x, target_pos.z))
	var cost_b: float = Vector2(unit.position.x, unit.position.z).distance_to(Vector2(resolved_corners[1].x, resolved_corners[1].z)) + Vector2(resolved_corners[1].x, resolved_corners[1].z).distance_to(Vector2(target_pos.x, target_pos.z))
	if cost_b + 0.05 < cost_a:
		best_idx = 1
	elif absf(cost_a - cost_b) <= 0.05:
		best_idx = 0 if (abs(uid) % 2 == 0) else 1

	_unit_flank_memory[uid] = {
		"wall_id": blocker_id,
		"side_idx": best_idx,
		"side": 1.0 if best_idx == 0 else -1.0,
		"waypoint": resolved_corners[best_idx],
		"expires": room_elapsed_time + 2.2,
	}
	return resolved_corners[best_idx]

func _navigate_unit_toward(unit: CombatUnitScript, target_pos: Vector3, delta: float) -> void:
	if delta <= 0.0:
		return
	_push_out_of_overlapping_walls(unit)

	var flat_target := Vector3(target_pos.x, unit.position.y, target_pos.z)
	if Vector2(unit.position.x, unit.position.z).distance_to(Vector2(flat_target.x, flat_target.z)) <= 0.15:
		return

	var uid: int = unit.get_instance_id()
	var steer_target: Vector3 = flat_target
	var blocker = _find_movement_blocker_along_segment(unit.position, flat_target)
	if blocker != null and is_instance_valid(blocker):
		steer_target = _pick_unblocked_corner(unit, blocker, flat_target)
	else:
		_unit_flank_memory.erase(uid)

	var to_steer: Vector3 = Vector3(steer_target.x, unit.position.y, steer_target.z) - unit.position
	var dist: float = to_steer.length()
	if dist <= 0.05:
		return
	var mods: Dictionary = _get_terrain_mods(unit.position)
	var speed_mult: float = float(mods.get("speed_multiplier", 1.0))
	var step: float = minf(dist, unit.speed * speed_mult * delta)
	var dir: Vector3 = to_steer / dist
	var mem: Variant = _unit_flank_memory.get(uid, null)
	var side_sign: float = float((mem as Dictionary).get("side", 1.0)) if (mem is Dictionary) else (1.0 if (abs(uid) % 2 == 0) else -1.0)

	var test_angles: Array[float] = [0.0, 0.61 * side_sign, -0.61 * side_sign, 1.13 * side_sign, -1.13 * side_sign, 1.65 * side_sign, -1.65 * side_sign]
	var moved: bool = false
	for ang in test_angles:
		var rot_dir: Vector3 = dir.rotated(Vector3.UP, ang)
		var cand: Vector3 = unit.position + rot_dir * step
		if _find_wall_blocking_point(cand, 0.36) == null and not _is_step_blocked_by_peer(unit, cand, 1.05):
			unit.position = cand
			moved = true
			break
	if not moved:
		for ang in test_angles:
			var rot_dir: Vector3 = dir.rotated(Vector3.UP, ang)
			var cand: Vector3 = unit.position + rot_dir * step
			if _find_wall_blocking_point(cand, 0.36) == null:
				unit.position = cand
				break

	var new_elev: float = float(_get_terrain_mods(unit.position).get("elevation_offset", 0.0))
	unit.position.y = lerpf(unit.position.y, new_elev, minf(1.0, delta * 10.0))

func _is_step_blocked_by_peer(unit: CombatUnitScript, cand_pos: Vector3, min_sep: float = 1.05) -> bool:
	var peers: Array = squad_units if (not (unit is EnemyUnitScript)) else enemy_units
	var cand_xz := Vector2(cand_pos.x, cand_pos.z)
	var cur_xz := Vector2(unit.position.x, unit.position.z)
	for other in peers:
		if other == unit or other == null or not is_instance_valid(other) or not other.is_alive:
			continue
		var o_xz := Vector2(other.position.x, other.position.z)
		var new_d: float = cand_xz.distance_to(o_xz)
		if new_d < min_sep:
			var cur_d: float = cur_xz.distance_to(o_xz)
			if new_d < cur_d:
				return true
	return false

func _move_unit_toward(unit: CombatUnitScript, target_pos: Vector3, delta: float) -> void:
	_navigate_unit_toward(unit, target_pos, delta)

func _apply_unit_separation(unit: CombatUnitScript, delta: float) -> void:
	if delta <= 0.0 or unit == null or not unit.is_alive:
		return
	var push := Vector3.ZERO
	var peers: Array = squad_units if (not (unit is EnemyUnitScript)) else enemy_units
	var uid: int = unit.get_instance_id()
	var sep_radius: float = 1.35
	for other in peers:
		if other == unit or other == null or not is_instance_valid(other) or not other.is_alive:
			continue
		var diff := Vector2(unit.position.x - other.position.x, unit.position.z - other.position.z)
		var d: float = diff.length()
		if d < sep_radius:
			var sep_dir: Vector2
			if d > 0.05:
				sep_dir = diff / d
			else:
				var ang: float = float(abs(uid) % 8) * (TAU / 8.0)
				sep_dir = Vector2(cos(ang), sin(ang))
			var strength: float = (sep_radius - d) / sep_radius
			push.x += sep_dir.x * strength
			push.z += sep_dir.y * strength
	if push.is_zero_approx():
		return
	var push_dir: Vector3 = push.normalized()
	var push_step: float = minf(0.55, 4.2 * delta)
	var cand: Vector3 = unit.position + push_dir * push_step
	if _find_wall_blocking_point(cand, 0.36) == null:
		unit.position = cand
	else:
		var side_sign: float = 1.0 if (abs(uid) % 2 == 0) else -1.0
		var tan_cand: Vector3 = unit.position + push_dir.rotated(Vector3.UP, PI * 0.5 * side_sign) * (push_step * 0.8)
		if _find_wall_blocking_point(tan_cand, 0.36) == null:
			unit.position = tan_cand

func _get_student_bond_level(unit: CombatUnitScript) -> int:
	if unit == null or unit.unit_data == null:
		return 1
	var save_mgr := get_node_or_null("/root/SaveManager")
	if save_mgr != null and &"bonds" in save_mgr:
		var bonds_dict: Variant = save_mgr.get("bonds")
		if bonds_dict is Dictionary:
			return maxi(1, int((bonds_dict as Dictionary).get(unit.unit_data.id, 1)))
	return 1

func _get_terrain_mods(world_pos: Vector3) -> Dictionary:
	if current_room_info != null and is_instance_valid(current_room_info):
		return current_room_info.get_terrain_modifiers_at(world_pos)
	return {
		"terrain_type": "NORMAL",
		"speed_multiplier": 1.0,
		"range_bonus_multiplier": 1.0,
		"damage_taken_multiplier": 1.0,
		"elevation_offset": 0.0,
	}

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
		var origin: Vector3 = _get_skill_caster_origin()
		targeting_overlay.set_caster_origin(origin)
		targeting_overlay.begin_targeting(sk)
		proxy_factory.update_skill_range_ring(skill_range_ring, origin, sk.cast_range, sk.cast_range > 0.0)
		_update_status_banner("Targeting EX Skill: %s | Range: %.0fm (Left-Click ground)" % [sk.name, sk.cast_range])

func _on_ex_target_confirmed(skill: SkillData, world_pos: Vector3) -> void:
	proxy_factory.update_skill_preview_disc(skill_preview_disc, Vector3.ZERO, 1.0, false)
	proxy_factory.update_skill_range_ring(skill_range_ring, Vector3.ZERO, 0.0, false)
	if skill == null or ex_skill_system == null:
		return
	ex_skill_system.activate_skill(skill, world_pos)

func _on_ex_target_cancelled() -> void:
	proxy_factory.update_skill_preview_disc(skill_preview_disc, Vector3.ZERO, 1.0, false)
	proxy_factory.update_skill_range_ring(skill_range_ring, Vector3.ZERO, 0.0, false)
	_update_status_banner("EX Skill Cancelled")

func _on_ex_skill_activated(skill: SkillData, target_pos: Vector3) -> void:
	if skill == null:
		return
	var caster_origin: Vector3 = _get_skill_caster_origin()
	if skill.effect_type == "HEAL":
		for unit in _get_living_strikers():
			var s := unit as CombatUnitScript
			if skill.is_point_inside_aoe(caster_origin, target_pos, s.position):
				s.heal(450)
		_update_status_banner("EX Skill Cast: %s (Healed allies!)" % skill.name)
		return

	# 1. Resolve structural damage / wall breaching inside skill AoE
	var breached_count: int = 0
	if current_room_info != null and skill.wall_damage > 0:
		var shape: String = skill.aoe_shape.to_upper()
		for wall in current_room_info.get_wall_obstacles():
			if wall == null or not is_instance_valid(wall) or wall.is_destroyed:
				continue
			var w_center: Vector3 = wall.get_world_center()
			var hits_wall: bool = false
			if shape == "LINE":
				hits_wall = skill.is_point_inside_aoe(caster_origin, target_pos, w_center) or bool(wall.intersects_segment(caster_origin + Vector3(0.0, 0.7, 0.0), target_pos + Vector3(0.0, 0.7, 0.0), skill.line_width * 0.5).get("hit", false))
			elif shape == "CONE":
				hits_wall = skill.is_point_inside_aoe(caster_origin, target_pos, w_center) or bool(wall.intersects_segment(caster_origin + Vector3(0.0, 0.7, 0.0), target_pos + Vector3(0.0, 0.7, 0.0), 0.5).get("hit", false))
			else:
				hits_wall = wall.intersects_point_xz(target_pos, skill.aoe_radius)
			if hits_wall:
				var was_intact: bool = not wall.is_destroyed
				wall.take_structural_damage(skill.wall_damage, skill.penetration_power)
				if was_intact and wall.is_destroyed:
					breached_count += 1
					if health_bar_overlay != null:
						health_bar_overlay.spawn_floating_text(w_center + Vector3(0.0, 1.6, 0.0), "💥 BREACH!", Color(1.0, 0.85, 0.2), true)

	# 2. Resolve damage to enemies inside AoE (honoring LOS & pierce attenuation)
	for unit in _get_living_enemies():
		var e := unit as CombatUnitScript
		if not skill.is_point_inside_aoe(caster_origin, target_pos, e.position):
			continue
		var final_dmg: int = 650
		if current_room_info != null:
			var los_info: Dictionary = current_room_info.check_line_of_sight(
				caster_origin + Vector3(0.0, 0.7, 0.0),
				e.position + Vector3(0.0, 0.7, 0.0),
				skill.penetration_power
			)
			var is_clear: bool = bool(los_info.get("clear", true))
			if skill.requires_los and not skill.pierce_walls and not is_clear:
				continue
			if skill.pierce_walls:
				if not is_clear:
					continue
				var pierced_count: int = (los_info.get("penetrated_walls", []) as Array).size()
				if pierced_count > 0:
					final_dmg = maxi(1, int(round(float(final_dmg) * pow(0.8, float(pierced_count)))))
		e.take_damage(final_dmg, self)

	if breached_count > 0:
		_update_status_banner("EX Skill Cast: %s (BREACHED %d WALL%s!)" % [skill.name, breached_count, "S" if breached_count > 1 else ""])
	else:
		_update_status_banner("EX Skill Cast: %s!" % skill.name)

func _finalize_commander_zone_drag(end_pos: Vector2) -> void:
	if commander_system == null:
		return
	var iso_cam := _get_isometric_camera()
	if iso_cam == null or not is_inside_tree():
		return
	var w_start: Vector3 = _project_to_ground(_drag_start_pos, iso_cam)
	var w_end: Vector3 = _project_to_ground(end_pos, iso_cam)
	var span: float = Vector2(w_start.x, w_start.z).distance_to(Vector2(w_end.x, w_end.z))
	var radius: float = 6.5 if span < 2.0 else clampf(span, 4.0, 13.0)
	var ztype: String = "ASSAULT"
	match commander_system.active_tool:
		CommanderDirectiveSystemScript.ToolMode.DEFENSE_ZONE:
			ztype = "DEFENSE"
		CommanderDirectiveSystemScript.ToolMode.FREESHOT_ZONE:
			ztype = "FREESHOT"
		_:
			ztype = "ASSAULT"
	var target_ids: Array[String] = _get_selected_student_ids()
	commander_system.create_zone_for_units(ztype, w_start, radius, target_ids)
	commander_system.cancel_tool()
	var who_label: String = "TOÀN ĐỘI" if target_ids.is_empty() else ", ".join(target_ids)
	_update_status_banner("Chỉ thị [%s]: Đặt %s (%.1fm)" % [who_label, ztype, radius])

func _handle_commander_right_click(screen_pos: Vector2) -> void:
	if commander_system == null:
		return
	var iso_cam := _get_isometric_camera()
	if iso_cam == null or not is_inside_tree():
		return
	var world_pt: Vector3 = _project_to_ground(screen_pos, iso_cam)
	var click_xz := Vector2(world_pt.x, world_pt.z)
	var sel_ids: Array[String] = _get_selected_student_ids()

	for enemy in _get_living_enemies():
		var e := enemy as CombatUnitScript
		if Vector2(e.position.x, e.position.z).distance_to(click_xz) <= 2.2:
			commander_system.set_target_for_units(e, sel_ids)
			var scope: String = "TOÀN ĐỘI" if sel_ids.is_empty() else ", ".join(sel_ids)
			_update_status_banner("Chỉ thị [%s]: Mục tiêu ưu tiên (%s)" % [scope, e.name])
			return

	if selection_manager != null and not selection_manager.selected_units.is_empty():
		selection_manager.issue_move_order(world_pt)
		proxy_factory.update_order_beacon(order_beacon, world_pt, Color(0.2, 0.9, 1.0, 0.45), true)
		_update_status_banner("Chỉ thị [%s]: Di chuyển đến điểm chỉ định" % ", ".join(sel_ids))
		return

	var origin_centroid: Vector3 = _get_squad_centroid()
	commander_system.set_advance_vector(origin_centroid, world_pt)
	proxy_factory.update_order_beacon(order_beacon, world_pt, Color(0.25, 0.92, 1.0, 0.55), true)
	_update_status_banner("Chỉ thị Chỉ Huy: Tiến quân theo hướng chỉ định")

func _get_selected_student_ids() -> Array[String]:
	var ids: Array[String] = []
	if selection_manager == null:
		return ids
	for u in selection_manager.selected_units:
		if u is CombatUnitScript:
			var cu := u as CombatUnitScript
			if cu.is_alive:
				var sid: String = cu.unit_data.id if cu.unit_data != null else str(cu.name)
				if not sid.is_empty() and not ids.has(sid):
					ids.append(sid)
	return ids

func _get_targeted_strikers() -> Array[CombatUnitScript]:
	var out: Array[CombatUnitScript] = []
	if selection_manager != null and not selection_manager.selected_units.is_empty():
		for u in selection_manager.selected_units:
			if u is CombatUnitScript and (u as CombatUnitScript).is_alive:
				out.append(u as CombatUnitScript)
	if out.is_empty():
		for s in _get_living_strikers():
			out.append(s as CombatUnitScript)
	return out

func _select_striker_slot(slot_idx: int, additive: bool = false) -> void:
	if selection_manager == null or slot_idx < 0 or slot_idx >= squad_units.size():
		return
	var u: CombatUnitScript = squad_units[slot_idx]
	if u != null and is_instance_valid(u) and u.is_alive:
		selection_manager.select_unit(u, additive)

func _select_all_living_strikers() -> void:
	if selection_manager == null:
		return
	selection_manager.deselect_all()
	for s in _get_living_strikers():
		selection_manager.select_unit(s, true)

func _on_striker_portrait_clicked(student_id: String) -> void:
	if selection_manager == null:
		return
	var additive: bool = Input.is_key_pressed(KEY_SHIFT)
	for s in squad_units:
		if s != null and is_instance_valid(s) and s.is_alive:
			var sid: String = s.unit_data.id if s.unit_data != null else str(s.name)
			if sid == student_id:
				selection_manager.select_unit(s, additive)
				return

func _toggle_hold_fire_for_selection() -> void:
	var targets: Array[CombatUnitScript] = _get_targeted_strikers()
	if targets.is_empty():
		return
	var any_not_holding: bool = false
	for u in targets:
		if not u.is_holding_fire:
			any_not_holding = true
			break
	for u in targets:
		u.set_hold_fire(any_not_holding)
		var tag: String = "🚫 GIỮ HỎA LỰC" if any_not_holding else ""
		proxy_factory.update_unit_order_visual(u, tag)
		if combat_hud != null and u.unit_data != null:
			combat_hud.update_striker_order(u.unit_data.id, tag)
	_update_status_banner("Giữ Hỏa Lực (%s): %s" % ["BẬT" if any_not_holding else "TẮT", ", ".join(_get_selected_student_ids()) if not _get_selected_student_ids().is_empty() else "TOÀN ĐỘI"])

func _clear_directives_for_selection() -> void:
	var sel_ids: Array[String] = _get_selected_student_ids()
	if commander_system != null:
		commander_system.clear_directives_for_units(sel_ids)
	for u in _get_targeted_strikers():
		u.set_hold_fire(false)
		u.clear_player_order()
		proxy_factory.update_unit_order_visual(u, "")
		if combat_hud != null and u.unit_data != null:
			combat_hud.update_striker_order(u.unit_data.id, "")
	_update_status_banner("Đã hủy chỉ thị: %s" % (", ".join(sel_ids) if not sel_ids.is_empty() else "TOÀN ĐỘI"))

func _on_commander_tool_clicked(tool_id: String) -> void:
	if commander_system == null:
		return
	match tool_id:
		"ASSAULT":
			commander_system.select_tool(CommanderDirectiveSystemScript.ToolMode.ASSAULT_ZONE)
		"DEFENSE":
			commander_system.select_tool(CommanderDirectiveSystemScript.ToolMode.DEFENSE_ZONE)
		"FREESHOT":
			commander_system.select_tool(CommanderDirectiveSystemScript.ToolMode.FREESHOT_ZONE)
		"HOLD_FIRE":
			_toggle_hold_fire_for_selection()
		"CLEAR":
			_clear_directives_for_selection()

func _on_commander_tool_changed(new_tool: int, _tool_name: String) -> void:
	if combat_hud == null:
		return
	match new_tool:
		CommanderDirectiveSystemScript.ToolMode.ASSAULT_ZONE:
			combat_hud.set_active_commander_tool("ASSAULT")
		CommanderDirectiveSystemScript.ToolMode.DEFENSE_ZONE:
			combat_hud.set_active_commander_tool("DEFENSE")
		CommanderDirectiveSystemScript.ToolMode.FREESHOT_ZONE:
			combat_hud.set_active_commander_tool("FREESHOT")
		_:
			combat_hud.set_active_commander_tool("NONE")

func _on_commander_zones_updated(_zones: Array) -> void:
	_sync_tactical_zone_discs()

func _clear_active_zone_discs() -> void:
	for zid in active_zone_discs:
		var disc: Variant = active_zone_discs[zid]
		if disc is Node and is_instance_valid(disc):
			var n := disc as Node
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.free()
	active_zone_discs.clear()
	if tactical_zone_disc != null and is_instance_valid(tactical_zone_disc):
		tactical_zone_disc.visible = false

func _sync_tactical_zone_discs() -> void:
	if commander_system == null:
		return
	var zones: Array[Dictionary] = commander_system.active_zones
	if zones.is_empty():
		_clear_active_zone_discs()
		return

	if tactical_zone_disc != null and is_instance_valid(tactical_zone_disc):
		proxy_factory.update_tactical_zone_visual(tactical_zone_disc, zones[0], true)

	var keep_ids: Array[int] = []
	for i: int in range(1, zones.size()):
		var zd: Dictionary = zones[i]
		var zid: int = int(zd.get("id", -1))
		keep_ids.append(zid)
		var disc_node: Node3D = active_zone_discs.get(zid, null) as Node3D
		if disc_node == null or not is_instance_valid(disc_node):
			disc_node = proxy_factory.create_tactical_zone_disc()
			disc_node.name = "TacticalZoneDisc_%d" % zid
			if effects_container != null:
				effects_container.add_child(disc_node)
			active_zone_discs[zid] = disc_node
		proxy_factory.update_tactical_zone_visual(disc_node, zd, true)

	var stale_ids: Array = []
	for existing_id in active_zone_discs:
		if not keep_ids.has(int(existing_id)):
			stale_ids.append(existing_id)
	for sid_key in stale_ids:
		var stale: Variant = active_zone_discs[sid_key]
		if stale is Node and is_instance_valid(stale):
			var sn := stale as Node
			if sn.get_parent() != null:
				sn.get_parent().remove_child(sn)
			sn.free()
		active_zone_discs.erase(sid_key)

func _get_squad_centroid() -> Vector3:
	var living: Array = _get_living_strikers()
	if living.is_empty():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	for s in living:
		var n := s as Node3D
		sum += n.global_position if n.is_inside_tree() else n.position
	return sum / float(living.size())

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
			proxy_factory.set_unit_selected(s, selection_manager.selected_units.has(s), true)

func _on_selection_changed(units: Array[Node3D]) -> void:
	var selected_ids: Array[String] = []
	var single_summary: String = ""
	for s in squad_units:
		if s != null and is_instance_valid(s):
			var is_sel: bool = units.has(s)
			proxy_factory.set_unit_selected(s, is_sel, true)
			if is_sel and s.unit_data != null:
				selected_ids.append(s.unit_data.id)

	if units.size() == 1 and units[0] is CombatUnitScript:
		var u := units[0] as CombatUnitScript
		var terrain_name: String = str(_get_terrain_mods(u.position).get("terrain_type", "NORMAL"))
		var order_str: String = u.current_order_type if u.has_player_order else "AUTO"
		single_summary = "Đang chọn: %s | Trạng thái: %s | Địa hình: %s" % [u.name, order_str, terrain_name]
	elif units.size() >= 2:
		single_summary = "Đang chọn nhóm (%d): %s" % [selected_ids.size(), ", ".join(selected_ids)]

	if combat_hud != null:
		combat_hud.update_selected_units(selected_ids, single_summary)
	_update_tactical_2d_overlay()

func _on_order_issued(order_type: String, units: Array[Node3D]) -> void:
	var last_target_pos: Vector3 = Vector3.ZERO
	var has_beacon_pos: bool = false
	for u in units:
		if u is CombatUnitScript:
			var cu := u as CombatUnitScript
			if order_type == "HOLD_FIRE":
				cu.is_holding_fire = true
				cu.has_player_order = false
			proxy_factory.update_unit_order_visual(cu, order_type)
			if combat_hud != null and cu.unit_data != null:
				combat_hud.update_striker_order(cu.unit_data.id, order_type)
			if order_type == "MOVE" or order_type == "COVER":
				last_target_pos = cu.order_target_position
				has_beacon_pos = true

	if has_beacon_pos:
		var b_color: Color = Color(0.2, 0.95, 0.55, 0.45) if order_type == "COVER" else Color(0.2, 0.9, 1.0, 0.45)
		proxy_factory.update_order_beacon(order_beacon, last_target_pos, b_color, true)
	else:
		proxy_factory.update_order_beacon(order_beacon, Vector3.ZERO, Color.WHITE, false)

	_refresh_target_reticles()
	_update_status_banner("Order Issued: %s (%d units)" % [order_type, units.size()])
	_update_tactical_2d_overlay()

func _on_striker_order_completed(u: CombatUnitScript) -> void:
	if u != null and is_instance_valid(u):
		var restored_tag: String = "🚫 GIỮ HỎA LỰC" if u.is_holding_fire else ""
		proxy_factory.update_unit_order_visual(u, restored_tag)
		if combat_hud != null and u.unit_data != null:
			combat_hud.update_striker_order(u.unit_data.id, restored_tag)
	_refresh_target_reticles()
	_update_tactical_2d_overlay()

func _on_directive_changed(summary_text: String) -> void:
	_sync_tactical_zone_discs()
	if commander_system != null:
		if not commander_system.has_advance_vector and order_beacon != null:
			proxy_factory.update_order_beacon(order_beacon, Vector3.ZERO, Color.WHITE, false)
	if combat_hud != null and not summary_text.is_empty():
		combat_hud.update_commander_status(summary_text)
	_refresh_target_reticles()
	_update_tactical_2d_overlay()

func _on_priority_target_changed(_target: Node3D) -> void:
	_refresh_target_reticles()
	_update_tactical_2d_overlay()

func _refresh_target_reticles() -> void:
	var focused_enemies: Array = []
	for s in squad_units:
		if s != null and is_instance_valid(s) and s.is_alive and s.has_player_order and s.current_order_type == "FOCUS_FIRE":
			if s.order_target_node != null and is_instance_valid(s.order_target_node):
				focused_enemies.append(s.order_target_node)

	if commander_system != null:
		var prio: Node3D = commander_system.get_valid_priority_target()
		if prio != null and not focused_enemies.has(prio):
			focused_enemies.append(prio)
		for uid_key: String in commander_system.unit_target_map.keys():
			var ut: Node3D = commander_system.get_target_for_unit(uid_key)
			if ut != null and not focused_enemies.has(ut):
				focused_enemies.append(ut)

	for e in enemy_units:
		if e != null and is_instance_valid(e):
			proxy_factory.set_unit_targeted(e, e.is_alive and focused_enemies.has(e))

func _update_tactical_2d_overlay() -> void:
	var iso_cam := _get_isometric_camera()
	var has_cam: bool = iso_cam != null and is_instance_valid(iso_cam) and iso_cam.is_inside_tree()

	_sync_tactical_zone_discs()

	if selection_box_overlay != null:
		var settings_mgr := get_node_or_null("/root/SettingsManager")
		if settings_mgr != null and &"show_group_frame" in settings_mgr:
			selection_box_overlay.show_group_frame = bool(settings_mgr.get("show_group_frame"))

		if not _is_dragging_box:
			var arrow_info: Dictionary = {}
			if has_cam and commander_system != null and commander_system.has_advance_vector:
				if not iso_cam.is_position_behind(commander_system.advance_origin) and not iso_cam.is_position_behind(commander_system.advance_target):
					arrow_info = {
						"active": true,
						"from": iso_cam.unproject_position(commander_system.advance_origin),
						"to": iso_cam.unproject_position(commander_system.advance_target),
						"color": Color(1.0, 0.85, 0.22, 0.90),
					}
			selection_box_overlay.update_commander_markers(Vector2.ZERO, 0.0, arrow_info)

		var screen_pts: Array[Vector2] = []
		var order_lines: Array[Dictionary] = []
		if has_cam and selection_manager != null:
			for u in selection_manager.selected_units:
				if u == null or not is_instance_valid(u):
					continue
				if u is CombatUnitScript and not (u as CombatUnitScript).is_alive:
					continue
				var wpos: Vector3 = u.global_position if u.is_inside_tree() else u.position
				if not iso_cam.is_position_behind(wpos):
					var from_pt: Vector2 = iso_cam.unproject_position(wpos)
					screen_pts.append(from_pt)
					if u is CombatUnitScript:
						var cu := u as CombatUnitScript
						if cu.has_player_order:
							var target_w: Variant = null
							var line_col := Color(0.2, 0.88, 1.0, 0.85)
							if cu.current_order_type == "FOCUS_FIRE" and cu.order_target_node != null and is_instance_valid(cu.order_target_node):
								target_w = (cu.order_target_node as Node3D).global_position
								line_col = Color(1.0, 0.25, 0.25, 0.9)
							elif cu.current_order_type == "MOVE" or cu.current_order_type == "COVER":
								target_w = cu.order_target_position
								line_col = Color(0.25, 0.95, 0.55, 0.85) if cu.current_order_type == "COVER" else Color(0.2, 0.88, 1.0, 0.85)
							if target_w is Vector3 and not iso_cam.is_position_behind(target_w as Vector3):
								order_lines.append({
									"from": from_pt,
									"to": iso_cam.unproject_position(target_w as Vector3),
									"color": line_col,
								})
		selection_box_overlay.update_tactical_markers(screen_pts, order_lines)

	if health_bar_overlay != null:
		var unit_bars: Array[Dictionary] = []
		var boss_bar: Dictionary = {}

		for s in _get_living_strikers():
			var su := s as CombatUnitScript
			var wpos: Vector3 = (su.global_position if su.is_inside_tree() else su.position) + Vector3(0.0, 1.35, 0.0)
			if not has_cam or not iso_cam.is_position_behind(wpos):
				var scr: Vector2 = iso_cam.unproject_position(wpos) if has_cam else Vector2(wpos.x * 24.0 + 640.0, wpos.z * 24.0 + 360.0)
				unit_bars.append({
					"screen_pos": scr,
					"hp_ratio": clampf(float(su.current_hp) / float(maxi(1, su.max_hp)), 0.0, 1.0),
					"current_hp": su.current_hp,
					"max_hp": su.max_hp,
					"is_enemy": false,
					"is_boss": false,
					"name": su.name,
				})

		for e in _get_living_enemies():
			var eu := e as EnemyUnitScript
			var is_boss: bool = eu is BossUnitScript
			var y_off: float = 2.1 if is_boss else 1.45
			var wpos: Vector3 = (eu.global_position if eu.is_inside_tree() else eu.position) + Vector3(0.0, y_off, 0.0)
			if not has_cam or not iso_cam.is_position_behind(wpos):
				var scr: Vector2 = iso_cam.unproject_position(wpos) if has_cam else Vector2(wpos.x * 24.0 + 640.0, wpos.z * 24.0 + 360.0)
				unit_bars.append({
					"screen_pos": scr,
					"hp_ratio": clampf(float(eu.current_hp) / float(maxi(1, eu.max_hp)), 0.0, 1.0),
					"current_hp": eu.current_hp,
					"max_hp": eu.max_hp,
					"is_enemy": true,
					"is_boss": is_boss,
					"name": "BOSS" if is_boss else eu.name,
				})
			if is_boss and boss_bar.is_empty():
				var boss := eu as BossUnitScript
				boss_bar = {
					"visible": true,
					"name": "BOSS: %s" % boss.name,
					"phase": boss.current_phase,
					"hp_ratio": boss.get_hp_ratio(),
					"current_hp": boss.current_hp,
					"max_hp": boss.max_hp,
				}

		health_bar_overlay.update_bars(unit_bars, boss_bar)

func _handle_right_click_order(screen_pos: Vector2) -> void:
	_handle_commander_right_click(screen_pos)

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
	var cam_yaw: float = camera_rig.rotation.y if camera_rig != null else 0.0
	for s in squad_units:
		if s != null and is_instance_valid(s):
			proxy_factory.update_unit_hp_label(s, s.name, s.current_hp, s.max_hp, false)
			var bar3d := s.get_node_or_null("VisualRoot/HPBar3D") as Node3D
			if bar3d != null:
				bar3d.rotation.y = cam_yaw
			if combat_hud != null and s.unit_data != null:
				combat_hud.update_striker_hp(s.unit_data.id, s.current_hp, s.max_hp)
	for e in enemy_units:
		if e != null and is_instance_valid(e):
			proxy_factory.update_unit_hp_label(e, "BOSS" if e is BossUnitScript else e.name, e.current_hp, e.max_hp, true)
			var bar3d := e.get_node_or_null("VisualRoot/HPBar3D") as Node3D
			if bar3d != null:
				bar3d.rotation.y = cam_yaw

func _bind_unit_hp_feedback(unit: CombatUnitScript) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	unit.set_meta(&"_prev_hp", unit.current_hp)
	var cb := _on_unit_hp_changed.bind(unit)
	if not unit.hp_changed.is_connected(cb):
		unit.hp_changed.connect(cb)

func _on_unit_hp_changed(current: int, _max_val: int, unit: CombatUnitScript) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var prev: int = int(unit.get_meta(&"_prev_hp", current))
	unit.set_meta(&"_prev_hp", current)
	var diff: int = current - prev
	if diff == 0:
		return
	var is_enemy: bool = unit is EnemyUnitScript
	proxy_factory.update_unit_hp_label(unit, "BOSS" if unit is BossUnitScript else unit.name, current, _max_val, is_enemy)
	if health_bar_overlay != null:
		var anchor: Vector3 = (unit.global_position if unit.is_inside_tree() else unit.position) + Vector3(0.0, 1.5, 0.0)
		if diff < 0:
			var dmg_amt: int = -diff
			health_bar_overlay.spawn_floating_number(anchor, dmg_amt, false, dmg_amt >= 350)
		else:
			health_bar_overlay.spawn_floating_number(anchor, diff, true, false)

func _get_skill_caster_origin() -> Vector3:
	if selection_manager != null:
		selection_manager.prune_invalid_units()
		for u in selection_manager.selected_units:
			if u is CombatUnitScript and (u as CombatUnitScript).is_alive:
				return (u as Node3D).global_position if u.is_inside_tree() else (u as Node3D).position
	var living: Array = _get_living_strikers()
	if not living.is_empty():
		var sum := Vector3.ZERO
		for s in living:
			var n := s as Node3D
			sum += n.global_position if n.is_inside_tree() else n.position
		return sum / float(living.size())
	if camera_rig != null:
		return camera_rig.global_position if camera_rig.is_inside_tree() else camera_rig.position
	return Vector3.ZERO

func _recenter_camera_on_squad() -> void:
	if camera_rig == null:
		return
	var living: Array = _get_living_strikers()
	if living.is_empty():
		camera_rig.center_on_position(Vector3.ZERO)
		return
	var sum := Vector3.ZERO
	for s in living:
		var n := s as Node3D
		sum += n.global_position if n.is_inside_tree() else n.position
	camera_rig.center_on_position(sum / float(living.size()))

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
	if targeting_overlay != null:
		if not targeting_overlay.target_confirmed.is_connected(_on_ex_target_confirmed):
			targeting_overlay.target_confirmed.connect(_on_ex_target_confirmed)
		if not targeting_overlay.target_cancelled.is_connected(_on_ex_target_cancelled):
			targeting_overlay.target_cancelled.connect(_on_ex_target_cancelled)
	if selection_manager != null:
		if not selection_manager.selection_changed.is_connected(_on_selection_changed):
			selection_manager.selection_changed.connect(_on_selection_changed)
		if not selection_manager.order_issued.is_connected(_on_order_issued):
			selection_manager.order_issued.connect(_on_order_issued)
	if ex_skill_system != null and not ex_skill_system.skill_activated.is_connected(_on_ex_skill_activated):
		ex_skill_system.skill_activated.connect(_on_ex_skill_activated)
	if projectile_manager != null and not projectile_manager.projectile_wall_hit.is_connected(_on_projectile_wall_hit):
		projectile_manager.projectile_wall_hit.connect(_on_projectile_wall_hit)
	if commander_system != null:
		if not commander_system.directive_changed.is_connected(_on_directive_changed):
			commander_system.directive_changed.connect(_on_directive_changed)
		if not commander_system.priority_target_changed.is_connected(_on_priority_target_changed):
			commander_system.priority_target_changed.connect(_on_priority_target_changed)
		if not commander_system.tool_changed.is_connected(_on_commander_tool_changed):
			commander_system.tool_changed.connect(_on_commander_tool_changed)
		if not commander_system.zones_updated.is_connected(_on_commander_zones_updated):
			commander_system.zones_updated.connect(_on_commander_zones_updated)
	if combat_hud != null:
		if not combat_hud.commander_tool_clicked.is_connected(_on_commander_tool_clicked):
			combat_hud.commander_tool_clicked.connect(_on_commander_tool_clicked)
		if not combat_hud.striker_portrait_clicked.is_connected(_on_striker_portrait_clicked):
			combat_hud.striker_portrait_clicked.connect(_on_striker_portrait_clicked)

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
	if targeting_overlay != null and is_instance_valid(targeting_overlay):
		if targeting_overlay.target_confirmed.is_connected(_on_ex_target_confirmed):
			targeting_overlay.target_confirmed.disconnect(_on_ex_target_confirmed)
		if targeting_overlay.target_cancelled.is_connected(_on_ex_target_cancelled):
			targeting_overlay.target_cancelled.disconnect(_on_ex_target_cancelled)
	if selection_manager != null and is_instance_valid(selection_manager):
		if selection_manager.selection_changed.is_connected(_on_selection_changed):
			selection_manager.selection_changed.disconnect(_on_selection_changed)
		if selection_manager.order_issued.is_connected(_on_order_issued):
			selection_manager.order_issued.disconnect(_on_order_issued)
	if ex_skill_system != null and is_instance_valid(ex_skill_system) and ex_skill_system.skill_activated.is_connected(_on_ex_skill_activated):
		ex_skill_system.skill_activated.disconnect(_on_ex_skill_activated)
	if projectile_manager != null and is_instance_valid(projectile_manager) and projectile_manager.projectile_wall_hit.is_connected(_on_projectile_wall_hit):
		projectile_manager.projectile_wall_hit.disconnect(_on_projectile_wall_hit)
	if commander_system != null and is_instance_valid(commander_system):
		if commander_system.directive_changed.is_connected(_on_directive_changed):
			commander_system.directive_changed.disconnect(_on_directive_changed)
		if commander_system.priority_target_changed.is_connected(_on_priority_target_changed):
			commander_system.priority_target_changed.disconnect(_on_priority_target_changed)
		if commander_system.tool_changed.is_connected(_on_commander_tool_changed):
			commander_system.tool_changed.disconnect(_on_commander_tool_changed)
		if commander_system.zones_updated.is_connected(_on_commander_zones_updated):
			commander_system.zones_updated.disconnect(_on_commander_zones_updated)
	if combat_hud != null and is_instance_valid(combat_hud):
		if combat_hud.commander_tool_clicked.is_connected(_on_commander_tool_clicked):
			combat_hud.commander_tool_clicked.disconnect(_on_commander_tool_clicked)
		if combat_hud.striker_portrait_clicked.is_connected(_on_striker_portrait_clicked):
			combat_hud.striker_portrait_clicked.disconnect(_on_striker_portrait_clicked)

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

func _on_projectile_wall_hit(_wall: Object, hit_pos: Vector3, penetrated: bool, wall_destroyed: bool) -> void:
	if health_bar_overlay == null:
		return
	if wall_destroyed:
		health_bar_overlay.spawn_floating_text(hit_pos + Vector3(0.0, 1.2, 0.0), "💥 BREACH!", Color(1.0, 0.85, 0.2), true)
	elif not penetrated:
		health_bar_overlay.spawn_floating_text(hit_pos + Vector3(0.0, 0.9, 0.0), "🧱 BLOCKED", Color(0.85, 0.72, 0.52), false)
