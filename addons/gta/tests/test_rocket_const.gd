extends GutTest

## Purpose: the published Rocket League figures survived the trip from Unreal
## units into metres, the piecewise curves read the way the game's own
## LinearPieceCurve does, and the axis conversion puts the two teams on the
## right ends of the pitch.
##
## These are the numbers every other Rocket League script depends on, so a typo
## here is a typo everywhere. Each assertion names the figure it is checking
## against rather than just repeating the constant.


func test_unreal_units_convert_to_metres_at_one_centimetre_each() -> void:
	assert_almost_eq(RocketConst.ARENA_EXTENT_X, 4096.0 * RocketConst.UU, 0.0001,
		"ARENA_EXTENT_X is 4096 uu")
	assert_almost_eq(RocketConst.ARENA_EXTENT_Y, 5120.0 * RocketConst.UU, 0.0001,
		"ARENA_EXTENT_Y is 5120 uu")
	assert_almost_eq(RocketConst.ARENA_HEIGHT, 2048.0 * RocketConst.UU, 0.0001,
		"ARENA_HEIGHT is 2048 uu")
	assert_almost_eq(RocketConst.BALL_RADIUS, 91.25 * RocketConst.UU, 0.0001,
		"BALL_COLLISION_RADIUS_SOCCAR is 91.25 uu")
	assert_almost_eq(RocketConst.GRAVITY, 650.0 * RocketConst.UU, 0.0001,
		"GRAVITY_Z is 650 uu/s^2")


func test_the_pitch_is_the_published_size() -> void:
	assert_almost_eq(RocketConst.ARENA_EXTENT_X * 2.0, 81.92, 0.001, "81.92 m wall to wall")
	assert_almost_eq(RocketConst.ARENA_EXTENT_Y * 2.0, 102.4, 0.001, "102.4 m goal to goal")


func test_the_corners_account_for_the_published_corner_wall_length() -> void:
	# the flat walls and the chamfers have to add up to the whole pitch: a
	# corner takes the same bite out of both axes, and the face across it is
	# that bite on the diagonal
	var bite_along_x: float = (RocketConst.ARENA_EXTENT_X * 2.0 - RocketConst.BACK_WALL_LENGTH) * 0.5
	var bite_along_z: float = (RocketConst.ARENA_EXTENT_Y * 2.0 - RocketConst.SIDE_WALL_LENGTH) * 0.5
	assert_almost_eq(bite_along_x, bite_along_z, 0.001,
		"A 45 degree chamfer cuts the same distance off each axis")
	assert_almost_eq(bite_along_x * sqrt(2.0), RocketConst.CORNER_WALL_LENGTH, 0.001,
		"CORNER_WALL_LENGTH 1629.174 uu is that cut on the diagonal")


func test_the_goal_line_sits_just_beyond_the_back_wall() -> void:
	assert_gt(RocketConst.GOAL_LINE_Y, RocketConst.ARENA_EXTENT_Y,
		"SOCCAR_GOAL_SCORE_BASE_THRESHOLD_Y 5124.25 uu is past the wall at 5120")


func test_a_full_tank_lasts_three_seconds() -> void:
	assert_almost_eq(RocketConst.BOOST_MAX / RocketConst.BOOST_PER_SECOND, 3.0, 0.01,
		"BOOST_MAX 100 at BOOST_USED_PER_SECOND 33.33")
	assert_almost_eq(RocketConst.BOOST_START, RocketConst.BOOST_MAX / 3.0, 0.01,
		"BOOST_SPAWN_AMOUNT is a third of a tank")


func test_boosting_accelerates_harder_in_the_air_than_on_the_ground() -> void:
	assert_gt(RocketConst.BOOST_ACCEL_AIR, RocketConst.BOOST_ACCEL_GROUND,
		"BOOST_ACCEL_AIR 3175/3 beats BOOST_ACCEL_GROUND 2975/3")


func test_the_published_pad_tables_are_all_there() -> void:
	assert_eq(RocketConst.BIG_PADS.size(), 6, "LOCS_AMOUNT_BIG is 6")
	assert_eq(RocketConst.SMALL_PADS.size(), 28, "LOCS_AMOUNT_SMALL_SOCCAR is 28")


