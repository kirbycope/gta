extends GutTest

## Purpose: To test the actions and keybindings in `res://addons/3d_player_controller/scripts/controls.gd`.


## Shared base setup/teardown for test classes that inherit from _this_ one.
class ControlsTestBase:
	extends IntegrationTestBase

	var PlayerScene = load("res://addons/3d_player_controller/scenes/player.tscn")
	var root: Node3D = null
	var player_instance: Player = null
	var player_debug: CanvasLayer = null

	## Runs before each test is executed.
	func before_each() -> void:
		root = Node3D.new()
		add_child_autofree(root)
		player_instance = PlayerScene.instantiate() as Player
		root.add_child(player_instance)
		player_debug = player_instance.get_node("Debug") as CanvasLayer
		await wait_physics_frames(2)

	## Runs after each test is executed.
	func after_each() -> void:
		if is_instance_valid(root):
			root.free()
			root = null
			player_instance = null
			player_debug = null


## Tests related to the function performed by an action.
class TestDebugAction:
	extends ControlsTestBase

	func test_pressing_debug_action_toggles_debug_node_visibility():
		# Arrange: Ensure the "debug" node is hidden before performing the action.
		assert_false(player_debug.visible, "Debug node should be hidden by default.")

		# Act: Perform the "debug" action.
		var sender = InputSender.new(player_debug)
		sender.action_down("debug").wait(0.1).action_up("debug")
		await sender.idle

		# Assert: Ensure that the "debug" node is now visible.
		assert_true(
			player_debug.visible,
			"Debug node should be visible after pressing the debug action.",
		)


## Tests related to the keybinding for an action.
class TestDebugKeybind:
	extends ControlsTestBase

	func test_pressing_f3_key_toggles_debug_node_visibility():
		# Arrange: Ensure the "debug" node is hidden before sending key events.
		assert_false(player_debug.visible, "Debug node should be hidden by default.")

		# Act: Perform the key press for [F3] to trigger the "debug" action.
		await send_key(Key.KEY_F3)

		# Assert: Ensure that the "debug" node is now visible.
		assert_true(player_debug.visible, "Debug node should be visible after pressing F3.")


## Tests related to Key I, J, K, L action bindings.
class TestKeyIJKLActionBindings:
	extends ControlsTestBase

	func test_key_ijkl_actions_assigned():
		var player = player_instance
		assert_eq(player.controls.key_i.action, "seeker")
		assert_eq(player.controls.key_j.action, "last_weapon")
		assert_eq(player.controls.key_k.action, "whistle")
		assert_eq(player.controls.key_l.action, "next_weapon")


## Tests related to Flying controls and contextual UI labels.
class TestFlyingControls:
	extends ControlsTestBase

	func test_flying_contextual_controls_keyboard():
		var player = player_instance
		player.enable_flying = true
		player.controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
		player.state_machine.travel(NodeStateMachine.States.STANDING, NodeStateMachine.States.FLYING)

		assert_eq(player.controls.joypad_button_3_label.text, "Fly Up")
		assert_eq(player.controls.joypad_button_7_label.text, "Fly Down")
		assert_eq(player.controls.left_joystick_label.text, "Fly")

	func test_flying_contextual_controls_controller():
		var player = player_instance
		player.enable_flying = true
		player.controls.current_input_type = Controls.InputType.MICROSOFT
		player.state_machine.travel(NodeStateMachine.States.STANDING, NodeStateMachine.States.FLYING)

		assert_eq(player.controls.joypad_button_3_label.text, "Fly Up")
		assert_eq(player.controls.joypad_button_0_label.text, "Fly Down")
		assert_eq(player.controls.left_joystick_label.text, "Fly")


## Tests related to Paragliding controls and contextual UI labels.
class TestParaglidingControls:
	extends ControlsTestBase

	func test_paragliding_contextual_controls_keyboard():
		var player = player_instance
		player.enable_paraglider = true
		player.controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
		player.state_machine.travel(NodeStateMachine.States.STANDING, NodeStateMachine.States.PARAGLIDING)

		assert_eq(player.controls.joypad_button_7_label.text, "Cancel")
		assert_eq(player.controls.left_joystick_label.text, "Steer")

	func test_paragliding_contextual_controls_controller():
		var player = player_instance
		player.enable_paraglider = true
		player.controls.current_input_type = Controls.InputType.MICROSOFT
		player.state_machine.travel(NodeStateMachine.States.STANDING, NodeStateMachine.States.PARAGLIDING)

		assert_eq(player.controls.joypad_button_0_label.text, "Cancel")
		assert_eq(player.controls.left_joystick_label.text, "Steer")


