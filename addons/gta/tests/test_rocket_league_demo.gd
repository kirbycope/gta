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
## The driving tests press a real key rather than calling into the car. The
## seated [Player] reads its own buttons in [method RocketCar.ride], so pressing
## the key is the only way to prove that path works. Headless Godot reports its
## input device as touch, having seen no keyboard, so the car is told its driver
## is on one before the key goes down.
##
## Every test here rebuilds the whole demo and sits through a three second
## countdown, so they are deliberately few and each one checks a whole sequence
## rather than a single step.

const DEMO: PackedScene = preload("res://addons/gta/scenes/demo/rocket_league.tscn")
const SETTLE_FRAMES: int = 8
const PATIENCE: float = 30.0 ## Seconds any wait_until is allowed before it gives up.

var match_node: RocketMatch
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
	await wait_until(func() -> bool: return match_node.state == RocketMatch.State.PLAYING,
		PATIENCE, "The kickoff countdown should hand over to a live game")


## Take every brain off the field so the test is the only thing driving. The
## match only reassigns brains when the state changes, so they stay off until
## the next kickoff, which is exactly as long as these tests need.
func _all_brains_off() -> void:
	for car: RocketCar in match_node.cars:
		var brain: RocketAi = car.get_node_or_null(^"RocketAi") as RocketAi
		if brain != null:
			brain.enabled = false
		car.release_controls()


## Hold the accelerate key down, as a person would.
func _press_accelerate() -> void:
	held_action = match_node.player_car.keyboard_accelerate_action
	# headless has seen no keyboard and calls itself a touch device, so the car
	# would otherwise resolve the gamepad binding instead of this one
	match_node.player_car.input_type = Controls.InputType.KEYBOARD_MOUSE
	Input.action_press(held_action)


func _release() -> void:
	if held_action != &"" and InputMap.has_action(held_action):
		Input.action_release(held_action)
	held_action = &""


## Put the ball in the mouth of orange's goal with the player's car behind it,
## pointed at the line. The opening position for every goal test below.
func _line_up_a_tap_in() -> RocketCar:
	var car: RocketCar = match_node.player_car
	match_node.ball.reset_to(Vector3(0.0, RocketConst.BALL_REST_HEIGHT, -48.0))
	car.place_at(Vector3(0.0, RocketConst.CAR_REST_HEIGHT, -44.0), PI)
	await wait_physics_frames(SETTLE_FRAMES)
	return car


# ------------------------------------------------- an AI match plays out -----

func test_with_nobody_seated_every_car_is_an_ai_and_the_player_stands_down() -> void:
	await _start_match(false)
	assert_null(match_node.player_car, "There is no car held back for a person")
	assert_eq(match_node.cars.size(), 6, "Three a side is six cars")
	var player: Node3D = match_node.get_node_or_null(^"Player") as Node3D
	assert_not_null(player)
	assert_false(player.visible,
		"A match nobody is playing should not have someone stood on the halfway line")
	await _wait_for_play()
	for car: RocketCar in match_node.cars:
		assert_true(car.is_ai, "%s should be driving itself" % car.name)


## The battle car sits on the same [Vehicle] chassis as the road car, so getting into one hands its
## multiplayer authority to the driver's peer exactly as getting into the CR-V does. Nothing in the
## match rules asks for that; it arrives with the chassis, which is the point of testing it here.
func test_getting_into_a_battle_car_hands_it_to_the_driver_s_peer() -> void:
	await _start_match(true)
	var player: Player = match_node.get_node(^"Player") as Player
	assert_not_null(match_node.player_car, "A seated match keeps one car for the person")
	assert_eq(match_node.player_car.current_driver_peer_id, player.get_multiplayer_authority(),
		"The car is the driver's while they are in it")
	assert_eq(match_node.player_car.get_multiplayer_authority(), player.get_multiplayer_authority())
	for car: RocketCar in match_node.cars:
		if car == match_node.player_car:
			continue
		assert_eq(car.current_driver_peer_id, Vehicle.SERVER_PEER,
			"%s has nobody in it, so it stays the server's" % car.name)


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
	if match_node.state != RocketMatch.State.OVER:
		assert_true(match_node.is_overtime, "Level at full time is overtime, not a draw")


