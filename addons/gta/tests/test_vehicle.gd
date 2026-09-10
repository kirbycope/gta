extends GutTest

## Purpose: A Vehicle is ridden through the Player's Riding state: mounting seats the driver behind the enter
## animation, drive inputs reach the drivetrain, the chase camera takes the view, and the exit action gets out.

const DEMO_SCENE: PackedScene = preload("res://addons/gta/scenes/demo/demo.tscn")

var demo: Node3D
var player: Player
var car: Vehicle


func before_each() -> void:
	demo = DEMO_SCENE.instantiate()
	add_child_autofree(demo)
	player = demo.get_node("Player")
	car = demo.get_node("HondaCRV")
	await wait_physics_frames(3)


## Mounts and skips the enter animation, the way a test can.
func _sit_in_the_car() -> void:
	player.mount(car)
	await wait_physics_frames(2)
	player.is_mounting = false
	for wheel: VehicleWheel3D in car.wheels:
		wheel.brake = 0.0


func test_mounting_seats_the_driver_and_takes_the_view() -> void:
	player.mount(car)
	await wait_physics_frames(2)
	assert_eq(player.current_state, NodeStateMachine.States.RIDING, "mount() rides the car")
	assert_eq(player.riding, car)
	assert_true(player.is_mounting, "The enter animation plays first")
	assert_true(player.riding_blocks_hands(), "Hands stay off weapons at the wheel")
	assert_true(car.chase_camera.camera.current, "The car's chase camera is the view")
	assert_false(player.camera.current)
	assert_true(car.driving_ui.visible, "The speedometer is up")
	player.is_mounting = false
	await wait_physics_frames(2)
	assert_almost_eq(player.global_position, car.driver_seat.global_position, Vector3.ONE * 0.1, "Seated on the DriverSeat marker once the animation is over")


func test_drive_inputs_reach_the_drivetrain() -> void:
	await _sit_in_the_car()
	player.controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
	var sender = InputSender.new(Input)
	sender.set_auto_flush_input(true)
	sender.action_down(car.keyboard_accelerate_action)
	sender.action_down("move_left")
	await wait_physics_frames(10)
	assert_true(car.is_driving_this_car, "The first drive input starts the drive")
	assert_gt(car.get_node("VehicleWheel3D").engine_force, 0.0, "Accelerating drives the wheels")
	assert_gt(car._steer, 0.0, "Steering left reaches the car")
	sender.action_up(car.keyboard_accelerate_action)
	sender.action_up("move_left")


func test_the_exit_action_gets_out_and_hands_the_view_back() -> void:
	await _sit_in_the_car()
	player.controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
	var sender = InputSender.new(Input)
	sender.set_auto_flush_input(true)
	sender.action_down(car.keyboard_exit_action)
	await wait_physics_frames(2)
	sender.action_up(car.keyboard_exit_action)
	assert_true(player.is_dismounting, "At rest the exit goes through the door animation")
	assert_eq(player.current_state, NodeStateMachine.States.RIDING, "And is still in the car until it ends")
	(player.state_machine.get_node("Riding") as Riding)._on_locomotion_node_changed("StandingLocomotion")
	await wait_physics_frames(2)
	assert_eq(player.current_state, NodeStateMachine.States.STANDING)
	assert_null(player.riding)
	assert_true(player.camera.current, "The Player's own camera is back")
	assert_false(car.chase_camera.camera.current)
	assert_false(car.driving_ui.visible)
	assert_false(car.is_driving_this_car)


func test_the_car_declares_its_side_of_the_rideable_contract() -> void:
	assert_true(car.blocks_hands)
	assert_true(car.disables_collision, "The driver's own collision is off inside the body")
	assert_eq(car.mount_animation, "EnteringCar")
	assert_eq(car.dismount_animation, "ExitingCar")
	assert_eq(car.camera, car.chase_camera.camera, "The chase camera is the view the Riding state makes current")
	assert_eq(car.get_contextual_controls(Controls.InputType.KEYBOARD_MOUSE).get("joypad_button_0"), "Exit")
	assert_eq(car.get_contextual_controls(Controls.InputType.SONY).get("joypad_button_3"), "Exit")


func test_a_bail_out_at_speed_skips_the_door_animation() -> void:
	await _sit_in_the_car()
	player.controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
	car.linear_velocity = Vector3(0.0, 0.0, 8.0)
	var sender = InputSender.new(Input)
	sender.set_auto_flush_input(true)
	sender.action_down(car.keyboard_exit_action)
	await wait_physics_frames(2)
	sender.action_up(car.keyboard_exit_action)
	assert_eq(player.current_state, NodeStateMachine.States.STANDING, "Straight out at speed")
	assert_false(player.is_dismounting)
	assert_true(player.camera.current)


func test_the_addon_car_has_no_fire_of_its_own() -> void:
	assert_null(car.fire, "Fire and explosion effects are optional nodes a project scene adds")
	car.is_on_fire = true
	await wait_physics_frames(1)
	assert_true(car.is_on_fire, "And flagging fire without them does not crash")
