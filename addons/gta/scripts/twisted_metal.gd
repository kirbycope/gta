extends Node3D
## The Twisted Metal 2 demo: the Los Angeles arena, the player already at the
## wheel, and a field of opponents driving the level's own waypoints and
## fighting each other as well as the player.
##
## The arena and the cars are built from your own copy of the game by
## [code]tools/extract_tm2.py[/code] and are not committed to this repository,
## so this scene loads them at run time and says so plainly when they are
## missing. That is why the level is assembled here rather than wired up as
## nodes in the scene the way the rest of the addon is.

const ASSETS: String = "res://addons/gta/assets/twistedmetal2"
const LEVEL_MESH: String = ASSETS + "/los_angeles.glb"
const WAYPOINTS: String = ASSETS + "/los_angeles_waypoints.tres"
const CARS_DIR: String = ASSETS + "/cars"
const TM2_CAR: PackedScene = preload("res://addons/gta/scenes/tm2_car.tscn")

## Who the player drives, and who they are up against. Keys are [Tm2Roster] cars.
const PLAYER_CAR: StringName = &"roadkill"
const OPPONENTS: Array[StringName] = [
	&"sweet_tooth", &"warthog", &"spectre", &"thumper", &"twister", &"minion",
]
## Folder under cars/ for each roster key, as the model rips are named.
const MODEL_DIRS: Dictionary = {
	&"axel": "axel", &"grasshopper": "grasshopper", &"hammerhead": "hammerhead",
	&"minion": "minion", &"mr_grimm": "mrgrimm", &"mr_slam": "mrslam",
	&"roadkill": "roadkill", &"spectre": "spectre", &"sweet_tooth": "sweettooth",
	&"thumper": "thumper", &"twister": "twister", &"warthog": "warthog",
}

const SPAWN_HEIGHT: float = 2.0 ## Drop the cars in just above the roof.
const RAY_TOP: float = 150.0 ## How far above a waypoint to start looking for the roof.
const RAY_BOTTOM: float = 150.0 ## And how far below it to give up.
const OPPONENT_SPACING: int = 9 ## Rooftop waypoints between one car and the next.
const FELL_OUT_Y: float = -40.0 ## Below the lowest part of the arena: put the car back.
const ROOF_TIER_BAND: float = 30.0 ## How far off the median height still counts as the rooftops.

@onready var hint: Label = $HUD/Hint

var waypoints: Tm2Waypoints
var player_car: Vehicle

var _roof: PackedInt32Array = PackedInt32Array() ## Indices on the rooftop tier.


func _ready() -> void:
	if not _build_level():
		return
	var flat: Tm2Waypoints = load(WAYPOINTS) as Tm2Waypoints if ResourceLoader.exists(WAYPOINTS) else null
	# the arena's collision only exists once physics has seen it, and the spawn
	# points are found by dropping a ray onto that collision
	await get_tree().physics_frame
	waypoints = _ground_waypoints(flat)
	_roof = _roof_waypoints()
	_spawn_cars()
	# the Player has to be in the tree with its own _ready done before it mounts
	_seat_the_player.call_deferred()


## Put the arena in the scene. Returns false, with the reason on screen, when
## the extractor has not been run yet.
func _build_level() -> bool:
	if not ResourceLoader.exists(LEVEL_MESH):
		hint.text = "Twisted Metal 2 assets are missing.\n\nBuild them from your own copy of the game:\n"\
			+ "  python tools/extract_tm2.py \"Twisted Metal 2 (USA) (Track 01).bin\""
		return false
	var scene: PackedScene = load(LEVEL_MESH) as PackedScene
	if scene == null:
		hint.text = "Could not load %s" % LEVEL_MESH
		return false
	var level: Node3D = scene.instantiate() as Node3D
	level.name = "LosAngeles"
	add_child(level)
	return true


## Los Angeles is two tiers, the rooftops and the street far below. Everyone
## starts on the rooftops, which is where Twisted Metal opens the round.
func _roof_waypoints() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	if waypoints == null or waypoints.points.is_empty():
		return out
	var heights: Array[float] = []
	for p: Vector3 in waypoints.points:
		heights.append(p.y)
	heights.sort()
	var median: float = heights[heights.size() / 2]
	for i: int in waypoints.points.size():
		if absf(waypoints.points[i].y - median) <= ROOF_TIER_BAND:
			out.append(i)
	return out


