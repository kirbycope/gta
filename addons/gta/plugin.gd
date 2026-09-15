@tool
extends EditorPlugin
## Godot Tim's Automobile. The scripts register their class names on their own; enabling the plugin only puts
## the cars in the Create New Node dialog under their own names.
##
## The [Vehicle] base is not here on purpose: it is a chassis to build a car on, not a car, so there is
## nothing to be gained by dropping a bare one into a scene.


func _enter_tree() -> void:
	add_custom_type("GtaCar", "VehicleBody3D", preload("scripts/gta_car.gd"), null)
	add_custom_type("RlCar", "VehicleBody3D", preload("scripts/rocket_car.gd"), null)
	add_custom_type("TwCar", "VehicleBody3D", preload("scripts/tm2_car.gd"), null)


func _exit_tree() -> void:
	remove_custom_type("GtaCar")
	remove_custom_type("RlCar")
	remove_custom_type("TwCar")
