class_name Sliding
extends NodeStateMachine


## Stand back up once the RunningSlide animation hands off to another locomotion node.
func _on_locomotion_node_changed(_state_path: String) -> void:
	if process_mode != Node.PROCESS_MODE_INHERIT: return

	if player.current_locomotion_node != "RunningSlide":
		player.state_machine.travel(state, States.STANDING)


## Start "sliding".
func start() -> void:
	super.start()
	# Flag the player as "sliding"
	player.is_sliding = true
	# Reduce the player's collision shape height and adjust its position to match the sliding posture
	player.collision_shape.shape.height = player.initial_collision_shape_height * 0.5
	player.collision_shape.position = Vector3(0, player.collision_shape.shape.height * 0.5, 0)


## Stop "sliding".
func stop() -> void:
	super.stop()
	# Flag the player as not "sliding"
	player.is_sliding = false
	# Reset the player's collision shape to its initial height and position
	player.collision_shape.shape.height = player.initial_collision_shape_height
	player.collision_shape.position = player.initial_collision_shape_position
