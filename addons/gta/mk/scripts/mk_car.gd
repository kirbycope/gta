class_name MkCar
extends Vehicle
## A kart: Mario Kart 64's acceleration curve, hop, drift and mini turbo.
##
## Built on [Vehicle] like the addon's other cars, and like [TwCar] it is
## deliberately not built on [GtaCar]. A kart has no gearbox, no clutch and no
## traction curve. What it has instead is a ten band acceleration table, a hop
## that starts a drift, and a mini turbo paid out for holding that drift long
## enough, and those three things are the whole feel of the game.
##
## [b]Where the numbers come from.[/b] [MkConst] and [MkRoster] carry them,
## read out of the mk64 decompilation rather than tuned by feel, and their class
## documentation shows the derivation. The short version is that the game holds
## a [member current_speed] in its own units, adds to it once a frame from a
## curve picked by how close to top speed it already is, and lets the kart
## settle where drive force balances drag. This class keeps that model intact
## and converts only at the edges: [method speed_limit] turns the game's number
## into metres per second, and the chassis pushes the wheels toward it.
##
## [b]The drift, which is the part worth getting right.[/b] Holding the drift
## button hops the kart ([code]kart_hop[/code]), and while it is held with the
## stick over, [member drift_duration] counts up one a frame to a cap of 100 and
## [member drift_state] climbs with it. Let go at or past
## [constant MkConst.MINI_TURBO_DRIFT_STATE] and the kart is paid a mini turbo
## lasting [constant MkConst.MINI_TURBO_FRAMES]. A drifting kart also keeps far
## more of its yaw rate as drive force than a turning one does
## ([constant MkConst.DRIFT_TURN_FORCE] against
## [constant MkConst.TURN_FORCE_BASE]), which is why drifting a corner is
## quicker than steering it even before the turbo lands.
##
## [b]Which way is forward.[/b] This chassis drives along [b]+Z[/b], the same way
## [TwCar] does, and for the same reason: that is where a Godot
## [VehicleBody3D] actually pushes a kart when its wheels are given a positive
## engine force. It was measured rather than assumed. With the wheels on +2600
## each, a rolling kart's velocity sits at +0.91 to +0.97 along its own
## [code]basis.z[/code], so the kart model is authored nose along +Z to match and
## [method forward] is the single place the decision is written down.
##
## [b]Over the network[/b] the body moves on the driver's authority the way every
## [Vehicle] does. What this class adds is that boosts, hops and spin outs are
## told to every peer rather than left to the synchroniser, because each is a
## short event that a position stream would smear or miss entirely.

signal boosted(seconds: float) ## A boost started, for the HUD and the exhaust.
signal mini_turbo_charged(state: int) ## The drift reached a new charge step.
signal mini_turbo_fired() ## The drift paid out.
signal spun_out() ## Hit by an item, or ran into a hazard.
signal item_used(item: int) ## This kart used the item in its slot.

## Roster key, and so the acceleration curve, the top speed and the colour.
@export var driver: StringName = &"rook"
## Which engine class the race is run at; see [constant MkConst.TOP_SPEED_UNITS].
@export var engine_class: StringName = &"150cc"

@export_group("Handling")
## Total drive force at the wheels. Unlike the ceilings above this one has no
## published figure: mk64 reaches its top speed by balancing force against a
## drag term, where a Godot vehicle pushes its wheels, so this is the force that
## gets the kart to the real ceiling in about the real time. Named in
## [constant MkConst.UNSOURCED].
@export var drive_force: float = 5200.0
@export var reverse_force: float = 2200.0 ## Backing up, which a kart barely does.
@export var brake_force: float = 220.0
@export var reverse_speed: float = 5.0 ## Metres per second backwards.
## Steering lock in degrees. mk64 turns the kart's facing directly rather than
## steering wheels, so this is a judgement; the speed dependence below is not.
@export var steering_lock: float = 30.0
@export var steering_speed: float = 8.0 ## Radians per second toward the stick.
## How much wider the kart turns while drifting. The game widens the yaw rate
## rather than the wheels, so the ratio is the judgement and the effect is not.
@export var drift_steering_scale: float = 1.7

