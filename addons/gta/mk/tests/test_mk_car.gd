extends GutTest

## Purpose: the kart's acceleration follows the decomp's band curve, the drift
## pays a mini turbo only when it was held long enough, and the directions the
## chassis was measured to have are the directions it still has.
##
## The direction tests are here because both of them were wrong once and neither
## showed up as an error: a kart with a reversed forward still drove, and a kart
## whose steering answered the stick backwards still moved. They cost a long
## afternoon, so they are pinned down here rather than left to be rediscovered.

const KART_SCENE: String = "res://addons/gta/mk/scenes/mk_kart.tscn"

var _kart: MkCar


func before_each() -> void:
	_kart = (load(KART_SCENE) as PackedScene).instantiate() as MkCar
	_kart.driver = &"rook"
	_kart.engine_class = &"150cc"
	add_child_autofree(_kart)
	await wait_physics_frames(1)


func test_the_kart_is_built_nose_along_positive_z() -> void:
	# measured: with the wheels on +2600 each, a rolling kart's velocity sits at
	# +0.91 to +0.97 along its own basis.z
	_kart.global_transform = Transform3D(Basis(), Vector3.ZERO)
	assert_almost_eq(_kart.forward().dot(_kart.global_transform.basis.z), 1.0, 0.0001,
		"forward() is +basis.z, the way TwCar's chassis is")


func test_the_nose_of_the_model_points_the_way_the_kart_drives() -> void:
	var nose: Node3D = _kart.get_node_or_null(^"Nose") as Node3D
	assert_not_null(nose, "the kart has a nose to check")
	assert_gt(nose.position.z, 0.0,
		"the nose is on the +Z side, which is where the chassis pushes the kart")
	var seat: Node3D = _kart.get_node_or_null(^"Seat") as Node3D
	assert_lt(seat.position.z, nose.position.z, "and the driver sits behind it")


func test_the_steering_wheels_are_the_front_ones() -> void:
	var front: VehicleWheel3D = _kart.get_node_or_null(^"FrontLeft") as VehicleWheel3D
	var rear: VehicleWheel3D = _kart.get_node_or_null(^"RearLeft") as VehicleWheel3D
	assert_true(front.use_as_steering, "the front wheels steer")
	assert_false(rear.use_as_steering, "the rear ones do not")
	assert_true(rear.use_as_traction, "and the rear ones drive")
	assert_gt(front.position.z, rear.position.z,
		"with the kart facing +Z, the steering wheels are the ones further forward")


func test_the_centre_of_mass_is_below_the_body_so_it_does_not_roll_over() -> void:
	assert_lt(_kart.center_of_mass.y, 0.0,
		"a kart with its mass at body height rolls itself over in the first corner")


func test_top_speed_comes_from_the_roster_and_the_engine_class() -> void:
	assert_almost_eq(_kart.top_speed(), MkRoster.top_speed(&"rook", &"150cc"), 0.0001,
		"the kart's ceiling is its driver's")
	assert_almost_eq(_kart.ceiling_speed_units(), 320.0, 0.0001,
		"a standard kart at 150cc runs to a topSpeed of 320")


func test_a_light_kart_carries_the_higher_ceiling() -> void:
	# built fresh rather than re-readied: the driver is read once when the kart
	# enters the tree, and calling _ready() again would wire its signals twice
	var light: MkCar = (load(KART_SCENE) as PackedScene).instantiate() as MkCar
	light.driver = &"pip"
	light.engine_class = &"150cc"
	add_child_autofree(light)
	await wait_physics_frames(1)
	assert_almost_eq(light.ceiling_speed_units(), 324.0, 0.0001,
		"gTopSpeedTable gives the light karts 324 at 150cc")


func test_holding_the_throttle_builds_speed_along_the_curve() -> void:
	_kart.current_speed = 0.0
	_kart.set_drive_input(true, false, false, 0.0)
	var was: float = _kart.current_speed
	for i in range(30):
		_kart._step_speed_one_frame()
		assert_true(_kart.current_speed >= was, "speed never goes backwards under power")
		was = _kart.current_speed
	assert_gt(_kart.current_speed, 0.0, "a second of throttle builds real speed")
	assert_true(_kart.current_speed <= _kart.ceiling_speed_units(),
		"and never past the kart's own ceiling")


