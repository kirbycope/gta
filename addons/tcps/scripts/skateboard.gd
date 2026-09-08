class_name Skateboard
extends Node3D
## Tim Cope's Pro Skater: a skateboard the Player picks up with "action" and rides through the Player's
## [Riding] state. The board owns the movement, the sounds and its own [SkateboardCamera]; the Player only
## lends its body, its input and its animations (requested through the rideable signals), and its Riding state
## makes [member camera] current and turns the Player's step-up ray off while the board owns the ground.
##
## The physics follows Neversoft's THUG skater (SkaterCorePhysicsComponent: maybe_straight_up, the vert tracking
## of do_in_air_physics, maybe_break_vert, do_jump, handle_ground_rotation). On the ground the board follows
## the floor normal, so speed carries up a transition and gravity along the surface slows the climb; transitions
## count as floor almost to vertical. Leaving a wall steeper than [constant VERT_ANGLE] is a vert launch: the
## velocity is rotated into the wall's vertical plane with its speed kept, and through the air the skater is held
## in that plane while the wall is still behind them, so they go up and come back down onto the same wall.
## Holding forward at the lip breaks vert instead and flies over the deck. Left and right spin the skater in the
## air, and every landing turns them to face the way they are rolling.

signal locomotion_requested(state_path: String, immediate: bool) ## Asks the rider to play an animation node.
signal locomotion_blend_requested(path: String, value: float) ## Asks the rider to set an animation blend value.
signal jump_requested ## Asks the rider to run its jump animation (the pop itself is applied here).

@export_category("Skateboarding Controls")
@export_group("Keyboard/Mouse Actions")
@export var keyboard_dismount_action: StringName = &"whistle"
@export var keyboard_jump_action: StringName = &"jump"
@export var keyboard_sprint_action: StringName = &"sprint"
@export var keyboard_kick_push_action: StringName = &"move_up"

@export_group("Controller/Touch Actions")
@export var pad_dismount_action: StringName = &"whistle"
@export var pad_jump_action: StringName = &"jump"
@export var pad_sprint_action: StringName = &"sprint"
@export var pad_kick_push_action: StringName = &"move_up"

const LOCOMOTION: String = "SkateboardingLocomotion" ## The rider's rolling animation node.
const KICK_PUSH: String = "SkateboardingKickPush" ## The rider's push-off animation node.
const LOCOMOTION_BLEND_PATH: String = "parameters/LocomotionStateMachine/SkateboardingLocomotion/blend_position"

