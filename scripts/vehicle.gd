class_name Vehicle
extends VehicleBody3D
## Godot Tim's Automobile: a vehicle the Player gets into with "action" and drives through the Player's
## [Riding] state. Drivetrain, transmission, damage (flip, burn, explode when the scene gives it fire and explosion
## nodes), engine SFX, first-person look, the GTA chase camera and the speedometer are all the vehicle's own; the
## Player lends its body and its input, and the [Riding] state plays the enter and exit clips named below, hands the
## view to [member camera] and turns the Player's collision off for the seat.

signal locomotion_requested(state_path: String, immediate: bool) ## Asks the rider to play an animation node.

@export_category("Driving Controls")
@export_group("Keyboard/Mouse Actions")
@export var keyboard_accelerate_action: StringName = &"jump"
@export var keyboard_brake_action: StringName = &"sprint"
@export var keyboard_handbrake_action: StringName = &"throw"
@export var keyboard_exit_action: StringName = &"action"
@export_group("Controller/Touch Actions")
@export var pad_accelerate_action: StringName = &"shoot"
@export var pad_brake_action: StringName = &"focus"
@export var pad_handbrake_action: StringName = &"throw"
@export var pad_exit_action: StringName = &"jump"
@export_group("")

const BAIL_OUT_SPEED: float = 2.0 ## Above this speed exiting skips the door animation.

const MAX_LOOK_YAW: float = 1.0472 # 60 degrees in radians
const MAX_LOOK_PITCH: float = 1.0472 # 60 degrees in radians
const FLIPPED_DOT_THRESHOLD: float = 0.5 # dot product <= 0.5 means tilted >= 60 degrees
const FLIPPED_VELOCITY_THRESHOLD: float = 2.0 # max linear/angular velocity to be considered settled
const DOOR_OPEN_TIME: float = 1.1333 # seconds into the "Entering Car" animation when the door opens
const DOOR_CLOSE_TIME: float = 3.7333 # seconds into the "Entering Car" animation when the door closes
const GEAR_SPEEDS: Array[float] = [7.0, 13.0, 20.0, 30.0, 45.0] # top speed (m/s) of each forward gear; drag caps the last one
const GEAR_TORQUE_MULTS: Array[float] = [1.2, 1.0, 0.85, 0.7, 0.55] # engine force multiplier per forward gear
const BURNED_MATERIAL: StandardMaterial3D = preload("res://addons/gta/materials/burned.tres")

@export var max_acceleration_force: float = 7000.0 ## Total drive force at the wheels in first gear, split across the driven wheels once.
@export var max_brake_force: float = 140.0 ## Per-wheel brake; about one g, so stops take real distance like GTA's fBrakeForce.
@export var max_reverse_force: float = -3000.0
@export var explosion_impulse_force: float = 6750.0
@export var min_brake_sound_velocity: float = 6.0 ## Minimum speed required to trigger brake screech sound
@export var brake_velocity_threshold: float = 14.0 ## Velocity threshold to switch between sfx_break_short and sfx_break_long
@export var wheels: Array[VehicleWheel3D]

@export_group("GTA Handling & Transmission")
@export var drive_bias_front: float = 0.5 ## AWD torque distribution (0.5 = 50% front / 50% rear)
@export var brake_bias_front: float = 0.65 ## Brake bias (65% front, 35% rear)
@export var handbrake_traction_loss: float = 0.7 ## Rear wheel friction while the handbrake locks them: the GTA rear slide.
@export var traction_curve_lateral: float = 14.0 ## Axle slip angle (degrees) where grip starts falling; gone to the minimum a further 14 degrees on.
@export var traction_curve_min: float = 0.85 ## Grip left once an axle slides, as a fraction of its wheels' friction (GTA fTractionCurveMin/Max).
@export var low_speed_traction_loss: float = 0.85 ## Driven-wheel friction under full throttle below 6 m/s in first: launch wheelspin.
@export var drag_coeff: float = 2.0 ## Air drag in N per (m/s)^2; the top speed is where it meets the drive force.
@export var downforce_coeff: float = 1.0 ## Downforce multiplier, capped at 2000 N.
@export var anti_roll_force: float = 9000.0 ## Anti-roll bar: N per metre of compression difference across an axle.
@export var max_steering_angle: float = 35.0 ## Lock at rest (GTA fSteeringLock); it shrinks to 30% by 40 m/s.
@export var steer_time: float = 0.25 ## Seconds for the stick to reach full lock (input smoothing).
@export var steering_speed: float = 6.0 ## Radians per second the wheels turn toward the smoothed target.
@export var counter_steer_gain: float = 0.6 ## Fraction of the slip angle steered back into a slide (GTA V steer assist).

