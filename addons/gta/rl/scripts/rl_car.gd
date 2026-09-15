class_name RlCar
extends Vehicle
## A Rocket League battle car.
##
## Rocket League runs its cars on Bullet's raycast vehicle and Godot's
## [VehicleBody3D] is a port of that same raycast vehicle, so the body, wheels
## and suspension in [Vehicle] underneath are a fair match already.
## Everything above them is this file, and all of it comes from Rocket League's
## own published numbers in [RlConst]. The order of the step follows
## RocketSim's: wheels, then air control, then jump, then auto-flip, then the
## dodge, then the sticky force and auto-roll, then boost.
##
## Four things are worth knowing beyond the constants.
##
## The sticky force is why this can be played on the walls. A car with any wheel
## on a surface is pressed into that surface, hard enough on a vertical one to
## hold its own weight, and that single term is the difference between a game
## played on the floor and Rocket League.
##
## Auto-roll is what keeps it there. The sticky force only holds a car that is
## square to the surface, and this is the turn that brings a crooked one back.
##
## The ground is three wheels, not one. On one or two the game hands you air
## control and lets you flip, which is how a car tipped into a corner gets out.
##
## Input is eight values, the same eight RocketSim's [code]CarControls[/code]
## carries, and yaw and roll are separate. A person on the default bindings
## drives one at a time through the air roll modifier; an AI, or a rebinding,
## can drive both at once, which is what directional air roll is.
##
## The car takes input from one of two places and does not care which. A seated
## [Player] reaches it through [method ride], the rideable contract
## [Vehicle] defines. A [RlAi] reaches it through [method
## set_rocket_input].

signal boost_changed(amount: float, maximum: float) ## The tank moved, for the HUD.
signal jumped(double: bool) ## Left the ground, or jumped again in the air.
signal dodged() ## A flip started.
signal auto_flipped() ## Threw itself back over after landing upside down.
signal bumped(other: RlCar) ## Knocked another car about without wrecking it.
signal supersonic_changed(supersonic: bool) ## Crossed the speed the trail turns on at.
signal ball_cam_changed(on: bool) ## The camera locked onto the ball, or let go of it.
signal demolished(by: RlCar) ## Wrecked by an opponent at speed.
signal respawned() ## Back in play after [constant RlConst.DEMO_RESPAWN_TIME].

## Which end of the pitch this car defends. Blue defends positive z in Godot's
## axes, which is Rocket League's negative y; see [method RlConst.to_godot].
enum Team { BLUE, ORANGE }

const SURFACE_PROBE: float = 1.2 ## How far to feel for the surface under the wheels.
const BOOST_PITCH_RANGE: Vector2 = Vector2(0.9, 1.25) ## Boost note, idle to flat out.

@export var team: Team = Team.BLUE
@export var is_ai: bool = false ## An AI car ignores [method ride] and waits for [method set_rocket_input].

@export_group("Rocket League Actions")
@export var keyboard_boost_action: StringName = &"shoot" ## Keyboard: left click.
## Pad: the B button. Not the left trigger, which is already reverse on a pad; the two used to share it,
## so pulling the trigger both braked and boosted.
@export var pad_boost_action: StringName = &"sprint"
@export var keyboard_jump_action: StringName = &"crouch" ## Keyboard: control.
## Pad: the A button, as in Rocket League. On this HUD the A slot carries the "action" action; the "jump"
## action sits on Y and the Space key, which is why a keyboard accelerates with it.
@export var pad_jump_action: StringName = &"action"
@export var keyboard_air_roll_action: StringName = &"throw" ## Keyboard: T, the same key as the handbrake.
@export var pad_air_roll_action: StringName = &"throw"
## Stick forward, which pitches the nose down, the way Rocket League has it.
@export var pitch_forward_action: StringName = &"move_up" ## Keyboard: W.
@export var pitch_back_action: StringName = &"move_down" ## Keyboard: S, nose up.
@export var keyboard_ball_cam_action: StringName = &"ability" ## Keyboard: Q.
@export var pad_ball_cam_action: StringName = &"ability" ## Pad: the left bumper.

@export_group("Ball Cam")
## Rocket League opens every kickoff in ball cam, and so does this. Turn it off
## for a car that should start looking where it is pointing instead.
@export var starts_in_ball_cam: bool = true

var boost: float = RlConst.BOOST_START: set = _set_boost
var is_ball_cam: bool = false: set = _set_ball_cam
var is_supersonic: bool = false
var is_demolished: bool = false
var on_ground: bool = false ## Three wheels or more, the way Rocket League counts it.
var wheels_down: int = 0 ## How many wheels are touching this frame.

