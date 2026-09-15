extends GutTest

## Purpose: the battle car spends and refills boost at the published rates,
## works its jump and dodge state machine to Rocket League's timings, latches
## supersonic, and demolishes only an opponent it hits fast and head on.
##
## The handling itself is checked against the engine rather than asserted here:
## a car driven by these inputs is what [code]rocket_league.tscn[/code] shows.
## What these tests hold onto is the bookkeeping, because that is where a rule
## can quietly stop being the game's rule.

const ROCKET_CAR: PackedScene = preload("res://addons/gta/rl/scenes/rl_car.tscn")

var car: RlCar


func before_each() -> void:
	# a car with nothing under its wheels is never on the ground, and half of
	# what is tested below only happens on the ground, so the test gets a floor
	var ground: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	ground.add_child(shape)
	ground.position = Vector3(0.0, -0.5, 0.0)
	add_child_autofree(ground)

	car = ROCKET_CAR.instantiate()
	car.team = RlCar.Team.BLUE
	(car.get_node(^"RlAi") as RlAi).enabled = false
	add_child_autofree(car)
	await wait_physics_frames(2)


func test_it_starts_with_the_published_kickoff_tank() -> void:
	assert_almost_eq(car.boost, RlConst.BOOST_START, 0.01,
		"BOOST_SPAWN_AMOUNT is a third of a tank")


func test_the_chassis_points_its_nose_along_positive_z() -> void:
	# this catches the axis the whole handling model is written against: the
	# steered wheels sit at positive z, so the nose does too
	assert_almost_eq(car.nose().z, 1.0, 0.001, "An unrotated car faces positive z")
	assert_almost_eq(car.flank().x, -1.0, 0.001, "Its right hand side is negative x")
	assert_almost_eq(car.roof().y, 1.0, 0.001)


func test_the_nose_flank_and_roof_stay_square_to_each_other() -> void:
	car.global_rotation = Vector3(0.3, 1.1, -0.4)
	assert_almost_eq(car.nose().dot(car.flank()), 0.0, 0.001)
	assert_almost_eq(car.nose().dot(car.roof()), 0.0, 0.001)
	assert_almost_eq(car.flank().dot(car.roof()), 0.0, 0.001)


func test_a_pad_tops_the_tank_up_without_going_over() -> void:
	car.refill_boost(50.0)
	car.collect_boost(RlConst.PAD_BOOST_SMALL)
	assert_almost_eq(car.boost, 62.0, 0.01, "A small pad is worth 12")
	car.collect_boost(RlConst.PAD_BOOST_BIG)
	assert_almost_eq(car.boost, RlConst.BOOST_MAX, 0.01, "A big pad fills it and stops there")


func test_boost_cannot_go_below_empty() -> void:
	car.refill_boost(0.0)
	car.boost = -40.0
	assert_almost_eq(car.boost, 0.0, 0.01)


func test_the_tank_reports_every_change() -> void:
	watch_signals(car)
	car.collect_boost(10.0)
	assert_signal_emitted(car, "boost_changed", "The HUD follows the tank by signal, not by polling")


func test_holding_boost_spends_the_tank() -> void:
	# the exact rate is asserted against the published figure in
	# test_rocket_const.gd and measured against the engine in the demo; what
	# matters here is that holding the button actually spends fuel, and that a
	# fraction of a second does not empty a three second tank
	car.refill_boost(RlConst.BOOST_MAX)
	for _i: int in 20:
		car.set_rocket_input(0.0, 0.0, 0.0, 0.0, 0.0, false, true, false)
		await wait_physics_frames(1)
	assert_lt(car.boost, RlConst.BOOST_MAX, "Holding boost spends it")
	assert_gt(car.boost, 0.0, "And does not empty the tank in a moment")


func test_an_empty_tank_cannot_boost() -> void:
	car.refill_boost(0.0)
	for _i: int in 10:
		car.set_rocket_input(0.0, 0.0, 0.0, 0.0, 0.0, false, true, false)
		await wait_physics_frames(1)
	assert_almost_eq(car.boost, 0.0, 0.01, "Nothing to spend and nothing spent")


