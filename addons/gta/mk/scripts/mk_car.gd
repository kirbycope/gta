class_name MkCar
extends Vehicle
## A kart: Mario Kart 64's own movement, frame by frame.
##
## Built on [Vehicle] like the addon's other cars for the rideable contract and
## the network hand-off, and on nothing else of it: the chassis has no wheels,
## no gravity and no physics rotation, because the game's kart is not a vehicle.
## It is a point with a facing, moved by one line a frame
## ([code]func_8002D268[/code] in the mk64 decompilation's
## [code]src/player_controller.c[/code]):
## [codeblock]
## v += (force * facing + gravity + lateral - v * 0.12 * 5800) / 6000
## [/codeblock]
## The drag term and the divisor give the velocity an 8.6 frame lag behind the
## facing, and that lag is the whole of the game's grip: turn the facing and the
## velocity follows it a third of a second later, which is the slide; stop
## turning and it settles. Everything else in this file decides what the force
## and the facing are each frame, and every number it uses is in [MkConst] with
## the line of the decomp it came from.
##
## [b]The frame.[/b] The model is stepped in the game's own thirtieths of a
## second ([method step_frame]) however often Godot ticks, and the body is given
## the result as a velocity and a pose. In order, as the game runs them: the hop
## and the drift on R, the steering ladder and the yaw rate, A and B on
## [member current_speed], the loss fraction on the force, the lateral term, the
## integrator, the ground.
##
## [b]Which way is forward.[/b] The kart's nose is along [b]+Z[/b], as the scene
## is built, and [method forward] is the one place that is written down.
##
## [b]Over the network[/b] the body moves on the driver's authority the way every
## [Vehicle] does. Boosts, hops and spin outs are told to every peer rather than
## left to the synchroniser, because each is a short event that a position
## stream would smear or miss entirely.

signal boosted(seconds: float) ## A boost started, for the HUD and the exhaust.
signal mini_turbo_charged(state: int) ## The drift reached a new charge step.
signal mini_turbo_fired() ## The drift paid out.
signal spun_out() ## Hit by an item, or ran into a hazard.
signal item_used(item: int) ## This kart used the item in its slot.

## Roster key, and so the acceleration curve, the top speed and the colour.
@export var driver: StringName = &"rook"
## Which engine class the race is run at; see [constant MkConst.TOP_SPEED_UNITS].
@export var engine_class: StringName = &"150cc"
## A computer driver's kart: it accelerates on the game's CPU path (3.2 times
## the table) and is given the catch-up force when [member cpu_fast] is set.
@export var is_cpu: bool = false

