extends GutTest

const PLAYER_SCENE = preload("res://addons/3d_player_controller/scenes/player.tscn")


func test_player_synchronizer_node_exists() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)

	assert_not_null(player.player_synchronizer, "Player should have PlayerSynchronizer node")
	assert_true(player.player_synchronizer is MultiplayerSynchronizer, "PlayerSynchronizer should be a MultiplayerSynchronizer")
	assert_not_null(player.player_synchronizer.replication_config, "PlayerSynchronizer should have a SceneReplicationConfig")


func test_player_synchronizer_properties_tracked() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)

	var config: SceneReplicationConfig = player.player_synchronizer.replication_config
	assert_not_null(config, "Replication config must not be null")

	var tracked_properties: Array[NodePath] = config.get_properties()
	assert_true(tracked_properties.has(NodePath(".:position")), "Should track player position")
	assert_true(tracked_properties.has(NodePath(".:rotation")), "Should track player rotation")
	assert_true(tracked_properties.has(NodePath("PlayerModel:position")), "Should track PlayerModel position")
	assert_true(tracked_properties.has(NodePath("PlayerModel:rotation")), "Should track PlayerModel rotation")
	assert_true(tracked_properties.has(NodePath(".:sync_locomotion_node")), "Should track sync_locomotion_node")
	assert_true(tracked_properties.has(NodePath(".:sync_blend_position")), "Should track sync_blend_position")
	assert_true(tracked_properties.has(NodePath(".:current_state")), "Should track current_state")


func test_animation_sync_properties_update() -> void:
	var player: Player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(player)

	# Test blend position update
	player.sync_blend_position = Vector2(0.5, 0.8)
	assert_eq(player.sync_blend_position, Vector2(0.5, 0.8), "sync_blend_position should store blend coordinates")

	# Test locomotion node name update
	player.sync_locomotion_node = "StandingLocomotion"
	assert_eq(player.sync_locomotion_node, "StandingLocomotion", "sync_locomotion_node should store state name")


func _make_puppet() -> Player:
	var puppet: Player = PLAYER_SCENE.instantiate() as Player
	puppet.set_multiplayer_authority(2)
	add_child_autofree(puppet)
	return puppet


func test_puppet_applies_grouped_locomotion_path() -> void:
	var puppet: Player = _make_puppet()
	puppet.sync_locomotion_node = "Bow/BowLocomotion"
	await wait_physics_frames(5)
	assert_eq(String(puppet.locomotion_state.get_current_node()), "Bow", "Root machine should enter the Bow group")
	assert_eq(puppet.current_locomotion_node, "BowLocomotion", "Inner machine should reach the synced node")


func test_puppet_applies_root_locomotion_node_without_bow_group() -> void:
	var puppet: Player = _make_puppet()
	puppet.sync_locomotion_node = "CrouchingLocomotion"
	await wait_physics_frames(5)
	assert_eq(String(puppet.locomotion_state.get_current_node()), "CrouchingLocomotion", "Root-level nodes must not be routed through the Bow group")


func test_puppet_blend_position_targets_synced_node() -> void:
	var puppet: Player = _make_puppet()
	puppet.sync_locomotion_node = "CrouchingLocomotion"
	puppet.sync_blend_position = Vector2(0.0, 0.7)
	assert_eq(puppet.animation_tree.get(Player.CROUCHING_LOCOMOTION_BLEND_POSITION_PATH), Vector2(0.0, 0.7))
