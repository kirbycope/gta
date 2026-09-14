class_name Vehicle
extends VehicleBody3D
## A rideable car chassis, and nothing but the chassis.
##
## This is the base the addon's three cars are built on: [GtaCar] the road car,
## [RocketCar] the battle car and [Tm2Car] the Twisted Metal one. It holds the
## three things every one of them needs and none of them should write twice: the
## wheels, the rideable contract the player controller's [Riding] state expects,
## and the multiplayer hand-off that moves the car to whoever is driving it.
##
## What is deliberately not here is the handling. There is no drivetrain, no
## gearbox, no traction model and no steering: a car's feel is the whole of what
## makes it that car, and a shared one would only be in the way. There is no HUD
## either, and no camera behaviour beyond starting and stopping the
## [VehicleCamera] a scene provides. A subclass that wants a speedometer, a first
## person view or a damage model brings its own.
##
## The rideable contract is duck typed, so the [Riding] state only needs the
## names to match. It looks for [member seat] to pin the rider to, [member
## camera] to make current, [member blocks_hands] and [member disables_collision]
## for the Player's own state, [member input_type] to keep in step, and the
## [method mount], [method dismount], [method ride] and [method ride_input]
## methods.
##
## [member seat] is optional, and the reason is worth knowing. The [Riding] state
## pins the rider to it the moment they get on, before [member mount_animation]
## has played. That is right for a car with no door, where getting in is instant.
## It is wrong for a car whose get-in clip is authored to start at the kerb and
## walk the driver into the seat, because they would play it from inside the
## seat. Such a car leaves [code]Seat[/code] out of its scene and seats the
## driver itself in [method ride]; [GtaCar] is the one that does.
##
## Over the network the body moves on the car's authority: the server's while
## parked, the driver's peer while driven, handed over on every peer when they
## get in and back when they get out. A scene that carries a
## [code]VehicleSynchronizer[/code] has it follow the car automatically, since
## authority is recursive.

const SERVER_PEER: int = 1 ## Who holds the car while nobody drives it.

@export var wheels: Array[VehicleWheel3D] ## Every wheel, for grip and contact counting.
@export var hides_driver_model: bool = true ## For a car with no cabin to put anyone in.

@export_group("Rideable")
@export var blocks_hands: bool = true ## Weapons stay holstered and the crosshair hides while driving.
@export var disables_collision: bool = true ## The rider sits inside the body, so their own shape is off.
## Locomotion clips played getting on and off. Empty means instant, which is
## what a car with no door wants.
@export var mount_animation: String = ""
@export var dismount_animation: String = ""

@export_group("Driving Actions")
@export var keyboard_accelerate_action: StringName = &"jump" ## Keyboard: space.
@export var pad_accelerate_action: StringName = &"shoot" ## Pad: the right trigger.
@export var keyboard_brake_action: StringName = &"sprint" ## Keyboard: shift.
@export var pad_brake_action: StringName = &"focus" ## Pad: the left trigger.
@export var keyboard_handbrake_action: StringName = &"throw" ## Keyboard: T.
@export var pad_handbrake_action: StringName = &"throw"
@export var keyboard_exit_action: StringName = &"whistle" ## Keyboard: K.
@export var pad_exit_action: StringName = &"whistle"
@export_group("")

## The driver's peer, [constant SERVER_PEER] with nobody at the wheel; replicated for a peer that joins
## mid-drive, and set by the hand-off itself on every peer already there.
@export var current_driver_peer_id: int = SERVER_PEER

## Kept equal to the Player's own device by the Riding state, so [method _action]
## resolves the right binding.
var input_type: int = Controls.InputType.KEYBOARD_MOUSE
var player: Player ## Whoever is driving, or null.

## Where the Riding state pins the rider, for a car that has one; see the class
## description for why a car with a get-in animation leaves it out.
@onready var seat: Node3D = get_node_or_null(^"Seat")
@onready var chase_camera: VehicleCamera = $VehicleCamera
@onready var camera: Camera3D = chase_camera.camera ## Made current by the Riding state while ridden.
## Optional: a scene that replicates its car carries one. Authority is recursive,
## so it follows the car without being told.
@onready var vehicle_synchronizer: MultiplayerSynchronizer = get_node_or_null(^"VehicleSynchronizer")


func _ready() -> void:
	add_to_group(&"vehicles")
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	set_sfx_volume(PlayerSettingsResource.load_or_create().sfx_volume)


## Sets the current driver and hands them the car's authority on every peer; null when the driver gets out, and
## the server has the car again.
func set_driver(driver: Player) -> void:
	if driver:
		player = driver
		_hand_authority_to(driver.get_multiplayer_authority())
		return
	_hand_authority_to(SERVER_PEER)
	player = null