var _throttle: float = 0.0 ## Minus one full reverse, plus one full throttle.
var _steer_axis: float = 0.0 ## Positive is left, matching the project's own move axis.
var _pitch: float = 0.0 ## Positive is nose up, which is stick back.
var _yaw: float = 0.0 ## Positive turns the nose left in the air.
var _roll: float = 0.0 ## Positive rolls the car to its left.
var _boosting: bool = false
var _jump_held: bool = false
var _jump_was_held: bool = false ## Last frame, so a press can be told from a hold.
var _powerslide: bool = false

var _jump_time: float = 0.0 ## Seconds the current jump has been held, up to JUMP_MAX_TIME.
var _is_jumping: bool = false
var _has_double_jump: bool = false
var _airborne_for: float = 0.0 ## Since the wheels last touched, for the double jump window.
var _flip_time: float = -1.0 ## Seconds into a dodge, or negative when not dodging.
var _flip_torque: Vector3 = Vector3.ZERO ## Local pitch and roll amounts held for the dodge.
var _autoflip_time: float = 0.0 ## Seconds left of an auto-flip, or zero.
var _autoflip_direction: float = 1.0
var _pitchlock_time: float = 0.0 ## Pitch is not yours for a second after a dodge starts.
var _supersonic_timer: float = 0.0
var _boost_min_timer: float = 0.0 ## A tap of boost still burns BOOST_MIN_TIME.
var _demo_timer: float = 0.0
var _slide: float = 0.0 ## The powerslide is analogue, and rises and falls at its own rates.
var _base_friction: float = 1.0 ## Wheel grip as the scene set it, restored when the slide ends.
var _bump_cooldowns: Dictionary = {} ## Car to seconds, so one shunt is not counted every frame.

@onready var sfx_boost: AudioStreamPlayer3D = $SFXBoost
@onready var sfx_jump: AudioStreamPlayer3D = $SFXJump
@onready var sfx_impact: AudioStreamPlayer3D = $SFXImpact


func _ready() -> void:
	super()
	mass = RlConst.CAR_MASS
	contact_monitor = true
	max_contacts_reported = 8
	can_sleep = false
	add_to_group(&"rl_cars")
	add_to_group(&"rl_blue" if team == Team.BLUE else &"rocket_orange")
	if not wheels.is_empty() and wheels[0] != null:
		_base_friction = wheels[0].wheel_friction_slip
	_apply_rocket_camera()
	body_entered.connect(_on_body_entered)
	# the car makes its own noise now rather than inheriting a road car's engine
	jumped.connect(_on_jumped)
	dodged.connect(_on_dodged)
	bumped.connect(_on_bumped)


## The way the car is pointing. This chassis is built nose along positive z,
## which is the opposite of Godot's usual convention but is where the steered
## wheels sit, so every axis below is taken from here rather than written out.
func nose() -> Vector3:
	return global_transform.basis.z


## The car's right. With the nose on positive z the right hand side is negative
## x, which is the sign that catches people out when reading this.
func flank() -> Vector3:
	return -global_transform.basis.x


## The car's roof, which is the direction a jump pushes.
func roof() -> Vector3:
	return global_transform.basis.y


## Which way this team attacks along Godot's z. Blue defends positive z, so it
## drives toward negative z.
func attack_direction() -> float:
	return -1.0 if team == Team.BLUE else 1.0


## The middle of the goal this car is trying to score in.
func target_goal() -> Vector3:
	return Vector3(0.0, RlConst.GOAL_HEIGHT * 0.5, RlConst.GOAL_LINE_Y * attack_direction())


## The middle of the goal this car is defending.
func own_goal() -> Vector3:
	return Vector3(0.0, RlConst.GOAL_HEIGHT * 0.5, -RlConst.GOAL_LINE_Y * attack_direction())


## The eight inputs a Rocket League car has, in the order RocketSim's
## [code]CarControls[/code] lists them. [param jump] is the button's state
## rather than an edge, because the length of the hold sets the height of the
## jump. Yaw and roll are separate: a person on the default bindings drives one
## at a time, an AI can drive both.
func set_rocket_input(throttle: float, steer: float, pitch: float, yaw: float,
		roll: float, jump: bool, boosting: bool, powerslide: bool) -> void:
	freeze = false
	_throttle = clampf(throttle, -1.0, 1.0)
	_steer_axis = clampf(steer, -1.0, 1.0)
	_pitch = clampf(pitch, -1.0, 1.0)
	_yaw = clampf(yaw, -1.0, 1.0)
	_roll = clampf(roll, -1.0, 1.0)
	_jump_held = jump
	_boosting = boosting
	_powerslide = powerslide


