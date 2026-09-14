extends GutTest

## Purpose: the Twisted Metal car. It is its own car on the shared [Vehicle] chassis rather than the
## road car with weapons bolted on, it drives to the published top speed for whoever it is and no
## further, turbo raises that ceiling while the meter lasts, and a wreck stops answering the
## controls.
##
## The one thing here that is a measurement rather than a rule is [method Tm2Car.forward]. This
## chassis drives along +Z, which is the opposite of Godot's usual convention, and every other part
## of the car is arranged around that: the model, the seat, the camera and both muzzles. So the test
## drives a car on a floor and checks it really does travel the way [method Tm2Car.forward] claims,
## because if that ever stops being true everything else quietly points backwards.

const TM2_CAR: PackedScene = preload("res://addons/gta/scenes/tm2_car.tscn")

var car: Tm2Car


func before_each() -> void:
	# a car with nothing under its wheels never drives, and most of this is about driving
	var ground: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(600.0, 1.0, 600.0)
	shape.shape = box
	ground.add_child(shape)
	ground.position = Vector3(0.0, -0.5, 0.0)
	add_child_autofree(ground)

	car = TM2_CAR.instantiate() as Tm2Car
	car.car = &"roadkill"
	(car.get_node(^"AiDriver") as AiDriver).enabled = false
	add_child_autofree(car)
	car.position = Vector3(0.0, 0.5, 0.0)
	await wait_physics_frames(4)


## Holds the throttle for [param frames] and gives back the speed along the nose.
func _drive_forward(frames: int, turbo: bool = false) -> float:
	for _i: int in frames:
		car.set_drive_input(true, false, turbo, 0.0)
		await wait_physics_frames(1)
	return car.forward_speed()


func test_it_is_its_own_car_on_the_shared_chassis() -> void:
	assert_true(car is Vehicle, "It sits on the chassis every car in the addon sits on")
	var chain: Array = []
	var step: Script = car.get_script()
	while step != null:
		chain.append(step.resource_path.get_file())
		step = step.get_base_script()
	assert_does_not_have(chain, "gta_car.gd",
		"A Twisted Metal car is not a Honda CR-V with a gun on it: %s" % [chain])
	assert_has(chain, "vehicle.gd")


func test_it_carries_the_rideable_contract() -> void:
	for method: String in ["mount", "dismount", "ride", "ride_input", "get_contextual_controls"]:
		assert_true(car.has_method(method), "A rideable needs %s()" % method)
	for property: String in ["seat", "camera", "blocks_hands", "disables_collision", "input_type"]:
		assert_true(property in car, "A rideable needs the %s property" % property)
	assert_not_null(car.seat, "The driver is hidden in here, so the Riding state pins them to the seat")
	assert_eq(car.mount_animation, "", "There is no door clip on a battle car")
	assert_true(car.hides_driver_model, "The ripped models have no cabin to seat anyone in")


func test_forward_is_the_way_the_wheels_actually_push_it() -> void:
	var heading_before: Vector3 = car.forward()
	var start: Vector3 = car.global_position
	await _drive_forward(60)
	var moved: Vector3 = car.global_position - start
	var flat: Vector3 = Vector3(moved.x, 0.0, moved.z)
	assert_gt(flat.length(), 1.0, "It should have gone somewhere")
	var flat_heading: Vector3 = Vector3(heading_before.x, 0.0, heading_before.z).normalized()
	assert_gt(flat.normalized().dot(flat_heading), 0.9,
		"forward() must be the direction a driven car travels, or the model, seat, camera and muzzles all point backwards")


func test_it_reaches_the_published_top_speed_for_its_car_and_no_further() -> void:
	var published: float = Tm2Roster.top_speed(&"roadkill")
	assert_almost_eq(car.speed_limit(), published, 0.01, "Roadkill's published top speed is the ceiling")
	var speed: float = await _drive_forward(420)
	assert_gt(speed, published * 0.75, "It should get most of the way there")
	assert_lt(speed, published * 1.1, "and it must not sail past the published figure")