## Tests related to Climbing controls and contextual UI labels.
class TestClimbingControls:
	extends ControlsTestBase

	func test_climbing_contextual_controls_keyboard():
		var player = player_instance
		player.controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
		player.state_machine.travel(NodeStateMachine.States.STANDING, NodeStateMachine.States.CLIMBING)

		assert_eq(player.controls.joypad_button_3_label.text, "Hop")
		assert_eq(player.controls.joypad_button_1_label.text, "Fast Climb")
		assert_eq(player.controls.joypad_button_7_label.text, "Drop")
		assert_eq(player.controls.left_joystick_label.text, "Climb")

	func test_climbing_contextual_controls_controller():
		var player = player_instance
		player.controls.current_input_type = Controls.InputType.MICROSOFT
		player.state_machine.travel(NodeStateMachine.States.STANDING, NodeStateMachine.States.CLIMBING)

		assert_eq(player.controls.joypad_button_3_label.text, "Hop")
		assert_eq(player.controls.joypad_button_1_label.text, "Fast Climb")
		assert_eq(player.controls.joypad_button_7_label.text, "Drop")
		assert_eq(player.controls.left_joystick_label.text, "Climb")


## Tests related to Hanging controls and contextual UI labels.
class TestHangingControls:
	extends ControlsTestBase

	func test_hanging_contextual_controls_keyboard():
		var player = player_instance
		player.controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
		player.state_machine.travel(NodeStateMachine.States.STANDING, NodeStateMachine.States.HANGING)

		assert_eq(player.controls.joypad_button_3_label.text, "Climb Up")
		assert_eq(player.controls.joypad_button_7_label.text, "Drop")
		assert_eq(player.controls.left_joystick_label.text, "Shimmy")

	func test_hanging_contextual_controls_controller():
		var player = player_instance
		player.controls.current_input_type = Controls.InputType.MICROSOFT
		player.state_machine.travel(NodeStateMachine.States.STANDING, NodeStateMachine.States.HANGING)

		assert_eq(player.controls.joypad_button_3_label.text, "Climb Up")
		assert_eq(player.controls.joypad_button_7_label.text, "Drop")
		assert_eq(player.controls.left_joystick_label.text, "Shimmy")


## Tests related to Swimming controls and contextual UI labels.
class TestSwimmingControls:
	extends ControlsTestBase

	func test_swimming_contextual_controls_keyboard():
		var player = player_instance
		player.controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
		player.state_machine.travel(NodeStateMachine.States.STANDING, NodeStateMachine.States.SWIMMING)

		assert_eq(player.controls.joypad_button_3_label.text, "Climb Out")
		assert_eq(player.controls.joypad_button_1_label.text, "Fast Swim")
		assert_eq(player.controls.left_joystick_label.text, "Swim")

	func test_swimming_contextual_controls_controller():
		var player = player_instance
		player.controls.current_input_type = Controls.InputType.MICROSOFT
		player.state_machine.travel(NodeStateMachine.States.STANDING, NodeStateMachine.States.SWIMMING)

		assert_eq(player.controls.joypad_button_3_label.text, "Climb Out")
		assert_eq(player.controls.joypad_button_1_label.text, "Fast Swim")
		assert_eq(player.controls.left_joystick_label.text, "Swim")


## Tests related to UI action bindings.
class TestUIActions:
	extends ControlsTestBase

	func test_ui_accept_has_joypad_a():
		var joy_a = InputEventJoypadButton.new()
		joy_a.button_index = JOY_BUTTON_A
		assert_true(InputMap.action_has_event("ui_accept", joy_a), "ui_accept should contain JOY_BUTTON_A")

	func test_ui_accept_has_space():
		var key_space = InputEventKey.new()
		key_space.physical_keycode = KEY_SPACE
		assert_true(InputMap.action_has_event("ui_accept", key_space), "ui_accept should contain KEY_SPACE")

	func test_ui_directions_have_dpad():
		var dpad_left = InputEventJoypadButton.new()
		dpad_left.button_index = JOY_BUTTON_DPAD_LEFT
		assert_true(InputMap.action_has_event("ui_left", dpad_left), "ui_left should contain JOY_BUTTON_DPAD_LEFT")

		var dpad_right = InputEventJoypadButton.new()
		dpad_right.button_index = JOY_BUTTON_DPAD_RIGHT
		assert_true(InputMap.action_has_event("ui_right", dpad_right), "ui_right should contain JOY_BUTTON_DPAD_RIGHT")

		var dpad_up = InputEventJoypadButton.new()
		dpad_up.button_index = JOY_BUTTON_DPAD_UP
		assert_true(InputMap.action_has_event("ui_up", dpad_up), "ui_up should contain JOY_BUTTON_DPAD_UP")

		var dpad_down = InputEventJoypadButton.new()
		dpad_down.button_index = JOY_BUTTON_DPAD_DOWN
		assert_true(InputMap.action_has_event("ui_down", dpad_down), "ui_down should contain JOY_BUTTON_DPAD_DOWN")


