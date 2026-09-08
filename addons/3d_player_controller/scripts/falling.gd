class_name Falling
extends NodeStateMachine


## Called when there is an input event.
func _input(event: InputEvent) -> void:

	# Do nothing if the player is not set
	if not player or player.is_paused or player.is_typing or player.is_ragdolling: return

	# Jump action triggers while falling
	if event.is_action_pressed("jump"):
		if player.ledge_detection_horizontal.is_colliding():
			# Exhausted players cannot grab the wall
			if not player.is_exhausted:
				player.state_machine.travel(state, States.CLIMBING)
				get_viewport().set_input_as_handled()
			return
		elif (not player.paraglider_raycast.is_colliding() or player.is_in_updraft()) and not player.is_exhausted:
			player.state_machine.travel(state, States.PARAGLIDING)
			get_viewport().set_input_as_handled()
			return
		elif player.paraglider_raycast.is_colliding():
			player.state_machine.travel(state, States.FLYING)
			get_viewport().set_input_as_handled()
			return


## Called every physics frame.
func _physics_process(_delta: float) -> void:

	# Do nothing if the player is not set
	if not player: return

	# Check if the player has reached the floor
	if player.is_on_floor():
		if player.last_fall_speed >= player.lethal_fall_speed:
			# Start "ragdolling" if falling at a lethal velocity
			player.state_machine.travel(state, States.RAGDOLLING)
		else:
			# Start "standing"
			player.state_machine.travel(state, States.STANDING)


## Start "falling".
func start() -> void:
	super.start()
	# Flag the player as "falling"
	player.is_falling = true


## Stop "falling".
func stop() -> void:
	super.stop()
	# Flag the player as not "falling"
	player.is_falling = false
