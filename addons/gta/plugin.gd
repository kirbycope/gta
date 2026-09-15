@tool
extends EditorPlugin
## Godot Tim's Automobile. The scripts register their class names on their own; enabling the plugin only puts
## the cars in the Create New Node dialog under their own names.
##
## The [Vehicle] base is not here on purpose: it is a chassis to build a car on, not a car, so there is
## nothing to be gained by dropping a bare one into a scene.


## These paths are relative to this script, so they are the one place in the
## addon a search for "res://" will not find. They were missed when each game
## moved into a folder of its own, and because nothing but the editor loads this
## script, neither the tests nor CI noticed: the addon simply failed to enable
## the moment a project was opened.
func _enter_tree() -> void:
	add_custom_type("GtaCar", "VehicleBody3D", preload("gta/scripts/gta_car.gd"), null)
	add_custom_type("TwCar", "VehicleBody3D", preload("tw/scripts/tw_car.gd"), null)
	add_custom_type("RlCar", "VehicleBody3D", preload("rl/scripts/rl_car.gd"), null)
	add_custom_type("MkCar", "VehicleBody3D", preload("mk/scripts/mk_car.gd"), null)


func _exit_tree() -> void:
	remove_custom_type("GtaCar")
	remove_custom_type("TwCar")
	remove_custom_type("RlCar")
	remove_custom_type("MkCar")
