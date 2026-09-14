extends GutTest

## Purpose: [Vehicle], the chassis the addon's three cars are built on, and the
## things it deliberately does not bring with it.
##
## It holds the wheels, the rideable contract and the multiplayer hand-off, and
## no handling model at all. The car under test here is the Rocket League one,
## because it is the lightest car in the addon to stand up, but nothing asserted
## below is particular to it.
##
## The split is worth holding onto. Every car used to be the road car: the
## battle car extended it to borrow a raycast body, four wheels and the rideable
## contract, and inherited a gearbox, a damage model and a radio along with them.
## One piece of that was quietly fatal, because the engine audio only ever ran
## for a car driven through the road car's own drive input, which a battle car
## never calls, so every battle car was silent.

const ROCKET_CAR: PackedScene = preload("res://addons/gta/scenes/rocket_car.tscn")
const PLAYER: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")

var car: RocketCar


func before_each() -> void:
	car = ROCKET_CAR.instantiate()
	(car.get_node(^"RocketAi") as RocketAi).enabled = false
	add_child_autofree(car)
	await wait_physics_frames(2)


func test_a_battle_car_is_a_chassis_and_not_the_road_car() -> void:
	assert_true(car is Vehicle, "Every car in the addon is one of these")
	# `car is GtaCar` will not even compile, which is the strongest form this
	# could take, so the chain is walked instead to say it out loud
	var chain: Array = []
	var step: Script = car.get_script()
	while step != null:
		chain.append(step.resource_path.get_file())
		step = step.get_base_script()
	assert_does_not_have(chain, "gta_car.gd",
		"The road car's gearbox, damage model and radio are nowhere in %s" % [chain])
	assert_has(chain, "vehicle.gd", "The chassis is")


func test_it_carries_the_rideable_contract_the_riding_state_looks_for() -> void:
	# the state is duck typed, so a missing name is a silent failure to mount
	for method: String in ["mount", "dismount", "ride", "ride_input", "get_contextual_controls"]:
		assert_true(car.has_method(method), "A rideable needs %s()" % method)
	for property: String in ["seat", "camera", "blocks_hands", "disables_collision",
			"mount_animation", "dismount_animation", "input_type"]:
		assert_true(property in car, "A rideable needs the %s property" % property)


func test_the_seat_is_a_node_the_rider_can_be_pinned_to() -> void:
	assert_not_null(car.seat, "The Riding state pins the rider here every frame")
	assert_true(car.seat is Node3D)


func test_getting_in_is_instant_because_a_battle_car_has_no_door() -> void:
	assert_eq(car.mount_animation, "", "No get-in clip, so the Riding state plays none")
	assert_eq(car.dismount_animation, "")


func test_the_camera_is_the_chase_camera_s_own() -> void:
	assert_not_null(car.chase_camera)
	assert_not_null(car.camera, "The Riding state makes this current while ridden")
	assert_eq(car.camera, car.chase_camera.camera)


func test_the_chassis_carries_no_handling_model_of_its_own() -> void:
	# a car built straight on the chassis has none of the road car's handling,
	# because none of it is on the chassis to inherit
	for handling: String in ["max_acceleration_force", "drive_bias_front", "traction_curve_min",
			"max_steering_angle", "current_gear", "radio_station", "driving_ui"]:
		assert_false(handling in car, "%s is a road car's, not the chassis's" % handling)


func test_it_does_not_drag_a_road_car_s_apparatus_along_with_it() -> void:
	# the CR-V brought a speedometer, a first person camera, a door animation,
	# an action prompt, a detection area and seven timers to every battle car
	for gone: String in ["DrivingUI", "FirstPersonCamera", "PlayerDetection", "ActionPrompt",
			"AnimationPlayer", "FlippedTimer", "FireTimer", "ClutchTimer", "Root Scene"]:
		assert_null(car.get_node_or_null(NodePath(gone)),
			"%s belongs to the GTA car, not a battle car" % gone)


func test_every_car_carries_its_own_sound() -> void:
	# this is the one the old arrangement got wrong: a battle car never called
	# set_drive_input, so Vehicle's engine audio stopped itself every frame and
	# the cars made no noise at all
	for named: String in ["SFXBoost", "SFXJump", "SFXImpact"]:
		var player: AudioStreamPlayer3D = car.get_node_or_null(NodePath(named)) as AudioStreamPlayer3D
		assert_not_null(player, "%s should be on the car" % named)
		assert_not_null(player.stream, "%s should have something to play" % named)


func test_the_boost_note_follows_the_tank() -> void:
	car.refill_boost(RocketConst.BOOST_MAX)
	for _i: int in 6:
		car.set_rocket_input(0.0, 0.0, 0.0, 0.0, 0.0, false, true, false)
		await wait_physics_frames(1)
	assert_true(car.sfx_boost.playing, "Holding boost should be heard")
	car.refill_boost(0.0)
	for _i: int in 20:
		car.release_controls()
		await wait_physics_frames(1)
	assert_false(car.sfx_boost.playing, "And an empty tank should go quiet")


