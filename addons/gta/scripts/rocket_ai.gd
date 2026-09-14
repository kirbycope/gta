class_name RocketAi
extends Node
## Drives a [RocketCar] through a game of soccar.
##
## It is built the way [AiDriver] is: it never touches the handling model, it
## fills in a virtual control pad and hands it to [method
## RocketCar.set_rocket_input] once a physics frame. It has the same eight
## inputs a person has and no others, so it cannot steer harder, accelerate
## faster or see further than the car it is sitting in.
##
## Three roles are shared out among a team every frame, on distance rather than
## on a fixed assignment, so the team rotates the way a real one does. Whoever
## can reach the ball soonest attacks, whoever is furthest back defends, and
## anyone left over holds the middle and keeps the tank full.
##
## The thresholds below have no equivalent in the real game and are not
## pretending to: [constant RocketConst.UNSOURCED] says as much. Everything the
## car itself does with these inputs is Rocket League's own published physics.

signal role_changed(role: Role) ## Rotated into a different job.

enum Role {
	ATTACK, ## Nearest the ball: go and hit it at the opponent's goal.
	MIDFIELD, ## Hold behind the play, collect boost, cover the attacker.
	DEFEND, ## Furthest back: stay between the ball and the goal.
}

const REACH_SPEED: float = 12.0 ## Assumed approach speed when guessing a time to the ball.
const INTERCEPT_MAX: float = 2.5 ## Never aim further ahead than this many seconds.
const APPROACH_OFFSET: float = 2.6 ## Metres behind the ball to aim, so the hit goes the right way.
const ALIGNED_DOT: float = 0.85 ## How square to the target the nose has to be to boost.
const POWERSLIDE_DOT: float = -0.1 ## Wider than this and the corner is taken sideways.
const BOOST_HUNT_LEVEL: float = 34.0 ## Below this a midfielder goes looking for a pad.
const BOOST_HUNT_RANGE: float = 34.0 ## And will not detour further than this for one.
const DEFEND_DISTANCE: float = 14.0 ## How far off its own line a defender sits.
const AERIAL_MIN_HEIGHT: float = 4.5 ## Ball this high is worth leaving the ground for.
const AERIAL_MIN_BOOST: float = 45.0 ## And only with this much in the tank.
const AERIAL_MAX_RANGE: float = 26.0 ## And only from this close.
const AERIAL_DURATION: float = 1.4 ## How long a committed aerial keeps climbing.
const FLIP_SPEED_MIN: float = 8.0 ## Flipping under this speed loses more than it gains.
const FLIP_RANGE_MIN: float = 16.0 ## Only flip for distance, never in close.
const STUCK_SPEED: float = 1.2
const STUCK_PATIENCE: float = 1.0
const RECOVER_DOT: float = 0.4 ## Roof this far from upright wants a roll back over.
const KICKOFF_RANGE: float = 3.0 ## Ball within this of the centre spot is a kickoff.

## Switching this off hands the car back, which is what the countdown before a
## kickoff and the goal replay both do. The car is told as well as the brain,
## because [member RocketCar.is_ai] is what the match reads to know whose car
## this is, and the two drifting apart leaves a car nobody drives.
@export var enabled: bool = true: set = _set_enabled
@export var skill: float = 0.8 ## Zero dawdles, one commits to everything.

var role: Role = Role.MIDFIELD

var _car: RocketCar
var _ball: RocketBall
var _stuck_for: float = 0.0
var _aerial_for: float = -1.0 ## Seconds into a committed aerial, or negative when grounded.
var _jump_held: bool = false ## Held across frames so a jump can be released and pressed again.
var _flip_cooldown: float = 0.0


func _ready() -> void:
	_car = get_parent() as RocketCar
	if is_instance_valid(_car):
		_car.is_ai = enabled


func _set_enabled(value: bool) -> void:
	enabled = value
	# before the node is in the tree there is no car to tell yet, and _ready
	# catches up the moment there is
	if is_instance_valid(_car):
		_car.is_ai = value


func _physics_process(delta: float) -> void:
	if not enabled or not is_instance_valid(_car) or not _car.is_inside_tree():
		return
	if _car.is_demolished:
		_car.release_controls()
		return
	_ball = _find_ball()
	if _ball == null:
		return
	_flip_cooldown = maxf(0.0, _flip_cooldown - delta)
	_update_role()
	_update_stuck(delta)

	if not _car.on_ground:
		_fly(delta)
		return
	if _stuck_for > STUCK_PATIENCE:
		_unstick()
		return
	_drive_toward(_target_point(), delta)