@export var current_driver_peer_id: int = 1

var current_gear: int = 1
var current_rpm: float = 0.0 # 0.0 = idle, 1.0 = redline
var has_exploded: bool = false
var initial_spawn_transform: Transform3D
var is_on_fire: bool = false:
	set(value):
		if is_on_fire == value:
			return
		is_on_fire = value
		if is_node_ready():
			_update_fire_state()
var is_flipped: bool = false
var is_engine_started: bool = false
var is_driving_this_car: bool = false ## True from the first drive input until the driver gets out.
var look_angles: Vector2 = Vector2.ZERO
var menu_displayed: bool = false ## The prompt is up for [member player], who is inside PlayerDetection.
var player: Player ## The driver, or the Player standing by the car.
var blocks_hands: bool = true ## Weapons and items stay holstered at the wheel (rideable contract).
var disables_collision: bool = true ## The Player sits inside the body, so their collision is off while ridden (rideable contract).
var mount_animation: String = "EnteringCar" ## The Player's get-in clip; the Riding state plays it before the drive starts (rideable contract).
var dismount_animation: String = "ExitingCar" ## The get-out clip at rest; a bail out at speed skips it (rideable contract).
var input_type: int = Controls.InputType.KEYBOARD_MOUSE ## Kept equal to the Player's input device by the Riding state.
var _accelerate: bool = false
var _brake: bool = false
var _handbrake: bool = false
var _steer: float = 0.0
var _steer_input: float = 0.0 ## The smoothed stick.
var _revved_current_accel: bool = false

@onready var action_prompt: Node3D = $ActionPrompt
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var fire: Node3D = get_node_or_null("Fire_05") ## Optional: a scene that adds fire and explosion nodes gets the damage effects.
@onready var fire_sfx: AudioStreamPlayer3D = get_node_or_null("Fire_05/FireSFX")
@onready var explosion: Node3D = get_node_or_null("VFXGroundExplosion_01")
@onready var explosion_sfx: AudioStreamPlayer3D = get_node_or_null("VFXGroundExplosion_01/ExplosionSFX")
@onready var driver_seat: Node3D = $DriverSeat
@onready var enter_car: Node3D = $EnterCar
@onready var chase_camera: VehicleCamera = $VehicleCamera
@onready var camera: Camera3D = chase_camera.camera ## The view while ridden (rideable contract); first person swaps in its own.
@onready var driving_ui: CanvasLayer = $DrivingUI
@onready var first_person_camera: Camera3D = $FirstPersonCamera
@onready var initial_camera_quat: Quaternion = first_person_camera.quaternion
@onready var engine_sfx: Node3D = $EngineSFX ## Container of every looping/rev engine player.
@onready var sfx_car_start: AudioStreamPlayer3D = $SFXCarStart
@onready var sfx_engine_rev: AudioStreamPlayer3D = $EngineSFX/SFXEngineRev
@onready var sfx_engine_slow_down_inside: AudioStreamPlayer3D = $EngineSFX/SFXEngineSlowDownInside
@onready var sfx_engine_slow_down_outside: AudioStreamPlayer3D = $EngineSFX/SFXEngineSlowDownOutside
@onready var sfx_engine_speed_up_inside: AudioStreamPlayer3D = $EngineSFX/SFXEngineSpeedUpInside
@onready var sfx_engine_speed_up_outside: AudioStreamPlayer3D = $EngineSFX/SFXEngineSpeedUpOutside
@onready var sfx_engine_running_inside: AudioStreamPlayer3D = $EngineSFX/SFXEngineRunningInside
@onready var sfx_engine_running_outside: AudioStreamPlayer3D = $EngineSFX/SFXEngineRunningOutside
@onready var sfx_break_short: AudioStreamPlayer3D = $SFXBreakShort
@onready var sfx_break_long: AudioStreamPlayer3D = $SFXBreakLong
@onready var vehicle_synchronizer: MultiplayerSynchronizer = $VehicleSynchronizer
@onready var flipped_timer: Timer = $FlippedTimer ## Runs while flipped and settled; timeout ignites the car.
@onready var fire_timer: Timer = $FireTimer ## Runs while burning; timeout explodes the car.
@onready var screech_timer: Timer = $ScreechTimer ## Minimum gap between brake screech retriggers.
@onready var look_return_timer: Timer = $LookReturnTimer ## Delay before first-person look recenters.
@onready var clutch_timer: Timer = $ClutchTimer ## Brief RPM dip after a gear shift.
@onready var reverse_hold_timer: Timer = $ReverseHoldTimer ## Holds the car still before reverse engages.
@onready var forward_hold_timer: Timer = $ForwardHoldTimer ## Holds the car still before forward engages from reverse.