func _spawn_cars() -> void:
	player_car = _make_car(PLAYER_CAR, 0, false)
	for i: int in OPPONENTS.size():
		_make_car(OPPONENTS[i], i + 1, true)


## One car: the shared [code]tm2_car.tscn[/code] with its model, its roster
## stats and, for an opponent, its [AiDriver] switched on.
func _make_car(car: StringName, waypoint: int, ai: bool) -> Vehicle:
	var vehicle: Vehicle = TM2_CAR.instantiate() as Vehicle
	vehicle.name = String(car).to_pascal_case()

	# everything is set before the car enters the tree, because CarCombat reads
	# its roster stats in _ready and would otherwise keep the scene's defaults
	var mesh: Mesh = _load_model(car)
	if mesh != null:
		var model: Node3D = vehicle.get_node_or_null(^"Model") as Node3D
		if model != null:
			var instance: MeshInstance3D = MeshInstance3D.new()
			instance.mesh = mesh
			model.add_child(instance)

	var combat: CarCombat = vehicle.get_node_or_null(^"CarCombat") as CarCombat
	if combat != null:
		combat.car = car

	var driver: AiDriver = vehicle.get_node_or_null(^"AiDriver") as AiDriver
	if driver != null:
		driver.enabled = ai
		driver.waypoints = waypoints
		driver.aggression = randf_range(0.45, 0.9)

	vehicle.position = _spawn_point(waypoint)
	vehicle.add_to_group(&"tm2_cars")
	add_child(vehicle)
	return vehicle


## The .PTS records carry only the ground plane, so each point is dropped onto
## the arena to give it a height. Points over a gap are left out: without this
## the opponents steer at a waypoint on a roof they are not standing on.
func _ground_waypoints(flat: Tm2Waypoints) -> Tm2Waypoints:
	if flat == null or flat.points.is_empty():
		return flat
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var grounded: PackedVector3Array = PackedVector3Array()
	for point: Vector3 in flat.points:
		var query := PhysicsRayQueryParameters3D.create(
			point + Vector3.UP * RAY_TOP, point + Vector3.DOWN * RAY_BOTTOM)
		var hit: Dictionary = space.intersect_ray(query)
		if not hit.is_empty():
			grounded.append(hit["position"] as Vector3)
	var result: Tm2Waypoints = Tm2Waypoints.new()
	result.points = grounded if grounded.size() >= 3 else flat.points
	return result


## The level's waypoints are flat: the .PTS records only carry the ground
## plane, so the roof under each one is found by dropping a ray onto it.
## [param slot] counts along the rooftop waypoints, spaced out so the field
## does not start in a heap. The points are already on the level, so this only
## lifts the car clear of it.
func _spawn_point(slot: int) -> Vector3:
	if waypoints == null or waypoints.points.is_empty():
		return Vector3(0.0, SPAWN_HEIGHT, 0.0)
	if _roof.is_empty():
		var any: Vector3 = waypoints.points[slot % waypoints.points.size()]
		return any + Vector3.UP * SPAWN_HEIGHT
	var index: int = _roof[(slot * OPPONENT_SPACING) % _roof.size()]
	return waypoints.points[index] + Vector3.UP * SPAWN_HEIGHT


## The car models import as meshes, not scenes, and the rips keep their own
## capitalised file names, so the folder is scanned rather than guessed at.
func _load_model(car: StringName) -> Mesh:
	var folder: String = CARS_DIR + "/" + String(MODEL_DIRS.get(car, String(car)))
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return null
	for file: String in dir.get_files():
		if file.get_extension().to_lower() == "obj":
			return load(folder + "/" + file) as Mesh
	return null


## Anything that leaves the arena is put back on it. Twisted Metal drops a car
## that falls out of the world back into play rather than losing it.
func _physics_process(_delta: float) -> void:
	if waypoints == null or waypoints.points.is_empty():
		return
	for node: Node in get_tree().get_nodes_in_group(&"tm2_cars"):
		var car: Vehicle = node as Vehicle
		if car == null or car.global_position.y > FELL_OUT_Y:
			continue
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		car.global_position = _spawn_point(randi())
		car.global_rotation = Vector3.ZERO


func _seat_the_player() -> void:
	var player: Player = $Player as Player
	if player == null or not is_instance_valid(player_car):
		return
	player.global_position = player_car.global_position
	player.mount(player_car)
	hint.text = "Twisted Metal 2 - Los Angeles\nSpace accelerates, Shift brakes, the throw button handbrakes."
