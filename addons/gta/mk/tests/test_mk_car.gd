extends GutTest

## Purpose: the kart moves the way Mario Kart 64's does. A person's throttle adds
## the table unscaled and a computer's three times over; the force settles the
## velocity at the game's top speed; the velocity lags the facing by the
## integrator's third of a second, which is the slide; the facing turns at the
## game's rate for the stick and the speed; a hop over 20 km/h is a drift; the
## mini turbo is charged by wiggling the stick against the slide and is worth
## fourteen percent more force; grass takes thirty percent off; the camera's own
## yaw chases the kart's by a capped step.
##
## The direction tests are kept from the first port, because both directions
## were wrong once and neither showed up as an error.

const KART_SCENE: String = "res://addons/gta/mk/scenes/mk_kart.tscn"
const FRAME: float = 1.0 / 30.0

var _kart: MkCar
var _floor: StaticBody3D


func before_each() -> void:
	_floor = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	_floor.add_child(shape)
	add_child_autofree(_floor)
	_kart = (load(KART_SCENE) as PackedScene).instantiate() as MkCar
	_kart.driver = &"rook"
	_kart.engine_class = &"150cc"
	add_child_autofree(_kart)
	await wait_physics_frames(2)
	_kart._probe_ground()


## Puts the kart at [param units_per_frame] along its nose, on the ground, as the game would read it.
func _rolling(units_per_frame: float) -> void:
	_kart.velocity_units = _kart.forward() * units_per_frame
	_kart.speed = units_per_frame
	_kart.previous_speed = units_per_frame


func test_the_kart_is_built_nose_along_positive_z() -> void:
	_kart.yaw = 0.0
	assert_almost_eq(_kart.forward().dot(Vector3.BACK), 1.0, 0.0001, "forward() is +Z at a yaw of zero, the way the scene is built")
	assert_almost_eq(_kart.right().dot(Vector3.LEFT), 1.0, 0.0001, "and the right hand side is -X")


func test_the_nose_of_the_model_points_the_way_the_kart_drives() -> void:
	var nose: Node3D = _kart.get_node_or_null(^"Nose") as Node3D
	assert_not_null(nose, "the kart has a nose to check")
	assert_gt(nose.position.z, 0.0, "the nose is on the +Z side")
	var seat: Node3D = _kart.get_node_or_null(^"Seat") as Node3D
	assert_lt(seat.position.z, nose.position.z, "and the driver sits behind it")


func test_the_body_is_the_models_and_not_the_physics_engines() -> void:
	assert_eq(_kart.wheels.size(), 0, "the game's kart has no wheels to push")
	assert_almost_eq(_kart.gravity_scale, 0.0, 0.0001, "no engine gravity: the kart's own 2600 is in the integrator")
	assert_true(_kart.lock_rotation, "and the pose is the facing, never a tumble")


func test_top_speed_comes_from_the_roster_and_the_engine_class() -> void:
	assert_almost_eq(_kart.top_speed(), MkRoster.top_speed(&"rook", &"150cc"), 0.0001, "the kart's ceiling is its driver's")
	assert_almost_eq(_kart.ceiling_speed_units(), 320.0, 0.0001, "a standard kart at 150cc runs to a topSpeed of 320")


func test_a_persons_throttle_adds_the_table_and_a_computers_three_times_over() -> void:
	_kart.set_drive_input(true, false, false, 0.0)
	for i: int in 5:
		_kart._accelerate_frame()
	assert_almost_eq(_kart.current_speed, 10.0, 0.01, "player_accelerate_alternative adds 2.0 a frame through the first band on flat ground")
	_kart.current_speed = 0.0
	_kart.is_cpu = true
	for i: int in 5:
		_kart._accelerate_frame()
	assert_almost_eq(_kart.current_speed, 32.0, 0.01, "player_accelerate, the CPU path, adds 3.2 times that")
	_kart.is_cpu = false
	var frames_to_top: int = 0
	_kart.current_speed = 0.0
	while _kart.current_speed < 320.0 and frames_to_top < 600:
		_kart._accelerate_frame()
		frames_to_top += 1
	assert_between(frames_to_top, 315, 330, "0 to 320 through the standard table takes 323 frames, nearly eleven seconds, most of it in the last bands")
	for i: int in 60:
		_kart._accelerate_frame()
	assert_almost_eq(_kart.current_speed, 320.0, 0.001, "and never past the ceiling")