func test_a_car_on_the_ground_jumps_when_the_button_goes_down() -> void:
	car.place_at(Vector3(0.0, RlConst.CAR_REST_HEIGHT, 0.0), 0.0)
	await wait_physics_frames(50)
	watch_signals(car)
	car.set_rocket_input(0.0, 0.0, 0.0, 0.0, 0.0, true, false, false)
	await wait_physics_frames(2)
	assert_signal_emitted(car, "jumped")


func test_holding_the_button_down_does_not_jump_twice() -> void:
	car.place_at(Vector3(0.0, RlConst.CAR_REST_HEIGHT, 0.0), 0.0)
	await wait_physics_frames(50)
	watch_signals(car)
	for _i: int in 20:
		car.set_rocket_input(0.0, 0.0, 0.0, 0.0, 0.0, true, false, false)
		await wait_physics_frames(1)
	assert_signal_emit_count(car, "jumped", 1,
		"The hold sets the height of one jump, it does not start another")


func test_a_second_press_with_the_stick_pushed_is_a_dodge() -> void:
	car.place_at(Vector3(0.0, RlConst.CAR_REST_HEIGHT, 0.0), 0.0)
	await wait_physics_frames(50)
	watch_signals(car)
	for _i: int in 6:
		car.set_rocket_input(0.0, 0.0, 0.0, 0.0, 0.0, true, false, false)
		await wait_physics_frames(1)
	for _i: int in 4:
		car.release_controls()
		await wait_physics_frames(1)
	for _i: int in 6:
		car.set_rocket_input(0.0, 0.0, -1.0, 0.0, 0.0, true, false, false)
		await wait_physics_frames(1)
	assert_signal_emitted(car, "dodged", "Stick past the deadzone turns the second jump into a flip")


func test_a_second_press_with_the_stick_centred_is_just_another_jump() -> void:
	car.place_at(Vector3(0.0, RlConst.CAR_REST_HEIGHT, 0.0), 0.0)
	await wait_physics_frames(50)
	watch_signals(car)
	for _i: int in 6:
		car.set_rocket_input(0.0, 0.0, 0.0, 0.0, 0.0, true, false, false)
		await wait_physics_frames(1)
	for _i: int in 4:
		car.release_controls()
		await wait_physics_frames(1)
	for _i: int in 6:
		car.set_rocket_input(0.0, 0.0, 0.0, 0.0, 0.0, true, false, false)
		await wait_physics_frames(1)
	assert_signal_emit_count(car, "jumped", 2, "Two jumps and no flip")
	assert_signal_emit_count(car, "dodged", 0)


func test_there_is_no_third_jump() -> void:
	car.place_at(Vector3(0.0, RlConst.CAR_REST_HEIGHT, 0.0), 0.0)
	await wait_physics_frames(50)
	watch_signals(car)
	for _pair: int in 3:
		for _i: int in 5:
			car.set_rocket_input(0.0, 0.0, 0.0, 0.0, 0.0, true, false, false)
			await wait_physics_frames(1)
		for _i: int in 4:
			car.release_controls()
			await wait_physics_frames(1)
	assert_signal_emit_count(car, "jumped", 2, "A jump and a double jump, and that is all there is")


func test_placing_the_car_clears_what_it_was_doing() -> void:
	car.set_rocket_input(1.0, 0.5, -0.5, 0.5, 0.5, true, true, true)
	car.place_at(Vector3(3.0, 1.0, -4.0), PI * 0.5)
	assert_almost_eq(car.global_position.x, 3.0, 0.001)
	assert_almost_eq(car.linear_velocity.length(), 0.0, 0.001, "A kickoff is a standing start")
	assert_almost_eq(car.angular_velocity.length(), 0.0, 0.001)


func test_the_two_teams_attack_opposite_ends() -> void:
	car.team = RlCar.Team.BLUE
	var blue_target: Vector3 = car.target_goal()
	var blue_own: Vector3 = car.own_goal()
	car.team = RlCar.Team.ORANGE
	assert_almost_eq(car.target_goal().z, blue_own.z, 0.001,
		"What blue defends is what orange attacks")
	assert_almost_eq(car.own_goal().z, blue_target.z, 0.001)


