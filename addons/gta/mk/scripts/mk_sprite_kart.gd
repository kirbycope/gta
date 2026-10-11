class_name MkSpriteKart
extends Sprite3D
## A kart drawn the way Mario Kart 64 draws its karts: a billboard of
## pre-rendered frames picked by where the camera is.
##
## The game has no kart models. Each character's kart was rendered once from a
## half ring of angles in nine pitch poses, and the game draws the frame whose
## angle is nearest to the camera's view of the kart, mirroring it for the half
## of the ring it did not store. This node is that rule, from
## [code]func_8002934C[/code] in the decompilation's
## [code]src/player_controller.c[/code], with whatever frames it is given:
## [code]tools/extract_mk64.py[/code] writes a drop-in kart scene (see
## [MkAssets]) that is one of these with the ROM's own frames in its arrays.
## The frames are the game's data and live in the git-ignored assets folder;
## this script is only the rule for showing them.
##
## [b]The pose is pitch, not steering.[/b] The game's nine frame sets are the
## kart tilted nose up or nose down by the slope under it
## ([code]func_80029200[/code]); there is no wheels-turned set. Steering and the
## drift show as the slide angle added to the view angle, so a drifting kart is
## drawn turned further than it is travelling, which is what the game does.
##
## [b]The ring.[/b] Frames 0 to 19 are 2.856 degrees apart, out to 56.95 degrees
## from behind; frames 21 to 34 are 8.998 degrees apart, out to head on; frame
## 20 is never chosen. Past 180.7 degrees the frame for the other side is drawn
## mirrored. A spin out uses a separate ring of twenty frames nine degrees
## apart. All of it is the game's own integer arithmetic in degrees.
##
## It sits under an [MkCar] as the dropped-in model, reads the kart's facing,
## slide, slope and spin from it, and stands on the kart's origin. With no
## frames it draws nothing and says so once.

## The game's nine pitch poses, nose up to nose down, each a half ring of
## thirty five frames in angle order. A pose left empty falls back to
## [member level].
@export var nose_up_10: Array[Texture2D] = []
@export var nose_up_7: Array[Texture2D] = []
@export var nose_up_3: Array[Texture2D] = []
@export var nose_up_2: Array[Texture2D] = []
@export var level: Array[Texture2D] = []
@export var nose_down_2: Array[Texture2D] = []
@export var nose_down_3: Array[Texture2D] = []
@export var nose_down_7: Array[Texture2D] = []
@export var nose_down_10: Array[Texture2D] = []
## The spin out ring: twenty frames nine degrees apart.
@export var spin_ring: Array[Texture2D] = []

## The pitch bands of [code]func_80029200[/code], in degrees of slope with
## nose down positive, each the lower edge of a pose from nose_up_7 on.
const PITCH_BANDS: PackedFloat32Array = [-10.0, -7.0, -3.0, -2.0, 2.0, 3.0, 7.0, 10.0]
const MIRROR_ABOVE_DEGREES: float = 180.703 ## 0x101 * 128 in 65536ths of a turn.
const FINE_STEP_DEGREES: float = 2.856 ## 0x208 in 65536ths.
const FINE_UNTIL_DEGREES: float = 56.953 ## 0x51 * 128 in 65536ths.
const COARSE_STEP_DEGREES: float = 8.998 ## DEGREES(9), 1638 in 65536ths.
const COARSE_OFFSET: int = 15
const LAST_FRAME: int = 34
const RING_FRAMES: int = 20

var _said_empty: bool = false


func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	centered = true
	if not level.is_empty() and level[0] != null:
		# stand on the kart's origin, which the kart keeps on the ground
		position.y = level[0].get_height() * pixel_size * 0.5


func _process(_delta: float) -> void:
	var kart: MkCar = get_parent() as MkCar
	var spinning: bool = kart != null and kart.spin_seconds > 0.0 and not spin_ring.is_empty()
	var frames: Array[Texture2D] = spin_ring if spinning else _frames_for_pitch(kart.pitch_degrees() if kart != null else 0.0)
	if frames.is_empty():
		if not _said_empty:
			_said_empty = true
			push_warning("%s has no frames to draw" % name)
		return
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var choice: Dictionary = frame_for_angle(view_angle_degrees(camera), spinning)
	var index: int = mini(int(choice["index"]), frames.size() - 1)
	texture = frames[index]
	flip_h = bool(choice["flipped"])


## The pose for a slope of [param pitch] degrees, nose down positive: the
## game's nine bands, with an empty pose standing in as level.
func _frames_for_pitch(pitch: float) -> Array[Texture2D]:
	var poses: Array = [nose_up_10, nose_up_7, nose_up_3, nose_up_2, level, nose_down_2, nose_down_3, nose_down_7, nose_down_10]
	var band: int = 0
	for edge: float in PITCH_BANDS:
		if pitch >= edge:
			band += 1
	var frames: Array[Texture2D] = poses[band]
	return frames if not frames.is_empty() else level


## The angle the camera sees the kart from, in degrees: 0 with the camera
## straight behind, 90 with the camera off the kart's left side, 180 head on,
## 270 off its right; plus the kart's slide, which the game adds so a drifting
## kart is drawn turned further than it is travelling. Without a camera it is
## 0, the frame the kart is most often seen from.
func view_angle_degrees(camera: Camera3D) -> float:
	var kart: MkCar = get_parent() as MkCar
	var slide: float = rad_to_deg(kart.turn_angle) if kart != null else 0.0
	if camera == null:
		return fposmod(slide, 360.0)
	var forward: Vector3 = kart.forward() if kart != null else global_transform.basis.z
	var to_camera: Vector3 = camera.global_position - global_position
	to_camera.y = 0.0
	if to_camera.length_squared() < 0.0001:
		return fposmod(slide, 360.0)
	to_camera = to_camera.normalized()
	var behind: Vector3 = -forward
	var left: Vector3 = Vector3.UP.cross(forward)
	var angle: float = rad_to_deg(atan2(to_camera.dot(left), to_camera.dot(behind)))
	return fposmod(angle + slide, 360.0)


## The frame for a view [param angle] in degrees: [code]index[/code] into the
## pose's half ring and [code]flipped[/code] when it is the mirrored side.
## [param spinning] uses the spin out ring's rule instead.
func frame_for_angle(angle: float, spinning: bool = false) -> Dictionary:
	var a: float = fposmod(angle, 360.0)
	var flipped: bool = false
	if a >= MIRROR_ABOVE_DEGREES:
		a = 360.0 - a
		flipped = true
	var index: int
	if spinning:
		index = int(a / COARSE_STEP_DEGREES)
		if index >= RING_FRAMES:
			index = 0
	elif a < FINE_UNTIL_DEGREES:
		index = int(a / FINE_STEP_DEGREES)
	else:
		index = mini(COARSE_OFFSET + int(a / COARSE_STEP_DEGREES), LAST_FRAME)
	return {"index": index, "flipped": flipped}
