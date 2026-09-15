extends GutTest

## Purpose: the soccar AI reaches its car only through the control pad, shares
## the three roles out on distance so a team rotates, aims its hits at the
## opponent's goal rather than at the ball, and knows when a pad is worth the
## detour.
##
## The point of the first test is the same one [code]test_ai_driver.gd[/code]
## makes about the Twisted Metal opponents: an AI that can only press the same
## buttons a person can cannot cheat, and that property is worth a test of its
## own rather than a comment.

const ROCKET_CAR: PackedScene = preload("res://addons/gta/rl/scenes/rl_car.tscn")
const ROCKET_BALL: PackedScene = preload("res://addons/gta/rl/scenes/rl_ball.tscn")

var ball: RlBall
var cars: Array[RlCar] = []


func before_each() -> void:
	cars = []
	ball = ROCKET_BALL.instantiate()
	add_child_autofree(ball)
	await wait_physics_frames(2)


## One car of [param team], parked at [param at] with its brain switched on.
func _add_car(team: RlCar.Team, at: Vector3) -> RlCar:
	var car: RlCar = ROCKET_CAR.instantiate()
	car.team = team
	var brain: RlAi = car.get_node(^"RlAi")
	brain.enabled = true
	add_child_autofree(car)
	car.place_at(at, 0.0)
	cars.append(car)
	return car


func _brain(car: RlCar) -> RlAi:
	return car.get_node(^"RlAi") as RlAi


func test_switching_the_brain_on_tells_the_car_an_ai_has_the_wheel() -> void:
	var car: RlCar = _add_car(RlCar.Team.BLUE, Vector3(0.0, 0.2, 20.0))
	await wait_physics_frames(2)
	assert_true(car.is_ai, "The car and its brain must agree about who is driving")


func test_switching_it_off_again_hands_the_car_back() -> void:
	var car: RlCar = _add_car(RlCar.Team.BLUE, Vector3(0.0, 0.2, 20.0))
	await wait_physics_frames(2)
	_brain(car).enabled = false
	assert_false(car.is_ai, "A kickoff countdown switches every brain off")


func test_a_lone_car_attacks() -> void:
	var car: RlCar = _add_car(RlCar.Team.BLUE, Vector3(0.0, 0.2, 20.0))
	await wait_physics_frames(4)
	assert_eq(_brain(car).role, RlAi.Role.ATTACK,
		"With nobody to rotate with there is only one job")


func test_the_nearer_car_takes_the_ball() -> void:
	ball.global_position = Vector3(0.0, 1.0, 0.0)
	var near: RlCar = _add_car(RlCar.Team.BLUE, Vector3(0.0, 0.2, 8.0))
	var far: RlCar = _add_car(RlCar.Team.BLUE, Vector3(0.0, 0.2, 44.0))
	await wait_physics_frames(6)
	assert_eq(_brain(near).role, RlAi.Role.ATTACK)
	assert_ne(_brain(far).role, RlAi.Role.ATTACK, "Two cars do not chase the same ball")


func test_the_deepest_of_three_defends() -> void:
	ball.global_position = Vector3(0.0, 1.0, -30.0)
	var first: RlCar = _add_car(RlCar.Team.BLUE, Vector3(0.0, 0.2, -20.0))
	var second: RlCar = _add_car(RlCar.Team.BLUE, Vector3(6.0, 0.2, 0.0))
	var third: RlCar = _add_car(RlCar.Team.BLUE, Vector3(-6.0, 0.2, -44.0))
	await wait_physics_frames(6)
	var roles: Array[int] = [_brain(first).role, _brain(second).role, _brain(third).role]
	assert_true(roles.has(RlAi.Role.ATTACK), "Somebody has to go for it")
	assert_true(roles.has(RlAi.Role.DEFEND), "And somebody has to stay home")


func test_the_roles_rotate_when_the_ball_moves() -> void:
	ball.global_position = Vector3(0.0, 1.0, 30.0)
	var one: RlCar = _add_car(RlCar.Team.BLUE, Vector3(0.0, 0.2, 34.0))
	var two: RlCar = _add_car(RlCar.Team.BLUE, Vector3(0.0, 0.2, -34.0))
	await wait_physics_frames(6)
	assert_eq(_brain(one).role, RlAi.Role.ATTACK)
	# send the ball to the other end; the other car is now the closer of the two
	ball.global_position = Vector3(0.0, 1.0, -30.0)
	await wait_physics_frames(6)
	assert_eq(_brain(two).role, RlAi.Role.ATTACK,
		"Roles follow the ball rather than being handed out once")