@export_group("Model")
## Turn a dropped-in model about Y, in degrees, when it was not authored nose
## along +Z. This chassis drives along +Z, so a model built the usual Godot way
## round wants 180 here. See [MkAssets].
@export var model_yaw_degrees: float = 0.0
## The primitive meshes the addon ships, hidden when a model is dropped in to
## replace them. Named here rather than found by type so that a kart with extra
## decoration keeps it.
@export var stock_model_parts: Array[NodePath] = [
	^"Chassis", ^"Nose", ^"SeatBack", ^"Driver",
]
@export_group("")

@export_group("Drift Actions")
## The drift and hop button. mk64 puts it on R; this addon's spare "ability"
## action is Q on a keyboard and the left bumper on a pad.
@export var keyboard_drift_action: StringName = &"ability"
@export var pad_drift_action: StringName = &"ability"
## The item button, on the addon's throw action: T on a keyboard, and the
## right bumper on a pad.
@export var keyboard_item_action: StringName = &"throw"
@export var pad_item_action: StringName = &"throw"

## The kart's speed in the game's own topSpeed units, which is what the
## acceleration curve adds to. Metres per second is derived from it, never the
## other way round, so the curve stays the thing in charge.
var current_speed: float = 0.0
var drift_duration: int = 0 ## Frames held, capped at [constant MkConst.DRIFT_DURATION_CAP].
var drift_state: int = 0 ## The charge step, and what a mini turbo is paid on.
var is_drifting: bool = false
var is_hopping: bool = false
var boost_seconds: float = 0.0 ## Time left on a boost or mini turbo.
var spin_seconds: float = 0.0 ## Time left spun out, during which the pad is ignored.
var surface: int = MkConst.SURFACE_SOLID ## What is under the wheels, for the off road penalty.

var _accelerate: bool = false
var _brake: bool = false
var _drift_held: bool = false
var _steer: float = 0.0 ## Positive is left, matching the project's own move axis.
var _drift_sign: float = 0.0 ## Which way the drift was started, so it cannot be flipped mid slide.
var _top_speed_units: float = 0.0
var _frame_accumulator: float = 0.0 ## Carries the leftover of a frame, so the curve stays per frame.

@onready var sfx_engine: AudioStreamPlayer3D = get_node_or_null(^"SFXEngine")
@onready var sfx_drift: AudioStreamPlayer3D = get_node_or_null(^"SFXDrift")
@onready var sfx_boost: AudioStreamPlayer3D = get_node_or_null(^"SFXBoost")


func _ready() -> void:
	super()
	add_to_group(&"mk_karts")
	_top_speed_units = _top_speed_units_for_driver()
	_apply_drop_in_assets()


## Swap in whatever has been dropped into [constant MkAssets.ROOT], if
## anything has. With an empty folder this does nothing at all and the kart
## keeps the primitives it was built with, which is the case on a fresh clone.
##
## A replacement kart model stands in for the whole stock body, so the boxes and
## the capsule are hidden rather than left inside it. A replacement driver model
## only stands in for the figure, because a kart model that already has a driver
## in it wants no second one.
func _apply_drop_in_assets() -> void:
	if not MkAssets.has_any():
		return
	var kart_scene: PackedScene = MkAssets.kart_model(driver)
	var driver_scene: PackedScene = MkAssets.driver_model(driver)
	if kart_scene != null:
		_replace_model(kart_scene, stock_model_parts)
	elif driver_scene != null:
		_replace_model(driver_scene, [^"Driver"] as Array[NodePath])
	_apply_drop_in_sounds()


## Put [param scene] in the kart and hide the stock parts it replaces.
func _replace_model(scene: PackedScene, replaces: Array[NodePath]) -> void:
	var model: Node3D = scene.instantiate() as Node3D
	if model == null:
		push_warning("%s: the dropped in model is not a 3D scene, keeping the stock one." % name)
		return
	model.name = "DropInModel"
	model.rotate_y(deg_to_rad(model_yaw_degrees))
	add_child(model)
	for path: NodePath in replaces:
		var part: Node3D = get_node_or_null(path) as Node3D
		if part != null:
			part.visible = false