func test_speed_is_capped_at_the_ceiling_however_long_the_throttle_is_held() -> void:
	_kart.set_drive_input(true, false, false, 0.0)
	for i in range(600):
		_kart._step_speed_one_frame()
	assert_almost_eq(_kart.current_speed, _kart.ceiling_speed_units(), 0.001,
		"twenty seconds of throttle reaches the ceiling and stops there")


func test_lifting_off_slows_the_kart_down() -> void:
	_kart.current_speed = 200.0
	_kart.set_drive_input(false, false, false, 0.0)
	for i in range(10):
		_kart._step_speed_one_frame()
	assert_lt(_kart.current_speed, 200.0, "a kart off the throttle slows rather than coasting")


func test_off_road_costs_speed_and_a_boost_carries_you_over_it() -> void:
	_kart.surface = MkConst.SURFACE_GRASS
	_kart.current_speed = 300.0
	_kart.set_drive_input(false, false, false, 0.0)
	_kart._step_speed_one_frame()
	var on_grass: float = _kart.current_speed

	_kart.surface = MkConst.SURFACE_SOLID
	_kart.current_speed = 300.0
	_kart._step_speed_one_frame()
	var on_road: float = _kart.current_speed
	assert_gt(on_road, on_grass, "grass costs more speed than pavement")

	_kart.surface = MkConst.SURFACE_GRASS
	_kart.current_speed = 300.0
	_kart.boost_seconds = 1.0
	_kart._step_speed_one_frame()
	assert_gt(_kart.current_speed, on_grass, "a boost carries a kart across the grass")
	# the boost waives the surface penalty and nothing else, so a boosting kart
	# on grass loses exactly what a coasting kart on pavement loses
	assert_almost_eq(_kart.current_speed, on_road, 0.0001,
		"grass costs a boosting kart nothing, though lifting off still does")


func test_a_boost_lifts_the_speed_limit() -> void:
	_kart.current_speed = _kart.ceiling_speed_units()
	var normal: float = _kart.speed_limit()
	_kart.boost_seconds = 1.0
	assert_gt(_kart.speed_limit(), normal, "a boost goes past the kart's own ceiling")
	assert_almost_eq(_kart.speed_limit() / normal, MkConst.BOOST_SPEED_SCALE, 0.01,
		"by the documented scale rather than by the decomp's other-unit figure")


func test_a_short_drift_pays_nothing_and_a_long_one_pays_a_mini_turbo() -> void:
	_kart.is_drifting = true
	_kart.drift_state = 1
	_kart._end_drift(true)
	assert_almost_eq(_kart.boost_seconds, 0.0, 0.0001,
		"func_8002A79C pays out only from driftState 2")

	_kart.is_drifting = true
	_kart.drift_state = MkConst.MINI_TURBO_DRIFT_STATE
	watch_signals(_kart)
	_kart._end_drift(true)
	assert_signal_emitted(_kart, "mini_turbo_fired", "a held drift pays a mini turbo")
	assert_almost_eq(_kart.boost_seconds, MkConst.frames(MkConst.MINI_TURBO_FRAMES), 0.001,
		"lasting the game's 31 frames")


func test_a_cancelled_drift_pays_nothing() -> void:
	_kart.is_drifting = true
	_kart.drift_state = 3
	_kart._end_drift(false)
	assert_almost_eq(_kart.boost_seconds, 0.0, 0.0001,
		"cancel_drift_effect ends a drift without the turbo")
	assert_false(_kart.is_drifting, "and the drift is over either way")


func test_spinning_out_quarters_the_speed_and_kills_the_drift() -> void:
	_kart.current_speed = 200.0
	_kart.is_drifting = true
	_kart.drift_state = 3
	watch_signals(_kart)
	_kart.spin_out(1.5)
	assert_almost_eq(_kart.current_speed, 50.0, 0.001,
		"player_controller.c quarters currentSpeed on a hit")
	assert_false(_kart.is_drifting, "and the drift goes with it")
	assert_almost_eq(_kart.boost_seconds, 0.0, 0.0001, "with no mini turbo paid out")
	assert_signal_emitted(_kart, "spun_out")


func test_a_kart_already_spinning_is_not_spun_again() -> void:
	_kart.current_speed = 200.0
	_kart.spin_out(1.5)
	var after_first: float = _kart.current_speed
	_kart.spin_out(1.5)
	assert_almost_eq(_kart.current_speed, after_first, 0.001,
		"a second hit while already spinning does not quarter the speed twice")
