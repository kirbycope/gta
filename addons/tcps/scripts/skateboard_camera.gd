class_name SkateboardCamera
extends Camera3D
## The THPS camera, after Neversoft's CSkaterCam::Update in the Tony Hawk's Underground source
## (Code/Sk/Objects/skatercam.cpp). It belongs to the [Skateboard]; the rider's Riding state makes it current while
## the board is ridden and takes the view back on dismount.
##
## A tripod chases the skater with lag; a frame turns toward the travel direction (flattened against the ground)
## and the skater's up, tilted down a little, plus the lookaround offset; the camera sits behind the frame and
## above the skater along their up, is pulled in by a feeler when something is in the way, and is aimed straight
## at the skater every physics tick, after the board has moved them. In vert air the frame's forward is straight
## down and the tripod barely moves, so the camera parks above the launch point and watches the skater go up and
## come back; spins never turn the view, and after touchdown the frame swings back behind the skater.

const VERT_AIR_FORWARD_NUDGE: float = 0.1 ## THUG aims "near straight down"; the nudge toward the deck makes the half turn swing out through the pipe.

@export var behind: float = 2.4 ## Metres behind the frame the camera sits.
@export var above: float = 1.0 ## The focus height above the skater's feet along their up; the camera is raised by it too.
@export var tilt: float = deg_to_rad(10.0) ## Resting downward tilt of the frame behind the skater.
@export var lerp_xz: float = 10.0 ## Per-second rate the tripod chases the skater sideways on the ground; the lag sells speed.
@export var lerp_y: float = 6.0 ## And vertically.
@export var vert_lerp_xz: float = 1.0 ## In vert air the tripod stays near where the skater left the wall.
@export var vert_lerp_y: float = 0.3 ## And barely climbs, so the camera watches the air from the ramp.
@export var slerp: float = 6.0 ## Per-second rate the frame turns toward its target on the ground.
@export var vert_slerp: float = 1.2 ## In vert air the frame swings to straight down slowly.
@export var landed_slerp: float = 4.0 ## Just after a vert landing the frame swings back behind the skater briskly.
@export var landed_time: float = 0.35 ## Seconds the landed rate applies.
@export var lookaround_max: Vector2 = Vector2(deg_to_rad(120.0), deg_to_rad(45.0)) ## Manual look is an offset on the frame (heading, tilt), not a free camera.
@export var lookaround_return: float = 3.0 ## Per-second rate the offset eases back once the look input stops.
@export var min_distance: float = 0.5 ## The feeler never pulls the camera closer to the skater than this.

var player: Player
var board: Node3D
var lookaround: Vector2 = Vector2.ZERO ## Manual look offset: heading about the skater's up, tilt about the frame's right.
var tripod: Vector3 = Vector3.ZERO ## The lagging pivot the camera hangs off, in world space.
var frame: Basis = Basis.IDENTITY ## The frame the camera hangs off (-Z forward).
var _forward: Vector3 = Vector3.FORWARD ## The frame's forward, eased toward the target along the great circle.
var _travel: Vector3 = Vector3.FORWARD ## Last travel direction, kept while the board is too slow to read one.
var _landed_timer: float = 0.0

@onready var look_return_timer: Timer = $LookReturnTimer ## Running while the lookaround holds instead of easing back.


func _ready() -> void:
	top_level = true
	set_process(false)
	set_process_unhandled_input(false)


## Takes over from [param rider]'s own camera, starting from its pose so the handover does not cut.
func begin(rider: Player, ridden: Node3D) -> void:
	player = rider
	board = ridden
	global_transform = rider.camera.global_transform
	frame = global_basis
	_forward = -global_basis.z
	_travel = _forward
	tripod = rider.global_position
	lookaround = Vector2.ZERO
	_landed_timer = 0.0
	set_process(true)
	set_process_unhandled_input(true)


## Stops following; the rider's own camera is made current by their Riding state.
func end() -> void:
	set_process(false)
	set_process_unhandled_input(false)
	player = null
	board = null