## Hands the car (and so its synchronizer) to [param peer_id] on every peer: the driver's while driven, since their
## Riding state feeds the drive inputs and moves the body, the server's again once they are out. Offline there is
## nobody to tell.
func _hand_authority_to(peer_id: int) -> void:
	if multiplayer.get_peers().is_empty():
		_set_authority(peer_id)
	elif multiplayer.is_server():
		_set_authority.rpc(peer_id)
	else:
		# A client only asks. Were it to take the wheel itself, the server would keep sending the car's sync for a
		# round trip and the client, already the authority, would reject every packet; the server switching first
		# means the old authority is quiet before the new one speaks. Getting out, this side goes quiet first.
		if peer_id == SERVER_PEER:
			set_multiplayer_authority(SERVER_PEER)
		_grant.rpc_id(SERVER_PEER, peer_id)


## The server's half of a client's [method _hand_authority_to]: it switches itself as it tells everyone.
@rpc("any_peer", "reliable")
func _grant(peer_id: int) -> void:
	if multiplayer.is_server():
		_set_authority.rpc(peer_id)


## Getting out hands the car back before its synchronizer could send the cleared driver, so the hand-off carries
## [member current_driver_peer_id] to every peer itself; the replicated copy is for a peer that joins later.
@rpc("any_peer", "call_local", "reliable")
func _set_authority(peer_id: int) -> void:
	set_multiplayer_authority(peer_id)
	current_driver_peer_id = peer_id


## A driver who drops out takes the authority with them; every peer hands the car back to the server.
func _on_peer_disconnected(peer_id: int) -> void:
	if peer_id == get_multiplayer_authority():
		set_multiplayer_authority(SERVER_PEER)
		current_driver_peer_id = SERVER_PEER


## Update volume on every SFX [AudioStreamPlayer3D] under the car. The player controller's audio
## settings call this on each member of the "vehicles" group, which is the group joined above.
func set_sfx_volume(value: float) -> void:
	var db: float = linear_to_db(value / 100.0) if value > 0.0 else -80.0
	for child: Node in find_children("*", "AudioStreamPlayer3D", true, false):
		(child as AudioStreamPlayer3D).volume_db = db


## Rideable contract: take the rider, and the car with them. A car with a get-in
## clip does the rest of getting in once it has played.
func mount(rider: Player) -> void:
	set_driver(rider)
	chase_camera.begin(rider, self)
	_set_driver_model_visible(not hides_driver_model)


## Rideable contract: give the rider back, and the view and the car with them.
func dismount(rider: Player) -> void:
	_set_driver_model_visible(true)
	chase_camera.end()
	if player == rider:
		set_driver(null)


## Rideable contract: every physics frame while ridden. A chassis has nothing to
## do here; a car overrides it to read the buttons and drive itself.
func ride(_rider: Player, _delta: float) -> void:
	pass


## Rideable contract: the exit button gets out. Anything else is the car's own.
func ride_input(rider: Player, event: InputEvent) -> void:
	if event.is_action_pressed(_action(keyboard_exit_action, pad_exit_action)):
		rider.dismount()


## Rideable contract: label names on the Player's controls to their text while driving. A car with
## more to say overrides this; what is here is only the button that gets back out.
func get_contextual_controls(input_type_: int) -> Dictionary:
	var controls: Dictionary = {
		"left_joystick": "Steer",
		"right_joystick": "Camera",
	}
	controls["joypad_button_0" if input_type_ == Controls.InputType.KEYBOARD_MOUSE else "joypad_button_3"] = "Exit"
	return controls


## The action for the driver's current input device.
func _action(keyboard_action: StringName, pad_action: StringName) -> StringName:
	if input_type == Controls.InputType.KEYBOARD_MOUSE:
		return keyboard_action
	return pad_action


## Shows or hides the rider's own model, for [member hides_driver_model].
##
## Worth knowing when turning it back on. A car model is authored nose down +Z, but a Godot vehicle
## drives toward -Z, so the mesh needs turning 180 about Y or the chase camera looks at its grille.
## [code]honda_crv.tscn[/code] does that on its "Root Scene" and [code]tm2_car.tscn[/code] on its
## "Model"; the driver rides in whichever way that node faces, so a car that has not been turned
## seats its driver backwards too.
func _set_driver_model_visible(shown: bool) -> void:
	if player == null or not is_instance_valid(player.player_model):
		return
	player.player_model.visible = shown


## How many wheels are actually touching. Rocket League counts three or more as
## the ground, which is why this is a count rather than a yes or no.
func wheels_in_contact() -> int:
	var down: int = 0
	for wheel: VehicleWheel3D in wheels:
		if wheel != null and wheel.is_in_contact():
			down += 1
	return down


## Drive and brake go to the wheels rather than to the body, so nothing is left
## over from whatever a previous frame put on either, and both are split across
## the wheels rather than set whole on each.
func apply_wheel_forces(drive: float, stop: float) -> void:
	engine_force = 0.0
	brake = 0.0
	var driven: int = 0
	for wheel: VehicleWheel3D in wheels:
		if wheel != null and wheel.use_as_traction:
			driven += 1
	var drive_share: float = drive / float(maxi(driven, 1))
	var stop_share: float = stop / float(maxi(wheels.size(), 1))
	for wheel: VehicleWheel3D in wheels:
		if wheel == null:
			continue
		wheel.engine_force = drive_share if wheel.use_as_traction else 0.0
		wheel.brake = stop_share
