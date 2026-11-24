# scripts/combat/CombatUnit.gd
class_name CombatUnit
extends CharacterBody3D

const DamageResolverScript := preload("res://scripts/combat/DamageResolver.gd")

signal hp_changed(current: int, max_val: int)
signal unit_died(unit: CombatUnit)
signal order_completed(unit: CombatUnit)

var unit_data: StudentData = null
var current_hp: int = 1000
var max_hp: int = 1000
var atk: int = 100
var def: int = 50
var speed: float = 5.0
var attack_range: float = 10.0
var penetration_power: int = 0
var wall_damage: int = 18
var weapon_class: String = "AR" # "SG", "SR", "AR", "ARTILLERY", "HG"
var attack_cooldown: float = 1.2
var projectile_speed: float = 24.0
var frontal_shield_ratio: float = 0.0
var facing_dir: Vector3 = Vector3(0.0, 0.0, -1.0)
var is_alive: bool = true
var is_holding_fire: bool = false
var is_aoe_attacker: bool = false
var basic_aoe_radius: float = 2.6

var has_player_order: bool = false
var current_order_type: String = ""
var order_target_position: Vector3 = Vector3.ZERO
var order_target_node: Node3D = null

var damage_resolver: DamageResolverScript = null

func _init() -> void:
	damage_resolver = DamageResolverScript.new()

## Initializes unit stats and state from a StudentData resource.
func setup(data: StudentData) -> void:
	if data == null:
		return
	unit_data = data
	max_hp = maxi(1, data.base_hp)
	current_hp = max_hp
	atk = data.base_atk
	def = data.base_def
	speed = data.base_speed
	attack_range = data.attack_range
	is_alive = true
	is_holding_fire = false
	has_player_order = false
	current_order_type = ""
	order_target_position = Vector3.ZERO
	order_target_node = null

## Updates planar XZ facing_dir toward target_pos and rotates VisualRoot/FacingPivot if present.
func update_facing_toward(target_pos: Vector3) -> void:
	var diff := Vector2(target_pos.x - position.x, target_pos.z - position.z)
	if diff.length() <= 0.05:
		return
	var dir2: Vector2 = diff.normalized()
	facing_dir = Vector3(dir2.x, 0.0, dir2.y)
	var pivot := get_node_or_null("VisualRoot/FacingPivot") as Node3D
	if pivot != null:
		pivot.rotation.y = atan2(dir2.x, dir2.y)

## Applies direct damage, mitigating frontal attacks when frontal_shield_ratio > 0 and penetration < 2.
func take_directional_damage(
	amount: int,
	source: Object = null,
	attacker_pos: Vector3 = Vector3.INF,
	incoming_penetration: int = 0
) -> Dictionary:
	if not is_alive or amount <= 0:
		return {"damage": 0, "shielded": false}
	var final_amount: int = amount
	var was_shielded: bool = false
	if frontal_shield_ratio > 0.0 and incoming_penetration < 2 and attacker_pos != Vector3.INF:
		var my_pos: Vector3 = global_position if is_inside_tree() else position
		var to_atk := Vector2(attacker_pos.x - my_pos.x, attacker_pos.z - my_pos.z)
		var f_xz := Vector2(facing_dir.x, facing_dir.z)
		if to_atk.length() > 0.05 and f_xz.length() > 0.05:
			if f_xz.normalized().dot(to_atk.normalized()) >= 0.35:
				final_amount = maxi(1, int(round(float(amount) * clampf(1.0 - frontal_shield_ratio, 0.1, 1.0))))
				was_shielded = true
	var dealt: int = take_damage(final_amount, source)
	return {"damage": dealt, "shielded": was_shielded}

## Applies direct damage clamped to 0, emits hp_changed, and triggers death at 0 HP.
func take_damage(amount: int, _source: Object = null) -> int:
	if not is_alive or amount <= 0:
		return 0
	var prev_hp: int = current_hp
	current_hp = maxi(0, current_hp - amount)
	var actual_damage: int = prev_hp - current_hp
	hp_changed.emit(current_hp, max_hp)
	if current_hp == 0:
		die()
	return actual_damage

## Mitigates raw attacker ATK against this unit's DEF and buffs, then applies damage.
func take_raw_hit(attacker_atk: int, active_buffs: Array = [], source: Object = null) -> int:
	if not is_alive:
		return 0
	var raw_dmg: int = damage_resolver.calculate_damage_raw(attacker_atk, def)
	var final_dmg: int = damage_resolver.apply_buff_modifiers(raw_dmg, active_buffs)
	return take_damage(final_dmg, source)

## Restores HP up to max_hp, emitting hp_changed and returning actual HP restored.
func heal(amount: int) -> int:
	if not is_alive or amount <= 0:
		return 0
	var prev_hp: int = current_hp
	current_hp = mini(max_hp, current_hp + amount)
	var restored: int = current_hp - prev_hp
	hp_changed.emit(current_hp, max_hp)
	return restored

## Marks the unit as dead, clears active orders, and emits unit_died.
func die() -> void:
	if not is_alive:
		return
	is_alive = false
	is_holding_fire = false
	has_player_order = false
	current_order_type = ""
	order_target_node = null
	unit_died.emit(self)

## Clears the active player order and emits order_completed.
func clear_player_order() -> void:
	has_player_order = false
	current_order_type = ""
	order_target_node = null
	order_completed.emit(self)

## Clears player order when HP falls below threshold so Role AI can take over survival.
func check_emergency_override(hp_threshold_ratio: float = 0.10) -> bool:
	if not is_alive:
		return false
	var hp_ratio: float = float(current_hp) / float(maxi(1, max_hp))
	if hp_ratio < hp_threshold_ratio:
		has_player_order = false
		return true
	return false

## Receives a MOVE order dispatched by UnitSelectionManager.
func receive_move_order(target: Vector3) -> void:
	has_player_order = true
	current_order_type = "MOVE"
	order_target_position = target
	order_target_node = null

## Receives a COVER order dispatched by UnitSelectionManager.
func receive_cover_order(cover_point: Node3D) -> void:
	has_player_order = true
	current_order_type = "COVER"
	order_target_node = cover_point
	if cover_point != null and is_instance_valid(cover_point):
		order_target_position = cover_point.global_position if cover_point.is_inside_tree() else cover_point.position

## Receives a FOCUS_FIRE order dispatched by UnitSelectionManager.
func receive_focus_fire(enemy: Node3D) -> void:
	is_holding_fire = false
	has_player_order = true
	current_order_type = "FOCUS_FIRE"
	order_target_node = enemy

## Receives a HOLD_POSITION order dispatched by UnitSelectionManager.
func receive_hold_position() -> void:
	has_player_order = true
	current_order_type = "HOLD_POSITION"
	order_target_node = null

## Receives a non-blocking HOLD_FIRE stance: prevents firing without locking movement.
func receive_hold_fire() -> void:
	is_holding_fire = true
	has_player_order = false
	current_order_type = "HOLD_FIRE"
	order_target_node = null

## Explicitly sets non-blocking Hold Fire mode (movement and zone orders still apply).
func set_hold_fire(enabled: bool) -> void:
	is_holding_fire = enabled

## Toggles non-blocking Hold Fire mode and returns the new state.
func toggle_hold_fire() -> bool:
	is_holding_fire = not is_holding_fire
	return is_holding_fire
