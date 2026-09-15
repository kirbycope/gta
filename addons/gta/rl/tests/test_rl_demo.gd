extends GutTest

## Purpose: the demo scene as a whole, rather than any one piece of it. The unit
## tests either build a match by hand out of bare nodes or drive a car with
## nothing around it; these load [code]rocket_league.tscn[/code] exactly as
## someone opening the project would, and let it play.
##
## Three things are worth an integration test. A match with nobody seated has to
## play itself out, which exercises the AI, the boost pads and the clock at
## once. A kickoff has to work, which is the one thing every game of soccar
## begins with. And a goal has to score, cut to the replay and come back to a
## kickoff, which is a chain of four systems that each pass their own unit tests
## and could still be wired up wrong between them.
##
## The driving tests press a real key rather than calling into the car. There
## is no [Player] in this demo: a [HumanDriver] under the person's car reads the
## buttons each frame and fills the pad, so pressing the key is the only way to
## prove that path works. With no joypad plugged in the driver reads the
## keyboard bindings, which is what a headless run has.
##
## Every test here rebuilds the whole demo and sits through a three second
## countdown, so they are deliberately few and each one checks a whole sequence
## rather than a single step.

const DEMO: PackedScene = preload("res://addons/gta/rl/scenes/demo.tscn")
const SETTLE_FRAMES: int = 8
const PATIENCE: float = 30.0 ## Seconds any wait_until is allowed before it gives up.

var match_node: RlMatch
var held_action: StringName = &""
var _boost_last: Dictionary = {} ## Car to the last tank reading, for spotting a burn.
var _saw_boost_burned: bool = false


func before_each() -> void:
	_boost_last.clear()
	_saw_boost_burned = false


func after_each() -> void:
	# a key left down would still be down in the next test
	_release()


## Build the demo the way opening the scene does. [param seated] false makes
## every car an AI's, including the one the player would otherwise drive.
func _start_match(seated: bool, minutes: float = 5.0) -> void:
	match_node = DEMO.instantiate()
	match_node.seat_player = seated
	match_node.match_minutes = minutes
	add_child_autofree(match_node)
	# the match waits a physics frame of its own before it builds the teams
	await wait_physics_frames(SETTLE_FRAMES)


func _wait_for_play() -> void:
	await wait_until(func() -> bool: return match_node.state == RlMatch.State.PLAYING,
		PATIENCE, "The kickoff countdown should hand over to a live game")


## Take every brain off the field so the test is the only thing driving. The
## match only reassigns brains when the state changes, so they stay off until
## the next kickoff, which is exactly as long as these tests need.
func _all_brains_off() -> void:
	for car: RlCar in match_node.cars:
		var brain: RlAi = car.get_node_or_null(^"RlAi") as RlAi
		if brain != null:
			brain.enabled = false
		car.release_controls()


## Hold the accelerate key down, as a person would.
func _press_accelerate() -> void:
	held_action = match_node.player_car.keyboard_accelerate_action
	# the driver picked the keyboard bindings, having found no joypad; said again
	# here so a CI runner with a phantom pad cannot turn space into a jump
	match_node.player_car.input_type = Controls.InputType.KEYBOARD_MOUSE
	Input.action_press(held_action)


func _release() -> void:
	if held_action != &"" and InputMap.has_action(held_action):
		Input.action_release(held_action)
	held_action = &""


## Put the ball in the mouth of orange's goal with the player's car behind it,
## pointed at the line. The opening position for every goal test below.
func _line_up_a_tap_in() -> RlCar:
	var car: RlCar = match_node.player_car
	match_node.ball.reset_to(Vector3(0.0, RlConst.BALL_REST_HEIGHT, -48.0))
	car.place_at(Vector3(0.0, RlConst.CAR_REST_HEIGHT, -44.0), PI)
	await wait_physics_frames(SETTLE_FRAMES)
	return car


# ------------------------------------------------- an AI match plays out -----

func test_with_nobody_seated_every_car_is_an_ai() -> void:
	await _start_match(false)
	assert_null(match_node.player_car, "There is no car held back for a person")
	assert_eq(match_node.cars.size(), 6, "Three a side is six cars")
	await _wait_for_play()
	for car: RlCar in match_node.cars:
		assert_true(car.is_ai, "%s should be driving itself" % car.name)
		assert_null(car.get_node_or_null(^"HumanDriver"), "and nobody has a hand on %s" % car.name)


