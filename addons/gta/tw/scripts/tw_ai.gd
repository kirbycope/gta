class_name TwAi
extends Node
## Drives a [TwCar] the way Twisted Metal drives its opponents.
##
## The structure is taken from the Twisted Metal 1 decompilation's symbol table,
## which still carries the original function names even though the bodies are
## not decompiled yet. Each step below names the routine it stands in for.
##
## The AI never touches the handling model. It fills in a virtual control pad and
## hands it to [method TwCar.set_drive_input], exactly as
## [code]AICarUpdateControlPad[/code] does in the original.

signal state_changed(state: State) ## Broke off, or joined, a fight.

enum State {
	OUT_OF_BATTLE, ## AICarOutOfBattle: patrol the waypoints, look for someone.
	IN_BATTLE, ## AICarInBattle: close on the target and shoot.
}

const ARRIVE_DISTANCE: float = 12.0 ## Close enough to a waypoint to take the next.
const ENGAGE_RANGE: float = 90.0 ## AICarUpdatePlayerRange: inside this, pick a fight.
const BREAK_RANGE: float = 140.0 ## Outside this the fight is over.
const STANDOFF_RANGE: float = 18.0 ## Nearer than this and the car peels away.
const FIRE_CONE: float = 0.86 ## Dot product the target must be inside to shoot.
const SWERVE_INTERVAL: Vector2 = Vector2(0.8, 2.2) ## AICarInitSwerve: seconds between weaves.
const SWERVE_STRENGTH: float = 0.45
const REVERSE_TIME: float = 1.1 ## How long to back up after getting stuck.
const STUCK_SPEED: float = 1.5
const STUCK_PATIENCE: float = 1.0
const TURBO_RANGE: float = 45.0 ## Far enough from the target to be worth burning turbo closing it.
const TURBO_MAX_STEER: float = 0.35 ## Turning harder than this, turbo would only run the car wide.
const OVERSPEED: float = 1.15 ## Brake once this far over the speed the corner allows.
const EDGE_LOOKAHEAD_TIME: float = 1.1 ## Seconds of travel to feel ahead for a drop.
const EDGE_MIN_LOOKAHEAD: float = 6.0
const EDGE_MAX_LOOKAHEAD: float = 26.0
const EDGE_DROP: float = 6.0 ## A fall deeper than this counts as the edge of the roof.
const DEFAULT_TOP_SPEED: float = 40.0 ## Used when the car is not in the roster.
const EDGE_CRAWL: float = 4.0 ## Brake off an edge only while still rolling at this speed.
const EDGE_SIDE_ANGLE: float = 0.9 ## Radians either side of the nose the edge feelers point.
const EDGE_SIDE_REACH: float = 0.7 ## Side feelers are this fraction of the forward reach.

@export var waypoints: TwWaypoints
@export var aggression: float = 0.6 ## AICarInitProfiles: 0 timid, 1 relentless.
@export var enabled: bool = true

var state: State = State.OUT_OF_BATTLE
var target: TwCar

var _vehicle: TwCar
var _combat: TwCombat
var _point: int = -1
var _swerve_timer: float = 0.0
var _swerve: float = 0.0
var _stuck_for: float = 0.0
var _reverse_for: float = 0.0
var _fire_cooldown: float = 0.0
var _top_speed: float = DEFAULT_TOP_SPEED


func _ready() -> void:
	_vehicle = get_parent() as TwCar
	_combat = _combat_of(_vehicle)
	if is_instance_valid(_vehicle):
		# the car drives to its own published Twisted Metal 2 top speed, which the car
		# already knows: its roster key is its identity, not the combat node's
		var published: float = TwRoster.top_speed(_vehicle.car)
		_top_speed = published if published > 0.0 else DEFAULT_TOP_SPEED
	if waypoints != null and is_instance_valid(_vehicle):
		_point = waypoints.nearest(_vehicle.global_position)


func _physics_process(delta: float) -> void:
	if not enabled or not is_instance_valid(_vehicle) or not _vehicle.is_inside_tree():
		return
	if _combat != null and _combat.is_dead:
		_vehicle.set_drive_input(false, true, false, 0.0)
		return
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	_update_closest_target()
	_update_transition()
	_update_swerve(delta)
	_update_stuck(delta)
	if state == State.IN_BATTLE:
		_drive_at_target(delta)
		_update_attack()
	else:
		_drive_between_points()


