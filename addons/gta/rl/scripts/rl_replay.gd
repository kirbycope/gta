class_name RlReplay
extends Node
## The goal replay: the last few seconds of the match, played back from behind
## the goal that was just scored in.
##
## It is a ring buffer rather than a file. Every physics frame the position and
## rotation of every car and the ball are written into a fixed number of slots,
## the oldest being overwritten, so the memory cost is flat however long the
## match runs. A goal rewinds to the start of the buffer and plays forward.
##
## Nothing is simulated during playback. The bodies are taken out of the physics
## world and their transforms are set straight from the buffer, which is what
## makes a replay show what actually happened rather than a re-simulation that
## drifts. They go back exactly as they were afterwards, though in practice the
## match resets them to a kickoff the moment the replay ends.
##
## Rocket League also saves a whole match to a file that can be scrubbed. This
## does not: it is the replay that plays during a match, not the replay theatre.

signal finished() ## The playback reached the end; the match takes a kickoff from here.

const SECONDS: float = 6.0 ## How much of the past is kept.
const TICK: float = 1.0 / 60.0
const FRAMES: int = int(SECONDS / TICK)
const PLAYBACK_SPEED: float = 0.65 ## Rocket League slows its goal replays down a little.

var is_playing: bool = false

var _bodies: Array[Node3D] = [] ## What is being recorded, fixed for the life of the match.
var _frames: Array = [] ## FRAMES slots, each an Array[Transform3D] matching _bodies.
var _write: int = 0 ## Next slot to write, wrapping.
var _filled: int = 0 ## How many slots hold real data, up to FRAMES.
var _play_head: float = 0.0 ## Position in the buffer during playback, in frames.
var _play_length: int = 0


## Start recording a fixed cast. Anything not passed here is not in the replay,
## which is why the match hands over every car and the ball at once.
func track(bodies: Array[Node3D]) -> void:
	_bodies = bodies
	_frames.resize(FRAMES)
	for i: int in FRAMES:
		var slot: Array[Transform3D] = []
		slot.resize(_bodies.size())
		_frames[i] = slot
	_write = 0
	_filled = 0


## One frame into the buffer. Called from the match's own physics step so the
## recording lines up with the simulation exactly.
func record() -> void:
	if is_playing or _bodies.is_empty():
		return
	var slot: Array[Transform3D] = _frames[_write]
	for i: int in _bodies.size():
		var body: Node3D = _bodies[i]
		slot[i] = body.global_transform if is_instance_valid(body) else Transform3D()
	_write = (_write + 1) % FRAMES
	_filled = mini(_filled + 1, FRAMES)


## Play back the last [param seconds], or everything held if that is less.
## Returns false when there is nothing recorded yet, so a goal in the first
## frames of a match goes straight to the kickoff instead of hanging.
func play(seconds: float = SECONDS) -> bool:
	if _filled <= 1 or _bodies.is_empty():
		return false
	_play_length = mini(int(seconds / TICK), _filled)
	_play_head = 0.0
	is_playing = true
	for body: Node3D in _bodies:
		if is_instance_valid(body):
			body.process_mode = Node.PROCESS_MODE_DISABLED
			var physical: RigidBody3D = body as RigidBody3D
			if physical != null:
				physical.freeze = true
	return true


## Stop early and hand the bodies back to the physics world.
func stop() -> void:
	if not is_playing:
		return
	is_playing = false
	for body: Node3D in _bodies:
		if is_instance_valid(body):
			body.process_mode = Node.PROCESS_MODE_INHERIT
			var physical: RigidBody3D = body as RigidBody3D
			if physical != null:
				physical.freeze = false


func _physics_process(delta: float) -> void:
	if not is_playing:
		return
	_play_head += (delta / TICK) * PLAYBACK_SPEED
	if _play_head >= float(_play_length):
		stop()
		finished.emit()
		return
	_apply(int(_play_head))


## Put every body where it was at [param offset] frames into the window. The
## buffer is a ring, so the oldest kept frame is walked back from the write
## head rather than sitting at index zero.
func _apply(offset: int) -> void:
	var start: int = (_write - _play_length + FRAMES) % FRAMES
	var slot: Array[Transform3D] = _frames[(start + offset) % FRAMES]
	for i: int in _bodies.size():
		var body: Node3D = _bodies[i]
		if is_instance_valid(body) and i < slot.size():
			body.global_transform = slot[i]
