class_name Focus
extends Node
## Acquires, cycles, and releases the lock-on focus target while the focus action is held.
##
## Candidates are bodies in the "Focusable" group overlapping [member target_detection]; a target
## that leaves the area is dropped after [member target_loss_timer] elapses. Firearms use free aim
## instead, so lock-on is disabled while one is equipped.

@export var player: Player
@export var target_detection: Area3D ## Area whose overlapping "Focusable" bodies can be locked on to.
@export var focus_target_marker: Marker3D ## Indicator moved above the focused body.
@export var target_loss_timer: Timer ## Grace period after the target leaves [member target_detection].

var current_focus_target: Node3D = null ## The body currently locked on to, if any.


func _ready() -> void:
	set_process_input(is_multiplayer_authority())
	set_physics_process(is_multiplayer_authority())


func _input(event: InputEvent) -> void:
	if player == null or player.is_paused or player.is_typing or player.is_ragdolling:
		return
	# Tapping focus while already locked on cycles to the next target.
	if event.is_action_pressed("focus") and not event.is_echo() and is_instance_valid(current_focus_target):
		cycle_focus_target(1)


func _physics_process(_delta: float) -> void:
	if player == null:
		return
	if not player.is_focusing:
		if current_focus_target:
			_clear_focus_target()
	elif not is_instance_valid(current_focus_target):
		_acquire_focus_target()
	else:
		focus_target_marker.global_position = get_focus_target_position(current_focus_target) + Vector3(0, 0.4, 0)


## Lock-on is unavailable while a firearm is equipped (free aim instead).
func _on_equipment_changed() -> void:
	set_physics_process(is_multiplayer_authority() and not player.has_firearm_equipped)
	if player.has_firearm_equipped:
		_clear_focus_target()


func _on_target_detection_body_entered(body: Node3D) -> void:
	if body == current_focus_target:
		target_loss_timer.stop()


func _on_target_detection_body_exited(body: Node3D) -> void:
	# Also fires while the scene is being torn down, when the timer can no longer start.
	if body == current_focus_target and target_loss_timer.is_inside_tree():
		target_loss_timer.start()


## Returns the "Marker3D_FocusTarget" descendant of the body, if any.
static func get_focus_target_node(body: Node3D) -> Node3D:
	if not is_instance_valid(body):
		return null
	return body.find_child("Marker3D_FocusTarget", true, false) as Node3D


## Returns the global 3D position to focus on for the given body.
static func get_focus_target_position(body: Node3D) -> Vector3:
	if not is_instance_valid(body):
		return Vector3.ZERO
	var marker: Node3D = get_focus_target_node(body)
	if marker:
		return marker.global_position
	var col: CollisionShape3D = body.find_child("CollisionShape3D", true, false) as CollisionShape3D
	return col.global_position if col else body.global_position


## Returns the focusable bodies in range sorted by horizontal angular proximity to camera center.
func get_focusable_targets() -> Array[Node3D]:
	var candidates: Array[Node3D] = []
	for body: Node3D in target_detection.get_overlapping_bodies():
		if body != player and body.is_in_group("Focusable"):
			candidates.append(body)

	var cam_forward: Vector3 = -player.spring_arm.global_transform.basis.z.slide(player.up_direction).normalized()
	candidates.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		var dir_a: Vector3 = (a.global_position - player.global_position).slide(player.up_direction).normalized()
		var dir_b: Vector3 = (b.global_position - player.global_position).slide(player.up_direction).normalized()
		return cam_forward.dot(dir_a) > cam_forward.dot(dir_b)
	)
	return candidates


## Locks on to the best focusable body.
func _acquire_focus_target() -> void:
	var targets: Array[Node3D] = get_focusable_targets()
	if not targets.is_empty():
		_set_focus_target(targets[0])


## Cycles to the next or previous focusable target.
func cycle_focus_target(direction: int = 1) -> void:
	var targets: Array[Node3D] = get_focusable_targets()
	if targets.is_empty():
		_clear_focus_target()
		return
	var current_idx: int = targets.find(current_focus_target)
	var next_idx: int = posmod(current_idx + direction, targets.size()) if current_idx >= 0 else 0
	_set_focus_target(targets[next_idx])


## Sets the current focus target and moves the bouncing indicator marker onto it.
func _set_focus_target(target: Node3D) -> void:
	current_focus_target = target
	target_loss_timer.stop()
	focus_target_marker.global_position = get_focus_target_position(target) + Vector3(0, 0.4, 0)
	focus_target_marker.show()


## Releases the current target and hides its marker (also wired to the loss timer's timeout).
func _clear_focus_target() -> void:
	current_focus_target = null
	target_loss_timer.stop()
	focus_target_marker.hide()