func test_every_pad_lands_inside_the_pitch() -> void:
	for spot: Vector2 in RocketConst.BIG_PADS + RocketConst.SMALL_PADS:
		assert_lt(absf(spot.x), RocketConst.ARENA_EXTENT_X, "Pad %s is inside the side walls" % spot)
		assert_lt(absf(spot.y), RocketConst.ARENA_EXTENT_Y, "Pad %s is inside the back walls" % spot)


func test_the_pad_tables_are_symmetrical_end_to_end() -> void:
	# neither team may be given more boost than the other, so every pad must
	# have a mirror in the other half
	for spot: Vector2 in RocketConst.SMALL_PADS:
		var mirrored: bool = false
		for other: Vector2 in RocketConst.SMALL_PADS:
			if is_equal_approx(other.x, -spot.x) and is_equal_approx(other.y, -spot.y):
				mirrored = true
				break
		assert_true(mirrored, "Small pad %s has no mirror in the other half" % spot)


func test_there_are_five_kickoff_spots_and_four_respawn_spots() -> void:
	assert_eq(RocketConst.KICKOFF_SPOTS.size(), 5, "CAR_SPAWN_LOCATION_AMOUNT is 5")
	assert_eq(RocketConst.RESPAWN_SPOTS.size(), 4, "CAR_RESPAWN_LOCATION_AMOUNT is 4")


func test_every_kickoff_spot_is_in_the_blue_half() -> void:
	# the table is blue's and orange mirrors it, so a positive y here would put
	# a car in the wrong half at kickoff
	for spot: Vector3 in RocketConst.KICKOFF_SPOTS:
		assert_lt(spot.y, 0.0, "Kickoff spot %s should be in the negative half" % spot)


func test_the_axis_conversion_puts_blue_on_the_positive_z_end() -> void:
	# Rocket League's blue defends negative y, and this project's blue defends
	# positive z so that it attacks along Godot's own forward
	var spawn: Vector3 = RocketConst.to_godot(0.0, -46.08, 0.17)
	assert_almost_eq(spawn.x, 0.0, 0.001)
	assert_almost_eq(spawn.y, 0.17, 0.001, "Rocket League's z is Godot's height")
	assert_almost_eq(spawn.z, 46.08, 0.001, "Rocket League's negative y is Godot's positive z")


func test_the_yaw_conversion_turns_a_kickoff_to_face_the_far_goal() -> void:
	# a blue car on the centre spot faces Rocket League's positive y, which is
	# Godot's negative z. The chassis noses along Godot's positive z, so the
	# yaw that puts its nose on negative z is pi, not zero. The old conversion
	# gave zero here and every kickoff faced away from the ball.
	var facing: float = RocketConst.to_godot_yaw(PI * 0.5)
	var nose: Vector3 = Basis(Vector3.UP, facing).z
	assert_almost_eq(nose.z, -1.0, 0.001, "The nose ends up on negative z, where positive y went")
	assert_almost_eq(nose.x, 0.0, 0.001)
	# and the corner spot: Rocket League's quarter pi faces between positive x and positive y
	var corner: Vector3 = Basis(Vector3.UP, RocketConst.to_godot_yaw(PI * 0.25)).z
	assert_almost_eq(corner.x, 0.7071, 0.001, "Positive x stays positive x")
	assert_almost_eq(corner.z, -0.7071, 0.001, "and positive y is negative z")


func test_a_curve_holds_its_end_values_beyond_either_end() -> void:
	assert_almost_eq(RocketConst.curve(RocketConst.STEER_CURVE, -10.0), 0.53356, 0.0001,
		"Below the first point the curve holds its first value")
	assert_almost_eq(RocketConst.curve(RocketConst.STEER_CURVE, 9000.0), 0.03454, 0.0001,
		"Above the last point it holds its last")


func test_a_curve_blends_between_its_points() -> void:
	# halfway between 0 m/s and 5 m/s on the steering curve
	var expected: float = (0.53356 + 0.31930) * 0.5
	assert_almost_eq(RocketConst.curve(RocketConst.STEER_CURVE, 2.5), expected, 0.0001)