func _ready() -> void:
	add_to_group("vehicles")
	initial_spawn_transform = global_transform
	set_sfx_volume(PlayerSettingsResource.load_or_create().sfx_volume)
	if is_on_fire:
		_update_fire_state()
	for sfx: Node in engine_sfx.get_children():
		if sfx != sfx_engine_rev and sfx.stream is AudioStreamOggVorbis:
			(sfx.stream as AudioStreamOggVorbis).loop = true


## Sets the current driver and updates multiplayer authority; null when the driver gets out.
func set_driver(driver: Player) -> void:
	if driver:
		player = driver
		current_driver_peer_id = driver.get_multiplayer_authority()
		set_multiplayer_authority(current_driver_peer_id)
		_play_door_sequence()
		return
	if player and first_person_camera.current:
		_show_chase_camera()
	is_driving_this_car = false
	current_driver_peer_id = 1
	set_multiplayer_authority(1)
	player = null


## Called by the Player's Driving state every physics frame while seated.
func set_drive_input(accelerate: bool, brake_pressed: bool, handbrake: bool, steer: float) -> void:
	freeze = false
	if not is_driving_this_car and not is_engine_started:
		sfx_car_start.play()
		is_engine_started = true
	is_driving_this_car = player != null
	_accelerate = accelerate
	_brake = brake_pressed
	_handbrake = handbrake
	_steer = steer


## Returns true if any vehicle wheel is currently touching ground.
func is_any_wheel_on_ground() -> bool:
	for wheel: VehicleWheel3D in wheels:
		if wheel.is_in_contact():
			return true
	return false


## Update volume on all vehicle SFX AudioStreamPlayer3D nodes.
func set_sfx_volume(value: float) -> void:
	var db: float = linear_to_db(value / 100.0) if value > 0.0 else -80.0
	for child: Node in find_children("*", "AudioStreamPlayer3D", true, false):
		(child as AudioStreamPlayer3D).volume_db = db


func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or player == null:
		return

	if event.is_action_pressed("action") and menu_displayed and not player.is_riding and not is_on_fire and not has_exploded:
		player.mount(self)
		return

	if is_driving_this_car and first_person_camera.current and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var player_cam: Camera = player.camera as Camera
		var motion: InputEventMouseMotion = event
		look_angles.x = clampf(look_angles.x - deg_to_rad(motion.relative.x * player_cam.mouse_sensitivity), -MAX_LOOK_YAW, MAX_LOOK_YAW)
		look_angles.y = clampf(look_angles.y - deg_to_rad(motion.relative.y * player_cam.mouse_sensitivity), -MAX_LOOK_PITCH, MAX_LOOK_PITCH)
		look_return_timer.start()


func _process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if is_driving_this_car:
		var player_cam: Camera = player.camera as Camera
		if player_cam.perspective == Camera.Perspective.FIRST_PERSON:
			if not first_person_camera.current:
				first_person_camera.current = true
				look_angles = Vector2.ZERO
				first_person_camera.quaternion = initial_camera_quat
		elif first_person_camera.current:
			_show_chase_camera()

		if first_person_camera.current:
			var joypad_look: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down")
			if joypad_look != Vector2.ZERO:
				look_angles.x = clampf(look_angles.x - deg_to_rad(joypad_look.x * player_cam.joypad_sensitivity * delta), -MAX_LOOK_YAW, MAX_LOOK_YAW)
				look_angles.y = clampf(look_angles.y - deg_to_rad(joypad_look.y * player_cam.joypad_sensitivity * delta), -MAX_LOOK_PITCH, MAX_LOOK_PITCH)
				look_return_timer.start()
			elif look_return_timer.is_stopped():
				look_angles = look_angles.lerp(Vector2.ZERO, delta * 5.0)
			var target_quat: Quaternion = initial_camera_quat * Quaternion.from_euler(Vector3(look_angles.y, look_angles.x, 0.0))
			first_person_camera.quaternion = first_person_camera.quaternion.slerp(target_quat, delta * 15.0)
	_update_engine_sfx()


## Opens then closes the driver door in sync with the Player's enter/exit animations.
func _play_door_sequence() -> void:
	await get_tree().create_timer(DOOR_OPEN_TIME).timeout
	if not is_instance_valid(animation_player):
		return
	animation_player.play("open")
	await get_tree().create_timer(DOOR_CLOSE_TIME - DOOR_OPEN_TIME).timeout
	if is_instance_valid(animation_player):
		animation_player.play("close")