## Nothing pressed, which is what a countdown and a wreck both want.
func release_controls() -> void:
	set_rocket_input(0.0, 0.0, 0.0, 0.0, 0.0, false, false, false)


## Refill the tank, which every kickoff does.
func refill_boost(to: float = RlConst.BOOST_START) -> void:
	boost = to


## Add boost from a pad, capped at a full tank.
func collect_boost(amount: float) -> void:
	boost = minf(boost + amount, RlConst.BOOST_MAX)


## Put the car back on a spot, still and upright, and clear everything the
## previous life was in the middle of. Used by kickoffs, resets and respawns.
func place_at(where: Vector3, yaw: float) -> void:
	freeze = true
	global_position = where
	global_rotation = Vector3(0.0, yaw, 0.0)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_is_jumping = false
	_has_double_jump = false
	_flip_time = -1.0
	_autoflip_time = 0.0
	_pitchlock_time = 0.0
	_jump_time = 0.0
	_airborne_for = 0.0
	_slide = 0.0
	_supersonic_timer = 0.0
	release_controls()
	freeze = false


## Wreck the car: it disappears for three seconds and comes back on its own
## back wall, which is what a supersonic hit does in Rocket League.
func demolish(by: RlCar = null) -> void:
	if is_demolished:
		return
	is_demolished = true
	_demo_timer = RlConst.DEMO_RESPAWN_TIME
	freeze = true
	visible = false
	# nothing should hit a wreck, so it leaves the physics world entirely
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)
	if is_instance_valid(sfx_impact):
		sfx_impact.play()
	demolished.emit(by)


## Rideable contract: seat the player, then take the ball cam lock. The camera
## only exists as a live thing once the chassis has started it.
func mount(rider: Player) -> void:
	super(rider)
	is_ball_cam = starts_in_ball_cam


## A driver with no body: the demo's way in. Opens in ball cam the way a
## kickoff does.
func take_the_wheel() -> void:
	super()
	is_ball_cam = starts_in_ball_cam


## Rideable contract: toggles first, then up to the chassis, which owns the exit.
func ride_input(rider: Player, event: InputEvent) -> void:
	if read_toggles(event):
		return
	super(rider, event)


## The ball cam is a toggle rather than a hold, so it is read off the event
## rather than polled. True when the event was one of this car's toggles. A
## seated [Player] and a [HumanDriver] both come through here.
func read_toggles(event: InputEvent) -> bool:
	if event.is_action_pressed(_action(keyboard_ball_cam_action, pad_ball_cam_action)):
		is_ball_cam = not is_ball_cam
		return true
	return false


## Rideable contract, filled from the player's own buttons. The Riding state has
## already pinned the rider to the seat by now; the only thing a body adds to
## reading the pad is that a paused or ragdolling one lets go of it.
func ride(rider: Player, _delta: float) -> void:
	if rider.is_paused or rider.is_ragdolling:
		release_controls()
		return
	read_controls()


## The pad, off the buttons. This is where the eight inputs are cut back down to
## the default control scheme: one stick, with the air roll button deciding
## whether its sideways axis is a yaw or a roll. A rebinding or an AI can drive
## both at once. A seated [Player] and a [HumanDriver] both come through here;
## [member Vehicle.input_type] says which bindings to read.
func read_controls() -> void:
	var forward: bool = Input.is_action_pressed(_action(keyboard_accelerate_action, pad_accelerate_action))
	var backward: bool = Input.is_action_pressed(_action(keyboard_brake_action, pad_brake_action))
	var stick: float = Input.get_axis(&"move_right", &"move_left")
	var air_rolling: bool = Input.is_action_pressed(_action(keyboard_air_roll_action, pad_air_roll_action))
	set_rocket_input(
		(1.0 if forward else 0.0) - (1.0 if backward else 0.0),
		stick,
		Input.get_axis(pitch_forward_action, pitch_back_action),
		0.0 if air_rolling else stick,
		stick if air_rolling else 0.0,
		Input.is_action_pressed(_action(keyboard_jump_action, pad_jump_action)),
		Input.is_action_pressed(_action(keyboard_boost_action, pad_boost_action)),
		Input.is_action_pressed(_action(keyboard_handbrake_action, pad_handbrake_action)))


