class_name MkRace
extends Node
## The race: a countdown, three laps, eight karts and a finishing order.
##
## The rules are Mario Kart 64's, from [code]src/racing/race_logic.c[/code]:
## [constant MkConst.RACERS] karts, [constant MkConst.LAPS] laps, and a
## position worked out by how far around the course each kart is rather than by
## who crossed what last. That last part is the one worth being careful about.
## The game ranks its karts by
## [code](2 - lapCount) * pathLength + distanceRemaining[/code], which is to say
## it measures progress along the course's own path, not straight line distance
## to the finish. A kart on the far side of a hairpin is not second because it
## happens to be near the line.
##
## [b]Checkpoints.[/b] Progress is measured against the course's [Path3D], which
## is the same curve the AI drives and the same one the course mesh is built
## around. Each kart's nearest offset along that curve, plus its lap, is its
## progress, and a lap only counts when the kart passes the line having gone the
## long way round; a kart reversing over the line does not gain one.
##
## [b]What this owns that the karts do not.[/b] The countdown, the order, and the
## world that fired items have to live in. A [MkItemSlot] that fires says so,
## and the race is what puts the projectile or the hazard in the scene, because
## the slot has no business knowing what a course looks like.

## How many physics frames to wait for the course's collision before giving up
## and saying so. Generous: a CSG road takes a handful, and a frozen grid is
## costing nothing while it waits.
const GROUND_WAIT_FRAMES: int = 240
const GROUND_RAY_UP: float = 3.0 ## How far above a kart to start looking for ground.
const GROUND_RAY_DOWN: float = 8.0 ## And how far below it to give up.
## How far above the line a retrieved kart is set down, so it lands on its
## wheels rather than starting inside the road.
const RECOVERY_HEIGHT: float = 0.8
## What fraction of its ceiling a kart has to be asking for before being
## motionless counts as wedged rather than simply stopped.
const WEDGED_THROTTLE: float = 0.25
## And how slow, in metres per second, counts as not moving.
const WEDGED_SPEED: float = 1.0

signal countdown_tick(seconds_left: int) ## Three, two, one.
signal race_started() ## The lights went out.
signal lap_completed(kart: MkCar, lap: int) ## Somebody crossed the line.
signal kart_finished(kart: MkCar, place: int) ## Somebody took the flag.
signal race_finished() ## Everybody is home, or the player is.
signal order_changed(order: Array) ## The running order moved, for the HUD.
signal kart_recovered(kart: MkCar) ## A stranded kart was set back on the line.

## The course to measure against. Its [Path3D] is the racing line, the lap
## length and the finishing line all at once.
@export var course: NodePath
@export var laps: int = MkConst.LAPS
## How long the lights take. mk64 counts three down; the exact timing is
## presentation rather than physics and is named in
## [constant MkConst.UNSOURCED].
@export var countdown_seconds: int = 3
@export_group("Recovery")
## How far off the racing line, in metres, counts as off the course. A little
## wider than the road's own half width, so a kart running the kerb is not
## retrieved for it.
@export var off_course_distance: float = 9.0
## How long a kart has to be stranded, upside down or off the course, before it
## is put back. Long enough that a kart sliding through a corner keeps its line.
@export var recovery_seconds: float = 2.5
## How far the kart's own up has to fall from vertical to count as overturned.
@export var overturned_dot: float = 0.35
@export_group("")

@export var projectile_scene: PackedScene ## What a fired shot spawns.
@export var hazard_scene: PackedScene ## What a dropped item spawns.
@export var decoy_scene: PackedScene ## What a dropped decoy spawns.

var karts: Array[MkCar] = [] ## Everyone in the race, in no particular order.
var order: Array[MkCar] = [] ## The running order, leader first.
var is_running: bool = false ## The lights are out and the clock is going.
var elapsed: float = 0.0 ## Seconds since the start.

var _lap_by_kart: Dictionary = {} ## MkCar to int.
var _progress_by_kart: Dictionary = {} ## MkCar to float, offset along the curve.
var _place_by_kart: Dictionary = {} ## MkCar to int, once they have finished.
var _stranded_for: Dictionary = {} ## MkCar to float, seconds spent stuck.
var _finished: Array[MkCar] = []
var _curve: Curve3D
var _curve_length: float = 0.0
var _path: Path3D