func _update_fire_state() -> void:
	if fire == null:
		return
	fire.emitting = is_on_fire
	if is_on_fire:
		if not fire_sfx.playing:
			fire_sfx.play()
		if not has_exploded and is_multiplayer_authority():
			fire_timer.start()
		_hide_prompt()
	else:
		fire_sfx.stop()
		fire_timer.stop()


func _on_flipped_timer_timeout() -> void:
	is_on_fire = true


func _on_fire_timer_timeout() -> void:
	has_exploded = true
	if fire:
		fire.emitting = false
		fire_sfx.stop()
	if explosion:
		explosion.play()
		explosion_sfx.play()
	freeze = false
	apply_impulse(-get_gravity().normalized() * explosion_impulse_force)
	_apply_burned_material(self)
	_hide_prompt()


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if is_driving_this_car and not is_on_fire and not has_exploded:
		_apply_drivetrain(delta)
	else:
		steering = 0.0
		engine_force = 0.0
		brake = max_brake_force
		for wheel: VehicleWheel3D in wheels:
			wheel.engine_force = 0.0
			wheel.brake = max_brake_force
		# Godot's wheel brake creeps a standing car in proportion to its force, so a parked car holds still frozen
		if not freeze and linear_velocity.length() < 0.5 and angular_velocity.length() < 0.5 and is_any_wheel_on_ground():
			freeze = true

	var up_dir: Vector3 = -get_gravity().normalized()
	if up_dir == Vector3.ZERO:
		up_dir = Vector3.UP

	if not is_on_fire:
		var is_tilted: bool = global_transform.basis.y.dot(up_dir) <= FLIPPED_DOT_THRESHOLD
		var is_settled: bool = linear_velocity.length() < FLIPPED_VELOCITY_THRESHOLD and angular_velocity.length() < FLIPPED_VELOCITY_THRESHOLD
		is_flipped = is_tilted and is_settled
		if not is_flipped:
			flipped_timer.stop()
		elif flipped_timer.is_stopped():
			flipped_timer.start()
	elif fire:
		var fwd: Vector3 = global_transform.basis.z
		if absf(fwd.dot(up_dir)) > 0.99:
			fwd = global_transform.basis.x
		fire.global_transform.basis = Basis.looking_at(fwd, up_dir)