## Rideable contract: what the on-screen controls say while driving one of
## these. The labels name what the button does, never the key it sits on.
func get_contextual_controls(input_type_: int) -> Dictionary:
	var controls: Dictionary = {
		"left_joystick": "Steer\nPitch",
		"right_joystick": "Camera",
		"joypad_button_10": "Powerslide\nAir Roll",
		"joypad_button_9": "Ball Cam",
	}
	# each label sits on the slot that carries the action the car reads for that device, and the
	# slot faces are fixed: on a keyboard Y is the Space key, B is Shift, L3 is Ctrl, RT is the mouse
	if input_type_ == Controls.InputType.KEYBOARD_MOUSE:
		controls["joypad_button_3"] = "Accelerate"
		controls["joypad_button_1"] = "Reverse"
		controls["joypad_button_7"] = "Jump"
		controls["joypad_axis_5_plus"] = "Boost"
	else:
		controls["joypad_axis_5_plus"] = "Accelerate"
		controls["joypad_axis_4_plus"] = "Reverse"
		controls["joypad_button_0"] = "Jump"
		controls["joypad_button_1"] = "Boost"
	return controls


## The step, in RocketSim's own order.
func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if is_demolished:
		_tick_respawn(delta)
		return
	for other: Variant in _bump_cooldowns.keys():
		_bump_cooldowns[other] = (_bump_cooldowns[other] as float) - delta
		if (_bump_cooldowns[other] as float) <= 0.0:
			_bump_cooldowns.erase(other)

	wheels_down = wheels_in_contact()
	on_ground = wheels_down >= RlConst.WHEELS_FOR_GROUND
	_airborne_for = 0.0 if on_ground else _airborne_for + delta
	if on_ground:
		# landing gives the second jump back, and ends any dodge still running
		_has_double_jump = true
		if _flip_time >= 0.0 and _flip_time > RlConst.FLIP_TORQUE_MIN_TIME:
			_flip_time = -1.0

	var pressed: bool = _jump_held and not _jump_was_held
	# the wheels still do their work on one or two, so this is not gated on
	# being properly on the ground
	if wheels_down > 0:
		_drive(delta)
	else:
		steering = 0.0
		apply_wheel_forces(0.0, 0.0)
	# air control is for a car with nothing at all touching; a dodge keeps
	# turning the car whatever it is resting on
	if wheels_down == 0 and _flip_time < 0.0 and _autoflip_time <= 0.0:
		_air_control(delta)
	_tick_jump(delta, pressed)
	_tick_autoflip(delta, pressed)
	_tick_flip(delta)
	_pitchlock_time = maxf(0.0, _pitchlock_time - delta)
	if wheels_down > 0:
		_apply_sticky_force()
	# partly in contact and driving: line the car up with what it is on. Four
	# wheels down already means it is lined up, which is why the game only runs
	# this in between, and it runs on the chassis touching as well as the
	# wheels, which is the case that matters against a wall.
	if wheels_down < wheels.size() and absf(_throttle) > RlConst.THROTTLE_DEADZONE:
		_apply_auto_roll(delta)
	_tick_boost(delta)
	_tick_supersonic(delta)

	if linear_velocity.length() > RlConst.CAR_MAX_SPEED:
		linear_velocity = linear_velocity.normalized() * RlConst.CAR_MAX_SPEED
	if angular_velocity.length() > RlConst.CAR_MAX_ANGULAR:
		angular_velocity = angular_velocity.normalized() * RlConst.CAR_MAX_ANGULAR
	_jump_was_held = _jump_held


## Rocket League presses a car into whatever surface its wheels are on. On flat
## ground that is half a gravity of extra downforce and barely noticeable; on a
## vertical wall it is one and a half, which is more than the car's own weight
## and is the entire reason the game can be played up there.
##
## The scale only gains its full value while the throttle is down or the car is
## still rolling, so letting go on a wall drops you off it.
func _apply_sticky_force() -> void:
	var up: Vector3 = _surface_up()
	var rolling: bool = absf(linear_velocity.dot(nose())) > RlConst.STOPPING_SPEED
	var scale: float = RlConst.STICKY_FORCE_BASE
	if absf(_throttle) > RlConst.THROTTLE_DEADZONE or rolling:
		scale += 1.0 - absf(up.y)
	# gravity is negative in Rocket League's own figures, which is what turns
	# this into a force into the surface rather than away from it
	apply_central_force(-up * scale * RlConst.GRAVITY * mass)


