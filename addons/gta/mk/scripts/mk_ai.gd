class_name MkAi
extends Node
## A computer racer at a kart's control pad.
##
## Sits under a [MkCar] and fills the same virtual pad a [HumanDriver] fills,
## the way [RlAi] and [TwAi] do for the addon's other two cars. It is a
## brain, not a driver: it has no body, gets in nothing and has nothing to get
## out of.
##
## [b]How it drives.[/b] The course's [Path3D] is the racing line, so the whole
## of steering is looking a little way up that line and turning toward it. How
## far up is [member lookahead], and it grows with speed, which is what stops a
## fast kart sawing at the wheel. It drifts a corner when the line bends harder
## than [member drift_angle] and it is going fast enough for a drift to be worth
## anything, which is also roughly when a person would.
##
## [b]Rubber banding.[/b] mk64's CPU karts are famously helped along, and the
## decomp shows how: [code]player_controller.c[/code] moves a trailing CPU kart's
## speed toward [constant MkConst.CPU_CATCHUP_TARGET] at
## [constant MkConst.CPU_CATCHUP_RATE] a frame while the catch up effect is
## lit. That target is reproduced here; when the effect is switched on is not, so
## [member catchup_places] stands in for it and is named in
## [constant MkConst.UNSOURCED].
##
## [b]Items.[/b] The brain uses whatever it is holding as soon as using it makes
## sense: a boost on a straight, a shot when somebody is in front of it and close
## enough to hit. It does not hoard and it does not aim, because mk64's own CPU
## item strategy was not read for this port.

## How many points up the road to test for the corner being braked for.
const CORNER_SAMPLES: int = 6
## The slowest a corner may ask for, so a hairpin never brings a kart to a stop.
const CORNER_SPEED_FLOOR: float = 6.0
## How far over the corner speed the brain will run before it uses the brake
## rather than simply lifting off.
const BRAKE_MARGIN: float = 1.15

@export var enabled: bool = true ## Off leaves the pad alone, so the countdown can hold it.
@export var course: NodePath ## Where the racing line is. Empty finds the race's course.
## How far up the line to aim, in metres, at a standstill. It grows with speed.
@export var lookahead: float = 8.0
@export var lookahead_per_speed: float = 0.55 ## Extra metres of lookahead per metre per second.
## How sharp a bend has to be, in degrees, before the brain drifts it.
@export var drift_angle: float = 28.0
## How far behind the leader, in places, before the catch up speed is allowed.
@export var catchup_places: int = 3
## How far ahead a kart has to be, in metres, to be worth shooting at.
@export var shoot_range: float = 40.0
## How much lateral grip the brain believes it has, in metres per second
## squared, which is what sets its corner entry speed: a corner of radius r can
## be taken at [code]sqrt(grip * r)[/code]. Lower makes a more cautious driver.
## A judgement, not a reading, and named in [constant MkConst.UNSOURCED]: mk64
## picks its CPU speeds off a per course path rather than by computing any of
## this.
@export var cornering_grip: float = 7.5
## How far up the road, in metres, to look for the corner being braked for.
@export var corner_horizon: float = 45.0

var _kart: MkCar
var _path: Path3D
var _curve: Curve3D
var _slot: MkItemSlot
var _race: MkRace


func _ready() -> void:
	_kart = get_parent() as MkCar
	_slot = get_parent().get_node_or_null(^"ItemSlot") as MkItemSlot
	_find_path.call_deferred()


func _physics_process(delta: float) -> void:
	if not enabled or not is_instance_valid(_kart) or _curve == null:
		return
	if not _kart.is_multiplayer_authority():
		return
	_drive()
	_use_items(delta)


## The racing line, from this node's own course or from the race's.
func _find_path() -> void:
	_race = get_tree().get_first_node_in_group(&"mk_race") as MkRace
	var node: Node = get_node_or_null(course)
	if node == null and _race != null:
		node = _race.get_node_or_null(_race.course)
	if node == null:
		return
	_path = node as Path3D
	if _path == null:
		_path = node.find_children("*", "Path3D", true, false).front() as Path3D
	if _path != null:
		_curve = _path.curve