func test_turbo_raises_the_ceiling_to_the_published_turbo_speed() -> void:
	assert_almost_eq(Tm2Roster.top_speed(&"roadkill", true), car._turbo_speed, 0.01)
	car.set_drive_input(true, false, true, 0.0)
	await wait_physics_frames(2)
	assert_true(car.is_turbo_engaged, "The button is down and the meter is full")
	assert_almost_eq(car.speed_limit(), Tm2Roster.top_speed(&"roadkill", true), 0.01,
		"The turbo ceiling is the published turbo speed")
	assert_gt(car.speed_limit(), Tm2Roster.top_speed(&"roadkill"), "which is faster than the ordinary one")


func test_the_turbo_meter_drains_while_it_is_held() -> void:
	watch_signals(car)
	assert_almost_eq(car.turbo, 1.0, 0.001, "It starts full")
	for _i: int in 40:
		car.set_drive_input(true, false, true, 0.0)
		await wait_physics_frames(1)
	assert_lt(car.turbo, 1.0, "Holding turbo spends the meter")
	assert_signal_emitted(car, "turbo_changed")


func test_the_meter_refills_on_its_own_the_way_the_game_does() -> void:
	car.turbo = 0.2
	var low: float = car.turbo
	for _i: int in 60:
		car.set_drive_input(false, false, false, 0.0)
		await wait_physics_frames(1)
	assert_gt(car.turbo, low, "Twisted Metal's turbo meter refills over time with the button off")
	assert_lte(car.turbo, 1.0, "and stops at full")


func test_an_empty_meter_will_not_engage() -> void:
	car.turbo = 0.0
	car.set_drive_input(true, false, true, 0.0)
	await wait_physics_frames(2)
	assert_false(car.is_turbo_engaged, "Nothing left to spend")
	assert_almost_eq(car.speed_limit(), Tm2Roster.top_speed(&"roadkill"), 0.01,
		"so the ceiling is the ordinary one")


func test_a_wreck_stops_answering_the_controls() -> void:
	watch_signals(car)
	var combat: CarCombat = car.get_node(^"CarCombat") as CarCombat
	combat.take_hit(10000.0)
	await wait_physics_frames(2)
	assert_true(car.is_wrecked, "Health running out wrecks the car")
	assert_signal_emitted(car, "wrecked")
	var speed: float = await _drive_forward(60)
	assert_lt(absf(speed), 1.0, "A wreck does not drive off")


func test_the_scene_wires_the_death_signal_to_the_car() -> void:
	# the connection lives in tm2_car.tscn rather than in _ready, which is the addon's rule
	var combat: CarCombat = car.get_node(^"CarCombat") as CarCombat
	assert_connected(combat, car, "died", "on_died")


func test_the_roster_key_names_the_car_in_both_places_it_matters() -> void:
	var minion: Tm2Car = TM2_CAR.instantiate() as Tm2Car
	minion.car = &"minion"
	(minion.get_node(^"CarCombat") as CarCombat).car = &"minion"
	(minion.get_node(^"AiDriver") as AiDriver).enabled = false
	add_child_autofree(minion)
	await wait_physics_frames(2)
	assert_almost_eq(minion.speed_limit(), Tm2Roster.top_speed(&"minion"), 0.01,
		"Minion is the fastest car in the roster and drives like it")
	assert_almost_eq((minion.get_node(^"CarCombat") as CarCombat).max_health, 230.0, 0.01,
		"and the toughest")
	assert_gt(minion.speed_limit(), car.speed_limit(), "Minion out-runs Roadkill, as published")


func test_braking_from_a_standstill_is_reverse() -> void:
	for _i: int in 90:
		car.set_drive_input(false, true, false, 0.0)
		await wait_physics_frames(1)
	assert_lt(car.forward_speed(), -0.5, "Holding brake at rest backs the car up")
	assert_gt(car.forward_speed(), -car.reverse_speed * 1.2, "but no faster than the reverse speed")


func test_steering_does_not_shrink_with_speed() -> void:
	# Twisted Metal's cars turn as hard flat out as they do at a crawl, which is most of
	# why the game feels the way it does
	for _i: int in 30:
		car.set_drive_input(false, false, false, 1.0)
		await wait_physics_frames(1)
	var at_rest: float = car.steering
	car.linear_velocity = car.forward() * 30.0
	for _i: int in 30:
		car.set_drive_input(true, false, false, 1.0)
		await wait_physics_frames(1)
	assert_almost_eq(car.steering, at_rest, 0.02, "The lock is the same at speed")
	assert_almost_eq(absf(at_rest), deg_to_rad(car.steering_lock), 0.02, "and it is the exported lock")