## Turn the car to line up with whatever it is standing on, and pull it onto
## that surface while doing it.
##
## The sticky force holds a car against a wall, but only for as long as the car
## is square to it. Landing on a wall at an angle, or clipping a corner, leaves
## it crooked and it slides off. This is what settles it.
##
## Rocket League runs it only while the throttle is down and the car is partly
## in contact, which is why letting go up there still drops you off.
func _apply_auto_roll(delta: float) -> void:
	# with no wheels down there is still a surface to line up with as long as
	# the car is against one, which is what carries it through the turn onto a
	# wall; with nothing anywhere near, there is nothing to line up with
	var found: Dictionary = _surface_hit()
	if found.is_empty():
		return
	var up: Vector3 = found["normal"] as Vector3
	# RocketSim splits this into a roll term and a pitch term with a sign on
	# each. The turn they add up to is the one that brings the roof round to
	# the surface, and taking it as a single cross product says the same thing
	# without four signs to get the wrong way round: the axis is the one that
	# rotates the roof onto the normal, and its length is the sine of how far
	# out the car is, so it fades to nothing as the car comes square.
	var align: Vector3 = roof().cross(up)
	if align.length_squared() < 0.000001:
		return # already square with it
	angular_velocity += align * RlConst.AUTOROLL_TORQUE * delta
	apply_central_force(-up * RlConst.AUTOROLL_FORCE * mass)


## The surface the wheels are on, as an up vector.
func _surface_up() -> Vector3:
	var hit: Dictionary = _surface_hit()
	return (hit["normal"] as Vector3) if not hit.is_empty() else roof()


## The raycast behind [method _surface_up], kept separate because auto-roll
## needs to know whether anything was found at all rather than fall back to the
## car's own roof. Godot's wheels do not report their contact normals, so this
## is how a wall is felt: on one, the ray down through the car's own floor
## points at the wall and comes back with the wall's normal.
func _surface_hit() -> Dictionary:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position, global_position - roof() * SURFACE_PROBE)
	query.exclude = [get_rid()]
	return space.intersect_ray(query)


## On the ground the wheels do the work. The throttle curve is handed to them
## as an engine force and the steering curve as a steering angle, which is what
## those two curves describe in the first place.
func _drive(delta: float) -> void:
	var speed: float = linear_velocity.dot(nose())
	var forward_speed: float = absf(speed)

	_slide = clampf(_slide + (RlConst.POWERSLIDE_RISE_RATE if _powerslide
		else -RlConst.POWERSLIDE_FALL_RATE) * delta, 0.0, 1.0)
	var lock: float = lerpf(
		RlConst.curve(RlConst.STEER_CURVE, forward_speed),
		RlConst.curve(RlConst.POWERSLIDE_STEER_CURVE, forward_speed),
		_slide)
	steering = lock * _steer_axis
	# a powerslide is lost grip, not a locked wheel: the rear end comes round.
	# Coasting on a steep surface loses grip too, which is what drops a car off
	# a wall the moment it stops driving.
	var coasting: float = 1.0 if absf(_throttle) > RlConst.THROTTLE_DEADZONE \
		else RlConst.curve(RlConst.NON_STICKY_FRICTION_CURVE, absf(_surface_up().y))
	for wheel: VehicleWheel3D in wheels:
		if wheel == null:
			continue
		wheel.wheel_friction_slip = _base_friction * coasting * lerpf(
			1.0, RlConst.HANDBRAKE_LAT_FRICTION, _slide if not wheel.use_as_steering else _slide * 0.5)

	var drive: float = 0.0
	var stop: float = 0.0
	if absf(_throttle) > RlConst.THROTTLE_DEADZONE:
		var torque_factor: float = RlConst.curve(RlConst.DRIVE_TORQUE_CURVE, forward_speed)
		drive = mass * RlConst.THROTTLE_ACCEL * torque_factor * _throttle
		# throttle against the direction of travel is a brake, not a reverse
		if not is_zero_approx(speed) and signf(_throttle) != signf(speed) \
				and forward_speed > RlConst.STOPPING_SPEED:
			stop = mass * RlConst.BRAKE_ACCEL
			drive = 0.0
	else:
		# coasting is a gentle brake, and becomes a full one once nearly stopped
		stop = mass * (RlConst.BRAKE_ACCEL if forward_speed <= RlConst.STOPPING_SPEED
			else RlConst.COAST_ACCEL)
	apply_wheel_forces(drive, stop)