func _ready() -> void:
	add_to_group(&"mk_race")
	_find_path()
	_collect_karts()
	_freeze_karts(true)
	await _wait_for_ground()
	_start_countdown()


## Hold everything until there is actually a road under the grid.
##
## This is not belt and braces, it is load bearing. A course whose road is a
## [CSGPolygon3D] does not have its collision the moment the scene enters the
## tree: CSG rebuilds its geometry over the following frames, and until it does
## a ray through the start grid hits nothing. Karts released into that window
## fall into the road slab and are flung out of it at thirty metres a second
## when the collision appears, which is exactly what this demo did until the
## karts were held here. Frozen bodies cannot fall, so the wait costs nothing.
func _wait_for_ground() -> void:
	if karts.is_empty():
		return
	var space: PhysicsDirectSpaceState3D = karts[0].get_world_3d().direct_space_state
	for _frame: int in GROUND_WAIT_FRAMES:
		await get_tree().physics_frame
		if _everyone_has_ground(space):
			return
	push_warning("MkRace found no ground under the grid; the course may have no collision.")


## Whether every kart has something solid under it.
func _everyone_has_ground(space: PhysicsDirectSpaceState3D) -> bool:
	for kart: MkCar in karts:
		if not is_instance_valid(kart):
			continue
		var from: Vector3 = kart.global_position + Vector3.UP * GROUND_RAY_UP
		var query := PhysicsRayQueryParameters3D.create(
			from, from - Vector3.UP * (GROUND_RAY_UP + GROUND_RAY_DOWN))
		query.exclude = [kart.get_rid()]
		if space.intersect_ray(query).is_empty():
			return false
	return true


## Where [param kart] is lying, zero based, so 0 is the leader. This is what the
## item odds are drawn against.
func rank_of(kart: MkCar) -> int:
	var index: int = order.find(kart)
	return index if index >= 0 else 0


## Whoever is leading, or null before the first order is worked out.
func leader() -> MkCar:
	return order[0] if not order.is_empty() else null


## The kart immediately ahead of [param kart] on the road, or null when it is
## leading. This is what a homing shot asks for.
func kart_ahead_of(kart: MkCar) -> MkCar:
	var index: int = order.find(kart)
	if index <= 0:
		return null
	return order[index - 1]


## Which lap [param kart] is on, one based while racing.
func lap_of(kart: MkCar) -> int:
	return int(_lap_by_kart.get(kart, 0)) + 1


## Where [param kart] finished, or 0 if they have not.
func place_of(kart: MkCar) -> int:
	return int(_place_by_kart.get(kart, 0))


func _physics_process(delta: float) -> void:
	if not is_running:
		return
	elapsed += delta
	_update_progress()
	_recover_stranded(delta)


## Put back any kart that has ended up somewhere it cannot drive out of.
##
## Mario Kart 64 has Lakitu for this: [code]LAKITU_RETRIEVAL[/code] in the
## decomp, fished out on the [constant MkConst.SURFACE_OUT_OF_BOUNDS] surface.
## There is no Lakitu here, but the need is the same and it is not cosmetic. A
## kart that rolls onto its roof has no way to right itself, its brain goes on
## steering into the ground, and it sits there for the rest of the race; a demo
## whose field is upside down within a lap is not showing anything. So a kart
## that has been overturned or off the course for [member recovery_seconds] is
## set back on the racing line at the point it last reached, facing the right
## way and stopped, which is what being dropped back on the track amounts to.
func _recover_stranded(delta: float) -> void:
	if _curve == null or _curve_length <= 0.0:
		return
	for kart: MkCar in karts:
		if not is_instance_valid(kart) or _place_by_kart.has(kart):
			continue
		if _is_stranded(kart):
			_stranded_for[kart] = float(_stranded_for.get(kart, 0.0)) + delta
			if float(_stranded_for[kart]) >= recovery_seconds:
				_put_back(kart)
				_stranded_for[kart] = 0.0
		else:
			_stranded_for[kart] = 0.0


