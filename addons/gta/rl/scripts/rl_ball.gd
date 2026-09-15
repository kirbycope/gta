class_name RlBall
extends RigidBody3D
## The soccar ball: Rocket League's own size, mass, drag and bounce, plus the
## extra impulse a car puts through it on contact.
##
## Every constant comes from [RlConst]. Two things here are worth knowing
## about rather than reading off a table.
##
## The first is that a rigid body collision alone does not make a Rocket League
## hit. The game adds an impulse on top, aimed along the line from the car to
## the ball but flattened vertically and blended toward the car's nose, and
## scaled by a curve that falls off as the closing speed rises. That is what
## turns a fast car into a shot rather than a nudge, and it is modelled here on
## RocketSim's own ball and car collision routine.
##
## The second is [method predict], which the AI leans on constantly. It steps a
## copy of the ball forward under gravity and drag, bouncing it off the six
## planes of the arena. It ignores the rounded corners and every car, so it is
## a guide rather than a guarantee, and the AI treats it as one.

signal touched(car: RlCar) ## A car hit the ball; the match credits goals from this.

const PREDICT_STEP: float = 1.0 / 60.0 ## Prediction runs at the physics tick.
const PREDICT_MAX_TIME: float = 6.0 ## Nothing asks further ahead than this.

@onready var _mesh: MeshInstance3D = $Mesh

var _last_touch_by: RlCar = null ## Who hit it last, for crediting a goal.
var _touch_cooldown: Dictionary = {} ## Car to seconds left, so one hit is not counted sixty times.


func _ready() -> void:
	mass = RlConst.BALL_MASS
	# Godot's linear damp is an acceleration proportional to velocity, which is
	# the same shape as Rocket League's net-velocity drag multiplier
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = RlConst.BALL_DRAG
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.0
	contact_monitor = true
	max_contacts_reported = 8
	can_sleep = false
	add_to_group(&"rl_ball")
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	for car: Variant in _touch_cooldown.keys():
		_touch_cooldown[car] = (_touch_cooldown[car] as float) - delta
		if (_touch_cooldown[car] as float) <= 0.0:
			_touch_cooldown.erase(car)
	# the game hard caps both of these rather than letting a collision stack
	if linear_velocity.length() > RlConst.BALL_MAX_SPEED:
		linear_velocity = linear_velocity.normalized() * RlConst.BALL_MAX_SPEED
	if angular_velocity.length() > RlConst.BALL_MAX_ANGULAR:
		angular_velocity = angular_velocity.normalized() * RlConst.BALL_MAX_ANGULAR


## Who touched the ball last, which is who gets the goal.
func last_touch() -> RlCar:
	return _last_touch_by if is_instance_valid(_last_touch_by) else null


## Put the ball back on the centre spot, still. Used by every kickoff.
func reset_to(where: Vector3) -> void:
	_last_touch_by = null
	_touch_cooldown.clear()
	freeze = true
	global_position = where
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = false


## Where the ball will be [param seconds] from now, stepping it forward under
## gravity and drag and reflecting it off the floor, ceiling and four walls.
## The rounded corners and the cars are not simulated, so this drifts near a
## corner; the AI only ever uses it to decide where to drive, not to aim.
func predict(seconds: float) -> Vector3:
	var position_now: Vector3 = global_position
	var velocity: Vector3 = linear_velocity
	var steps: int = int(minf(seconds, PREDICT_MAX_TIME) / PREDICT_STEP)
	for _i: int in steps:
		velocity.y -= RlConst.GRAVITY * PREDICT_STEP
		velocity -= velocity * RlConst.BALL_DRAG * PREDICT_STEP
		position_now += velocity * PREDICT_STEP
		var bounced: Dictionary = _bounce(position_now, velocity)
		position_now = bounced["position"] as Vector3
		velocity = bounced["velocity"] as Vector3
	return position_now


## One step of the prediction's wall handling: push the ball back inside the
## box and mirror the velocity through the face it left by, losing Rocket
## League's 40 percent on the way.
func _bounce(at: Vector3, velocity: Vector3) -> Dictionary:
	var radius: float = RlConst.BALL_RADIUS
	var limit_x: float = RlConst.ARENA_EXTENT_X - radius
	var limit_z: float = RlConst.ARENA_EXTENT_Y - radius
	var ceiling: float = RlConst.ARENA_HEIGHT - radius
	if at.y < radius:
		at.y = radius
		velocity.y = absf(velocity.y) * RlConst.BALL_RESTITUTION
	elif at.y > ceiling:
		at.y = ceiling
		velocity.y = -absf(velocity.y) * RlConst.BALL_RESTITUTION
	if absf(at.x) > limit_x:
		at.x = signf(at.x) * limit_x
		velocity.x = -absf(velocity.x) * signf(at.x) * RlConst.BALL_RESTITUTION
	# the goal mouths are open, so the ball only meets the back wall outside them
	if absf(at.z) > limit_z and absf(at.x) > RlConst.GOAL_HALF_WIDTH:
		at.z = signf(at.z) * limit_z
		velocity.z = -absf(velocity.z) * signf(at.z) * RlConst.BALL_RESTITUTION
	return {"position": at, "velocity": velocity}


## Rocket League adds an impulse on top of the rigid body response whenever a
## car touches the ball, which is the whole reason a hit carries. The direction
## runs from the car to the ball with the vertical part scaled down, blended
## toward the car's nose; the size follows a falloff curve on the closing speed
## and is capped. The scales, the curve and the cap are all published values in
## [RlConst]; the order they are combined in is read off RocketSim's
## routine rather than stated anywhere, so it is an approximation of the real
## thing rather than a transcription of it.
func _on_body_entered(body: Node) -> void:
	var car: RlCar = body as RlCar
	if car == null or not is_instance_valid(car):
		return
	if _touch_cooldown.has(car):
		return
	_touch_cooldown[car] = RlConst.BUMP_COOLDOWN
	_last_touch_by = car
	touched.emit(car)

	var closing: float = (linear_velocity - car.linear_velocity).length()
	if closing <= 0.0:
		return
	var direction: Vector3 = global_position - car.global_position
	direction.y *= RlConst.BALL_CAR_IMPULSE_Z_SCALE
	if direction.length_squared() <= 0.0:
		return
	direction = direction.normalized()
	direction = (direction + car.nose() * RlConst.BALL_CAR_IMPULSE_FORWARD_SCALE).normalized()
	var scale_factor: float = RlConst.curve(RlConst.BALL_CAR_IMPULSE_CURVE, closing)
	var delta_velocity: float = minf(closing * scale_factor, RlConst.BALL_CAR_IMPULSE_MAX_DELTA)
	apply_central_impulse(direction * delta_velocity * mass)