## Off the ground the wheels are doing nothing, so the car is flown. Pitch, yaw
## and roll are angular accelerations against a damping term that falls away as
## the stick is pushed, which is the shape RLUtilities gives for Rocket League's
## air control.
func _air_control(delta: float) -> void:
	# nose up is a turn about the car's left, a turn to the left is about its
	# roof, and a roll to the left is about its nose reversed; with the chassis
	# built along positive z these are not the axes they would be otherwise
	var pitch_axis: Vector3 = -global_transform.basis.x
	var yaw_axis: Vector3 = global_transform.basis.y
	var roll_axis: Vector3 = -global_transform.basis.z
	# a dodge takes the pitch axis away for a second from the moment it starts,
	# which is why a flip cannot simply be pitched out of and why cancelling one
	# is done on the other axes
	var inputs: Vector3 = Vector3(0.0 if _pitchlock_time > 0.0 else _pitch, _yaw, _roll)
	var axes: Array[Vector3] = [pitch_axis, yaw_axis, roll_axis]
	var spin: Vector3 = Vector3(
		pitch_axis.dot(angular_velocity),
		yaw_axis.dot(angular_velocity),
		roll_axis.dot(angular_velocity))
	var change: Vector3 = Vector3.ZERO
	for axis: int in 3:
		var accel: float = RlConst.AIR_CONTROL_TORQUE[axis] * inputs[axis] \
			- RlConst.AIR_CONTROL_DAMPING[axis] * spin[axis] * (1.0 - absf(inputs[axis]))
		change += axes[axis] * accel
	angular_velocity += change * delta

	if absf(_throttle) > RlConst.THROTTLE_DEADZONE:
		apply_central_force(nose() * mass * RlConst.AIR_THROTTLE_ACCEL * _throttle)


## The jump is an instant kick plus whatever is added while the button is held,
## up to a fifth of a second. A second press in the air either jumps again or,
## with the stick pushed, dodges.
func _tick_jump(delta: float, pressed: bool) -> void:
	var up: Vector3 = roof()

	if _is_jumping:
		_jump_time += delta
		if _jump_held and _jump_time <= RlConst.JUMP_MAX_TIME:
			apply_central_force(up * mass * RlConst.JUMP_ACCEL)
		elif _jump_time >= RlConst.JUMP_MIN_TIME:
			_is_jumping = false

	if not pressed:
		return
	if on_ground:
		_is_jumping = true
		_jump_time = 0.0
		_has_double_jump = true
		apply_central_impulse(up * mass * RlConst.JUMP_IMMEDIATE)
		jumped.emit(false)
		return
	if not _has_double_jump or _airborne_for > RlConst.DOUBLE_JUMP_MAX_DELAY:
		return
	if _autoflip_time > 0.0:
		return
	_has_double_jump = false
	# the deadzone is the sum of the three stick axes, not any one of them
	if absf(_yaw) + absf(_pitch) + absf(_roll) >= RlConst.FLIP_DEADZONE:
		_start_flip()
	else:
		apply_central_impulse(up * mass * RlConst.JUMP_IMMEDIATE)
		jumped.emit(true)


## Land upside down and a car is stuck on its roof with its wheels in the air,
## because a jump pushes through the roof and the roof is against the floor.
## Rocket League's answer is to throw the car back over on the next press.
func _tick_autoflip(delta: float, pressed: bool) -> void:
	if _autoflip_time > 0.0:
		_autoflip_time -= delta
		angular_velocity += nose() * RlConst.AUTOFLIP_TORQUE * _autoflip_direction * delta
		return
	if not pressed or on_ground:
		return
	# the wheels are pointing at the sky, so what is underneath has to be found
	# by looking straight down rather than through the car's own floor
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position, global_position + Vector3.DOWN * SURFACE_PROBE)
	query.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty() or (hit["normal"] as Vector3).y < RlConst.AUTOFLIP_NORMAL_MIN:
		return
	var roll: float = global_rotation.z
	if absf(roll) <= RlConst.AUTOFLIP_ROLL_MIN:
		return
	_autoflip_time = RlConst.AUTOFLIP_TIME * (absf(roll) / PI)
	_autoflip_direction = 1.0 if roll > 0.0 else -1.0
	apply_central_impulse(-roof() * mass * RlConst.AUTOFLIP_IMPULSE)
	auto_flipped.emit()


