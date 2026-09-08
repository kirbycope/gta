class_name EquipmentEntry
extends Resource
## A saved weapon or tool: the [Equipment] scene to instance and whether it was on the skeleton or stowed.

@export_file("*.tscn", "*.scn") var scene_path: String = ""
@export var equipped: bool = false
