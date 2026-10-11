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

const DEMO: PackedScene = preload("res://addons/gta/tw/scenes/demo.tscn")
const SETTLE_FRAMES: int = 12
const CAR_SCENES: String = "res://addons/gta/tw/scenes/cars"

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
	# the extracted level imports as a few meshes of up to two hundred surfaces each, so the
	# geometry is counted in faces and the textures in surfaces
	var faces: int = 0
	var textured: int = 0
	for node: Node in arena.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		faces += mesh.get_faces().size() / 3
		for i: int in mesh.get_surface_count():
			var material: BaseMaterial3D = mesh.surface_get_material(i) as BaseMaterial3D
			if material != null and material.albedo_texture != null:
				textured += 1
	assert_gt(faces, 10000, "and it is a level, not an empty node: %d faces" % faces)
	assert_gt(textured, 300, "drawn with the disc's own textures: %d textured surfaces" % textured)
	assert_false(arena.find_children("*", "StaticBody3D", true, false).is_empty(),
		"with collision for the cars to drive on")


func test_there_is_floor_under_every_waypoint() -> void:
	# the AI path is the game's own, so wherever it goes there has to be ground: a hole under it is a
	# piece of the level the extractor lost, and a car that follows the path into it is gone
	var space: PhysicsDirectSpaceState3D = demo.get_world_3d().direct_space_state
	var holes: Array = []
	for p: Vector3 in demo.waypoints.points:
		var query := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 5.0, p + Vector3.DOWN * 10.0)
		if space.intersect_ray(query).is_empty():
			holes.append(p)
	assert_eq(holes.size(), 0, "Waypoints with nothing under them: %s" % [holes])


func test_the_field_starts_apart_on_its_wheels() -> void:
	# the first waypoint of Los Angeles is the arena's origin, inside a building, and the field used
	# to spawn into it in a heap; a spawn point is passed over when something stands on it or another
	# car already started there
	await wait_physics_frames(60)
	var cars: Array = get_tree().get_nodes_in_group(&"tw_cars")
	for i: int in cars.size():
		var car: TwCar = cars[i]
		assert_eq(car.wheels_in_contact(), 4, "%s starts on all four wheels" % car.name)
		for j: int in range(i + 1, cars.size()):
			var other: TwCar = cars[j]
			assert_gt(car.global_position.distance_to(other.global_position), 10.0,
				"%s and %s start apart" % [car.name, other.name])


func test_a_car_outside_the_arena_is_put_back() -> void:
	# the game's arenas are fenced and this port has no fence, so a car that has driven far from
	# the AI path is treated like one that fell out of the world
	var car: TwCar = demo.player_car
	car.global_position = Vector3(900.0, 5.0, 900.0)
	await wait_physics_frames(3)
	assert_true(demo._is_near_the_course(car.global_position), "Back within reach of the course")


func test_new_york_is_the_rooftop_level_with_a_scene_of_its_own() -> void:
	# the level that used to be here under Los Angeles's name
	var packed: PackedScene = load("res://addons/gta/tw/scenes/new_york.tscn") as PackedScene
	assert_not_null(packed)
	var root: Node3D = packed.instantiate() as Node3D
	assert_eq(root.get("level_name"), "New York")
	assert_true(String(root.get("level_waypoints")).ends_with("new_york_waypoints.tres"))
	var arena: Node3D = root.get_node_or_null(^"Arena") as Node3D
	assert_not_null(arena, "New York's arena is a node in its scene")
	var faces: int = 0
	for node: Node in arena.find_children("*", "MeshInstance3D", true, false):
		faces += (node as MeshInstance3D).mesh.get_faces().size() / 3
	assert_gt(faces, 10000, "and it is the rooftop level, not an empty node: %d faces" % faces)
	root.free()


func test_every_roster_car_has_a_scene_of_its_own_with_its_model_in_it() -> void:
	for key: StringName in TwRoster.CARS:
		var path: String = "%s/%s.tscn" % [CAR_SCENES, key]
		if not ResourceLoader.exists(path):
			# outlaw and shadow have no ripped model in the assets, and say so rather than fake one
			assert_true(key in [&"outlaw", &"shadow"], "%s has no scene and is not one of the two unripped cars" % key)
			continue
		var car: TwCar = (load(path) as PackedScene).instantiate() as TwCar
		assert_not_null(car, "%s is a TwCar scene" % key)
		assert_eq(car.car, key, "and carries its own roster key")
		var mesh: MeshInstance3D = car.get_node_or_null(^"Model/Mesh") as MeshInstance3D
		assert_not_null(mesh, "%s has its model as a node under Model" % key)
		assert_not_null(mesh.mesh, "with the ripped mesh set on it")
		car.free()


func test_the_field_is_spawned_from_those_scenes_with_a_person_on_roadkill() -> void:
	assert_null(demo.get_node_or_null(^"Player"), "No Player node in the demo")
	var cars: Array = get_tree().get_nodes_in_group(&"tw_cars")
	assert_eq(cars.size(), 7, "Roadkill and six opponents")
	assert_not_null(demo.player_car)
	assert_not_null(demo.player_car.get_node_or_null(^"HumanDriver"), "The person is a HumanDriver on Roadkill")
	for car: TwCar in cars:
		assert_not_null(car.get_node_or_null(^"Model/Mesh"), "%s came from its scene, model and all" % car.name)
		if car == demo.player_car:
			assert_false((car.get_node(^"TwAi") as TwAi).enabled, "Roadkill's brain is off")
		else:
			assert_true((car.get_node(^"TwAi") as TwAi).enabled, "%s drives itself" % car.name)


func test_each_car_s_materials_are_editable_resources_that_draw_both_sides() -> void:
	# the fix for the see-through rips lives in the scene, not in code: an override per surface
	var checked: int = 0
	for car: TwCar in get_tree().get_nodes_in_group(&"tw_cars"):
		var mesh: MeshInstance3D = car.get_node(^"Model/Mesh") as MeshInstance3D
		for i: int in mesh.mesh.get_surface_count():
			var material: StandardMaterial3D = mesh.get_surface_override_material(i) as StandardMaterial3D
			assert_not_null(material, "%s surface %d has a material of its own in its scene" % [car.name, i])
			assert_eq(material.cull_mode, BaseMaterial3D.CULL_DISABLED,
				"%s surface %d is drawn on both sides" % [car.name, i])
			assert_not_null(material.albedo_texture, "and keeps the rip's texture")
			checked += 1
	assert_gt(checked, 0, "There were surfaces to check")