## Whoever on this team reaches the ball soonest attacks and whoever is nearest
## their own goal defends, worked out afresh every frame. A team that assigns
## these once stops rotating the moment one car gets caught upfield.
func _update_role() -> void:
	var mates: Array[RocketCar] = _team_mates()
	if mates.size() <= 1:
		_set_role(Role.ATTACK)
		return
	var closest: RocketCar = null
	var deepest: RocketCar = null
	var best_time: float = INF
	var deepest_distance: float = -INF
	for mate: RocketCar in mates:
		var time_to_ball: float = mate.global_position.distance_to(_ball.global_position) / REACH_SPEED
		if time_to_ball < best_time:
			best_time = time_to_ball
			closest = mate
		var back: float = mate.global_position.distance_to(mate.own_goal())
		if back > deepest_distance:
			deepest_distance = back
			deepest = mate
	if _car == closest:
		_set_role(Role.ATTACK)
	elif _car == deepest and mates.size() > 2:
		_set_role(Role.DEFEND)
	else:
		_set_role(Role.MIDFIELD)


## Where this car wants to be, which is the whole of its decision making. Every
## branch returns a point on the pitch and the driving below is the same for
## all of them.
func _target_point() -> Vector3:
	var ball_at: Vector3 = _ball.global_position
	if _is_kickoff():
		return ball_at
	match role:
		Role.ATTACK:
			return _strike_point()
		Role.DEFEND:
			var goal: Vector3 = _car.own_goal()
			var toward_ball: Vector3 = (ball_at - goal)
			toward_ball.y = 0.0
			return goal + toward_ball.normalized() * DEFEND_DISTANCE
		_:
			if _car.boost < BOOST_HUNT_LEVEL:
				var pad: RocketBoostPad = _nearest_pad()
				if pad != null:
					return pad.global_position
			# hold station between the ball and the goal, out of the attacker's way
			var behind: Vector3 = ball_at + Vector3(0.0, 0.0, -_car.attack_direction() * 18.0)
			behind.x = clampf(ball_at.x * 0.5, -RocketConst.ARENA_EXTENT_X + 6.0,
				RocketConst.ARENA_EXTENT_X - 6.0)
			behind.y = 0.0
			return behind


## Where to meet the ball so the hit goes toward the opponent's goal: predict
## where it will be, then stand off along the line back from the goal through
## that point. Driving straight at the ball puts it wherever the car happened
## to be pointing.
func _strike_point() -> Vector3:
	var distance: float = _car.global_position.distance_to(_ball.global_position)
	var lead: float = clampf(distance / REACH_SPEED, 0.0, INTERCEPT_MAX)
	var meeting: Vector3 = _ball.predict(lead)
	var goal: Vector3 = _car.target_goal()
	var from_goal: Vector3 = meeting - goal
	from_goal.y = 0.0
	if from_goal.length_squared() < 0.01:
		from_goal = Vector3(0.0, 0.0, -_car.attack_direction())
	var strike: Vector3 = meeting + from_goal.normalized() * APPROACH_OFFSET
	strike.y = meeting.y
	return strike


## Steer at a point and decide what to do with the pedals. This is the only
## place the control pad is filled while the car is on the ground.
func _drive_toward(point: Vector3, _delta: float) -> void:
	var to_point: Vector3 = point - _car.global_position
	to_point.y = 0.0
	var distance: float = to_point.length()
	if distance < 0.01:
		_car.release_controls()
		return
	var direction: Vector3 = to_point.normalized()
	var alignment: float = _car.nose().dot(direction)
	# positive steer is left, matching the project's own move axis
	var steer: float = clampf(-_car.flank().dot(direction) * 2.5, -1.0, 1.0)

	var throttle: float = 1.0
	# a target behind the car is reached faster in reverse than by turning round
	if alignment < -0.55 and distance < 12.0:
		throttle = -1.0
		steer = -steer

	var speed: float = _car.linear_velocity.length()
	var boosting: bool = _car.boost > 0.0 and alignment > ALIGNED_DOT \
		and distance > 6.0 and throttle > 0.0 and randf() < skill
	var powerslide: bool = alignment < POWERSLIDE_DOT and speed > 9.0

	if _should_aerial(point):
		_begin_aerial()
		return
	# a forward flip is free speed on a long straight run with an empty tank
	var wants_flip: bool = _car.boost <= 0.0 and alignment > ALIGNED_DOT \
		and distance > FLIP_RANGE_MIN and speed > FLIP_SPEED_MIN and _flip_cooldown <= 0.0
	if wants_flip:
		_flip_cooldown = 1.6
		_jump_held = true
		_car.set_rocket_input(throttle, 0.0, -1.0, 0.0, 0.0, true, boosting, false)
		return

	_jump_held = false
	_car.set_rocket_input(throttle, steer, 0.0, 0.0, 0.0, false, boosting, powerslide)