func test_blue_defends_the_positive_end() -> void:
	car.team = RlCar.Team.BLUE
	assert_gt(car.own_goal().z, 0.0, "Blue defends positive z so it attacks along Godot's forward")
	assert_almost_eq(car.attack_direction(), -1.0, 0.001)


func test_a_demolished_car_leaves_play_and_comes_back() -> void:
	watch_signals(car)
	car.demolish(null)
	assert_true(car.is_demolished)
	assert_false(car.visible, "A wreck is not drawn")
	assert_signal_emitted(car, "demolished")


func test_a_wreck_cannot_be_demolished_again() -> void:
	car.demolish(null)
	watch_signals(car)
	car.demolish(null)
	assert_signal_emit_count(car, "demolished", 0)


func test_it_is_not_supersonic_standing_still() -> void:
	assert_false(car.is_supersonic)


# ------------------------------------------------- three wheels is ground -----

func test_the_ground_is_three_wheels_rather_than_one() -> void:
	# Rocket League's own rule: isOnGround is numWheelsInContact >= 3. On one or
	# two it hands you air control and lets you flip, which is how a car tipped
	# into a corner gets itself out
	car.place_at(Vector3(0.0, RlConst.CAR_REST_HEIGHT, 0.0), 0.0)
	await wait_physics_frames(50)
	assert_eq(car.wheels_down, 4, "Sitting flat, all four are down")
	assert_true(car.on_ground)
	# tip it right over: nothing is touching now
	car.place_at(Vector3(0.0, 6.0, 0.0), 0.0)
	await wait_physics_frames(2)
	assert_eq(car.wheels_down, 0, "In the air nothing is down")
	assert_false(car.on_ground)


func test_a_car_in_the_air_is_not_on_the_ground() -> void:
	car.place_at(Vector3(0.0, 8.0, 0.0), 0.0)
	await wait_physics_frames(2)
	assert_false(car.on_ground, "Air control belongs to a car with nothing under it")


# -------------------------------------------------------- the sticky force -----

func test_the_sticky_force_presses_the_car_into_flat_ground() -> void:
	# half a gravity of extra downforce on the flat, which is the published
	# STICKY_FORCE_BASE and barely noticeable until the surface tilts
	car.place_at(Vector3(0.0, RlConst.CAR_REST_HEIGHT, 0.0), 0.0)
	await wait_physics_frames(40)
	assert_true(car.on_ground, "It should settle rather than be pushed off")
	assert_almost_eq(car.global_position.y, RlConst.CAR_REST_HEIGHT, 0.2,
		"And sit at the published resting height")


func test_the_sticky_force_is_stronger_the_steeper_the_surface() -> void:
	# the scale gains 1 - abs(up.y) while driving, so a vertical wall gets three
	# times what flat ground does. This is the whole reason wall play works.
	var flat: float = RlConst.STICKY_FORCE_BASE + (1.0 - 1.0)
	var wall: float = RlConst.STICKY_FORCE_BASE + (1.0 - 0.0)
	assert_almost_eq(flat, 0.5, 0.001, "Flat ground gets only the base")
	assert_almost_eq(wall, 1.5, 0.001, "A wall gets one and a half gravities")
	assert_gt(wall * RlConst.GRAVITY, RlConst.GRAVITY,
		"Which is more than the car's own weight, so it holds against it")


# ------------------------------------------------------------- auto-roll -----

func test_auto_roll_turns_a_tipped_car_back_square_with_the_ground() -> void:
	# the sticky force holds a car against a surface, but only while it is
	# square to it; this is what brings a crooked one back round, and it is the
	# difference between reaching a wall and staying on it
	car.place_at(Vector3(0.0, RlConst.CAR_REST_HEIGHT, 0.0), 0.0)
	await wait_physics_frames(50)
	# tip it well over onto one side, still over the floor
	car.global_rotation = Vector3(0.0, 0.0, 0.9)
	await wait_physics_frames(2)
	var tipped: float = car.roof().dot(Vector3.UP)
	for _i: int in 40:
		car.set_rocket_input(1.0, 0.0, 0.0, 0.0, 0.0, false, false, false)
		await wait_physics_frames(1)
	assert_gt(car.roof().dot(Vector3.UP), tipped,
		"Driving with the car crooked should bring the roof back toward upright")


