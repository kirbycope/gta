extends GutTest

## Purpose: Mario Raceway is the demo's course, as nodes a fresh clone can race
## on. The racing line is the game's own path, closed; the grid sits on the
## road; the item boxes, trees and plants are where the game puts them; and the
## real course, when its model has been built from a rip, swaps in for the
## primitives without the line, the grid or the boxes moving.

const COURSE_SCENE: String = "res://addons/gta/mk/scenes/mario_raceway.tscn"

var course: MkCourse


func before_each() -> void:
	course = (load(COURSE_SCENE) as PackedScene).instantiate() as MkCourse
	add_child_autofree(course)


func test_the_racing_line_is_the_games_closed_path() -> void:
	var line: Path3D = course.get_node(^"RacingLine") as Path3D
	assert_true(line.curve.closed, "a lap comes back to the start")
	assert_gt(line.curve.point_count, 400, "the game's path has 499 points")
	var length: float = line.curve.get_baked_length()
	assert_between(length, 1050.0, 1150.0, "a lap of 9967 game units is 1107 m at a ninth of a metre each")


func test_the_road_follows_its_own_centre_line_not_the_racing_line() -> void:
	var road: CSGPolygon3D = course.get_node(^"Road") as CSGPolygon3D
	assert_eq(String(road.path_node), "../RoadLine")
	assert_eq(road.use_collision, not course.has_drop_in(), "the slab collides unless the real course is in")
	var polygon: PackedVector2Array = road.polygon
	var width: float = polygon[1].x - polygon[0].x
	assert_almost_eq(width, 11.0, 0.2, "the game's road is 99 units, 11 m, wide")


func test_the_grid_and_the_boxes_are_placed() -> void:
	assert_eq(course.get_node(^"StartGrid").get_child_count(), 8)
	assert_eq(course.get_node(^"ItemBoxes").get_child_count(), 15, "the game's fifteen item boxes")
	assert_gt(course.get_node(^"Walls").get_child_count(), 30, "the fences")
	assert_gt(course.get_node(^"Props").get_child_count(), 37, "27 trees, 10 piranha plants, the grandstand and the warp pipe")


func test_the_racing_line_runs_clear_of_the_primitive_walls_and_props() -> void:
	# the warp pipe is hollow and the grandstand stands beside the road, so nothing solid sits on the line
	await wait_physics_frames(6)
	var space: PhysicsDirectSpaceState3D = course.get_world_3d().direct_space_state
	var line: Path3D = course.get_node(^"RacingLine") as Path3D
	var road: Node = course.get_node(^"Road")
	var ground: Node = course.get_node(^"Ground")
	var blocked: Array[String] = []
	var count: int = int(line.curve.get_baked_length() / 5.0)
	for i: int in count:
		var point: Vector3 = line.to_global(line.curve.sample_baked(i * 5.0)) + Vector3.UP * 0.8
		var query := PhysicsPointQueryParameters3D.new()
		query.position = point
		for hit: Dictionary in space.intersect_point(query, 8):
			var collider: Node = hit["collider"] as Node
			if collider != road and collider != ground and not road.is_ancestor_of(collider):
				blocked.append("%s at %s" % [collider.name, point])
	assert_eq(blocked, [] as Array[String], "something solid sits on the racing line")


func test_every_grid_slot_has_road_under_it() -> void:
	# CSG collision arrives a few frames after the scene does, which is what MkRace waits for
	await wait_physics_frames(6)
	var space: PhysicsDirectSpaceState3D = course.get_world_3d().direct_space_state
	for slot: Node3D in course.get_node(^"StartGrid").get_children():
		var from: Vector3 = slot.global_position + Vector3.UP * 2.0
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from - Vector3.UP * 5.0))
		assert_false(hit.is_empty(), "%s is over the road" % slot.name)
		if not hit.is_empty():
			assert_true(course.is_ancestor_of(hit["collider"]), "%s stands on the course's own collision" % slot.name)


func test_the_ground_is_grass_to_the_kart() -> void:
	var ground: StaticBody3D = course.get_node(^"Ground") as StaticBody3D
	assert_eq(int(ground.get_meta(&"mk_surface")), MkConst.SURFACE_GRASS)


func test_the_real_course_swaps_in_when_its_model_is_there() -> void:
	if not ResourceLoader.exists(course.model):
		assert_false(course.has_drop_in(), "no model, so the primitives stay")
		assert_true((course.get_node(^"Road") as Node3D).visible)
		pending("tools/mk64_course.py has not been run here; the drop-in is untested")
		return
	assert_true(course.has_drop_in())
	assert_not_null(course.get_node_or_null(^"DropInModel"))
	assert_false((course.get_node(^"Road") as Node3D).visible, "the primitive road is hidden")
	assert_false((course.get_node(^"Road") as CSGPolygon3D).use_collision, "and no longer collides")
	var grass: Array[Node] = course.get_node(^"DropInModel").find_children("grass*", "StaticBody3D", true, false)
	assert_gt(grass.size(), 0, "the model carries its own grass collision")
	for body: Node in grass:
		assert_eq(int(body.get_meta(&"mk_surface")), MkConst.SURFACE_GRASS, "tagged for the kart's surface tables")
	assert_eq(course.get_node(^"StartGrid").get_child_count(), 8, "the grid is the scene's either way")


func test_a_model_that_is_not_there_is_left_alone_quietly() -> void:
	var bare: MkCourse = MkCourse.new()
	bare.model = "res://addons/gta/mk/assets/courses/nowhere.glb"
	add_child_autofree(bare)
	assert_false(bare.has_drop_in())
