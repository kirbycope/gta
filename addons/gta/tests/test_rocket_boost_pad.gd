extends GutTest

## Purpose: a pad gives the published amount, goes away for the published
## cooldown, and is not wasted on a car that is already full.
##
## That last rule is easy to miss and matters: in Rocket League a full car
## drives straight over a big pad and leaves it standing for a team mate.

const ROCKET_CAR: PackedScene = preload("res://addons/gta/scenes/rocket_car.tscn")
const BOOST_PAD: PackedScene = preload("res://addons/gta/scenes/rocket_boost_pad.tscn")

var pad: RocketBoostPad
var car: RocketCar


func before_each() -> void:
	pad = BOOST_PAD.instantiate()
	add_child_autofree(pad)
	car = ROCKET_CAR.instantiate()
	(car.get_node(^"RocketAi") as RocketAi).enabled = false
	add_child_autofree(car)
	# the pad is a real Area3D with its own body_entered wired up in the scene,
	# so a car left sitting on top of it collects it before the test starts;
	# every test below drives the pickup by hand instead
	pad.global_position = Vector3(0.0, 0.0, 60.0)
	car.global_position = Vector3(0.0, 0.0, -60.0)
	await wait_physics_frames(2)


func test_a_small_pad_is_worth_twelve_and_a_big_one_a_full_tank() -> void:
	pad.is_big = false
	assert_almost_eq(pad.amount(), RocketConst.PAD_BOOST_SMALL, 0.01, "BOOST_AMOUNT_SMALL")
	pad.is_big = true
	assert_almost_eq(pad.amount(), RocketConst.PAD_BOOST_BIG, 0.01, "BOOST_AMOUNT_BIG")


func test_a_pad_starts_available() -> void:
	assert_true(pad.is_available)


func test_driving_over_one_fills_the_car_and_takes_the_pad_away() -> void:
	pad.is_big = false
	car.refill_boost(20.0)
	watch_signals(pad)
	pad._on_body_entered(car)
	assert_almost_eq(car.boost, 32.0, 0.01, "Twenty plus a small pad's twelve")
	assert_false(pad.is_available)
	assert_false(pad.get_node(^"Mesh").visible, "A taken pad is not drawn")
	assert_signal_emitted(pad, "collected")


func test_a_big_pad_fills_the_tank_from_anywhere() -> void:
	pad.is_big = true
	car.refill_boost(3.0)
	pad._on_body_entered(car)
	assert_almost_eq(car.boost, RocketConst.BOOST_MAX, 0.01)


func test_a_full_car_leaves_the_pad_standing() -> void:
	pad.is_big = true
	car.refill_boost(RocketConst.BOOST_MAX)
	watch_signals(pad)
	pad._on_body_entered(car)
	assert_true(pad.is_available, "It is left for a team mate who needs it")
	assert_signal_emit_count(pad, "collected", 0)


func test_a_pad_already_taken_cannot_be_taken_again() -> void:
	car.refill_boost(0.0)
	pad._on_body_entered(car)
	car.refill_boost(0.0)
	watch_signals(pad)
	pad._on_body_entered(car)
	assert_signal_emit_count(pad, "collected", 0)
	assert_almost_eq(car.boost, 0.0, 0.01)


func test_a_wreck_cannot_pick_up_boost() -> void:
	car.refill_boost(0.0)
	car.demolish(null)
	watch_signals(pad)
	pad._on_body_entered(car)
	assert_signal_emit_count(pad, "collected", 0)
	assert_true(pad.is_available)


func test_anything_that_is_not_a_car_is_ignored() -> void:
	var passer_by: Node3D = Node3D.new()
	add_child_autofree(passer_by)
	watch_signals(pad)
	pad._on_body_entered(passer_by)
	assert_true(pad.is_available)
	assert_signal_emit_count(pad, "collected", 0)


func test_the_cooldown_matches_the_kind_of_pad() -> void:
	pad.is_big = true
	car.refill_boost(0.0)
	pad._on_body_entered(car)
	assert_almost_eq(pad.get_node(^"Cooldown").wait_time, RocketConst.PAD_COOLDOWN_BIG, 0.01,
		"COOLDOWN_BIG is ten seconds")


func test_a_small_pad_comes_back_sooner() -> void:
	pad.is_big = false
	car.refill_boost(0.0)
	pad._on_body_entered(car)
	assert_almost_eq(pad.get_node(^"Cooldown").wait_time, RocketConst.PAD_COOLDOWN_SMALL, 0.01,
		"COOLDOWN_SMALL is four seconds")


func test_the_cooldown_ending_puts_it_back() -> void:
	car.refill_boost(0.0)
	pad._on_body_entered(car)
	pad._on_cooldown_timeout()
	assert_true(pad.is_available)
	assert_true(pad.get_node(^"Mesh").visible)


func test_a_kickoff_puts_every_pad_back_at_once() -> void:
	car.refill_boost(0.0)
	pad._on_body_entered(car)
	pad.reset_pad()
	assert_true(pad.is_available)
	assert_true(pad.get_node(^"Cooldown").is_stopped(), "The cooldown is cancelled, not left running")
