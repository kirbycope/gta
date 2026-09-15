extends GutTest

## Purpose: the ball is the published size and weight, keeps its speed and spin
## inside the caps the game enforces, and predicts where it will be well enough
## for the AI to drive at.
##
## The prediction is the part worth guarding. Every attacking decision
## [RlAi] makes is built on it, and it is deliberately a simplification:
## flat walls, no corners, no cars. These tests hold it to what it does claim.

const ROCKET_BALL: PackedScene = preload("res://addons/gta/rl/scenes/rl_ball.tscn")

var ball: RlBall


func before_each() -> void:
	ball = ROCKET_BALL.instantiate()
	add_child_autofree(ball)
	await wait_physics_frames(2)


func test_the_ball_is_the_published_size_and_weight() -> void:
	assert_almost_eq(ball.mass, RlConst.BALL_MASS, 0.01, "BALL_MASS_BT is a sixth of a car")
	var shape: CollisionShape3D = ball.get_node(^"CollisionShape3D")
	var sphere: SphereShape3D = shape.shape as SphereShape3D
	assert_almost_eq(sphere.radius, RlConst.BALL_RADIUS, 0.001, "91.25 uu")


func test_drag_is_set_the_way_rocket_league_models_it() -> void:
	assert_eq(ball.linear_damp_mode, RigidBody3D.DAMP_MODE_REPLACE,
		"The project's own damping must not be added on top")
	assert_almost_eq(ball.linear_damp, RlConst.BALL_DRAG, 0.0001)


func test_it_bounces_at_sixty_percent() -> void:
	assert_almost_eq(ball.physics_material_override.bounce, RlConst.BALL_RESTITUTION, 0.001)
	assert_almost_eq(ball.physics_material_override.friction, RlConst.BALL_FRICTION, 0.001)


func test_speed_is_capped_at_the_published_maximum() -> void:
	ball.linear_velocity = Vector3(500.0, 500.0, 500.0)
	await wait_physics_frames(3)
	assert_lte(ball.linear_velocity.length(), RlConst.BALL_MAX_SPEED + 0.5,
		"BALL_MAX_SPEED is 6000 uu/s")


func test_spin_is_capped_at_the_published_maximum() -> void:
	ball.angular_velocity = Vector3(80.0, 80.0, 80.0)
	await wait_physics_frames(3)
	assert_lte(ball.angular_velocity.length(), RlConst.BALL_MAX_ANGULAR + 0.2,
		"BALL_MAX_ANG_SPEED is 6 radians a second")


func test_a_reset_puts_it_somewhere_still() -> void:
	ball.linear_velocity = Vector3(30.0, 12.0, -8.0)
	ball.angular_velocity = Vector3(4.0, 1.0, 2.0)
	ball.reset_to(Vector3(0.0, RlConst.BALL_REST_HEIGHT, 0.0))
	await wait_physics_frames(2)
	assert_almost_eq(ball.linear_velocity.length(), 0.0, 0.5)
	assert_almost_eq(ball.angular_velocity.length(), 0.0, 0.5)
	assert_null(ball.last_touch(), "A kickoff ball has not been touched by anyone")


func test_predicting_no_time_ahead_gives_where_it_is_now() -> void:
	ball.global_position = Vector3(4.0, 6.0, -9.0)
	await wait_physics_frames(1)
	var guess: Vector3 = ball.predict(0.0)
	assert_almost_eq(guess.x, 4.0, 0.01)
	assert_almost_eq(guess.z, -9.0, 0.01)


func test_a_ball_in_the_air_is_predicted_to_fall() -> void:
	ball.freeze = true
	ball.global_position = Vector3(0.0, 12.0, 0.0)
	ball.linear_velocity = Vector3.ZERO
	await wait_physics_frames(1)
	var guess: Vector3 = ball.predict(0.5)
	assert_lt(guess.y, 12.0, "Gravity is 650 uu/s^2 and it applies to the prediction too")
	# free fall under 6.5 m/s^2 for half a second is about 0.81 m, less a little drag
	assert_almost_eq(guess.y, 12.0 - 0.81, 0.15)


func test_the_prediction_never_leaves_the_floor_or_the_ceiling() -> void:
	ball.freeze = true
	ball.global_position = Vector3(0.0, 3.0, 0.0)
	ball.linear_velocity = Vector3(0.0, -40.0, 0.0)
	await wait_physics_frames(1)
	for ahead: float in [0.5, 1.0, 2.0, 4.0]:
		var guess: Vector3 = ball.predict(ahead)
		assert_gte(guess.y, RlConst.BALL_RADIUS - 0.01,
			"The ball cannot be predicted through the floor, at %s seconds" % ahead)
		assert_lte(guess.y, RlConst.ARENA_HEIGHT, "Nor through the roof")


func test_the_prediction_keeps_the_ball_inside_the_side_walls() -> void:
	ball.freeze = true
	ball.global_position = Vector3(0.0, 5.0, 0.0)
	ball.linear_velocity = Vector3(50.0, 0.0, 0.0)
	await wait_physics_frames(1)
	for ahead: float in [0.5, 1.0, 2.0, 3.0]:
		var guess: Vector3 = ball.predict(ahead)
		assert_lte(absf(guess.x), RlConst.ARENA_EXTENT_X + 0.01,
			"A ball driven at the wall bounces off it, at %s seconds" % ahead)


func test_the_prediction_lets_a_ball_through_the_goal_mouth() -> void:
	# the back wall only exists outside the posts, or a shot on target would be
	# predicted to bounce out and the AI would never defend it
	ball.freeze = true
	ball.global_position = Vector3(0.0, 1.0, 40.0)
	ball.linear_velocity = Vector3(0.0, 0.0, 40.0)
	await wait_physics_frames(1)
	var guess: Vector3 = ball.predict(1.0)
	assert_gt(guess.z, RlConst.ARENA_EXTENT_Y,
		"Between the posts there is nothing to bounce off")


func test_the_prediction_is_capped_rather_than_running_forever() -> void:
	ball.freeze = true
	ball.global_position = Vector3(0.0, 5.0, 0.0)
	ball.linear_velocity = Vector3(3.0, 0.0, 0.0)
	await wait_physics_frames(1)
	var far: Vector3 = ball.predict(60.0)
	var capped: Vector3 = ball.predict(RlBall.PREDICT_MAX_TIME)
	assert_almost_eq(far.x, capped.x, 0.01, "Asking further ahead than the cap gives the cap")