func test_the_force_settles_the_kart_at_the_games_top_speed() -> void:
	_kart.set_drive_input(true, false, false, 0.0)
	for i: int in 450:
		_kart.step_frame()
	var kmh: float = MkConst.units_to_kmh(_kart.speed)
	assert_between(kmh, 68.0, 72.0, "fifteen seconds of throttle on asphalt settles where 4096 balances 696 v: 70.6 km/h")
	assert_almost_eq(_kart.forward_speed(), MkConst.units_to_ms(_kart.speed), 0.01, "all of it along the nose")


func test_the_velocity_lags_the_facing_by_the_integrators_third_of_a_second() -> void:
	_kart.current_speed = 320.0
	_kart._force = MkConst.drive_force(320.0)
	_rolling(MkConst.top_speed_units_per_frame(320.0))
	_kart.yaw = PI * 0.5 # the nose snaps to +X with the velocity still along +Z
	_kart.set_drive_input(true, false, false, 0.0)
	for i: int in 9:
		_kart.step_frame()
	var travel: Vector3 = Vector3(_kart.velocity_units.x, 0.0, _kart.velocity_units.z).normalized()
	var left_to_turn: float = rad_to_deg(travel.angle_to(Vector3.RIGHT))
	assert_between(left_to_turn, 20.0, 45.0, "after 8.6 frames the velocity has come about two thirds of the way round to the nose")
	for i: int in 60:
		_kart.step_frame()
	travel = Vector3(_kart.velocity_units.x, 0.0, _kart.velocity_units.z).normalized()
	assert_lt(rad_to_deg(travel.angle_to(Vector3.RIGHT)), 3.0, "two seconds on it has settled behind the nose")


func test_full_stick_turns_the_facing_at_the_games_rate() -> void:
	_kart.current_speed = 320.0
	_kart._force = MkConst.drive_force(320.0)
	_rolling(MkConst.top_speed_units_per_frame(320.0))
	_kart.set_drive_input(true, false, false, 1.0)
	for i: int in 15:
		_kart.step_frame() # the ladder takes about ten frames to bring steerPosition to the stick
	var start: float = _kart.yaw
	for i: int in 30:
		_kart.step_frame()
	var turned: float = rad_to_deg(angle_difference(start, _kart.yaw))
	assert_between(turned, 35.0, 55.0, "at top speed a full stick turns the nose about 45 degrees a second: 53 / (8 + 320 / 50) x 0.7 x 1.5 x 1.4 a frame, less as the turn costs speed")
	assert_gt(turned, 0.0, "to the left, which is the project's positive steer")
	assert_gt(absf(rad_to_deg(_kart.turn_angle)), 6.0, "and the slide between the nose and the travel is the turn angle")
	_kart.sync_from_transform()
	_kart.current_speed = 60.0
	_kart._force = MkConst.drive_force(60.0)
	_rolling(MkConst.top_speed_units_per_frame(60.0)) # about 2.5 km/h: the slow divisor and the slow table
	_kart.set_drive_input(true, false, false, 1.0)
	start = _kart.yaw
	for i: int in 30:
		_kart.step_frame()
	var slow_turn: float = rad_to_deg(angle_difference(start, _kart.yaw))
	assert_lt(slow_turn, turned, "and slower still at a crawl, where the stick is divided by 12 and the table reads 0.5")


func test_a_flick_of_the_stick_leaves_the_games_lateral_kick() -> void:
	_rolling(MkConst.top_speed_units_per_frame(320.0))
	_kart._steer_position = 0.0
	_kart._steer_delta = -53.0
	_kart._run_steering_ladder(53.0, 3.0, 6.0)
	assert_almost_eq(_kart._sideways_kick, -59.85, 0.01, "the decomp's own comment: a stick change past 30 always leaves unk_090 at -59.85")
	assert_between(_kart._steer_position, 25.0, 40.0, "and the position comes about thirty of the fifty three in that frame, the rest over the next few")
	for i: int in 6:
		_kart._steer_delta = -10.0
		_kart._run_steering_ladder(10.0, 3.0, 6.0)
	assert_almost_eq(_kart._sideways_kick, 0.0, 0.0001, "small changes bring the kick back to nothing")


