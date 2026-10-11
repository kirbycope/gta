extends Node3D
## The Twisted Metal 2 demo: a Los Angeles arena, you already at the wheel, and
## a field of opponents driving the level and fighting each other as well as
## you. There is no [Player] here: a [HumanDriver] under your car fills the same
## pad the opponents' [TwAi] fills, and there is nothing to get out of.
##
## The arena is a node in the scene, an instance of the level's glTF named
## [code]Arena[/code], so it can be looked at and selected in the editor. The
## two demo scenes differ by which glTF that is and at what scale, which is what
## a scene is for. This script only prepares the node it finds: it strips the
## painted backdrop, gives a level that arrived without collision a trimesh, and
## measures where out of the world is.
##
## The cars are their own scenes under [code]scenes/tm2/[/code], one per ripped
## model, each with its mesh and its materials embedded where they can be edited.
## They are spawned here at run time because their spawn points are found by
## dropping rays onto the arena's collision, which needs the game running; open
## a car's scene to change its look.
##
## [code]demo.tscn[/code] plays the arena pulled out of the game disc by
## [code]tools/extract_tm2.py[/code], with the AI on the level's own waypoints;
## a level without waypoints of its own has them sampled off its surface instead.

const ASSETS: String = "res://addons/gta/tw/assets"
const CAR_SCENES: String = "res://addons/gta/tw/scenes/cars" ## One scene per ripped car, named by roster key.

## Who the player drives, and who they are up against. Keys are [TwRoster] cars.
const PLAYER_CAR: StringName = &"roadkill"
const OPPONENTS: Array[StringName] = [
	&"sweet_tooth", &"warthog", &"spectre", &"thumper", &"twister", &"minion",
]

const SPAWN_HEIGHT: float = 2.0 ## Drop the cars in just above the roof.
const SPAWN_CLEARANCE: Vector3 = Vector3(6.0, 3.0, 8.0) ## The box a spawn point has to have empty around it.
const SPAWN_SPACING: float = 15.0 ## Metres between one car's spawn point and the next.
const RAY_TOP: float = 150.0 ## How far above a waypoint to start looking for the roof.
const RAY_BOTTOM: float = 150.0 ## And how far below it to give up.
const OPPONENT_SPACING: int = 9 ## Rooftop waypoints between one car and the next.
const FELL_OUT_MARGIN: float = 40.0 ## How far under the arena a car has to be to count as lost.
const FENCE_DISTANCE: float = 120.0 ## How far from the AI path a car may stray before it is outside the arena; a turbo run covers it in two seconds.
const FLOOR_HEIGHT: float = -4.0 ## The invisible floor, just under Los Angeles's lowest street (-2.5 m).
const WEDGED_SPEED: float = 0.5 ## Slower than this on the throttle or the brake is not moving.
const WEDGED_SECONDS: float = 6.0 ## How long a car may ask for speed and get none before it is put back.
const BACKDROP_RATIO: float = 8.0 ## A mesh this many times wider than its neighbours is scenery, not arena.
const BACKDROP_TALLNESS: float = 0.15 ## And it only counts as scenery if it rises this much of its own width.
const SPAWN_TIER_BAND: float = 3.0 ## Height bins the AI path is sorted into; the field starts on the fullest one, give or take a bin.
const SPAWN_STEP: float = 0.4 ## The most the ground may vary under a spawning car's four corners, in metres.
const SAMPLE_STEPS: int = 26 ## Grid resolution across the widest side when sampling a level.
const SAMPLE_MIN_SPACING: float = 3.0
const SAMPLE_MAX_SPACING: float = 30.0
const SAMPLE_FLATNESS: float = 0.85 ## How level a surface has to be to be worth driving on.
const SAMPLE_LIMIT: int = 600 ## Stop sampling past this many points.

@export_group("Level")
## The arena's own AI path. Leave empty for a level that has none and the
## drivable surface is sampled for waypoints instead.
@export_file("*.tres") var level_waypoints: String = ASSETS + "/los_angeles_waypoints.tres"
@export var level_name: String = "Los Angeles"