## Whether [param kart] is somewhere it cannot drive out of: on its roof, well
## off the course, or wedged.
##
## The wedge is the one worth spelling out. A kart that slides into a wall at an
## angle ends up with all four wheels on the road, upright, inside the course,
## and with its drive force pushing it straight into the barrier: nothing about
## where it is says anything is wrong, and it will sit there for the rest of the
## race. What gives it away is the kart asking for speed and not getting any, so
## that is what is tested.
func _is_stranded(kart: MkCar) -> bool:
	if kart.global_transform.basis.y.dot(Vector3.UP) < overturned_dot:
		return true
	var local: Vector3 = _path.to_local(kart.global_position)
	var on: Vector3 = _curve.sample_baked(_curve.get_closest_offset(local))
	if Vector2(local.x - on.x, local.z - on.z).length() > off_course_distance:
		return true
	var wants_to_move: bool = kart.current_speed > kart.ceiling_speed_units() * WEDGED_THROTTLE
	return wants_to_move and absf(kart.forward_speed()) < WEDGED_SPEED


## Set [param kart] back on the line at the furthest point it reached, upright,
## facing along the course and stopped.
func _put_back(kart: MkCar) -> void:
	var offset: float = float(_progress_by_kart.get(kart, 0.0))
	var here: Vector3 = _path.to_global(_curve.sample_baked(offset))
	var ahead: Vector3 = _path.to_global(_curve.sample_baked(fmod(offset + 4.0, _curve_length)))
	var facing: Vector3 = (ahead - here).normalized()
	if facing.is_zero_approx():
		return
	var basis := Basis()
	# a kart is built nose along +Z, so +Z is the heading and the rest follows
	basis.z = facing
	basis.x = Vector3.UP.cross(facing).normalized()
	basis.y = basis.z.cross(basis.x).normalized()
	kart.linear_velocity = Vector3.ZERO
	kart.angular_velocity = Vector3.ZERO
	kart.current_speed = 0.0
	kart.global_transform = Transform3D(basis.orthonormalized(), here + Vector3.UP * RECOVERY_HEIGHT)
	kart_recovered.emit(kart)


## Find the course's path once. Everything about position and lap depends on it,
## so a missing one is worth being loud about rather than quietly ranking
## everybody equal.
func _find_path() -> void:
	var node: Node = get_node_or_null(course)
	if node == null:
		push_warning("MkRace has no course, so there is no racing line to measure against.")
		return
	_path = node as Path3D
	if _path == null:
		_path = node.find_children("*", "Path3D", true, false).front() as Path3D
	if _path == null:
		push_warning("MkRace's course has no Path3D, so laps cannot be counted.")
		return
	_curve = _path.curve
	_curve_length = _curve.get_baked_length() if _curve != null else 0.0


## Everybody in the karts group, which is every [MkCar] that has entered the
## tree, plus their item slots wired to this race.
func _collect_karts() -> void:
	for node: Node in get_tree().get_nodes_in_group(&"mk_karts"):
		var kart: MkCar = node as MkCar
		if kart == null:
			continue
		karts.append(kart)
		_lap_by_kart[kart] = 0
		_progress_by_kart[kart] = 0.0
		var slot: MkItemSlot = kart.get_node_or_null(^"ItemSlot") as MkItemSlot
		if slot != null:
			slot.item_fired.connect(_on_item_fired.bind(kart))
	order = karts.duplicate()


## The lights. Karts are held still until they go out, which is what stops the
## AI driving off during the count.
func _start_countdown() -> void:
	for remaining: int in range(countdown_seconds, 0, -1):
		countdown_tick.emit(remaining)
		await get_tree().create_timer(1.0).timeout
	_freeze_karts(false)
	is_running = true
	race_started.emit()


## Hold or release every kart, in both senses: the body is frozen so it cannot
## fall or be shoved before the lights, and the pad is emptied so neither a
## brain nor a person can drive during the count.
func _freeze_karts(held: bool) -> void:
	for kart: MkCar in karts:
		if not is_instance_valid(kart):
			continue
		kart.freeze = held
		kart.set_drive_input(false, held, false, 0.0)
		var ai: Node = kart.get_node_or_null(^"MkAi")
		if ai != null:
			ai.set(&"enabled", not held)
		var human: Node = kart.get_node_or_null(^"HumanDriver")
		if human != null:
			human.set(&"enabled", not held)


