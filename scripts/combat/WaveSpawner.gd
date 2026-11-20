# scripts/combat/WaveSpawner.gd
class_name WaveSpawner
extends Node

signal wave_started(wave_index: int, enemy_count: int)
signal wave_cleared(wave_index: int)

var current_wave: int = 0
var alive_enemies: int = 0

## Sets the active alive enemy count, clamped to >= 0.
func register_enemy_count(count: int) -> void:
	alive_enemies = maxi(0, count)

## Decrements alive enemy count and emits wave_cleared when the wave reaches 0 enemies.
func register_enemy_killed() -> void:
	if alive_enemies <= 0:
		return
	alive_enemies = maxi(0, alive_enemies - 1)
	if alive_enemies == 0:
		wave_cleared.emit(current_wave)

## Starts a wave with the given index and enemy count and emits wave_started.
func start_wave(wave_index: int, enemy_count: int = 0) -> void:
	current_wave = wave_index
	register_enemy_count(enemy_count)
	wave_started.emit(wave_index, alive_enemies)

## Returns true when no alive enemies remain in the current wave.
func is_wave_complete() -> bool:
	return alive_enemies == 0

## Returns the active wave index.
func get_current_wave() -> int:
	return current_wave