## There is no Player in this demo. A person is a [HumanDriver] under one blue
## car, with nothing seated and nothing to get out of, which is why the space
## bar cannot put you on the pitch on foot the way it once did.
func test_seating_a_person_puts_a_driver_on_one_blue_car_and_no_body_in_it() -> void:
	await _start_match(true)
	assert_null(match_node.get_node_or_null(^"Player"), "No Player node anywhere in the demo")
	var car: RlCar = match_node.player_car
	assert_not_null(car, "One car is held back for the person")
	assert_eq(car.team, RlCar.Team.BLUE)
	var driver: HumanDriver = car.get_node_or_null(^"HumanDriver") as HumanDriver
	assert_not_null(driver, "and it has a HumanDriver under it")
	assert_false(car.is_ai)
	assert_false((car.get_node(^"RlAi") as RlAi).enabled, "Its brain is off")
	assert_true(car.camera.current, "The car's chase camera is the view")
	assert_true(car.is_ball_cam, "and it opened in ball cam, the way a kickoff does")
	for other: RlCar in match_node.cars:
		if other != car:
			assert_null(other.get_node_or_null(^"HumanDriver"), "%s is nobody's" % other.name)
	assert_false(driver.enabled, "Nobody drives during the countdown")
	await _wait_for_play()
	assert_true(driver.enabled, "The whistle hands over the pad")


## The bug this pins: with the yaw conversion a half turn out, every kickoff
## faced away from the ball, the ball cam sat in front of the nose, and pressing
## accelerate drove the car into the camera with the steering mirrored.
func test_every_car_faces_the_ball_at_kickoff() -> void:
	await _start_match(true)
	for car: RlCar in match_node.cars:
		var to_ball: Vector3 = match_node.ball.global_position - car.global_position
		to_ball.y = 0.0
		var facing: float = to_ball.normalized().dot(car.nose())
		assert_gt(facing, 0.7, "%s should be nosed at the ball, not away from it (dot %.2f)" % [car.name, facing])
	# and the camera is behind the person's car, on the far side from the ball
	var cam: Camera3D = match_node.player_car.camera
	var behind: Vector3 = cam.global_position - match_node.player_car.global_position
	behind.y = 0.0
	assert_lt(behind.normalized().dot(match_node.player_car.nose()), -0.5,
		"The chase camera sits behind the nose, not in front of it")


func test_an_ai_match_plays_itself_out() -> void:
	await _start_match(false)
	await _wait_for_play()
	_watch_boost()

	# the ball starts dead on the centre spot, so any real distance is the
	# opponents having gone and done something with it
	await wait_until(func() -> bool: return match_node.ball.global_position.length() > 8.0,
		PATIENCE, "The opponents should get to the ball and move it")
	assert_gt(match_node.ball.global_position.length(), 8.0, "The ball is in play")
	assert_not_null(match_node.ball.last_touch(), "And somebody hit it")

	await wait_until(_a_pad_has_been_taken, PATIENCE, "Somebody should drive over a boost pad")
	assert_true(_a_pad_has_been_taken(), "Pads get picked up during a match")

	await wait_until(func() -> bool: return _saw_boost_burned, PATIENCE,
		"Somebody should burn boost rather than hoarding it")
	assert_true(_saw_boost_burned, "The AI spends its tank")


func test_a_level_match_reaches_full_time_and_goes_to_overtime() -> void:
	# a six second clock, so regulation runs out inside the test rather than in
	# five minutes; everything else is the demo exactly as it ships
	await _start_match(false, 0.1)
	await _wait_for_play()
	await wait_until(_regulation_is_over, PATIENCE,
		"The clock should run out and the match should resolve")
	assert_almost_eq(match_node.clock, 0.0, 1.0, "Regulation ended at zero")
	if match_node.state != RlMatch.State.OVER:
		assert_true(match_node.is_overtime, "Level at full time is overtime, not a draw")


# --------------------------------------------------------- the kickoff -----

func test_driving_forward_off_the_kickoff_hits_the_ball_downfield() -> void:
	await _start_match(true)
	await _wait_for_play()
	assert_not_null(match_node.player_car, "One blue car is held back for the person")
	assert_false(match_node.player_car.is_ai)
	assert_null(match_node.player_car.player, "Nobody is seated: the person is a HumanDriver on the pad")
	assert_not_null(match_node.player_car.get_node_or_null(^"HumanDriver"))

	_all_brains_off()
	# the classic opener: square on to the ball, pointed at the other goal
	var car: RlCar = match_node.player_car
	car.place_at(Vector3(0.0, RlConst.CAR_REST_HEIGHT, 8.0), PI)
	match_node.ball.reset_to(RlMatch.CENTRE_SPOT)
	await wait_physics_frames(SETTLE_FRAMES)
	assert_almost_eq(car.nose().z, -1.0, 0.01, "Blue attacks along negative z")

	_press_accelerate()
	await wait_until(func() -> bool: return match_node.ball.linear_velocity.length() > 2.0,
		PATIENCE, "The car should reach the ball and hit it")

	assert_gt(car.linear_velocity.length(), 1.0, "The key press reached the car")
	assert_eq(match_node.ball.last_touch(), car, "The player's own car gets the touch")
	assert_lt(match_node.ball.linear_velocity.z, 0.0,
		"A hit off the kickoff sends the ball at the opponent's goal")