const SKATEBOARD_ACCELERATION: float = 12.0
const SKATEBOARD_MAX_SPEED: float = 10.0
const SKATEBOARD_FRICTION: float = 1.0 ## Rolling resistance while coasting (m/s^2); a board carries its speed up a transition after the push stops.
const SKATEBOARD_BRAKE: float = 6.0 ## Deceleration while holding back (m/s^2).
const SKATEBOARD_KICK_PUSH_ACCELERATION: float = 3.5
const SKATEBOARD_KICK_PUSH_SPEED_THRESHOLD: float = 0.1
const SKATEBOARD_HIGH_SPEED_TURN_FACTOR: float = 0.65
const SKATEBOARD_SIDE_VELOCITY_FACTOR: float = 0.1
const SKATEBOARD_TURN_SPEED: float = 1.8
const RAMP_FLOOR_MAX_ANGLE: float = deg_to_rad(88.0) ## Transitions stay "floor" almost to vertical, so the board rides them instead of hitting a wall.
const RAMP_FLOOR_SNAP_LENGTH: float = 1.0 ## Keeps the board glued to a curving transition at speed.
const VERT_ANGLE: float = deg_to_rad(50.0) ## Leaving a floor steeper than this is a vert launch.
const VERT_GRAVITY_SCALE: float = 1.0 ## THUG divides air gravity by a hang stat in vert air; a touch floatier than regular air.
const VERT_TRACK_REACH: float = 1.5 ## Metres behind the skater the wall must still be for vert tracking to hold (THUG's tracking feeler).
const BREAK_VERT_SPEED_SCALE: float = 0.5 ## Holding forward at the lip breaks vert: this share of the speed is thrown over the deck.
const BREAK_VERT_UP_SCALE: float = 0.8 ## And the climb is trimmed by this.
const AIR_SPIN_SPEED: float = TAU ## Radians per second the skater spins with left/right while airborne.
const OLLIE_SPEED: float = 5.0 ## Pop straight up (world up, never the wall's normal), on the press rather than at the animation's keyframe.
const VERT_OLLIE_SPEED: float = 3.0 ## The pop off a vert wall is smaller (THUG's air jump speed stat is below its flat one).
const OLLIE_GRACE: float = 0.15 ## Seconds after a pop during which the floor is ignored, so a curving wall cannot catch the board and bleed the pop.
const GROUND_GRAVITY_SCALE: float = 1.0
const AIR_GRAVITY_SCALE: float = 1.2 ## A little floatier than rolling, for hang time over the lip.
const MODEL_TILT_SPEED: float = 12.0 ## How fast the model leans onto a transition.
const AIR_TILT_SPEED: float = 2.5 ## How fast the lean eases back upright over flat air; vert air keeps the wall's lean.
const MIN_AIR_TIME: float = 0.1 ## Shorter hops are contact flicker on a steep transition, not a landing to turn for.
const DISPLAY_NORMAL_SPEED: float = 14.0 ## Per-second rate the display normal drifts to the floor normal, smoothing a ramp's facets (THUG's adjust_normal).

var player: Player ## The rider, or the Player looking at the board.
var blocks_hands: bool = false ## Riding a board leaves the hands free (rideable contract).
var input_type: int = Controls.InputType.KEYBOARD_MOUSE ## Kept equal to the Player's input device by the Riding state.
var vert_out: Vector3 = Vector3.ZERO ## Horizontal direction over the deck of the wall the skater launched from; ZERO on flat air.
var vert_normal: Vector3 = Vector3.ZERO ## Horizontal normal of that wall, into the pipe; the skater is held in its vertical plane through vert air.
var display_normal: Vector3 = Vector3.UP ## The floor normal smoothed over time, for the lean and the camera, so facet edges do not step them.
var last_floor_normal: Vector3 = Vector3.UP
var _vert_point: Vector3 = Vector3.ZERO
var _was_on_floor: bool = false
var _air_time: float = 0.0
var _ollie_grace: float = 0.0
var _saved_floor_max_angle: float = 0.0
var _saved_floor_snap_length: float = 0.0
var _saved_floor_stop_on_slope: bool = true
var _saved_floor_block_on_wall: bool = true
var _saved_floor_constant_speed: bool = true
var _saved_pivot_height: float = 0.0
var _home_parent: Node
var _sfx_was_on_floor: bool = false
var _sfx_was_jumping: bool = false
var _sfx_was_falling: bool = false

@onready var camera: SkateboardCamera = $SkateboardCamera ## The view while ridden (rideable contract).
@onready var action_prompt: ActionPrompt = $ActionPrompt
@onready var ground_ray: RayCast3D = $GroundRay ## What the board rolls on, for the roll sounds.
@onready var area: Area3D = $Area3D
@onready var sfx_roll_on_cobblestone: AudioStreamPlayer3D = $SFX_Roll_on_Cobblestone
@onready var sfx_roll_on_concrete: AudioStreamPlayer3D = $SFX_Roll_on_Concrete
@onready var sfx_roll_on_wood: AudioStreamPlayer3D = $SFX_Roll_on_Wood
@onready var sfx_ollie: AudioStreamPlayer3D = $SFX_Ollie
@onready var sfx_land: AudioStreamPlayer3D = $SFX_Land
@onready var _area_layer: int = area.collision_layer