## Transmission, RPM, wheel forces through a traction curve, smoothed speed-sensitive steering with
## counter-steer assist, air drag, anti-roll bars and downforce from the stored drive inputs.
func _apply_drivetrain(delta: float) -> void:
	brake = 0.0 # the body-wide parking brake set while nobody drives; the wheels' own brakes follow the pedal below
	var speed: float = linear_velocity.length()
	var heading: Vector3 = Vector3(global_transform.basis.z.x, 0.0, global_transform.basis.z.z).normalized()
	var forward_speed: float = heading.dot(linear_velocity) if heading != Vector3.ZERO else global_transform.basis.z.dot(linear_velocity)
	var ground_speed: float = Vector2(linear_velocity.x, linear_velocity.z).length()
	var is_grounded: bool = is_any_wheel_on_ground()

	# --- Transmission & Gear State Machine ---
	var target_gear: int = -1
	if forward_speed >= -0.3:
		target_gear = GEAR_SPEEDS.size()
		for g_idx: int in GEAR_SPEEDS.size():
			if speed <= GEAR_SPEEDS[g_idx]:
				target_gear = g_idx + 1
				break
		# Aggressive handbrake downshift: reset gear when handbraking slows the vehicle
		if _handbrake:
			if speed < 10.0:
				target_gear = 1
			elif speed < 18.0:
				target_gear = mini(target_gear, 2)
			elif speed < 28.0:
				target_gear = mini(target_gear, 3)

	if target_gear != current_gear and target_gear > 0 and current_gear > 0:
		if _handbrake:
			clutch_timer.stop() # Instant downshift on handbrake without shift lag
		else:
			clutch_timer.start() # Brief clutch disengagement for shift sound drop
		current_gear = target_gear
	elif target_gear < 0 or current_gear < 0:
		current_gear = target_gear

	# --- Target RPM Calculation ---
	var target_rpm: float = 0.0
	if not is_grounded and not _accelerate:
		target_rpm = 0.1 # Gentle idle hum in mid-air
	elif current_gear > 0:
		var g_idx: int = current_gear - 1
		var min_g_spd: float = 0.0 if g_idx == 0 else GEAR_SPEEDS[g_idx - 1]
		var progress: float = clampf((ground_speed - min_g_spd) / maxf(GEAR_SPEEDS[g_idx] - min_g_spd, 1.0), 0.0, 1.0)
		target_rpm = lerpf(0.35, 1.0, progress) if _accelerate else lerpf(0.1, 0.5, progress)
	elif current_gear == -1: # Reverse
		target_rpm = lerpf(0.3, 0.9, clampf(ground_speed / 12.0, 0.0, 1.0)) if _brake else 0.1

	if (_brake or _handbrake) and _accelerate and speed < 2.5:
		target_rpm = 0.95 # Burnout redline
	if not clutch_timer.is_stopped():
		target_rpm = 0.25 # Clutch dip on gear shift
	current_rpm = lerpf(current_rpm, target_rpm, delta * 12.0)

	# --- Force Calculation (engine force is the total at the wheels) ---
	var target_engine_force: float = 0.0
	var target_brake_front: float = 0.0
	var target_brake_rear: float = 0.0
	var rear_slip_multiplier: float = 1.0
	var current_gear_mult: float = GEAR_TORQUE_MULTS[clampi(current_gear - 1, 0, GEAR_TORQUE_MULTS.size() - 1)] if current_gear > 0 else 1.0

	# 1. Acceleration Forward / Braking when in Reverse
	if _accelerate:
		if forward_speed < -0.4:
			# Moving backward in reverse: pressing accelerate smoothly brakes to a stop
			forward_hold_timer.start()
			target_brake_front = max_brake_force * brake_bias_front
			target_brake_rear = max_brake_force * (1.0 - brake_bias_front)
		elif absf(forward_speed) <= 0.4 and not forward_hold_timer.is_stopped() and not _brake:
			# Hold standstill when stopped from reverse
			target_brake_front = max_brake_force
			target_brake_rear = max_brake_force
		else:
			target_engine_force = max_acceleration_force * current_gear_mult
	else:
		forward_hold_timer.stop()

	# 2. Regular Braking Forward / Reversing
	if _brake:
		if forward_speed > 0.4:
			# Moving forward: smoothly brake to a stop and hold before reversing
			reverse_hold_timer.start()
			target_brake_front = max_brake_force * brake_bias_front
			target_brake_rear = max_brake_force * (1.0 - brake_bias_front)
			if not _handbrake and not _accelerate:
				target_engine_force = 0.0
		elif forward_speed < -0.4:
			# Already moving backward: continue reverse unless accelerating
			if _accelerate:
				target_brake_front = max_brake_force
				target_brake_rear = max_brake_force
				target_engine_force = 0.0
			else:
				target_engine_force = max_reverse_force
				target_brake_front = 0.0
				target_brake_rear = 0.0
		elif _accelerate or not reverse_hold_timer.is_stopped():
			# Standstill: rev in place / hold still before reverse engages
			target_brake_front = max_brake_force
			target_brake_rear = max_brake_force
			target_engine_force = 0.0
		else:
			target_engine_force = max_reverse_force
			target_brake_front = 0.0
			target_brake_rear = 0.0
	else:
		reverse_hold_timer.stop()

	# 3. Handbrake (locks the rear wheels and cuts their grip, so the rear steps out)
	if _handbrake:
		target_brake_rear = max_brake_force * 1.5
		rear_slip_multiplier = handbrake_traction_loss
		if not _brake and not (_accelerate and forward_speed < -0.4):
			target_brake_front = 0.0
		if _accelerate and forward_speed >= -0.4:
			target_engine_force = max_acceleration_force * current_gear_mult

	# --- Traction curve: an axle sliding past traction_curve_lateral loses grip, like GTA's fTractionCurve ---
	var front_grip: float = _axle_grip(_axle_z(false), steering)
	var rear_grip: float = _axle_grip(_axle_z(true), 0.0) * rear_slip_multiplier
	var launch_loss: float = low_speed_traction_loss if _accelerate and current_gear == 1 and speed < 6.0 and is_grounded else 1.0
	var driven_front: int = 0
	var driven_rear: int = 0
	for wheel: VehicleWheel3D in wheels:
		if wheel.use_as_traction:
			if wheel.position.z < 0.0:
				driven_rear += 1
			else:
				driven_front += 1

	# --- Apply Forces to Wheels ---
	for wheel: VehicleWheel3D in wheels:
		if not wheel.has_meta("default_friction"):
			wheel.set_meta("default_friction", wheel.wheel_friction_slip)
		var is_rear: bool = wheel.position.z < 0.0
		wheel.brake = lerpf(wheel.brake, target_brake_rear if is_rear else target_brake_front, delta * 10.0)

		if wheel.use_as_traction:
			if (_brake and forward_speed > 0.4 and not _accelerate) or (_accelerate and forward_speed < -0.4 and not _brake):
				wheel.engine_force = 0.0
			else:
				# The axle's share of the total, split across that axle's driven wheels
				var axle_share: float = (1.0 - drive_bias_front) / maxi(driven_rear, 1) if is_rear else drive_bias_front / maxi(driven_front, 1)
				wheel.engine_force = lerpf(wheel.engine_force, target_engine_force * axle_share, delta * 12.0)

		var grip: float = rear_grip if is_rear else front_grip
		if wheel.use_as_traction:
			grip *= launch_loss
		var target_slip: float = float(wheel.get_meta("default_friction")) * grip
		wheel.wheel_friction_slip = lerpf(wheel.wheel_friction_slip, target_slip, delta * (12.0 if _handbrake else 25.0))

	# --- Steering: smoothed stick, lock shrinking with speed, counter-steer into a slide (GTA V) ---
	_steer_input = move_toward(_steer_input, _steer, delta / steer_time)
	var lock: float = deg_to_rad(max_steering_angle)
	var target_steering: float = _steer_input * lock * lerpf(1.0, 0.3, clampf(speed / 40.0, 0.0, 1.0))
	if is_grounded and forward_speed > 3.0:
		var travel: Vector3 = Vector3(linear_velocity.x, 0.0, linear_velocity.z).normalized()
		target_steering += clampf(heading.signed_angle_to(travel, Vector3.UP), -0.5, 0.5) * counter_steer_gain
	steering = move_toward(steering, clampf(target_steering, -lock, lock), delta * steering_speed)

	# --- Air drag: what caps the top speed ---
	apply_central_force(-linear_velocity * speed * drag_coeff)

	# --- Anti-roll bars: the more compressed side pushes the body back up, the other side pulls it down ---
	if is_grounded:
		for rear_axle: bool in [false, true]:
			var left: VehicleWheel3D
			var right: VehicleWheel3D
			for wheel: VehicleWheel3D in wheels:
				if (wheel.position.z < 0.0) == rear_axle:
					if wheel.position.x > 0.0:
						left = wheel
					else:
						right = wheel
			if left and right and left.is_in_contact() and right.is_in_contact():
				var bar: float = anti_roll_force * (left.position.y - right.position.y)
				apply_force(global_transform.basis.y * bar, global_transform.basis * left.position)
				apply_force(-global_transform.basis.y * bar, global_transform.basis * right.position)

	# --- Aerodynamic Downforce Stabilization ---
	if is_grounded:
		apply_central_force(-global_transform.basis.y * clampf(ground_speed * ground_speed * downforce_coeff, 0.0, 2000.0))


