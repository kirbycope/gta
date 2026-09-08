extends Camera3D
class_name Camera

signal looking_at_changed(previous: Node3D, current: Node3D) ## Emitted when the interactable under the camera ray changes (either may be null).

enum Perspective {
	FIRST_PERSON, ## Rendered from the viewpoint of the player character
	THIRD_PERSON, ## Rendered from a fixed distance behind and slightly above the player character.
}

const FOCUS_AIM_WORLD_RADIUS: float = 0.5 ## World-space radius in units/meters that the aim can deviate from the target center.

@export var camera_mount: Node3D
@export var camera_spring_arm: SpringArm3D
@export var first_person_offset: Vector3 = Vector3(0.0, 0.0, -0.3) ## The offset of the camera from the player's head when in first-person perspective.
@export var first_person_item_spring_length: float = 0.7 ## Held-item spring length in first-person.
@export var held_pitch_min: float = -0.35 ## Radians: in third person the item arm never dips below this when the camera looks down, so a held object stays out of the ground and the Player's legs.
@export var held_pitch_max: float = 0.6 ## Radians: and never rises above this when the camera looks up.
@export var third_person_item_spring_length: float = 2.0 ## Held-item spring length in third-person.
@export var interaction_distance: float = 3.0 ## The maximum distance the player can reach to interact with objects.
@export var joypad_sensitivity: float = 100.0
@export var held_joypad_look_multiplier: float = 0.45
@export var mouse_sensitivity: float = 0.1
@export var default_fov: float = 75.0 ## Base third-person FOV.
@export var aim_fov: float = 58.0 ## Narrowed FOV when aiming/shooting (over-the-shoulder).
@export var default_h_offset: float = 0.0 ## Base horizontal offset.
@export var aim_h_offset: float = 0.25 ## Over-the-right-shoulder offset when aiming/shooting.
@export var perspective: Perspective = Perspective.THIRD_PERSON ## What perspective should the Camera use?
@export var player: Player

var focus_aim_offset: Vector2 = Vector2.ZERO ## Current aim offset applied on top of the focused lock-on target.
var is_temporarily_captured: bool = false ## Cursor captured only while right-click rotating; released back to visible.
var looking_at: Node3D = null: ## The nearest ancestor of the camera ray's collider that has a `display_menu` method, if any.
	set(value):
		if value == looking_at:
			return
		var previous: Node3D = looking_at
		looking_at = value
		looking_at_changed.emit(previous, value)

@onready var camera_initial_transform: Transform3D = transform
@onready var camera_ray_cast: RayCast3D = $CameraRayCast
@onready var camera_follow_timer: Timer = $CameraFollowTimer ## Running while the camera holds its manual rotation instead of following the player.
@onready var first_person_bone_attachment: BoneAttachment3D = %FirstPersonCameraBoneAttachment
@onready var item_spring_arm: SpringArm3D = %ItemSpringArm
@onready var item_spring_arm_initial_transform: Transform3D = item_spring_arm.transform


## Returns the maximum angular aim offset (in radians) based on distance to target.
## Uses atan2(FOCUS_AIM_WORLD_RADIUS, distance) so the angular window shrinks with distance.
func get_max_focus_aim_angle() -> float:
	var dist: float = 5.0
	if player:
		if is_instance_valid(player.current_focus_target):
			var target_pos: Vector3 = Focus.get_focus_target_position(player.current_focus_target)
			dist = maxf(camera_mount.global_position.distance_to(target_pos), 1.0)
		elif player.focus and player.focus.target_detection:
			var col: CollisionShape3D = player.focus.target_detection.get_node_or_null("CollisionShape3D") as CollisionShape3D
			if col and col.shape is SphereShape3D:
				dist = (col.shape as SphereShape3D).radius
	return atan2(FOCUS_AIM_WORLD_RADIUS, dist)


## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	set_process(is_multiplayer_authority())
	set_physics_process(is_multiplayer_authority())
	set_process_unhandled_input(is_multiplayer_authority())

	looking_at_changed.connect(_on_looking_at_changed)

	# Ensure the [RayCast3D] doesn't collide with the player
	camera_ray_cast.add_exception(player)

	# Water is looked through, never at: the ray has to reach the boat and the props floating in it
	for water: Node in get_tree().get_nodes_in_group(&"WATER"):
		if water is CollisionObject3D:
			camera_ray_cast.add_exception(water)

	# Ensure the Camera's [SpringArm3D] doesn't collide with the player
	camera_spring_arm.add_excluded_object(player.get_rid())
	# The item arm shortens against walls and the ground, never against the Player carrying the item
	item_spring_arm.add_excluded_object(player.get_rid())

	_update_raycast()


## Shows the interaction prompt of the object now under the camera ray and hides the previous one.
func _on_looking_at_changed(previous: Node3D, current: Node3D) -> void:
	if is_instance_valid(previous) and previous.has_method("hide_menu"):
		previous.hide_menu()
	if is_instance_valid(current):
		current.display_menu(player)


## Called when an input event has not been consumed by the UI.
func _unhandled_input(event: InputEvent) -> void:
	# Do nothing if the player is not set or is paused/ragdolling
	if not player or player.is_paused or player.is_typing or player.is_ragdolling: return

	# Look-at interactables that take "action" (the skateboard, the push button); Equipment pickups are walk-over areas instead
	if looking_at and event.is_action_pressed("action") and looking_at.has_method("equip"):
		looking_at.equip(player)
		looking_at = null

	# Perspective { Microsoft: ⧉, Nintendo: ⊝, Sony: ⦀, Keyboard: [F5] }
	if event.is_action_pressed("perspective"):
		if perspective == Perspective.FIRST_PERSON:
			perspective = Perspective.THIRD_PERSON
			transform = camera_initial_transform
		else:
			perspective = Perspective.FIRST_PERSON
		_update_raycast()

	# With a visible cursor, holding right-click temporarily captures the mouse so rotation feels normal.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if player.held_object and player.held_object.is_holding_object():
			return
		if event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			is_temporarily_captured = true
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif not event.pressed and is_temporarily_captured:
			is_temporarily_captured = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Rotate the [Camera3D]'s [SpringArm3D] using the mouse motion input event
	if event is InputEventMouseMotion \
	and (DisplayServer.get_name() == "headless" or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED) \
	and not (player.is_riding and not current) \
	and not is_radial_menu_open():
		if player.is_focusing and not player.has_firearm_equipped:
			if player.is_shooting:
				var mouse_motion_input: Vector2 = event.relative
				focus_aim_offset.x += deg_to_rad(-mouse_motion_input.x * mouse_sensitivity)
				focus_aim_offset.y += deg_to_rad(-mouse_motion_input.y * mouse_sensitivity)
				focus_aim_offset = focus_aim_offset.limit_length(get_max_focus_aim_angle())
		else:
			rotate_camera_using_mouse_motion(event)

	# Only continue if the perspective is third-person
	if perspective == Perspective.THIRD_PERSON:
		# If Mouse scroll wheel up
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			# Shorten the camera spring arm, min 1.0
			camera_spring_arm.spring_length = maxf(camera_spring_arm.spring_length - 0.1, 1.0)
			# TODO: If the player tries to zoom in further, switch to first-person perspective instead?
			_update_raycast()

		# If Mouse scroll wheel down
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# Lengthen the camera spring arm, max 6.0
			camera_spring_arm.spring_length = minf(camera_spring_arm.spring_length + 0.1, 6.0)
			_update_raycast()


## Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if not player: return

	# Rotate the [Camera3D]'s [SpringArm3D] using the joypad motion input event
	var joypad_motion_input: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if joypad_motion_input != Vector2.ZERO \
	and not player.is_paused \
	and not player.is_typing \
	and not player.is_ragdolling \
	and not (player.is_riding and not current) \
	and not is_radial_menu_open():
		if player.is_focusing and not player.has_firearm_equipped:
			if player.is_shooting:
				focus_aim_offset.x += deg_to_rad(-joypad_motion_input.x * joypad_sensitivity * delta)
				focus_aim_offset.y -= deg_to_rad(joypad_motion_input.y * joypad_sensitivity * delta)
				focus_aim_offset = focus_aim_offset.limit_length(get_max_focus_aim_angle())
		else:
			# Rotate the camera based on the joypad motion input event
			var look_multiplier: float = 1.0
			if player.held_object and player.held_object.is_holding_object():
				look_multiplier = held_joypad_look_multiplier
			rotate_camera_using_joypad_motion(delta * look_multiplier)

	# Only continue if the perspective is third-person
	if perspective != Perspective.THIRD_PERSON: return

	# Smoothly interpolate FOV and shoulder offset when aiming/shooting (BotW/TotK over-the-shoulder framing)
	var is_aiming_now: bool = player.is_focusing if player.has_firearm_equipped \
			else player.is_shooting or player.is_drawing_arrow or player.is_aiming_bow
	fov = lerpf(fov, aim_fov if is_aiming_now else default_fov, delta * 10.0)
	h_offset = lerpf(h_offset, aim_h_offset if is_aiming_now else default_h_offset, delta * 10.0)

	# Lerp camera to face the player's direction when focusing, driving, or skateboarding (and the follow delay has expired).
	if player.is_focusing and not player.has_firearm_equipped:
		var max_angle: float = get_max_focus_aim_angle()
		focus_aim_offset = focus_aim_offset.limit_length(max_angle)
		if not player.is_shooting:
			focus_aim_offset = focus_aim_offset.move_toward(Vector2.ZERO, delta * 4.0)

		if is_instance_valid(player.current_focus_target):
			var target_pos: Vector3 = Focus.get_focus_target_position(player.current_focus_target)
			# CameraMount is a child of the Player body, so its rotation is local: put the target direction in the body frame first
			var to_target: Vector3 = player.global_basis.inverse() * (target_pos - camera_mount.global_position)
			var target_yaw: float = atan2(-to_target.x, -to_target.z) + focus_aim_offset.x
			var horiz_dist: float = Vector2(to_target.x, to_target.z).length()
			var target_pitch: float = clampf(atan2(to_target.y, horiz_dist) + focus_aim_offset.y, deg_to_rad(-80.0), deg_to_rad(80.0))
			camera_mount.rotation.y = lerp_angle(camera_mount.rotation.y, target_yaw, delta * 8.0)
			camera_mount.rotation.x = lerp_angle(camera_mount.rotation.x, target_pitch, delta * 8.0)
		else:
			camera_mount.rotation.y = lerp_angle(camera_mount.rotation.y, player.player_model.rotation.y + PI + focus_aim_offset.x, delta * 8.0)
			camera_mount.rotation.x = lerp_angle(camera_mount.rotation.x, deg_to_rad(-15.0) + focus_aim_offset.y, delta * 8.0)
	else:
		focus_aim_offset = Vector2.ZERO


## Called every physics frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(_delta: float) -> void:
	if not player: return

	# Move camera to player's head if in first-person perspective
	if perspective == Perspective.FIRST_PERSON:
		move_camera_to_player_head()

	_sync_item_spring_arm()

	# Keep the projectile ray on the camera's centre line (shoulder offset, first-person head), so the crosshair is where rounds go
	var centre: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var normal: Vector3 = project_ray_normal(centre)
	player.projectile_raycast.global_transform = Transform3D(Basis.looking_at(normal, global_basis.y),
			project_ray_origin(centre) + normal * global_position.distance_to(camera_mount.global_position))

	# Resolve the nearest ancestor of the ray's collider that can display an interaction prompt
	var target: Node = camera_ray_cast.get_collider() as Node if camera_ray_cast.is_colliding() else null
	while target and not target.has_method("display_menu"):
		target = target.get_parent()
	looking_at = target as Node3D


## Rotates the [Camera3D]'s [SpringArm3D] using the input from a joypad motion event, while clamping the vertical rotation to prevent flipping.
func rotate_camera_using_joypad_motion(delta: float) -> void:
	# Get the input from the joypad motion event
	var joypad_motion_input: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	# Rotate the [Camera3D]'s [CameraMount] horizontally using the joypad motion input's x value
	if joypad_motion_input.x != 0:
		camera_mount.rotate_y(deg_to_rad(-joypad_motion_input.x * joypad_sensitivity * delta))
	# Rotate the [Camera3D]'s [CameraMount] vertically using the joypad motion input's y value
	if joypad_motion_input.y != 0:
		var new_rotation_x: float = camera_mount.rotation_degrees.x - joypad_motion_input.y * joypad_sensitivity * delta
		# Clamp the rotation to prevent flipping
		camera_mount.rotation_degrees.x = clampf(new_rotation_x, -89.0, 89.0)