## Called by [Camera] while the player looks at the skateboard.
func display_menu(_player: Player) -> void:
	if _player.is_riding:
		return
	player = _player
	action_prompt.show_for(player)


## Called by [Camera] when the player looks away from the skateboard.
func hide_menu() -> void:
	action_prompt.hide()
	if player and not player.is_riding:
		player = null


## Called by [Camera] when the player looks at the skateboard and presses "action".
func equip(_player: Player) -> void:
	_player.mount(self)


## Rideable contract: the Riding state hands the Player over. The board goes under the Player's feet and its
## camera takes the view.
func mount(_player: Player) -> void:
	player = _player
	action_prompt.hide()
	_home_parent = get_parent()
	reparent(player.player_model, false)
	transform = Transform3D.IDENTITY
	area.collision_layer = 0
	_saved_floor_max_angle = player.floor_max_angle
	_saved_floor_snap_length = player.floor_snap_length
	_saved_floor_stop_on_slope = player.floor_stop_on_slope
	_saved_floor_block_on_wall = player.floor_block_on_wall
	_saved_floor_constant_speed = player.floor_constant_speed
	_saved_pivot_height = player.model_pitch_pivot_height
	player.floor_max_angle = RAMP_FLOOR_MAX_ANGLE
	player.floor_snap_length = RAMP_FLOOR_SNAP_LENGTH
	player.floor_stop_on_slope = false # a board at rest on a transition rolls back down instead of sticking to it
	player.floor_block_on_wall = false # brushing the vert above the arc must not zero the speed the way a wall does on foot
	player.floor_constant_speed = false # speed is along the surface already; no slope compensation on top
	player.model_pitch_pivot_height = 0.0 # lean from the feet, not the hips
	var vertical_speed: float = minf(player.velocity.dot(player.up_direction), 0.0)
	player.velocity = player.velocity.slide(player.up_direction) + (player.up_direction * vertical_speed)
	_was_on_floor = player.is_on_floor()
	_sfx_was_on_floor = _was_on_floor
	last_floor_normal = player.up_direction
	display_normal = player.get_floor_normal() if player.is_on_floor() else player.up_direction
	vert_out = Vector3.ZERO
	vert_normal = Vector3.ZERO
	_ollie_grace = 0.0
	locomotion_requested.emit(LOCOMOTION, false)
	camera.begin(player, self)


## Rideable contract: the Player gets off. The board is left where they stand and the view returns to them.
func dismount(_player: Player) -> void:
	stop_all_roll_sounds()
	camera.end()
	player.floor_max_angle = _saved_floor_max_angle
	player.floor_snap_length = _saved_floor_snap_length
	player.floor_stop_on_slope = _saved_floor_stop_on_slope
	player.floor_block_on_wall = _saved_floor_block_on_wall
	player.floor_constant_speed = _saved_floor_constant_speed
	player.model_pitch_pivot_height = _saved_pivot_height
	player.model_pitch = 0.0
	var drop: Transform3D = Transform3D(Basis(player.up_direction, player.orientation.basis.get_euler().y), player.global_position)
	if is_instance_valid(_home_parent):
		reparent(_home_parent, false)
	global_transform = drop
	area.collision_layer = _area_layer
	vert_out = Vector3.ZERO
	vert_normal = Vector3.ZERO
	player = null


## Rideable contract: input events while ridden.
func ride_input(_player: Player, event: InputEvent) -> void:
	# Dismount
	if event.is_action_pressed(_action(keyboard_dismount_action, pad_dismount_action)) and not event.is_echo():
		player.dismount()
		return

	var is_kick_pushing: bool = player.current_locomotion_node == KICK_PUSH

	# Jump
	if event.is_action_pressed(_action(keyboard_jump_action, pad_jump_action)) \
	and not player.is_jumping \
	and not player.is_jump_queued \
	and not is_kick_pushing:
		jump_requested.emit()
		_ollie()

	# Kick push from (near) standstill
	if event.is_action_pressed(_action(keyboard_kick_push_action, pad_kick_push_action)) \
	and not is_kick_pushing \
	and player.velocity.slide(player.up_direction).length() <= SKATEBOARD_KICK_PUSH_SPEED_THRESHOLD:
		locomotion_requested.emit(KICK_PUSH, false)


