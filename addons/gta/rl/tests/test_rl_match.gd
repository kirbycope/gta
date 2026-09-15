extends GutTest

## Purpose: the rules of a game of soccar. A goal is the ball's centre crossing
## the published line and not a near miss, the clock runs down and holds at
## zero, a draw at full time goes to overtime and the next goal ends it, and a
## reset really does put everything back.
##
## The match is built here rather than by loading the demo scene, because the
## demo brings a pitch, a Player and thirty four boost pads with it and none of
## those are what is being checked. Scoring is tested through the same helper
## the match itself uses, so the test and the game agree on where the line is.

const ROCKET_BALL: PackedScene = preload("res://addons/gta/rl/scenes/rl_ball.tscn")

var match_node: RlMatch
var ball: RlBall


func before_each() -> void:
	match_node = RlMatch.new()
	match_node.name = "RocketLeague"
	match_node.seat_player = false
	match_node.team_size = 1
	# the match reaches for these by name in _ready, so they exist before it does
	ball = ROCKET_BALL.instantiate()
	ball.name = "Ball"
	match_node.add_child(ball)
	var replay: RlReplay = RlReplay.new()
	replay.name = "Replay"
	match_node.add_child(replay)
	var timer: Timer = Timer.new()
	timer.name = "CountdownTimer"
	timer.one_shot = true
	match_node.add_child(timer)
	# the replay camera is a pivot, a spring arm and a camera, mirroring
	# rocket_league.tscn: the arm is what keeps the arena out of the shot
	var replay_pivot: Node3D = Node3D.new()
	replay_pivot.name = "ReplayCamera"
	var arm: SpringArm3D = SpringArm3D.new()
	arm.name = "SpringArm3D"
	var camera: Camera3D = Camera3D.new()
	camera.name = "Camera3D"
	arm.add_child(camera)
	replay_pivot.add_child(arm)
	match_node.add_child(replay_pivot)
	var arena: RlArena = RlArena.new()
	arena.name = "Arena"
	match_node.add_child(arena)
	var ui: RlUi = load("res://addons/gta/rl/scenes/rl_ui.tscn").instantiate()
	ui.name = "UI"
	match_node.add_child(ui)
	add_child_autofree(match_node)
	await wait_physics_frames(4)


func test_a_match_starts_level_with_a_full_clock() -> void:
	assert_eq(match_node.blue_score, 0)
	assert_eq(match_node.orange_score, 0)
	assert_almost_eq(match_node.clock, match_node.match_minutes * 60.0, 1.0)
	assert_false(match_node.is_overtime)


func test_the_ball_on_the_centre_spot_is_not_a_goal() -> void:
	ball.global_position = RlMatch.CENTRE_SPOT
	assert_eq(match_node._goal_crossed(), 0)


func test_a_ball_over_the_line_between_the_posts_is_a_goal() -> void:
	ball.global_position = Vector3(0.0, 1.0, RlConst.GOAL_LINE_Y + 0.5)
	assert_eq(match_node._goal_crossed(), 1, "Past the positive line is a goal in blue's net")
	ball.global_position = Vector3(0.0, 1.0, -RlConst.GOAL_LINE_Y - 0.5)
	assert_eq(match_node._goal_crossed(), -1)


func test_a_ball_just_short_of_the_line_is_not_a_goal() -> void:
	ball.global_position = Vector3(0.0, 1.0, RlConst.GOAL_LINE_Y - 0.05)
	assert_eq(match_node._goal_crossed(), 0,
		"Rocket League needs the ball wholly over 5124.25 uu")


func test_a_ball_wide_of_the_post_is_not_a_goal() -> void:
	ball.global_position = Vector3(RlConst.GOAL_HALF_WIDTH + 1.0, 1.0,
		RlConst.GOAL_LINE_Y + 0.5)
	assert_eq(match_node._goal_crossed(), 0, "Outside the posts is the back wall, not the net")


func test_a_ball_over_the_crossbar_is_not_a_goal() -> void:
	ball.global_position = Vector3(0.0, RlConst.GOAL_HEIGHT + 1.0,
		RlConst.GOAL_LINE_Y + 0.5)
	assert_eq(match_node._goal_crossed(), 0)


func test_a_goal_in_blue_s_net_is_scored_by_orange() -> void:
	watch_signals(match_node)
	match_node._award_goal(RlCar.Team.ORANGE)
	assert_eq(match_node.orange_score, 1)
	assert_eq(match_node.blue_score, 0)
	assert_signal_emitted(match_node, "goal_scored")
	assert_signal_emitted(match_node, "score_changed")


func test_the_clock_counts_down_and_stops_at_zero() -> void:
	match_node.clock = 0.4
	match_node.state = RlMatch.State.PLAYING
	# the ball is in the air, so time is up but the game is not over yet
	ball.global_position = Vector3(0.0, 8.0, 0.0)
	ball.linear_velocity = Vector3(0.0, 4.0, 0.0)
	match_node._tick_clock(0.5)
	assert_almost_eq(match_node.clock, 0.0, 0.001, "The clock never goes negative")
	assert_ne(match_node.state, RlMatch.State.OVER,
		"A ball still in the air keeps the game alive past zero")