@onready var hint: Label = $HUD/Hint
@onready var ui: TwUi = get_node_or_null(^"TwUi")
@onready var arena: Node3D = get_node_or_null(^"Arena") ## The level, placed in the scene as a node.

var waypoints: TwWaypoints
var player_car: TwCar

var _roof: PackedInt32Array = PackedInt32Array() ## Indices on the rooftop tier.
var _spawned_at: Array[Vector3] = [] ## Where the field has started, so no two cars share a point.
var _floor: StaticBody3D ## The invisible floor under the level; see [method _give_floor].
var _stuck_for: Dictionary = {} ## Car to seconds it has asked for speed and got none.
var _fell_out_y: float = -INF ## Set from the arena's own bounds once it is loaded.


func _ready() -> void:
	if not _prepare_level():
		return
	var flat: TwWaypoints = null
	if not level_waypoints.is_empty() and ResourceLoader.exists(level_waypoints):
		flat = load(level_waypoints) as TwWaypoints
	# the arena's collision only exists once physics has seen it, and the spawn
	# points are found by dropping a ray onto that collision
	await get_tree().physics_frame
	waypoints = _ground_waypoints(flat) if flat != null else _sample_waypoints()
	_roof = _roof_waypoints()
	_spawn_cars()
	# deferred so the HUD is listening when the driver's car starts talking
	_hand_over_the_wheel.call_deferred()


## Make the [code]Arena[/code] node ready to drive on. Returns false, with the
## reason on screen, when the scene has no arena, which is what a checkout that
## has not run the extractor gets: the glTF is missing and the instance is empty.
func _prepare_level() -> bool:
	if arena == null or arena.find_children("*", "MeshInstance3D", true, false).is_empty():
		hint.text = "Twisted Metal 2 assets are missing.\n\nBuild them from your own copy of the game:\n"\
			+ "  python tools/extract_tm2.py \"Twisted Metal 2 (USA) (Track 01).bin\""
		return false
	_strip_backdrop(arena)
	_give_collision(arena)
	_give_floor()
	_fell_out_y = _arena_bounds(arena).position.y - FELL_OUT_MARGIN
	return true


## An invisible floor at street level under the whole level. The drawn arena has gaps where the
## kerbs between the plateau and the streets would be: the original game's ground is a height
## lookup from the TERRAIN files, not the drawn polygons, so its cars never fell through them, and
## those tables do not land on the drawn surface closely enough to be used as collision here. A car
## that drops through a gap lands on the street instead of leaving the world.
func _give_floor() -> void:
	_floor = StaticBody3D.new()
	_floor.name = "Floor"
	var shape: CollisionShape3D = CollisionShape3D.new()
	var plane: WorldBoundaryShape3D = WorldBoundaryShape3D.new()
	plane.plane = Plane(Vector3.UP, FLOOR_HEIGHT)
	shape.shape = plane
	_floor.add_child(shape)
	add_child(_floor)


## Both of these maps paint their distant scenery as a handful of enormous
## pieces wrapped round the arena, which swamp it in an engine that has its own
## sky. Anything far larger than the meshes around it goes.
func _strip_backdrop(level: Node3D) -> void:
	var meshes: Array[Node] = level.find_children("*", "MeshInstance3D", true, false)
	if meshes.size() < 4:
		return
	var widths: Array[float] = []
	for node: Node in meshes:
		var size: Vector3 = (node as MeshInstance3D).get_aabb().size
		widths.append(maxf(size.x, size.z))
	var sorted: Array[float] = widths.duplicate()
	sorted.sort()
	var median: float = sorted[sorted.size() / 2]
	if median <= 0.0:
		return
	for i: int in meshes.size():
		if widths[i] <= median * BACKDROP_RATIO:
			continue
		# A painted sky wraps up and around, so it is tall as well as wide. The
		# ground the arena sits on is just as wide and must be kept, or the
		# cars drop straight through the streets.
		var size: Vector3 = (meshes[i] as MeshInstance3D).get_aabb().size
		if size.y < widths[i] * BACKDROP_TALLNESS:
			continue
		# freed now rather than queued, because the arena is measured for
		# its scale on the very next line
		meshes[i].get_parent().remove_child(meshes[i])
		meshes[i].free()