## Rideable contract: moves the rider this physics frame, then the sounds and the camera.
func ride(_player: Player, delta: float) -> void:
	var up: Vector3 = player.up_direction
	var gravity: Vector3 = player.get_gravity()
	_ollie_grace = maxf(_ollie_grace - delta, 0.0)
	var on_floor: bool = player.is_on_floor() and _ollie_grace <= 0.0
	var normal: Vector3 = player.get_floor_normal() if on_floor else up
	if on_floor:
		if not _was_on_floor:
			_land(normal)
		last_floor_normal = normal
		_air_time = 0.0
	else:
		if _was_on_floor:
			_launch(up)
		_air_time += delta
	_was_on_floor = on_floor
	var blended_normal: Vector3 = display_normal.lerp(normal, clampf(DISPLAY_NORMAL_SPEED * delta, 0.0, 1.0))
	display_normal = blended_normal.normalized() if blended_normal.length_squared() > 0.0001 else normal

	var target_motion: Vector2 = player.player_input.motion
	if Input.is_action_pressed(_action(keyboard_sprint_action, pad_sprint_action)) and not player.is_exhausted and target_motion.y > 0.0:
		target_motion.y = 1.1

	if on_floor:
		_roll(target_motion, normal, gravity, delta)
	else:
		_fly(target_motion, up, gravity, delta)

	locomotion_blend_requested.emit(LOCOMOTION_BLEND_PATH, target_motion.y)
	var lean_up: Vector3 = surface_up()
	_tilt_model(lean_up, MODEL_TILT_SPEED if lean_up != up or on_floor else AIR_TILT_SPEED, delta)
	var intended: Vector3 = player.velocity
	player.update_movement_and_rotation(delta)
	if player.is_on_floor():
		# move_and_slide strips the vertical part of a grounded velocity, which would bleed off a descent down a
		# transition frame by frame; keep the intended speed along the surface (and any ollie push off it)
		var floor_normal: Vector3 = player.get_floor_normal()
		var kept: Vector3 = intended.slide(floor_normal) + floor_normal * maxf(intended.dot(floor_normal), 0.0)
		if player.is_on_wall():
			kept = kept.slide(player.get_wall_normal())
		player.velocity = kept
	_update_sounds()
	camera.follow(delta)


