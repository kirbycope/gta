class_name Tm2Car
extends Vehicle
## A Twisted Metal 2 car: arcade handling, a turbo, and a wreck state.
##
## Built on [Vehicle] like the addon's other two cars, and deliberately not on [GtaCar]. Twisted
## Metal is not a driving game with weapons bolted on, it is a shooter where the floor moves: the
## cars turn on a dime at any speed, have no gearbox to speak of and reach their top speed almost at
## once. A five gear transmission and a traction curve would be fighting that, so there is neither.
##
## What drives the car is two published numbers and a handful of judgements. [Tm2Roster] carries the
## real top speed and turbo speed for each car off the community stat tables, and those are the two
## ceilings here. Everything else, the force that gets the car to them, the brake, the steering lock
## and the turbo meter, has no published figure anywhere, so each one is an export with a comment
## saying so and each is listed in [constant Tm2Roster.UNSOURCED] rather than dressed up as a fact.
##
## [b]Which way is forward.[/b] This chassis drives along [b]+Z[/b], not Godot's usual -Z. That was
## measured rather than assumed: an opponent rolling on four wheels in the Los Angeles arena travels
## along its own [code]basis.z[/code] with a mean dot product of 0.99. The model, the seat, the
## camera and both muzzles are all arranged around that, and [method forward] is the single place it
## is written down, so nothing else has to repeat the decision.
##
## [b]The turbo.[/b] Twisted Metal 2's turbo meter sits above the weapon bay and refills on its own
## over time, which is what [member turbo] models here. The real game also drops turbo pickups in its
## arenas; this demo has no pickups of any kind, so that half is missing rather than wrong. How fast
## the real meter refills is not published, so [member turbo_recharge_time] is a judgement.
##
## [b]The wreck.[/b] [CarCombat] owns the health; when it runs out its [signal CarCombat.died] is
## wired in the scene to [method on_died] and the car stops answering the controls and rolls to a
## stop. There is no fire and no explosion: that was the road car's damage model and it does not
## come with this chassis.

signal turbo_changed(amount: float) ## The meter moved, for the HUD.
signal wrecked() ## Health ran out; the car no longer answers the controls.

@export var car: StringName = &"roadkill" ## Roster key, and so the top speed. See [Tm2Roster].

@export_group("Handling")
## None of these are published. Twisted Metal's own handling figures have never been released and the
## per-car stat screens on the disc are pictures rather than tables, so every one of them is a
## judgement chosen to feel like the game, and every one is named in [constant Tm2Roster.UNSOURCED].
@export var drive_force: float = 9000.0 ## Total drive force at the wheels, split across them once.
@export var reverse_force: float = 4500.0 ## Backing up is slower than going forward, as in the game.
@export var brake_force: float = 260.0 ## Per-car brake, split across the wheels by the chassis.
@export var reverse_speed: float = 9.0 ## How fast it will go backwards, in metres per second.
## Steering lock in degrees, and it does not shrink with speed. Twisted Metal's cars turn as hard at
## full tilt as they do at a crawl, which is most of why the game feels the way it does.
@export var steering_lock: float = 32.0
@export var steering_speed: float = 7.0 ## Radians per second the wheels turn toward the stick.

@export_group("Turbo")
@export var turbo_seconds: float = 3.0 ## A full meter is this long held down.
@export var turbo_recharge_time: float = 12.0 ## Empty to full, with the button off.

@export_group("Turbo Actions")
## Twisted Metal 2 puts turbo on Triangle. There is no Triangle in this addon's action set, and
## brake already has shift, so it sits on the addon's spare "ability" action instead: Q on a
## keyboard, the left bumper on a pad.
@export var keyboard_turbo_action: StringName = &"ability"
@export var pad_turbo_action: StringName = &"ability"

var turbo: float = 1.0: set = _set_turbo ## The meter, nought to one.
var is_wrecked: bool = false ## Health ran out; the controls do nothing.
var is_turbo_engaged: bool = false ## The button is down and there is meter left to spend.

var _accelerate: bool = false
var _brake: bool = false
var _turbo_held: bool = false
var _steer: float = 0.0 ## Positive is left, matching the project's own move axis.
var _top_speed: float = 0.0 ## Published, from the roster.
var _turbo_speed: float = 0.0 ## Published, from the roster.

@onready var sfx_engine: AudioStreamPlayer3D = get_node_or_null(^"SFXEngine")
@onready var sfx_turbo: AudioStreamPlayer3D = get_node_or_null(^"SFXTurbo")


func _ready() -> void:
	super()
	_top_speed = Tm2Roster.top_speed(car)
	_turbo_speed = Tm2Roster.top_speed(car, true)
	add_to_group(&"tm2_cars")
	turbo_changed.emit(turbo)


## The way the car is pointing. This chassis is built nose along positive z, which is the opposite of
## Godot's usual convention but is where the wheels actually push it; see the class description.
func forward() -> Vector3:
	return global_transform.basis.z


## The whole virtual control pad, and the only way into the handling model. A seated [Player] fills
## it from [method ride] and an [AiDriver] fills it directly, exactly as Twisted Metal's own
## [code]AICarUpdateControlPad[/code] does; the drivetrain below cannot tell the two apart.
func set_drive_input(accelerate: bool, brake_pressed: bool, turbo_pressed: bool, steer: float) -> void:
	_accelerate = accelerate
	_brake = brake_pressed
	_turbo_held = turbo_pressed
	_steer = steer