## Tests related to the Demo scene instantiation.
class TestPlayerControllerDemoScene:
	extends GutTest

	func test_demo_scene_instantiation():
		var scene = load("res://addons/3d_player_controller/scenes/demo/demo.tscn")
		assert_not_null(scene)
		var demo = scene.instantiate()
		assert_not_null(demo)
		add_child_autofree(demo)
		assert_not_null(demo.player)
		assert_not_null(demo.get_node("Markers/Tower"))
		assert_not_null(demo.get_node("Markers/Courtyard"))
		assert_not_null(demo.get_node("Markers/Pool"))
		assert_not_null(demo.get_node("Markers/ClimbingWall"))
		assert_true(demo.player.enable_stamina)
		
		# Test Teleport
		demo._on_teleport_pressed(^"Markers/Tower")
		assert_almost_eq(demo.player.global_position.x, demo.get_node("Markers/Tower").global_position.x, 0.1)

		# Test Water Pool Teleport & Swimming Entry
		demo._on_teleport_pressed(^"Markers/Pool")
		await wait_physics_frames(2)
		assert_eq(demo.player.current_state, NodeStateMachine.States.SWIMMING, "Player should enter SWIMMING state when in the water pool")
		assert_true(demo.player.is_swimming, "Player is_swimming flag should be true")


## Tests related to swapping input types, label resetting, and texture state.
class TestInputTypeSwapping:
	extends ControlsTestBase

	func test_swapping_input_types_resets_custom_labels():
		var controls = player_instance.controls
		# Custom label override
		controls.set_labels({ controls.joypad_button_0_label: "CustomAction" })
		assert_eq(controls.joypad_button_0_label.text, "CustomAction")
		assert_eq(controls.joypad_button_1_label.text, "")

		# Swap input type to Keyboard/Mouse -> should reset all labels to defaults
		controls.current_input_type = controls.InputType.KEYBOARD_MOUSE
		assert_eq(controls.joypad_button_0_label.text, "Action", "Label should reset to default upon swapping input type")
		assert_eq(controls.key_s_label.text, "Move", "Key S label should reset to default Move")
		assert_eq(controls.key_i_label.text, "Seeker", "Key I label should reset to default Seeker")

	func test_dpad_texture_resets_to_outline_after_input_swap():
		var controls = player_instance.controls
		var dpad_up = controls.joypad_button_11
		var outline_texture = dpad_up.texture_normal

		# Simulate pressing DPad Up (action: "seeker")
		var press_event = InputEventAction.new()
		press_event.action = "seeker"
		press_event.pressed = true
		controls._input(press_event)
		assert_eq(dpad_up.texture_normal, dpad_up.texture_pressed, "Texture should switch to pressed texture when held")

		# Bump mouse (swap to Keyboard/Mouse)
		controls.current_input_type = controls.InputType.KEYBOARD_MOUSE

		# Release DPad Up action
		var release_event = InputEventAction.new()
		release_event.action = "seeker"
		release_event.pressed = false
		controls._input(release_event)

		# Swap back to controller
		controls.current_input_type = controls.InputType.MICROSOFT
		assert_eq(dpad_up.texture_normal, outline_texture, "DPad Up texture should return to outline texture when released after input swap")


## Tests related to the runtime InputMap action table.
class TestActionTable:
	extends ControlsTestBase

	func test_every_table_action_is_registered_with_its_bindings():
		for action_name: String in Controls.ACTIONS:
			assert_true(InputMap.has_action(action_name), "Action %s should be registered." % action_name)
			var binding: Dictionary = Controls.ACTIONS[action_name]
			for key in binding.get("keys", []):
				var key_event := InputEventKey.new()
				key_event.physical_keycode = key
				assert_true(InputMap.action_has_event(action_name, key_event), "%s should have physical key %s." % [action_name, key])
			for keycode in binding.get("keycodes", []):
				var key_event := InputEventKey.new()
				key_event.keycode = keycode
				assert_true(InputMap.action_has_event(action_name, key_event), "%s should have keycode %s." % [action_name, keycode])
			for button in binding.get("buttons", []):
				var button_event := InputEventJoypadButton.new()
				button_event.button_index = button
				assert_true(InputMap.action_has_event(action_name, button_event), "%s should have joypad button %s." % [action_name, button])
			for axis in binding.get("axes", []):
				var motion_event := InputEventJoypadMotion.new()
				motion_event.axis = axis[0]
				motion_event.axis_value = axis[1]
				assert_true(InputMap.action_has_event(action_name, motion_event), "%s should have joypad axis %s." % [action_name, axis])
			for mouse_button in binding.get("mouse", []):
				var mouse_event := InputEventMouseButton.new()
				mouse_event.button_index = mouse_button
				assert_true(InputMap.action_has_event(action_name, mouse_event), "%s should have mouse button %s." % [action_name, mouse_button])

	func test_emote_action_is_not_registered():
		assert_false(Controls.ACTIONS.has("emote"), "The unused emote action should be gone from the table.")
