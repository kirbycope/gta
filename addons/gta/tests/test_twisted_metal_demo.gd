extends GutTest

## Purpose: the Twisted Metal demo as a whole, and the shape that makes it editable. The arena is a
## node in the scene, an instance of the level, that the demo script prepares rather than builds. Each
## car is its own scene under scenes/tm2/ with its mesh and its materials embedded, so a material can
## be changed in the inspector; the demo spawns those scenes onto the arena with a person's hand on
## one of them.
##
## The materials are drawn on both sides because the rips are wound mostly inside out, 64 to 86
## percent of each car's triangles facing inward, and a culled back face is a hole you see through.
## That is a property of a resource in the car's scene, where it is yours to change, and the last test
## reads it from there.
##
## Each test loads the whole level, which is why there are few of them.

const DEMO: PackedScene = preload("res://addons/gta/scenes/demo/twisted_metal.tscn")
const SETTLE_FRAMES: int = 12
const CAR_SCENES: String = "res://addons/gta/scenes/tm2"

var demo: Node3D


func before_each() -> void:
	demo = DEMO.instantiate() as Node3D
	add_child_autofree(demo)
	await wait_physics_frames(SETTLE_FRAMES)


func test_the_arena_is_a_node_in_the_scene_with_geometry_and_collision() -> void:
	# a node, not a runtime build: it is there before the script runs, and selectable in the editor
	var packed_root: Node = DEMO.instantiate()
	assert_not_null(packed_root.get_node_or_null(^"Arena"), "Arena is a child in the scene file itself")
	packed_root.free()
	var arena: Node3D = demo.get_node_or_null(^"Arena") as Node3D
	assert_not_null(arena)
	# the extracted level imports as one mesh with one surface, so the geometry is counted in faces
	var faces: int = 0
	for node: Node in arena.find_children("*", "MeshInstance3D", true, false):
		faces += (node as MeshInstance3D).mesh.get_faces().size() / 3
	assert_gt(faces, 1000, "and it is a level, not an empty node: %d faces" % faces)
	assert_false(arena.find_children("*", "StaticBody3D", true, false).is_empty(),
		"with collision for the cars to drive on")


func test_every_roster_car_has_a_scene_of_its_own_with_its_model_in_it() -> void:
	for key: StringName in Tm2Roster.CARS:
		var path: String = "%s/%s.tscn" % [CAR_SCENES, key]
		if not ResourceLoader.exists(path):
			# outlaw and shadow have no ripped model in the assets, and say so rather than fake one
			assert_true(key in [&"outlaw", &"shadow"], "%s has no scene and is not one of the two unripped cars" % key)
			continue
		var car: Tm2Car = (load(path) as PackedScene).instantiate() as Tm2Car
		assert_not_null(car, "%s is a Tm2Car scene" % key)
		assert_eq(car.car, key, "and carries its own roster key")
		var mesh: MeshInstance3D = car.get_node_or_null(^"Model/Mesh") as MeshInstance3D
		assert_not_null(mesh, "%s has its model as a node under Model" % key)
		assert_not_null(mesh.mesh, "with the ripped mesh set on it")
		car.free()


func test_the_field_is_spawned_from_those_scenes_with_a_person_on_roadkill() -> void:
	assert_null(demo.get_node_or_null(^"Player"), "No Player node in the demo")
	var cars: Array = get_tree().get_nodes_in_group(&"tm2_cars")
	assert_eq(cars.size(), 7, "Roadkill and six opponents")
	assert_not_null(demo.player_car)
	assert_not_null(demo.player_car.get_node_or_null(^"HumanDriver"), "The person is a HumanDriver on Roadkill")
	for car: Tm2Car in cars:
		assert_not_null(car.get_node_or_null(^"Model/Mesh"), "%s came from its scene, model and all" % car.name)
		if car == demo.player_car:
			assert_false((car.get_node(^"AiDriver") as AiDriver).enabled, "Roadkill's brain is off")
		else:
			assert_true((car.get_node(^"AiDriver") as AiDriver).enabled, "%s drives itself" % car.name)


func test_each_car_s_materials_are_editable_resources_that_draw_both_sides() -> void:
	# the fix for the see-through rips lives in the scene, not in code: an override per surface
	var checked: int = 0
	for car: Tm2Car in get_tree().get_nodes_in_group(&"tm2_cars"):
		var mesh: MeshInstance3D = car.get_node(^"Model/Mesh") as MeshInstance3D
		for i: int in mesh.mesh.get_surface_count():
			var material: StandardMaterial3D = mesh.get_surface_override_material(i) as StandardMaterial3D
			assert_not_null(material, "%s surface %d has a material of its own in its scene" % [car.name, i])
			assert_eq(material.cull_mode, BaseMaterial3D.CULL_DISABLED,
				"%s surface %d is drawn on both sides" % [car.name, i])
			assert_not_null(material.albedo_texture, "and keeps the rip's texture")
			checked += 1
	assert_gt(checked, 0, "There were surfaces to check")