## A dodge throws the car along the ground in the direction the stick is pushed
## and rolls it over while it travels.
##
## Two details are easy to get wrong and both are taken from RocketSim. The
## impulse is scaled from one at a standstill up to its published maximum at top
## speed rather than applied flat, so a dodge from rest is worth the same
## whichever way it is thrown. And it is applied in the horizontal plane rather
## than along the car's own nose, so a dodge taken nose-down still carries the
## car sideways instead of into the floor.
func _start_flip() -> void:
	# Rocket League's dodge direction: forward from the pitch reversed, because
	# stick forward is nose down, and sideways from yaw and roll together
	var direction: Vector2 = Vector2(-_pitch, _yaw + _roll)
	if absf(direction.x) < 0.1 and absf(direction.y) < 0.1:
		return
	direction = direction.normalized()
	if absf(direction.x) < 0.1:
		direction.x = 0.0
	if absf(direction.y) < 0.1:
		direction.y = 0.0
	if direction == Vector2.ZERO:
		return

	var forward_speed: float = linear_velocity.dot(nose())
	var speed_ratio: float = absf(forward_speed) / RlConst.CAR_MAX_SPEED
	var backwards: bool = direction.x < 0.0 if absf(forward_speed) < 1.0 \
		else (direction.x >= 0.0) != (forward_speed >= 0.0)
	var along: float = RlConst.FLIP_BACKWARD_MAX_SCALE if backwards \
		else RlConst.FLIP_FORWARD_MAX_SCALE

	var throw: Vector2 = direction * RlConst.FLIP_INITIAL_VEL
	throw.x *= (along - 1.0) * speed_ratio + 1.0
	throw.y *= (RlConst.FLIP_SIDE_MAX_SCALE - 1.0) * speed_ratio + 1.0
	if backwards:
		throw.x *= RlConst.FLIP_BACKWARD_SCALE_X

	var flat_nose: Vector3 = Vector3(nose().x, 0.0, nose().z)
	if flat_nose.length_squared() < 0.001:
		flat_nose = Vector3(0.0, 0.0, 1.0)
	flat_nose = flat_nose.normalized()
	var flat_side: Vector3 = flat_nose.rotated(Vector3.UP, -PI * 0.5)
	apply_central_impulse((flat_nose * throw.x + flat_side * throw.y) * mass)

	# held as a pair of local amounts rather than a world vector, because the
	# car is turning over while the dodge runs and its axes turn with it: x is
	# the pitch over the nose, z the roll onto a flank
	_flip_torque = Vector3(RlConst.FLIP_TORQUE_PITCH * direction.x, 0.0,
		RlConst.FLIP_TORQUE_ROLL * direction.y)
	_flip_time = 0.0
	_pitchlock_time = RlConst.FLIP_PITCHLOCK_TIME
	dodged.emit()


func _tick_flip(delta: float) -> void:
	if _flip_time < 0.0:
		return
	_flip_time += delta
	if _flip_time >= RlConst.FLIP_TORQUE_TIME:
		_flip_time = -1.0
		return
	# a forward dodge pitches the nose down and over, a side dodge rolls onto
	# that flank, which is a turn about the nose
	angular_velocity += (global_transform.basis.x * _flip_torque.x
		+ global_transform.basis.z * _flip_torque.z) * delta
	# through a short window the game kills downward speed, which is what keeps
	# a dodge flat instead of driving the car into the floor
	if _flip_time >= RlConst.FLIP_Z_DAMP_START and _flip_time <= RlConst.FLIP_Z_DAMP_END \
			and linear_velocity.y < 0.0:
		linear_velocity.y = 0.0


## Boost is a flat acceleration along the nose for as long as there is fuel,
## and it is the only way past 14.1 m/s. A tap still costs a tenth of a second,
## so feathering it is not free.
func _tick_boost(delta: float) -> void:
	_boost_min_timer = maxf(0.0, _boost_min_timer - delta)
	var wants: bool = _boosting and boost > 0.0
	if wants and _boost_min_timer <= 0.0:
		_boost_min_timer = RlConst.BOOST_MIN_TIME
	var burning: bool = wants or _boost_min_timer > 0.0
	_update_boost_sound(burning)
	if not burning:
		return
	boost = maxf(0.0, boost - RlConst.BOOST_PER_SECOND * delta)
	if linear_velocity.length() >= RlConst.CAR_MAX_SPEED:
		return
	var accel: float = RlConst.BOOST_ACCEL_GROUND if on_ground else RlConst.BOOST_ACCEL_AIR
	apply_central_force(nose() * mass * accel)


## Supersonic latches: once it is reached the car stays supersonic for a second
## even after dropping back under the threshold, so the trail does not flicker.
func _tick_supersonic(delta: float) -> void:
	var speed: float = linear_velocity.length()
	var was: bool = is_supersonic
	if speed >= RlConst.SUPERSONIC_START:
		is_supersonic = true
		_supersonic_timer = RlConst.SUPERSONIC_MAINTAIN_TIME
	elif is_supersonic and speed >= RlConst.SUPERSONIC_MAINTAIN:
		_supersonic_timer -= delta
		is_supersonic = _supersonic_timer > 0.0
	else:
		is_supersonic = false
	if was != is_supersonic:
		supersonic_changed.emit(is_supersonic)


func _tick_respawn(delta: float) -> void:
	_demo_timer -= delta
	if _demo_timer > 0.0:
		return
	is_demolished = false
	visible = true
	set_collision_layer_value(1, true)
	set_collision_mask_value(1, true)
	var spot: Vector3 = RlConst.RESPAWN_SPOTS[randi() % RlConst.RESPAWN_SPOTS.size()]
	var side: float = attack_direction()
	place_at(
		Vector3(spot.x * -side, RlConst.CAR_RESPAWN_HEIGHT, spot.y * -side),
		RlConst.to_godot_yaw(spot.z) + (0.0 if team == Team.BLUE else PI))
	refill_boost()
	respawned.emit()