## Local Z of the front or rear axle, from the wheels.
func _axle_z(rear: bool) -> float:
	for wheel: VehicleWheel3D in wheels:
		if (wheel.position.z < 0.0) == rear:
			return wheel.position.z
	return 0.0


## Grip multiplier for an axle from its slip angle: 1.0 up to [member traction_curve_lateral], then falling to
## [member traction_curve_min] over the same span again. [param wheel_yaw] is the steering angle on that axle.
func _axle_grip(axle_z: float, wheel_yaw: float) -> float:
	var axle_velocity: Vector3 = linear_velocity + angular_velocity.cross(global_transform.basis.z * axle_z)
	axle_velocity.y = 0.0
	if axle_velocity.length() < 2.0:
		return 1.0
	var wheel_direction: Vector3 = global_transform.basis.z.rotated(global_transform.basis.y, wheel_yaw)
	wheel_direction.y = 0.0
	var slip: float = rad_to_deg(wheel_direction.normalized().angle_to(axle_velocity.normalized()))
	if slip > 90.0:
		slip = 180.0 - slip # Rolling backwards
	return lerpf(1.0, traction_curve_min, clampf((slip - traction_curve_lateral) / traction_curve_lateral, 0.0, 1.0))


## Wired to PlayerDetection.body_entered: the Player who walked up gets the prompt and a "Get In" Action label, GTA style.
func _on_player_detection_body_entered(body: Node3D) -> void:
	if body is Player and body.is_multiplayer_authority() and not (body as Player).is_riding:
		_show_prompt(body)