## Measure everybody's progress along the curve, count any laps that were
## completed, and re-sort the order.
func _update_progress() -> void:
	if _curve == null or _curve_length <= 0.0:
		return
	var was: Array[MkCar] = order.duplicate()
	for kart: MkCar in karts:
		if not is_instance_valid(kart) or _place_by_kart.has(kart):
			continue
		var local: Vector3 = _path.to_local(kart.global_position)
		var offset: float = _curve.get_closest_offset(local)
		var previous: float = float(_progress_by_kart[kart])
		# crossing the line shows up as the offset jumping from near the end of
		# the curve back to near its start, and only that way round counts
		if previous > _curve_length * 0.75 and offset < _curve_length * 0.25:
			_complete_lap(kart)
		elif previous < _curve_length * 0.25 and offset > _curve_length * 0.75:
			# went back over the line, so give the lap back
			_lap_by_kart[kart] = maxi(0, int(_lap_by_kart[kart]) - 1)
		_progress_by_kart[kart] = offset
	_sort_order()
	if order != was:
		order_changed.emit(order)


## One more lap for [param kart], and the flag if that was the last.
func _complete_lap(kart: MkCar) -> void:
	var lap: int = int(_lap_by_kart[kart]) + 1
	_lap_by_kart[kart] = lap
	lap_completed.emit(kart, lap)
	if lap < laps:
		return
	_finished.append(kart)
	var place: int = _finished.size()
	_place_by_kart[kart] = place
	kart_finished.emit(kart, place)
	if _finished.size() >= karts.size():
		is_running = false
		race_finished.emit()


## Sort by progress the way the game does: laps first, then how far around this
## one. Karts that have finished keep their finishing places at the top.
func _sort_order() -> void:
	order.sort_custom(_compare_progress)


func _compare_progress(a: MkCar, b: MkCar) -> bool:
	var a_place: int = int(_place_by_kart.get(a, 0))
	var b_place: int = int(_place_by_kart.get(b, 0))
	if a_place != b_place:
		# a finished kart is ahead of an unfinished one, and earlier is ahead
		if a_place == 0:
			return false
		if b_place == 0:
			return true
		return a_place < b_place
	var a_progress: float = float(_lap_by_kart.get(a, 0)) * _curve_length + float(_progress_by_kart.get(a, 0.0))
	var b_progress: float = float(_lap_by_kart.get(b, 0)) * _curve_length + float(_progress_by_kart.get(b, 0.0))
	return a_progress > b_progress


## A slot fired. The race owns the world, so it is the one that puts the item in
## it: ahead of the kart for a shot, behind for a hazard.
func _on_item_fired(item: int, forward: bool, kart: MkCar) -> void:
	if not is_instance_valid(kart):
		return
	if forward:
		_spawn_projectile(item, kart)
	else:
		_spawn_hazard(item, kart)


func _spawn_projectile(item: int, kart: MkCar) -> void:
	if projectile_scene == null:
		return
	var shot: MkProjectile = projectile_scene.instantiate() as MkProjectile
	if shot == null:
		return
	match item:
		MkItems.Item.HOMING_SHOT, MkItems.Item.TRIPLE_HOMING_SHOT:
			shot.homing_strength = 3.0
		MkItems.Item.LEADER_SHOT:
			shot.homing_strength = 4.0
			shot.targets_leader = true
		_:
			shot.homing_strength = 0.0
	add_child(shot)
	shot.global_position = kart.global_position + kart.forward() * 2.0 + Vector3.UP * 0.4
	shot.launch(kart, kart.forward())


func _spawn_hazard(item: int, kart: MkCar) -> void:
	var scene: PackedScene = decoy_scene if item == MkItems.Item.DECOY else hazard_scene
	if scene == null:
		return
	var dropped: Node3D = scene.instantiate() as Node3D
	if dropped == null:
		return
	add_child(dropped)
	dropped.global_position = kart.global_position - kart.forward() * 2.0
	if dropped is MkHazard:
		(dropped as MkHazard).drop(kart)
