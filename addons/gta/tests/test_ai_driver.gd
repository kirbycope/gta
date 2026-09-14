extends GutTest

## Purpose: the opponent driver follows the arena's waypoints, joins and leaves
## a fight by range and how hurt it is, and never touches the handling model:
## everything it does reaches the car through [method Tm2Car.set_drive_input].

const TM2_CAR: PackedScene = preload("res://addons/gta/scenes/tm2_car.tscn")

var car: Tm2Car
var driver: AiDriver
var combat: CarCombat
var waypoints: Tm2Waypoints


func before_each() -> void:
	waypoints = Tm2Waypoints.new()
	waypoints.points = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(30, 0, 0), Vector3(30, 0, 30), Vector3(0, 0, 30),
	])
	car = TM2_CAR.instantiate()
	car.car = &"roadkill"
	(car.get_node(^"CarCombat") as CarCombat).car = &"roadkill"
	var d: AiDriver = car.get_node(^"AiDriver")
	d.enabled = true
	d.waypoints = waypoints
	add_child_autofree(car)
	driver = car.get_node(^"AiDriver")
	combat = car.get_node(^"CarCombat")
	await wait_physics_frames(2)


func test_an_enabled_driver_sets_off_toward_its_first_waypoint() -> void:
	# the car no longer needs telling that an AI has the wheel: its drivetrain runs from
	# whatever last filled the control pad, whoever that was
	await wait_physics_frames(6)
	assert_true(car._accelerate, "It should be on the throttle heading for a waypoint")


func test_it_starts_out_of_battle_with_nobody_to_fight() -> void:
	assert_eq(driver.state, AiDriver.State.OUT_OF_BATTLE)
	assert_null(driver.target, "There is no other car in this scene")


func test_it_drives_to_the_published_top_speed_for_its_car() -> void:
	assert_almost_eq(driver._top_speed, Tm2Roster.top_speed(&"roadkill"), 0.01)


func test_waypoints_find_the_nearest_point_and_wrap_round_the_ring() -> void:
	assert_eq(waypoints.nearest(Vector3(29, 0, 1)), 1)
	assert_eq(waypoints.next_index(3), 0, "The ring wraps")
	assert_eq(waypoints.next_index(0), 1)


func test_an_empty_waypoint_set_reports_no_point_rather_than_crashing() -> void:
	var empty: Tm2Waypoints = Tm2Waypoints.new()
	assert_eq(empty.nearest(Vector3.ZERO), -1)
	assert_eq(empty.random_index(), -1)
	assert_eq(empty.next_index(5), 0)


func test_a_hurt_car_needs_the_target_closer_before_it_commits() -> void:
	# AICarUpdateDrivingProfile reads the health tier; a healthy car engages
	# from further out than a wrecked one
	var healthy_tier: int = combat.health_tier()
	combat.take_hit(combat.max_health * 0.9)
	assert_gt(combat.health_tier(), healthy_tier,
		"Losing health raises the tier the engage range is divided by")


func test_a_dead_driver_brakes_and_stops_steering() -> void:
	combat.take_hit(1000.0)
	await wait_physics_frames(2)
	assert_true(combat.is_dead)
	assert_true(car.is_wrecked, "and the car knows it, through the scene's died connection")
	assert_eq(car._steer, 0.0, "A wrecked car does not keep steering")


func test_a_disabled_driver_leaves_the_car_alone() -> void:
	var parked: Tm2Car = TM2_CAR.instantiate()
	(parked.get_node(^"AiDriver") as AiDriver).enabled = false
	add_child_autofree(parked)
	await wait_physics_frames(3)
	assert_false(parked._accelerate, "A switched off driver leaves the throttle alone")
	assert_eq(parked._steer, 0.0, "and does not steer")