## The box the whole arena sits in, which is how far down is out of the world
## and where the waypoint sampler casts from.
func _arena_bounds(level: Node3D) -> AABB:
	var box: AABB = AABB()
	var first: bool = true
	for node: Node in level.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		var one: AABB = mesh.global_transform * mesh.get_aabb()
		box = one if first else box.merge(one)
		first = false
	return box


## The extracted arena carries Godot's -col import hint and arrives with a body
## of its own. A model from anywhere else does not, so one is built for it.
func _give_collision(level: Node3D) -> void:
	if not level.find_children("*", "StaticBody3D", true, false).is_empty():
		return
	for node: Node in level.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).create_trimesh_collision()


## Waypoints for a level that brought none: drop a grid of rays over it and
## keep the spots flat enough to drive on.
func _sample_waypoints() -> TwWaypoints:
	var result: TwWaypoints = TwWaypoints.new()
	var arena: Node3D = get_node_or_null(^"Arena") as Node3D
	if arena == null:
		return result
	var bounds: AABB = _arena_bounds(arena)
	if bounds.size == Vector3.ZERO:
		return result
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var points: PackedVector3Array = PackedVector3Array()
	var top: float = bounds.position.y + bounds.size.y + 10.0
	var bottom: float = bounds.position.y - 10.0
	# the step follows the size of the arena, so this works on a level of any
	# scale rather than only one the size of the extracted one
	var spacing: float = clampf(maxf(bounds.size.x, bounds.size.z) / float(SAMPLE_STEPS),
		SAMPLE_MIN_SPACING, SAMPLE_MAX_SPACING)
	var x: float = bounds.position.x
	while x <= bounds.position.x + bounds.size.x and points.size() < SAMPLE_LIMIT:
		var z: float = bounds.position.z
		while z <= bounds.position.z + bounds.size.z and points.size() < SAMPLE_LIMIT:
			var query := PhysicsRayQueryParameters3D.create(
				Vector3(x, top, z), Vector3(x, bottom, z))
			var hit: Dictionary = space.intersect_ray(query)
			if not hit.is_empty() and (hit["normal"] as Vector3).y >= SAMPLE_FLATNESS:
				points.append(hit["position"] as Vector3)
			z += spacing
		x += spacing
	result.points = points
	return result


## The waypoints on the level's main tier: the height most of the AI path runs at, give or take
## [constant SPAWN_TIER_BAND]. New York is two tiers, the rooftops and the street far below, and
## everyone starts on the rooftops, which is where Twisted Metal opens the round; Los Angeles is a
## plateau with streets a few metres below round its edge, and the field starts on the plateau.
func _roof_waypoints() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	if waypoints == null or waypoints.points.is_empty():
		return out
	var bins: Dictionary = {}
	for p: Vector3 in waypoints.points:
		var bin: int = floori(p.y / SPAWN_TIER_BAND)
		bins[bin] = int(bins.get(bin, 0)) + 1
	var fullest: int = 0
	for bin: int in bins:
		if int(bins[bin]) > int(bins.get(fullest, 0)):
			fullest = bin
	var tier: float = (float(fullest) + 0.5) * SPAWN_TIER_BAND
	for i: int in waypoints.points.size():
		if absf(waypoints.points[i].y - tier) <= SPAWN_TIER_BAND:
			out.append(i)
	return out


func _spawn_cars() -> void:
	player_car = _make_car(PLAYER_CAR, 0, false)
	for i: int in OPPONENTS.size():
		_make_car(OPPONENTS[i], i + 1, true)


