extends GutTest

## Purpose: a [HumanDriver] is a person's hand on a car's control pad, with no body in the car. It
## fills the pad from the keyboard or a joypad the way a brain fills it from a plan, picks which
## bindings to read from the last device that spoke, starts the chase camera, and never gets out of
## anything, because there is nothing to get out of.
##
## The bug it exists to close: the battle demos used to seat a Player at load, before any key was
## pressed, and the Player's controls assume touch until they hear a key. The first space bar was
## therefore judged as a pad press, and on the Twisted Metal car the pad exit is the jump button.
## Space ejected you.

const ROCKET_CAR: PackedScene = preload("res://addons/gta/scenes/rocket_car.tscn")
const TM2_CAR: PackedScene = preload("res://addons/gta/scenes/tm2_car.tscn")
## The Controls HUD is what registers the addon's action names into the InputMap; a Player carries one,
## and a demo with no Player instances the car's own HUD as a node. The test does the same.
const CONTROLS: PackedScene = preload("res://addons/gta/scenes/car_controls.tscn")

var car: RocketCar
var driver: HumanDriver


var controls: Controls


func before_each() -> void:
	controls = CONTROLS.instantiate() as Controls
	add_child_autofree(controls)
	car = ROCKET_CAR.instantiate() as RocketCar
	(car.get_node(^"RocketAi") as RocketAi).enabled = false
	add_child_autofree(car)
	await wait_physics_frames(1)
	driver = HumanDriver.new()
	driver.name = "HumanDriver"
	driver.controls = controls
	car.add_child(driver)
	await wait_physics_frames(2)


func after_each() -> void:
	for action: StringName in [&"jump", &"sprint", &"move_left", &"move_right", &"ability"]:
		if InputMap.has_action(action):
			Input.action_release(action)


func test_with_no_joypad_it_reads_the_keyboard_bindings() -> void:
	# a headless run has no joypad, which is also every desktop without one plugged in
	assert_eq(driver.input_type, Controls.InputType.KEYBOARD_MOUSE)
	assert_eq(car.input_type, Controls.InputType.KEYBOARD_MOUSE, "and the car is told, so _action resolves the keyboard set")


func test_it_takes_the_wheel_without_a_body() -> void:
	assert_null(car.player, "Nobody is seated")
	assert_true(car.camera.current, "but the chase camera is the view")
	assert_true(car.is_ball_cam, "and it opened in ball cam, as a kickoff does")
	assert_eq(car.current_driver_peer_id, Vehicle.SERVER_PEER, "No peer got in, so no authority changed hands")


func test_the_space_bar_is_the_throttle_and_nothing_else() -> void:
	# the whole point: on a pad, jump is the jump button; on a keyboard it is accelerate
	Input.action_press(car.keyboard_accelerate_action)
	await wait_physics_frames(3)
	assert_almost_eq(car._throttle, 1.0, 0.01, "Space is the throttle on the keyboard bindings")
	assert_false(car._jump_held, "and not a jump")
	Input.action_release(car.keyboard_accelerate_action)
	await wait_physics_frames(2)
	assert_almost_eq(car._throttle, 0.0, 0.01, "Let go, and the pad is empty again")


func test_with_a_hud_in_the_scene_the_hud_s_device_is_the_driver_s() -> void:
	# the HUD is the one watching the devices, and the driver follows what it says
	controls.current_input_type = Controls.InputType.MICROSOFT
	assert_eq(driver.input_type, Controls.InputType.MICROSOFT, "A pad on the HUD is a pad on the driver")
	assert_eq(car.input_type, Controls.InputType.MICROSOFT, "and on the car")
	controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
	assert_eq(driver.input_type, Controls.InputType.KEYBOARD_MOUSE, "and back")
	assert_eq(car.input_type, Controls.InputType.KEYBOARD_MOUSE)