## Health ran out. Wired to [signal CarCombat.died] in the scene.
func on_died(_killer: Node3D) -> void:
	if is_wrecked:
		return
	is_wrecked = true
	set_drive_input(false, false, false, 0.0)
	wrecked.emit()


## How fast this car may go right now, in metres per second: its published top speed, or its
## published turbo speed while the turbo is lit.
func speed_limit() -> float:
	return _turbo_speed if is_turbo_engaged else _top_speed


## Speed along the nose, negative when reversing.
func forward_speed() -> float:
	return linear_velocity.dot(forward())


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_tick_turbo(delta)
	if is_wrecked:
		apply_wheel_forces(0.0, brake_force)
		steering = move_toward(steering, 0.0, steering_speed * delta)
		return
	_drive(delta)


## The meter drains while the button is down and there is something to spend, and fills again
## whenever it is not. The real game's meter refills on its own the same way.
func _tick_turbo(delta: float) -> void:
	var wants: bool = _turbo_held and not is_wrecked and turbo > 0.0
	is_turbo_engaged = wants
	if wants:
		turbo = maxf(0.0, turbo - delta / maxf(turbo_seconds, 0.01))
	elif turbo < 1.0:
		turbo = minf(1.0, turbo + delta / maxf(turbo_recharge_time, 0.01))
	if is_instance_valid(sfx_turbo) and sfx_turbo.stream != null:
		if wants and not sfx_turbo.playing:
			sfx_turbo.play()
		elif not wants and sfx_turbo.playing:
			sfx_turbo.stop()


## Arcade handling in one function: push until the published ceiling, brake to a stop and then
## reverse, and turn as hard at speed as at rest.
func _drive(delta: float) -> void:
	var speed: float = forward_speed()
	var drive: float = 0.0
	var stop: float = 0.0

	if _brake and speed > 0.5:
		# still rolling forward, so the brake is a brake
		stop = brake_force
	elif _brake:
		# stopped or already rolling back, so it is reverse
		drive = -reverse_force if speed > -reverse_speed else 0.0
	elif _accelerate:
		drive = drive_force if speed < speed_limit() else 0.0
	elif absf(speed) > 0.1:
		# off the throttle a Twisted Metal car slows rather than coasting for ever
		stop = brake_force * 0.25

	apply_wheel_forces(drive, stop)

	var target: float = deg_to_rad(steering_lock) * clampf(_steer, -1.0, 1.0)
	steering = move_toward(steering, target, steering_speed * delta)
	_update_engine_sound()


## The engine note follows the speed. This is the addon's own Gravity Sound engine loop put to use;
## a real Twisted Metal engine would want its own recording.
func _update_engine_sound() -> void:
	if not is_instance_valid(sfx_engine) or sfx_engine.stream == null:
		return
	if not sfx_engine.playing:
		sfx_engine.play()
	var fraction: float = clampf(absf(forward_speed()) / maxf(_top_speed, 1.0), 0.0, 1.0)
	sfx_engine.pitch_scale = lerpf(0.8, 1.6, fraction) * (1.25 if is_turbo_engaged else 1.0)


## Rideable contract: read the buttons for a seated driver. The only thing a body adds to reading the
## pad is that a paused or ragdolling one lets go of it.
func ride(rider: Player, _delta: float) -> void:
	if rider.is_paused or rider.is_ragdolling:
		set_drive_input(false, false, false, 0.0)
		return
	read_controls()


## The pad, off the buttons. A seated [Player] and a [HumanDriver] both come through here, and the AI
## calls [method set_drive_input] directly; the drivetrain cannot tell which of the three filled it.
## [member Vehicle.input_type] says which bindings to read.
func read_controls() -> void:
	set_drive_input(
		Input.is_action_pressed(_action(keyboard_accelerate_action, pad_accelerate_action)),
		Input.is_action_pressed(_action(keyboard_brake_action, pad_brake_action)),
		Input.is_action_pressed(_action(keyboard_turbo_action, pad_turbo_action)),
		Input.get_axis("move_right", "move_left"))


## Rideable contract: label names on the Player's controls to their text while driving.
func get_contextual_controls(input_type_: int) -> Dictionary:
	var controls: Dictionary = {
		"left_joystick": "Steer",
		"right_joystick": "Camera",
	}
	if input_type_ == Controls.InputType.KEYBOARD_MOUSE:
		controls["joypad_button_3"] = "Accelerate"
		controls["joypad_button_1"] = "Reverse"
		controls["joypad_button_0"] = "Exit"
	else:
		controls["joypad_axis_5_plus"] = "Accelerate"
		controls["joypad_axis_4_plus"] = "Reverse"
		controls["joypad_button_3"] = "Exit"
	controls["joypad_button_4"] = "Turbo"
	return controls


func _set_turbo(value: float) -> void:
	var clamped: float = clampf(value, 0.0, 1.0)
	if is_equal_approx(clamped, turbo):
		return
	turbo = clamped
	turbo_changed.emit(clamped)