func test_auto_roll_leaves_a_square_car_alone() -> void:
	car.place_at(Vector3(0.0, RlConst.CAR_REST_HEIGHT, 0.0), 0.0)
	await wait_physics_frames(50)
	for _i: int in 40:
		car.set_rocket_input(1.0, 0.0, 0.0, 0.0, 0.0, false, false, false)
		await wait_physics_frames(1)
	assert_gt(car.roof().dot(Vector3.UP), 0.97,
		"A car already flat on the floor should be left flat, not rolled about")


# ------------------------------------------------------ the pitch lock -----

func test_a_dodge_takes_the_pitch_axis_away_for_a_moment() -> void:
	# FLIP_PITCHLOCK_TIME: pitch is not yours for a second after a dodge
	# starts, which is why a flip cannot simply be pitched out of
	car.place_at(Vector3(0.0, RlConst.CAR_REST_HEIGHT, 0.0), 0.0)
	await wait_physics_frames(50)
	for _i: int in 5:
		car.set_rocket_input(0.0, 0.0, 0.0, 0.0, 0.0, true, false, false)
		await wait_physics_frames(1)
	for _i: int in 4:
		car.release_controls()
		await wait_physics_frames(1)
	for _i: int in 3:
		car.set_rocket_input(0.0, 0.0, -1.0, 0.0, 0.0, true, false, false)
		await wait_physics_frames(1)
	assert_gt(car._pitchlock_time, 0.0, "A dodge starts the lock")
	assert_almost_eq(car._pitchlock_time, RlConst.FLIP_PITCHLOCK_TIME, 0.2,
		"And it runs for the published second")


func test_the_pitch_lock_clears_on_a_kickoff() -> void:
	car._pitchlock_time = RlConst.FLIP_PITCHLOCK_TIME
	car.place_at(Vector3(0.0, RlConst.CAR_REST_HEIGHT, 0.0), 0.0)
	assert_almost_eq(car._pitchlock_time, 0.0, 0.001,
		"A car put back on its spot is not still mid-dodge")


# ------------------------------------------------------------- auto-flip -----

func test_landing_upside_down_and_pressing_jump_throws_the_car_back_over() -> void:
	# without this a car on its roof is stuck: a jump pushes through the roof,
	# and the roof is against the floor
	car.place_at(Vector3(0.0, 0.4, 0.0), 0.0)
	car.global_rotation = Vector3(0.0, 0.0, PI)
	await wait_physics_frames(40)
	assert_lt(car.roof().y, 0.0, "It really is upside down to start with")
	watch_signals(car)
	for _i: int in 6:
		car.set_rocket_input(0.0, 0.0, 0.0, 0.0, 0.0, true, false, false)
		await wait_physics_frames(1)
	assert_signal_emitted(car, "auto_flipped", "Jump rights an upside-down car")


func test_a_car_the_right_way_up_does_not_auto_flip() -> void:
	car.place_at(Vector3(0.0, RlConst.CAR_REST_HEIGHT, 0.0), 0.0)
	await wait_physics_frames(50)
	watch_signals(car)
	for _i: int in 6:
		car.set_rocket_input(0.0, 0.0, 0.0, 0.0, 0.0, true, false, false)
		await wait_physics_frames(1)
	assert_signal_emit_count(car, "auto_flipped", 0, "That press was an ordinary jump")
	assert_signal_emitted(car, "jumped")


# ------------------------------------------------------------- the dodge -----