## Steers, pushes and brakes along the surface under the board.
func _roll(target_motion: Vector2, normal: Vector3, gravity: Vector3, delta: float) -> void:
	var lift: float = maxf(player.velocity.dot(normal), 0.0) # an ollie's push off the surface, kept so the board leaves it
	var velocity: Vector3 = player.velocity.slide(normal)
	var speed_ratio: float = clampf(velocity.length() / SKATEBOARD_MAX_SPEED, 0.0, 1.0)
	var turn_speed_factor: float = 1.0 - ((1.0 - SKATEBOARD_HIGH_SPEED_TURN_FACTOR) * speed_ratio)
	var turn_amount: float = - target_motion.x * SKATEBOARD_TURN_SPEED * turn_speed_factor * delta

	# The heading along the surface: the yaw on flat ground, the velocity itself on a steep wall, where a yaw squashed
	# onto the wall would turn a small steer into a swing to sideways
	var steep_moving: bool = normal.dot(player.up_direction) < 0.7 and velocity.length() > 1.0
	var forward_dir: Vector3 = velocity if steep_moving else player.orientation.basis.z.slide(normal)
	var has_forward_dir: bool = forward_dir.length_squared() > 0.001
	if has_forward_dir:
		forward_dir = forward_dir.normalized()
		if steep_moving:
			if not is_zero_approx(turn_amount):
				# Steer about the surface normal, as THUG does (RotateYLocal on the skater's ground matrix)
				forward_dir = forward_dir.rotated(normal, turn_amount)
			var heading: Vector3 = forward_dir.slide(player.up_direction)
			if heading.length_squared() > 0.0001:
				player.turn_model_toward_direction(heading, delta) # eased: the heading of a near-vertical velocity is noisy
		elif not is_zero_approx(turn_amount):
			player.orientation.basis = Basis(player.up_direction, turn_amount) * player.orientation.basis
			forward_dir = player.orientation.basis.z.slide(normal).normalized()
		var side_dir: Vector3 = player.orientation.basis.x.slide(normal)
		if side_dir.length_squared() > 0.001:
			side_dir = side_dir.normalized()
			var forward_velocity: Vector3 = forward_dir * velocity.dot(forward_dir)
			var side_velocity: Vector3 = side_dir * velocity.dot(side_dir)
			velocity = forward_velocity + (side_velocity * SKATEBOARD_SIDE_VELOCITY_FACTOR)
	elif not is_zero_approx(turn_amount):
		player.orientation.basis = Basis(player.up_direction, turn_amount) * player.orientation.basis

	var is_kick_pushing: bool = player.current_locomotion_node == KICK_PUSH
	# Braking (held analog input) cancels the kick push
	if target_motion.y < 0.0 and is_kick_pushing:
		locomotion_requested.emit(LOCOMOTION, true)
		is_kick_pushing = false

	var target_velocity: Vector3 = forward_dir * SKATEBOARD_MAX_SPEED
	if is_kick_pushing and has_forward_dir:
		velocity = velocity.move_toward(target_velocity, SKATEBOARD_KICK_PUSH_ACCELERATION * delta)
	elif target_motion.y > 0.0 and has_forward_dir:
		velocity = velocity.move_toward(target_velocity, SKATEBOARD_ACCELERATION * delta)
	elif target_motion.y < 0.0:
		velocity = velocity.move_toward(Vector3.ZERO, SKATEBOARD_BRAKE * delta)
	else:
		velocity = velocity.move_toward(Vector3.ZERO, SKATEBOARD_FRICTION * delta)

	# Gravity along the surface slows a climb and rolls the board back down; the rest presses it onto the ramp
	player.velocity = velocity + normal * lift + gravity * GROUND_GRAVITY_SCALE * delta


## Pops the board straight up. At the lip that adds to the climb and drops the skater back where they were. A late
## pop while already falling back into the ramp pushes off the wall into the pipe and ends the vert air (THUG do_jump).
func _ollie() -> void:
	var up: Vector3 = player.up_direction
	if vert_normal != Vector3.ZERO and not player.is_on_floor() and player.velocity.dot(up) < 0.0:
		player.velocity += vert_normal * OLLIE_SPEED
		vert_out = Vector3.ZERO
		vert_normal = Vector3.ZERO
		return
	var from_vert: bool = player.is_on_floor() and vert_launch_direction(player.get_floor_normal(), up) != Vector3.ZERO
	var pop: float = VERT_OLLIE_SPEED if from_vert else OLLIE_SPEED
	player.velocity += up * (pop - minf(player.velocity.dot(up), 0.0))
	if player.is_on_floor() and _ollie_grace <= 0.0:
		# Off the ground right now: decide vert from the surface under the board, and keep the wall from catching the pop
		_ollie_grace = OLLIE_GRACE
		_was_on_floor = false
		_launch(up)