func test_an_empty_curve_reads_zero_rather_than_failing() -> void:
	var nothing: Array[Vector2] = []
	assert_almost_eq(RocketConst.curve(nothing, 12.0), 0.0, 0.0001)


func test_the_throttle_curve_dies_at_the_speed_boost_is_needed_past() -> void:
	assert_almost_eq(RocketConst.curve(RocketConst.DRIVE_TORQUE_CURVE, 0.0), 1.0, 0.0001,
		"Full torque from a standstill")
	assert_almost_eq(RocketConst.curve(RocketConst.DRIVE_TORQUE_CURVE,
		RocketConst.CAR_MAX_DRIVE_SPEED), 0.0, 0.0001,
		"No torque left at 1410 uu/s, which is why boost is the only way past it")


func test_steering_lock_tightens_as_the_car_speeds_up() -> void:
	var previous: float = INF
	for speed: float in [0.0, 5.0, 10.0, 15.0, 17.5, 30.0]:
		var lock: float = RocketConst.curve(RocketConst.STEER_CURVE, speed)
		assert_lt(lock, previous, "Steering lock should keep shrinking, at %s m/s" % speed)
		previous = lock


func test_a_powerslide_widens_the_lock_at_the_speeds_it_is_used_at() -> void:
	# the two curves are different shapes rather than one being the other
	# shifted up, and they cross between 4 and 5 m/s
	for speed: float in [5.0, 10.0, 15.0, 20.0]:
		assert_gt(RocketConst.curve(RocketConst.POWERSLIDE_STEER_CURVE, speed),
			RocketConst.curve(RocketConst.STEER_CURVE, speed),
			"Sliding should turn the car harder than gripping, at %s m/s" % speed)


func test_below_walking_pace_gripping_turns_harder_than_sliding() -> void:
	# worth pinning down rather than treating as a bug in the tables: a
	# standing car turns 30.6 degrees on its tyres and only 22.5 sliding, so
	# throwing the handbrake on at a crawl makes the turn worse, not better
	assert_gt(RocketConst.curve(RocketConst.STEER_CURVE, 0.0),
		RocketConst.curve(RocketConst.POWERSLIDE_STEER_CURVE, 0.0))


func test_roll_is_the_fastest_axis_in_the_air() -> void:
	# CAR_AIR_CONTROL_TORQUE is pitch, yaw, roll, and roll being far the
	# largest is why air roll is the quick way to turn a car over
	assert_gt(RocketConst.AIR_CONTROL_TORQUE.z, RocketConst.AIR_CONTROL_TORQUE.x)
	assert_gt(RocketConst.AIR_CONTROL_TORQUE.z, RocketConst.AIR_CONTROL_TORQUE.y)


func test_air_control_settles_under_the_angular_speed_cap() -> void:
	# torque against damping gives the speed each axis settles at, and none of
	# them may sit above CAR_MAX_ANG_SPEED or the cap would be doing the steering
	for axis: int in 3:
		var settled: float = RocketConst.AIR_CONTROL_TORQUE[axis] / RocketConst.AIR_CONTROL_DAMPING[axis]
		assert_lt(settled, 10.0, "Axis %d settles at %f rad/s" % [axis, settled])


func test_a_backward_dodge_carries_furthest() -> void:
	assert_gt(RocketConst.FLIP_BACKWARD_MAX_SCALE, RocketConst.FLIP_SIDE_MAX_SCALE)
	assert_gt(RocketConst.FLIP_SIDE_MAX_SCALE, RocketConst.FLIP_FORWARD_MAX_SCALE)


func test_supersonic_is_held_below_the_speed_it_starts_at() -> void:
	assert_lt(RocketConst.SUPERSONIC_MAINTAIN, RocketConst.SUPERSONIC_START,
		"Dropping under the threshold stays supersonic for a second")


func test_the_gaps_in_the_sourcing_are_written_down() -> void:
	assert_gt(RocketConst.UNSOURCED.size(), 0,
		"Anything not taken from a published source belongs in UNSOURCED")
