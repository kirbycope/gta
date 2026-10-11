class_name MkCamera
extends VehicleCamera
## Mario Kart 64's one-player race camera, after [code]func_8001E45C[/code] and [code]func_8001CCEC[/code] in
## [code]src/camera.c[/code] of the mk64 decompilation.
##
## The game's camera does not hang behind the kart: it carries a yaw of its own, [member cam_yaw], and each
## frame pulls that yaw toward the kart's by a capped step ([code]adjust_angle[/code]): 500 of the game's 65536
## units a frame with the stick centred, a smaller step that grows with the kart's own yaw rate while it is
## steering, so the kart visibly turns across the screen before the view comes round. Through a drift the
## camera leads the kart by twelve degrees on the drift's side ([code]camera->unk_B0[/code]). From that yaw it
## places itself [constant MkConst.CAMERA_BEHIND] units behind and [constant MkConst.CAMERA_ABOVE] above the
## kart and looks at a point [constant MkConst.CAMERA_LOOK_AHEAD] ahead, both eased: the position and the
## look point move forty percent of the way across the ground each frame and fifteen (position) or fifty
## (look point) percent of the way vertically.
##
## It sits on the kart's [code]VehicleCamera[/code] node in place of the road car's spring arm, so the chassis
## and the Riding state start and stop it the same way; the arm is folded to nothing and the camera node is
## placed by hand.

var cam_yaw: float = 0.0 ## The camera's own yaw in radians ([code]camera->unk_2C[/code]).
var _drift_lead: float = 0.0 ## Radians the camera leads the kart by in a drift ([code]camera->unk_B0[/code]).
var _look_at: Vector3 = Vector3.ZERO ## The eased look point ([code]camera->lookAt[/code]).
var _kart: MkCar


func begin(rider: Player, driven: RigidBody3D) -> void:
	super(rider, driven)
	_kart = driven as MkCar
	spring_arm.spring_length = 0.0
	spring_arm.rotation = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	cam_yaw = _kart_yaw()
	_drift_lead = 0.0
	global_position = _target_position()
	_look_at = _target_look()
	look_at(_look_at, Vector3.UP)


func end() -> void:
	super()
	_kart = null


func _physics_process(delta: float) -> void:
	if _kart == null or not is_instance_valid(_kart):
		return
	var frames: float = delta * MkConst.FPS
	_chase_yaw(frames)
	var blend_xz: float = MkConst.step_fraction(MkConst.CAMERA_XZ_LERP, frames)
	var slow_hop: bool = _kart.is_hopping and MkConst.ms_to_kmh(absf(_kart.forward_speed())) <= MkConst.CAMERA_HOP_STILL_KMH
	var blend_y: float = MkConst.step_fraction(MkConst.CAMERA_HOP_Y_LERP if slow_hop else MkConst.CAMERA_Y_LERP, frames)
	var blend_look_y: float = MkConst.step_fraction(MkConst.CAMERA_HOP_LOOK_Y_LERP if slow_hop else MkConst.CAMERA_LOOK_Y_LERP, frames)
	var target: Vector3 = _target_position()
	var look: Vector3 = _target_look()
	global_position = Vector3(
		lerpf(global_position.x, target.x, blend_xz),
		lerpf(global_position.y, target.y, blend_y),
		lerpf(global_position.z, target.z, blend_xz))
	_look_at = Vector3(
		lerpf(_look_at.x, look.x, blend_xz),
		lerpf(_look_at.y, look.y, blend_look_y),
		lerpf(_look_at.z, look.z, blend_xz))
	if not global_position.is_equal_approx(_look_at):
		look_at(_look_at, Vector3.UP)


## The kart's yaw as the game keeps it: the heading of its nose about world up.
func _kart_yaw() -> float:
	var nose: Vector3 = _kart.forward()
	return atan2(nose.x, nose.z)


## [code]adjust_angle(&camera->unk_2C, rotation[1] + unk_B0, step)[/code]: the camera's yaw moves toward the
## kart's, plus the drift lead, by at most a step that depends on what the kart is doing.
func _chase_yaw(frames: float) -> void:
	var yaw_rate: float = absf(_kart.yaw_rate_units())
	var step_units: float
	if _kart.is_drifting:
		var lead: float = MkConst.CAMERA_DRIFT_LEAD_OUTSIDE if _kart.is_drifting_outside() else MkConst.CAMERA_DRIFT_LEAD
		var toward: float = 0.0 if _kart.yaw_rate_units() == 0.0 else signf(_kart.yaw_rate_units()) * lead
		_drift_lead = lerpf(_drift_lead, toward, MkConst.step_fraction(MkConst.CAMERA_DRIFT_LEAD_LERP, frames))
		step_units = MkConst.CAMERA_YAW_STEP_STRAIGHT if yaw_rate == 0.0 else MkConst.CAMERA_YAW_STEP_TURN + yaw_rate * 0.5
	else:
		_drift_lead = lerpf(_drift_lead, 0.0, MkConst.step_fraction(MkConst.CAMERA_DRIFT_LEAD_RELEASE, frames))
		var behind: float = absf(rad_to_deg(angle_difference(_kart_yaw(), cam_yaw)))
		if yaw_rate == 0.0:
			step_units = MkConst.CAMERA_YAW_STEP_SPIN if _kart.is_spinning_in_place() else MkConst.CAMERA_YAW_STEP_STRAIGHT
		elif behind >= MkConst.CAMERA_YAW_FAR_DEGREES:
			step_units = MkConst.CAMERA_YAW_STEP_FAR + yaw_rate
		else:
			step_units = MkConst.CAMERA_YAW_STEP_TURN + yaw_rate * 0.5
	var step: float = MkConst.angle_units_to_radians(step_units) * frames
	var target_yaw: float = _kart_yaw() + _drift_lead
	cam_yaw += clampf(angle_difference(cam_yaw, target_yaw), -step, step)


## Where the camera wants to be: behind and above the kart along its own yaw.
func _target_position() -> Vector3:
	return _kart.global_position + Basis(Vector3.UP, cam_yaw) * (Vector3(0.0, MkConst.CAMERA_ABOVE, -MkConst.CAMERA_BEHIND) * MkConst.UNIT)


## Where it wants to look: a point ahead of the kart along its own yaw.
func _target_look() -> Vector3:
	return _kart.global_position + Basis(Vector3.UP, cam_yaw) * (Vector3(0.0, 0.0, MkConst.CAMERA_LOOK_AHEAD) * MkConst.UNIT)
