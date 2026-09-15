class_name HumanDriver
extends Node
## A person at a car's control pad, with no body in the car.
##
## The addon's cars take input two ways and cannot tell them apart. A [Player] who has walked up and got
## in reaches the car through the rideable contract, [method Vehicle.ride], and that is the road car's way:
## you get in, you drive, you get out. The battle cars are driven the other way, through the same virtual
## pad the AI brains fill, [method RlCar.set_rocket_input] and [method TwCar.set_drive_input]. This
## node is the human's hand on that pad. It sits under a car the way [RlAi] and [TwAi] do, reads
## the keyboard or a joypad each physics frame, and fills the pad. There is nothing to get out of, which
## is the point: a demo that puts you straight at the wheel has no walking around and no exit.
##
## Which set of bindings to read is the one thing a pad has to know, because space is accelerate on a
## keyboard and the jump button on a pad. The last device that spoke decides, and until one has it is
## the keyboard unless a joypad is plugged in. A [Player] gets this from its on-screen controls, which
## start out assuming touch until a key is pressed; a driver with no body has no controls HUD and does
## not guess touch on a desktop.

const JOYPAD_DEADZONE: float = 0.2 ## Stick noise below this is not a person choosing a pad.

@export var enabled: bool = true ## Off leaves the pad alone, the way a switched off brain does.
## The on-screen controls HUD, when the scene has one. It is what registers the addon's action names
## into the InputMap, so a demo with no [Player] instances it as a node. With one here the driver does
## for it what a [Player] does for its own: follows its idea of the input device, labels its buttons
## with what the car says they do, and shows or hides it by the player's HUD setting, which on a
## desktop keeps the touch overlay off the screen.
@export var controls: Controls

## Which bindings the car reads, kept equal to [member Vehicle.input_type] on the car.
var input_type: int = Controls.InputType.KEYBOARD_MOUSE

var _car: Vehicle


func _ready() -> void:
	_car = get_parent() as Vehicle
	if not Input.get_connected_joypads().is_empty():
		input_type = Controls.InputType.MICROSOFT
	_apply_input_type()
	if is_instance_valid(_car):
		_car.take_the_wheel()
	if controls != null:
		# the HUD rebuilds its panels on a device change and only then says so, so the labels
		# have to be put back after it speaks rather than before
		controls.input_type_changed.connect(_on_controls_input_type_changed)
		controls.contextual_labels_requested.connect(_apply_labels)
		_apply_hud_visibility()


## The last device that spoke picks the bindings; toggles (the ball cam) are read off the event here,
## since a toggle is a press rather than a hold. Both work while [member enabled] is off, so the camera
## can be changed during a countdown; only the pad itself waits.
func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(_car):
		return
	# with a HUD in the scene it is the one that watches the devices, and it tells us
	if controls == null:
		var was: int = input_type
		if event is InputEventKey or event is InputEventMouseButton:
			input_type = Controls.InputType.KEYBOARD_MOUSE
		elif event is InputEventJoypadButton:
			input_type = Controls.InputType.MICROSOFT
		elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > JOYPAD_DEADZONE:
			input_type = Controls.InputType.MICROSOFT
		if input_type != was:
			_apply_input_type()
	if _car.has_method(&"read_toggles"):
		_car.call(&"read_toggles", event)


## The HUD heard a device. Its panels are already rebuilt by now, with the scene's own labels back on
## them, so the car's labels go on again and the HUD is shown or hidden for the device.
func _on_controls_input_type_changed(value: int) -> void:
	input_type = value
	_apply_input_type()
	_apply_hud_visibility()


## The same rule a [Player] applies to its own controls: the player's HUD setting decides, and on
## its default a desktop with no touchscreen draws nothing until a pad or the touch screen speaks.
func _apply_hud_visibility() -> void:
	if controls == null:
		return
	controls.visible = PlayerSettingsResource.load_or_create().hud_shown(
		controls.current_input_type, DisplayServer.is_touchscreen_available())


func _physics_process(_delta: float) -> void:
	if not enabled or not is_instance_valid(_car) or not _car.is_inside_tree():
		return
	if _car.has_method(&"read_controls"):
		_car.call(&"read_controls")


func _apply_input_type() -> void:
	if is_instance_valid(_car):
		_car.input_type = input_type
	_apply_labels()


## The car names its buttons by the HUD label they sit on, "joypad_button_0": "Boost"; the HUD wants
## the label nodes, so each name is looked up on it, exactly as the Riding state does.
func _apply_labels() -> void:
	if controls == null or not is_instance_valid(_car) or not _car.has_method(&"get_contextual_controls"):
		return
	var named: Dictionary = _car.call(&"get_contextual_controls", input_type)
	var labels: Dictionary = {}
	for label_name: String in named:
		var label: Variant = controls.get(label_name + "_label")
		if label is Label:
			labels[label] = named[label_name]
	controls.set_labels(labels)