## Wired to PlayerDetection.body_exited: walking away takes the prompt and the label with it.
func _on_player_detection_body_exited(body: Node3D) -> void:
	if body == player and menu_displayed:
		_hide_prompt()


func _show_prompt(_player: Player) -> void:
	if is_on_fire or has_exploded:
		return
	player = _player
	if action_prompt:
		action_prompt.update_text()
		action_prompt.show_for(player, "Get In")
	menu_displayed = true


## Hides the prompt and hands the Action label back to the Player's state; a driver keeps [member player].
func _hide_prompt() -> void:
	menu_displayed = false
	if player == null or player.riding == self:
		if action_prompt:
			action_prompt.hide()
		return
	if action_prompt:
		action_prompt.hide_for(player)
	player = null


## Replaces every body mesh material with the charred material and hides the glass.
func _apply_burned_material(node: Node) -> void:
	# Skip VFX, particles, prompts
	if node == fire or node == explosion or node is GPUParticles3D or node is CPUParticles3D:
		return
	if node.name.begins_with("VFX") or node.name.begins_with("Fire") or node.name.begins_with("Explosion") or node.name == "ActionPrompt":
		return

	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node
		var node_name: String = node.name.to_lower()
		if "glass" in node_name or "window" in node_name:
			mesh_instance.visible = false
		else:
			var surface_count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh else mesh_instance.get_surface_override_material_count()
			for i: int in surface_count:
				mesh_instance.set_surface_override_material(i, BURNED_MATERIAL)

	for child: Node in node.get_children():
		_apply_burned_material(child)


## Plays the engine and brake SFX that match the stored drive inputs and current RPM.
func _update_engine_sfx() -> void:
	if not is_driving_this_car or is_on_fire or has_exploded:
		for sfx: Node in engine_sfx.get_children():
			(sfx as AudioStreamPlayer3D).stop()
		sfx_break_short.stop()
		sfx_break_long.stop()
		_revved_current_accel = false
		screech_timer.stop()
		return

	if not _accelerate:
		_revved_current_accel = false

	# If start SFX is still playing and player isn't providing inputs yet, let start SFX finish
	if sfx_car_start.playing and not (_accelerate or _brake or _handbrake):
		for sfx: Node in engine_sfx.get_children():
			(sfx as AudioStreamPlayer3D).stop()
		return

	var player_cam: Camera = player.camera as Camera
	var is_first_person: bool = (player_cam and player_cam.perspective == Camera.Perspective.FIRST_PERSON) or first_person_camera.current
	var forward_speed: float = global_transform.basis.z.dot(linear_velocity)
	var lateral_speed: float = absf(global_transform.basis.x.dot(linear_velocity))
	var speed: float = linear_velocity.length()

	# 1. Brake screech / skid SFX (only with wheels on the ground and above the speed threshold)
	var is_screeching: bool = is_any_wheel_on_ground() and speed > min_brake_sound_velocity \
			and (_handbrake or lateral_speed > 2.5 \
			or (_brake and not _accelerate and forward_speed > min_brake_sound_velocity) \
			or (_accelerate and not _brake and forward_speed < -min_brake_sound_velocity))
	if is_screeching:
		if not sfx_break_short.playing and not sfx_break_long.playing and screech_timer.is_stopped():
			screech_timer.start()
			if speed > brake_velocity_threshold or lateral_speed > 4.0:
				sfx_break_long.play()
			else:
				sfx_break_short.play()
	else:
		sfx_break_short.stop()
		sfx_break_long.stop()
		screech_timer.stop()

	# 2. Determine target engine SFX
	var target_sfx: AudioStreamPlayer3D
	if (_brake or _handbrake) and _accelerate and speed < 2.5:
		# Rev engine only during a stationary burnout, once per accelerate press
		if not _revved_current_accel:
			_revved_current_accel = true
			target_sfx = sfx_engine_rev
		elif sfx_engine_rev.playing:
			target_sfx = sfx_engine_rev
		else:
			target_sfx = sfx_engine_running_inside if is_first_person else sfx_engine_running_outside
	elif (_accelerate and forward_speed >= -0.4) or (_brake and not _accelerate and forward_speed < -1.5):
		# Accelerating forward, or actively reversing
		target_sfx = sfx_engine_speed_up_inside if is_first_person else sfx_engine_speed_up_outside
	else:
		# Braking / coasting / idle (off-throttle)
		target_sfx = sfx_engine_running_inside if is_first_person else sfx_engine_running_outside

	# 3. RPM-driven pitch modulation
	var base_pitch: float = lerpf(0.85, 1.6, current_rpm)
	if target_sfx == sfx_engine_speed_up_inside or target_sfx == sfx_engine_speed_up_outside:
		target_sfx.pitch_scale = clampf(base_pitch, 0.85, 1.65)
	elif target_sfx == sfx_engine_rev:
		target_sfx.pitch_scale = 1.0
	elif (_brake or _handbrake) and _accelerate:
		target_sfx.pitch_scale = 1.35
	else:
		target_sfx.pitch_scale = clampf(base_pitch, 0.85, 1.5)

	# 4. Play the target SFX and stop every other engine SFX
	for sfx: Node in engine_sfx.get_children():
		var engine_player: AudioStreamPlayer3D = sfx
		if engine_player == target_sfx:
			if not engine_player.playing:
				engine_player.play()
		else:
			engine_player.stop()