## Running into another car does one of two things. A supersonic hit on an
## opponent wrecks it. Anything else is a bump: the car that was hit is thrown,
## on a curve of the closing speed, which is a real defensive tool rather than
## the rigid body bounce it would otherwise be. Teammates can be bumped but not
## wrecked, the way the game has it.
func _on_body_entered(body: Node) -> void:
	var other: RlCar = body as RlCar
	if other == null or not is_instance_valid(other) or other == self:
		return
	if _bump_cooldowns.has(other) or other.is_demolished:
		return
	# it only counts if this car is closing on the other one
	var toward: Vector3 = other.global_position - global_position
	if toward.length_squared() < 0.0001:
		return
	var direction: Vector3 = toward.normalized()
	var closing: float = linear_velocity.dot(direction)
	if closing <= other.linear_velocity.dot(direction):
		return
	# and only if it landed on the bumper, so reversing into somebody is not a hit
	if toward.dot(nose()) < RlConst.BUMP_MIN_FORWARD_DIST:
		return
	_bump_cooldowns[other] = RlConst.BUMP_COOLDOWN

	if is_supersonic and other.team != team:
		other.demolish(self)
		return
	var curve: Array[Vector2] = RlConst.BUMP_GROUND_CURVE if other.on_ground \
		else RlConst.BUMP_AIR_CURVE
	var up: Vector3 = other.roof() if other.on_ground else Vector3.UP
	var travel: Vector3 = linear_velocity.normalized() if linear_velocity.length() > 0.01 \
		else direction
	# the curves give a velocity to hand over rather than a force to apply
	other.linear_velocity += travel * RlConst.curve(curve, closing) \
		+ up * RlConst.curve(RlConst.BUMP_UP_CURVE, closing)
	bumped.emit(other)


## Rocket League's chase camera, which is wider and much closer than a road
## car's. A battle car is only 1.2 metres long, so the camera sits back a few
## metres rather than the five and a half a road car needs, and the 110 degree
## field of view is what makes the pitch readable at all.
func _apply_rocket_camera() -> void:
	if not is_instance_valid(chase_camera):
		return
	chase_camera.pivot_height = RlConst.CAMERA_HEIGHT
	chase_camera.pitch = deg_to_rad(RlConst.CAMERA_ANGLE)
	var arm: SpringArm3D = chase_camera.get_node_or_null(^"SpringArm3D") as SpringArm3D
	if arm != null:
		arm.spring_length = RlConst.CAMERA_DISTANCE
	if is_instance_valid(camera):
		camera.fov = RlConst.CAMERA_FOV


## The boost note rises with the car's speed and stops with the tank. Extending
## [GtaCar] used to leave a battle car silent outright, because that engine
## audio only ever ran for a car driven through the road car's own drive input.
func _update_boost_sound(burning: bool) -> void:
	if not is_instance_valid(sfx_boost):
		return
	if not burning:
		if sfx_boost.playing:
			sfx_boost.stop()
		return
	sfx_boost.pitch_scale = lerpf(BOOST_PITCH_RANGE.x, BOOST_PITCH_RANGE.y,
		clampf(linear_velocity.length() / RlConst.CAR_MAX_SPEED, 0.0, 1.0))
	if not sfx_boost.playing:
		sfx_boost.play()


func _on_jumped(_double: bool) -> void:
	if is_instance_valid(sfx_jump):
		sfx_jump.play()


func _on_dodged() -> void:
	if is_instance_valid(sfx_jump):
		sfx_jump.play()


func _on_bumped(_other: RlCar) -> void:
	if is_instance_valid(sfx_impact):
		sfx_impact.play()


## Ball cam is the chase camera's lock-on pointed at the ball. The camera does
## the work; all this decides is whether it has something to hold onto.
func _set_ball_cam(value: bool) -> void:
	is_ball_cam = value
	if not is_instance_valid(chase_camera):
		return
	chase_camera.look_target = _find_ball() if value else null
	ball_cam_changed.emit(is_ball_cam)


## The one ball on the pitch. A kickoff moves it rather than replacing it, so
## the lock survives a goal.
func _find_ball() -> Node3D:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group(&"rl_ball") as Node3D


func _set_boost(value: float) -> void:
	var clamped: float = clampf(value, 0.0, RlConst.BOOST_MAX)
	if is_equal_approx(clamped, boost):
		return
	boost = clamped
	boost_changed.emit(boost, RlConst.BOOST_MAX)
