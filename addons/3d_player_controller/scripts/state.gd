class_name NodeStateMachine
extends Node

## Node-based finite state machine for [Player]: this script is both the machine node and the base of every state node beneath it.

enum States {
	NONE = -1,
	ATTACKING,
	CLIMBING,
	CROUCHING,
	FALLING,
	FLYING,
	HANGING,
	JUMPING,
	PARAGLIDING,
	PUSHING,
	RAGDOLLING,
	RIDING,
	SITTING,
	SLIDING,
	SPRINTING,
	STANDING,
	SWIMMING,
}

@export var player: Player

## The state this node represents, derived from its node name ("Standing" -> STANDING); NONE on the machine node itself.
@onready var state: States = States.get(String(name).to_upper(), States.NONE)


func _ready() -> void:
	set_process(is_multiplayer_authority())
	set_physics_process(is_multiplayer_authority())
	set_process_input(is_multiplayer_authority())
	if player and is_multiplayer_authority() and not player.locomotion_node_changed.is_connected(_on_locomotion_node_changed):
		player.locomotion_node_changed.connect(_on_locomotion_node_changed)


## Helper function to get the state name from the `NodeStateMachine.States` enum value.
static func get_state_name(state_value: int) -> StringName:
	var state_name: Variant = States.find_key(state_value)
	if state_name == null:
		return &""
	return StringName(String(state_name).capitalize())


## Transition from one state to another.
func travel(from_state: States, to_state: States) -> void:
	if player == null:
		return

	# Optional states must be enabled; RAGDOLLING is also blocked while paused, and nothing but RAGDOLLING changes while ragdolling
	match to_state:
		States.FLYING when not player.enable_flying: return
		States.PARAGLIDING when not player.enable_paraglider: return
		States.RAGDOLLING when not player.enable_ragdoll or player.is_paused or player.is_typing or (player.pause and player.pause.visible): return
	if player.is_ragdolling and to_state != States.RAGDOLLING and from_state != States.RAGDOLLING:
		return

	if from_state != States.NONE:
		var from_node: NodeStateMachine = get_node_or_null(NodePath(get_state_name(from_state))) as NodeStateMachine
		if from_node == null:
			push_error("Invalid from_state: %s" % from_state)
		else:
			if player.controls:
				if player.controls.input_type_changed.is_connected(from_node._on_input_type_changed):
					player.controls.input_type_changed.disconnect(from_node._on_input_type_changed)
				player.controls.reset_labels()
			from_node.stop()

	var to_node: NodeStateMachine = get_node_or_null(NodePath(get_state_name(to_state))) as NodeStateMachine
	if to_node == null:
		push_error("Invalid to_state: %s" % to_state)
		return
	if player.controls:
		if player.held_object and player.held_object.is_holding_object():
			player.held_object.refresh_contextual_controls()
		else:
			if not player.controls.input_type_changed.is_connected(to_node._on_input_type_changed):
				player.controls.input_type_changed.connect(to_node._on_input_type_changed)
			to_node._on_input_type_changed(player.controls.current_input_type)
	to_node.start()


## Enables this state node and makes it the player's current state; states extend it with `super.start()`.
func start() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	player.current_state = state


## Disables this state node and clears the player's current state (if it is still this state); states extend it with `super.stop()`.
func stop() -> void:
	process_mode = Node.PROCESS_MODE_DISABLED
	if player.current_state == state:
		player.current_state = States.NONE


## Resolves an action name for the current input type (keyboard/mouse vs controller/touch).
func action(keyboard: StringName, pad: StringName) -> StringName:
	if player.controls == null or player.controls.current_input_type == Controls.InputType.KEYBOARD_MOUSE:
		return keyboard
	return pad


## Called when the player's locomotion path changes; states override it and early-return unless `process_mode == PROCESS_MODE_INHERIT`.
func _on_locomotion_node_changed(_state_path: String) -> void:
	pass


## True if the player is moving into a wall (or heavy object) they are facing.
func is_player_pushing_into_wall() -> bool:
	if not player.has_move_input or not player.is_on_wall():
		return false
	var facing: Vector3 = player.get_facing_direction()
	if facing == Vector3.ZERO:
		return false
	for i: int in player.get_slide_collision_count():
		var collision: KinematicCollision3D = player.get_slide_collision(i)
		if collision.get_collider() is CharacterBody3D:
			continue
		var normal: Vector3 = collision.get_normal()
		# Skip floor/ceiling contacts
		if absf(normal.dot(player.up_direction)) > 0.3:
			continue
		# get_facing_direction() aligns with the pushed wall's normal (PlayerModel forward is +Z).
		if facing.dot(normal) > 0.8:
			return true
	return false


## Applies this state's contextual control labels (plus the shared Perspective/Screenshot/Pause Menu labels), or the defaults when it has none.
func _on_input_type_changed(input_type: int) -> void:
	if player == null or player.controls == null: return
	# A held object owns the labels while it is held, and a fishing rod while it is equipped
	if player.held_object and player.held_object.is_holding_object(): return
	if player.is_fishing: return

	var controls: Dictionary = get_contextual_controls(input_type)
	if controls.is_empty():
		player.controls.reset_labels()
	else:
		var labels: Dictionary = controls.merged({
			player.controls.joypad_button_4_label: "Perspective",
			player.controls.joypad_button_15_label: "Screenshot",
			player.controls.joypad_button_6_label: "Pause Menu",
		})
		var seeker: String = player.controls.seeker_label_text()
		if seeker != "" and not labels.has(player.controls.joypad_button_11_label) and not labels.has(player.controls.key_i_label):
			labels[player.controls.joypad_button_11_label] = seeker
		player.controls.set_labels(labels)


## State-specific control labels keyed by label node; return {} to keep the default labels.
func get_contextual_controls(_input_type: int) -> Dictionary:
	return {}
