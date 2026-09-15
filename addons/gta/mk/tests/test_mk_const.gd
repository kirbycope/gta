extends GutTest

## Purpose: the Mario Kart 64 figures survived the trip out of the decompilation
## into metres, and the unit scale that makes that trip is the derived one
## rather than a guess.
##
## Every other kart script leans on these, so a typo here is a typo everywhere.
## Each assertion names the thing in the decomp it is checking against.


func test_one_game_unit_is_a_ninth_of_a_metre() -> void:
	# func_80030150 reads the speedometer as (speed / 18) * 216, which is speed
	# times 12, and the speedometer is in km/h. So one unit per frame is 12 km/h,
	# and at 30 fps that makes a unit a ninth of a metre.
	assert_almost_eq(MkConst.UNITS_PER_FRAME_TO_KMH, 12.0, 0.0001,
		"(speed / 18) * 216 is speed * 12")
	var metres_per_second: float = MkConst.UNITS_PER_FRAME_TO_KMH / 3.6
	assert_almost_eq(MkConst.UNIT, metres_per_second / MkConst.FPS, 0.0001,
		"one unit per frame is 12 km/h at 30 fps, so a unit is 1/9 m")
	assert_almost_eq(MkConst.UNIT, 1.0 / 9.0, 0.0001, "which is a ninth of a metre")


func test_the_kart_collision_box_is_a_real_go_kart() -> void:
	# the independent check on the scale: gKartBoundingBoxSizeTable is 5.5
	var width: float = MkConst.BOUNDING_BOX * 2.0 * MkConst.UNIT
	assert_almost_eq(width, 1.222, 0.01, "5.5 units across comes out about 1.22 m")
	assert_gt(MkConst.BOUNDING_BOX_HEAVY, MkConst.BOUNDING_BOX,
		"the heavy karts carry the wider box")


func test_drive_force_matches_the_decomps_own_precomputed_table() -> void:
	# This is the check that the whole model is right rather than plausible.
	# src/data/kart_attributes.c holds 3364, 3844, 4096 and 2401 as drive
	# forces, and those are exactly topSpeed squared over 25 for the 50cc,
	# 100cc, 150cc and battle figures.
	assert_almost_eq(MkConst.drive_force(290.0), 3364.0, 0.01, "290^2 / 25 is the 50cc force")
	assert_almost_eq(MkConst.drive_force(310.0), 3844.0, 0.01, "310^2 / 25 is the 100cc force")
	assert_almost_eq(MkConst.drive_force(320.0), 4096.0, 0.01, "320^2 / 25 is the 150cc force")
	assert_almost_eq(MkConst.drive_force(245.0), 2401.0, 0.01, "245^2 / 25 is the battle force")


func test_a_kart_settles_where_drive_force_balances_drag() -> void:
	# the integrator is v += ((force - v * 0.12 * kartFriction) / 6000) / divisor
	var force: float = MkConst.drive_force(320.0)
	var settled: float = force / (MkConst.DRAG_FACTOR * MkConst.KART_FRICTION)
	assert_almost_eq(MkConst.top_speed_units_per_frame(320.0), settled, 0.0001,
		"top speed is force over 0.12 * 5800")
	assert_almost_eq(settled * MkConst.UNITS_PER_FRAME_TO_KMH, 70.6, 0.1,
		"a 150cc kart settles at about 70.6 km/h")


func test_the_engine_classes_are_in_the_published_order() -> void:
	var fifty: float = MkConst.top_speed(&"50cc")
	var hundred: float = MkConst.top_speed(&"100cc")
	var one_fifty: float = MkConst.top_speed(&"150cc")
	var battle: float = MkConst.top_speed(&"battle")
	assert_lt(fifty, hundred, "100cc is faster than 50cc")
	assert_lt(hundred, one_fifty, "150cc is faster than 100cc")
	assert_lt(battle, fifty, "battle mode is the slowest of the lot")
	assert_almost_eq(one_fifty, 19.62, 0.05, "150cc is about 19.6 m/s")


func test_the_light_karts_get_the_higher_top_speed() -> void:
	for engine_class: StringName in [&"50cc", &"100cc", &"150cc"]:
		assert_gt(MkConst.top_speed(engine_class, true), MkConst.top_speed(engine_class, false),
			"gTopSpeedTable gives the light karts 294/314/324 against 290/310/320")
	assert_almost_eq(MkConst.top_speed(&"battle", true), MkConst.top_speed(&"battle", false),
		0.0001, "battle mode is 245 for everybody")


func test_an_unknown_engine_class_is_nothing_rather_than_a_guess() -> void:
	assert_almost_eq(MkConst.top_speed(&"200cc"), 0.0, 0.0001,
		"Mario Kart 64 has no 200cc, so there is no figure to invent")


func test_frame_timings_convert_at_the_games_thirty_fps() -> void:
	assert_almost_eq(MkConst.frames(MkConst.MINI_TURBO_FRAMES), 31.0 / 30.0, 0.001,
		"func_8002A79C ends the mini turbo at 0x1F frames")
	assert_almost_eq(MkConst.frames(MkConst.BOOST_FRAMES), 80.0 / 30.0, 0.001,
		"func_8002A704 sets boostTimer to 0x50")
	assert_eq(MkConst.DRIFT_DURATION_CAP, 100,
		"update_player_drift_duration clamps driftDuration at 100")


func test_the_off_road_surfaces_are_the_ones_the_surface_doc_lists() -> void:
	assert_true(MkConst.is_off_road(MkConst.SURFACE_GRASS), "grass is off road")
	assert_true(MkConst.is_off_road(MkConst.SURFACE_SAND), "sand is off road")
	assert_true(MkConst.is_off_road(MkConst.SURFACE_DIRT_OFF_ROAD), "dirt off road is off road")
	assert_false(MkConst.is_off_road(MkConst.SURFACE_SOLID), "pavement is not")
	assert_false(MkConst.is_off_road(MkConst.SURFACE_BOOST_RAMP), "a boost ramp is not")
	assert_false(MkConst.is_off_road(MkConst.SURFACE_WOOD_BRIDGE), "a solid bridge is not")


func test_the_race_rules_are_the_games_own() -> void:
	assert_eq(MkConst.RACERS, 8, "NUM_PLAYERS is 8")
	assert_eq(MkConst.LAPS, 3, "race_logic.c ends a race when lapCount reaches 3")


func test_the_gaps_are_named_rather_than_filled_in() -> void:
	assert_gt(MkConst.UNSOURCED.size(), 0,
		"what could not be read out of the decomp is listed rather than invented")
	var joined: String = " ".join(MkConst.UNSOURCED)
	assert_string_contains(joined, "item probability curves",
		"the item odds live in the ROM, and that is said out loud")
	assert_string_contains(joined, "BOOST_SPEED_SCALE",
		"the boost magnitude is a judgement, because the decomp's figure is in other units")