## AICarUpdateClosestPlayer: whoever is nearest and still alive is the target.
func _update_closest_target() -> void:
	var best: TwCar = null
	var best_distance: float = INF
	for node: Node in get_tree().get_nodes_in_group(&"tw_cars"):
		var other: TwCar = node as TwCar
		if other == null or other == _vehicle or not other.is_inside_tree():
			continue
		var other_combat: TwCombat = _combat_of(other)
		if other_combat != null and other_combat.is_dead:
			continue
		var d: float = other.global_position.distance_squared_to(_vehicle.global_position)
		if d < best_distance:
			best_distance = d
			best = other
	target = best


## AICarInitTransition and AICarUpdateTransition: in and out of a fight. A hurt
## car needs the target closer before it will commit, which is what
## AICarUpdateDrivingProfile reads the health tier for.
func _update_transition() -> void:
	var was: State = state
	if not is_instance_valid(target):
		state = State.OUT_OF_BATTLE
	else:
		var range_to: float = target.global_position.distance_to(_vehicle.global_position)
		var tier: int = _combat.health_tier() if _combat != null else 0
		var engage: float = ENGAGE_RANGE * lerpf(0.55, 1.15, aggression) / float(1 + tier)
		if state == State.OUT_OF_BATTLE and range_to <= engage:
			state = State.IN_BATTLE
		elif state == State.IN_BATTLE and range_to > BREAK_RANGE:
			state = State.OUT_OF_BATTLE
	if state != was:
		state_changed.emit(state)


## AICarDriveBetweenPts: follow the arena's own waypoint ring.
func _drive_between_points() -> void:
	if waypoints == null or waypoints.points.is_empty():
		_vehicle.set_drive_input(false, false, false, 0.0)
		return
	if _point < 0:
		_point = waypoints.nearest(_vehicle.global_position)
	var goal: Vector3 = waypoints.points[_point]
	if _flat_distance(goal) <= ARRIVE_DISTANCE:
		_point = waypoints.next_index(_point)
		goal = waypoints.points[_point]
	# steer level with the car: a waypoint on a lower roof should not tip the
	# nose down, only turn the wheels
	goal.y = _vehicle.global_position.y
	_steer_towards(goal)


## Close on the target, but keep off its bumper so the fight keeps moving.
func _drive_at_target(_delta: float) -> void:
	if not is_instance_valid(target):
		_drive_between_points()
		return
	var to_target: Vector3 = target.global_position - _vehicle.global_position
	if to_target.length() < STANDOFF_RANGE:
		var away: Vector3 = _vehicle.global_position - to_target.normalized() * STANDOFF_RANGE
		_steer_towards(away)
		return
	_steer_towards(target.global_position)


## AICarTurn and AICarUpdateNextPtAngle, then AICarUpdateControlPad.
func _steer_towards(goal: Vector3) -> void:
	var local: Vector3 = _vehicle.global_transform.affine_inverse() * goal
	var steer: float = clampf(atan2(local.x, maxf(0.5, local.z)) * 1.6, -1.0, 1.0)
	steer = clampf(steer + _swerve, -1.0, 1.0)
	if _reverse_for > 0.0:
		# braking from a standstill is what puts this car into reverse
		_vehicle.set_drive_input(false, true, false, -steer)
		return

	var speed: float = _vehicle.linear_velocity.length()
	# The arena is a set of rooftops with nothing between them, so the one
	# thing an opponent must not do is hold the throttle over an edge.
	var avoid: float = _edge_avoidance(speed)
	if not is_nan(avoid):
		# ease off and turn towards whichever side still has roof under it
		_vehicle.set_drive_input(false, speed > EDGE_CRAWL, false, avoid)
		return

	# published top speed for this car, eased down for how hard it is turning
	var limit: float = _top_speed * lerpf(0.35, 1.0, 1.0 - absf(steer))
	var accelerate: bool = speed < limit
	var brake: bool = speed > limit * OVERSPEED
	# turbo is for covering ground in a straight line, never for cornering: a Twisted Metal
	# car under turbo does not turn well enough to spend it there. That means the long runs
	# between waypoints, and closing a gap on someone who is still a way off.
	var turbo: bool = false
	if accelerate and not brake and absf(steer) < TURBO_MAX_STEER:
		if state == State.OUT_OF_BATTLE:
			turbo = true
		elif is_instance_valid(target):
			turbo = target.global_position.distance_to(_vehicle.global_position) > TURBO_RANGE
	_vehicle.set_drive_input(accelerate and not brake, brake, turbo, steer)