func _unhandled_input(event: InputEvent) -> void:
	if not current or player == null or player.is_paused: return
	if event is InputEventMouseMotion and (DisplayServer.get_name() == "headless" or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
		var sensitivity: float = player.camera.get("mouse_sensitivity") if player.camera.get("mouse_sensitivity") != null else 0.1
		_lookaround_input(-event.relative * sensitivity)


func _process(delta: float) -> void:
	if not current or player == null or player.is_paused: return
	var joypad: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if joypad != Vector2.ZERO:
		var sensitivity: float = player.camera.get("joypad_sensitivity") if player.camera.get("joypad_sensitivity") != null else 100.0
		_lookaround_input(-joypad * sensitivity * delta)


func _lookaround_input(degrees: Vector2) -> void:
	lookaround += Vector2(deg_to_rad(degrees.x), deg_to_rad(degrees.y))
	lookaround = lookaround.clamp(-lookaround_max, lookaround_max)
	look_return_timer.start()


## Places the camera for this physics tick; the board calls it after it has moved the skater.
func follow(delta: float) -> void:
	if player == null or board == null: return
	var on_floor: bool = player.is_on_floor()
	var vert_normal: Vector3 = board.get("vert_normal")
	var vert: bool = not on_floor and vert_normal != Vector3.ZERO
	var up: Vector3 = player.up_direction
	var skater_up: Vector3 = board.call("surface_up")

	# The tripod tends toward the skater; slowly in vert air so the camera stays at the ramp
	var t_xz: float = 1.0 - exp(-(vert_lerp_xz if vert else lerp_xz) * delta)
	var t_y: float = 1.0 - exp(-(vert_lerp_y if vert else lerp_y) * delta)
	var target_pos: Vector3 = player.global_position
	tripod = Vector3(lerpf(tripod.x, target_pos.x, t_xz), lerpf(tripod.y, target_pos.y, t_y), lerpf(tripod.z, target_pos.z, t_xz))

	# Target forward: the travel direction, or near straight down in vert air
	var forward: Vector3
	if vert:
		forward = (-up + board.get("vert_out") * VERT_AIR_FORWARD_NUDGE).normalized()
		lookaround = Vector2.ZERO
	else:
		var velocity: Vector3 = player.velocity
		if velocity.length() > 0.1:
			var flattened: Vector3 = velocity - skater_up * (0.8 * velocity.dot(skater_up))
			if flattened.length_squared() > 0.0001:
				_travel = flattened.normalized()
		forward = _travel

	# Ease the frame's forward along the great circle, then hang the frame on the skater's up
	var rate: float = vert_slerp if vert else (landed_slerp if _landed_timer > 0.0 else slerp)
	if vert:
		_landed_timer = landed_time
	elif on_floor:
		_landed_timer = maxf(_landed_timer - delta, 0.0)
	if _forward.dot(forward) < -0.999:
		_forward = (_forward + skater_up * 0.01).normalized()
	_forward = _forward.slerp(forward, 1.0 - exp(-rate * delta)).normalized()
	var right: Vector3 = skater_up.cross(_forward)
	if right.length_squared() < 0.0001:
		right = frame.x
	right = right.normalized()
	var frame_up: Vector3 = _forward.cross(right).normalized()
	frame = Basis.looking_at(_forward, frame_up)
	if not vert:
		frame = Basis(frame.x.normalized(), -tilt) * frame
		if look_return_timer.is_stopped():
			lookaround = lookaround.move_toward(Vector2.ZERO, lookaround_return * delta)
		if lookaround != Vector2.ZERO:
			frame = Basis(frame_up.normalized(), lookaround.x) * frame
			frame = Basis(frame.x.normalized(), lookaround.y) * frame

	# Behind the frame and above the skater, pulled in by a feeler, aimed straight at them
	var focus: Vector3 = player.global_position + skater_up * above
	var camera_position: Vector3 = tripod + frame.z * behind + skater_up * above
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(focus, camera_position, player.collision_mask, [player.get_rid()])
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var pulled: float = maxf(focus.distance_to(hit.position) * 0.9, min_distance)
		camera_position = focus + (camera_position - focus).normalized() * pulled
	var to_focus: Vector3 = focus - camera_position
	if to_focus.length_squared() < 0.0001 or to_focus.normalized().cross(frame.y).length_squared() < 0.0001:
		return
	global_transform = Transform3D(Basis.looking_at(to_focus.normalized(), frame.y), camera_position)