## Airborne: left/right spin the skater, gravity does the rest. In vert air the skater is held in the wall's
## vertical plane (THUG tracking), so nothing carries them out over the pipe or the deck.
func _fly(target_motion: Vector2, up: Vector3, gravity: Vector3, delta: float) -> void:
	if not is_zero_approx(target_motion.x):
		player.orientation.basis = Basis(up, - target_motion.x * AIR_SPIN_SPEED * delta) * player.orientation.basis
	if vert_normal != Vector3.ZERO and not _wall_still_behind():
		vert_out = Vector3.ZERO # off the end of the wall: THUG drops tracking and the skater recovers as regular air
		vert_normal = Vector3.ZERO
	if vert_normal != Vector3.ZERO:
		var drift: float = (player.global_position - _vert_point).dot(vert_normal)
		if not is_zero_approx(drift):
			player.global_position -= vert_normal * drift
		player.velocity = player.velocity.slide(vert_normal) + gravity * VERT_GRAVITY_SCALE * delta
	else:
		player.velocity += gravity * AIR_GRAVITY_SCALE * delta


## Whether the wall the skater launched from is still behind them at the launch height (THUG's tracking feeler).
func _wall_still_behind() -> bool:
	var from: Vector3 = Vector3(player.global_position.x, _vert_point.y, player.global_position.z) + vert_normal * 0.5
	var to: Vector3 = from - vert_normal * VERT_TRACK_REACH
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, player.collision_mask, [player.get_rid()])
	return not player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Leaving the floor. Off a vert wall the velocity is rotated into the wall's vertical plane with its speed kept and
## the plane is remembered for tracking. Holding forward at the lip breaks vert instead: a share of the speed goes
## over the deck and it is regular air.
func _launch(up: Vector3) -> void:
	if vert_normal != Vector3.ZERO:
		return # a brush against the wall mid vert air, not a new launch
	var out: Vector3 = vert_launch_direction(last_floor_normal, up)
	vert_out = Vector3.ZERO
	vert_normal = Vector3.ZERO
	if out == Vector3.ZERO:
		return
	if player.player_input.motion.y > 0.5:
		var speed: float = player.velocity.length()
		player.velocity += out * speed * BREAK_VERT_SPEED_SCALE
		player.velocity -= up * player.velocity.dot(up) * (1.0 - BREAK_VERT_UP_SCALE)
		return
	vert_out = out
	vert_normal = -out
	_vert_point = player.global_position
	player.velocity = vert_launch_velocity(player.velocity, vert_normal)


## Touching down: face the way the board is rolling, whatever the spin left the skater at (THUG flips a skater
## rolling backwards on touchdown, lean intact).
func _land(normal: Vector3) -> void:
	if _air_time < MIN_AIR_TIME:
		return # contact flicker on a steep transition; the vert air, if any, carries on
	vert_out = Vector3.ZERO
	vert_normal = Vector3.ZERO
	var rolling: Vector3 = player.velocity.slide(normal)
	if rolling.length() > 1.0:
		var reversed: bool = player.orientation.basis.z.slide(player.up_direction).dot(rolling.slide(player.up_direction)) < 0.0
		player.rotate_model_to_direction(rolling)
		if reversed:
			player.model_pitch = -player.model_pitch


## The up the skater is leaning to and the camera hangs off: the smoothed floor normal on the ground and through
## contact flicker on a steep transition, the wall's normal through vert air, world up in regular air.
func surface_up() -> Vector3:
	if player == null:
		return Vector3.UP
	if player.is_on_floor() and _ollie_grace <= 0.0 or _air_time < MIN_AIR_TIME and vert_normal == Vector3.ZERO and not _was_on_floor:
		return display_normal
	if vert_normal != Vector3.ZERO:
		return last_floor_normal if _air_time < MIN_AIR_TIME else vert_normal
	return player.up_direction


## Leans the model (pivoting at the feet) so its up matches [param surface_up], at [param speed] per second.
func _tilt_model(surface_up_: Vector3, speed: float, delta: float) -> void:
	var local_up: Vector3 = player.orientation.basis.inverse() * surface_up_
	var target_pitch: float = atan2(local_up.z, local_up.y)
	player.model_pitch = lerp_angle(player.model_pitch, target_pitch, clampf(speed * delta, 0.0, 1.0))