## Point the kart's players at any dropped in loops. A missing sound leaves the
## stock one alone rather than silencing the kart.
func _apply_drop_in_sounds() -> void:
	for pair: Array in [[sfx_engine, "engine"], [sfx_boost, "boost"], [sfx_drift, "drift"]]:
		var player: AudioStreamPlayer3D = pair[0] as AudioStreamPlayer3D
		if not is_instance_valid(player):
			continue
		var stream: AudioStream = MkAssets.sound(pair[1] as String)
		if stream != null:
			player.stream = stream


## The way the kart is pointing. This chassis is built nose along positive z,
## which is where the wheels actually push it; see the class description.
func forward() -> Vector3:
	return global_transform.basis.z


## The whole virtual control pad, and the only way into the handling model. A
## seated [Player] fills it from [method ride], a [HumanDriver] fills it from the
## keyboard and a [MkAi] fills it from the racing line; none of them can be
## told apart below this line.
func set_drive_input(accelerate: bool, brake_pressed: bool, drift_pressed: bool, steer: float) -> void:
	_accelerate = accelerate
	_brake = brake_pressed
	_drift_held = drift_pressed
	_steer = steer


## How fast the kart may go right now, in metres per second. This is the game's
## model rather than a ceiling: [member current_speed] is what the curve builds,
## and everything else scales it.
func speed_limit() -> float:
	var limit: float = MkConst.units_to_ms(MkConst.top_speed_units_per_frame(current_speed))
	if boost_seconds <= 0.0:
		return limit
	# The scale is a multiplier on speed, so it is applied to the speed and not
	# to the topSpeed units behind it. Those go through force = u * u / 25 on
	# the way out, so scaling them by 1.25 would come out as 1.5625 and a boost
	# would be half again as fast as it says on the constant.
	var ceiling: float = MkConst.units_to_ms(MkConst.top_speed_units_per_frame(_top_speed_units))
	return maxf(limit, ceiling) * _boost_scale()


## Speed along the nose, negative when reversing.
func forward_speed() -> float:
	return linear_velocity.dot(forward())


## The kart's top speed in metres per second, for the HUD and the AI.
func top_speed() -> float:
	return MkRoster.top_speed(driver, engine_class)


## The kart's ceiling in the game's own topSpeed units, which is what
## [member current_speed] fills toward and what the AI's catch up aims at.
func ceiling_speed_units() -> float:
	return _top_speed_units


## Start a boost lasting [param seconds], which is how an item, a boost ramp and
## a mini turbo all land. Told to every peer: it is too short an event to leave
## to the position stream.
@rpc("any_peer", "call_local", "reliable")
func boost(seconds: float) -> void:
	boost_seconds = maxf(boost_seconds, seconds)
	boosted.emit(seconds)
	if is_instance_valid(sfx_boost) and sfx_boost.stream != null:
		sfx_boost.play()


## Spin the kart out for [param seconds], which is what a hazard or a shot does.
## The pad is ignored while it lasts and the speed is quartered, the way
## [code]player_controller.c[/code] does with its own [code]/= 4[/code].
@rpc("any_peer", "call_local", "reliable")
func spin_out(seconds: float = 1.5) -> void:
	if spin_seconds > 0.0:
		return
	spin_seconds = seconds
	current_speed /= 4.0
	_end_drift(false)
	spun_out.emit()


## Whether the kart is going fast enough for the game to stop docking it the
## under speed penalty; see [constant MkConst.SLOW_PENALTY].
func is_up_to_speed() -> bool:
	return MkConst.ms_to_kmh(absf(forward_speed())) >= MkConst.SLOW_PENALTY_KMH


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	_tick_timers(delta)
	if spin_seconds > 0.0:
		apply_wheel_forces(0.0, brake_force)
		steering = move_toward(steering, 0.0, steering_speed * delta)
		return
	_step_speed(delta)
	_tick_drift(delta)
	_drive(delta)


## Boost and spin out both run down in seconds, not frames, so the kart behaves
## the same at any refresh rate even though the curve above it is per frame.
func _tick_timers(delta: float) -> void:
	boost_seconds = maxf(0.0, boost_seconds - delta)
	spin_seconds = maxf(0.0, spin_seconds - delta)


