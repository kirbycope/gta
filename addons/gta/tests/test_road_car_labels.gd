extends GutTest

## Purpose: the road car names the rider's buttons by the actions it reads, so each word sits on the button
## carrying that action under whatever layout the rider has, and the keyboard set draws that button as the key
## that does it: Space accelerates, Shift brakes, E gets out. A word pinned to a slot would be on the wrong key
## the moment a layout moved the action, which is what the Zelda layout does with Sprint and Action.

const PLAYER_SCENE: PackedScene = preload("res://addons/3d_player_controller/scenes/player.tscn")
const CAR_SCENE: PackedScene = preload("res://addons/gta/gta/scenes/honda_crv.tscn")

var player: Player
var car: GtaCar


func before_each() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	floor_shape.shape.size = Vector3(60.0, 1.0, 60.0)
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	car = CAR_SCENE.instantiate()
	root.add_child(car)
	car.global_position = Vector3(0.0, 0.6, 0.0)
	player = PLAYER_SCENE.instantiate()
	root.add_child(player)
	player.global_position = Vector3(4.0, 0.1, 0.0)
	player.controls.current_input_type = Controls.InputType.KEYBOARD_MOUSE
	await wait_physics_frames(6)


func _key_face(action: StringName) -> String:
	var button: TouchScreenButton = player.controls.action_button(action)
	return button.texture_normal.resource_path.get_file() if button else ""


func test_the_words_sit_on_the_buttons_that_do_them() -> void:
	car._show_prompt(player) # walked up: "Get In" is on the Action button
	player.mount(car)
	await wait_physics_frames(2)

	var controls: Controls = player.controls
	assert_false(car.menu_displayed, "Getting in takes the walk-up prompt down")
	assert_eq(controls.prompt_action_label, "", "and gives the Action button back, so Exit is not written over")
	assert_eq(controls.action_label(car.keyboard_accelerate_action).text, "Accelerate", "Space accelerates")
	assert_eq(_key_face(car.keyboard_accelerate_action), "keyboard_space_icon_outline.svg", "drawn as Space")
	assert_eq(controls.action_label(car.keyboard_brake_action).text, "Brake", "Shift brakes")
	assert_eq(_key_face(car.keyboard_brake_action), "keyboard_shift_icon_outline.svg", "drawn as Shift")
	assert_eq(controls.action_label(car.keyboard_exit_action).text, "Exit", "E gets out")
	assert_eq(_key_face(car.keyboard_exit_action), "keyboard_e_outline.svg", "drawn as E")
	assert_eq(controls.action_label(car.keyboard_handbrake_action).text, "Handbrake", "T is the handbrake")
	assert_eq(controls.key_j_label.text, "Prev\nStation")
	assert_eq(controls.key_l_label.text, "Next\nStation")
	assert_eq(controls.left_joystick_label.text, "Steer")

	controls.current_input_type = Controls.InputType.MICROSOFT
	await wait_physics_frames(1)
	assert_eq(controls.action_label(car.pad_accelerate_action).text, "Accelerate", "The right trigger accelerates")
	assert_eq(controls.action_label(car.pad_brake_action).text, "Brake", "the left one brakes")
	assert_eq(controls.action_label(car.pad_exit_action).text, "Exit", "and the jump button gets out")
	assert_eq(controls.joypad_button_13_label.text, "Prev\nStation", "The radio is on the d-pad")
