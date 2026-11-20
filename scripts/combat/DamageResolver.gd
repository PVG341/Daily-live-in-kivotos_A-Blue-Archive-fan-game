# scripts/combat/DamageResolver.gd
class_name DamageResolver
extends RefCounted

## Computes raw damage from attacker ATK vs defender DEF with optional variance.
func calculate_damage_raw(atk_val: int, def_val: int, variance_factor: float = -1.0) -> int:
	var base: float = maxf(1.0, float(atk_val) - float(def_val) * 0.5)
	var factor: float = variance_factor if variance_factor > 0.0 else randf_range(0.9, 1.1)
	var result: float = base * factor
	return maxi(1, int(round(result)))

## Calculates final damage from attacker/defender objects and active buff modifiers.
func calculate_damage(attacker: Object, defender: Object, active_buffs: Array = []) -> int:
	var atk_val: int = _extract_stat(attacker, &"atk", &"base_atk")
	var def_val: int = _extract_stat(defender, &"def", &"base_def")
	var raw_damage: int = calculate_damage_raw(atk_val, def_val)
	return apply_buff_modifiers(raw_damage, active_buffs)

## Applies multiplicative percentage bonuses (ATK_UP, DMG_UP) and flat bonuses (FLAT_DMG).
func apply_buff_modifiers(base_damage: int, active_buffs: Array) -> int:
	var pct_bonus: float = 0.0
	var flat_bonus: float = 0.0
	for buff in active_buffs:
		if not (buff is Dictionary):
			continue
		var buff_type: String = String(buff.get("type", ""))
		var buff_value: float = float(buff.get("value", 0.0))
		match buff_type:
			"ATK_UP", "DMG_UP":
				pct_bonus += buff_value
			"FLAT_DMG":
				flat_bonus += buff_value
	var modified: float = float(base_damage) * (1.0 + pct_bonus) + flat_bonus
	return maxi(1, int(round(modified)))

func _extract_stat(obj: Object, primary_key: StringName, fallback_key: StringName) -> int:
	if obj == null or not is_instance_valid(obj):
		return 0
	if primary_key in obj:
		var val: Variant = obj.get(primary_key)
		if val != null:
			return int(val)
	if fallback_key in obj:
		var fallback_val: Variant = obj.get(fallback_key)
		if fallback_val != null:
			return int(fallback_val)
	return 0