func test_the_hop_over_twenty_kmh_is_a_drift() -> void:
	_rolling(MkConst.top_speed_units_per_frame(320.0))
	_kart.current_speed = 320.0
	_kart.set_drive_input(true, false, true, 1.0)
	_kart.step_frame()
	assert_true(_kart.is_hopping, "R hops")
	assert_true(_kart.is_drifting, "and over 20 km/h the hop is a drift at once (func_80036C5C)")
	var ground: float = _kart._ground_height
	var top: float = 0.0
	for i: int in 9:
		_kart.step_frame()
		top = maxf(top, _kart._height - ground)
	assert_between(top, 0.25, 0.5, "kartHopVelocity 0.93 a frame with the jerk 0.03, less the hop's own gravity, rises about a third of a metre")
	_kart.sync_from_transform()
	_rolling(MkConst.top_speed_units_per_frame(100.0)) # 7 km/h
	_kart.current_speed = 100.0
	_kart.set_drive_input(true, false, false, 1.0) # let go of R, so the next press is a press
	_kart.set_drive_input(true, false, true, 1.0)
	_kart.step_frame()
	assert_true(_kart.is_hopping, "a slow kart still hops")
	assert_false(_kart.is_drifting, "but it is no drift")


func test_the_mini_turbo_is_charged_by_wiggling_against_the_slide() -> void:
	_kart.is_drifting = true
	_kart.turn_angle = deg_to_rad(20.0) # sliding to the right
	watch_signals(_kart)
	for cycle: int in 2:
		_kart._steer_position = -53.0 # the stick against the slide
		for i: int in MkConst.DRIFT_STATE_FRAMES:
			_kart._update_drift_state_counter()
		_kart._steer_position = 0.0 # and back
		_kart._update_drift_state_counter()
	assert_eq(_kart.drift_state, 2, "two wiggles of 18 frames are driftState 2")
	assert_signal_emitted(_kart, "mini_turbo_charged")
	_kart._end_drift(true)
	assert_signal_emitted(_kart, "mini_turbo_fired", "letting go at driftState 2 pays the turbo (func_8002A79C)")
	assert_almost_eq(_kart.boost_seconds, MkConst.frames(MkConst.MINI_TURBO_FRAMES), 0.001, "lasting the game's 31 frames")


func test_holding_the_drift_without_the_wiggle_charges_nothing() -> void:
	_kart.is_drifting = true
	_kart.turn_angle = deg_to_rad(20.0)
	_kart._steer_position = 53.0 # held into the slide the whole way
	for i: int in 120:
		_kart._update_drift_state_counter()
	assert_eq(_kart.drift_state, 0, "the counter only climbs against the slide")
	watch_signals(_kart)
	_kart._end_drift(true)
	assert_signal_not_emitted(_kart, "mini_turbo_fired", "so a held drift pays nothing")
	assert_almost_eq(_kart.boost_seconds, 0.0, 0.0001)


func test_a_mini_turbo_is_fourteen_percent_more_force_and_a_mushroom_ten() -> void:
	_rolling(MkConst.top_speed_units_per_frame(320.0))
	_kart.current_speed = 320.0
	_kart._force = MkConst.drive_force(320.0)
	var plain: float = 0.0
	for i: int in 30:
		plain = _kart._drive_force()
	assert_almost_eq(plain, 4096.0, 1.0, "straight on asphalt the whole force arrives")
	_kart._mini_turbo_on = true
	var turbo: float = 0.0
	for i: int in 30:
		turbo = _kart._drive_force()
	assert_almost_eq(turbo / plain, 1.0 + MkConst.MINI_TURBO_TARGET / 4096.0, 0.01, "unk_0E8 lerped to 580 on top of 4096")
	_kart._mini_turbo_on = false
	_kart._mini_turbo_force = 0.0
	_kart.boost(MkConst.frames(MkConst.BOOST_FRAMES))
	var mushroom: float = 0.0
	for i: int in 30:
		mushroom = _kart._drive_force()
	assert_almost_eq(mushroom / plain, 1.0 + MkConst.MUSHROOM_FORCE / 4096.0, 0.01, "boostPower lerped to 400 on top of it")