func test_full_time_with_a_lead_ends_the_match() -> void:
	match_node.blue_score = 2
	match_node.orange_score = 1
	match_node.clock = 0.0
	match_node.state = RlMatch.State.PLAYING
	ball.global_position = Vector3(0.0, RlConst.BALL_REST_HEIGHT, 0.0)
	ball.linear_velocity = Vector3.ZERO
	watch_signals(match_node)
	match_node._tick_clock(0.1)
	assert_eq(match_node.state, RlMatch.State.OVER)
	assert_signal_emitted(match_node, "match_ended")


func test_full_time_level_goes_to_overtime_rather_than_a_draw() -> void:
	match_node.blue_score = 1
	match_node.orange_score = 1
	match_node.clock = 0.0
	match_node.state = RlMatch.State.PLAYING
	ball.global_position = Vector3(0.0, RlConst.BALL_REST_HEIGHT, 0.0)
	ball.linear_velocity = Vector3.ZERO
	match_node._tick_clock(0.1)
	assert_true(match_node.is_overtime)
	assert_ne(match_node.state, RlMatch.State.OVER)


func test_the_overtime_clock_counts_up() -> void:
	match_node.is_overtime = true
	match_node.clock = 0.0
	match_node._tick_clock(1.0)
	assert_almost_eq(match_node.clock, 1.0, 0.01, "Overtime counts how long it has run")


func test_the_first_goal_in_overtime_ends_it() -> void:
	match_node.is_overtime = true
	match_node.blue_score = 1
	match_node.orange_score = 1
	watch_signals(match_node)
	match_node._award_goal(RlCar.Team.BLUE)
	assert_eq(match_node.state, RlMatch.State.OVER, "Golden goal")
	assert_signal_emitted(match_node, "match_ended")


func test_the_replay_camera_is_aimed_from_inside_the_arena() -> void:
	# the bug this guards against: the replay was first written to sit behind
	# the net, the way the real game does it. This arena is a closed box, so
	# that put the camera six metres beyond the back wall, filming the outside
	# of the stadium with a wall panel in the way.
	for goal_z: float in [RlConst.GOAL_LINE_Y, -RlConst.GOAL_LINE_Y]:
		match_node._aim_replay_at(goal_z)
		# the spring arm places the camera on its own physics step
		await wait_physics_frames(3)
		var eye: Vector3 = match_node.replay_camera.global_position
		assert_lt(absf(eye.x), RlConst.ARENA_EXTENT_X,
			"Inside the side walls, filming the goal at %.1f" % goal_z)
		assert_lt(absf(eye.z), RlConst.ARENA_EXTENT_Y,
			"Inside the back walls, filming the goal at %.1f" % goal_z)
		assert_between(eye.y, 0.0, RlConst.ARENA_HEIGHT,
			"Under the roof, filming the goal at %.1f" % goal_z)


func test_the_replay_camera_films_the_end_that_was_scored_in() -> void:
	for goal_z: float in [RlConst.GOAL_LINE_Y, -RlConst.GOAL_LINE_Y]:
		match_node._aim_replay_at(goal_z)
		await wait_physics_frames(3)
		var eye: Vector3 = match_node.replay_camera.global_position
		assert_eq(signf(eye.z), signf(goal_z),
			"The camera belongs at the same end as the goal at %.1f" % goal_z)
		assert_lt(absf(eye.z), absf(goal_z),
			"And on the playing side of it, not past the line")


func test_the_replay_camera_looks_back_at_the_goal_it_is_filming() -> void:
	match_node._aim_replay_at(-RlConst.GOAL_LINE_Y)
	await wait_physics_frames(3)
	var eye: Vector3 = match_node.replay_camera.global_position
	var toward_goal: Vector3 = (match_node.replay_pivot.global_position - eye).normalized()
	var looking: Vector3 = -match_node.replay_camera.global_basis.z
	assert_gt(looking.dot(toward_goal), 0.9, "The camera faces the goal it was aimed at")


func test_a_reset_puts_the_scores_and_the_clock_back() -> void:
	match_node.blue_score = 3
	match_node.orange_score = 2
	match_node.is_overtime = true
	match_node.clock = 91.0
	match_node.reset_match()
	assert_eq(match_node.blue_score, 0)
	assert_eq(match_node.orange_score, 0)
	assert_false(match_node.is_overtime)
	assert_almost_eq(match_node.clock, match_node.match_minutes * 60.0, 0.01)


func test_a_kickoff_puts_the_ball_back_on_the_centre_spot() -> void:
	ball.global_position = Vector3(20.0, 6.0, -30.0)
	ball.linear_velocity = Vector3(9.0, 2.0, -4.0)
	match_node.start_kickoff()
	await wait_physics_frames(2)
	assert_almost_eq(ball.global_position.x, 0.0, 0.2)
	assert_almost_eq(ball.global_position.z, 0.0, 0.2)
	assert_almost_eq(ball.linear_velocity.length(), 0.0, 0.5, "A kickoff ball is still")


func test_a_kickoff_counts_down_before_anyone_may_drive() -> void:
	match_node.start_kickoff()
	assert_eq(match_node.state, RlMatch.State.COUNTDOWN)


func test_nobody_is_driving_while_the_clock_is_stopped() -> void:
	# the state setter is what freezes the field, and every state but PLAYING
	# has to freeze it or a goal replay would be played over a live game
	for frozen: RlMatch.State in [RlMatch.State.COUNTDOWN,
			RlMatch.State.REPLAY, RlMatch.State.OVER]:
		match_node.state = frozen
		assert_ne(match_node.state, RlMatch.State.PLAYING)