## Look up the line, turn toward it, and decide whether the corner is worth
## drifting.
func _drive() -> void:
	var speed: float = absf(_kart.forward_speed())
	var here: Vector3 = _path.to_local(_kart.global_position)
	var offset: float = _curve.get_closest_offset(here)
	var length: float = _curve.get_baked_length()
	var ahead: float = lookahead + speed * lookahead_per_speed
	var aim: Vector3 = _path.to_global(_curve.sample_baked(fmod(offset + ahead, length)))
	# a second, further point says how hard the line is about to bend, which is
	# what decides the drift
	var further: Vector3 = _path.to_global(_curve.sample_baked(fmod(offset + ahead * 2.0, length)))

	var to_aim: Vector3 = (aim - _kart.global_position).slide(Vector3.UP).normalized()
	var facing: Vector3 = _kart.forward().slide(Vector3.UP).normalized()
	# Positive steer is left, matching the project's own move axis and the
	# chassis: a kart given steering +0.5 was measured turning left. So the sign
	# is taken off the kart's own right vector, and negated, rather than from a
	# cross product whose handedness is easy to get backwards.
	var right: Vector3 = _kart.global_transform.basis.x
	var steer: float = -signf(to_aim.dot(right)) * facing.angle_to(to_aim)
	steer = clampf(steer / deg_to_rad(35.0), -1.0, 1.0)

	var bend: float = rad_to_deg((further - aim).slide(Vector3.UP).normalized()
		.angle_to(to_aim))
	var wants_drift: bool = bend > drift_angle and speed > _kart.top_speed() * 0.5

	# Lift and brake for the corner coming up. Without this the brain holds the
	# throttle down everywhere, arrives at a 39 m radius bend needing more than a
	# gravity of lateral grip, and slides into the wall, where it wedges and the
	# race is over for it. Pure pursuit steers the line; it does not slow for it.
	var safe: float = _corner_speed(offset, length)
	var accelerate: bool = speed < safe
	var brake: bool = speed > safe * BRAKE_MARGIN

	_kart.set_drive_input(accelerate, brake, wants_drift, steer)
	_apply_catchup()


## The fastest this kart should be going right now, in metres per second, for
## the tightest corner within [member corner_horizon] metres up the road.
##
## A corner of radius r can be held at [code]sqrt(grip * r)[/code], so the
## tightest radius ahead sets the speed. The radius is measured from three
## points on the racing line rather than from any curvature the curve exposes,
## because that is the same measurement the course generator uses and the two
## agreeing matters more than either being exact.
func _corner_speed(offset: float, length: float) -> float:
	var slowest: float = _kart.top_speed()
	var step: float = corner_horizon / float(CORNER_SAMPLES)
	for i in range(1, CORNER_SAMPLES + 1):
		var at: float = offset + step * float(i)
		var a: Vector3 = _path.to_global(_curve.sample_baked(fmod(at - step, length)))
		var b: Vector3 = _path.to_global(_curve.sample_baked(fmod(at, length)))
		var c: Vector3 = _path.to_global(_curve.sample_baked(fmod(at + step, length)))
		var radius: float = _radius_through(a, b, c)
		slowest = minf(slowest, sqrt(cornering_grip * radius))
	return maxf(slowest, CORNER_SPEED_FLOOR)


## The radius of the circle through three points, flattened to the ground plane.
## Huge when they are in a straight line, which is what a straight should give.
func _radius_through(a: Vector3, b: Vector3, c: Vector3) -> float:
	var ab: float = Vector2(b.x - a.x, b.z - a.z).length()
	var bc: float = Vector2(c.x - b.x, c.z - b.z).length()
	var ca: float = Vector2(a.x - c.x, a.z - c.z).length()
	var area: float = absf((b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z)) * 0.5
	if area < 0.0001:
		return 100000.0
	return (ab * bc * ca) / (4.0 * area)


## The catch up speed, when this kart is far enough back to have earned it.
##
## The game's own figure cannot be used directly: it lives in an accumulator
## whose conversion to the units a kart's speed is kept in the decomp never
## states, and reading 380 as a topSpeed would put a trailing kart above every
## ceiling in the table. So what is reproduced is the shape, a trailing kart
## being pulled toward its ceiling at [constant MkConst.CPU_CATCHUP_RATE] a
## frame rather than having to build up to it, and the magnitude is left alone.
func _apply_catchup() -> void:
	if _race == null or catchup_places <= 0:
		return
	if _race.rank_of(_kart) < catchup_places:
		return
	_kart.current_speed = move_toward(
		_kart.current_speed, _kart.ceiling_speed_units(), MkConst.CPU_CATCHUP_RATE)


## Use whatever is in the slot once it is worth using.
func _use_items(_delta: float) -> void:
	if _slot == null or not _slot.has_item():
		return
	if MkItems.is_boost(_slot.item):
		# a boost is wasted in a corner, so wait for the kart to be pointing
		# roughly where it is going
		if absf(_kart.steering) < deg_to_rad(8.0):
			_slot.use()
		return
	if MkItems.is_dropped(_slot.item):
		_slot.use()
		return
	var target: MkCar = _race.kart_ahead_of(_kart) if _race != null else null
	if is_instance_valid(target) and _kart.global_position.distance_to(target.global_position) < shoot_range:
		_slot.use()