## [code]player_accelerate[/code] and [code]player_decelerate[/code], stepped at
## the game's own 30 fps however often Godot calls us. The leftover of a frame is
## carried in [member _frame_accumulator] rather than dropped, so a 60 fps client
## and a 30 fps one build speed identically.
func _step_speed(delta: float) -> void:
	_frame_accumulator += delta * MkConst.FPS
	var steps: int = int(_frame_accumulator)
	_frame_accumulator -= float(steps)
	for _i: int in mini(steps, 4):
		_step_speed_one_frame()


## One game frame of the acceleration curve.
func _step_speed_one_frame() -> void:
	var ceiling: float = _top_speed_units
	if _accelerate and not _brake:
		var fraction: float = clampf(current_speed / maxf(ceiling, 1.0), 0.0, 1.0)
		current_speed += MkRoster.acceleration_fraction(driver, fraction)
	elif _brake:
		current_speed -= MkRoster.acceleration_fraction(driver, 0.0)
	else:
		# off the throttle a kart slows rather than coasting for ever
		current_speed -= MkRoster.acceleration_fraction(driver, 0.0) * 0.25
	current_speed -= _surface_penalty()
	current_speed = clampf(current_speed, 0.0, ceiling)


## What the ground under the wheels takes off the kart. The game does this with
## a per surface force table; off road is the part of it the surface type doc
## publishes, so that is what is reproduced.
func _surface_penalty() -> float:
	if boost_seconds > 0.0:
		return 0.0 ## A boost carries a kart across grass, which is most of the point of one.
	if MkConst.is_off_road(surface):
		return _top_speed_units * 0.02
	return 0.0


## The hop, the drift and the mini turbo, in the order the game runs them.
func _tick_drift(_delta: float) -> void:
	var wants: bool = _drift_held and absf(_steer) > 0.2 and wheels_in_contact() >= 3
	if wants and not is_drifting:
		_begin_drift()
	elif is_drifting and not _drift_held:
		_end_drift(true)
	if not is_drifting:
		drift_duration = maxi(0, drift_duration - 1)
		return
	drift_duration = mini(MkConst.DRIFT_DURATION_CAP, drift_duration + 1)
	var was: int = drift_state
	# the charge climbs with the hold, and the mini turbo is paid at step 2
	drift_state = mini(3, drift_duration / 20)
	if drift_state != was:
		mini_turbo_charged.emit(drift_state)


## [code]kart_hop[/code]: the kart leaves the ground and the drift begins.
func _begin_drift() -> void:
	is_drifting = true
	is_hopping = true
	drift_state = 0
	_drift_sign = signf(_steer)
	# the hop's initial velocity, converted out of the game's units per frame
	apply_central_impulse(Vector3.UP * MkConst.HOP_VELOCITY * MkConst.UNIT * MkConst.FPS * mass)
	if is_instance_valid(sfx_drift) and sfx_drift.stream != null:
		sfx_drift.play()


## Letting go. [param pay] is false when the drift was cancelled rather than
## released, which is what a spin out does; the game's
## [code]cancel_drift_effect[/code] does the same.
func _end_drift(pay: bool) -> void:
	if not is_drifting:
		return
	is_drifting = false
	is_hopping = false
	if pay and drift_state >= MkConst.MINI_TURBO_DRIFT_STATE:
		boost(MkConst.frames(MkConst.MINI_TURBO_FRAMES))
		mini_turbo_fired.emit()
	drift_state = 0
	_drift_sign = 0.0
	if is_instance_valid(sfx_drift) and sfx_drift.playing:
		sfx_drift.stop()


