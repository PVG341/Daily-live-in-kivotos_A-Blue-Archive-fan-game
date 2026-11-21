# scripts/hub/FloorVisibilityZone.gd
class_name FloorVisibilityZone
extends Area3D

@export var target_node_paths: Array[NodePath] = []
@export var start_visible: bool = true

var is_zone_active: bool = true

func _ready() -> void:
	set_zone_active(start_visible)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

func _exit_tree() -> void:
	if body_entered.is_connected(_on_body_entered):
		body_entered.disconnect(_on_body_entered)
	if body_exited.is_connected(_on_body_exited):
		body_exited.disconnect(_on_body_exited)

func set_zone_active(active: bool) -> void:
	is_zone_active = active
	for np: NodePath in target_node_paths:
		if np.is_empty():
			continue
		var node := get_node_or_null(np) as Node3D
		if node != null:
			node.visible = active

func _on_body_entered(body: Node3D) -> void:
	if body is SenseiController:
		set_zone_active(true)

func _on_body_exited(body: Node3D) -> void:
	if body is SenseiController:
		set_zone_active(false)