## Shows the chase camera (the first-person camera goes back to being an alternative).
func _show_chase_camera() -> void:
	first_person_camera.current = false
	chase_camera.camera.current = true


## Rideable contract: the Riding state hands the Player over at the door; it plays [member mount_animation], which
## walks them in, and the chase camera starts behind the car.
func mount(_player: Player) -> void:
	player = _player
	_hide_prompt()
	set_driver(player)
	player.global_position = enter_car.global_position
	player.orientation = enter_car.global_transform
	player.orientation.origin = Vector3.ZERO
	player.player_model.global_transform = enter_car.global_transform
	player.velocity = Vector3.ZERO
	chase_camera.begin(player, self)
	driving_ui.show()


## Rideable contract: the Player is off (after the exit animation, or a bail out at speed).
func dismount(_player: Player) -> void:
	driving_ui.hide()
	first_person_camera.current = false
	chase_camera.end()
	if player == _player:
		set_driver(null)
	is_driving_this_car = false
	_accelerate = false
	_brake = false
	_handbrake = false
	_steer = 0.0


## Rideable contract: once seated (the Riding state does not call this while a clip plays), keeps the Player on
## the seat and feeds the drive inputs.
func ride(_player: Player, _delta: float) -> void:
	_player.global_position = driver_seat.global_position
	_player.orientation = driver_seat.global_transform
	_player.orientation.origin = Vector3.ZERO
	_player.player_model.global_transform = driver_seat.global_transform
	var blocked: bool = _player.is_paused or _player.is_ragdolling
	set_drive_input(
		not blocked and Input.is_action_pressed(_action(keyboard_accelerate_action, pad_accelerate_action)),
		not blocked and Input.is_action_pressed(_action(keyboard_brake_action, pad_brake_action)),
		not blocked and Input.is_action_pressed(_action(keyboard_handbrake_action, pad_handbrake_action)),
		0.0 if blocked else Input.get_axis("move_right", "move_left"))


## Rideable contract: the exit action gets out, through the door at rest (the Riding state plays
## [member dismount_animation] and finishes the dismount after it) or straight out at speed.
func ride_input(_player: Player, event: InputEvent) -> void:
	if not event.is_action_pressed(_action(keyboard_exit_action, pad_exit_action)):
		return
	if linear_velocity.length() > BAIL_OUT_SPEED:
		var exit_marker: Node3D = get_node_or_null("ExitCar") as Node3D
		if exit_marker == null:
			exit_marker = enter_car
		_player.global_position = exit_marker.global_position
		_player.dismount(true)
	else:
		_play_door_sequence()
		if first_person_camera.current:
			_show_chase_camera()
		is_driving_this_car = false
		_player.dismount()


## Rideable contract: label names on the Player's controls to their text while driving.
func get_contextual_controls(input_type_: int) -> Dictionary:
	var controls: Dictionary = {
		"joypad_button_10": "Handbrake",
		"joypad_button_13": "Prev\nStation",
		"joypad_button_14": "Next\nStation",
		"left_joystick": "Steer",
		"right_joystick": "Camera",
	}
	if input_type_ == Controls.InputType.KEYBOARD_MOUSE:
		controls["joypad_button_3"] = "Accelerate"
		controls["joypad_button_1"] = "Brake"
		controls["joypad_button_0"] = "Exit"
		controls["key_j"] = "Prev\nStation"
		controls["key_l"] = "Next\nStation"
	else:
		controls["joypad_axis_4_plus"] = "Brake"
		controls["joypad_axis_5_plus"] = "Accelerate"
		controls["joypad_button_3"] = "Exit"
	return controls


## The action for the driver's current input device.
func _action(keyboard_action: StringName, pad_action: StringName) -> StringName:
	if input_type == Controls.InputType.KEYBOARD_MOUSE:
		return keyboard_action
	return pad_action
