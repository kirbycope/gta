@tool
extends EditorPlugin
## Godot Tim's Automobile. The scripts register their class names on their own; enabling the plugin only puts
## the vehicle in the Create New Node dialog under its own name.


func _enter_tree() -> void:
	add_custom_type("Vehicle", "VehicleBody3D", preload("scripts/vehicle.gd"), null)


func _exit_tree() -> void:
	remove_custom_type("Vehicle")