## Horizontal direction over the deck of a wall steep enough to be vert (away from the face the skater rode up),
## or ZERO when leaving flatter ground.
static func vert_launch_direction(floor_normal: Vector3, up: Vector3) -> Vector3:
	var into_pipe: Vector3 = floor_normal.slide(up)
	if floor_normal.angle_to(up) < VERT_ANGLE or into_pipe.length_squared() < 0.0001:
		return Vector3.ZERO
	return -into_pipe.normalized()


## The launch velocity rotated into the wall's vertical plane (normal [param wall_normal]) with its speed kept,
## as THUG's RotateToPlane does: speed that was heading over the deck becomes climb.
static func vert_launch_velocity(velocity: Vector3, wall_normal: Vector3) -> Vector3:
	var in_plane: Vector3 = velocity.slide(wall_normal)
	if in_plane.length_squared() < 0.000001:
		return velocity
	return in_plane.normalized() * velocity.length()


## Rideable contract: label names on the Player's controls to their text while skating.
func get_contextual_controls(input_type_: int) -> Dictionary:
	return {
		"left_joystick": "Steer / Spin",
		"right_joystick": "Camera",
		"joypad_button_3": "Ollie",
		"joypad_button_1": "Fast Push",
		"key_k" if input_type_ == Controls.InputType.KEYBOARD_MOUSE else "joypad_button_12": "Dismount",
	}


## The action for the rider's current input device.
func _action(keyboard_action: StringName, pad_action: StringName) -> StringName:
	if input_type == Controls.InputType.KEYBOARD_MOUSE:
		return keyboard_action
	return pad_action


## Roll, ollie and landing sounds for the surface under the board.
func _update_sounds() -> void:
	var is_on_floor: bool = player.is_on_floor()
	var is_jumping: bool = player.is_jumping
	var is_falling: bool = player.is_falling
	var target_roll_sfx: AudioStreamPlayer3D = _get_target_roll_sfx()
	if is_jumping and not _sfx_was_jumping:
		stop_all_roll_sounds()
		if target_roll_sfx and not sfx_ollie.playing:
			sfx_ollie.play()
	if is_on_floor and (not _sfx_was_on_floor or _sfx_was_jumping or _sfx_was_falling):
		if target_roll_sfx and not sfx_land.playing:
			sfx_land.play()
	var h_speed: float = player.velocity.slide(player.up_direction).length()
	if is_on_floor and h_speed > 0.1:
		_play_roll_sfx(target_roll_sfx)
	else:
		stop_all_roll_sounds()
	_sfx_was_on_floor = is_on_floor
	_sfx_was_jumping = is_jumping
	_sfx_was_falling = is_falling


func _get_target_roll_sfx() -> AudioStreamPlayer3D:
	if ground_ray.is_colliding():
		var collider: Node3D = ground_ray.get_collider() as Node3D
		if collider:
			if collider.is_in_group("WOOD"):
				return sfx_roll_on_wood
			elif collider.is_in_group("STONE") or collider.is_in_group("COBBLESTONE"):
				return sfx_roll_on_cobblestone
			elif collider.is_in_group("CONCRETE"):
				return sfx_roll_on_concrete
	return null


func _play_roll_sfx(target_sfx: AudioStreamPlayer3D) -> void:
	# Don't play roll sound while Ollie or Land SFX is actively playing
	if not target_sfx or sfx_ollie.playing or sfx_land.playing:
		stop_all_roll_sounds()
		return
	if target_sfx.playing:
		return
	stop_all_roll_sounds()
	target_sfx.play()


func stop_all_roll_sounds() -> void:
	sfx_roll_on_cobblestone.stop()
	sfx_roll_on_concrete.stop()
	sfx_roll_on_wood.stop()