func test_grass_takes_thirty_percent_of_the_force_and_a_turn_takes_more() -> void:
	_rolling(MkConst.top_speed_units_per_frame(320.0))
	_kart.current_speed = 320.0
	_kart._force = MkConst.drive_force(320.0)
	_kart.surface = MkConst.SURFACE_GRASS
	var on_grass: float = 0.0
	for i: int in 120:
		on_grass = _kart._drive_force()
	assert_almost_eq(on_grass / 4096.0, 0.70, 0.01, "three tyres at 0.09 and one at 0.03 (D_800E2E90, D_800E2EB0) for a standard kart")
	_kart.surface = MkConst.SURFACE_SOLID
	_kart.turn_angle = deg_to_rad(20.0)
	var turning: float = 0.0
	for i: int in 120:
		turning = _kart._drive_force()
	assert_almost_eq(turning / 4096.0, 1.0 - 20.0 * MkConst.TURN_FORCE_BASE, 0.01, "twenty degrees of turn angle costs a fifth while steering")
	_kart.is_drifting = true
	var drifting: float = 0.0
	for i: int in 120:
		drifting = _kart._drive_force()
	assert_almost_eq(drifting / 4096.0, 1.0 - 20.0 * MkConst.DRIFT_TURN_FORCE, 0.01, "and less than half that while drifting, which is why a drift is faster")


func test_a_cancelled_drift_pays_nothing() -> void:
	_kart.is_drifting = true
	_kart.drift_state = 3
	_kart._end_drift(false)
	assert_almost_eq(_kart.boost_seconds, 0.0, 0.0001, "cancel_drift_effect ends a drift without the turbo")
	assert_false(_kart.is_drifting, "and the drift is over either way")


func test_spinning_out_quarters_the_speed_and_kills_the_drift() -> void:
	_kart.current_speed = 200.0
	_kart.is_drifting = true
	_kart.drift_state = 3
	watch_signals(_kart)
	_kart.spin_out(1.5)
	assert_almost_eq(_kart.current_speed, 50.0, 0.001, "player_controller.c quarters currentSpeed on a hit")
	assert_false(_kart.is_drifting, "and the drift goes with it")
	assert_almost_eq(_kart.boost_seconds, 0.0, 0.0001, "with no mini turbo paid out")
	assert_signal_emitted(_kart, "spun_out")
	_kart.spin_out(1.5)
	assert_almost_eq(_kart.current_speed, 50.0, 0.001, "a second hit while already spinning does not quarter the speed twice")


func test_b_with_the_stick_back_at_a_standstill_reverses() -> void:
	_kart.set_drive_input(false, true, false, 0.0, true)
	_kart.step_frame()
	assert_almost_eq(_kart.current_speed, MkConst.REVERSE_SPEED_UNITS, 0.001, "currentSpeed is set to 140 backwards")
	for i: int in 60:
		_kart.step_frame()
	assert_lt(_kart.forward_speed(), -0.5, "and the kart backs up")
	_kart.set_drive_input(false, true, false, 0.0, false)
	_kart.step_frame()
	assert_almost_eq(_kart.current_speed, 0.0, 0.001, "the stick let go stops it")
	_kart.sync_from_transform()
	_kart.set_drive_input(false, true, false, 0.0, false)
	_kart.step_frame()
	assert_almost_eq(_kart.current_speed, 0.0, 0.001, "B alone at a standstill is a brake, not a reverse, which is what the race's countdown holds")


func test_the_camera_chases_the_karts_yaw_by_a_capped_step() -> void:
	var camera: MkCamera = _kart.chase_camera as MkCamera
	assert_not_null(camera, "the kart's camera is the Mario Kart one")
	camera.begin(null, _kart)
	var behind: Vector3 = camera.global_position - _kart.global_position
	assert_almost_eq(behind.y, MkConst.CAMERA_ABOVE * MkConst.UNIT, 0.01, "11.6 units above")
	assert_almost_eq(Vector2(behind.x, behind.z).length(), MkConst.CAMERA_BEHIND * MkConst.UNIT, 0.01, "38.5 units behind")
	_kart.yaw += PI * 0.5
	for i: int in 30:
		camera._physics_process(FRAME)
	var chased: float = rad_to_deg(absf(angle_difference(camera.cam_yaw, _kart.yaw - PI * 0.5)))
	assert_between(chased, 75.0, 86.0, "a second on, the camera has come 500 units (2.75 degrees) a frame of the 90, and is still behind")
	for i: int in 30:
		camera._physics_process(FRAME)
	assert_almost_eq(angle_difference(camera.cam_yaw, _kart.yaw), 0.0, 0.01, "and has caught up")
	camera.end()