## Feel for the edge of the roof ahead, and say which way to turn off it.
## Returns NAN when the way forward is solid, otherwise the steer to use.
## Twisted Metal's own opponents know the arena; ours has to feel for it.
func _edge_avoidance(speed: float) -> float:
	if _vehicle.wheels_in_contact() == 0:
		return NAN
	var ahead: float = clampf(speed * EDGE_LOOKAHEAD_TIME, EDGE_MIN_LOOKAHEAD, EDGE_MAX_LOOKAHEAD)
	if _ground_at(ahead, 0.0):
		return NAN
	# nothing in front: prefer the side that still has roof, and if neither
	# does, turn the way the car is already leaning and let the stuck timer
	# back it out
	var left: bool = _ground_at(ahead * EDGE_SIDE_REACH, -EDGE_SIDE_ANGLE)
	var right: bool = _ground_at(ahead * EDGE_SIDE_REACH, EDGE_SIDE_ANGLE)
	if left and not right:
		return -1.0
	if right and not left:
		return 1.0
	return -1.0 if _swerve <= 0.0 else 1.0


## Is there roof [param distance] ahead, [param angle] radians off the nose?
func _ground_at(distance: float, angle: float) -> bool:
	var space: PhysicsDirectSpaceState3D = _vehicle.get_world_3d().direct_space_state
	var forward: Vector3 = _vehicle.forward().rotated(Vector3.UP, angle)
	var probe: Vector3 = _vehicle.global_position + forward * distance
	var query := PhysicsRayQueryParameters3D.create(probe + Vector3.UP * 2.0,
		probe + Vector3.DOWN * EDGE_DROP)
	query.exclude = [_vehicle.get_rid()]
	return not space.intersect_ray(query).is_empty()


## AICarInitSwerve and AICarUpdateSwerve: opponents weave so they are harder to hit.
func _update_swerve(delta: float) -> void:
	_swerve_timer -= delta
	if _swerve_timer <= 0.0:
		_swerve_timer = randf_range(SWERVE_INTERVAL.x, SWERVE_INTERVAL.y)
		_swerve = randf_range(-SWERVE_STRENGTH, SWERVE_STRENGTH) * aggression
	_swerve = move_toward(_swerve, 0.0, delta * 0.2)


## Not a routine of its own in the original, but a car wedged against a wall
## never recovers without it.
func _update_stuck(delta: float) -> void:
	if _reverse_for > 0.0:
		_reverse_for -= delta
		return
	if _vehicle.linear_velocity.length() < STUCK_SPEED:
		_stuck_for += delta
		if _stuck_for > STUCK_PATIENCE:
			_stuck_for = 0.0
			_reverse_for = REVERSE_TIME
	else:
		_stuck_for = 0.0


## AICarUpdateAttackProfile, AIPickAttackWeapon and AICarChooseForeWeapon:
## shoot when the target is in front, pick the special when it is charged.
func _update_attack() -> void:
	if _combat == null or not is_instance_valid(target) or _fire_cooldown > 0.0:
		return
	var to_target: Vector3 = target.global_position - _vehicle.global_position
	var distance: float = to_target.length()
	if distance > ENGAGE_RANGE:
		return
	var facing: float = _vehicle.forward().dot(to_target.normalized())
	if facing >= FIRE_CONE:
		if _combat.specials > 0 and distance < ENGAGE_RANGE * 0.6:
			_combat.fire_special(target)
		else:
			_combat.fire_forward(target)
		_fire_cooldown = lerpf(1.4, 0.45, aggression)
	elif facing <= -FIRE_CONE:
		# AICarChooseAftWeapon: it is behind us, so drop something out the back
		_combat.fire_rear(target)
		_fire_cooldown = lerpf(1.8, 0.7, aggression)


## Distance ignoring height, for the flat waypoints out of the .PTS file.
func _flat_distance(to: Vector3) -> float:
	var here: Vector3 = _vehicle.global_position
	return Vector2(to.x - here.x, to.z - here.z).length()


func _combat_of(vehicle: TwCar) -> TwCombat:
	if not is_instance_valid(vehicle):
		return null
	for child: Node in vehicle.get_children():
		if child is TwCombat:
			return child as TwCombat
	return null
