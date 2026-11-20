# scripts/hub/CameraModeState.gd
class_name CameraModeState
extends RefCounted

enum CameraMode { FPS, TPS }

var current_mode: CameraMode = CameraMode.TPS

func toggle() -> CameraMode:
	if current_mode == CameraMode.TPS:
		current_mode = CameraMode.FPS
	else:
		current_mode = CameraMode.TPS
	return current_mode

func is_fps() -> bool:
	return current_mode == CameraMode.FPS

func is_tps() -> bool:
	return current_mode == CameraMode.TPS
