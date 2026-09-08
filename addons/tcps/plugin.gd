@tool
extends EditorPlugin
## Tim Cope's Pro Skater. The scripts register their class names on their own; enabling the plugin only puts
## the board in the Create New Node dialog under its own name.


func _enter_tree() -> void:
	add_custom_type("Skateboard", "Node3D", preload("scripts/skateboard.gd"), null)


func _exit_tree() -> void:
	remove_custom_type("Skateboard")