func test_a_dodge_from_rest_is_worth_the_same_whichever_way_it_is_thrown() -> void:
	# Rocket League scales the three published dodge multipliers from one at a
	# standstill up to their full value at top speed, so a standing dodge gets
	# exactly FLIP_INITIAL_VEL in every direction. Applying them flat, which is
	# what this used to do, made a standing side dodge almost twice too strong.
	var speeds: Array[float] = []
	for direction: Vector2 in [Vector2(0.0, -1.0), Vector2(1.0, 0.0), Vector2(-1.0, 0.0)]:
		car.place_at(Vector3(0.0, RlConst.CAR_REST_HEIGHT, 0.0), 0.0)
		await wait_physics_frames(50)
		for _i: int in 5:
			car.set_rocket_input(0.0, 0.0, 0.0, 0.0, 0.0, true, false, false)
			await wait_physics_frames(1)
		for _i: int in 4:
			car.release_controls()
			await wait_physics_frames(1)
		# the dodge impulse is flat, and the car is still carrying the jump's
		# upward speed, so only the horizontal part is the dodge
		var before: Vector2 = Vector2(car.linear_velocity.x, car.linear_velocity.z)
		for _i: int in 3:
			car.set_rocket_input(0.0, 0.0, direction.x, direction.y, 0.0, true, false, false)
			await wait_physics_frames(1)
		var after: Vector2 = Vector2(car.linear_velocity.x, car.linear_velocity.z)
		speeds.append((after - before).length())
	for gained: float in speeds:
		assert_almost_eq(gained, RlConst.FLIP_INITIAL_VEL, 2.0,
			"A dodge from rest is worth FLIP_INITIAL_VEL, whichever way: got %s" % [speeds])


func test_yaw_and_roll_both_feed_the_sideways_half_of_a_dodge() -> void:
	# RocketSim's dodgeDir.y is yaw + roll, so a directional air roll dodges
	# sideways just as a yaw does
	car.place_at(Vector3(0.0, RlConst.CAR_REST_HEIGHT, 0.0), 0.0)
	await wait_physics_frames(50)
	watch_signals(car)
	for _i: int in 5:
		car.set_rocket_input(0.0, 0.0, 0.0, 0.0, 0.0, true, false, false)
		await wait_physics_frames(1)
	for _i: int in 4:
		car.release_controls()
		await wait_physics_frames(1)
	for _i: int in 5:
		car.set_rocket_input(0.0, 0.0, 0.0, 0.0, 1.0, true, false, false)
		await wait_physics_frames(1)
	assert_signal_emitted(car, "dodged", "Roll alone is past the deadzone and dodges")


func test_the_dodge_deadzone_is_the_sum_of_the_three_axes() -> void:
	# none of these three is past the deadzone alone, but together they are
	car.place_at(Vector3(0.0, RlConst.CAR_REST_HEIGHT, 0.0), 0.0)
	await wait_physics_frames(50)
	watch_signals(car)
	for _i: int in 5:
		car.set_rocket_input(0.0, 0.0, 0.0, 0.0, 0.0, true, false, false)
		await wait_physics_frames(1)
	for _i: int in 4:
		car.release_controls()
		await wait_physics_frames(1)
	for _i: int in 5:
		car.set_rocket_input(0.0, 0.0, 0.2, 0.2, 0.2, true, false, false)
		await wait_physics_frames(1)
	assert_signal_emitted(car, "dodged",
		"Three tenths each is six tenths together, past the half the game asks for")


func test_ball_cam_locks_the_chase_camera_onto_the_ball() -> void:
	var ball: RlBall = load("res://addons/gta/rl/scenes/rl_ball.tscn").instantiate()
	add_child_autofree(ball)
	await wait_physics_frames(2)
	car.is_ball_cam = true
	assert_eq(car.chase_camera.look_target, ball,
		"Ball cam is the chase camera's lock-on pointed at the ball")


func test_turning_ball_cam_off_lets_the_camera_go_back_to_the_heading() -> void:
	var ball: RlBall = load("res://addons/gta/rl/scenes/rl_ball.tscn").instantiate()
	add_child_autofree(ball)
	await wait_physics_frames(2)
	car.is_ball_cam = true
	car.is_ball_cam = false
	assert_null(car.chase_camera.look_target)


func test_the_camera_reports_every_change_so_the_hud_can_follow() -> void:
	var ball: RlBall = load("res://addons/gta/rl/scenes/rl_ball.tscn").instantiate()
	add_child_autofree(ball)
	await wait_physics_frames(2)
	watch_signals(car)
	car.is_ball_cam = true
	assert_signal_emitted(car, "ball_cam_changed")


func test_ball_cam_with_no_ball_on_the_pitch_locks_onto_nothing() -> void:
	# a car dropped into a scene that is not a match must not fall over here
	car.is_ball_cam = true
	assert_null(car.chase_camera.look_target)
	assert_true(car.is_ball_cam, "The setting stands even with nothing to point at")