## One car: its own scene under [constant CAR_SCENES], which carries its mesh,
## its materials and its roster key, plus for an opponent its [TwAi] switched
## on. A key with no scene falls back to the bare chassis so the field still
## fills, and says so.
func _make_car(car: StringName, waypoint: int, ai: bool) -> TwCar:
	var path: String = "%s/%s.tscn" % [CAR_SCENES, car]
	var scene: PackedScene = load(path) as PackedScene if ResourceLoader.exists(path) else null
	if scene == null:
		push_warning("No scene for %s at %s; spawning the bare chassis." % [car, path])
		scene = load("res://addons/gta/tw/scenes/tw_car.tscn") as PackedScene
	var vehicle: TwCar = scene.instantiate() as TwCar
	vehicle.name = String(car).to_pascal_case()
	# set before the car enters the tree, because the car and its combat node read the key in _ready
	vehicle.car = car
	var combat: TwCombat = vehicle.get_node_or_null(^"TwCombat") as TwCombat
	if combat != null:
		combat.car = car

	var driver: TwAi = vehicle.get_node_or_null(^"TwAi") as TwAi
	if driver != null:
		driver.enabled = ai
		driver.waypoints = waypoints
		driver.aggression = randf_range(0.45, 0.9)

	vehicle.position = _spawn_point(waypoint)
	add_child(vehicle)
	return vehicle


## The .PTS records carry only the ground plane, so each point is dropped onto
## the arena to give it a height. Points over a gap are left out: without this
## the opponents steer at a waypoint on a roof they are not standing on.
func _ground_waypoints(flat: TwWaypoints) -> TwWaypoints:
	if flat == null or flat.points.is_empty():
		return flat
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var grounded: PackedVector3Array = PackedVector3Array()
	for point: Vector3 in flat.points:
		var query := PhysicsRayQueryParameters3D.create(
			point + Vector3.UP * RAY_TOP, point + Vector3.DOWN * RAY_BOTTOM)
		# the invisible floor is not the arena: a point with only that under it is over a gap
		if _floor != null:
			query.exclude = [_floor.get_rid()]
		var hit: Dictionary = space.intersect_ray(query)
		if not hit.is_empty():
			grounded.append(hit["position"] as Vector3)
	var result: TwWaypoints = TwWaypoints.new()
	result.points = grounded if grounded.size() >= 3 else flat.points
	return result


## The level's waypoints are flat: the .PTS records only carry the ground
## plane, so the roof under each one is found by dropping a ray onto it.
## [param slot] counts along the rooftop waypoints, spaced out so the field
## does not start in a heap. The points are already on the level, so this only
## lifts the car clear of it. A point with something standing on it is passed
## over: Los Angeles's first waypoint is the arena's origin, which is inside a
## building, and seven cars spawned into it sat there wedged for the whole round.
func _spawn_point(slot: int) -> Vector3:
	if waypoints == null or waypoints.points.is_empty():
		return Vector3(0.0, SPAWN_HEIGHT, 0.0)
	var ring: PackedInt32Array = _roof
	if ring.is_empty():
		ring = PackedInt32Array(range(waypoints.points.size()))
	var start: int = (slot * OPPONENT_SPACING) % ring.size()
	# a spot of its own first; failing that any clear spot; failing that the slot's own point
	for apart: bool in [true, false]:
		for step: int in ring.size():
			var point: Vector3 = waypoints.points[ring[(start + step) % ring.size()]] + Vector3.UP * SPAWN_HEIGHT
			if _is_clear(point) and (not apart or _is_apart(point)):
				_spawned_at.append(point)
				return point
	return waypoints.points[ring[start]] + Vector3.UP * SPAWN_HEIGHT