func test_an_opponent_is_never_counted_as_a_team_mate() -> void:
	ball.global_position = Vector3(0.0, 1.0, 0.0)
	var blue: RlCar = _add_car(RlCar.Team.BLUE, Vector3(0.0, 0.2, 30.0))
	_add_car(RlCar.Team.ORANGE, Vector3(0.0, 0.2, 2.0))
	await wait_physics_frames(6)
	assert_eq(_brain(blue).role, RlAi.Role.ATTACK,
		"A nearer orange car does not take blue's attacking job")


func test_it_aims_from_behind_the_ball_so_the_hit_goes_the_right_way() -> void:
	ball.global_position = Vector3(0.0, 1.0, 0.0)
	ball.linear_velocity = Vector3.ZERO
	var car: RlCar = _add_car(RlCar.Team.BLUE, Vector3(0.0, 0.2, 20.0))
	await wait_physics_frames(6)
	var strike: Vector3 = _brain(car)._strike_point()
	# blue attacks toward negative z, so the point to hit from is on the
	# positive z side of the ball
	assert_gt(strike.z, ball.global_position.z,
		"Driving straight at the ball puts it wherever the car was pointing")


func test_the_two_teams_aim_from_opposite_sides_of_the_ball() -> void:
	ball.global_position = Vector3(0.0, 1.0, 0.0)
	var blue: RlCar = _add_car(RlCar.Team.BLUE, Vector3(0.0, 0.2, 20.0))
	var orange: RlCar = _add_car(RlCar.Team.ORANGE, Vector3(0.0, 0.2, -20.0))
	await wait_physics_frames(6)
	var blue_strike: Vector3 = _brain(blue)._strike_point()
	var orange_strike: Vector3 = _brain(orange)._strike_point()
	assert_gt(blue_strike.z, 0.0)
	assert_lt(orange_strike.z, 0.0)


func test_a_demolished_car_stops_driving() -> void:
	var car: RlCar = _add_car(RlCar.Team.BLUE, Vector3(0.0, 0.2, 20.0))
	await wait_physics_frames(4)
	car.demolish(null)
	await wait_physics_frames(2)
	assert_almost_eq(car._throttle, 0.0, 0.01, "A wreck does not hold the throttle down")


func test_a_kickoff_is_recognised_by_the_ball_sitting_on_the_spot() -> void:
	# frozen rather than merely placed: this test has no floor under it, so an
	# unfrozen ball is already falling by the time the brains next think
	ball.freeze = true
	ball.global_position = Vector3(0.0, RlConst.BALL_REST_HEIGHT, 0.0)
	ball.linear_velocity = Vector3.ZERO
	var car: RlCar = _add_car(RlCar.Team.BLUE, Vector3(0.0, 0.2, 25.6))
	await wait_physics_frames(6)
	assert_true(_brain(car)._is_kickoff(), "Still, on the centre spot, is a kickoff")


func test_a_ball_in_play_is_not_a_kickoff() -> void:
	ball.global_position = Vector3(18.0, 2.0, -20.0)
	ball.linear_velocity = Vector3(6.0, 0.0, 3.0)
	var car: RlCar = _add_car(RlCar.Team.BLUE, Vector3(0.0, 0.2, 25.6))
	await wait_physics_frames(6)
	assert_false(_brain(car)._is_kickoff())


func test_it_will_not_detour_across_the_pitch_for_a_pad() -> void:
	var car: RlCar = _add_car(RlCar.Team.BLUE, Vector3(0.0, 0.2, 0.0))
	await wait_physics_frames(4)
	var pad: RlBoostPad = load("res://addons/gta/rl/scenes/rl_boost_pad.tscn").instantiate()
	pad.is_big = true
	add_child_autofree(pad)
	pad.global_position = Vector3(0.0, 0.0, 90.0)
	await wait_physics_frames(2)
	assert_null(_brain(car)._nearest_pad(),
		"A pad further than BOOST_HUNT_RANGE is not worth the drive")


func test_a_pad_on_cooldown_is_not_worth_driving_to() -> void:
	var car: RlCar = _add_car(RlCar.Team.BLUE, Vector3(0.0, 0.2, 0.0))
	await wait_physics_frames(4)
	var pad: RlBoostPad = load("res://addons/gta/rl/scenes/rl_boost_pad.tscn").instantiate()
	pad.is_big = true
	add_child_autofree(pad)
	pad.global_position = Vector3(0.0, 0.0, 10.0)
	await wait_physics_frames(2)
	assert_not_null(_brain(car)._nearest_pad(), "It is close enough while it is up")
	pad.is_available = false
	assert_null(_brain(car)._nearest_pad(), "And worth nothing while it is recharging")