## Rotates the [Camera3D]'s [SpringArm3D] using the input from a mouse motion event, while clamping the vertical rotation to prevent flipping.
func rotate_camera_using_mouse_motion(event: InputEventMouseMotion) -> void:
	# Get the input from the mouse motion event
	var mouse_motion_input: Vector2 = event.relative
	# Rotate the [Camera3D]'s [CameraMount] horizontally using the mouse motion input's x value
	camera_mount.rotate_y(deg_to_rad(-mouse_motion_input.x * mouse_sensitivity))
	# Rotate the [Camera3D]'s [CameraMount] vertically using the mouse motion input's y value
	var new_rotation_x: float = camera_mount.rotation_degrees.x - mouse_motion_input.y * mouse_sensitivity
	# Clamp the rotation to prevent flipping
	camera_mount.rotation_degrees.x = clampf(new_rotation_x, -89.0, 89.0)


## Update the camera to follow the character head's position (while in "first-person").
func move_camera_to_player_head() -> void:
	global_position = first_person_bone_attachment.global_position
	global_rotation = camera_mount.global_rotation
	global_position += global_transform.basis.z * first_person_offset.z
	global_position += global_transform.basis.y * first_person_offset.y
	global_position += global_transform.basis.x * first_person_offset.x


## Keeps the held-item spring arm aligned with perspective/camera behavior.
func _sync_item_spring_arm() -> void:
	if not is_instance_valid(item_spring_arm):
		return

	if perspective == Perspective.FIRST_PERSON:
		# Preserve arm's authored local orientation (typically 180deg yaw)
		# so SpringArm extension remains in front of the first-person camera.
		item_spring_arm.global_basis = global_basis * item_spring_arm_initial_transform.basis
		item_spring_arm.global_position = global_position
		item_spring_arm.spring_length = player.held_object.get_held_distance(
			first_person_item_spring_length
		) if player.held_object else first_person_item_spring_length
	else:
		# Third person: the camera's yaw, but only so much of its pitch, so looking down never puts the object in the
		# ground or inside the Player, where releasing it would shove it out or leave it stuck
		var up: Vector3 = player.up_direction
		var forward: Vector3 = -camera_mount.global_basis.z
		var flat: Vector3 = forward.slide(up)
		if flat.length_squared() < 0.0001:
			flat = (-player.global_basis.z).slide(up)
		flat = flat.normalized()
		var pitch: float = clampf(asin(clampf(forward.dot(up), -1.0, 1.0)), held_pitch_min, held_pitch_max)
		var direction: Vector3 = (flat * cos(pitch) + up * sin(pitch)).normalized()
		item_spring_arm.global_transform = Transform3D(Basis.looking_at(direction, up) * item_spring_arm_initial_transform.basis,
				camera_mount.global_position + camera_mount.global_basis * item_spring_arm_initial_transform.origin)
		if player.held_object:
			item_spring_arm.spring_length = player.held_object.get_held_distance(item_spring_arm.spring_length)
		item_spring_arm.spring_length = player.held_object.get_held_distance(
			third_person_item_spring_length
		) if player.held_object else third_person_item_spring_length


## Updates the [RayCast3D] position and target_position based on current perspective/depth.
func _update_raycast() -> void:
	if perspective == Perspective.FIRST_PERSON:
		camera_ray_cast.position = Vector3.ZERO
		camera_ray_cast.target_position = Vector3(0, 0, -interaction_distance)
	else:
		camera_ray_cast.position = Vector3(0, 0, -1.0)
		var length: float = camera_spring_arm.spring_length if is_instance_valid(camera_spring_arm) else 2.0
		camera_ray_cast.target_position = Vector3(0, 0, - (length + interaction_distance - 1.0))


## Returns whether the RadialMenu is currently open/visible.
func is_radial_menu_open() -> bool:
	if player and is_instance_valid(player.radial_menu):
		return player.radial_menu.is_open() or player.abilities.radial_menu.is_open()
	return false