# --------------------------------------------------------- the kickoff -----

func test_driving_forward_off_the_kickoff_hits_the_ball_downfield() -> void:
	await _start_match(true)
	await _wait_for_play()
	assert_not_null(match_node.player_car, "One blue car is held back for the person")
	assert_false(match_node.player_car.is_ai)
	assert_eq(match_node.player_car.player, match_node.get_node(^"Player"),
		"The Player is at the wheel, the way the Twisted Metal demo seats them")
	assert_true(match_node.player_car.hides_driver_model, "And not drawn while they are")

	_all_brains_off()
	# the classic opener: square on to the ball, pointed at the other goal
	var car: RocketCar = match_node.player_car
	car.place_at(Vector3(0.0, RocketConst.CAR_REST_HEIGHT, 8.0), PI)
	match_node.ball.reset_to(RocketMatch.CENTRE_SPOT)
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
	var car: RocketCar = await _line_up_a_tap_in()
	car.refill_boost(0.0)
	assert_false(match_node.replay_camera.current, "The chase camera has the view during play")

	_press_accelerate()
	await wait_until(func() -> bool: return match_node.state == RocketMatch.State.REPLAY,
		PATIENCE, "A goal should cut to the replay")
	_release()

	assert_true(match_node.replay_camera.current, "The replay camera takes the view")
	assert_true(match_node.replay.is_playing, "And the buffer is playing back")
	# the arena is a closed box, so a camera outside it films the back of a wall
	var eye: Vector3 = match_node.replay_camera.global_position
	assert_lt(absf(eye.x), RocketConst.ARENA_EXTENT_X, "The replay camera is inside the side walls")
	assert_lt(absf(eye.z), RocketConst.ARENA_EXTENT_Y, "And inside the back walls")
	assert_between(eye.y, 0.0, RocketConst.ARENA_HEIGHT, "And under the roof")
	assert_lt(eye.z, 0.0, "It watches the end that was scored in")
	assert_true(_has_line_of_sight(eye, match_node.replay_pivot.global_position),
		"Nothing should be standing between the replay camera and the goal")

	await wait_until(func() -> bool: return match_node.state == RocketMatch.State.COUNTDOWN,
		PATIENCE, "The replay should end on a kickoff")

	assert_false(match_node.replay.is_playing)
	assert_false(match_node.replay_camera.current, "The view goes back to the car")
	assert_almost_eq(match_node.ball.global_position.x, 0.0, 1.0,
		"The ball is back on the centre spot")
	assert_almost_eq(match_node.ball.global_position.z, 0.0, 1.0)
	assert_almost_eq(car.boost, RocketConst.BOOST_START, 0.1,
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
	for car: RocketCar in match_node.cars:
		skip.append(car.get_rid())
	skip.append(match_node.ball.get_rid())
	query.exclude = skip
	return space.intersect_ray(query).is_empty()


## Regulation time is done either way: level goes to overtime, a lead ends it.
func _regulation_is_over() -> bool:
	return match_node.is_overtime or match_node.state == RocketMatch.State.OVER


func _a_pad_has_been_taken() -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"rocket_boost_pads"):
		if not (node as RocketBoostPad).is_available:
			return true
	return false


## Listen to every tank rather than sampling them. A car that boosts and then
## drives over a big pad is back above where it started, so comparing against
## the kickoff amount would miss it; a drop between two readings cannot be
## anything but boosting.
func _watch_boost() -> void:
	for car: RocketCar in match_node.cars:
		_boost_last[car] = car.boost
		car.boost_changed.connect(_on_any_boost_changed.bind(car))


func _on_any_boost_changed(amount: float, _maximum: float, car: RocketCar) -> void:
	if amount < (_boost_last.get(car, 0.0) as float) - 0.01:
		_saw_boost_burned = true
	_boost_last[car] = amount