## Push the wheels toward whatever [method speed_limit] currently allows, and
## point them where the stick says.
func _drive(delta: float) -> void:
	var speed: float = forward_speed()
	var drive: float = 0.0
	var stop: float = 0.0

	if _brake and speed > 0.5:
		stop = brake_force
	elif _brake:
		drive = -reverse_force if speed > -reverse_speed else 0.0
	elif speed < speed_limit():
		drive = drive_force * (1.5 if boost_seconds > 0.0 else 1.0)

	apply_wheel_forces(drive, stop)

	var lock: float = deg_to_rad(steering_lock)
	var target: float = lock * clampf(_steer, -1.0, 1.0)
	if is_drifting:
		# a drift holds its own side: the stick trims the angle rather than choosing it
		target = lock * drift_steering_scale * clampf(_drift_sign * 0.7 + _steer * 0.3, -1.0, 1.0)
	# mk64 divides the stick by 8 + currentSpeed / 50, so a fast kart turns less
	# for the same input. The speed in that expression is the game's own
	# currentSpeed, which runs to about 320, not a velocity: feeding it units per
	# frame instead leaves the divisor at 8 whatever the kart is doing, and a
	# kart that keeps full lock at top speed simply rolls itself over.
	var divisor: float = MkConst.STEER_DIVISOR_BASE + current_speed / MkConst.STEER_DIVISOR_SPEED
	target *= MkConst.STEER_DIVISOR_BASE / divisor
	# Negated, and measured rather than reasoned about. [member _steer] is
	# positive for left, because that is what Input.get_axis("move_right",
	# "move_left") gives and what every caller here assumes. A kart driven with a
	# positive steering angle was measured travelling 5.39 m to its own right
	# over 150 frames, and 5.29 m to its left on a negative one, so the angle
	# this chassis wants is the opposite sign to the stick. Without this the AI
	# steers away from the racing line and parks itself against the wall.
	steering = move_toward(steering, -target, steering_speed * delta)
	_update_engine_sound()


## The engine note follows the speed, and jumps while a boost is lit.
func _update_engine_sound() -> void:
	if not is_instance_valid(sfx_engine) or sfx_engine.stream == null:
		return
	if not sfx_engine.playing:
		sfx_engine.play()
	var fraction: float = clampf(absf(forward_speed()) / maxf(top_speed(), 1.0), 0.0, 1.0)
	sfx_engine.pitch_scale = lerpf(0.8, 1.7, fraction) * (1.3 if boost_seconds > 0.0 else 1.0)


## How much over its ceiling a boost carries the kart. The game moves the kart
## toward a target held in an accumulator whose conversion to the units this
## model works in the decomp never states, so this is a judgement rather than a
## reading; see [constant MkConst.BOOST_SPEED_SCALE].
func _boost_scale() -> float:
	return MkConst.BOOST_SPEED_SCALE


## The driver's topSpeed figure in the game's own units, which is what the
## acceleration curve fills toward.
func _top_speed_units_for_driver() -> float:
	var row: Dictionary = MkConst.TOP_SPEED_UNITS.get(engine_class, {})
	if row.is_empty():
		return 0.0
	return float(row["light" if MkRoster.is_light(driver) else "standard"])


## Rideable contract: read the buttons for a seated driver.
func ride(rider: Player, _delta: float) -> void:
	if rider.is_paused or rider.is_ragdolling:
		set_drive_input(false, false, false, 0.0)
		return
	read_controls()


## The pad, off the buttons. [member Vehicle.input_type] says which bindings.
func read_controls() -> void:
	set_drive_input(
		Input.is_action_pressed(_action(keyboard_accelerate_action, pad_accelerate_action)),
		Input.is_action_pressed(_action(keyboard_brake_action, pad_brake_action)),
		Input.is_action_pressed(_action(keyboard_drift_action, pad_drift_action)),
		Input.get_axis("move_right", "move_left"))


## Toggles, which are presses rather than holds. The item button is one: holding
## it must not empty the whole slot in three frames.
func read_toggles(event: InputEvent) -> void:
	if event.is_action_pressed(_action(keyboard_item_action, pad_item_action)):
		item_used.emit(MkItems.Item.NONE)


## Rideable contract: label names on the Player's controls to their text.
func get_contextual_controls(input_type_: int) -> Dictionary:
	var controls: Dictionary = {
		"left_joystick": "Steer",
		"right_joystick": "Camera",
	}
	if input_type_ == Controls.InputType.KEYBOARD_MOUSE:
		controls["joypad_button_3"] = "Accelerate"
		controls["joypad_button_1"] = "Brake"
		if player != null:
			controls["joypad_button_0"] = "Exit"
	else:
		controls["joypad_axis_5_plus"] = "Accelerate"
		controls["joypad_axis_4_plus"] = "Brake"
		if player != null:
			controls["joypad_button_3"] = "Exit"
	controls["joypad_button_9"] = "Drift" ## The left bumper, where "ability" sits.
	controls["joypad_button_10"] = "Item" ## The right bumper, where "throw" sits.
	return controls
