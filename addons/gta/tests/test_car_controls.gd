extends GutTest

## Purpose: the on-screen controls in the battle demos are only ever the car's. [CarControls] is the
## Controls addon's HUD with the slots the cars read mapped and every other slot left blank, which
## hides it. It registers the car actions into the InputMap, since the demos have no [Player] to do
## that, with the same keys the player controller binds so a person moving between the demos meets
## nothing new.
##
## The other half is truthfulness. A car names its buttons by the HUD slot they sit on, and the
## slot faces are fixed, so a label on the wrong slot names the wrong key. Three of them were, and
## two pad bindings shared one trigger. These tests read every label back against what the car
## actually reads for that device.

const CAR_CONTROLS: PackedScene = preload("res://addons/gta/scenes/car_controls.tscn")
const ROCKET_CAR: PackedScene = preload("res://addons/gta/scenes/rocket_car.tscn")
const TM2_CAR: PackedScene = preload("res://addons/gta/scenes/tm2_car.tscn")

var controls: CarControls


func before_each() -> void:
	controls = CAR_CONTROLS.instantiate() as CarControls
	add_child_autofree(controls)
	await wait_physics_frames(1)


## Every action a car reads for a device, from its own exports, plus the sticks.
func _actions_read(car: Vehicle, keyboard: bool) -> Array[StringName]:
	var out: Array[StringName] = [&"move_up", &"move_down", &"move_left", &"move_right",
		&"look_up", &"look_down", &"look_left", &"look_right"]
	var prefix: String = "keyboard_" if keyboard else "pad_"
	for property: Dictionary in car.get_property_list():
		var name: String = property["name"]
		# the exit is read by ride_input for a seated body, and a driver with no body has no exit
		if name.begins_with(prefix) and name.ends_with("_action") and not name.ends_with("_exit_action"):
			out.append(car.get(name))
	# the pitch axis is read on both devices under one name
	if "pitch_forward_action" in car:
		out.append(car.pitch_forward_action)
		out.append(car.pitch_back_action)
	return out


func _car(scene: PackedScene) -> Vehicle:
	var car: Vehicle = scene.instantiate() as Vehicle
	for brain_name: String in ["RocketAi", "AiDriver"]:
		var brain: Node = car.get_node_or_null(NodePath(brain_name))
		if brain != null:
			brain.set("enabled", false)
	add_child_autofree(car)
	return car


func test_it_registers_every_action_the_cars_read_with_the_player_controller_s_keys() -> void:
	for car: Vehicle in [_car(ROCKET_CAR), _car(TM2_CAR)]:
		for keyboard: bool in [true, false]:
			for action: StringName in _actions_read(car, keyboard):
				assert_true(InputMap.has_action(action), "%s reads %s, so the HUD registers it" % [car.name, action])
	# and with the keys a Player knows, straight from the player controller's own table
	var space: InputEventKey = InputEventKey.new()
	space.physical_keycode = KEY_SPACE
	assert_true(InputMap.action_has_event(&"jump", space), "Space is jump, which a keyboard accelerates with")
	var shift: InputEventKey = InputEventKey.new()
	shift.physical_keycode = KEY_SHIFT
	assert_true(InputMap.action_has_event(&"sprint", shift), "Shift is sprint, which a keyboard reverses with")


func test_it_maps_nothing_the_cars_do_not_read() -> void:
	# a slot with an action the cars never read is a button on screen the demo does not use
	var read: Array[StringName] = []
	for car: Vehicle in [_car(ROCKET_CAR), _car(TM2_CAR)]:
		for keyboard: bool in [true, false]:
			for action: StringName in _actions_read(car, keyboard):
				if not read.has(action):
					read.append(action)
	for slot: String in controls.get_slot_actions():
		var action: StringName = controls.get_slot_actions()[slot]
		if action == &"":
			continue
		assert_has(read, action, "Slot %s carries %s, which no car reads" % [slot, action])


func test_every_label_a_car_gives_sits_on_a_slot_that_reads_that_way() -> void:
	# the whole point of a HUD: the label on a button says what that button does
	for car: Vehicle in [_car(ROCKET_CAR), _car(TM2_CAR)]:
		for input_type: int in [Controls.InputType.KEYBOARD_MOUSE, Controls.InputType.MICROSOFT]:
			var keyboard: bool = input_type == Controls.InputType.KEYBOARD_MOUSE
			var read: Array[StringName] = _actions_read(car, keyboard)
			var named: Dictionary = car.get_contextual_controls(input_type)
			for label_name: String in named:
				if label_name.ends_with("joystick"):
					continue
				assert_true(controls.get(label_name + "_label") is Label,
					"%s labels %s, which must be a slot on this HUD" % [car.name, label_name])
				var slot: String = label_name.trim_prefix("joypad_")
				var action: StringName = controls.get_slot_actions().get(slot, &"")
				assert_has(read, action,
					"%s says the %s slot is '%s', but that slot carries '%s', which it does not read on this device"
					% [car.name, slot, named[label_name], action])


func test_no_two_things_a_car_does_share_one_pad_button() -> void:
	# LT used to be both reverse and boost on the Rocket League car
	for car: Vehicle in [_car(ROCKET_CAR), _car(TM2_CAR)]:
		var seen: Dictionary = {}
		for property: Dictionary in car.get_property_list():
			var name: String = property["name"]
			if name.begins_with("pad_") and name.ends_with("_action"):
				var action: StringName = car.get(name)
				if name.ends_with("_exit_action"):
					continue # the exit, which a driver with no body never reads
				# Rocket League binds powerslide and air roll to one button by default, and so does
				# this car: the one is on the ground and the other in the air, and the label says both
				if name in ["pad_handbrake_action", "pad_air_roll_action"] and action == &"throw":
					continue
				assert_false(seen.has(action), "%s: %s and %s both read '%s'" % [car.name, name, seen.get(action, ""), action])
				seen[action] = name


func test_a_driver_with_no_body_is_offered_no_exit() -> void:
	var tm2: Tm2Car = _car(TM2_CAR) as Tm2Car
	for input_type: int in [Controls.InputType.KEYBOARD_MOUSE, Controls.InputType.MICROSOFT]:
		for text: String in tm2.get_contextual_controls(input_type).values():
			assert_ne(text, "Exit", "Nothing to get out of, so nothing says Exit")