## Whether a car-sized box at [param at] touches nothing and stands over level ground: the arena's
## outskirts are slabs at different heights, and a car dropped across a step sits on two wheels.
func _is_clear(at: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = SPAWN_CLEARANCE
	query.shape = box
	# the box stands on the ground the car will land on, a little above it, so a kerb or a prop
	# under the car's belly is seen as well as a wall at its roof
	query.transform = Transform3D(Basis(), at - Vector3.UP * (SPAWN_HEIGHT - 0.3 - SPAWN_CLEARANCE.y * 0.5))
	if not space.intersect_shape(query, 1).is_empty():
		return false
	var lowest: float = INF
	var highest: float = -INF
	for corner: Vector3 in [Vector3(1.0, 0.0, 2.0), Vector3(-1.0, 0.0, 2.0), Vector3(1.0, 0.0, -2.0), Vector3(-1.0, 0.0, -2.0)]:
		var ray := PhysicsRayQueryParameters3D.create(at + corner, at + corner + Vector3.DOWN * (SPAWN_HEIGHT + 2.0))
		if _floor != null:
			ray.exclude = [_floor.get_rid()]
		var hit: Dictionary = space.intersect_ray(ray)
		if hit.is_empty():
			return false
		lowest = minf(lowest, hit["position"].y)
		highest = maxf(highest, hit["position"].y)
	return highest - lowest <= SPAWN_STEP


## Whether [param at] is its own spot rather than one the field already started on: with the
## origin blocked, every car walked the ring to the same first clear point and the field spawned
## in a heap.
func _is_apart(at: Vector3) -> bool:
	for taken: Vector3 in _spawned_at:
		if taken.distance_to(at) < SPAWN_SPACING:
			return false
	return true


## Anything that leaves the arena is put back on it. Twisted Metal drops a car
## that falls out of the world back into play rather than losing it, and its
## arenas are fenced: a car that has driven further from the AI path than any
## part of the course lies is outside the fence this port does not have, and is
## put back the same way.
func _physics_process(delta: float) -> void:
	if waypoints == null or waypoints.points.is_empty():
		return
	for node: Node in get_tree().get_nodes_in_group(&"tw_cars"):
		var car: TwCar = node as TwCar
		if car == null:
			continue
		# under the level, or on the invisible floor in a pocket between a plateau's skirt and the
		# street, or outside the fence, or wedged (asking for speed and getting none for a while,
		# the same test MkRace uses): back onto the course
		var lost: bool = car.global_position.y <= maxf(_fell_out_y, FLOOR_HEIGHT + 1.0) \
			or not _is_near_the_course(car.global_position)
		if not lost:
			var trying: bool = (car._accelerate or car._brake or car.is_turbo_engaged) and not car.is_wrecked
			if trying and car.linear_velocity.length() < WEDGED_SPEED:
				_stuck_for[car] = float(_stuck_for.get(car, 0.0)) + delta
				lost = float(_stuck_for[car]) >= WEDGED_SECONDS
			else:
				_stuck_for[car] = 0.0
		if not lost:
			continue
		_stuck_for[car] = 0.0
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		car.global_position = _spawn_point(randi())
		car.global_rotation = Vector3.ZERO


## Whether [param at] is within [constant FENCE_DISTANCE] of the AI path, measured flat.
func _is_near_the_course(at: Vector3) -> bool:
	var nearest: float = INF
	for p: Vector3 in waypoints.points:
		nearest = minf(nearest, Vector2(p.x - at.x, p.z - at.z).length())
	return nearest <= FENCE_DISTANCE


## Put a person on the pad of Roadkill: a [HumanDriver] under it, the way the
## opponents have an [TwAi] under them.
func _hand_over_the_wheel() -> void:
	if not is_instance_valid(player_car) or player_car.get_node_or_null(^"HumanDriver") != null:
		return
	var driver: HumanDriver = HumanDriver.new()
	driver.name = "HumanDriver"
	driver.controls = get_node_or_null(^"Controls") as Controls
	player_car.add_child(driver)
	if is_instance_valid(ui):
		ui.watch(player_car)
	hint.text = ("Twisted Metal 2 - %s\nSpace accelerates, Shift brakes, Q is turbo, Ctrl with the stick is a hard turn.\n"
		+ "Left click fires the machine gun, right click the pickup, T cycles pickups.") % level_name
