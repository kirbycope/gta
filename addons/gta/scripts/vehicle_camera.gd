class_name VehicleCamera
extends Node3D
## The GTA chase camera: a pivot over the vehicle with a spring arm behind it. It follows where the vehicle is
## travelling once it moves the way the camera looks, so slides swing the view, and the vehicle's facing at
## rest; manual look holds for a moment before the follow resumes. The Player's Riding state makes its camera
## current on mount and takes the view back on dismount.

@export var pivot_height: float = 1.2 ## Metres above the vehicle's origin the arm pivots.
@export var pitch: float = deg_to_rad(-15.0) ## Resting pitch, looking down at the vehicle.
@export var follow_speed: float = 5.0 ## Per-second rate the yaw settles behind the vehicle.
@export var travel_speed: float = 3.0 ## Above this (m/s) the yaw follows the direction of travel instead of the facing.
@export var mouse_sensitivity: float = 0.1
@export var joypad_sensitivity: float = 100.0

var vehicle: RigidBody3D
var player: Player

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D
@onready var follow_timer: Timer = $FollowTimer ## Running while the camera holds a manual look instead of following.


func _ready() -> void:
	top_level = true
	set_process(false)
	set_physics_process(false)
	set_process_unhandled_input(false)


## Takes the view for [param rider] driving [param driven], starting behind the vehicle.
func begin(rider: Player, driven: RigidBody3D) -> void:
	player = rider
	vehicle = driven
	spring_arm.add_excluded_object(driven.get_rid())
	global_position = driven.global_position + driven.global_basis.y * pivot_height
	var forward: Vector3 = driven.global_basis.z
	rotation = Vector3(pitch, atan2(-forward.x, -forward.z), 0.0)
	set_process(true)
	set_physics_process(true)
	set_process_unhandled_input(true)


## Stops following; the rider's own camera is made current by their Riding state.
func end() -> void:
	set_process(false)
	set_physics_process(false)
	set_process_unhandled_input(false)
	if vehicle:
		spring_arm.remove_excluded_object(vehicle.get_rid())
	player = null
	vehicle = null


func _unhandled_input(event: InputEvent) -> void:
	if not camera.current or player == null or player.is_paused: return
	if event is InputEventMouseMotion and (DisplayServer.get_name() == "headless" or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
		_look(-event.relative * mouse_sensitivity)


func _process(delta: float) -> void:
	if not camera.current or player == null or player.is_paused: return
	var joypad: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if joypad != Vector2.ZERO:
		_look(-joypad * joypad_sensitivity * delta)


func _look(degrees: Vector2) -> void:
	rotation.y += deg_to_rad(degrees.x)
	rotation.x = clampf(rotation.x + deg_to_rad(degrees.y), deg_to_rad(-89.0), deg_to_rad(89.0))
	follow_timer.start()


func _physics_process(delta: float) -> void:
	if vehicle == null: return
	global_position = vehicle.global_position + vehicle.global_basis.y * pivot_height
	if not follow_timer.is_stopped():
		return
	var look_dir: Vector3 = vehicle.global_basis.z
	var travel: Vector3 = vehicle.linear_velocity
	if Vector2(travel.x, travel.z).length() > travel_speed and travel.dot(-global_basis.z) > 0.0:
		look_dir = travel
	var target_yaw: float = atan2(-look_dir.x, -look_dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-follow_speed * delta))
	rotation.x = lerp_angle(rotation.x, pitch, 1.0 - exp(-follow_speed * delta))