# ------------------------------------------------ a goal, and what follows -----

func test_nudging_the_ball_over_the_line_scores() -> void:
	await _start_match(true)
	await _wait_for_play()
	_all_brains_off()
	watch_signals(match_node)
	await _line_up_a_tap_in()
	assert_eq(match_node.blue_score, 0, "Nothing scored yet")

	_press_accelerate()
	await wait_until(func() -> bool: return match_node.blue_score > 0, PATIENCE,
		"Pushing the ball over the line should score")

	assert_eq(match_node.blue_score, 1, "Into orange's net is blue's goal")
	assert_eq(match_node.orange_score, 0, "And not anybody else's")
	assert_signal_emitted(match_node, "goal_scored")
	assert_signal_emitted(match_node, "score_changed")


func test_a_goal_cuts_to_the_replay_and_comes_back_to_a_kickoff() -> void:
	await _start_match(true)
	await _wait_for_play()
	_all_brains_off()
	var car: RlCar = await _line_up_a_tap_in()
	car.refill_boost(0.0)
	assert_false(match_node.replay_camera.current, "The chase camera has the view during play")

	_press_accelerate()
	await wait_until(func() -> bool: return match_node.state == RlMatch.State.REPLAY,
		PATIENCE, "A goal should cut to the replay")
	_release()

	assert_true(match_node.replay_camera.current, "The replay camera takes the view")
	assert_true(match_node.replay.is_playing, "And the buffer is playing back")
	# the arena is a closed box, so a camera outside it films the back of a wall
	var eye: Vector3 = match_node.replay_camera.global_position
	assert_lt(absf(eye.x), RlConst.ARENA_EXTENT_X, "The replay camera is inside the side walls")
	assert_lt(absf(eye.z), RlConst.ARENA_EXTENT_Y, "And inside the back walls")
	assert_between(eye.y, 0.0, RlConst.ARENA_HEIGHT, "And under the roof")
	assert_lt(eye.z, 0.0, "It watches the end that was scored in")
	assert_true(_has_line_of_sight(eye, match_node.replay_pivot.global_position),
		"Nothing should be standing between the replay camera and the goal")

	await wait_until(func() -> bool: return match_node.state == RlMatch.State.COUNTDOWN,
		PATIENCE, "The replay should end on a kickoff")

	assert_false(match_node.replay.is_playing)
	assert_false(match_node.replay_camera.current, "The view goes back to the car")
	assert_almost_eq(match_node.ball.global_position.x, 0.0, 1.0,
		"The ball is back on the centre spot")
	assert_almost_eq(match_node.ball.global_position.z, 0.0, 1.0)
	assert_almost_eq(car.boost, RlConst.BOOST_START, 0.1,
		"Every kickoff hands out a third of a tank")
	assert_eq(match_node.blue_score, 1, "The goal still counts after the reset")


# ----------------------------------------------------------- the helpers -----

## Can [param from] actually see [param to], or is there arena in the way? The
## cars and the ball are excluded the same way the spring arm excludes them,
## since something crossing the shot is the replay rather than an obstruction.
func _has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = match_node.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var skip: Array[RID] = []
	for car: RlCar in match_node.cars:
		skip.append(car.get_rid())
	skip.append(match_node.ball.get_rid())
	query.exclude = skip
	return space.intersect_ray(query).is_empty()


## Regulation time is done either way: level goes to overtime, a lead ends it.
func _regulation_is_over() -> bool:
	return match_node.is_overtime or match_node.state == RlMatch.State.OVER


func _a_pad_has_been_taken() -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"rl_boost_pads"):
		if not (node as RlBoostPad).is_available:
			return true
	return false


## Listen to every tank rather than sampling them. A car that boosts and then
## drives over a big pad is back above where it started, so comparing against
## the kickoff amount would miss it; a drop between two readings cannot be
## anything but boosting.
func _watch_boost() -> void:
	for car: RlCar in match_node.cars:
		_boost_last[car] = car.boost
		car.boost_changed.connect(_on_any_boost_changed.bind(car))


func _on_any_boost_changed(amount: float, _maximum: float, car: RlCar) -> void:
	if amount < (_boost_last.get(car, 0.0) as float) - 0.01:
		_saw_boost_burned = true
	_boost_last[car] = amount