func test_with_no_hud_the_last_device_that_spoke_decides() -> void:
	var lone: HumanDriver = HumanDriver.new()
	var tm2: Tm2Car = TM2_CAR.instantiate() as Tm2Car
	(tm2.get_node(^"AiDriver") as AiDriver).enabled = false
	add_child_autofree(tm2)
	await wait_physics_frames(1)
	tm2.add_child(lone)
	await wait_physics_frames(1)
	var button: InputEventJoypadButton = InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	button.pressed = true
	lone._unhandled_input(button)
	assert_eq(lone.input_type, Controls.InputType.MICROSOFT, "A joypad button picks the pad set")
	assert_eq(tm2.input_type, Controls.InputType.MICROSOFT)
	var motion: InputEventJoypadMotion = InputEventJoypadMotion.new()
	motion.axis = JOY_AXIS_LEFT_X
	motion.axis_value = 0.05
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	lone._unhandled_input(key)
	assert_eq(lone.input_type, Controls.InputType.KEYBOARD_MOUSE, "and a key picks the keyboard set back")
	lone._unhandled_input(motion)
	assert_eq(lone.input_type, Controls.InputType.KEYBOARD_MOUSE, "Stick noise below the deadzone changes nothing")
	motion.axis_value = 0.8
	lone._unhandled_input(motion)
	assert_eq(lone.input_type, Controls.InputType.MICROSOFT, "A real push does")


func test_the_hud_is_shown_or_hidden_by_the_player_s_setting_as_a_player_would() -> void:
	# the default setting is Auto, which on a desktop with no touchscreen draws no overlay
	var settings: PlayerSettingsResource = PlayerSettingsResource.load_or_create()
	var want: bool = settings.hud_shown(controls.current_input_type, DisplayServer.is_touchscreen_available())
	assert_eq(controls.visible, want, "The driver applies the same rule the Player applies to its own HUD")
	if not DisplayServer.is_touchscreen_available() and settings.hud_mode == PlayerSettingsResource.HudMode.AUTO:
		controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
		assert_false(controls.visible, "and so a keyboard on a desktop shows no touch overlay")


func test_disabled_leaves_the_pad_alone_but_still_hears_the_toggles() -> void:
	driver.enabled = false
	Input.action_press(car.keyboard_accelerate_action)
	await wait_physics_frames(3)
	assert_almost_eq(car._throttle, 0.0, 0.01, "Off, the driver does not fill the pad")
	Input.action_release(car.keyboard_accelerate_action)
	var was: bool = car.is_ball_cam
	var toggle: InputEventAction = InputEventAction.new()
	toggle.action = car.keyboard_ball_cam_action
	toggle.pressed = true
	driver._unhandled_input(toggle)
	assert_eq(car.is_ball_cam, not was, "but the camera can still be changed during a countdown")


func test_it_drives_the_twisted_metal_car_through_the_same_shape() -> void:
	var tm2: Tm2Car = TM2_CAR.instantiate() as Tm2Car
	(tm2.get_node(^"AiDriver") as AiDriver).enabled = false
	add_child_autofree(tm2)
	await wait_physics_frames(1)
	var hand: HumanDriver = HumanDriver.new()
	tm2.add_child(hand)
	await wait_physics_frames(2)
	assert_true(tm2.camera.current, "The wheel is taken the same way")
	Input.action_press(tm2.keyboard_accelerate_action)
	await wait_physics_frames(3)
	assert_true(tm2._accelerate, "and space is the throttle here too, never the exit")
	Input.action_release(tm2.keyboard_accelerate_action)


func test_there_is_nothing_to_get_out_of() -> void:
	# the road car's exit action, pressed under either binding set, does nothing here:
	# the driver never calls ride_input, and there is no rider to dismount
	for action: StringName in [car.keyboard_exit_action, car.pad_exit_action]:
		var press: InputEventAction = InputEventAction.new()
		press.action = action
		press.pressed = true
		driver._unhandled_input(press)
	await wait_physics_frames(2)
	assert_true(car.camera.current, "Still at the wheel")
	assert_not_null(car.get_node_or_null(^"HumanDriver"), "and the driver is still there")


func test_the_hud_says_what_the_car_s_buttons_do() -> void:
	# on the keyboard bindings the battle car labels space as accelerate
	var named: Dictionary = car.get_contextual_controls(Controls.InputType.KEYBOARD_MOUSE)
	assert_true(named.has("joypad_button_3"), "The car labels the accelerate slot")
	var label: Label = controls.get("joypad_button_3_label") as Label
	assert_not_null(label)
	assert_eq(label.text, named["joypad_button_3"], "and the HUD shows it")
	# the HUD hearing a pad rebuilds its panels with the scene's own labels, and the car's go back on
	controls.current_input_type = Controls.InputType.MICROSOFT
	var pad_named: Dictionary = car.get_contextual_controls(Controls.InputType.MICROSOFT)
	var pad_label: Label = controls.get("joypad_button_0_label") as Label
	assert_eq(pad_label.text, pad_named["joypad_button_0"], "On a pad the A slot is jump, and the HUD says so after its rebuild")