func test_a_car_bounces_off_the_world_the_way_rocket_league_says() -> void:
	# the CR-V's material had bounce zero, so nothing rebounded off anything
	var material: PhysicsMaterial = car.physics_material_override
	assert_not_null(material)
	assert_almost_eq(material.bounce, RocketConst.WORLD_RESTITUTION, 0.01,
		"CARWORLD_COLLISION_RESTITUTION is 0.3")
	assert_almost_eq(material.friction, RocketConst.WORLD_FRICTION, 0.01,
		"CARWORLD_COLLISION_FRICTION is 0.3")


func test_the_chassis_counts_wheels_rather_than_answering_yes_or_no() -> void:
	assert_eq(car.wheels.size(), 4)
	assert_eq(car.wheels_in_contact(), 0, "Nothing under it in this test scene")


func test_drive_and_brake_are_shared_across_the_wheels() -> void:
	# setting the whole brake on each of four was four times the braking asked
	# for, and Godot's wheel brake creeps a standing car in proportion to it
	car.apply_wheel_forces(400.0, 800.0)
	var driven: int = 0
	for wheel: VehicleWheel3D in car.wheels:
		if wheel.use_as_traction:
			driven += 1
		assert_almost_eq(wheel.brake, 800.0 / 4.0, 0.01, "The brake is split four ways")
	assert_eq(driven, 4, "All four drive")
	for wheel: VehicleWheel3D in car.wheels:
		assert_almost_eq(wheel.engine_force, 400.0 / float(driven), 0.01,
			"And the drive is split across the driven wheels")


func test_the_body_holds_no_force_of_its_own() -> void:
	car.apply_wheel_forces(400.0, 800.0)
	assert_almost_eq(car.engine_force, 0.0, 0.001,
		"Godot adds the body's own force to each wheel's, so the body holds none")
	assert_almost_eq(car.brake, 0.0, 0.001)


func test_the_driver_takes_the_car_s_authority_and_hands_it_back() -> void:
	var driver: Player = PLAYER.instantiate() as Player
	add_child_autofree(driver)
	driver.set_multiplayer_authority(42)
	car.set_driver(driver)
	assert_eq(car.current_driver_peer_id, 42, "The driver's peer is the driver")
	assert_eq(car.get_multiplayer_authority(), 42, "and holds the car")
	car.set_driver(null)
	assert_eq(car.current_driver_peer_id, Vehicle.SERVER_PEER, "Getting out hands the car back to the server")
	assert_eq(car.get_multiplayer_authority(), Vehicle.SERVER_PEER)


func test_the_hand_off_carries_the_driver_s_peer_to_every_copy() -> void:
	car._set_authority(42)
	assert_eq(car.get_multiplayer_authority(), 42, "The RPC every peer runs moves the authority")
	assert_eq(car.current_driver_peer_id, 42, "and names the driver itself, since the synchronizer has already changed hands")
	car._set_authority(Vehicle.SERVER_PEER)
	assert_eq(car.get_multiplayer_authority(), Vehicle.SERVER_PEER)
	assert_eq(car.current_driver_peer_id, Vehicle.SERVER_PEER)


func test_a_driver_who_disconnects_hands_the_car_back_to_the_server() -> void:
	car._set_authority(42)
	car._on_peer_disconnected(7)
	assert_eq(car.get_multiplayer_authority(), 42, "Somebody else leaving changes nothing")
	car._on_peer_disconnected(42)
	assert_eq(car.get_multiplayer_authority(), Vehicle.SERVER_PEER, "The driver leaving hands the car to the server")
	assert_eq(car.current_driver_peer_id, Vehicle.SERVER_PEER)


## A client at the wheel asks the server rather than taking the car itself, so the server is quiet before the
## client speaks; the grant is the server's alone and a client that receives one ignores it.
func test_a_clients_hand_off_is_a_request_the_server_grants() -> void:
	var config: Dictionary = (car.get_script() as Script).get_rpc_config()
	assert_true(config.has(&"_grant"), "The request travels by RPC")
	assert_eq(config[&"_grant"]["rpc_mode"], MultiplayerAPI.RPC_MODE_ANY_PEER, "any peer may ask")
	assert_false(config[&"_grant"].get("call_local", false), "and the asker does not switch itself")
	assert_true(config.has(&"_set_authority"), "the switch is the server's broadcast")
	car._grant(7) # offline this side is the server, so its own grant applies at once
	assert_eq(car.get_multiplayer_authority(), 7, "The server's grant switches the car")
	assert_eq(car.current_driver_peer_id, 7, "and names the driver")
	car._set_authority(Vehicle.SERVER_PEER)


func test_the_audio_settings_reach_every_player_on_the_car() -> void:
	# the player controller's audio settings call this on every member of the
	# "vehicles" group, and the chassis is what joins that group
	assert_true(car.is_in_group(&"vehicles"))
	car.set_sfx_volume(0.0)
	for named: String in ["SFXBoost", "SFXJump", "SFXImpact"]:
		var speaker: AudioStreamPlayer3D = car.get_node(NodePath(named)) as AudioStreamPlayer3D
		assert_almost_eq(speaker.volume_db, -80.0, 0.01, "%s is silenced" % named)
	car.set_sfx_volume(100.0)
	for named: String in ["SFXBoost", "SFXJump", "SFXImpact"]:
		var speaker: AudioStreamPlayer3D = car.get_node(NodePath(named)) as AudioStreamPlayer3D
		assert_almost_eq(speaker.volume_db, 0.0, 0.01, "%s is back to full" % named)
