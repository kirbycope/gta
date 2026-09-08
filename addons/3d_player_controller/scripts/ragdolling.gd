class_name Ragdolling
extends NodeStateMachine

var _hips_physical_bone: PhysicalBone3D
var _physical_bones: Array[Node] = []


## Called when there is an input event.
func _input(event: InputEvent) -> void:
	# Do nothing if the player is not set or is paused/pause layer visible
	if not player or player.is_paused or player.is_typing or (player.pause and player.pause.visible): return

	# If the player is ragdolling, pressing the "action" button will stop "ragdolling"
	if player.is_ragdolling and event.is_action_pressed("action"):
		player.state_machine.travel(state, States.STANDING)


## Called every physics frame.
func _physics_process(_delta: float) -> void:
	# Sync player global position to the hips physical bone position while ragdolling
	if player and player.is_ragdolling and is_instance_valid(_hips_physical_bone):
		player.global_position = _hips_physical_bone.global_position


## Start "ragdolling".
func start() -> void:
	super.start()
	player.is_ragdolling = true
	# Detach player_model transform hierarchy while ragdolling so setting player.global_position does not shift physical bones
	if player.player_model:
		player.player_model.top_level = true
	# Disable the AnimationTree to prevent animations from continuing and playing audio via method tracks
	if player.animation_tree:
		player.animation_tree.active = false
	if player.physical_bone_simulator:
		_hips_physical_bone = player.physical_bone_simulator.find_child("Physical Bone Hips", true, false) as PhysicalBone3D
		_physical_bones = player.physical_bone_simulator.find_children("*", "PhysicalBone3D", true, false)
		_set_bone_collision(true)
		player.physical_bone_simulator.physical_bones_start_simulation()
	# Disable main collision shape while ragdolling
	if player.collision_shape:
		player.collision_shape.disabled = true


## Stop "ragdolling".
func stop() -> void:
	super.stop()
	player.is_ragdolling = false
	# Sync position one last time to hips bone position before restoring player_model
	if is_instance_valid(_hips_physical_bone):
		player.global_position = _hips_physical_bone.global_position
	# Re-attach player_model transform hierarchy and restore initial transform
	if player.player_model:
		player.player_model.top_level = false
		player.player_model.transform = player.initial_player_model_transform
	if player.animation_tree:
		player.animation_tree.active = true
	if player.physical_bone_simulator:
		player.physical_bone_simulator.physical_bones_stop_simulation()
		_set_bone_collision(false)
	if player.collision_shape:
		player.collision_shape.disabled = false
	_hips_physical_bone = null


## Physical bones only collide on layer/mask 1 while the ragdoll simulates; the scene ships them with both cleared.
func _set_bone_collision(enabled: bool) -> void:
	for bone: Node in _physical_bones:
		if is_instance_valid(bone):
			(bone as PhysicalBone3D).set_collision_layer_value(1, enabled)
			(bone as PhysicalBone3D).set_collision_mask_value(1, enabled)