## A ball high enough, close enough and a tank full enough to reach it. The AI
## only ever goes up for the ball as the attacker, so two cars do not leave the
## floor at once.
func _should_aerial(_point: Vector3) -> bool:
	if role != Role.ATTACK or _aerial_for >= 0.0:
		return false
	if _ball.global_position.y < AERIAL_MIN_HEIGHT or _car.boost < AERIAL_MIN_BOOST:
		return false
	var flat: Vector3 = _ball.global_position - _car.global_position
	flat.y = 0.0
	if flat.length() > AERIAL_MAX_RANGE:
		return false
	return _car.nose().dot(flat.normalized()) > ALIGNED_DOT and randf() < skill


func _begin_aerial() -> void:
	_aerial_for = 0.0
	_jump_held = true
	_car.set_rocket_input(1.0, 0.0, 0.0, 0.0, 0.0, true, true, false)


## Airborne, the car is either climbing at the ball or getting its wheels back
## under it. Both are the same three inputs: pitch, roll and boost.
func _fly(delta: float) -> void:
	var upright: float = _car.global_transform.basis.y.dot(Vector3.UP)
	if _aerial_for >= 0.0:
		_aerial_for += delta
		if _aerial_for < AERIAL_DURATION and _car.boost > 0.0:
			var to_ball: Vector3 = (_ball.global_position - _car.global_position).normalized()
			var pitch: float = clampf((to_ball.y - _car.nose().y) * 3.0, -1.0, 1.0)
			var yaw: float = clampf(-_car.flank().dot(to_ball) * 2.5, -1.0, 1.0)
			# the jump has to be let go and pressed again for the second one to count
			_jump_held = _aerial_for > 0.25 and _aerial_for < 0.35
			_car.set_rocket_input(1.0, yaw, pitch, yaw, 0.0, _jump_held, true, false)
			return
		_aerial_for = -1.0

	# falling: roll the roof back up so the landing is on the wheels
	if upright < RECOVER_DOT:
		var roll: float = signf(_car.flank().dot(Vector3.UP))
		_car.set_rocket_input(0.0, 0.0, 0.0, 0.0,
			roll if not is_zero_approx(roll) else 1.0, false, false, false)
		return
	# level the nose out on the way down, so the landing is flat
	_car.set_rocket_input(0.0, 0.0, clampf(-_car.nose().y * 2.0, -1.0, 1.0),
		0.0, 0.0, false, false, false)


## Wedged against a wall or another car. Rocket League's own answer is to back
## off and turn, and a jump shakes the car loose of a corner it has climbed.
func _unstick() -> void:
	_stuck_for = 0.0
	_jump_held = not _jump_held
	_car.set_rocket_input(-1.0, 1.0 if randf() < 0.5 else -1.0, 0.0, 0.0, 0.0,
		_jump_held, false, false)


func _update_stuck(delta: float) -> void:
	if _car.linear_velocity.length() < STUCK_SPEED and _car.on_ground:
		_stuck_for += delta
	else:
		_stuck_for = 0.0


## The ball is at the centre spot and still, so everyone is lined up waiting.
func _is_kickoff() -> bool:
	return _ball.global_position.length() < KICKOFF_RANGE \
		and _ball.linear_velocity.length() < 1.0


func _team_mates() -> Array[RocketCar]:
	var out: Array[RocketCar] = []
	for node: Node in get_tree().get_nodes_in_group(&"rocket_cars"):
		var car: RocketCar = node as RocketCar
		if car != null and car.team == _car.team and not car.is_demolished and car.is_inside_tree():
			out.append(car)
	return out


## The best pad worth a detour: near enough to be on the way, and a big one
## beats a small one at the same distance.
func _nearest_pad() -> RocketBoostPad:
	var best: RocketBoostPad = null
	var best_score: float = -INF
	for node: Node in get_tree().get_nodes_in_group(&"rocket_boost_pads"):
		var pad: RocketBoostPad = node as RocketBoostPad
		if pad == null or not pad.is_available:
			continue
		var distance: float = pad.global_position.distance_to(_car.global_position)
		if distance > BOOST_HUNT_RANGE:
			continue
		var score: float = pad.amount() - distance
		if score > best_score:
			best_score = score
			best = pad
	return best


func _find_ball() -> RocketBall:
	var balls: Array[Node] = get_tree().get_nodes_in_group(&"rocket_ball")
	return balls[0] as RocketBall if not balls.is_empty() else null


func _set_role(to: Role) -> void:
	if role == to:
		return
	role = to
	role_changed.emit(role)