@export_group("Model")
## Turn a dropped-in model about Y, in degrees, when it was not authored nose
## along +Z. See [MkAssets].
@export var model_yaw_degrees: float = 0.0
## The primitive meshes the addon ships, hidden when a model is dropped in to
## replace them. Named here rather than found by type so that a kart with extra
## decoration keeps it.
@export var stock_model_parts: Array[NodePath] = [
	^"Chassis", ^"Nose", ^"SeatBack", ^"Driver",
	^"FrontLeft/Tyre", ^"FrontRight/Tyre", ^"RearLeft/Tyre", ^"RearRight/Tyre",
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

const GROUND_PROBE_UP: float = 1.0 ## Metres above the origin the ground ray starts.
const GROUND_PROBE_DOWN: float = 3.0 ## And how far below it reaches.
const GROUND_SNAP: float = 0.06 ## Metres off the ground before the kart is in the air.
const WALL_NORMAL_MAX_UP: float = 0.5 ## A contact normal flatter than this is a wall.
const MAX_FRAMES_PER_TICK: int = 4 ## A stalled tick catches up at most this many game frames.
const SPIN_OUT_TURNS: float = 1.0 ## A spin out turns the kart this many times over its length.

# The game's own state, in its own units: speeds in units a frame, forces in
# the units the acceleration table builds, angles in radians (the game's 65536ths
# are converted at the edges, see MkConst).
var current_speed: float = 0.0 ## [code]currentSpeed[/code]: what the throttle builds and the force is squared from.
var velocity_units: Vector3 = Vector3.ZERO ## [code]velocity[/code]: units a frame, in the world.
var speed: float = 0.0 ## [code]speed[/code]: the horizontal speed in units a frame.
var previous_speed: float = 0.0
var yaw: float = 0.0 ## [code]rotation[1][/code] as a Godot yaw: radians about up, counter-clockwise positive.
var turn_angle: float = 0.0 ## [code]unk_0C0[/code]: the slide between travel and facing in radians, positive to the right.
var yaw_rate: float = 0.0 ## [code]unk_078[/code] in radians a frame, positive to the right.
var drift_duration: int = 0 ## Frames in the drift, capped at [constant MkConst.DRIFT_DURATION_CAP].
var drift_state: int = 0 ## [code]driftState[/code]: the charge step, and what a mini turbo is paid on.
var drift_counter: int = 0 ## [code]driftStateCounter[/code]: frames the stick has been held against the slide.
var is_drifting: bool = false ## [code]DRIFTING_EFFECT[/code].
var is_hopping: bool = false ## [code]HOP_EFFECT[/code]: from the hop to the touchdown.
var is_midair: bool = false ## [code]MIDAIR_EFFECT[/code].
var boost_seconds: float = 0.0 ## Time left on the mini turbo or the mushroom, whichever is longer, for the HUD.
var spin_seconds: float = 0.0 ## Time left spun out, during which the pad is ignored.
var surface: int = MkConst.SURFACE_SOLID ## What is under the kart, for the surface tables.
var cpu_fast: bool = false ## [code]CPU_FAST_EFFECT[/code]: the catch-up, set by [MkAi].

var _accelerate: bool = false
var _brake: bool = false
var _drift_held: bool = false
var _drift_pressed: bool = false ## The button went down and the hop has not spent it yet.
var _hop_armed: bool = true ## R has been let go since the last press.
var _was_frozen: bool = false ## The race holds the body frozen on the grid; the model syncs when it is let go.
var _stick_back: bool = false ## The stick pulled back, which with B at a standstill is reverse.
var _steer: float = 0.0 ## Positive is left, matching the project's own move axis.
var _stick: float = 0.0 ## The game's reading: -53..53, positive to the right.
var _steer_position: float = 0.0 ## [code]steerPosition[/code]: the stick after the ladder, -53..53.
var _steer_delta: float = 0.0 ## [code]steerPositionDelta[/code]: how far the stick moved this frame (old less new).
var _steer_increment: float = 0.0 ## [code]steerChangeIncrement[/code].
var _sideways_kick: float = 0.0 ## [code]unk_090[/code]: the lateral kick a flick of the stick leaves.
var _force: float = 0.0 ## [code]unk_08C[/code]: currentSpeed squared over 25 while on the ground.
var _loss: float = 0.0 ## [code]unk_104[/code]: the share of the force lost, eased toward the frame's figure.
var _air_loss: float = 0.0 ## [code]unk_0A0[/code].
var _mini_turbo_force: float = 0.0 ## [code]unk_0E8[/code].
var _mushroom_force: float = 0.0 ## [code]boostPower[/code].
var _cpu_fast_force: float = 0.0 ## [code]unk_0E4[/code] for a human, [code]unk_0E8[/code] for a CPU.
var _mini_turbo_on: bool = false ## [code]MINI_TURBO_EFFECT[/code].
var _mini_turbo_frames: int = 0 ## [code]unk_23A[/code].
var _boost_frames: float = 0.0 ## [code]boostTimer[/code], the mushroom.
var _brake_slide: float = 0.0 ## [code]unk_20C[/code].
var _braking: bool = false ## [code]BRAKING_EFFECT[/code].
var _reversing: bool = false ## [code]BACK_UP[/code].
var _moving_backwards: bool = false ## [code]MOVE_BACKWARDS[/code].
var _spin_in_place: bool = false ## [code]AB_SPIN_EFFECT[/code].
var _drift_outside: bool = false ## [code]DRIFT_OUTSIDE_EFFECT[/code].
var _turn_left: bool = false ## [code]LEFT_TURN[/code].
var _turn_right: bool = false ## [code]RIGHT_TURN[/code].
var _hop_velocity: float = 0.0 ## [code]kartHopVelocity[/code], units a frame.
var _hop_acceleration: float = 0.0
var _hop_jerk: float = 0.0
var _kart_gravity: float = MkConst.KART_GRAVITY
var _vertical_divisor: float = 1.0 ## [code]unk_DAC[/code].
var _air_frames: int = 0 ## [code]unk_0C2[/code].
var _height: float = 0.0 ## The kart's own height in metres, moved by the model rather than the body.
var _ground_height: float = 0.0
var _ground_normal: Vector3 = Vector3.UP
var _display_normal: Vector3 = Vector3.UP
var _has_ground: bool = false
var _wall_normal: Vector3 = Vector3.ZERO ## From the body's contacts this tick, zero when nothing is touched.
var _touching_wall: bool = false
var _spin_yaw_left: float = 0.0 ## Radians of spin out still to turn through.
var _frame_accumulator: float = 0.0 ## Carries the leftover of a tick, so the model stays in whole game frames.
var _top_speed_units: float = 0.0
var _kart_class: StringName = &"standard"
var _old_position: Vector3 = Vector3.ZERO ## Where the kart was a frame ago, for the turn angle and the backwards check.

@onready var sfx_engine: AudioStreamPlayer3D = get_node_or_null(^"SFXEngine")
@onready var sfx_drift: AudioStreamPlayer3D = get_node_or_null(^"SFXDrift")
@onready var sfx_boost: AudioStreamPlayer3D = get_node_or_null(^"SFXBoost")


func _ready() -> void:
	super()
	add_to_group(&"mk_karts")
	gravity_scale = 0.0
	lock_rotation = true
	_top_speed_units = _top_speed_units_for_driver()
	_kart_class = MkRoster.kart_class(driver)
	if _kart_class == &"":
		_kart_class = &"standard"
	yaw = atan2(global_transform.basis.z.x, global_transform.basis.z.z)
	_height = global_position.y
	_old_position = global_position
	_apply_drop_in_assets()


## Swap in whatever has been dropped into [constant MkAssets.ROOT], if
## anything has. With an empty folder this does nothing at all and the kart
## keeps the primitives it was built with, which is the case on a fresh clone.
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
		var player_: AudioStreamPlayer3D = pair[0] as AudioStreamPlayer3D
		if not is_instance_valid(player_):
			continue
		var stream: AudioStream = MkAssets.sound(pair[1] as String)
		if stream != null:
			player_.stream = stream


# --- What the rest of the demo reads ------------------------------------------------------------------------------

## The way the kart is pointing: the facing the game keeps as [code]rotation[1][/code], flat.
func forward() -> Vector3:
	return Vector3(sin(yaw), 0.0, cos(yaw))


## The kart's right, flat.
func right() -> Vector3:
	return forward().cross(Vector3.UP)


## The whole virtual control pad, and the only way into the handling model. A
## seated [Player] fills it from [method ride], a [HumanDriver] fills it from the
## keyboard and a [MkAi] fills it from the racing line; none of them can be
## told apart below this line. [param drift_pressed] is the button's state; the
## press that hops is told from the hold here.
func set_drive_input(accelerate: bool, brake_pressed: bool, drift_pressed: bool, steer: float, stick_back: bool = false) -> void:
	_accelerate = accelerate
	_brake = brake_pressed
	if drift_pressed and _hop_armed:
		_drift_pressed = true
		_hop_armed = false
	elif not drift_pressed:
		_hop_armed = true # R has to come up before it can hop again, the way an N64 buttonPressed edge works
	_drift_held = drift_pressed
	_steer = clampf(steer, -1.0, 1.0)
	_stick_back = stick_back


## Puts the model where the body has been placed: a teleport, the start grid or
## a recovery. The facing is read off the transform and the motion dropped.
func sync_from_transform() -> void:
	yaw = atan2(global_transform.basis.z.x, global_transform.basis.z.z)
	_height = global_position.y
	_old_position = global_position
	velocity_units = Vector3.ZERO
	speed = 0.0
	previous_speed = 0.0
	turn_angle = 0.0
	yaw_rate = 0.0
	_steer_position = 0.0
	_brake_slide = 0.0
	is_midair = false
	is_hopping = false
	_hop_velocity = 0.0
	_cancel_drift()
	_display_normal = Vector3.UP
	linear_velocity = Vector3.ZERO


## Speed along the nose in metres per second, negative when reversing.
func forward_speed() -> float:
	return MkConst.units_to_ms(Vector3(velocity_units.x, 0.0, velocity_units.z).dot(forward()))


## The kart's top speed in metres per second, for the HUD and the AI.
func top_speed() -> float:
	return MkRoster.top_speed(driver, engine_class)


## The kart's ceiling in the game's own topSpeed units, which is what
## [member current_speed] fills toward.
func ceiling_speed_units() -> float:
	return _top_speed_units


## The yaw rate in the game's own units a frame, positive to the right; the camera reads it.
func yaw_rate_units() -> float:
	return yaw_rate / TAU * MkConst.ANGLE_UNITS_PER_TURN


func is_drifting_outside() -> bool:
	return _drift_outside


func is_spinning_in_place() -> bool:
	return _spin_in_place


## Whether the kart is going fast enough for the game to stop giving it the
## slow kart's extra force; see [constant MkConst.SLOW_PENALTY].
func is_up_to_speed() -> bool:
	return MkConst.units_to_kmh(speed) >= MkConst.SLOW_PENALTY_KMH


## Start a mushroom boost lasting [param seconds] (the game's own is
## [constant MkConst.BOOST_FRAMES]): [code]boostPower[/code] is pulled toward 400
## and added to the force with no loss on it. Told to every peer: it is too
## short an event to leave to the position stream.
@rpc("any_peer", "call_local", "reliable")
func boost(seconds: float) -> void:
	_boost_frames = maxf(_boost_frames, seconds * MkConst.FPS)
	_refresh_boost_seconds()
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
	_spin_yaw_left = TAU * SPIN_OUT_TURNS
	current_speed /= 4.0
	_force = MkConst.drive_force(current_speed)
	_end_drift(false)
	spun_out.emit()


# --- The tick ------------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if freeze:
		_was_frozen = true
		return
	if _was_frozen:
		# the grid, a recovery or a teleport placed the body while it was held: the model starts from there
		_was_frozen = false
		sync_from_transform()
	_probe_ground()
	_frame_accumulator += delta * MkConst.FPS
	var steps: int = int(_frame_accumulator)
	_frame_accumulator -= float(steps)
	for _i: int in mini(steps, MAX_FRAMES_PER_TICK):
		step_frame()
	_apply_to_body()
	_update_engine_sound()


## The body's contacts: a wall is anything with a flat enough normal. The
## model takes the component of the velocity into it away and charges the
## game's wall deceleration.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	_touching_wall = false
	_wall_normal = Vector3.ZERO
	for i: int in state.get_contact_count():
		var normal: Vector3 = state.get_contact_local_normal(i)
		if absf(normal.y) >= WALL_NORMAL_MAX_UP:
			continue
		# another kart is a bump, not a wall: the game's own kart-to-kart response is not ported, and
		# charging the wall deceleration for it would stall the whole grid on the first corner
		if state.get_contact_collider_object(i) is RigidBody3D:
			continue
		_touching_wall = true
		_wall_normal += normal
	if _touching_wall:
		_wall_normal = _wall_normal.normalized()


## Where the ground is under the kart this tick, its normal and its surface.
func _probe_ground() -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = global_position + Vector3.UP * GROUND_PROBE_UP
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, from - Vector3.UP * (GROUND_PROBE_UP + GROUND_PROBE_DOWN))
	query.exclude = [get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	_has_ground = not hit.is_empty()
	if _has_ground:
		_ground_height = (hit["position"] as Vector3).y
		_ground_normal = (hit["normal"] as Vector3).normalized()
		surface = _surface_of(hit["collider"] as Node)
	else:
		_ground_normal = Vector3.UP


## A course says what a floor is made of with an [code]mk_surface[/code] meta on
## the collider holding one of the [MkConst] surface ids; the "GRASS" and
## "off_road" groups are grass; anything else is solid.
static func _surface_of(collider: Node) -> int:
	if collider == null:
		return MkConst.SURFACE_SOLID
	if collider.has_meta(&"mk_surface"):
		return int(collider.get_meta(&"mk_surface"))
	if collider.is_in_group(&"GRASS") or collider.is_in_group(&"off_road"):
		return MkConst.SURFACE_GRASS
	return MkConst.SURFACE_SOLID


## One game frame, in the order [code]func_8002D268[/code] and
## [code]func_80037CFC[/code] run them.
func step_frame() -> void:
	_old_position = Vector3(global_position.x, _height, global_position.z)
	_tick_spin_out()
	_tick_boost_timers()
	_update_drift_duration()
	_pay_mini_turbo()
	if spin_seconds <= 0.0:
		_read_pad()
	_relax_gravity()
	var force: float = _drive_force()
	var lateral: Vector3 = _turn_and_lateral()
	_integrate(force, lateral)
	_move_vertical()
	_update_turn_angle()
	_measure_speed()
	_drift_pressed = false


# --- Timers ---------------------------------------------------------------------------------------------------------

func _tick_spin_out() -> void:
	if spin_seconds <= 0.0:
		return
	var step: float = _spin_yaw_left / maxf(spin_seconds * MkConst.FPS, 1.0)
	yaw -= step
	_spin_yaw_left -= step
	spin_seconds = maxf(0.0, spin_seconds - 1.0 / MkConst.FPS)
	_accelerate = false
	_brake = false
	_drift_held = false
	yaw_rate = 0.0


func _tick_boost_timers() -> void:
	if _boost_frames > 0.0:
		_boost_frames = maxf(0.0, _boost_frames - 1.0)
	_refresh_boost_seconds()


func _refresh_boost_seconds() -> void:
	boost_seconds = maxf(float(_mini_turbo_frames if _mini_turbo_on else 0), _boost_frames) / MkConst.FPS


## [code]update_player_drift_duration[/code].
func _update_drift_duration() -> void:
	if is_drifting:
		drift_duration = mini(drift_duration + 1, MkConst.DRIFT_DURATION_CAP)
	else:
		drift_duration = maxi(drift_duration - 1, 0)


## [code]func_8002A79C[/code]: a drift that has ended at driftState 2 or more
## pays a mini turbo lasting [constant MkConst.MINI_TURBO_FRAMES].
func _pay_mini_turbo() -> void:
	if not _mini_turbo_on and not is_drifting and drift_state >= MkConst.MINI_TURBO_DRIFT_STATE:
		_mini_turbo_on = true
		_mini_turbo_frames = MkConst.MINI_TURBO_FRAMES
		drift_state = 0
		drift_counter = 0
		mini_turbo_fired.emit()
		if is_instance_valid(sfx_boost) and sfx_boost.stream != null:
			sfx_boost.play()
	elif _mini_turbo_on:
		_mini_turbo_frames -= 1
		if _mini_turbo_frames <= 0:
			_mini_turbo_frames = 0
			_mini_turbo_on = false
			drift_state = 0
			drift_counter = 0
	_refresh_boost_seconds()


# --- The pad: hop, steer, A and B (func_80037CFC) -------------------------------------------------------------------

func _read_pad() -> void:
	var kmh: float = MkConst.units_to_kmh(speed)
	# R on the ground hops, and over 20 km/h the hop is a drift (kart_hop, func_80036C5C)
	if _drift_pressed and not is_midair and not is_hopping and not is_drifting:
		_kart_hop()
	# the steering only runs on the ground, or through a hop still near it; in the air the yaw rate is kept
	if not is_midair or (is_hopping and _height - _ground_height <= 5.0 * MkConst.UNIT):
		_steer_frame()
	_braking = false
	# A and B together under 12 km/h is the spin in place
	if kmh <= MkConst.SPIN_IN_PLACE_KMH and _accelerate and _brake and not _spin_in_place:
		_spin_in_place = true
		current_speed += 100.0
	if _spin_in_place and not (_accelerate and _brake):
		_spin_in_place = false
	if not _reversing:
		if _accelerate:
			_accelerate_frame()
		else:
			_decelerate_frame(MkConst.COAST_DECELERATION)
		if _brake:
			_brake_frame()
		else:
			_brake_slide = 0.0
	# B with the stick back under 5 km/h backs up at a fixed currentSpeed; letting either go stops
	if _brake and _stick_back and kmh <= MkConst.REVERSE_MAX_KMH and not _reversing:
		_reversing = true
		current_speed = MkConst.REVERSE_SPEED_UNITS
		_force = MkConst.drive_force(current_speed)
		_brake_slide = 0.0
	if _reversing and (not _brake or not _stick_back):
		_reversing = false
		current_speed = 0.0
		_force = 0.0


## [code]kart_hop[/code]: the kart leaves the ground, and if it is going fast enough that is a drift.
func _kart_hop() -> void:
	_hop_jerk = MkConst.HOP_JERK
	_hop_acceleration = 0.0
	_hop_velocity = MkConst.HOP_VELOCITY
	is_hopping = true
	_vertical_divisor = MkConst.HOP_VERTICAL_DIVISOR
	_kart_gravity = MkConst.HOP_GRAVITY
	if MkConst.units_to_kmh(speed) > MkConst.DRIFT_MIN_KMH:
		drift_duration = 0
		is_drifting = true
		if is_instance_valid(sfx_drift) and sfx_drift.stream != null:
			sfx_drift.play()


## [code]cancel_drift_effect[/code]: the drift ends, and the stick is left on the drift's side.
func _cancel_drift() -> void:
	if not is_drifting:
		return
	if turn_angle > 0.0:
		_steer_position = _drift_stick(_steer_position, true)
	elif turn_angle < 0.0:
		_steer_position = _drift_stick(_steer_position, false)
	is_drifting = false
	_drift_outside = false
	if is_instance_valid(sfx_drift) and sfx_drift.playing:
		sfx_drift.stop()


## Letting go, for the demo's other scripts and the tests. [param pay] false
## ends the drift without its charge, which is what a spin out does; true ends
## it and pays whatever it has charged, at once.
func _end_drift(pay: bool) -> void:
	if not pay:
		drift_state = 0
		drift_counter = 0
	_cancel_drift()
	is_hopping = false
	if pay:
		_pay_mini_turbo()


## The stick remapped onto the drift's own side: -53..53 becomes 40..53 to the
## right, or -53..-40 to the left ([code]var_s1_2[/code] at [code]:4195[/code]).
static func _drift_stick(stick: float, to_right: bool) -> float:
	var mapped: float = (stick * 13.0 + 13.0 * MkConst.STICK_MAX) / (2.0 * MkConst.STICK_MAX)
	return mapped + MkConst.DRIFT_STICK_MIN if to_right else mapped - MkConst.STICK_MAX


## [code]func_80033AE0[/code]: the drift's life, the turn flags, the steering
## ladder, and the yaw rate for the frame.
func _steer_frame() -> void:
	var kmh: float = MkConst.units_to_kmh(speed)
	var turn_degrees: float = rad_to_deg(turn_angle)
	if (not is_hopping and (absf(turn_degrees) <= MkConst.DRIFT_MIN_DEGREES or not _drift_held)) or kmh <= MkConst.DRIFT_MIN_KMH:
		_cancel_drift()
	_turn_left = turn_degrees < -MkConst.TURN_FLAG_DEGREES
	_turn_right = turn_degrees > MkConst.TURN_FLAG_DEGREES
	if is_hopping or is_drifting:
		_turn_left = false
		_turn_right = false

	# the stick as the game reads it, mirrored while backing up
	_stick = -_steer * MkConst.STICK_MAX
	if _reversing or _moving_backwards:
		_stick = -_stick
	var desired: float = _stick
	_steer_delta = _steer_position - desired
	# a full flick at 150cc speed spins the kart out (DRIVING_SPINOUT_TRIGGER)
	if absf(_steer_delta) >= MkConst.SPINOUT_STEER_DELTA and not is_drifting and engine_class == &"150cc" \
			and not is_midair and kmh >= MkConst.SPINOUT_MIN_KMH and drift_duration == 0:
		spin_out()
		return

	var resistance_large: float
	var resistance_small: float
	if _spin_in_place:
		resistance_large = MkConst.STEER_RESISTANCE_SPIN
		resistance_small = MkConst.STEER_RESISTANCE_SPIN
	elif kmh >= MkConst.STEER_RESISTANCE_SLOW_KMH:
		var drifting: float = MkConst.STEER_RESISTANCE_DRIFT if is_drifting and not is_hopping else 0.0
		var same_way: bool = (_turn_right and _steer_delta <= MkConst.STEER_RESISTANCE_TURNING_CHANGE and _steer_delta >= 0.0) \
			or (_turn_left and _steer_delta >= -MkConst.STEER_RESISTANCE_TURNING_CHANGE and _steer_delta <= 0.0)
		if _turn_right or _turn_left:
			if same_way:
				resistance_large = drifting + MkConst.STEER_RESISTANCE_TURNING
				resistance_small = drifting + MkConst.STEER_RESISTANCE_TURNING
			else:
				resistance_large = drifting + MkConst.STEER_RESISTANCE_RETURN_LARGE
				resistance_small = drifting + MkConst.STEER_RESISTANCE_RETURN_SMALL
		else:
			resistance_large = drifting + MkConst.STEER_RESISTANCE_STRAIGHT_LARGE
			resistance_small = drifting + MkConst.STEER_RESISTANCE_STRAIGHT_SMALL
	else:
		resistance_large = MkConst.STEER_RESISTANCE_SLOW
		resistance_small = MkConst.STEER_RESISTANCE_SLOW
	_run_steering_ladder(desired, resistance_large, resistance_small)

	# the turn factor: the stick over a divisor that grows with currentSpeed, times the per km/h table
	var factor: float
	if is_drifting:
		factor = _steer_position / MkConst.STEER_DIVISOR_DRIFT
	elif kmh <= MkConst.STEER_SLOW_KMH:
		factor = _steer_position / MkConst.STEER_DIVISOR_SLOW
	else:
		factor = _steer_position / (MkConst.STEER_DIVISOR_BASE + current_speed / MkConst.STEER_DIVISOR_SPEED)
	factor = absf(factor)
	var table: PackedFloat32Array = MkConst.TURN_FACTOR_BY_KMH
	if _spin_in_place:
		factor *= table[clampi(int(kmh) + 10, 0, table.size() - 1)] * MkConst.TURN_SCALE
	elif is_drifting:
		factor *= table[clampi(int(kmh), 0, table.size() - 1)]
	else:
		factor *= table[clampi(int(kmh), 0, table.size() - 1)] * MkConst.TURN_SCALE

	_drift_outside = false
	var rate_units: float
	if not is_hopping and not is_drifting:
		if _spin_in_place:
			rate_units = _steer_position * MkConst.SPIN_STEER_SCALE * factor
		elif not _braking:
			var handling: float = float(MkConst.CLASS_HANDLING.get(_kart_class, 1.25))
			if absf(_steer_position) >= MkConst.HARD_STEER:
				handling += MkConst.HARD_STEER_BONUS
			rate_units = _steer_position * factor * handling
		else:
			var add: float = 0.0
			if kmh >= MkConst.BRAKE_STEER_FAST_KMH:
				add = MkConst.BRAKE_STEER_ADD_FAST
			elif kmh >= MkConst.BRAKE_STEER_SLOW_KMH:
				add = MkConst.BRAKE_STEER_ADD_MID
			rate_units = _steer_position * (factor + add)
		drift_counter = 0
		if drift_state < MkConst.MINI_TURBO_DRIFT_STATE:
			drift_state = 0
	elif not is_midair and not is_hopping:
		# drifting: the stick only picks a point on the drift's own side, and against it is an outside drift
		var to_right: bool = turn_angle > 0.0
		var mapped: float = _drift_stick(_steer_position, to_right)
		if (to_right and _steer_position <= -MkConst.DRIFT_OUTSIDE_STICK) or (not to_right and _steer_position >= MkConst.DRIFT_OUTSIDE_STICK):
			_drift_outside = true
		_update_drift_state_counter()
		var add: float = MkConst.DRIFT_STEER_ADD_SLOW
		if kmh >= MkConst.BRAKE_STEER_FAST_KMH:
			add = MkConst.DRIFT_STEER_ADD_FAST
		elif kmh >= MkConst.BRAKE_STEER_SLOW_KMH:
			add = MkConst.DRIFT_STEER_ADD_MID
		rate_units = mapped * (factor + add)
		rate_units *= MkConst.DRIFT_OUTSIDE_STEER_SCALE if _drift_outside else MkConst.DRIFT_STEER_SCALE
	else:
		# through the hop
		var held: float = _steer_position if _stick != 0.0 else 0.0
		rate_units = held * (factor + (MkConst.HOP_STEER_ADD_STILL if kmh <= MkConst.HOP_STEER_STILL_KMH else MkConst.HOP_STEER_ADD))
	yaw_rate = MkConst.angle_units_to_radians(rate_units)


## The steering ladder, the fifty nine [code]update_steering_large[/code] and
## thirty one [code]update_steering_small[/code] calls, in stick units.
func _run_steering_ladder(desired: float, resistance_large: float, resistance_small: float) -> void:
	var position: float = _steer_position
	var delta: float = _steer_delta
	for entry: Array in MkConst.STEER_LADDER_LARGE:
		var threshold: float = float(entry[0])
		if delta >= threshold or -threshold >= delta:
			position = _ladder_step(position, desired, float(entry[1]), resistance_large)
			_sideways_kick = -float(entry[2])
	for entry: Array in MkConst.STEER_LADDER_SMALL:
		var threshold: float = float(entry[0])
		if delta >= threshold or -threshold >= delta:
			position = _ladder_step(position, desired, float(entry[1]), resistance_small)
			_sideways_kick = minf(0.0, _sideways_kick + float(entry[2]))
	_steer_position = clampf(position, -MkConst.STICK_MAX, MkConst.STICK_MAX)


## One rung: the increment decays, is floored at the rung's own figure over the
## resistance, and moves the position toward the stick by that much.
func _ladder_step(position: float, desired: float, numerator: float, resistance: float) -> float:
	var before: float = _steer_increment
	_steer_increment -= MkConst.STEER_INCREMENT_DECAY
	if _steer_increment < 0.0:
		_steer_increment = before
	var floor_value: float = numerator * MkConst.STEER_INCREMENT_SCALE / maxf(resistance, 1.0)
	if floor_value >= _steer_increment:
		_steer_increment = floor_value
	return position - _steer_increment if desired < position else position + _steer_increment


## [code]update_drift_state_counter[/code]: the charge is the wiggle. With the
## kart sliding one way, the counter climbs only while the stick is pushed the
## other way; bringing it back after 18 or more frames bumps the charge.
func _update_drift_state_counter() -> void:
	var against: bool = (turn_angle > 0.0 and _steer_position <= -MkConst.DRIFT_COUNTER_STICK) \
		or (turn_angle <= 0.0 and _steer_position >= MkConst.DRIFT_COUNTER_STICK)
	if against:
		if drift_counter <= MkConst.DRIFT_COUNTER_CAP:
			drift_counter += 1
		return
	var was: int = drift_state
	if drift_counter >= MkConst.DRIFT_STATE_FRAMES and drift_counter < MkConst.DRIFT_COUNTER_CAP:
		drift_state = mini(drift_state + 1, MkConst.DRIFT_STATE_CAP)
	if drift_counter >= MkConst.DRIFT_COUNTER_HOLD and drift_counter < MkConst.DRIFT_COUNTER_CAP:
		drift_counter = MkConst.DRIFT_COUNTER_HOLD
	else:
		drift_counter = 0
		drift_state = 0
	if drift_state != was:
		mini_turbo_charged.emit(drift_state)


## [code]player_accelerate_alternative[/code] for a person,
## [code]player_accelerate[/code] for a computer: one band of the table a frame.
func _accelerate_frame() -> void:
	var curve: Array = MkRoster.curve_for(driver)
	if curve.is_empty():
		return
	var band: int = clampi(int(current_speed / maxf(_top_speed_units, 1.0) * float(MkRoster.CURVE_BANDS)), 0, MkRoster.CURVE_BANDS - 1)
	var add: float = float(curve[band])
	if is_cpu:
		add *= MkConst.CPU_ACCELERATION_SCALE_LOW if band < MkConst.CPU_ACCELERATION_SCALE_SPLIT else MkConst.CPU_ACCELERATION_SCALE_HIGH
	else:
		add += MkConst.SLOPE_ACCELERATION * _slope_degrees()
	current_speed = clampf(current_speed + add, 0.0, _top_speed_units)
	if not is_midair:
		_force = MkConst.drive_force(current_speed)


## [code]player_decelerate_alternative[/code].
func _decelerate_frame(amount: float) -> void:
	current_speed = clampf(current_speed - amount, 0.0, _top_speed_units)
	if speed < 0.2:
		_force = 0.0
	if not is_midair:
		_force = MkConst.drive_force(current_speed)


## [code]func_800323E4[/code]: B held. The brake slide counts up while the kart
## is actually slowing, and the brake bites harder once it has.
func _brake_frame() -> void:
	_braking = true
	var surface_loss: float = 2.0 * MkConst.surface_entry(MkConst.SURFACE_BRAKE_LOSS, surface)
	if previous_speed - speed <= 0.0:
		_brake_slide = 0.0
	else:
		_brake_slide = minf(_brake_slide + MkConst.BRAKE_SLIDE_RATE, MkConst.BRAKE_SLIDE_CAP)
	if MkConst.units_to_kmh(speed) <= MkConst.BRAKE_SLOW_KMH:
		_decelerate_frame((1.0 - surface_loss) * MkConst.BRAKE_DECELERATION_SLOW)
	if _brake_slide >= MkConst.BRAKE_SLIDE_CAP:
		_decelerate_frame((1.0 - surface_loss) * MkConst.BRAKE_DECELERATION_SETTLED)
	else:
		_decelerate_frame((1.0 - surface_loss) * MkConst.BRAKE_DECELERATION)


# --- The force (func_80030150) ---------------------------------------------------------------------------------------

## The gradient under the kart in degrees, nose down positive, as the game's
## [code]slopeAccel[/code] reads it; the sprite kart picks its pitch pose from this.
func pitch_degrees() -> float:
	return _slope_degrees()


## The gradient under the kart in degrees, negative uphill, as [code]slopeAccel[/code] reads.
func _slope_degrees() -> float:
	if not _has_ground:
		return 0.0
	return -rad_to_deg(asin(clampf(_ground_normal.dot(forward()), -1.0, 1.0)))


## [code]func_8002AB70[/code]: the kart's gravity and the vertical divisor ease
## back after a hop, lighten downhill, and stay light in the air.
func _relax_gravity() -> void:
	var kmh: float = MkConst.units_to_kmh(speed)
	var slope: float = _slope_degrees()
	if not is_midair and _force > 0.0:
		if slope < -1.0 and slope >= -20.0 and kmh >= MkConst.BRAKE_SLOW_KMH:
			_kart_gravity = lerpf(_kart_gravity, MkConst.DOWNHILL_GRAVITY, MkConst.DOWNHILL_GRAVITY_RELAX)
			_vertical_divisor = lerpf(_vertical_divisor, MkConst.DOWNHILL_VERTICAL_DIVISOR, MkConst.DOWNHILL_DIVISOR_RELAX)
		else:
			_kart_gravity = lerpf(_kart_gravity, MkConst.KART_GRAVITY, MkConst.GRAVITY_RELAX_GROUND)
			_vertical_divisor = lerpf(_vertical_divisor, 1.0, MkConst.VERTICAL_DIVISOR_RELAX)
	else:
		if _height - _ground_height >= 50.0 * MkConst.UNIT:
			_vertical_divisor = 2.0
		_kart_gravity = lerpf(_kart_gravity, MkConst.KART_GRAVITY, MkConst.GRAVITY_RELAX_AIR)
		_vertical_divisor = lerpf(_vertical_divisor, 1.0, MkConst.VERTICAL_DIVISOR_RELAX)


## The drive force for the frame: what the throttle built, plus the mini turbo,
## the mushroom and the catch-up, less the loss fraction.
func _drive_force() -> float:
	var kmh: float = MkConst.units_to_kmh(speed)
	var loss: float = 0.0
	var slope: float = _slope_degrees()
	if kmh >= MkConst.LOSS_MIN_KMH:
		var rear_table: Array = MkConst.SURFACE_FORCE_LOSS_REAR.get(_kart_class, MkConst.SURFACE_FORCE_LOSS_REAR[&"standard"])
		var front_table: Array = MkConst.SURFACE_FORCE_LOSS_FRONT.get(_kart_class, MkConst.SURFACE_FORCE_LOSS_FRONT[&"standard"])
		# three tyres read the rear table and one the front, as the game's own loop does
		loss += 3.0 * MkConst.surface_entry(rear_table, surface) + MkConst.surface_entry(front_table, surface)
		if not is_midair:
			if kmh >= MkConst.SLOW_PENALTY_KMH:
				loss -= slope * (MkConst.SLOPE_FORCE_STEEP if absf(slope) > MkConst.SLOPE_SPLIT_DEGREES else MkConst.SLOPE_FORCE_SHALLOW)
			else:
				loss += MkConst.SLOW_PENALTY
			var degrees: float = absf(rad_to_deg(turn_angle))
			if is_drifting or drift_duration > 0:
				loss += degrees * MkConst.DRIFT_TURN_FORCE
			else:
				loss += degrees * (MkConst.TURN_FORCE_BASE + float(MkConst.CLASS_TURN_LOSS.get(_kart_class, 0.0)))
			if _drift_outside and drift_counter < MkConst.DRIFT_OUTSIDE_FRAMES:
				loss += degrees * MkConst.DRIFT_OUTSIDE_FORCE
		if is_midair:
			_air_loss = lerpf(_air_loss, _force * MkConst.AIR_FORCE_LOSS, MkConst.AIR_FORCE_LOSS_LERP)
		else:
			_air_loss = lerpf(_air_loss, 0.0, MkConst.AIR_FORCE_LOSS_RECOVER)
	else:
		_air_loss = 0.0
		_mini_turbo_force = 0.0
		if slope < 0.0:
			loss += MkConst.STALL_UPHILL_GAIN
	if is_cpu:
		_cpu_fast_force = lerpf(_cpu_fast_force, MkConst.CPU_CATCHUP_TARGET if cpu_fast else 0.0, MkConst.CPU_CATCHUP_RATE if cpu_fast else MkConst.CPU_CATCHUP_DECAY)
	else:
		if _mini_turbo_on and not is_drifting:
			_mini_turbo_force = lerpf(_mini_turbo_force, MkConst.MINI_TURBO_TARGET, MkConst.MINI_TURBO_RATE)
		else:
			_mini_turbo_force = lerpf(_mini_turbo_force, 0.0, MkConst.MINI_TURBO_DECAY)
		_cpu_fast_force = 0.0
	if _boost_frames > 0.0:
		_mushroom_force = lerpf(_mushroom_force, MkConst.MUSHROOM_FORCE, MkConst.MUSHROOM_RATE)
	else:
		_mushroom_force = lerpf(_mushroom_force, 0.0, MkConst.MUSHROOM_DECAY)
		if _mushroom_force <= 1.0:
			_mushroom_force = 0.0
	_loss = lerpf(_loss, loss, MkConst.LOSS_RATE + float(MkConst.CLASS_TURN_LOSS.get(_kart_class, 0.0)))
	var total: float = maxf(_force + _mini_turbo_force + _mushroom_force + _cpu_fast_force - _air_loss, 0.0)
	if _boost_frames > 0.0:
		return _mushroom_force + _force # a mushroom goes past the loss
	return (1.0 - _loss) * total


# --- The lateral term and the yaw (func_80037BB4) ---------------------------------------------------------------------

## Turns the facing by the frame's yaw rate and returns the lateral push, in
## force units in the world: the kart's own grip less what the surface takes,
## the flick's kick, and a drag along the nose. The push is across the kart
## toward the outside of the turn once the speed terms outweigh the base grip
## of 28, which at racing speed they always do, and in a drift by a lot: it is
## what keeps the tail out and the slide alive. At a crawl it reverses and
## pulls the kart into the turn, which is the tight turning circle of a slow
## kart. (The decomp applies it along the kart's X; with the game's nose on +Z
## that is the left, and the right-hand variant of the function is the one
## used for a right turn, so a positive figure is the outside.)
func _turn_and_lateral() -> Vector3:
	if yaw_rate == 0.0:
		return Vector3.ZERO
	if not _drift_outside or drift_counter >= MkConst.DRIFT_COUNTER_CAP:
		yaw -= yaw_rate # a positive rate is a right turn, which is clockwise seen from above
	if _spin_in_place:
		return Vector3.ZERO
	var kmh: float = MkConst.units_to_kmh(speed)
	var grip_loss: float = 2.0 * MkConst.surface_entry(MkConst.SURFACE_GRIP_LOSS_REAR, surface) \
		+ 2.0 * MkConst.surface_entry(MkConst.SURFACE_GRIP_LOSS_FRONT, surface)
	var grip: float = MkConst.LATERAL_BASE - MkConst.LATERAL_BASE * grip_loss
	var across: float
	var along: float
	if is_drifting and not is_hopping:
		across = grip - kmh * MkConst.LATERAL_DRIFT_KMH_SCALE - _brake_slide * MkConst.LATERAL_BRAKE_SLIDE_SCALE
		along = MkConst.LATERAL_DRAG * MkConst.LATERAL_DRIFT_DRAG_SCALE
	else:
		var stick: float = absf(_steer_position)
		if stick <= MkConst.LATERAL_STICK_SOFT:
			across = grip - kmh / MkConst.LATERAL_KMH_DIVISOR - current_speed * MkConst.LATERAL_SPEED_SCALE
		else:
			across = grip - kmh / MkConst.LATERAL_KMH_DIVISOR - (stick * MkConst.LATERAL_STICK_SCALE_HARD + current_speed * MkConst.LATERAL_SPEED_SCALE_HARD)
		across -= _brake_slide * MkConst.LATERAL_BRAKE_SLIDE_SCALE
		along = MkConst.LATERAL_DRAG
	var outward: float = -(_sideways_kick + across) * speed
	return right() * -signf(yaw_rate) * outward + forward() * speed * along


# --- The integrator (func_8002D268) ------------------------------------------------------------------------------------

func _integrate(force: float, lateral: Vector3) -> void:
	var up: Vector3 = Vector3.UP
	var facing: Vector3 = forward() if not _reversing else -forward()
	var along_ground: Vector3 = facing.slide(_ground_normal) if not is_midair else facing
	if along_ground.length_squared() > 0.0001:
		along_ground = along_ground.normalized()
	var push: Vector3 = along_ground * force
	var gravity: Vector3
	if is_midair:
		gravity = -up * _kart_gravity
	elif _spin_in_place:
		gravity = -up * _kart_gravity / 4.0
	else:
		var scale: float = MkConst.GROUND_GRAVITY_SCALE
		if surface != MkConst.SURFACE_SOLID:
			var kmh: float = MkConst.units_to_kmh(speed)
			scale = MkConst.GROUND_GRAVITY_BY_SPEED[clampi(int(kmh / 10.0), 0, MkConst.GROUND_GRAVITY_BY_SPEED.size() - 1)]
		gravity = Vector3(-_ground_normal.x * _kart_gravity * scale, -_ground_normal.y * _kart_gravity, -_ground_normal.z * _kart_gravity * scale)
	# braking with no drive, the kart's backward creep is pushed back (sp178)
	if _braking and _force <= 0.0 and not _spin_in_place:
		var backwards: float = -(Vector3(global_position.x, 0.0, global_position.z) - Vector3(_old_position.x, 0.0, _old_position.z)).dot(forward()) / MkConst.UNIT
		if backwards > MkConst.MOVE_BACKWARDS_UNITS:
			push += forward() * backwards * MkConst.BRAKE_REVERSE_PUSH
	var drag: float = MkConst.DRAG_FACTOR * MkConst.KART_FRICTION
	var numerator: Vector3 = push + gravity + lateral - velocity_units * drag
	var divisor: float
	var outside_held: float = MkConst.HELD_DRIFT_DIVISOR if _drift_outside and drift_counter >= MkConst.DRIFT_COUNTER_CAP else 0.0
	if absf(_steer_position) >= MkConst.BRAKE_HARD_STEER:
		divisor = _brake_slide * MkConst.BRAKE_SLIDE_DIVISOR + 1.0 + outside_held
	else:
		divisor = outside_held + 1.0
	velocity_units.x += numerator.x / MkConst.INTEGRATOR_DIVISOR / divisor
	velocity_units.z += numerator.z / MkConst.INTEGRATOR_DIVISOR / divisor
	velocity_units.y += numerator.y / MkConst.INTEGRATOR_DIVISOR / _vertical_divisor
	if _touching_wall and _wall_normal != Vector3.ZERO:
		var into: float = velocity_units.dot(_wall_normal)
		if into < 0.0:
			velocity_units -= _wall_normal * into
		current_speed = maxf(current_speed - MkConst.WALL_DECELERATION, 0.0)
		_force = MkConst.drive_force(current_speed)
	if _drift_outside and drift_counter >= MkConst.DRIFT_COUNTER_CAP:
		_decelerate_frame(MkConst.HELD_DRIFT_DECELERATION)


## The hop and the ground: the height moves by the vertical velocity and the
## hop, the ground catches the kart, and leaving it is the air.
func _move_vertical() -> void:
	_tick_hop()
	var rise: float = velocity_units.y + _hop_velocity - (0.0 if is_midair else MkConst.GROUND_PULL)
	_height += rise * MkConst.UNIT
	var over: float = _height - _ground_height
	if _has_ground and over <= 0.0:
		_height = _ground_height
		velocity_units.y = 0.0
		if is_midair:
			_land()
		is_midair = false
		is_hopping = false
	elif _has_ground and not is_midair and over <= GROUND_SNAP and _hop_velocity <= 0.0:
		_height = _ground_height
		velocity_units.y = 0.0
	else:
		is_midair = true
		_air_frames += 1


## [code]func_8002AAC0[/code]: the hop's jerk, acceleration and velocity.
func _tick_hop() -> void:
	if not is_hopping and _hop_velocity <= 0.0:
		return
	_hop_acceleration = clampf(_hop_acceleration - _hop_jerk, -MkConst.HOP_ACCELERATION_CAP, MkConst.HOP_ACCELERATION_CAP)
	_hop_velocity = minf(_hop_velocity + _hop_acceleration, MkConst.HOP_VELOCITY_CAP)
	if _hop_velocity <= 0.0:
		_hop_velocity = 0.0
		_hop_acceleration = 0.0
		_hop_jerk = 0.0


func _land() -> void:
	_air_frames = 0
	_hop_velocity = 0.0
	_hop_acceleration = 0.0
	_hop_jerk = 0.0


## [code]func_8002AE38[/code]: the turn angle. Near straight, or crawling, it
## follows the yaw rate; otherwise it is the slide itself, measured between
## where the kart went and where it faces.
func _update_turn_angle() -> void:
	var kmh: float = MkConst.units_to_kmh(speed)
	var travel: Vector3 = Vector3(velocity_units.x, 0.0, velocity_units.z)
	var cap: float = deg_to_rad(MkConst.TURN_ANGLE_CAP_DEGREES)
	if not is_drifting and (kmh <= MkConst.TURN_ANGLE_STILL_KMH or absf(_steer_position) < MkConst.TURN_ANGLE_STILL_STICK):
		if _spin_in_place:
			turn_angle -= turn_angle * MkConst.SPIN_DRAG
		else:
			turn_angle = lerpf(turn_angle, yaw_rate * MkConst.TURN_ANGLE_FOLLOW_SCALE, MkConst.TURN_ANGLE_FOLLOW_LERP)
		return
	var measured: float = 0.0
	if travel.length_squared() > 0.000001:
		measured = -travel.normalized().signed_angle_to(forward(), Vector3.UP) # positive when the nose is right of the travel
	var fast_and_wide: bool = current_speed >= MkConst.TURN_ANGLE_SINGLE_SPEED and absf(rad_to_deg(turn_angle)) >= MkConst.TURN_ANGLE_SINGLE_DEGREES
	var target: float = measured if fast_and_wide else measured * MkConst.TURN_ANGLE_SLIP_SCALE
	var against: bool = (_steer_position > 0.0 and target < 0.0) or (_steer_position < 0.0 and target > 0.0)
	if not is_drifting and against:
		target = yaw_rate * MkConst.TURN_ANGLE_COUNTER_SCALE
	else:
		target = clampf(target, -cap, cap)
	turn_angle = lerpf(turn_angle, target, MkConst.TURN_ANGLE_SLIP_LERP)


func _measure_speed() -> void:
	previous_speed = speed
	speed = Vector3(velocity_units.x, 0.0, velocity_units.z).length()
	var moved: Vector3 = Vector3(global_position.x, 0.0, global_position.z) - Vector3(_old_position.x, 0.0, _old_position.z)
	_moving_backwards = -moved.dot(forward()) / MkConst.UNIT > MkConst.MOVE_BACKWARDS_UNITS
	if _force <= 0.0 and speed <= 0.08 and not is_midair:
		velocity_units.x = 0.0
		velocity_units.z = 0.0
		speed = 0.0


# --- The body ------------------------------------------------------------------------------------------------------

## Hands the frame's result to the body: the velocity in metres a second, the
## height the model keeps, and the pose from the yaw and the smoothed ground.
func _apply_to_body() -> void:
	var metres_per_frame: float = MkConst.UNIT * MkConst.FPS
	var vertical: float = (_height - global_position.y) * MkConst.FPS if not is_midair else (velocity_units.y + _hop_velocity) * metres_per_frame
	linear_velocity = Vector3(velocity_units.x * metres_per_frame, vertical, velocity_units.z * metres_per_frame)
	angular_velocity = Vector3.ZERO
	var target_up: Vector3 = _ground_normal if (_has_ground and not is_midair) else Vector3.UP
	_display_normal = _display_normal.lerp(target_up, 0.25).normalized()
	var facing: Vector3 = forward()
	var side: Vector3 = _display_normal.cross(facing)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	var nose: Vector3 = side.cross(_display_normal).normalized()
	global_transform.basis = Basis(side, _display_normal, nose)
	steering = turn_angle # for anything that reads the chassis's own steering as "how hard the kart is cornering"


## The engine note follows the speed, and jumps while a boost is lit.
func _update_engine_sound() -> void:
	if not is_instance_valid(sfx_engine) or sfx_engine.stream == null:
		return
	if not sfx_engine.playing:
		sfx_engine.play()
	var fraction: float = clampf(absf(forward_speed()) / maxf(top_speed(), 1.0), 0.0, 1.0)
	sfx_engine.pitch_scale = lerpf(0.8, 1.7, fraction) * (1.3 if boost_seconds > 0.0 else 1.0)


## The driver's topSpeed figure in the game's own units, which is what the
## acceleration curve fills toward.
func _top_speed_units_for_driver() -> float:
	var row: Dictionary = MkConst.TOP_SPEED_UNITS.get(engine_class, {})
	if row.is_empty():
		return 0.0
	return float(row["light" if MkRoster.is_light(driver) else "standard"])


# --- The rideable contract -------------------------------------------------------------------------------------------

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
		Input.get_axis("move_right", "move_left"),
		Input.is_action_pressed(&"move_down"))


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
	controls["joypad_button_9"] = "Hop / Drift" ## The left bumper, where "ability" sits.
	controls["joypad_button_10"] = "Item" ## The right bumper, where "throw" sits.
	return controls
